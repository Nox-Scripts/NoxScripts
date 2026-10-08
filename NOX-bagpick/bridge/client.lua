function Bridge.Notify(message, duration)
    if message == nil or message == '' then return end
    duration = duration or 5000

    if Bridge.Framework == 'esx' then
        Bridge.Core.ShowNotification(tostring(message), 'info', duration)
        return
    end

    if Bridge.Framework == 'qbox' or Bridge.Framework == 'qbcore' then
        Bridge.Core.Functions.Notify(tostring(message), 'primary', duration)
        return
    end

    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message))
    EndTextCommandThefeedPostTicker(false, true)
end

-- The server doesn't know the client's framework (delegates display via this event)
RegisterNetEvent('bagpick:bridge:notify')
AddEventHandler('bagpick:bridge:notify', function(message, duration)
    Bridge.Notify(message, duration)
end)

function Bridge.ShowHelpNotification(message)
    SetTextComponentFormat('STRING')
    AddTextComponentString(message)
    DisplayHelpTextFromStringLabel(0, 0, 1, -1)
end

function Bridge.GetClosestPed(coords)
    local pedPool = GetGamePool('CPed')
    local playerPed = PlayerPedId()
    local closestPed, closestDist = nil, -1
    for _, ped in ipairs(pedPool) do
        if ped ~= playerPed and DoesEntityExist(ped) then
            local dist = #(coords - GetEntityCoords(ped))
            if closestDist == -1 or dist < closestDist then
                closestPed = ped
                closestDist = dist
            end
        end
    end
    return closestPed, closestDist
end

local callbackId = 0
local pendingCallbacks = {}

RegisterNetEvent('bagpick:bridge:callbackResult')
AddEventHandler('bagpick:bridge:callbackResult', function(id, ...)
    local cb = pendingCallbacks[id]
    if cb then
        pendingCallbacks[id] = nil
        cb(...)
    end
end)

function Bridge.TriggerCallback(name, cb, ...)
    callbackId = callbackId + 1
    local id = callbackId
    pendingCallbacks[id] = cb
    TriggerServerEvent('bagpick:bridge:callback', name, id, ...)
end
