-- =============================================
-- STATE
-- =============================================

local airTrickActive = false
local wheeliePoseActive = false
local isDirectionInverted = false

-- Timestamp (GetGameTimer) until which the automatic wheelie-inclination
-- check is paused. Set whenever a Shift+Arrow manual pose plays, so the
-- two systems take turns instead of fighting over the same animation task.
local manualTrickLockedUntil = 0

-- 55 degrees converted to radians for knockoff pitch comparison
local KNOCKOFF_PITCH_THRESHOLD = 55.0 * math.pi / 180.0

-- All trick clip names used to check if any trick animation is currently playing
local TRICK_ANIM_CLIPS = {
    "trick_1_right_start_clip",
    "trick_1_right_end_clip",
    "trick_1_left_start_clip",
    "trick_1_left_end_clip",
    "trick_2_right_start_clip",
    "trick_2_right_left_clip",
    "trick_2_left_right_clip",
    "trick_2_right_end_clip",
    "trick_2_left_end_clip",
    "trick_3_start_clip",
    "trick_3_end_clip",
    "trick_4_start_clip",
    "trick_4_end_clip",
}

-- =============================================
-- TRICK DEFINITIONS
-- =============================================
-- anim  = primary start clip
-- anim2 = alternate start / transition clip
-- anim3 = reverse transition clip
-- anim4 = alternate end clip
-- anim5 = primary end clip

BikeTricks = {
    {
        label = "BikeTrick: Pose 1",
        dict  = "bike@tricks@anims",
        anim  = "trick_1_right_start_clip",
        anim2 = "trick_1_left_start_clip",
        anim3 = "",
        anim4 = "trick_1_left_end_clip",
        anim5 = "trick_1_right_end_clip",
        flag  = 131106,
        flag2 = 4126,
    },
    {
        label = "BikeTrick: Pose 2",
        dict  = "bike@tricks@anims",
        anim  = "trick_2_right_start_clip",
        anim2 = "trick_2_right_left_clip",
        anim3 = "trick_2_left_right_clip",
        anim4 = "trick_2_left_end_clip",
        anim5 = "trick_2_right_end_clip",
        flag  = 131106,
        flag2 = 4126,
    },
    {
        label = "BikeTrick: Pose 3",
        dict  = "bike@tricks@anims",
        anim  = "trick_3_start_clip",
        anim2 = "",
        anim3 = "",
        anim4 = "",
        anim5 = "trick_3_end_clip",
        flag  = 131106,
        flag2 = 4126,
    },
    {
        label = "BikeTrick: Pose 4",
        dict  = "bike@tricks@anims",
        anim  = "trick_4_start_clip",
        anim2 = "",
        anim3 = "",
        anim4 = "",
        anim5 = "trick_4_end_clip",
        flag  = 131106,
        flag2 = 4126,
    },
    {
        label = "BikeTrick: Switch Side",
        dict  = "bike@tricks@anims",
        anim = "", anim2 = "", anim3 = "", anim4 = "", anim5 = "",
        flag = 131106, flag2 = 4126,
        key  = "F6",
    },
    {
        label = "BikeTrick: AirTrick",
        dict  = "bike@airtrick@anims",
        anim = "", anim2 = "", anim3 = "", anim4 = "", anim5 = "",
        flag = 131106, flag2 = 4126,
    },
    {
        label = "BikeTrick: Invert",
        dict  = "bike@airtrick@anims",
        anim = "", anim2 = "", anim3 = "", anim4 = "", anim5 = "",
        flag = 131106, flag2 = 4126,
    },
    {
        label = "BikeTrick: Jump",
        dict  = "bike@airtrick@anims",
        anim = "", anim2 = "", anim3 = "", anim4 = "", anim5 = "",
        flag = 131106, flag2 = 4126,
    },
}

-- =============================================
-- UTILITY
-- =============================================

