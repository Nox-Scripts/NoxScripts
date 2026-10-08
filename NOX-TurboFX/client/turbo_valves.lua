
local SoundConfig = {
    { file = 'blowoff-sound-sfx.mp3',               enabled = false },
    { file = 'raider-sfx-engine-turbo-flutter.mp3', enabled = false },
    { file = 'blow-off-valve-supra-stutututu.mp3',  enabled = false },
    { file = 'sfx-turbo-dump-high-1.mp3',           enabled = false },
    { file = 'turbo-ttuuuutututu-1.mp3',            enabled = true },
}

local Sounds = {}
for _, s in ipairs(SoundConfig) do
    if s.enabled then
        table.insert(Sounds, s.file)
    end
end

if #Sounds == 0 then
    print('^1[Turbo BOV] WARNING: every sound is disabled in SoundConfig - nothing will play. Enable at least one.^0')
end

local BaseVolume     = 0.05   -- 0.0 - 1.0 (quieter than before)
local CooldownMs     = 100    -- minimum time between ANY two plays (manual, auto or shift)
local PitchJitter    = 0.35   -- +/- range applied to playback rate each time
local VolumeJitter   = 0.08   -- +/- range applied to volume each time (kept small since base is quiet)
local ShakeIntensity = 0.04   -- camera shake strength, 0.0 - 1.0 (turned down)

-- Auto-trigger ("go off by themselves") tuning. AutoModeEnabled is the
-- master switch for the whole watch-loop below (both throttle-lift and
-- gear-shift live inside it); TriggerOnThrottleLift is a second, more
-- specific switch just for the throttle-lift half of it.
--
-- TriggerOnThrottleLift is OFF by default: with it on, ANY throttle lift
-- held long enough fires the valve, even mid-gear with no shift happening,
-- which reads as random/unrelated to what the car is actually doing. With
-- it off, the valve only fires from the manual key and the gear-shift
-- trigger below - both of which are tied to something actually changing
-- (you pressed the key, or the gearbox shifted), so it stops firing on a
-- plain lift in the middle of a gear.
local AutoModeEnabled           = true   -- toggle with /turbo_bov_auto (master switch for this whole loop)
local TriggerOnThrottleLift     = false  -- toggle with /turbo_bov_liftoff
local AutoCooldownMs            = 700    -- separate, longer cooldown just for auto-fires
local AutoHoldThrottleThreshold = 0.6    -- 0.0-1.0, how hard you need to be on the gas to count as "holding"
local AutoHoldDurationMs        = 1000   -- how long you must hold it before a lift-off will trigger the valve (change with /turbo_bov_hold <seconds>)
local AutoThrottleDropThreshold = 0.5    -- how sharp the throttle lift needs to be, 0.0-1.0
local AutoMinSpeed              = 8.0    -- m/s (~29 km/h) - ignores lifting off while crawling/parking

