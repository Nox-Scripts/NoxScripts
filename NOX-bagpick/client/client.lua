local bagpickEnabled = false

local npcs = {}
local closestPed, chosenPed
local canInteract = false

local droppedBags = {}
local BAG_MODEL = GetHashKey('prop_beachbag_02')

local obj, obj2, obj3

-- perf (avoid re-reading globals on every call)
local Wait = Wait
local PlayerPedId = PlayerPedId
local GetEntityCoords = GetEntityCoords

local function MakeEntityFaceEntity(entity1, entity2)
    local p1 = GetEntityCoords(entity1, true)
    local p2 = GetEntityCoords(entity2, true)

    local dx = p2.x - p1.x
    local dy = p2.y - p1.y

    local heading = GetHeadingFromVector_2d(dx, dy)
    SetEntityHeading(entity1, heading)
end

-- Loads an anim dict with a timeout so a bad/missing dict can never hang this thread forever
local function LoadAnimDict(dict, timeoutMs)
    timeoutMs = timeoutMs or 5000
    RequestAnimDict(dict)
    local waited = 0
    while not HasAnimDictLoaded(dict) and waited < timeoutMs do
        Wait(10)
        waited = waited + 10
    end
    return HasAnimDictLoaded(dict)
end

Citizen.CreateThread(function()
    while true do
        if bagpickEnabled then
            local playerPed = PlayerPedId()
            local coords = GetEntityCoords(playerPed)
            closestPed = Bridge.GetClosestPed(coords)
            Wait(500)
        else
            closestPed = nil
            Wait(2000)
        end
    end
end)

RegisterNetEvent('bagpick:client:npcPhoneDistraction')
AddEventHandler('bagpick:client:npcPhoneDistraction', function(chosenPed)
    if not LoadAnimDict("cellphone@") then return end
    TaskPlayAnim(chosenPed, "cellphone@", "cellphone_text_read_base", 2.0, 2.0, -1, 51, 0, false, false, false)
    Citizen.Wait(5000)
    ClearPedTasks(chosenPed)
end)

local holdingBag = false

