local ActiveCalls = {}
local TableReady = false

local function cfg()
    return Config and Config.ATNT or {}
end

local function enabled()
    return cfg().Enabled == true
end

local function debugLog(...)
    if cfg().Debug then
        print("[ATNT]", ...)
    end
end

local function resourceName()
    return GetCurrentResourceName()
end

local function roundMoney(value)
    value = tonumber(value) or 0
    return math.floor((value * 100) + 0.5) / 100
end

local function formatMoney(value)
    local label = cfg().CurrencyLabel or "$"
    return ("%s%.2f"):format(label, roundMoney(value))
end

local function normalizeAccount(row)
    if not row then
        return nil
    end

    return {
        phoneImei = row.phone_imei,
        phoneNumber = row.phone_number,
        flexes = tonumber(row.flexes) or 0,
        balance = roundMoney(row.balance),
        dataEnabled = row.data_enabled == true or row.data_enabled == 1 or row.data_enabled == "1"
    }
end

local function getPackage(packageId)
    for _, package in ipairs(cfg().Packages or {}) do
        if package.id == packageId then
            return package
        end
    end
end

local function normalizeJobData(job, player)
    if type(job) == "string" then
        job = { name = job }
    end

    if not job and player and player.playerData then
        job = player.playerData.job
    end

    if not job and player and player.PlayerData then
        job = player.PlayerData.job
    end

    if type(job) == "string" then
        job = { name = job }
    end

    if not job or not job.name then
        return nil
    end

    local grade = 0
    if type(job.grade) == "table" then
        grade = tonumber(job.grade.level or job.grade.grade or 0) or 0
    else
        grade = tonumber(job.grade or job.grade_level or job.gradeLevel or 0) or 0
    end

    local duty = true
    if job.onduty ~= nil then
        duty = job.onduty == true
    elseif job.onDuty ~= nil then
        duty = job.onDuty == true
    elseif job.duty ~= nil then
        duty = job.duty == true
    elseif player and player.playerData and player.playerData.job and player.playerData.job.onduty ~= nil then
        duty = player.playerData.job.onduty == true
    elseif player and player.PlayerData and player.PlayerData.job and player.PlayerData.job.onduty ~= nil then
        duty = player.PlayerData.job.onduty == true
    end

    return {
        name = job.name,
        grade = grade,
        duty = duty
    }
end

local function getFrameworkFallbackJobData(source)
    if Config.Framework == "qb" and GetResourceState("qb-core"):find("start") then
        local ok, qbPlayer = pcall(function()
            return exports["qb-core"]:GetCoreObject().Functions.GetPlayer(source)
        end)

        if ok and qbPlayer and qbPlayer.PlayerData then
            return normalizeJobData(qbPlayer.PlayerData.job, qbPlayer)
        end
    end

    if Config.Framework == "qbox" and GetResourceState("qbx_core"):find("start") then
        local ok, qboxPlayer = pcall(function()
            return exports.qbx_core:GetPlayer(source)
        end)

        if ok and qboxPlayer and qboxPlayer.PlayerData then
            return normalizeJobData(qboxPlayer.PlayerData.job, qboxPlayer)
        end
    end

    if Config.Framework == "esx" and GetResourceState("es_extended"):find("start") then
        local ok, esxPlayer = pcall(function()
            local ESX = exports.es_extended:getSharedObject()
            return ESX and ESX.GetPlayerFromId(source)
        end)

        if ok and esxPlayer then
            return normalizeJobData(esxPlayer.job, esxPlayer)
        end
    end

    return nil
end

local function getPlayerJobData(source)
    if not Framework or not Framework.GetPlayerFromId then
        return getFrameworkFallbackJobData(source)
    end

    local player = Framework.GetPlayerFromId(source)
    if not player then
        return getFrameworkFallbackJobData(source)
    end

    local job = player.job or (player.playerData and player.playerData.job) or (player.PlayerData and player.PlayerData.job)

    if type(player.getJob) == "function" then
        local ok, compactJob = pcall(player.getJob)
        if ok and compactJob then
            if type(job) == "string" then
                job = { name = job }
            else
                job = job or {}
            end

            job.name = job.name or compactJob.name

            if type(job.grade) == "table" then
                job.grade.level = job.grade.level or compactJob.grade
                job.grade.name = job.grade.name or compactJob.grade_name
            else
                job.grade = job.grade or compactJob.grade
            end
        end
    end

    return normalizeJobData(job, player) or getFrameworkFallbackJobData(source)
