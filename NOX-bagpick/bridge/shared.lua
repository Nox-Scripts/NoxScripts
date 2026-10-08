Bridge = Bridge or {}

local function detectFramework()
    local forced = Config.Framework
    if forced and forced ~= 'auto' then
        return forced
    end

    if GetResourceState('es_extended') == 'started' then
        return 'esx'
    end

    if GetResourceState('qbx_core') == 'started' then
        return 'qbox'
    end

    if GetResourceState('qb-core') == 'started' then
        return 'qbcore'
    end

    return 'none'
end

Bridge.Framework = detectFramework()

if Bridge.Framework == 'esx' then
    Bridge.Core = exports['es_extended']:getSharedObject()
elseif Bridge.Framework == 'qbox' then
    Bridge.Core = exports['qbx_core']:GetCoreObject()
elseif Bridge.Framework == 'qbcore' then
    Bridge.Core = exports['qb-core']:GetCoreObject()
end

if Config.Debug then
    print(('[Laugh] Framework detected: %s'):format(Bridge.Framework))
end
