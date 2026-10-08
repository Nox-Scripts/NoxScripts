local QBCore = exports['qb-core']:GetCoreObject()

local busy = false
local onShift = false

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    RequestModel(hash)
    local timeout = 0
    while not HasModelLoaded(hash) and timeout < 5000 do
        Wait(10)
        timeout = timeout + 10
    end
    return hash
end

-- ============================================================
-- SHIFT COUNTER UI (ox_lib text UI - kept to plain text, no custom NUI)
-- ============================================================
local function updateShiftUI(scrapCount, earnings)
    -- ox_lib only supports right-center/left-center/top-center/bottom-center,
    -- no true corners - left-center is the closest to bottom-left
    lib.showTextUI(('Scrap Extracted: %d | Earned This Shift: $%d'):format(scrapCount, earnings), {
        position = 'left-center',
        icon = 'trash',
    })
end

RegisterNetEvent('scrapyard_job:client:shiftStarted', function()
    onShift = true
    updateShiftUI(0, 0)
end)

RegisterNetEvent('scrapyard_job:client:shiftEnded', function(scrapCount, earnings)
    onShift = false
    lib.hideTextUI()
    lib.notify({
        title = 'Scrapyard',
        description = ('Shift ended - %dx cars, $%d earned'):format(scrapCount, earnings),
        type = 'inform',
    })
end)

RegisterNetEvent('scrapyard_job:client:updateShiftUI', function(scrapCount, earnings)
    updateShiftUI(scrapCount, earnings)
end)

-- ============================================================
-- BLIP
-- ============================================================
local function createBlip()
    local blip = AddBlipForCoord(Config.StartCoords.x, Config.StartCoords.y, Config.StartCoords.z)
    SetBlipSprite(blip, Config.Blip.sprite)
    SetBlipColour(blip, Config.Blip.color)
    SetBlipScale(blip, Config.Blip.scale)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(Config.Blip.label)
    EndTextCommandSetBlipName(blip)
end

-- ============================================================
-- EXTRACT LOGIC
-- entity = the specific existing map prop qb-target hit with its raycast
-- ============================================================
local function doExtract(kind, entity)
    if busy then return end
    if not entity or not DoesEntityExist(entity) then return end
    if Config.RequireShiftToExtract and not onShift then
        lib.notify({ title = 'Scrapyard', description = 'Start your shift first.', type = 'error' })
        return
    end
    busy = true

    local duration = kind == 'car' and Config.ExtractDuration or Config.TireExtractDuration
    local label = kind == 'car' and 'Stripping parts from wreck...' or 'Pulling scrap rubber...'

    local success = lib.progressBar({
        duration = duration,
        label = label,
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true, mouse = false },
        anim = { dict = Config.ExtractAnim.dict, clip = Config.ExtractAnim.clip, flag = Config.ExtractAnim.flag },
        prop = {
            model = Config.ExtractProp.model,
            bone = Config.ExtractProp.bone,
            pos = Config.ExtractProp.pos,
            rot = Config.ExtractProp.rot,
        },
    })

    busy = false
    if not success then return end
    if not DoesEntityExist(entity) then return end -- prop could've been deleted mid-animation

    local coords = GetEntityCoords(entity)

    QBCore.Functions.TriggerCallback('scrapyard_job:server:extract', function(ok, reason)
        if ok then
            lib.notify({ title = 'Scrapyard', description = reason, type = 'success' })
        else
            lib.notify({ title = 'Scrapyard', description = reason, type = 'error' })
        end
    end, kind, coords)
end

-- ============================================================
-- START JOB NPC
-- ============================================================
local npcPed = nil

local function spawnNPC()
    local hash = loadModel(Config.NPCModel)
    if not HasModelLoaded(hash) then return end

    local ped = CreatePed(4, hash, Config.StartCoords.x, Config.StartCoords.y, Config.StartCoords.z - 1.0, Config.StartCoords.w, false, true)

    RequestCollisionAtCoord(Config.StartCoords.x, Config.StartCoords.y, Config.StartCoords.z)
    local timeout = 0
    while not HasCollisionLoadedAroundEntity(ped) and timeout < 2000 do
        RequestCollisionAtCoord(Config.StartCoords.x, Config.StartCoords.y, Config.StartCoords.z)
        Wait(50)
        timeout = timeout + 50
    end

    PlaceObjectOnGroundProperly(ped)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedDiesWhenInjured(ped, false)
    SetPedCanBeTargetted(ped, false)
    TaskStartScenarioInPlace(ped, Config.NPCScenario, 0, true)
    SetModelAsNoLongerNeeded(hash)

    exports['qb-target']:AddTargetEntity(ped, {
        options = {
            {
                icon = 'fas fa-play',
                label = 'Start Shift',
                canInteract = function() return not onShift end,
                action = function()
                    TriggerServerEvent('scrapyard_job:server:startShift')
                end,
            },
            {
                icon = 'fas fa-stop',
                label = 'End Shift',
                canInteract = function() return onShift end,
                action = function()
                    TriggerServerEvent('scrapyard_job:server:endShift')
                end,
            },
        },
        distance = Config.TargetDistance,
    })

    npcPed = ped
end

-- ============================================================
-- TARGET SETUP - applies to every existing prop on the map that
-- matches these models, no spawning needed
-- ============================================================
CreateThread(function()
    createBlip()
    spawnNPC()

    exports['qb-target']:AddTargetModel(Config.WreckModels, {
        options = {
            {
                icon = 'fas fa-tools',
                label = 'Extract Scrap',
                action = function(entity)
                    doExtract('car', entity)
                end,
            },
        },
        distance = Config.TargetDistance,
    })

    exports['qb-target']:AddTargetModel(Config.TireModels, {
        options = {
            {
                icon = 'fas fa-circle-notch',
                label = 'Pull Rubber',
                action = function(entity)
                    doExtract('tire', entity)
                end,
            },
        },
        distance = Config.TargetDistance,
    })
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if onShift then lib.hideTextUI() end
    if npcPed and DoesEntityExist(npcPed) then DeleteEntity(npcPed) end
end)

-- ============================================================
-- DEV HELPER: print your current coords (handy for tuning Config.StartCoords
-- / Config.JobRadius against your actual scrapyard layout)
-- ============================================================
RegisterCommand('scrapcoords', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local line = string.format(
        'vector4(%.2f, %.2f, %.2f, %.2f)',
        coords.x, coords.y, coords.z, heading
    )
    print(line)
    TriggerEvent('chat:addMessage', {
        color = { 255, 165, 0 },
        multiline = true,
        args = { 'Scrapyard', line .. ' (also printed to F8 console)' }
    })
end, false)