RegisterNetEvent('bagpick:client:startTheft')
AddEventHandler('bagpick:client:startTheft', function(chosenPed)
    TriggerServerEvent('laugh_bagpick:npcBusy', NetworkGetNetworkIdFromEntity(chosenPed))

    if not LoadAnimDict('melee@unarmed@streamed_variations') then
        TriggerServerEvent('laugh_bagpick:npcFreed', NetworkGetNetworkIdFromEntity(chosenPed))
        return
    end
    if not LoadAnimDict('anim@heists@narcotics@trash') then
        TriggerServerEvent('laugh_bagpick:npcFreed', NetworkGetNetworkIdFromEntity(chosenPed))
        return
    end
    if not LoadAnimDict('missfbi3_toothpull') then
        TriggerServerEvent('laugh_bagpick:npcFreed', NetworkGetNetworkIdFromEntity(chosenPed))
        return
    end

    Wait(500)
    ClearPedTasks(chosenPed)
    ClearPedTasks(PlayerPedId())
    SetEntityAsMissionEntity(chosenPed)
    MakeEntityFaceEntity(PlayerPedId(), chosenPed)
    MakeEntityFaceEntity(chosenPed, PlayerPedId())
    Wait(100)

    local heading = GetEntityHeading(chosenPed)
    local pedCoords = GetEntityCoords(chosenPed)

    local off = Config.BagpickAnimOffset or { x = 0.0, y = 1.0, z = 0.0 }
    local headOff = Config.BagpickAnimHeadingOffset or -170
    local offsetCoords = GetOffsetFromEntityInWorldCoords(chosenPed, off.x, off.y, off.z)

    local groundZ = offsetCoords.z
    local success, z = GetGroundZFor_3dCoord(offsetCoords.x, offsetCoords.y, pedCoords.z + 1.0, true)
    if success and z then groundZ = z end

    SetEntityCoordsNoOffset(PlayerPedId(), offsetCoords.x, offsetCoords.y, groundZ, false, false, false)
    SetEntityHeading(PlayerPedId(), (heading + headOff) % 360.0)

    PlayAmbientSpeech1(chosenPed, 'GENERIC_SHOCKED_HIGH', 'SPEECH_PARAMS_FORCE_SHOUTED_CRITICAL')
    TaskPlayAnim(PlayerPedId(), 'missfbi3_toothpull', "pull_tooth_loop_player", 8.0, 1.0, -1, 1, 0, 0, 0, 0)
    TaskPlayAnim(chosenPed, 'missfbi3_toothpull', "pull_tooth_loop_player", 8.0, 1.0, -1, 1, 0, 0, 0)
    obj = CreateObject(GetHashKey('prop_beachbag_02'), 0, 0, 0, true)
    AttachEntityToEntity(obj, PlayerPedId(), GetPedBoneIndex(PlayerPedId(), 28422), -0.07, 0.00, 0.07, 0.0, 108.5, 0, 1, 1, 0, 1, 0, 1)

    local totalTirsacTime = math.random(Config.Tirsacmintime, Config.Tirsacmaxtime)
    Wait(totalTirsacTime)
    local chanceReussite = (math.random(1, 100) <= Config.reussitesac)

    DeleteEntity(obj)
    if chanceReussite then
        ClearPedTasks(PlayerPedId())
        ClearPedTasks(chosenPed)
        holdingBag = true
        -- Only the server decides and grants the reward (token set here on success)
        TriggerServerEvent('laugh_bagpick:theftSuccess')
        handleHeldBagLoop()
        TaskPlayAnim(PlayerPedId(), 'anim@heists@narcotics@trash', 'walk', 8.0, -1.0, -1, 49, 0, 0, 0, 0)
        obj2 = CreateObject(GetHashKey('prop_beachbag_02'), 0, 0, 0, true)
        AttachEntityToEntity(obj2, PlayerPedId(), GetPedBoneIndex(PlayerPedId(), 28422), -0.02, 0.00, -0.28, 0.00, 2.4, -58.05, 1, 1, 0, 1, 0, 1)
        Wait(100)
        PlayAmbientSpeech1(chosenPed, 'FALL_BACK', 'SPEECH_PARAMS_FORCE_SHOUTED_CRITICAL')
        SetPedToRagdoll(chosenPed, 3000, 3000, 0, 0, 0, 0)
        ClearPedTasks(chosenPed)
        SetPedAsNoLongerNeeded(chosenPed)
        Wait(3000)
    else
        ClearPedTasks(PlayerPedId())
        ClearPedTasks(chosenPed)
        SetPedAsNoLongerNeeded(chosenPed)
        PlayAmbientSpeech1(chosenPed, 'STAY_DOWN', 'SPEECH_PARAMS_FORCE')
        TaskPlayAnim(chosenPed, 'melee@unarmed@streamed_variations', "plyr_takedown_front_slap", 8.0, 1.0, -1, 1, 0, 0, 0, 0)
        Wait(450)
        ClearPedTasks(chosenPed)
        Wait(450)
        if math.random(1, 100) <= 30 then
            TriggerEvent('bagpick:client:npcPhoneDistraction', chosenPed)
            SetEntityAsNoLongerNeeded(chosenPed)
        end
        SetPedToRagdoll(PlayerPedId(), 5000, 5000, 0, 0, 0, 0)
    end

    TriggerServerEvent('laugh_bagpick:npcFreed', NetworkGetNetworkIdFromEntity(chosenPed))

    -- Free the ped from the local "already targeted" table now that the theft is over,
    -- otherwise this ped handle can never be selected as a target again for the rest
    -- of the session (memory leak + a permanently-skipped NPC).
    npcs[chosenPed] = nil
end)

function handleHeldBagLoop()
    Citizen.CreateThread(function()
        while holdingBag do
            local ped = PlayerPedId()
            if not IsEntityPlayingAnim(ped, 'anim@heists@narcotics@trash', 'walk', 3) then
                TaskPlayAnim(ped, 'anim@heists@narcotics@trash', 'walk', 8.0, -1.0, -1, 49, 0, false, false, false)
            end
            SetTextComponentFormat('STRING')
            AddTextComponentString(_U('carryPrompt'))
            DisplayHelpTextFromStringLabel(0, 0, 1, -1)
            -- Drop key = let go of the bag
            if IsControlJustPressed(1, Config.Keys.Drop) then
                local ped = PlayerPedId()
                local coords = GetEntityCoords(ped)
                local dropCoords = vector3(coords.x, coords.y, coords.z - 0.78)
                holdingBag = false
                if obj2 and DoesEntityExist(obj2) then DeleteEntity(obj2) end
                obj2 = nil
                StopAnimTask('anim@heists@narcotics@trash', 'walk', false)
                ClearPedTasks(ped)
                TriggerServerEvent('laugh_bagpick:dropBag', dropCoords)
                Bridge.Notify('~b~Bag dropped on the ground.')
                break
            end
            if IsPedDeadOrDying(PlayerPedId()) then
                holdingBag = false
                DeleteEntity(obj2)
                StopAnimTask('anim@amb@nightclub@peds@', 'rcmme_amanda1_stand_loop_cop', false)
                ClearPedTasks(PlayerPedId())
                break
            end
            -- Search key = search the bag while holding it
            if IsControlJustPressed(1, Config.Keys.Search) then
                holdingBag = false
                StopAnimTask('anim@amb@nightclub@peds@', 'rcmme_amanda1_stand_loop_cop', false)
                ClearPedTasks(PlayerPedId())
                DetachEntity(obj2)
                DeleteEntity(obj2)
                obj2 = nil
                searchBagInHand()
                break
            end
            Wait(0)
        end
    end)
