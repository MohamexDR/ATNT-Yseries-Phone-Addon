Config = Config or {}

local resourceName = GetCurrentResourceName and GetCurrentResourceName() or "yseries"
local baseUrl = ("https://cfx-nui-%s/"):format(resourceName)
local atntConfig = Config.ATNT or {}
local atntApp = atntConfig.App or {}
local atntIcon = atntApp.IconPath or "ui/build/atnt/icon.svg"

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
