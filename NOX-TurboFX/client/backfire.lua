local QBCore = exports['qb-core']:GetCoreObject()

local enabled = true
local multiPopEnabled = Config.MultiPop
local vehicleCooldowns = {}    -- netId -> GetGameTimer() timestamp before which nothing may fire again
local holdStart = {}           -- netId -> GetGameTimer() when accelerate was first pressed (hold mode)
local charged = {}             -- netId -> true once accelerate has been held past Config.HoldDuration (hold mode)
local lastThrottleRpm = {}     -- netId -> last throttle reading (rpm mode)
local currentVehicleNetId = nil -- netId of the vehicle we last checked, so we can clear its state on exit

-- ---------------------------------------------------------------------------
-- Main detection loop
-- Each player's client only evaluates the vehicle THEY are driving, so a
-- given car is only ever checked once per tick regardless of how many
-- passengers are riding in it. Runs all three trigger modes below -
-- Config.PopMode decides which of 'hold'/'rpm' actually get to fire,
-- Config.RevLimiterCrackle is independent of both.
-- ---------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(Config.CheckInterval)

        if enabled then
            local ped = PlayerPedId()
            local inDriverSeat = false

            if IsPedInAnyVehicle(ped, false) then
                local vehicle = GetVehiclePedIsIn(ped, false)

                if GetPedInVehicleSeat(vehicle, -1) == ped then
                    inDriverSeat = true
                    local netId = NetworkGetNetworkIdFromEntity(vehicle)
                    currentVehicleNetId = netId

                    if SharedFX.VehicleHasTurbo(vehicle, Config.RequireTurbo) then
                        if Config.PopMode == 'hold' or Config.PopMode == 'both' then
                            HandleHoldModeCheck(vehicle, netId)
                        end
                        if Config.PopMode == 'rpm' or Config.PopMode == 'both' then
                            HandleRpmModeCheck(vehicle, netId)
                        end
                        HandleRevLimiterCrackle(vehicle, netId)
                    else
                        -- no turbo installed -- don't let a hold carry over in case one
                        -- gets installed later
                        ResetHoldState(netId)
                    end
                end
            end

            if not inDriverSeat and currentVehicleNetId then
                -- exited the vehicle (or left the driver seat) -- don't let
                -- a hold carry over to whatever they get into next
                ResetHoldState(currentVehicleNetId)
                currentVehicleNetId = nil
            end
        end
    end
end)

function ResetHoldState(netId)
    if not netId then return end
    holdStart[netId] = nil
    charged[netId] = nil
end

function IsOnCooldown(netId)
    return vehicleCooldowns[netId] and GetGameTimer() < vehicleCooldowns[netId]
end

-- ---------------------------------------------------------------------------
-- Mode 1 - "hold": the original behaviour. Hold accelerate for
-- Config.HoldDuration ms, release it, and Config.ReleaseDelay ms after that
-- release a backfire fires. Good for a deliberate, on-demand pop.
-- ---------------------------------------------------------------------------
function HandleHoldModeCheck(vehicle, netId)
    if IsOnCooldown(netId) then
        holdStart[netId] = nil
        charged[netId] = nil
        return
    end

    local now = GetGameTimer()
    local throttleHeld = IsControlPressed(0, 71) -- INPUT_VEH_ACCELERATE

    if throttleHeld then
        if not holdStart[netId] then
            holdStart[netId] = now
        end

        if not charged[netId] and (now - holdStart[netId]) >= Config.HoldDuration then
            charged[netId] = true

            if Config.Debug then
                print(('[carbackfire] netId %s charged after holding accelerate %dms'):format(netId, Config.HoldDuration))
            end
        end
    elseif holdStart[netId] then
        -- accelerate was just released
        if charged[netId] then
            if Config.Debug then
                print(('[carbackfire] netId %s released -- firing backfire in %dms'):format(netId, Config.ReleaseDelay))
            end

            -- block re-charging until the delayed backfire has fired and
            -- the normal cooldown afterwards has elapsed
            vehicleCooldowns[netId] = now + Config.ReleaseDelay + Config.VehicleCooldown

            SetTimeout(Config.ReleaseDelay, function()
                if DoesEntityExist(vehicle) then
                    TriggerBackfire(vehicle, netId)
                end
            end)
        end

        holdStart[netId] = nil
        charged[netId] = nil
    end
end