end

local function cleanupNearbyBagProps(coords, radius)
    radius = radius or 0.8
    local objects = GetGamePool('CObject')
    for _, obj in ipairs(objects) do
        if DoesEntityExist(obj) and GetEntityModel(obj) == BAG_MODEL then
            local opos = GetEntityCoords(obj)
            if #(vector3(coords.x, coords.y, coords.z) - opos) <= radius then
                SetEntityAsMissionEntity(obj, true, true)
                FreezeEntityPosition(obj, false)
                DeleteEntity(obj)
            end
        end
    end
end

-- Each client spawns its own local prop on receiving the event: no networked entity to manage
local function createDroppedBag(bagId, x, y, z)
    local coords = vector3(x, y, z)
    local existing = droppedBags[bagId]
    if existing and existing.prop and DoesEntityExist(existing.prop) then return end

    cleanupNearbyBagProps(coords, 0.8)
    RequestModel(BAG_MODEL)
    local timeout = 0
    while not HasModelLoaded(BAG_MODEL) and timeout < 100 do Wait(10) timeout = timeout + 1 end
    if not HasModelLoaded(BAG_MODEL) then return end
    local prop = CreateObject(BAG_MODEL, x, y, z, true, true, false)
    SetModelAsNoLongerNeeded(BAG_MODEL)
    if not prop or prop == 0 then return end
    FreezeEntityPosition(prop, true)
    SetEntityAsMissionEntity(prop, true, true)
    droppedBags[bagId] = { prop = prop, coords = coords }
end

local function removeDroppedBag(bagId)
    local data = droppedBags[bagId]
    if not data then return end
    if data.prop and DoesEntityExist(data.prop) then
        SetEntityAsMissionEntity(data.prop, true, true)
        FreezeEntityPosition(data.prop, false)
        DeleteEntity(data.prop)
        SetTimeout(100, function()
            if DoesEntityExist(data.prop) then
                SetEntityAsMissionEntity(data.prop, true, true)
                DeleteEntity(data.prop)
            end
        end)
    end
    droppedBags[bagId] = nil
end

function searchBagInHand()
    holdingBag = false
    Citizen.Wait(200)
    ClearPedTasks(PlayerPedId())
    local player = GetEntityCoords(PlayerPedId(), true)

    local groundZ = 0
    local success, groundZ = GetGroundZFor_3dCoord(player.x + 0.5, player.y + 0.5, player.z, true)

    obj3 = CreateObject(GetHashKey('prop_beachbag_02'), player.x + 0.5, player.y + 0.5, success and groundZ or player.z - 0.5, true)

    if not PlaceObjectOnGroundProperly(obj3) then
        local objCoords = GetEntityCoords(obj3)
        SetEntityCoords(obj3, objCoords.x, objCoords.y, player.z - 0.5, false, false, false, false)
    end

    -- Avoid teleporting the player if the bag ends up placed too far off in height
    local objCoords = GetEntityCoords(obj3)
    if math.abs(objCoords.z - player.z) > 2.0 then
        SetEntityCoords(obj3, player.x + 0.5, player.y + 0.5, player.z - 0.5, false, false, false, false)
    end

    MakeEntityFaceEntity(PlayerPedId(), obj3)
    TaskStartScenarioInPlace(PlayerPedId(), 'CODE_HUMAN_MEDIC_TEND_TO_DEAD', 0, true)
    Bridge.Notify(_U('searchingBag'))
    Wait(Config.FouilleSacTime or 12000)
    ClearPedTasks(PlayerPedId())
    DeleteEntity(obj3)
    -- Only the server decides and distributes the reward (token set by startTheft on success)
    TriggerServerEvent('laugh_bagpick:claimHandReward')
end

local busyNpcs = {}

RegisterNetEvent('laugh_bagpick:syncBusyNpcs')
AddEventHandler('laugh_bagpick:syncBusyNpcs', function(busy)
    busyNpcs = busy
end)

RegisterNetEvent('laugh_bagpick:createDroppedBag')
AddEventHandler('laugh_bagpick:createDroppedBag', function(bagId, x, y, z)
    createDroppedBag(bagId, x, y, z)
end)

RegisterNetEvent('laugh_bagpick:removeDroppedBag')
AddEventHandler('laugh_bagpick:removeDroppedBag', function(bagId)
    removeDroppedBag(bagId)
end)