end

local function normalizeJobName(jobName)
    if not jobName then
        return nil
    end

    return tostring(jobName):lower()
end

local function getProviderJobRule(jobName)
    local panelCfg = cfg().ProviderPanel or {}
    local normalizedJob = normalizeJobName(jobName)

    if not normalizedJob then
        return nil
    end

    if panelCfg.Job and normalizeJobName(panelCfg.Job) == normalizedJob then
        return true
    end

    if panelCfg.JobName and normalizeJobName(panelCfg.JobName) == normalizedJob then
        return true
    end

    local jobs = panelCfg.Jobs or {}

    if type(jobs) == "string" then
        return normalizeJobName(jobs) == normalizedJob and true or nil
    end

    if type(jobs) ~= "table" then
        return nil
    end

    for configuredJob, rule in pairs(jobs) do
        if type(configuredJob) == "string" and normalizeJobName(configuredJob) == normalizedJob then
            return rule
        end
    end

    for _, rule in ipairs(jobs) do
        if normalizeJobName(rule) == normalizedJob then
            return true
        end

        if type(rule) == "table"
            and (
                normalizeJobName(rule.name) == normalizedJob
                or normalizeJobName(rule.job) == normalizedJob
                or normalizeJobName(rule.Job) == normalizedJob
            )
        then
            return rule
        end
    end

    return nil
end

local function canUseProviderPanel(source)
    local panelCfg = cfg().ProviderPanel or {}
    if panelCfg.Enabled == false then
        return false
    end

    local jobData = getPlayerJobData(source)
    if not jobData then
        return false
    end

    local rule = getProviderJobRule(jobData.name)
    if not rule then
        return false
    end

    if type(rule) == "table" then
        local minGrade = tonumber(rule.MinGrade or rule.MinimumGrade or rule.minGrade or rule.minimumGrade or 0) or 0
        if jobData.grade < minGrade then
            return false
        end

        local requireDuty = rule.RequireDuty == true or rule.requireDuty == true or rule.OnDuty == true
        if requireDuty and not jobData.duty then
            return false
        end
    end

    return true, jobData
end

local function getPhoneIdentity(source, payload)
    payload = payload or {}

    local imei = payload.phoneImei or payload.imei
    local phoneNumber = payload.phoneNumber or payload.number

    local okImei, exportedImei = pcall(function()
        return exports[resourceName()]:GetPhoneImeiBySourceId(source)
    end)

    if okImei and exportedImei then
        imei = exportedImei
    end

    local okNumber, exportedNumber = pcall(function()
        return exports[resourceName()]:GetPhoneNumberBySourceId(source)
    end)

    if okNumber and exportedNumber then
        phoneNumber = exportedNumber
    end

    return imei, phoneNumber
end

local function publicConfig(source)
    local rechargeCfg = cfg().Recharge or {}
    local panelCfg = cfg().ProviderPanel or {}
    local canUsePanel = canUseProviderPanel(source)

    return {
        providerName = cfg().ProviderName,
        currencyLabel = cfg().CurrencyLabel,
        packages = cfg().Packages or {},
        selfRechargeEnabled = rechargeCfg.AllowSelfTopUp ~= false,
        rechargePresets = rechargeCfg.Presets or {},
        providerPanel = {
            enabled = canUsePanel == true,
            allowBalanceCharge = panelCfg.AllowBalanceCharge ~= false,
            allowFlexCharge = panelCfg.AllowFlexCharge ~= false,
            balancePresets = panelCfg.BalancePresets or rechargeCfg.Presets or {},
            flexPresets = panelCfg.FlexPresets or {}
        },
        costs = {
            smsFlexes = cfg().Costs and cfg().Costs.SmsFlexes or 1,
            callFlexesPerMinute = cfg().Calls and cfg().Calls.FlexesPerMinute or 1,
            internetActionFlexes = cfg().Costs and cfg().Costs.InternetActionFlexes or 0,
            balancePerFlex = cfg().Costs and cfg().Costs.BalancePerFlex or 1
        }
    }
end