-- ---------------------------------------------------------------------------
-- Mode 2 - "rpm": fires the instant you lift off the throttle at high RPM,
-- no charge-up and no delay. This is the one that actually lines up with
-- what you see the game's own engine/exhaust do on a hard lift, since
-- that's driven purely by RPM + throttle in the moment, not a timer - so
-- this is the mode to use if you want NOX-TurboFX's pop to feel like part
-- of the same moment rather than a delayed scripted event.
-- ---------------------------------------------------------------------------
function HandleRpmModeCheck(vehicle, netId)
    if IsOnCooldown(netId) then
        lastThrottleRpm[netId] = nil
        return
    end

    local throttle = GetControlNormal(0, 71)
    local prevThrottle = lastThrottleRpm[netId] or throttle
    local rpm = GetVehicleCurrentRpm(vehicle)
    local speed = GetEntitySpeed(vehicle)
    local droppedThrottle = (prevThrottle - throttle) > Config.PopThrottleDropThreshold

    if droppedThrottle and rpm >= Config.PopRpmThreshold and speed > Config.PopMinSpeed then
        if Config.Debug then
            print(('[carbackfire] rpm-mode pop: rpm=%.2f speed=%.1f'):format(rpm, speed))
        end

        -- cancel any in-progress hold charge so 'both' mode can't also fire
        -- a delayed backfire off the same lift a moment later
        holdStart[netId] = nil
        charged[netId] = nil

        TriggerBackfire(vehicle, netId)
    end

    lastThrottleRpm[netId] = throttle
end

-- ---------------------------------------------------------------------------
-- Rev-limiter crackle: occasional single pops while sitting on the limiter
-- at full throttle (bouncing off redline), like overrun crackle on a real
-- engine. Independent of Config.PopMode - runs either way if enabled.
-- ---------------------------------------------------------------------------
function HandleRevLimiterCrackle(vehicle, netId)
    if not Config.RevLimiterCrackle then return end
    if IsOnCooldown(netId) then return end

    local rpm = GetVehicleCurrentRpm(vehicle)
    local throttle = GetControlNormal(0, 71)

    if rpm >= Config.RevLimiterRpm and throttle > 0.8 then
        if math.random() < Config.RevLimiterCrackleChance then
            if Config.Debug then
                print(('[carbackfire] rev-limiter crackle: rpm=%.2f'):format(rpm))
            end
            TriggerBackfire(vehicle, netId)
        end
    end
end

-- Weighted random pick from Config.PopWeights -- e.g. {[1]=6,[2]=3,[3]=1}
-- means a roll out of 10, where 1-6 -> single pop, 7-9 -> double, 10 -> triple.
function PickPopCount()
    local total = 0
    for _, weight in ipairs(Config.PopWeights) do
        total = total + weight
    end

    if total <= 0 then return 1 end

    local roll = math.random() * total
    local running = 0

    for count, weight in ipairs(Config.PopWeights) do
        running = running + weight
        if roll <= running then
            return count
        end
    end

    return #Config.PopWeights -- fallback, shouldn't normally hit this
end

