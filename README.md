# ATNT YSeries Phone Addon

**ATNT-Yseries-Phone-Addon** adds a complete telecom/provider layer to **YSeries Phone** for FiveM. It integrates quota, flexes, balance, mobile data toggling, allowed mobile-data apps, and data consumption into the phone with a custom ATNT provider application.

This addon is made to feel like a real in-phone telecom service: players can manage their provider account, check usage, control mobile data, and use supported apps through a configurable provider system.

---

## Features

- Custom ATNT provider app for YSeries Phone.
- Player balance, quota, and flexes system.
- Mobile data on/off control.
- Configurable apps that are allowed to use mobile data.
- Data consumption tracking for supported apps.
- Provider settings are configurable from Lua.
- Clean UI inside the phone build.
- Persistent server-side handling through `oxmysql`.
- Designed as a drop-in addon for the existing YSeries Phone structure.

---

## Requirements

Before installing, make sure you already have:

- A working FiveM server.
- YSeries Phone installed and working.
- `oxmysql` installed and started before the phone resource.
- Access to the YSeries phone resource files.

Example start order:

```cfg
ensure oxmysql
ensure yseries
```

Replace `yseries` with the real resource name of your phone if it is different.

---

## Package Structure

The addon package contains the following files/folders:

```txt
ATNT-Yseries-Phone-Addon/
├── client/
│   └── custom/
│       └── atnt/
│           └── client.lua
├── server/
│   └── custom/
│       └── atnt/
│           └── server.lua
├── config/
│   ├── zz_atnt.lua
│   └── config.customApps.lua
└── ui/
    └── build/
        └── atnt/
            ├── index.html
            └── icon.svg
```

---

## Installation

### 1. Backup your phone resource

Before editing the phone resource, make a backup of your current YSeries Phone folder.

---

### 2. Install the UI files

Copy this folder from the addon:

```txt
ui/build/atnt
```

Into your YSeries Phone build folder:

```txt
your-yseries-phone/ui/build/atnt
```

The final path should look like this:

```txt
your-yseries-phone/ui/build/atnt/index.html
your-yseries-phone/ui/build/atnt/icon.svg
```

YSeries Phone can auto-load custom app UI files from the build folder when the custom app config points to the correct path.

---

### 3. Install the server files

Copy this folder:

```txt
server/custom/atnt
```

Into your YSeries Phone server custom folder:

```txt
your-yseries-phone/server/custom/atnt
```

The final path should be:

```txt
your-yseries-phone/server/custom/atnt/server.lua
```

---

### 4. Install the client files

Copy this folder:

```txt
client/custom/atnt
```

Into your YSeries Phone client custom folder:

```txt
your-yseries-phone/client/custom/atnt
```

The final path should be:

```txt
your-yseries-phone/client/custom/atnt/client.lua
```

---

### 5. Install the config file

Copy:

```txt
config/zz_atnt.lua
```

Into your YSeries Phone config folder:

```txt
your-yseries-phone/config/zz_atnt.lua
```

Open `zz_atnt.lua` and configure the provider name, app settings, balance/quota/flex settings, and any other options included in the file.

---

### 6. Add the files to `fxmanifest.lua`

Open the YSeries Phone `fxmanifest.lua` and make sure the custom folders are loaded.

Server scripts should include `oxmysql` and the server Lua files:

```lua
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/**/*.lua',
}
```

Client scripts should include the client Lua files:

```lua
client_scripts {
    'client/**/*.lua',
}
```

Make sure your config files are loaded too. Depending on how your YSeries Phone manifest is structured, either include all config files:

```lua
shared_scripts {
    'config/**/*.lua',
}
```

Or add the ATNT config directly:

```lua
shared_scripts {
    'config/zz_atnt.lua',
}
```

If your phone already has `shared_scripts` for config files, do not duplicate it. Just make sure `config/zz_atnt.lua` is included and loaded before the custom app registration.

---

### 7. Register the custom app

Open your YSeries Phone custom apps config and add the ATNT app.

If your phone already has `Config.CustomApps`, add the ATNT app inside the existing table instead of replacing the whole table.

Recommended append version:

```lua
Config.CustomApps = Config.CustomApps or {}

Config.CustomApps[#Config.CustomApps + 1] = {
    key = atntApp.Key or "atnt",
    name = atntApp.Name or atntConfig.ProviderName or "ATNT",
    description = "Provider service",
    defaultApp = atntApp.DefaultApp ~= false,
    ui = baseUrl .. (atntApp.UiPath or "ui/build/atnt/index.html"),
    icon = {
        yos = baseUrl .. atntIcon,
        humanoid = baseUrl .. atntIcon
    }
}
```

Clean install version:

```lua
Config.CustomApps = {
    {
        key = atntApp.Key or "atnt",
        name = atntApp.Name or atntConfig.ProviderName or "ATNT",
        description = "Provider service",
        defaultApp = atntApp.DefaultApp ~= false,
        ui = baseUrl .. (atntApp.UiPath or "ui/build/atnt/index.html"),
        icon = {
            yos = baseUrl .. atntIcon,
            humanoid = baseUrl .. atntIcon
        }
    }
}
```

> Important: only use the clean install version if you do not already have other custom apps. If you already have custom apps, use the append version so you do not overwrite them.

---

### 8. Restart the resource

After copying the files and editing the manifest/config, restart the phone resource:

```cfg
restart yseries
```

Or restart the full server.

---

## Configuration

Most addon settings are inside:

```txt
config/zz_atnt.lua
```

Use this file to customize the provider system, including things like:

- Provider name.
- App key/name/icon/path.
- Default app visibility.
- Quota and flex settings.
- Balance settings.
- Mobile data behavior.
- Supported apps that can consume data.
- Any server-side pricing or consumption values included in the config.

After editing the config, restart the phone resource.

---

## Common Issues

### The ATNT app does not appear

Check the following:

- `config/zz_atnt.lua` is loaded in `fxmanifest.lua`.
- The custom app was added to `Config.CustomApps`.
- The app key is unique and not used by another app.
- The phone resource was restarted after installation.

---

### The ATNT app opens as a black screen

Check the UI path:

```lua
ui = baseUrl .. (atntApp.UiPath or "ui/build/atnt/index.html")
```

Then confirm the file exists here:

```txt
your-yseries-phone/ui/build/atnt/index.html
```

Also check the browser console/NUI console for JavaScript errors.

---

### Database errors appear in server console

Check the following:

- `oxmysql` is installed.
- `oxmysql` starts before the phone resource.
- Your database connection string is correct.
- The ATNT server file is being loaded.

---

### Existing custom apps disappeared

This usually means `Config.CustomApps` was overwritten.

Use the append method instead:

```lua
Config.CustomApps = Config.CustomApps or {}
Config.CustomApps[#Config.CustomApps + 1] = { ... }
```

Do not replace the full `Config.CustomApps` table if you already have apps installed.

---

## Notes for Developers

This addon is installed inside the YSeries Phone resource structure. It is not meant to be started as a completely separate resource unless you manually convert the paths, exports, and NUI loading logic for standalone usage.

The expected addon paths are:

```txt
client/custom/atnt/client.lua
server/custom/atnt/server.lua
config/zz_atnt.lua
ui/build/atnt/index.html
```

---

## Support

When asking for support, include:

- Your YSeries Phone version.
- Your server artifact version.
- Any server console errors.
- Any F8/NUI console errors.
- Your custom app config snippet.
- A screenshot of the app issue, if it is UI-related.

---

## License

This resource is provided by its author/vendor. Do not redistribute, leak, resell, or reupload without permission.
