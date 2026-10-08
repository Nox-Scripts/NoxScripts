-- Standalone replacement for the parts of prp-bridge that prp-dartboard uses.
-- Framework: qb-core. Nothing here needs prp-bridge to be installed or started.
--
-- Provides (same names/signatures the rest of the script already calls):
--   bridge.fw.getIdentifier(src)
--   bridge.fw.getSrcFromIdentifier(identifier)
--   bridge.fw.notify(src, type, message, title, duration)
--   bridge.fw.registerCommand(name, help, params, restrictedGroup, callback)
--   bridge.fw.addMoney / removeMoney / getMoney
--   bridge.log.send(webhookUrl, title, message, args)
-- and fires these local events for the rest of the resource:
--   prp-dartboard:server:playerLoad   (src)
--   prp-dartboard:server:playerUnload (src)

local QBCore = exports['qb-core']:GetCoreObject()

local fw = {}
local log = {}

---@param src number | string
---@return string?
function fw.getIdentifier(src)
    local player = QBCore.Functions.GetPlayer(tonumber(src) or src)
    if not player or not player.PlayerData then
        return nil
    end

    return player.PlayerData.citizenid
end

---@param identifier string
---@return number?
function fw.getSrcFromIdentifier(identifier)
    local player = QBCore.Functions.GetPlayerByCitizenId(identifier)
    if not player or not player.PlayerData then
        return nil
    end

    return player.PlayerData.source
end

---@param src number | string
---@param type 'inform' | 'error' | 'success' | 'warning'
---@param message string
---@param title? string
---@param duration? number
function fw.notify(src, type, message, title, duration)
    TriggerClientEvent("prp-dartboard:client:notify", src, type, message, title, duration)
end

-- True when the player is a QBCore admin or god (works with stock qb-core permissions,
-- no server.cfg / permissions.cfg changes needed).
---@param src number | string
---@return boolean
function fw.isQbAdmin(src)
    src = tonumber(src)
    if not src or src <= 0 then
        return false
    end

    for _, permission in ipairs({ "god", "admin" }) do
        local ok, allowed = pcall(QBCore.Functions.HasPermission, src, permission)
        if ok and allowed then
            return true
        end
    end

    return false
end

---@param commandName string
---@param helpText string
---@param params table?
---@param restrictedGroup string?
---@param callback fun(src: number, args: table, rawCommand: string)
function fw.registerCommand(commandName, helpText, params, restrictedGroup, callback)
    lib.addCommand(commandName, {
        help = helpText,
        params = params,
        restricted = restrictedGroup,
    }, callback)
end

-- The dartboard treats a truthy return as "money was actually added/removed"
-- and queues a database payout otherwise, so only ever return a real boolean.

---@param src number | string
---@param moneyType "cash" | "bank" | "crypto"
---@param moneyAmount number
---@param reason string | nil
---@return boolean
function fw.addMoney(src, moneyType, moneyAmount, reason)
    local player = QBCore.Functions.GetPlayer(tonumber(src) or src)
    if not player then return false end

    return player.Functions.AddMoney(moneyType, moneyAmount, reason) == true
end

---@param src number | string
---@param moneyType "cash" | "bank" | "crypto"
---@param moneyAmount number
---@param reason string | nil
---@return boolean
function fw.removeMoney(src, moneyType, moneyAmount, reason)
    local player = QBCore.Functions.GetPlayer(tonumber(src) or src)
    if not player then return false end

    return player.Functions.RemoveMoney(moneyType, moneyAmount, reason) == true
end

---@param src number | string
---@param moneyType "cash" | "bank" | "crypto"
---@return number
function fw.getMoney(src, moneyType)
    local player = QBCore.Functions.GetPlayer(tonumber(src) or src)
    if not player then return 0 end

    return tonumber(player.Functions.GetMoney(moneyType)) or 0
end

-- Discord webhook logging ---------------------------------------------------

local LOG_COLOR = 5814783

---@param webhookUrl string
---@param title string
---@param message string
---@param args? table<string, any>
function log.send(webhookUrl, title, message, args)
    if type(webhookUrl) ~= "string" or webhookUrl == "" then
        return
    end

    local description = message

    if args then
        description = description .. "\n\n"
        for k, v in pairs(args) do
            description = description .. ("**%s**: %s\n"):format(k, v)
        end
    end

    local payload = {
        embeds = {
            {
                title = title,
                description = description,
                color = LOG_COLOR,
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                footer = { text = ("Resource: %s"):format(GetCurrentResourceName()) },
            },
        },
    }

    PerformHttpRequest(webhookUrl, function(statusCode)
        if statusCode ~= 204 and statusCode ~= 200 then
            print(("[%s] Discord webhook request failed (HTTP %s)"):format(GetCurrentResourceName(), tostring(statusCode)))
        end
    end, "POST", json.encode(payload), { ["Content-Type"] = "application/json" })
end

-- Character load / unload lifecycle -----------------------------------------

-- Fired by qb-spawn / qb-apartments once the character has actually spawned.
RegisterNetEvent("QBCore:Server:OnPlayerLoaded", function()
    local src = tonumber(source)
    if not src or src <= 0 then
        return
    end

    if not fw.getIdentifier(src) then
        return
    end

    TriggerEvent("prp-dartboard:server:playerLoad", src)
end)

-- Fired by qb-core on logout / character switch.
AddEventHandler("QBCore:Server:OnPlayerUnload", function(src)
    src = tonumber(src)
    if not src or src <= 0 then
        return
    end

    TriggerEvent("prp-dartboard:server:playerUnload", src)
end)

bridge = {
    fw = fw,
    log = log,
}