function TriggerBackfire(vehicle, netId)
    local now = GetGameTimer()
    -- refresh/extend the cooldown from the actual moment of firing, whichever
    -- trigger mode caused it
    vehicleCooldowns[netId] = math.max(vehicleCooldowns[netId] or 0, now + Config.VehicleCooldown)

    local coords = GetEntityCoords(vehicle)
    local popCount = multiPopEnabled and PickPopCount() or 1

    local sounds = {}
    local previous = nil
    for i = 1, popCount do
        local pick = Config.Sounds[math.random(#Config.Sounds)]
        if #Config.Sounds > 1 then
            while pick == previous do
                pick = Config.Sounds[math.random(#Config.Sounds)]
            end
        end
        sounds[i] = pick
        previous = pick
    end

    if Config.Debug then
        print(('[carbackfire] firing backfire, %d pop(s): %s'):format(popCount, table.concat(sounds, ', ')))
    end

    TriggerServerEvent('qb-carbackfire:server:broadcast', netId, coords, sounds)
end

-- ---------------------------------------------------------------------------
-- Flame effect: a "veh_backfire" particle out of the exhaust bone(s),
-- non-looped so it's a single pop rather than a sustained flame. Shared
-- with the turbo valve script's optional flame-on-valve.
-- ---------------------------------------------------------------------------
function PlayBackfireFlame(vehicle)
    if not Config.FlameEffect then return end
    local scale = math.max(0.1, Config.FlameScale + SharedFX.RandomFloat(-Config.FlameScaleJitter, Config.FlameScaleJitter))
    SharedFX.PlayExhaustFlame(vehicle, scale, 'carbackfire', Config.Debug)
end

-- ---------------------------------------------------------------------------
-- Playback: fired on every client (including the one that triggered it).
-- Audio distance/volume is decided locally per-client. The flame is
-- rendered locally when the networked vehicle exists on that client. Camera
-- shake only applies if this client happens to be riding in the vehicle
-- that's popping, so bystanders who merely hear it don't get their view
-- shaken too.
-- ---------------------------------------------------------------------------
RegisterNetEvent('qb-carbackfire:client:play', function(netId, coords, sounds)
    local myVehicle = IsPedInAnyVehicle(PlayerPedId(), false) and GetVehiclePedIsIn(PlayerPedId(), false) or 0
    local poppingVehicle = NetworkGetEntityFromNetworkId(netId)
    local imRidingIt = poppingVehicle ~= 0 and myVehicle == poppingVehicle

    if imRidingIt and Config.BackfireCameraShake then
        local intensity = Config.BackfireShakeIntensity * (1.0 + 0.25 * (#sounds - 1)) -- a bit stronger for multi-pop bursts
        ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', intensity)
    end

    local function popOnce(popSound)
        local myCoords = GetEntityCoords(PlayerPedId())
        local dist = #(myCoords - coords)

        if dist <= Config.MaxHearingDistance then
            local volume = Config.MaxVolume * (1.0 - (dist / Config.MaxHearingDistance))
            volume = math.max(volume, 0.0)

            SendNUIMessage({
                action = 'playBackfire',
                sound = popSound,
                volume = volume
            })
        end

        if DoesEntityExist(poppingVehicle) then
            PlayBackfireFlame(poppingVehicle)
        end
    end

    for i, popSound in ipairs(sounds) do
        if i == 1 then
            popOnce(popSound)
        else
            SetTimeout(Config.PopDelay * (i - 1), function()
                popOnce(popSound)
            end)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Quick toggle so server owners/players can turn it off without restarting
-- ---------------------------------------------------------------------------
RegisterCommand('togglebackfire', function()
    enabled = not enabled
    QBCore.Functions.Notify(('Car backfire sounds %s'):format(enabled and 'enabled' or 'disabled'), 'primary')
end, false)

-- ---------------------------------------------------------------------------
-- Toggle multi-pop (a random 1-3 pops per backfire) on or off without
-- restarting the resource. Off = always exactly one pop.
-- ---------------------------------------------------------------------------
RegisterCommand('togglemultipop', function()
    multiPopEnabled = not multiPopEnabled
    QBCore.Functions.Notify(('Multi-pop %s'):format(multiPopEnabled and 'enabled' or 'disabled'), 'primary')
end, false)

-- ---------------------------------------------------------------------------
-- Switch trigger mode live: /backfire_mode hold | rpm | both
-- ---------------------------------------------------------------------------
RegisterCommand('backfire_mode', function(source, args)
    local mode = args[1]
    if mode == 'hold' or mode == 'rpm' or mode == 'both' then
        Config.PopMode = mode
        QBCore.Functions.Notify(('Backfire trigger mode set to "%s"'):format(mode), 'primary')
    else
        QBCore.Functions.Notify('Usage: /backfire_mode hold | rpm | both', 'error')
    end
end, false)

-- ---------------------------------------------------------------------------
-- Toggle rev-limiter crackle without restarting the resource
-- ---------------------------------------------------------------------------
RegisterCommand('backfire_revlimiter', function()
    Config.RevLimiterCrackle = not Config.RevLimiterCrackle
    QBCore.Functions.Notify(('Rev-limiter crackle %s'):format(Config.RevLimiterCrackle and 'enabled' or 'disabled'), 'primary')
end, false)

-- ---------------------------------------------------------------------------
-- /testbackfire -- forces a backfire on your current vehicle immediately,
-- bypassing ALL trigger-mode detection entirely. Use this to check whether
-- the AUDIO PIPELINE works at all, separate from whether the timing/RPM
-- thresholds feel right for your driving.
-- ---------------------------------------------------------------------------
RegisterCommand('testbackfire', function()
    local ped = PlayerPedId()

    if not IsPedInAnyVehicle(ped, false) then
        QBCore.Functions.Notify('Get in a vehicle first', 'error')
        return
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)

    print('[carbackfire] /testbackfire fired, sending trigger for vehicle netId ' .. netId)
    TriggerBackfire(vehicle, netId)
end, false)