-- Gear-shift trigger tuning: a real wastegate/BOV flutters on an upshift
-- made under boost, not just on a full throttle lift. This fires the valve
-- whenever the gearbox changes gear while RPM was recently high, regardless
-- of whether you actually lifted off the throttle to do it (an automatic
-- gearbox upshifting under full throttle never "releases" the gas at all,
-- so the throttle-lift trigger above would otherwise miss it entirely).
local TriggerOnGearShift   = true  -- toggle with /turbo_bov_gearshift
local ShiftUpOnly          = true  -- only upshifts trigger it (downshifts don't build the boost a BOV vents); set false to also fire on downshifts
local ShiftMinRpmWindow    = 0.55  -- RPM (0.0-1.0) that counts as "high" for the recent-RPM check below
local ShiftHighRpmHoldMs   = 250   -- how recently RPM had to be at/above ShiftMinRpmWindow for the shift to count as "under boost"
local ShiftMinSpeed        = 3.0   -- m/s - ignores gear hunting while basically stationary
local ShiftCooldownMs      = 350   -- separate cooldown just for shift-triggered fires, so rapid sequential upshifts (e.g. flooring it through the gears) don't spam the sound back-to-back

-- Flame on the valve firing: a small flutter/spit of flame out of the
-- exhaust, using the same particle the backfire effect uses. Off by default
-- since a stock BOV is just a hiss/flutter with no flame - turn this on for
-- more of an "anti-lag" look (also looks great paired with gear-shift
-- triggering above).
local FlameOnValve       = false  -- toggle with /turbo_bov_flame
local ValveFlameScale    = 0.9
local ValveFlameJitter   = 0.25   -- +/- random size variation per flame, purely visual variety

-- If true, both the manual key and every auto-trigger (throttle-lift AND
-- gear-shift) only work on vehicles that actually have a turbo installed
-- (checked via the vehicle's toggle mods, mod slot 18 = turbo in GTA V).
local RequireTurbo = true

-- If true, the sound is broadcast so nearby players hear it too, with volume
-- fading out by distance (nothing at all past MaxHearDistance). If false, only
-- you hear it, same as before.
local NetworkedAudio  = true
local MaxHearDistance = 70.0  -- meters

local lastPlay = 0
local lastAutoPlay = 0
local lastShiftPlay = 0
local lastIndex = nil
local lastThrottle = 0.0
local heldSince = 0     -- GetGameTimer() timestamp of when throttle first went above the hold threshold, or 0
local lastGear = nil    -- last known gear of whatever vehicle we're driving, or nil if not driving
local lastHighRpmAt = 0 -- GetGameTimer() timestamp of the last tick RPM was >= ShiftMinRpmWindow

local function RandomFloat(min, max)
    return SharedFX.RandomFloat(min, max)
end

local function FireSound()
    if #Sounds == 0 then return end

    local index = math.random(#Sounds)
    if #Sounds > 1 then
        while index == lastIndex do
            index = math.random(#Sounds)
        end
    end
    lastIndex = index

    local volume = math.max(0.05, math.min(1.0, BaseVolume + RandomFloat(-VolumeJitter, VolumeJitter)))
    local rate = math.max(0.5, RandomFloat(1 - PitchJitter, 1 + PitchJitter))

    if NetworkedAudio then
        local coords = GetEntityCoords(PlayerPedId())
        TriggerServerEvent('turbo_bov:broadcast', Sounds[index], coords, rate, volume)
    else
        SendNUIMessage({
            type = 'playSound',
            file = Sounds[index],
            volume = volume,
            rate = rate
        })
    end
end

-- Received when ANY player (including you) triggers the valve. Works out how
-- far away the source was and scales the volume down with distance, muting it
-- entirely past MaxHearDistance.
RegisterNetEvent('turbo_bov:play')
AddEventHandler('turbo_bov:play', function(file, sourceCoords, rate, sourceVolume)
    local myCoords = GetEntityCoords(PlayerPedId())
    local dist = #(myCoords - sourceCoords)
    if dist > MaxHearDistance then return end

    local falloff = 1.0 - (dist / MaxHearDistance)
    local volume = sourceVolume * falloff
    if volume <= 0.01 then return end

    SendNUIMessage({
        type = 'playSound',
        file = file,
        volume = volume,
        rate = rate
    })
end)

-- `vehicle` is optional - pass it whenever you have it so FlameOnValve can
-- spawn the exhaust flame; the manual key, auto-lift and gear-shift
-- triggers all have it, so it's only ever nil in edge cases.
local function PlayRandomBOV(vehicle)
    if #Sounds == 0 then return end

    local now = GetGameTimer()
    if now - lastPlay < CooldownMs then return end
    lastPlay = now

    FireSound()
    ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', ShakeIntensity)

    if FlameOnValve and vehicle then
        local scale = math.max(0.1, ValveFlameScale + RandomFloat(-ValveFlameJitter, ValveFlameJitter))
        SharedFX.PlayExhaustFlame(vehicle, scale, 'turbo_bov')
    end
end

-- Manual trigger
RegisterCommand('turbo_bov', function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        local veh = GetVehiclePedIsIn(ped, false)
        if SharedFX.VehicleHasTurbo(veh, RequireTurbo) then
            PlayRandomBOV(veh)
        end
    end
end, false)

-- default key: backslash (\). Players can rebind it in
-- Settings > Key Bindings > FiveM > "Play random turbo blow-off valve sound"
RegisterKeyMapping('turbo_bov', 'Play random turbo blow-off valve sound', 'keyboard', 'BACKSLASH')

-- Master on/off for the whole auto-trigger loop (throttle-lift AND
-- gear-shift both stop if this is off, regardless of their own flags)
RegisterCommand('turbo_bov_auto', function()
    AutoModeEnabled = not AutoModeEnabled
    TriggerEvent('chat:addMessage', {
        args = { '^3[Turbo BOV]', 'Auto self-trigger ' .. (AutoModeEnabled and 'ENABLED' or 'DISABLED') }
    })
end, false)

-- Change how long you need to hold the accelerator before a lift-off triggers
-- the valve, e.g. "/turbo_bov_hold 2" for 2 seconds.
RegisterCommand('turbo_bov_hold', function(source, args)
    local seconds = tonumber(args[1])
    if seconds and seconds >= 0 then
        AutoHoldDurationMs = seconds * 1000
        heldSince = 0 -- restart the hold timer so the new duration applies cleanly
        TriggerEvent('chat:addMessage', {
            args = { '^3[Turbo BOV]', ('Hold time set to %.1f second(s)'):format(seconds) }
        })
    else
        TriggerEvent('chat:addMessage', {
            args = { '^3[Turbo BOV]', 'Usage: /turbo_bov_hold <seconds>, e.g. /turbo_bov_hold 2' }
        })
    end
end, false)

-- Toggle the throttle-lift auto-trigger on/off independently of the gear-shift one
RegisterCommand('turbo_bov_liftoff', function()
    TriggerOnThrottleLift = not TriggerOnThrottleLift
    heldSince = 0 -- don't fire off a stale hold the moment it's re-enabled
    TriggerEvent('chat:addMessage', {
        args = { '^3[Turbo BOV]', 'Throttle-lift trigger ' .. (TriggerOnThrottleLift and 'ENABLED' or 'DISABLED') }
    })
end, false)

-- Toggle the gear-shift trigger on/off independently of the throttle-lift auto-trigger
RegisterCommand('turbo_bov_gearshift', function()
    TriggerOnGearShift = not TriggerOnGearShift
    lastGear = nil -- don't fire off a stale comparison the moment it's re-enabled
    TriggerEvent('chat:addMessage', {
        args = { '^3[Turbo BOV]', 'Gear-shift trigger ' .. (TriggerOnGearShift and 'ENABLED' or 'DISABLED') }
    })
end, false)

-- Toggle the exhaust flame that plays alongside the valve sound
RegisterCommand('turbo_bov_flame', function()
    FlameOnValve = not FlameOnValve
    TriggerEvent('chat:addMessage', {
        args = { '^3[Turbo BOV]', 'Flame-on-valve ' .. (FlameOnValve and 'ENABLED' or 'DISABLED') }
    })
end, false)

-- Watches the accelerator and the gearbox every frame while driving a
-- turbo'd vehicle:
--   - throttle-lift (OFF by default, /turbo_bov_liftoff): hold the gas past
--     AutoHoldThrottleThreshold for AutoHoldDurationMs, then let off
--     sharply, and the valve fires - regardless of gear.
--   - gear-shift (ON by default, /turbo_bov_gearshift): if RPM was high
--     within the last ShiftHighRpmHoldMs ms and the gearbox changes gear
--     (upshift only by default), the valve fires - regardless of whether
--     you actually lifted the throttle to do it.
Citizen.CreateThread(function()
    while true do
        if AutoModeEnabled then
            Citizen.Wait(0)
            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) then
                local veh = GetVehiclePedIsIn(ped, false)
                if GetPedInVehicleSeat(veh, -1) == ped and SharedFX.VehicleHasTurbo(veh, RequireTurbo) then -- driver + turbo required
                    local throttle = GetControlNormal(0, 71) -- analog accelerator input
                    local speed = GetEntitySpeed(veh)
                    local rpm = GetVehicleCurrentRpm(veh)
                    local gear = GetVehicleCurrentGear(veh)
                    local now = GetGameTimer()

                    if rpm >= ShiftMinRpmWindow then
                        lastHighRpmAt = now
                    end

                    -- throttle-lift trigger (off by default - see TriggerOnThrottleLift above)
                    if TriggerOnThrottleLift then
                        local droppedThrottle = (lastThrottle - throttle) > AutoThrottleDropThreshold
                        local heldLongEnough = heldSince > 0 and (now - heldSince) >= AutoHoldDurationMs

                        if droppedThrottle
                            and heldLongEnough
                            and speed > AutoMinSpeed
                            and (now - lastAutoPlay) > AutoCooldownMs
                            and (now - lastPlay) > CooldownMs then
                            lastAutoPlay = now
                            PlayRandomBOV(veh)
                            heldSince = 0 -- must hold for another 3s before it can fire again
                        end
                    end

                    if throttle > AutoHoldThrottleThreshold then
                        if heldSince == 0 then heldSince = now end
                    else
                        heldSince = 0
                    end
                    lastThrottle = throttle

                    -- gear-shift trigger
                    if TriggerOnGearShift and lastGear ~= nil and gear ~= lastGear then
                        local isUpshift = gear > lastGear
                        local wasUnderBoost = (now - lastHighRpmAt) <= ShiftHighRpmHoldMs

                        if (isUpshift or not ShiftUpOnly)
                            and wasUnderBoost
                            and speed > ShiftMinSpeed
                            and (now - lastPlay) > CooldownMs
                            and (now - lastShiftPlay) > ShiftCooldownMs then
                            lastShiftPlay = now
                            PlayRandomBOV(veh)
                        end
                    end
                    lastGear = gear
                else
                    heldSince = 0
                    lastThrottle = 0.0
                    lastGear = nil
                end
            else
                heldSince = 0
                lastThrottle = 0.0
                lastGear = nil
            end
        else
            heldSince = 0
            lastGear = nil
            Citizen.Wait(500)
        end
    end
end)
