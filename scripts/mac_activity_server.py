#!/usr/bin/env python3
"""Expose a tiny local API with live macOS activity data."""

from __future__ import annotations

import argparse
import json
import re
import socket
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Optional


def run_command(*command: str) -> str:
    result = subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def get_frontmost_app() -> Optional[str]:
    script = """
tell application "System Events"
    set frontApp to first application process whose frontmost is true
    return name of frontApp
end tell
""".strip()

    try:
        output = run_command("osascript", "-e", script)
    except Exception:
        return None

    return output or None


def get_memory() -> dict[str, Any]:
    try:
        total_bytes = int(run_command("sysctl", "-n", "hw.memsize"))
        vm_stat_output = run_command("vm_stat")
    except Exception:
        return {
            "usedGB": None,
            "totalGB": None,
            "pressure": None,
        }

    page_size_match = re.search(r"page size of (\d+) bytes", vm_stat_output)
    if not page_size_match:
        return {
            "usedGB": None,
            "totalGB": round(total_bytes / (1024 ** 3), 1),
            "pressure": None,
        }

    page_size = int(page_size_match.group(1))
    page_keys = [
        "Pages active",
        "Pages wired down",
        "Pages occupied by compressor",
    ]
    used_pages = 0
    for key in page_keys:
        match = re.search(rf"{re.escape(key)}:\s+(\d+)\.", vm_stat_output)
        if match:
            used_pages += int(match.group(1))

    used_bytes = used_pages * page_size
    total_gb = round(total_bytes / (1024 ** 3), 1)
    used_gb = round(used_bytes / (1024 ** 3), 1)
    pressure = round((used_bytes / total_bytes) * 100, 1) if total_bytes else None
    return {
        "usedGB": used_gb,
        "totalGB": total_gb,
        "pressure": pressure,
    }


def get_battery() -> dict[str, Any]:
    try:
        output = run_command("pmset", "-g", "batt")
    except Exception:
        return {
            "percentage": None,
            "charging": None,
            "powerSource": None,
        }

    percentage_match = re.search(r"(\d+)%", output)
    status_match = re.search(r"\d+%;\s*([^;]+);", output)
    source_match = re.search(r"Now drawing from '([^']+)'", output)

    status = status_match.group(1).strip() if status_match else ""
    return {
        "percentage": int(percentage_match.group(1)) if percentage_match else None,
        "charging": "charging" in status.lower() or "ac attached" in status.lower(),
        "powerSource": source_match.group(1) if source_match else None,
    }


def build_payload() -> dict[str, Any]:
    return {
        "host": socket.gethostname(),
        "frontmostApp": get_frontmost_app(),
        "memory": get_memory(),
        "battery": get_battery(),
    }


class ActivityHandler(BaseHTTPRequestHandler):
    server_version = "MacActivityHTTP/1.0"

    def _send_json(self, status_code: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        if self.path in ("/api/activity", "/api/activity/"):
            self._send_json(200, build_payload())
            return

        if self.path in ("/api/health", "/api/health/"):
            self._send_json(200, {"ok": True})
            return

        self._send_json(404, {"error": "Not found"})

    def log_message(self, format: str, *args: Any) -> None:
        return


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Serve local macOS activity as JSON.")
    parser.add_argument("--host", default="127.0.0.1", help="Host to bind to.")
    parser.add_argument("--port", type=int, default=48123, help="Port to bind to.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    server = ThreadingHTTPServer((args.host, args.port), ActivityHandler)
    print(f"mac activity server listening on http://{args.host}:{args.port}/api/activity")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