RegisterNetEvent('laugh_bagpick:pickupBagSuccess')
AddEventHandler('laugh_bagpick:pickupBagSuccess', function()
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    if not LoadAnimDict('anim@heists@narcotics@trash') then return end
    TaskPlayAnim(ped, 'anim@heists@narcotics@trash', 'walk', 8.0, -1.0, -1, 49, 0, false, false, false)
    obj2 = CreateObject(GetHashKey('prop_beachbag_02'), 0, 0, 0, true)
    AttachEntityToEntity(obj2, ped, GetPedBoneIndex(ped, 28422), -0.02, 0.00, -0.28, 0.00, 2.4, -58.05, 1, 1, 0, 1, 0, 1)
    Wait(100)
    holdingBag = true
    handleHeldBagLoop()
end)

Citizen.CreateThread(function()
    while true do
        local hasBags = next(droppedBags) ~= nil
        if not hasBags then
            Wait(1000)
        else
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local nearBagId

            for bagId, data in pairs(droppedBags) do
                if #(coords - data.coords) <= 1.5 then
                    nearBagId = bagId
                    break
                end
            end

            if nearBagId then
                SetTextComponentFormat('STRING')
                AddTextComponentString(_U('bag_ground_prompt'))
                DisplayHelpTextFromStringLabel(0, 0, 1, -1)

                if IsControlJustPressed(0, Config.Keys.Pickup) then
                    TriggerServerEvent('laugh_bagpick:pickupBag', nearBagId)
                elseif IsControlJustPressed(0, Config.Keys.Search) then
                    local p = PlayerPedId()
                    TaskStartScenarioInPlace(p, 'CODE_HUMAN_MEDIC_TEND_TO_DEAD', 0, true)
                    Bridge.Notify(_U('searchingBag'))
                    Wait(Config.FouilleSacTime or 12000)
                    ClearPedTasks(p)
                    TriggerServerEvent('laugh_bagpick:searchBag', nearBagId)
                end
                Wait(0)
            else
                Wait(250)
            end
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        if bagpickEnabled and canInteract and not IsPedRunningRagdollTask(PlayerPedId()) then
            if closestPed and npcs[closestPed] == nil then
                if not IsPedInAnyVehicle(closestPed, false) and not IsPedDeadOrDying(closestPed) then
                    Bridge.ShowHelpNotification(_U('stealPrompt'))
                    if IsControlJustPressed(0, Config.Keys.Steal) then
                        Bridge.TriggerCallback('laugh_bagpick:checkCops', function(hasEnoughCops)
                            if hasEnoughCops then
                                if IsPedDeadOrDying(closestPed) == false and IsPedAPlayer(closestPed) == false and GetPedType(closestPed) == 5 and IsPedInAnyVehicle(closestPed, true) == false then
                                    Bridge.TriggerCallback('laugh_bagpick:isNpcBusy', function(isBusy)
                                        if not isBusy then
                                            if not IsPedInAnyVehicle(GetPlayerPed(-1), true) then
                                                chosenPed = closestPed
                                                npcs[chosenPed] = 'inTable'
                                                TriggerEvent('bagpick:client:startTheft', chosenPed)
                                                canInteract = false
                                            else
                                                Bridge.Notify(_U('in_vehicle'))
                                            end
                                        else
                                            Bridge.Notify(_U('npc_already_robbed'))
                                        end
                                    end, NetworkGetNetworkIdFromEntity(closestPed))
                                end
                            else
                                Bridge.Notify("Not enough police officers on duty")
                            end
                        end)
                    end
                end
            end
            Wait(0)
        else
            Wait(1000)
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        if bagpickEnabled and closestPed then
            local playerPed = GetPlayerPed(-1)
            local playerCoords = GetEntityCoords(playerPed)
            local closestPedCoords = GetEntityCoords(closestPed)
            local dist = Vdist(playerCoords, closestPedCoords)
            if dist <= 30 and dist ~= -1 then
                if dist <= 5 then
                    if dist <= 2 and GetPedType(closestPed) == 5 then
                        canInteract = true
                    else
                        canInteract = false
                    end
                else
                    canInteract = false
                end
                Wait(500)
            else
                canInteract = false
                Wait(1000)
            end
        else
            canInteract = false
            Wait(2000)
        end
    end
end)

RegisterCommand('bagpick', function()
    bagpickEnabled = not bagpickEnabled
    if bagpickEnabled then
        Bridge.Notify(_U('bagpick_enabled'))
    else
        Bridge.Notify(_U('bagpick_disabled'))
        canInteract = false
        closestPed = nil
    end
end)