function LoadAnimDict(dict)
    RequestAnimDict(dict)
    local attempts = 0
    while not HasAnimDictLoaded(dict) do
        attempts = attempts + 1
        if attempts > 500 then
            print("ERROR: Something happened while trying to load a bike trick.")
            break
        end
        Wait(0)
    end
end

-- ⚠️ Overrides the native GetEntityPitch with a custom forward-vector-based pitch calculation
function GetEntityPitch(entity)
    local fwd = GetEntityForwardVector(entity)
    local horizontal = math.sqrt(fwd.x * fwd.x + fwd.y * fwd.y)
    return math.deg(math.atan2(fwd.z, horizontal))
end

function IsPlayingAnyBikeAnim(ped)
    for _, clipName in ipairs(TRICK_ANIM_CLIPS) do
        if IsEntityPlayingAnim(ped, "bike@tricks@anims", clipName, 1) then
            return true
        end
    end
    return false
end

-- Identical to IsPlayingAnyBikeAnim, kept as separate global for external compatibility
CanEndBikeAnim = IsPlayingAnyBikeAnim

-- Shared eligibility check used by BOTH the manual btrick commands and the
-- Shift+Arrow poses below, so the two systems always agree on which
-- vehicles/speeds are allowed instead of each mod having its own rules.
function IsBikeTrickAllowed(vehicle)
    if not vehicle or vehicle == 0 then return false end

    local model = GetEntityModel(vehicle)
    local vehClass = GetVehicleClass(vehicle)

    if Config.allowedVehicles[model] and (GetEntitySpeed(vehicle) * 3.6) > Config.minimumSpeed then
        return true
    end

    if vehClass == 8 and Config.AllowAllBikes then
        return true
    end

    return false
end

function HasPassenger(vehicle)
    local numSeats = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))
    for seatIndex = 0, numSeats - 1 do
        local occupant = GetPedInVehicleSeat(vehicle, seatIndex)
        if occupant and DoesEntityExist(occupant) then
            return true
        end
    end
    return false
end

-- =============================================
-- TRICK POSE TOGGLE
-- =============================================

function ToggleTrickPose(dict, startAnim, altAnim, transitionAnim, altEndAnim, endAnim, startFlag, rotOrder, vehicle)
    LoadAnimDict(dict)
    local ped = PlayerPedId()
    wheeliePoseActive = false

    if not IsPlayingAnyBikeAnim(ped) then
        TaskPlayAnim(ped, dict, startAnim, 8.0, -8.0, -1, startFlag, 0.0, false, rotOrder, false)
    elseif IsEntityPlayingAnim(ped, dict, startAnim, 1) or IsEntityPlayingAnim(ped, dict, transitionAnim, 1) then
        TaskPlayAnim(ped, dict, endAnim, 8.0, -8.0, -1, 131104, 0.0, false, rotOrder, false)
    elseif IsEntityPlayingAnim(ped, dict, altAnim, 1) then
        TaskPlayAnim(ped, dict, altEndAnim, 8.0, -8.0, -1, 131104, 0.0, false, rotOrder, false)
    end
end

-- =============================================
-- SWITCH SIDE
-- =============================================

