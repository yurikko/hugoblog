# Hugo Example

This directory is a brief example of a [Hugo](https://gohugo.io/) app that can be deployed to Vercel with zero configuration.

## Deploy Your Own

Deploy your own Hugo project with Vercel.

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https://github.com/vercel/examples/tree/main/framework-boilerplates/hugo&template=hugo)

_Live Example: https://hugo-template.vercel.app_

### How We Created This Example

To get started with Hugo for deployment with Vercel, you can use the [Hugo CLI](https://gohugo.io/commands/) to initialize the project:

```shell
$ hugo new site project-name
```

## Local Mac Activity Widget

This site now includes a Mac activity widget in the homepage sidebar.

Start the activity API on your Mac:

```shell
python3 scripts/mac_activity_server.py
```

Then run the Hugo site locally:

```shell
hugo server
```

Open the local page over `http://localhost:1313` and the widget will show:

- frontmost app
- custom status text by app name
- memory usage
- battery state

### Notes

- The script only reads the frontmost app name. It does not read window content or document content.
- If you open the deployed HTTPS site directly, browsers will usually block requests to `http://127.0.0.1`, so the widget will show a disconnected hint instead of live data.
- You can change the endpoint, refresh interval, default text, and per-app messages in `/Users/miya/Blogs/hugo.yaml` under `params.macActivity`.

## Public HTTPS Endpoint

If you want the deployed HTTPS blog to read your Mac activity, expose the API through an HTTPS URL and point the widget to that URL.

Start the local API with restricted browser origins and an optional API key:

```shell
python3 scripts/mac_activity_server.py \
  --host 127.0.0.1 \
  --port 48123 \
  --cors-origin https://yurikko.github.io \
  --cors-origin http://localhost:1313 \
  --api-key REPLACE_WITH_A_LONG_RANDOM_TOKEN
```

Then expose `http://127.0.0.1:48123` through an HTTPS tunnel or reverse proxy. One easy option is Cloudflare Tunnel:

```shell
cloudflared tunnel --url http://127.0.0.1:48123
```

After you get a public HTTPS URL such as `https://example.trycloudflare.com`, update `/Users/miya/Blogs/hugo.yaml`:

```yaml
params:
  macActivity:
    endpoint: https://example.trycloudflare.com/api/activity
    requestHeaders:
      Authorization: Bearer REPLACE_WITH_A_LONG_RANDOM_TOKEN
```

Then rebuild and redeploy the Hugo site.

### Security Notes

- `requestHeaders` are shipped to the browser, so a public static site cannot keep this token fully secret.
- This is enough to stop accidental scraping, but not enough for strong security once the page is public.
- If you want stronger protection, place the HTTPS endpoint behind Cloudflare Access, Tailscale Funnel, or your own authenticated reverse proxy instead of relying only on an embedded token.

## Menu Bar App

If you do not want to keep a Terminal window open, there is also a native macOS menu bar app version.

Build the app bundle:

```shell
./scripts/build_mac_activity_menubar_app.sh
```

Then open:

```shell
open "mac-activity-menubar/dist/Mac Activity Menu Bar.app"
```

The menu bar app will:

- stay in the macOS menu bar
- expose the same local API at `http://127.0.0.1:48123/api/activity`
- update the current app, memory, and battery in the background

If you want it to start automatically after login, add the generated app to System Settings -> General -> Login Items.

## launchd Auto Start

To keep both the activity API and Cloudflare Tunnel running after login, this repo now includes launchd templates:

- `/Users/miya/Blogs/launchd/com.miya.mac-activity-server.plist`
- `/Users/miya/Blogs/launchd/com.miya.cloudflared-mac-activity.plist`

First create your local env file:

```shell
cp /Users/miya/Blogs/launchd/mac-activity.env.example /Users/miya/Blogs/launchd/mac-activity.env
```

Then edit `/Users/miya/Blogs/launchd/mac-activity.env` and fill in:

- `MAC_ACTIVITY_API_KEY`
- `MAC_ACTIVITY_CORS_ORIGINS`
- `CLOUDFLARED_TUNNEL_NAME`

Install the agents:

```shell
mkdir -p ~/Library/LaunchAgents
cp /Users/miya/Blogs/launchd/com.miya.mac-activity-server.plist ~/Library/LaunchAgents/
cp /Users/miya/Blogs/launchd/com.miya.cloudflared-mac-activity.plist ~/Library/LaunchAgents/
launchctl unload ~/Library/LaunchAgents/com.miya.mac-activity-server.plist 2>/dev/null || true
launchctl unload ~/Library/LaunchAgents/com.miya.cloudflared-mac-activity.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/com.miya.mac-activity-server.plist
launchctl load ~/Library/LaunchAgents/com.miya.cloudflared-mac-activity.plist
```

Useful commands:

```shell
launchctl list | rg 'com.miya.(mac-activity-server|cloudflared-mac-activity)'
tail -f ~/Library/Logs/mac-activity-server.log
tail -f ~/Library/Logs/cloudflared-mac-activity.log
```
