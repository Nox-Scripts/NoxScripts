-- ---------------------------------------------------------------------------
-- Shared helpers used by BOTH client/turbo_valves.lua and client/backfire.lua.
-- Must load before either of them (see fxmanifest.lua). Having this in one
-- place means the exhaust-flame code and the turbo check only exist once,
-- and the valve script can spawn the same flame the backfire script does.
-- ---------------------------------------------------------------------------

SharedFX = {}

local ptfxAsset = 'core'
local ptfxRequested = false

local function EnsurePtfxLoaded()
    if HasNamedPtfxAssetLoaded(ptfxAsset) then return true end

    if not ptfxRequested then
        RequestNamedPtfxAsset(ptfxAsset)
        ptfxRequested = true
    end

    -- give it up to ~50 ticks (roughly half a second worst-case) to stream
    -- in rather than blocking forever if it never loads
    local attempts = 0
    while not HasNamedPtfxAssetLoaded(ptfxAsset) and attempts < 50 do
        Citizen.Wait(0)
        attempts = attempts + 1
    end

    return HasNamedPtfxAssetLoaded(ptfxAsset)
end

-- Most vehicles only expose "exhaust" and "exhaust_2" - the rest just get
-- skipped on models that don't have them (trucks/vans with quad exhausts,
-- etc). Reuses Config.FlameBones (config.lua, a shared_script, loads before
-- this file) so there's one list to edit either way; falls back to a
-- sensible default if this file is ever used somewhere without that Config.
SharedFX.ExhaustBones = (Config and Config.FlameBones) or {
    'exhaust', 'exhaust_2', 'exhaust_3', 'exhaust_4',
    'exhaust_5', 'exhaust_6', 'exhaust_7', 'exhaust_8',
    'exhaust_9', 'exhaust_10', 'exhaust_11', 'exhaust_12',
    'exhaust_13', 'exhaust_14', 'exhaust_15', 'exhaust_16',
}

-- Mod slot 18 = Turbo Tuning in GTA V's toggle mods.
function SharedFX.VehicleHasTurbo(vehicle, requireTurbo)
    if not requireTurbo then return true end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    return IsToggleModOn(vehicle, 18)
end

function SharedFX.RandomFloat(min, max)
    return min + math.random() * (max - min)
end

-- Spawns the 'veh_backfire' particle out of every exhaust bone the vehicle
-- has, falling back to a spot just behind the vehicle if it has none.
-- `scale` controls the size (1.0 ~= the game's natural scale). `debugTag`
-- is just a label used in the F8 console print when Config.Debug is on.
function SharedFX.PlayExhaustFlame(vehicle, scale, debugTag, debug)
    if not vehicle or not DoesEntityExist(vehicle) then return end

    if not EnsurePtfxLoaded() then
        if debug then
            print(('[%s] core PTFX asset failed to load'):format(debugTag or 'SharedFX'))
        end
        return
    end

    local firedAny = false

    -- Do not use StartParticleFxNonLoopedOnEntityBone here - some FiveM
    -- artifacts expose that native inconsistently. Instead, calculate the
    -- exhaust bone's position and spawn the effect on the vehicle at that
    -- local offset.
    for _, boneName in ipairs(SharedFX.ExhaustBones) do
        local boneIndex = GetEntityBoneIndexByName(vehicle, boneName)

        if boneIndex ~= -1 then
            local pos = GetWorldPositionOfEntityBone(vehicle, boneIndex)
            local off = GetOffsetFromEntityGivenWorldCoords(vehicle, pos.x, pos.y, pos.z)

            UseParticleFxAssetNextCall(ptfxAsset)
            StartParticleFxNonLoopedOnEntity(
                'veh_backfire', vehicle,
                off.x, off.y, off.z,
                0.0, 0.0, 0.0,
                scale, false, false, false
            )
            firedAny = true
        end
    end

    if not firedAny then
        local minDim, maxDim = GetModelDimensions(GetEntityModel(vehicle))
        local off = vector3(0.0, minDim.y - 0.15, math.max(minDim.z + 0.15, 0.0))

        UseParticleFxAssetNextCall(ptfxAsset)
        StartParticleFxNonLoopedOnEntity(
            'veh_backfire', vehicle,
            off.x, off.y, off.z,
            0.0, 0.0, 0.0,
            scale, false, false, false
        )

        if debug then
            print(('[%s] no exhaust bones found; used fallback offset'):format(debugTag or 'SharedFX'))
        end
    end
end
