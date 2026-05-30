Config = Config or {}

Config.ATNT = {
    Enabled = true,

    ProviderName = "ATNT",
    CurrencyLabel = "$",

    App = {
        Key = "atnt",
        Name = "ATNT",
        DefaultApp = true,
        IconPath = "ui/build/atnt/icon.svg",
        UiPath = "ui/build/atnt/index.html"
    },

    Account = {
        StartingFlexes = 0,
        StartingBalance = 0.0,
        DataEnabledByDefault = true
    },

    Costs = {
        BalancePerFlex = 1.0,
        SmsFlexes = 1,
        InternetActionFlexes = 0,
        UseFlexesBeforeBalance = true
    },

    Calls = {
        Enabled = true,
        RequireQuotaToAnswer = true,
        FlexesPerMinute = 1,
        RoundUpToMinute = true,
        MinimumBillableMinutes = 1,
        NotifyAfterCall = true,
        NotifyUnansweredCalls = false
    },

    Internet = {
        Enabled = true,
        RequireServiceForInternet = true,
        ChargePerMatchedCallback = false,
        BypassWhenCallbackReturns = false,

        GatedCallbackPrefixes = {
            "yseries:server:audix:",
            "yseries:server:banking:",
            "yseries:server:companies:",
            "yseries:server:email:",
            "yseries:server:garage:",
            "yseries:server:y:",
            "yseries:server:lovr:",
            "yseries:server:instashots:",
            "yseries:server:darkchat:",
            "yseries:server:news:",
            "yseries:server:ybuy:",
            "yseries:server:ypay:",
            "yseries:server:maps:",
            "yseries:server:messages:",
            "yseries:server:notes:",
            "yseries:server:gallery:",
            "yseries:server:groups:",
            "yseries:server:home:",
            "yseries:server:phone:",
            "yseries:server:playstore:",
            "yseries:server:promoHub:",
            "yseries:server:radio:",
            "yseries:server:recent:add",
            "yseries:server:utils:fivemanage:",
            "yseries:server:video-call",
            "yseries:server:wallpapers:",
            "yseries:server:weather:",
            "yseries:server:ycloud:"
        },

        BypassCallbacks = {
            ["yseries:server:generate-uid"] = true,
            ["yseries:server:main:get-phone-data"] = true,
            ["yseries:server:get-phone-imei-by-phone-number"] = true,
            ["yseries:server:get-contacts-by-imei"] = true,
            ["yseries:server:phone:add-contact"] = true,
            ["yseries:server:phone:edit-contact"] = true,
            ["yseries:server:phone:delete-contact"] = true,
            ["yseries:server:phone:set-favorite-status"] = true,
            ["yseries:server:phone:block-contact"] = true,
            ["yseries:server:phone:get-recent-calls"] = true,
            ["yseries:server:phone:validate-sim-number"] = true,
            ["yseries:server:phone:save-sound-setting"] = true,
            ["yseries:server:quickshare:is-enabled"] = true,
            ["yseries:server:quickshare:get-player-data"] = true,
            ["yseries:server:quickshare:share"] = true
        }
    },

    Packages = {
        { id = "daily", label = "Daily Flex", flexes = 25, price = 15.0, description = "Light calls, SMS, and app access." },
        { id = "plus", label = "Flex Plus", flexes = 90, price = 45.0, description = "A balanced everyday quota." },
        { id = "max", label = "Flex Max", flexes = 220, price = 100.0, description = "Long calls and heavy app usage." }
    },

    Recharge = {
        AllowSelfTopUp = false,
        Presets = { 25, 50, 100, 200 },
        VoucherCodes = {
            ATNT25 = 25,
            ATNT50 = 50,
            ATNT100 = 100
        }
    },

    ProviderPanel = {
        Enabled = true,
        Jobs = {
            [Config.Companies and Config.Companies.PoliceJob or "police"] = {
                MinGrade = 0,
                RequireDuty = false
            }
        },
        AllowBalanceCharge = true,
        AllowFlexCharge = true,
        NearbyRadius = 10.0,
        BalancePresets = { 25, 50, 100, 200 },
        FlexPresets = { 25, 90, 220 },
        NotifyTarget = true
    },

    Notifications = {
        Sound = "default",
        Timeout = 6000,
        NoServiceText = "No ATNT service. Recharge balance or buy Flexes to use this.",
        NoInternetText = "Mobile data is off or you have no ATNT quota.",
        NoCallText = "You need ATNT Flexes or balance before making calls.",
        NoTextText = "You need ATNT Flexes or balance before sending texts."
    },

    Debug = false
}

local function configureAtntCustomApp()
    Config.CustomApps = Config.CustomApps or {}

    local appConfig = Config.ATNT.App or {}
    local key = appConfig.Key or "atnt"

    for index = #Config.CustomApps, 1, -1 do
        local app = Config.CustomApps[index]
        if app.key == key or app.key == "atnt" then
            table.remove(Config.CustomApps, index)
        end
    end

    if Config.ATNT.Enabled == false then
        return
    end

    local resourceName = GetCurrentResourceName and GetCurrentResourceName() or "yseries"
    local baseUrl = ("https://cfx-nui-%s/"):format(resourceName)
    local iconPath = appConfig.IconPath or "ui/build/atnt/icon.svg"

    Config.CustomApps[#Config.CustomApps + 1] = {
        key = key,
        name = appConfig.Name or Config.ATNT.ProviderName or "ATNT",
        description = "Provider service",
        defaultApp = appConfig.DefaultApp ~= false,
        ui = baseUrl .. (appConfig.UiPath or "ui/build/atnt/index.html"),
        icon = {
            yos = baseUrl .. iconPath,
            humanoid = baseUrl .. iconPath
        }
    }
end

configureAtntCustomApp()