local function ensureTable()
    if TableReady or not enabled() then
        return true
    end

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `yseries_atnt_accounts` (
            `phone_imei` VARCHAR(64) NOT NULL,
            `phone_number` VARCHAR(32) DEFAULT NULL,
            `flexes` INT NOT NULL DEFAULT 0,
            `balance` DECIMAL(12,2) NOT NULL DEFAULT 0.00,
            `data_enabled` TINYINT(1) NOT NULL DEFAULT 1,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`phone_imei`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    TableReady = true
    return true
end

local function ensureAccount(source, payload)
    if not enabled() then
        return nil, "ATNT is disabled"
    end

    ensureTable()

    local imei, phoneNumber = getPhoneIdentity(source, payload)
    if not imei then
        return nil, "No phone found"
    end

    local row = MySQL.single.await("SELECT * FROM `yseries_atnt_accounts` WHERE `phone_imei` = ?", { imei })
    if not row then
        local accountCfg = cfg().Account or {}
        MySQL.insert.await([[
            INSERT INTO `yseries_atnt_accounts` (`phone_imei`, `phone_number`, `flexes`, `balance`, `data_enabled`)
            VALUES (?, ?, ?, ?, ?)
        ]], {
            imei,
            phoneNumber,
            tonumber(accountCfg.StartingFlexes) or 0,
            roundMoney(accountCfg.StartingBalance),
            accountCfg.DataEnabledByDefault == false and 0 or 1
        })

        row = MySQL.single.await("SELECT * FROM `yseries_atnt_accounts` WHERE `phone_imei` = ?", { imei })
    elseif phoneNumber and row.phone_number ~= phoneNumber then
        MySQL.update.await("UPDATE `yseries_atnt_accounts` SET `phone_number` = ? WHERE `phone_imei` = ?", {
            phoneNumber,
            imei
        })

        row.phone_number = phoneNumber
    end

    return normalizeAccount(row)
end

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function getPhoneImeiByNumber(phoneNumber)
    local imei = nil

    if GetPhoneImeiByPhoneNumber then
        imei = GetPhoneImeiByPhoneNumber(phoneNumber)
    end

    if not imei then
        local ok, exportedImei = pcall(function()
            return exports[resourceName()]:GetPhoneImeiByPhoneNumber(phoneNumber)
        end)

        if ok then
            imei = exportedImei
        end
    end

    return imei
end

local function getSourceByPhoneNumber(phoneNumber)
    local targetSource = nil

    if GetPlayerSourceIdByPhoneNumber then
        targetSource = GetPlayerSourceIdByPhoneNumber(phoneNumber)
    end

    if not targetSource then
        local ok, exportedSource = pcall(function()
            return exports[resourceName()]:GetPlayerSourceIdByPhoneNumber(phoneNumber)
        end)

        if ok then
            targetSource = exportedSource
        end
    end

    return tonumber(targetSource)
end

local function getPhoneNumberBySource(playerSource)
    local ok, phoneNumber = pcall(function()
        return exports[resourceName()]:GetPhoneNumberBySourceId(playerSource)
    end)

    if ok then
        return phoneNumber
    end

    return nil
end

local function getDisplayName(playerSource)
    local player = Framework and Framework.GetPlayerFromId and Framework.GetPlayerFromId(playerSource)

    if player and type(player.getName) == "function" then
        local ok, name = pcall(player.getName)
        if ok and name and name ~= "" then
            return name
        end
    end

    return GetPlayerName(playerSource) or ("Player %s"):format(playerSource)
end

local function distanceBetween(firstCoords, secondCoords)
    local dx = (firstCoords.x or firstCoords[1] or 0) - (secondCoords.x or secondCoords[1] or 0)
    local dy = (firstCoords.y or firstCoords[2] or 0) - (secondCoords.y or secondCoords[2] or 0)
    local dz = (firstCoords.z or firstCoords[3] or 0) - (secondCoords.z or secondCoords[3] or 0)

    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

local function ensureAccountByPhoneNumber(phoneNumber)
    phoneNumber = trim(phoneNumber)
    if phoneNumber == "" then
        return nil, "Enter a phone number"
    end

    ensureTable()

    local row = MySQL.single.await("SELECT * FROM `yseries_atnt_accounts` WHERE `phone_number` = ? LIMIT 1", { phoneNumber })
    if row then
        return normalizeAccount(row), nil, getSourceByPhoneNumber(phoneNumber)
    end

    local imei = getPhoneImeiByNumber(phoneNumber)
    if not imei then
        return nil, "Phone number not found"
    end

    row = MySQL.single.await("SELECT * FROM `yseries_atnt_accounts` WHERE `phone_imei` = ? LIMIT 1", { imei })
    if not row then
        local accountCfg = cfg().Account or {}
        MySQL.insert.await([[
            INSERT INTO `yseries_atnt_accounts` (`phone_imei`, `phone_number`, `flexes`, `balance`, `data_enabled`)
            VALUES (?, ?, ?, ?, ?)
        ]], {
            imei,
            phoneNumber,
            tonumber(accountCfg.StartingFlexes) or 0,
            roundMoney(accountCfg.StartingBalance),
            accountCfg.DataEnabledByDefault == false and 0 or 1
        })

        row = MySQL.single.await("SELECT * FROM `yseries_atnt_accounts` WHERE `phone_imei` = ? LIMIT 1", { imei })
    elseif row.phone_number ~= phoneNumber then
        MySQL.update.await("UPDATE `yseries_atnt_accounts` SET `phone_number` = ? WHERE `phone_imei` = ?", {
            phoneNumber,
            imei
        })

        row.phone_number = phoneNumber
    end

    return normalizeAccount(row), nil, getSourceByPhoneNumber(phoneNumber)
end

local function saveAccount(account)
    MySQL.update.await([[
        UPDATE `yseries_atnt_accounts`
        SET `phone_number` = ?, `flexes` = ?, `balance` = ?, `data_enabled` = ?
        WHERE `phone_imei` = ?
    ]], {
        account.phoneNumber,
        math.floor(tonumber(account.flexes) or 0),
        roundMoney(account.balance),
        account.dataEnabled and 1 or 0,
        account.phoneImei
    })
end

local function hasService(account, usageType)
    if not account then
        return false
    end

    if usageType == "internet" and cfg().Internet and cfg().Internet.RequireServiceForInternet then
        if not account.dataEnabled then
            return false
        end
    end

    return (tonumber(account.flexes) or 0) > 0 or (tonumber(account.balance) or 0) > 0
end

local function balanceCostForFlexes(flexes)
    return roundMoney((tonumber(flexes) or 0) * (cfg().Costs and cfg().Costs.BalancePerFlex or 1))
end

local function canAfford(account, flexCost)
    flexCost = math.max(0, tonumber(flexCost) or 0)
    if flexCost <= 0 then
        return true
    end

    local availableFlexes = tonumber(account.flexes) or 0
    local remainingFlexes = math.max(0, flexCost - availableFlexes)
    local balanceCost = balanceCostForFlexes(remainingFlexes)

    return (tonumber(account.balance) or 0) >= balanceCost
end

local function chargeAccount(account, flexCost)
    flexCost = math.max(0, tonumber(flexCost) or 0)

    local spentFlexes = 0
    local spentBalance = 0

    if flexCost <= 0 then
        return true, account, {
            flexes = spentFlexes,
            balance = spentBalance
        }
    end

    if not canAfford(account, flexCost) then
        return false, account, {
            flexes = spentFlexes,
            balance = spentBalance
        }
    end

    local useFlexesFirst = not cfg().Costs or cfg().Costs.UseFlexesBeforeBalance ~= false

    if useFlexesFirst then
        spentFlexes = math.min(tonumber(account.flexes) or 0, flexCost)
        account.flexes = (tonumber(account.flexes) or 0) - spentFlexes
        flexCost = flexCost - spentFlexes
    end

    if flexCost > 0 then
        spentBalance = balanceCostForFlexes(flexCost)
        account.balance = roundMoney((tonumber(account.balance) or 0) - spentBalance)
    end

    saveAccount(account)

    return true, account, {
        flexes = spentFlexes,
        balance = spentBalance
    }
end

local function notifySource(source, text, title)
    if not source or source <= 0 then
        return
    end

    TriggerClientEvent("yseries:client:send-notification", source, {
        app = cfg().App and cfg().App.Key or "atnt",
        title = title or cfg().ProviderName or "ATNT",
        text = text,
        sound = cfg().Notifications and cfg().Notifications.Sound or "default",
        timeout = cfg().Notifications and cfg().Notifications.Timeout or 6000
    })
end

local function notifyPhone(account, source, text, title)
    if source and source > 0 and GetPlayerPing(source) > 0 then
        notifySource(source, text, title)
        return
    end

    if SendNotification and account and account.phoneImei then
        SendNotification({
            app = cfg().App and cfg().App.Key or "atnt",
            title = title or cfg().ProviderName or "ATNT",
            text = text,
            sound = cfg().Notifications and cfg().Notifications.Sound or "default",
            timeout = cfg().Notifications and cfg().Notifications.Timeout or 6000
        }, "phoneImei", account.phoneImei)
    end
end

local function pushAccount(source, account)
    if source and source > 0 then
        TriggerClientEvent("atnt:client:account-updated", source, account)
    end
end

local function usageCost(usageType, payload)
    payload = payload or {}

    if usageType == "message" then
        local base = cfg().Costs and cfg().Costs.SmsFlexes or 1
        local participants = payload.participants
        local count = 1

        if type(participants) == "table" and #participants > 1 then
            count = #participants
        end

        return base * count
    end

    if usageType == "internet" then
        if cfg().Internet and cfg().Internet.ChargePerMatchedCallback then
            return cfg().Costs and cfg().Costs.InternetActionFlexes or 0
        end

        return 0
    end

    if usageType == "callMinute" then
        return cfg().Calls and cfg().Calls.FlexesPerMinute or 1
    end

    return 0
end

local function authorizeUsage(source, usageType, payload)
    local account, err = ensureAccount(source, payload)
    if not account then
        return {
            allowed = false,
            reason = err or "ATNT account unavailable"
        }
    end

    if not hasService(account, usageType) then
        return {
            allowed = false,
            account = account,
            reason = cfg().Notifications and cfg().Notifications.NoServiceText or "No ATNT service"
        }
    end

    local cost = usageCost(usageType, payload)
    if not canAfford(account, cost) then
        return {
            allowed = false,
            account = account,
            reason = cfg().Notifications and cfg().Notifications.NoServiceText or "Insufficient ATNT balance"
        }
    end

    return {
        allowed = true,
        account = account,
        cost = cost
    }
end

local function chargeUsage(source, usageType, payload)
    local account, err = ensureAccount(source, payload)
    if not account then
        return {
            success = false,
            reason = err or "ATNT account unavailable"
        }
    end

    local cost = usageCost(usageType, payload)
    local ok, updated, spent = chargeAccount(account, cost)

    if ok then
        pushAccount(source, updated)
    end

    return {
        success = ok,
        account = updated,
        spent = spent,
        cost = cost
    }
end

local function authorizeCall(source, callData)
    local response = authorizeUsage(source, "call", callData)
    if not response.allowed then
        return response
    end

    local minuteCost = usageCost("callMinute")
    if not canAfford(response.account, minuteCost) then
        return {
            allowed = false,
            account = response.account,
            reason = cfg().Notifications and cfg().Notifications.NoCallText or "No ATNT call quota"
        }
    end

    local callId = callData and (callData.callId or callData.CallId)
    if callId then
        ActiveCalls[callId] = {
            source = source,
            phoneImei = response.account.phoneImei,
            phoneNumber = response.account.phoneNumber,
            targetNumber = callData.targetNumber,
            authorizedAt = os.time(),
            startedAt = nil,
            account = response.account
        }
    end

    return {
        allowed = true,
        account = response.account,
        cost = minuteCost
    }
end

local function releaseCall(callId)
    if callId then
        ActiveCalls[callId] = nil
    end

    return true
end

local function markCallAnswered(callData)
    if not callData then
        return
    end

    local callId = callData.CallId or callData.callId
    local session = callId and ActiveCalls[callId]

    if session and not session.startedAt then
        session.startedAt = os.time()
        debugLog("Call answered", callId)
    end
end

local function billableMinutes(duration)
    duration = math.max(0, tonumber(duration) or 0)

    if cfg().Calls and cfg().Calls.RoundUpToMinute == false then
        return math.max(cfg().Calls.MinimumBillableMinutes or 0, duration / 60)
    end

    return math.max(cfg().Calls and cfg().Calls.MinimumBillableMinutes or 1, math.ceil(duration / 60))
end

local function finalizeCall(callId)
    local session = callId and ActiveCalls[callId]
    if not session then
        return
    end

    ActiveCalls[callId] = nil

    local account = ensureAccount(session.source, {
        phoneImei = session.phoneImei,
        phoneNumber = session.phoneNumber
    })

    if not account then
        return
    end

    if not session.startedAt then
        if cfg().Calls and cfg().Calls.NotifyUnansweredCalls then
            notifyPhone(account, session.source, ("No charge. Flexes: %d. Balance: %s."):format(account.flexes, formatMoney(account.balance)))
        end

        return
    end

    local duration = math.max(0, os.time() - session.startedAt)
    local minutes = billableMinutes(duration)
    local cost = minutes * usageCost("callMinute")
    local ok, updated, spent = chargeAccount(account, cost)

    if not ok then
        notifyPhone(account, session.source, "Your ATNT balance ran out during the call.")
        pushAccount(session.source, account)
        return
    end

    if cfg().Calls and cfg().Calls.NotifyAfterCall then
        local charged = ("%d Flexes"):format(spent.flexes or 0)

        if (spent.balance or 0) > 0 then
            charged = ("%s + %s"):format(charged, formatMoney(spent.balance))
        end

        local text = ("Call ended. %s charged for %d min. Flexes: %d. Balance: %s."):format(
            charged,
            minutes,
            updated.flexes,
            formatMoney(updated.balance)
        )

        notifyPhone(updated, session.source, text)
    end

    pushAccount(session.source, updated)
end

CreateThread(function()
    if not enabled() then
        return
    end

    while not MySQL do
        Wait(250)
    end

    ensureTable()
    debugLog("ATNT accounts table is ready")
end)

lib.callback.register("atnt:server:get-dashboard", function(source, payload)
    local account, err = ensureAccount(source, payload)

    return {
        success = account ~= nil,
        error = err,
        account = account,
        config = publicConfig(source)
    }
end)

lib.callback.register("atnt:server:purchase-package", function(source, packageId)
    local package = getPackage(packageId)
    if not package then
        return {
            success = false,
            error = "Unknown package"
        }
    end

    local account, err = ensureAccount(source)
    if not account then
        return {
            success = false,
            error = err or "ATNT account unavailable"
        }
    end

    local price = roundMoney(package.price)
    if account.balance < price then
        return {
            success = false,
            account = account,
            error = "Insufficient balance"
        }
    end

    account.balance = roundMoney(account.balance - price)
    account.flexes = account.flexes + (tonumber(package.flexes) or 0)
    saveAccount(account)
    pushAccount(source, account)

    return {
        success = true,
        account = account,
        message = ("Purchased %s."):format(package.label)
    }
end)

lib.callback.register("atnt:server:top-up", function(source, payload)
    payload = payload or {}

    if not cfg().Recharge or cfg().Recharge.AllowSelfTopUp == false then
        return {
            success = false,
            error = "Recharge is disabled"
        }
    end

    local amount = tonumber(payload.amount)
    local code = payload.code

    if code and code ~= "" and cfg().Recharge.VoucherCodes then
        amount = tonumber(cfg().Recharge.VoucherCodes[string.upper(code)])
    end

    amount = roundMoney(amount)

    if amount <= 0 then
        return {
            success = false,
            error = "Invalid recharge amount"
        }
    end

    local account, err = ensureAccount(source)
    if not account then
        return {
            success = false,
            error = err or "ATNT account unavailable"
        }
    end

    account.balance = roundMoney(account.balance + amount)
    saveAccount(account)
    pushAccount(source, account)

    return {
        success = true,
        account = account,
        message = ("Added %s balance."):format(formatMoney(amount))
    }
end)

lib.callback.register("atnt:server:get-nearby-customers", function(source, playerIds)
    local allowed = canUseProviderPanel(source)
    if not allowed then
        return {
            success = false,
            error = "ATNT provider access denied"
        }
    end

    local panelCfg = cfg().ProviderPanel or {}
    local radius = tonumber(panelCfg.NearbyRadius) or 10.0
    local sourcePed = GetPlayerPed(source)
    local sourceCoords = sourcePed and sourcePed ~= 0 and GetEntityCoords(sourcePed)
    local customers = {}
    local seen = {}

    for _, playerId in ipairs(playerIds or {}) do
        local targetSource = tonumber(playerId)

        if targetSource and targetSource ~= source and not seen[targetSource] and GetPlayerPing(targetSource) > 0 then
            seen[targetSource] = true

            local includePlayer = true
            local targetPed = GetPlayerPed(targetSource)
            if sourceCoords and targetPed and targetPed ~= 0 then
                includePlayer = distanceBetween(sourceCoords, GetEntityCoords(targetPed)) <= (radius + 1.0)
            end

            if includePlayer then
                local phoneNumber = getPhoneNumberBySource(targetSource)

                if phoneNumber then
                    customers[#customers + 1] = {
                        source = targetSource,
                        name = getDisplayName(targetSource),
                        phoneNumber = phoneNumber
                    }
                end
            end
        end
    end

    table.sort(customers, function(first, second)
        return tostring(first.name):lower() < tostring(second.name):lower()
    end)

    return {
        success = true,
        customers = customers
    }
end)

lib.callback.register("atnt:server:provider-charge", function(source, payload)
    payload = payload or {}

    local allowed = canUseProviderPanel(source)
    if not allowed then
        return {
            success = false,
            error = "ATNT provider access denied"
        }
    end

    local panelCfg = cfg().ProviderPanel or {}
    local balance = roundMoney(tonumber(payload.balance or payload.amount) or 0)
    local flexes = math.floor(tonumber(payload.flexes) or 0)

    if balance > 0 and panelCfg.AllowBalanceCharge == false then
        return {
            success = false,
            error = "Balance charges are disabled"
        }
    end

    if flexes > 0 and panelCfg.AllowFlexCharge == false then
        return {
            success = false,
            error = "Flex charges are disabled"
        }
    end

    if balance <= 0 and flexes <= 0 then
        return {
            success = false,
            error = "Enter balance or Flexes"
        }
    end

    local targetAccount, err, targetSource = ensureAccountByPhoneNumber(payload.phoneNumber)
    if not targetAccount then
        return {
            success = false,
            error = err or "Customer account unavailable"
        }
    end

    targetAccount.balance = roundMoney((targetAccount.balance or 0) + math.max(0, balance))
    targetAccount.flexes = math.floor((targetAccount.flexes or 0) + math.max(0, flexes))
    saveAccount(targetAccount)

    if targetSource and targetSource > 0 then
        pushAccount(targetSource, targetAccount)
    end

    if panelCfg.NotifyTarget ~= false then
        local parts = {}

        if balance > 0 then
            parts[#parts + 1] = formatMoney(balance)
        end

        if flexes > 0 then
            parts[#parts + 1] = ("%d Flexes"):format(flexes)
        end

        notifyPhone(targetAccount, targetSource, ("ATNT recharge added: %s. Flexes: %d. Balance: %s."):format(
            table.concat(parts, " + "),
            targetAccount.flexes,
            formatMoney(targetAccount.balance)
        ))
    end

    local operatorAccount = ensureAccount(source)

    return {
        success = true,
        account = operatorAccount,
        targetAccount = targetAccount,
        message = ("Charged %s. Flexes: %d. Balance: %s."):format(
            targetAccount.phoneNumber or payload.phoneNumber,
            targetAccount.flexes,
            formatMoney(targetAccount.balance)
        )
    }
end)

lib.callback.register("atnt:server:set-data-enabled", function(source, enabledState)
    local account, err = ensureAccount(source)
    if not account then
        return {
            success = false,
            error = err or "ATNT account unavailable"
        }
    end

    account.dataEnabled = enabledState == true
    saveAccount(account)
    pushAccount(source, account)

    return {
        success = true,
        account = account
    }
end)

lib.callback.register("atnt:server:authorize-usage", function(source, usageType, payload)
    return authorizeUsage(source, usageType, payload)
end)

lib.callback.register("atnt:server:charge-usage", function(source, usageType, payload)
    return chargeUsage(source, usageType, payload)
end)

lib.callback.register("atnt:server:authorize-call", function(source, callData)
    return authorizeCall(source, callData)
end)

lib.callback.register("atnt:server:release-call", function(_, callId)
    return releaseCall(callId)
end)

RegisterNetEvent("yseries:server:answer-call", function(callData)
    markCallAnswered(callData)
end)

RegisterNetEvent("yseries:server:on-call-cancelled", function(callId)
    finalizeCall(callId)
end)

AddEventHandler("playerDropped", function()
    local droppedSource = source

    for callId, session in pairs(ActiveCalls) do
        if session.source == droppedSource then
            finalizeCall(callId)
        end
    end
end)

exports("ATNTGetAccount", function(source)
    return ensureAccount(source)
end)

exports("ATNTAddBalance", function(source, amount)
    local account = ensureAccount(source)
    if not account then
        return false
    end

    account.balance = roundMoney(account.balance + (tonumber(amount) or 0))
    saveAccount(account)
    pushAccount(source, account)
    return true, account
end)

exports("ATNTAddFlexes", function(source, flexes)
    local account = ensureAccount(source)
    if not account then
        return false
    end

    account.flexes = account.flexes + math.floor(tonumber(flexes) or 0)
    saveAccount(account)
    pushAccount(source, account)
    return true, account
end)
