local resourceName = GetCurrentResourceName()
local resourceVersion = GetResourceMetadata(resourceName, 'version', 0) or 'unknown'

-- =============================================
-- RESOURCE LIFECYCLE
-- =============================================

AddEventHandler('onResourceStart', function(resource)
    if resource ~= resourceName then return end

    local vehicleCount = 0
    if Config and Config.allowedVehicles then
        for _ in pairs(Config.allowedVehicles) do
            vehicleCount = vehicleCount + 1
        end
    end

    print('^2[TrapRepublic-BikeTrikz]^0 ─────────────────────────────────')
    print('^2[TrapRepublic-BikeTrikz]^0  Auto Wheelie + Shift-Arrow Trick Poses')
    print('^2[TrapRepublic-BikeTrikz]^0  Version:             ' .. resourceVersion)
    print('^2[TrapRepublic-BikeTrikz]^0  AllowAllBikes:       ' .. tostring(Config.AllowAllBikes))
    print('^2[TrapRepublic-BikeTrikz]^0  Whitelisted Vehicles: ' .. vehicleCount)
    print('^2[TrapRepublic-BikeTrikz]^0  Minimum Speed:       ' .. Config.minimumSpeed .. ' km/h')
    print('^2[TrapRepublic-BikeTrikz]^0  Helmet:              ' .. tostring(Config.helmet))
    print('^2[TrapRepublic-BikeTrikz]^0  Status:              ^2Loaded^0')
    print('^2[TrapRepublic-BikeTrikz]^0 ─────────────────────────────────')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= resourceName then return end
    print('^1[TrapRepublic-BikeTrikz]^0 Resource Stopped.')
end)

-- =============================================
-- ADMIN COMMAND
-- =============================================

RegisterCommand('biketrikz', function(source, args, rawCommand)
    local src = source

    local statusLine = 'v' .. resourceVersion
        .. ' | AllowAllBikes: ' .. tostring(Config.AllowAllBikes)
        .. ' | MinSpeed: ' .. Config.minimumSpeed .. ' km/h'
        .. ' | Helmet: ' .. tostring(Config.helmet)

    if src == 0 then
        print('^2[TrapRepublic-BikeTrikz]^0 ' .. statusLine)
        return
    end

    if IsPlayerAceAllowed(src, 'command.biketrikz') then
        TriggerClientEvent('chat:addMessage', src, {
            color = {0, 255, 128},
            args  = {'[TrapRepublic-BikeTrikz]', statusLine},
        })
    end
end, true)
