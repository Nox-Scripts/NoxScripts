local QBCore = exports['qb-core']:GetCoreObject()

local propState = {}      -- [key] = { uses = n }
local playerCooldown = {} -- [source] = os.time() they can next act
local shiftState = {}     -- [source] = { active = bool, scrapCount = n, earnings = n }

local COOLDOWN_SECONDS = 2
local MAX_DISTANCE = 4.0 -- player-to-prop distance

-- ============================================================
-- HELPERS
-- ============================================================

-- props aren't ours (they're existing map entities), so track state by
-- rounded world position instead of an owned id/handle
local function keyFor(kind, coords)
    return string.format('%s:%.1f:%.1f:%.1f', kind, coords.x, coords.y, coords.z)
end

local function getState(kind, coords)
    local key = keyFor(kind, coords)
    if not propState[key] then
        propState[key] = { uses = kind == 'car' and Config.MaxUsesPerWreck or Config.MaxUsesPerTire }
    end
    return propState[key], key
end

local function rollLoot()
    local totalWeight = 0
    for _, entry in ipairs(Config.LootTable) do
        totalWeight = totalWeight + entry.weight
    end

    local roll = math.random(1, totalWeight)
    local cumulative = 0
    for _, entry in ipairs(Config.LootTable) do
        cumulative = cumulative + entry.weight
        if roll <= cumulative then
            local amount = math.random(entry.min, entry.max)
            return entry.item, amount
        end
    end

    return Config.LootTable[1].item, 1
end

local function giveItem(source, item, amount)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end

    local added = Player.Functions.AddItem(item, amount)
    if added then
        TriggerClientEvent('qb-inventory:client:ItemBox', source, QBCore.Shared.Items[item], 'add', amount)
    end
    return added
end

local function scheduleRespawn(key, kind)
    SetTimeout(Config.RespawnMinutes * 60000, function()
        local state = propState[key]
        if not state then return end
        state.uses = kind == 'car' and Config.MaxUsesPerWreck or Config.MaxUsesPerTire
    end)
end

-- ============================================================
-- MAIN CALLBACK
-- kind = 'car' | 'tire', coords = vector3 of the specific prop the player hit
-- ============================================================
QBCore.Functions.CreateCallback('scrapyard_job:server:extract', function(source, cb, kind, coords)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb(false, 'Something went wrong.') end

    if kind ~= 'car' and kind ~= 'tire' then
        return cb(false, 'Invalid target.')
    end

    if Config.RequiredJob and Player.PlayerData.job.name ~= Config.RequiredJob then
        return cb(false, 'You are not able to do this.')
    end

    if Config.RequireShiftToExtract and (not shiftState[source] or not shiftState[source].active) then
        return cb(false, 'Start your shift first.')
    end

    -- per-player rate limit
    local now = os.time()
    if playerCooldown[source] and playerCooldown[source] > now then
        return cb(false, 'You are working too fast.')
    end
    playerCooldown[source] = now + COOLDOWN_SECONDS

    -- fence to the job zone - the client sent us real prop coords, but that
    -- prop could be anywhere on the map matching that model, so confirm it's
    -- actually inside the scrapyard before paying out
    local zoneCenter = vector3(Config.StartCoords.x, Config.StartCoords.y, Config.StartCoords.z)
    if #(coords - zoneCenter) > Config.JobRadius then
        return cb(false, 'That is outside the scrapyard.')
    end

    -- distance check: player must actually be standing at the coords they claim
    local ped = GetPlayerPed(source)
    if ped == 0 then return cb(false, 'Something went wrong.') end
    local pCoords = GetEntityCoords(ped)
    if #(pCoords - coords) > MAX_DISTANCE then
        return cb(false, 'You are too far away.')
    end

    local state, key = getState(kind, coords)
    if state.uses <= 0 then
        return cb(false, 'This has already been picked clean.')
    end

    state.uses = state.uses - 1
    if state.uses <= 0 then
        scheduleRespawn(key, kind)
    end

    if kind == 'car' then
        local item, amount = rollLoot()
        giveItem(source, item, amount)
        Player.Functions.AddMoney(Config.PayAccount, Config.PayPerCar, 'scrapyard-job')

        if shiftState[source] and shiftState[source].active then
            shiftState[source].scrapCount = shiftState[source].scrapCount + 1
            shiftState[source].earnings = shiftState[source].earnings + Config.PayPerCar
            TriggerClientEvent('scrapyard_job:client:updateShiftUI', source, shiftState[source].scrapCount, shiftState[source].earnings)
        end

        local label = (QBCore.Shared.Items[item] and QBCore.Shared.Items[item].label) or item
        return cb(true, ('Extracted scrap - got $%d and %dx %s'):format(Config.PayPerCar, amount, label))
    else
        local amount = math.random(Config.TireLootMin, Config.TireLootMax)
        giveItem(source, 'rubber', amount)
        return cb(true, ('Pulled %dx Rubber'):format(amount))
    end
end)

-- ============================================================
-- SHIFT START / END
-- ============================================================
RegisterNetEvent('scrapyard_job:server:startShift', function()
    local source = source
    if shiftState[source] and shiftState[source].active then return end
    shiftState[source] = { active = true, scrapCount = 0, earnings = 0 }
    TriggerClientEvent('scrapyard_job:client:shiftStarted', source)
end)

RegisterNetEvent('scrapyard_job:server:endShift', function()
    local source = source
    local state = shiftState[source]
    if not state or not state.active then return end
    state.active = false
    TriggerClientEvent('scrapyard_job:client:shiftEnded', source, state.scrapCount, state.earnings)
end)

-- ============================================================
-- CLEANUP ON DISCONNECT
-- ============================================================
AddEventHandler('playerDropped', function()
    playerCooldown[source] = nil
    shiftState[source] = nil
end)
