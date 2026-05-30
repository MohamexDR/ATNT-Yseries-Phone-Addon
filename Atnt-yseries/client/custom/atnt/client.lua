local ATNT = {
    Wrapped = false,
    LastAccount = nil
}

local function cfg()
    return Config and Config.ATNT or {}
end

local function enabled()
    return cfg().Enabled == true
end

local function appKey()
    return cfg().App and cfg().App.Key or "atnt"
end

local function resourceName()
    return GetCurrentResourceName()
end

local function isStaticCustomAppConfigured()
    for _, app in ipairs(Config.CustomApps or {}) do
        if app.key == appKey() then
            return true
        end
    end

    return false
end

local function debugLog(...)
    if cfg().Debug then
        print("[ATNT]", ...)
    end
end

local function sendNotification(text, title)
    TriggerEvent("yseries:client:send-notification", {
        app = appKey(),
        title = title or cfg().ProviderName or "ATNT",
        text = text,
        sound = cfg().Notifications and cfg().Notifications.Sound or "default",
        timeout = cfg().Notifications and cfg().Notifications.Timeout or 6000
    })
end

local function currentPhonePayload()
    local payload = {}

    if CurrentPhoneImei then
        payload.phoneImei = CurrentPhoneImei
    end

    if Device and Device.number then
        payload.phoneNumber = Device.number
    end

    return payload
end

local function pushAccountToApp(account)
    ATNT.LastAccount = account

    pcall(function()
        exports[resourceName()]:SendAppMessage(appKey(), {
            type = "account",
            account = account
        })
    end)
end

local function pushDashboardToApp()
    if not enabled() or not lib or not lib.callback or not lib.callback.await then
        return
    end

    pcall(function()
        local response = lib.callback.await("atnt:server:get-dashboard", false, currentPhonePayload())

        if not response or not response.success then
            return
        end

        if response.account then
            ATNT.LastAccount = response.account
        end

        exports[resourceName()]:SendAppMessage(appKey(), {
            type = "dashboard",
            account = response.account,
            config = response.config
        })
    end)
end

local function scheduleDashboardRefresh()
    CreateThread(function()
        Wait(750)
        pushDashboardToApp()
    end)
end

