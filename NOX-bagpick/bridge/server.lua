function Bridge.GetPlayer(src)
    if Bridge.Framework == 'esx' then
        return Bridge.Core.GetPlayerFromId(src)
    end

    if Bridge.Framework == 'qbox' or Bridge.Framework == 'qbcore' then
        return Bridge.Core.Functions.GetPlayer(src)
    end

    return nil
end

function Bridge.PlayerExists(src)
    return Bridge.GetPlayer(src) ~= nil
end

function Bridge.GetOnlinePlayers()
    if Bridge.Framework == 'esx' then
        return Bridge.Core.GetPlayers()
    end

    if Bridge.Framework == 'qbox' or Bridge.Framework == 'qbcore' then
        return Bridge.Core.Functions.GetPlayers()
    end

    return {}
end

function Bridge.GetPlayerJob(src)
    local player = Bridge.GetPlayer(src)
    if not player then return nil end

    if Bridge.Framework == 'esx' then
        return player.job and player.job.name
    end

    if Bridge.Framework == 'qbox' or Bridge.Framework == 'qbcore' then
        return player.PlayerData.job and player.PlayerData.job.name
    end
end

function Bridge.GetPlayerName(src)
    local player = Bridge.GetPlayer(src)

    if Bridge.Framework == 'esx' and player then
        return player.getName()
    end

    if (Bridge.Framework == 'qbox' or Bridge.Framework == 'qbcore') and player then
        local info = player.PlayerData.charinfo
        return info and (info.firstname .. ' ' .. info.lastname) or GetPlayerName(src)
    end

    return GetPlayerName(src)
end

function Bridge.GetPlayerCoords(src)
    return GetEntityCoords(GetPlayerPed(src))
end

--- moneyType: 'money' | 'black_money'. On QBox/QBCore, black_money maps to the 'crypto' account
function Bridge.AddMoney(src, amount, moneyType)
    moneyType = moneyType or 'money'
    local player = Bridge.GetPlayer(src)
    if not player then return false end

    if Bridge.Framework == 'esx' then
        if moneyType == 'black_money' then
            player.addAccountMoney('black_money', amount)
        else
            player.addMoney(amount)
        end
        return true
    end

    if Bridge.Framework == 'qbox' or Bridge.Framework == 'qbcore' then
        local account = (moneyType == 'black_money') and 'crypto' or 'cash'
        player.Functions.AddMoney(account, amount, 'bagpick')
        return true
    end

    return false
end

-- Prioritize ox_inventory (framework-independent) then fall back to the active framework
function Bridge.AddItem(src, item, amount)
    if GetResourceState('ox_inventory') == 'started' then
        local ok, success = pcall(function()
            return exports.ox_inventory:AddItem(src, item, amount)
        end)
        return ok and success and true or false
    end

    local player = Bridge.GetPlayer(src)
    if not player then return false end

    if Bridge.Framework == 'esx' then
        if player.canCarryItem and not player.canCarryItem(item, amount) then
            return false
        end
        player.addInventoryItem(item, amount)
        return true
    end

    if Bridge.Framework == 'qbox' or Bridge.Framework == 'qbcore' then
        local ok, success = pcall(function()
            return player.Functions.AddItem(item, amount)
        end)
        if not ok then
            print(('[bagpick] AddItem failed for item "%s" - it is probably missing from your items table. Error: %s'):format(item, success))
            return false
        end
        return success and true or false
    end

    return false
end

-- Delegates display to the client's Bridge.Notify (the server doesn't know the client's framework)
function Bridge.Notify(src, message, duration)
    TriggerClientEvent('bagpick:bridge:notify', src, message, duration)
end

-- Generic client -> server -> client callback, framework-independent
local callbacks = {}

function Bridge.RegisterCallback(name, handler)
    callbacks[name] = handler
end

RegisterNetEvent('bagpick:bridge:callback')
AddEventHandler('bagpick:bridge:callback', function(name, id, ...)
    local src = source
    local handler = callbacks[name]
    if not handler then return end
    handler(src, function(...)
        TriggerClientEvent('bagpick:bridge:callbackResult', src, id, ...)
    end, ...)
end)