function SwitchTrickSide(dict, startAnim, altAnim, transitionAnim, altEndAnim, endAnim, startFlag, rotOrder, vehicle)
    LoadAnimDict(dict)
    local ped = PlayerPedId()

    if IsEntityPlayingAnim(ped, dict, "trick_1_right_start_clip", 1) then
        TaskPlayAnim(ped, dict, "trick_1_right_end_clip", 8.0, -8.0, -1, startFlag, 0.0, false, rotOrder, false)
        Wait(700)
        TaskPlayAnim(ped, dict, "trick_1_left_start_clip", 8.0, -8.0, -1, startFlag, 0.0, false, rotOrder, false)

    elseif IsEntityPlayingAnim(ped, dict, "trick_1_left_start_clip", 1) then
        TaskPlayAnim(ped, dict, "trick_1_left_end_clip", 8.0, -8.0, -1, startFlag, 0.0, false, rotOrder, false)
        Wait(700)
        TaskPlayAnim(ped, dict, "trick_1_right_start_clip", 8.0, -8.0, -1, startFlag, 0.0, false, rotOrder, false)

    elseif IsEntityPlayingAnim(ped, dict, "trick_2_right_start_clip", 1) then
        TaskPlayAnim(ped, dict, "trick_2_right_left_clip", 8.0, -8.0, -1, startFlag, 0.0, false, rotOrder, false)
        Wait(700)

    elseif IsEntityPlayingAnim(ped, dict, "trick_2_right_left_clip", 1) then
        TaskPlayAnim(ped, dict, "trick_2_left_right_clip", 8.0, -8.0, -1, startFlag, 0.0, false, rotOrder, false)
        Wait(700)

    elseif IsEntityPlayingAnim(ped, dict, "trick_2_left_right_clip", 1) then
        TaskPlayAnim(ped, dict, "trick_2_right_left_clip", 8.0, -8.0, -1, startFlag, 0.0, false, rotOrder, false)
        Wait(700)
    end
end

-- =============================================
-- AIR TRICKS
-- =============================================

function PlayAirTrickSimple()
    local ped = PlayerPedId()
    LoadAnimDict("bike@tricks@anims")
    TaskPlayAnim(ped, "bike@tricks@anims", "airtrick_1", 8.0, -8.0, -1, 131104, 0.0, false, 4126, false)
    Citizen.Wait(1000)
    airTrickActive = false
end

function PlayAirTrickWithVehicle()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    LoadAnimDict("bike@airtrick@anims")
    TaskVehiclePlayAnim(vehicle, "bike@airtrick@anims", "bike_front", 8.0, -8.0, -1, 131112, 0.0, false, false, false)
    LoadAnimDict("bike@tricks@anims")
    TaskPlayAnim(ped, "bike@tricks@anims", "airtrick_2", 8.0, -8.0, -1, 131104, 0.0, false, 4126, false)
    Citizen.Wait(1000)
    airTrickActive = false
end

function PerformAirTrick()
    local ped = PlayerPedId()
    if GetEntityHeightAboveGround(ped) <= 6.0 then return end
    if not IsPedOnAnyBike(ped) then return end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return end
    if airTrickActive then return end

    airTrickActive = true
    if math.random(0, 1) == 0 then
        PlayAirTrickSimple()
    else
        PlayAirTrickWithVehicle()
    end
end

-- =============================================
-- DIRECTION / BRAKE
-- =============================================

function BrakeStopForward()
    airTrickActive = true
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    LoadAnimDict("bike@airtrick@anims")
    TaskVehiclePlayAnim(vehicle, "bike@airtrick@anims", "bike_stop", 8.0, -8.0, -1, 167, 0.0, false, false, false)
    Citizen.Wait(900)
    airTrickActive = false
end

function BrakeStopBackward()
    airTrickActive = true
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    LoadAnimDict("bike@airtrick@anims")
    TaskVehiclePlayAnim(vehicle, "bike@airtrick@anims", "bike_stop_back", 8.0, -8.0, -1, 167, 0.0, false, false, false)
    Citizen.Wait(900)
    airTrickActive = false
    isDirectionInverted = false
end

function ChangeDirection()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsUsing(ped)
    if vehicle == 0 then return end

    local velocity = GetEntityVelocity(vehicle)
    local speed = #velocity

    if speed <= 13.4112 or speed >= 26.8224 then return end

    if isDirectionInverted then
        BrakeStopBackward()
    else
        isDirectionInverted = true
        BrakeStopForward()
    end
end

-- =============================================
-- BIKE JUMP
-- =============================================

function BikeJump()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsUsing(ped)
    if vehicle == 0 then return end

    local pitch = GetEntityPitch(vehicle)
    if pitch > -30.0 then return end
    if not IsPedOnAnyBike(ped) then return end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return end
    if GetEntityModel(vehicle) == GetHashKey("bmx") then return end

    local vel = GetEntityVelocity(vehicle)
    SetEntityVelocity(vehicle, vel.x, vel.y, 10.0)

    Citizen.Wait(500)
    while GetEntityHeightAboveGround(vehicle) < 1.0 do
        Citizen.Wait(0)
    end