local function callbackMatches(name)
    if not name or name:sub(1, 12) == "atnt:server:" then
        return false
    end

    local internetCfg = cfg().Internet or {}

    if internetCfg.BypassCallbacks and internetCfg.BypassCallbacks[name] then
        return false
    end

    for _, prefix in ipairs(internetCfg.GatedCallbackPrefixes or {}) do
        if name:sub(1, #prefix) == prefix then
            return true
        end
    end

    return false
end

local function isCallCallback(name)
    return name == "yseries:server:call-contact" or name == "yseries:server:video-call-contact"
end

local function cancelPendingCall(originalAwait, callData)
    local callId = callData and (callData.callId or callData.CallId)

    if callId and originalAwait then
        pcall(function()
            originalAwait("atnt:server:release-call", false, callId)
        end)
    end

    pcall(function()
        TriggerEvent("yseries:client:cancel-call")
    end)
end

local function blockedReturn(name, reason)
    if isCallCallback(name) then
        return nil
    end

    return nil
end

local function authorize(originalAwait, usageType, payload)
    payload = payload or currentPhonePayload()

    local response = originalAwait("atnt:server:authorize-usage", false, usageType, payload)
    if response and response.account then
        pushAccountToApp(response.account)
    end

    return response
end

local function charge(originalAwait, usageType, payload)
    payload = payload or currentPhonePayload()

    local response = originalAwait("atnt:server:charge-usage", false, usageType, payload)
    if response and response.account then
        pushAccountToApp(response.account)
    end

    return response
end

local function installCallbackWrapper()
    if ATNT.Wrapped or not enabled() then
        return
    end

    while not lib or not lib.callback or not lib.callback.await do
        Wait(100)
    end

    local originalAwait = lib.callback.await

    lib.callback.await = function(name, ...)
        local args = { ... }

        if not enabled() then
            return originalAwait(name, ...)
        end

        if isCallCallback(name) and (not cfg().Calls or cfg().Calls.Enabled ~= false) then
            local callData = args[2] or {}
            local auth = originalAwait("atnt:server:authorize-call", false, callData)

            if not auth or not auth.allowed then
                local reason = auth and auth.reason or (cfg().Notifications and cfg().Notifications.NoCallText) or "No ATNT call quota"
                sendNotification(reason)
                cancelPendingCall(originalAwait, callData)
                return blockedReturn(name, reason)
            end

            local result = originalAwait(name, ...)
            if not result or result.success == false then
                originalAwait("atnt:server:release-call", false, callData.callId or callData.CallId)
                cancelPendingCall(originalAwait, callData)
                return nil
            end

            return result
        end

        if name == "yseries:server:messages:send" then
            local messagePayload = args[2] or {}
            local auth = authorize(originalAwait, "message", messagePayload)

            if not auth or not auth.allowed then
                local reason = auth and auth.reason or (cfg().Notifications and cfg().Notifications.NoTextText) or "No ATNT text quota"
                sendNotification(reason)
                return nil
            end

            local result = originalAwait(name, ...)
            if result then
                charge(originalAwait, "message", messagePayload)
            end

            return result
        end

        if cfg().Internet and cfg().Internet.Enabled and callbackMatches(name) then
            local auth = authorize(originalAwait, "internet", currentPhonePayload())

            if not auth or not auth.allowed then
                local reason = auth and auth.reason or (cfg().Notifications and cfg().Notifications.NoInternetText) or "No ATNT internet quota"
                sendNotification(reason)
                return blockedReturn(name, reason)
            end

            local result = originalAwait(name, ...)

            if result and cfg().Internet.ChargePerMatchedCallback then
                charge(originalAwait, "internet", currentPhonePayload())
            end

            return result
        end

        return originalAwait(name, ...)
    end

    ATNT.Wrapped = true
    debugLog("callback wrapper installed")
end

local function installCallAnswerWrapper()
    local originalTriggerServerEvent = TriggerServerEvent

    TriggerServerEvent = function(name, ...)
        if enabled()
            and cfg().Calls
            and cfg().Calls.Enabled ~= false
            and cfg().Calls.RequireQuotaToAnswer ~= false
            and (name == "yseries:server:answer-call" or name == "yseries:server:answer-video-call")
        then
            local auth = lib.callback.await("atnt:server:authorize-usage", false, "call", currentPhonePayload())

            if auth and auth.account then
                pushAccountToApp(auth.account)
            end

            if not auth or not auth.allowed then
                local reason = auth and auth.reason or (cfg().Notifications and cfg().Notifications.NoCallText) or "No ATNT call quota"
                sendNotification(reason)

                if PhoneData and PhoneData.CallData and PhoneData.CallData.TargetData and PhoneData.CallData.TargetData.number then
                    originalTriggerServerEvent("yseries:server:cancel-call", PhoneData.CallData.TargetData.number)
                end

                TriggerEvent("yseries:client:cancel-call")
                return
            end
        end

        return originalTriggerServerEvent(name, ...)
    end
end

local function addApp()
    if not enabled() then
        return
    end

    if isStaticCustomAppConfigured() then
        debugLog("static custom app config found, skipping dynamic AddCustomApp")
        return
    end

    while GetResourceState(resourceName()) ~= "started" do
        Wait(500)
    end

    local dataLoaded = false
    while not dataLoaded do
        pcall(function()
            dataLoaded = exports[resourceName()]:GetDataLoaded()
        end)
        Wait(500)
    end

    local baseUrl = "https://cfx-nui-" .. resourceName() .. "/"
    local appCfg = cfg().App or {}

    pcall(function()
        exports[resourceName()]:AddCustomApp({
            key = appCfg.Key or "atnt",
            name = appCfg.Name or "ATNT",
            defaultApp = appCfg.DefaultApp ~= false,
            ui = baseUrl .. (appCfg.UiPath or "ui/build/atnt/index.html"),
            icon = {
                yos = baseUrl .. (appCfg.IconPath or "ui/build/atnt/icon.svg"),
                humanoid = baseUrl .. (appCfg.IconPath or "ui/build/atnt/icon.svg")
            }
        })
    end)
end

RegisterNUICallback("atnt:get-dashboard", function(data, cb)
    local response = lib.callback.await("atnt:server:get-dashboard", false, data or currentPhonePayload())

    if response and response.account then
        pushAccountToApp(response.account)
    end

    cb(response or {
        success = false,
        error = "ATNT unavailable"
    })
end)

RegisterNUICallback("atnt:purchase-package", function(data, cb)
    local response = lib.callback.await("atnt:server:purchase-package", false, data and data.packageId)

    if response and response.account then
        pushAccountToApp(response.account)
    end

    cb(response or {
        success = false,
        error = "Purchase failed"
    })
end)

RegisterNUICallback("atnt:top-up", function(data, cb)
    local response = lib.callback.await("atnt:server:top-up", false, data or {})

    if response and response.account then
        pushAccountToApp(response.account)
    end

    cb(response or {
        success = false,
        error = "Recharge failed"
    })
end)

RegisterNUICallback("atnt:provider-charge", function(data, cb)
    local response = lib.callback.await("atnt:server:provider-charge", false, data or {})

    if response and response.account then
        pushAccountToApp(response.account)
    end

    cb(response or {
        success = false,
        error = "Provider charge failed"
    })
end)

RegisterNUICallback("atnt:get-nearby-customers", function(_, cb)
    local playerIds = {}
    local panelCfg = cfg().ProviderPanel or {}
    local radius = tonumber(panelCfg.NearbyRadius) or 10.0
    local selfSource = GetPlayerServerId(PlayerId())
    local nearbyPlayers = lib.getNearbyPlayers(GetEntityCoords(PlayerPedId()), radius) or {}

    for _, player in ipairs(nearbyPlayers) do
        local playerId = player.id
        local serverId = playerId and GetPlayerServerId(playerId)

        if serverId and serverId ~= selfSource then
            playerIds[#playerIds + 1] = serverId
        end
    end

    local response = lib.callback.await("atnt:server:get-nearby-customers", false, playerIds)

    cb(response or {
        success = false,
        error = "Could not load nearby customers"
    })
end)

RegisterNUICallback("atnt:set-data-enabled", function(data, cb)
    local response = lib.callback.await("atnt:server:set-data-enabled", false, data and data.enabled == true)

    if response and response.account then
        pushAccountToApp(response.account)
    end

    cb(response or {
        success = false,
        error = "Could not update mobile data"
    })
end)

RegisterNUICallback("atnt:toggle-focus", function(focus, cb)
    SetNuiFocusKeepInput(focus == true)
    cb({})
end)

RegisterNetEvent("atnt:client:account-updated", function(account)
    pushAccountToApp(account)
end)

RegisterNetEvent("QBCore:Client:OnJobUpdate", scheduleDashboardRefresh)
RegisterNetEvent("QBCore:Client:OnPlayerLoaded", scheduleDashboardRefresh)
RegisterNetEvent("esx:setJob", scheduleDashboardRefresh)
RegisterNetEvent("esx:playerLoaded", scheduleDashboardRefresh)

AddEventHandler("onResourceStop", function(resource)
    if resource == resourceName() then
        if isStaticCustomAppConfigured() then
            return
        end

        pcall(function()
            exports[resourceName()]:RemoveCustomApp(appKey())
        end)
    end
end)

CreateThread(function()
    Wait(1000)
    installCallbackWrapper()
    installCallAnswerWrapper()
end)

CreateThread(function()
    addApp()
end)
