-- ================================================================
--  DX3_Fov — effects.lua  (Ultimate Edition v3.0)
--  Handles: myopia blur, crash screen flash, speed vignette,
--           chromatic aberration at high speed
-- ================================================================

local CFG = DX3_FOV_CONFIG

-- ============================================================
-- State
-- ============================================================
local esMiope        = false
local wearingGlasses = false
local blurActive     = false
local inVehicleLast  = false

-- Crash flash
local crashFlashTimer = 0
local CRASH_FLASH_MS  = 120   -- white flash duration on big impact
local lastSpeedEff    = 0.0

-- Speed chromatic aberration / vignette
local aberrationActive = false

-- ============================================================
-- Blur
-- ============================================================
local function SetBlur(state)
    if state == blurActive then return end
    blurActive = state

    if state then
        SetTimecycleModifier(CFG.BLUR_TIMECYCLE)
        SetTimecycleModifierStrength(CFG.BLUR_STRENGTH)
        TriggerScreenblurFadeIn(CFG.BLUR_FADE_IN)
    else
        ClearTimecycleModifier()
        TriggerScreenblurFadeOut(CFG.BLUR_FADE_OUT)
    end
end

local function ShouldBlur()
    if not esMiope        then return false end
    if wearingGlasses     then return false end

    local ped       = PlayerPedId()
    local inVehicle = IsPedInAnyVehicle(ped, false)
    if inVehicle              then return true end
    if CFG.BLUR_ON_FOOT       then return true end
    return false
end

local function IsWearingGlasses()
    local ped = PlayerPedId()
    local d   = GetPedPropIndex(ped, 1)
    return d ~= 0 and d ~= -1
end

-- ============================================================
-- Server sync
-- ============================================================
RegisterNetEvent("fzt_fov:setMiopia", function(state)
    esMiope = state
    SetBlur(ShouldBlur())
end)

RegisterNetEvent("fzt_fov:setGlassesState", function(state)
    wearingGlasses = state
    SetBlur(ShouldBlur())
end)

-- ============================================================
-- Crash flash
-- ============================================================
local function CheckCrashFlash(vehicle)
    if not CFG.CRASH_SHAKE_ENABLED then return end

    local speedNow = GetEntitySpeed(vehicle)
    local delta    = lastSpeedEff - speedNow
    lastSpeedEff   = speedNow

    if delta > CFG.CRASH_SHAKE_THRESHOLD * 1.5 then
        -- Big impact: white flash
        crashFlashTimer = CRASH_FLASH_MS
        AnimpostfxPlay("Dont_tazeme_bro", 0, false)
    end
end

-- ============================================================
-- Speed chromatic aberration (motion blur + post FX at speed)
-- ============================================================
local function UpdateSpeedEffects(vehicle)
    if not vehicle or vehicle == 0 then
        if aberrationActive then
            AnimpostfxStop("MotionBlurVehicle")
            aberrationActive = false
        end
        return
    end

    local speedMph = GetEntitySpeed(vehicle) * 2.23694
    local threshold = CFG.LETTERBOX_SPEED_MPH or 80.0

    if speedMph > threshold and not aberrationActive then
        AnimpostfxPlay("MotionBlurVehicle", 0, true)
        aberrationActive = true
    elseif speedMph <= threshold and aberrationActive then
        AnimpostfxStop("MotionBlurVehicle")
        aberrationActive = false
    end
end

-- ============================================================
-- Main loop
-- ============================================================
CreateThread(function()
    while true do
        Wait(CFG.BLUR_POLL_MS)

        local ped       = PlayerPedId()
        local inVehicle = IsPedInAnyVehicle(ped, false)
        local vehicle   = GetVehiclePedIsIn(ped, false)

        wearingGlasses = IsWearingGlasses()

        -- Blur transitions
        if inVehicle ~= inVehicleLast then
            inVehicleLast = inVehicle
            SetBlur(ShouldBlur())
        end

        -- Keep blur consistent (guard against other scripts clearing timecycle)
        if blurActive and not ShouldBlur() then
            SetBlur(false)
        elseif not blurActive and ShouldBlur() then
            SetBlur(true)
        end

        -- Crash & speed effects while driving
        if inVehicle and GetPedInVehicleSeat(vehicle, -1) == ped then
            CheckCrashFlash(vehicle)
            UpdateSpeedEffects(vehicle)
        else
            if aberrationActive then
                AnimpostfxStop("MotionBlurVehicle")
                aberrationActive = false
            end
            lastSpeedEff = 0.0
        end
    end
end)