end

-- =============================================
-- WHEELIE POSES
-- =============================================

function WheeliePoseStart(ped)
    LoadAnimDict("bike@tricks@anims")
    TaskPlayAnim(ped, "bike@tricks@anims", "wheelie_pose_start", 8.0, -8.0, -1, 131106, 0.0, false, false, false)
end

function WheeliePoseEnd(ped)
    LoadAnimDict("bike@tricks@anims")
    TaskPlayAnim(ped, "bike@tricks@anims", "wheelie_pose_end", 8.0, -8.0, -1, 131104, 0.0, false, false, false)
    wheeliePoseActive = false
end

function WheeliePoseStartPass(ped)
    LoadAnimDict("veh@bike@dirt@front@base")
    TaskPlayAnim(ped, "veh@bike@dirt@front@base", "sit_high", 8.0, -8.0, -1, 131105, 0.0, false, false, false)
end

function WheeliePoseStartBack(ped)
    LoadAnimDict("anim@veh@sit_variations@dirt@front@idle_a")
    TaskPlayAnim(ped, "anim@veh@sit_variations@dirt@front@idle_a", "sit_balance_bwd", 8.0, -8.0, -1, 131105, 0.0, false, 4126, false)
end

-- =============================================
-- MANUAL POSE TRICKS (Shift + Arrow)
-- =============================================
-- Merged in from the old separate "biketricks" resource so it shares state
-- with the automatic wheelie system above instead of blindly overwriting
-- it. Previously, pressing Shift+Arrow mid-wheelie would slam a new
-- animation over the wheelie pose without telling the wheelie system about
-- it, leaving "wheeliePoseActive" stuck ON forever - which is why the
-- automatic wheelie animation would stop firing until you got off and back
-- on the bike. This version cleanly hands off between the two instead, and
-- the safety-net check in CheckBikeInclination() below means even an
-- unrelated future script doing the same thing can't get you stuck again.

local ManualTrickDict = "rcmextreme2atv"
local ManualTrickClips = {
    up    = "idle_e",
    down  = "idle_d",
    left  = "idle_b",
    right = "idle_c",
}

function PlayManualTrick(clip)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if not IsBikeTrickAllowed(vehicle) then return end

    -- If the automatic wheelie pose is currently playing, end it properly
    -- (this resets wheeliePoseActive) instead of letting the manual trick
    -- silently overwrite it and leave the flag stuck.
    if wheeliePoseActive then
        WheeliePoseEnd(ped)
    end

    -- Pause the automatic inclination check briefly so it doesn't immediately
    -- slam a wheelie pose back over this animation while it's playing.
    manualTrickLockedUntil = GetGameTimer() + Config.manualTrickHoldMs

    LoadAnimDict(ManualTrickDict)
    TaskPlayAnim(ped, ManualTrickDict, clip, 8.0, -8.0, -1, 32, 0.0, false, false, false)
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(5)

        if IsControlPressed(0, 21) then -- LEFTSHIFT
            if IsControlJustReleased(0, 172) then
                PlayManualTrick(ManualTrickClips.up)
            elseif IsControlJustReleased(0, 173) then
                PlayManualTrick(ManualTrickClips.down)
            elseif IsControlJustReleased(0, 174) then
                PlayManualTrick(ManualTrickClips.left)
            elseif IsControlJustReleased(0, 175) then
                PlayManualTrick(ManualTrickClips.right)
            end
        end
    end
end)

-- =============================================
-- INCLINATION CHECK
-- =============================================

