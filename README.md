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

This site now includes a local-only Mac activity widget in the homepage sidebar.

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