function CheckBikeInclination(ped)
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return end

    local pitch = GetEntityPitch(vehicle)

    if pitch >= 50.0 then
        if wheeliePoseActive then return end

        if isDirectionInverted then
            wheeliePoseActive = true
            WheeliePoseStartBack(ped)
        elseif HasPassenger(vehicle) then
            wheeliePoseActive = true
            WheeliePoseStartPass(ped)
        else
            wheeliePoseActive = true
            WheeliePoseStart(ped)
        end

    elseif pitch < 30.0 then
        if IsEntityPlayingAnim(ped, "bike@tricks@anims", "wheelie_pose_start", 3) then
            WheeliePoseEnd(ped)
        elseif IsEntityPlayingAnim(ped, "veh@bike@dirt@front@base", "sit_high", 3) then
            StopAnimTask(PlayerPedId(), "veh@bike@dirt@front@base", "sit_high", 1.0)
            wheeliePoseActive = false
        elseif IsEntityPlayingAnim(ped, "anim@veh@sit_variations@dirt@front@idle_a", "sit_balance_bwd", 3) then
            StopAnimTask(PlayerPedId(), "anim@veh@sit_variations@dirt@front@idle_a", "sit_balance_bwd", 1.0)
            wheeliePoseActive = false
        elseif wheeliePoseActive then
            -- Safety net: pitch is low and none of the known wheelie
            -- animations are actually playing, yet the flag still thinks
            -- one is. Something else took over the anim task (another
            -- script, a ragdoll, etc.) - resync instead of staying stuck
            -- like the old bug where the auto wheelie pose would stop
            -- firing until you got off and back on the bike.
            wheeliePoseActive = false
        end
    end
end

-- =============================================
-- THREAD: REGISTER COMMANDS & KEY MAPPINGS
-- =============================================

CreateThread(function()
    for index, trick in pairs(BikeTricks) do
        local commandName = "btrick" .. index

        RegisterCommand(commandName, function()
            local vehicle = GetVehiclePedIsUsing(PlayerPedId())

            if not IsBikeTrickAllowed(vehicle) then return end

            if trick.label == "BikeTrick: Switch Side" then
                Citizen.CreateThread(function()
                    SwitchTrickSide(trick.dict, trick.anim, trick.anim2, trick.anim3, trick.anim4, trick.anim5, trick.flag, trick.flag2, vehicle)
                end)
            elseif trick.label == "BikeTrick: AirTrick" then
                PerformAirTrick()
            elseif trick.label == "BikeTrick: Invert" then
                ChangeDirection()
            elseif trick.label == "BikeTrick: Jump" then
                BikeJump()
            else
                ToggleTrickPose(trick.dict, trick.anim, trick.anim2, trick.anim3, trick.anim4, trick.anim5, trick.flag, trick.flag2, vehicle)
            end
        end)

        RegisterKeyMapping(commandName, trick.label, "keyboard", trick.key or "")
    end
end)

-- =============================================
-- THREAD: MAIN LOOP (helmet + inclination)
-- =============================================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(100)

        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsUsing(ped)
        local model = GetEntityModel(vehicle)
        local vehClass = GetVehicleClass(vehicle)
        local isAllowed = Config.allowedVehicles[model] or (vehClass == 8 and Config.AllowAllBikes)

        if isAllowed then
            if not IsPlayingAnyBikeAnim(ped) and GetGameTimer() >= manualTrickLockedUntil then
                if not Config.helmet then
                    SetPedConfigFlag(ped, 35, false)
                end
                CheckBikeInclination(ped)
            end
        elseif vehClass ~= 8 then
            wheeliePoseActive = false
            manualTrickLockedUntil = 0
        end
    end
end)

-- =============================================
-- THREAD: KNOCKOFF PROTECTION
-- =============================================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(100)

        local ped = PlayerPedId()
        if not IsPedOnAnyBike(ped) then goto continue end

        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle == 0 then goto continue end

        local pitch = GetEntityPitch(vehicle)
        if pitch > KNOCKOFF_PITCH_THRESHOLD then
            SetPedCanBeKnockedOffVehicle(ped, 1)
        else
            SetPedCanBeKnockedOffVehicle(ped, 0)
        end

        ::continue::
    end
end)
