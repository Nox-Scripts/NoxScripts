-- ================================================================
--  DX3_Fov — footfov.lua  (Ultimate Edition v3.1)
--  Handles: on-foot FOV shifts for sprinting, aiming, cover
-- ================================================================

local CFG = DX3_FOV_CONFIG

-- ============================================================
-- State
-- ============================================================
local footCamActive = false
local currentFov    = CFG.FOOT_FOV_DEFAULT
local lastAppliedFov = currentFov

-- ============================================================
-- Helpers
-- ============================================================
local function Lerp(a, b, t)
    return a + (b - a) * t
end

local function ApplyGameplayFov(fov)
    -- Native hash fallback (most reliable in FiveM)
    Citizen.InvokeNative(0x65019750A0324133, fov)
end

-- ============================================================
-- Target FOV logic
-- ============================================================
local function GetFootTargetFov()

    local ped = PlayerPedId()

    -- ========================================================
    -- Ignore first-person mode
    -- ========================================================
    if GetFollowPedCamViewMode() == 4 then
        return CFG.FOV_DEFAULT
    end

    -- ========================================================
    -- Aiming
    -- ========================================================
    if IsPlayerFreeAiming(PlayerId()) or IsAimCamActive() then
        return CFG.FOOT_FOV_AIM
    end

    -- ========================================================
    -- Cover
    -- ========================================================
    if IsPedInCover(ped, false) then
        return CFG.FOOT_FOV_COVER or CFG.FOOT_FOV_DEFAULT
    end

    -- ========================================================
    -- Sprint / Running
    -- ========================================================
    if IsPedSprinting(ped) or IsPedRunning(ped) then
        return CFG.FOOT_FOV_SPRINT
    end

    -- ========================================================
    -- Default
    -- ========================================================
    return CFG.FOOT_FOV_DEFAULT
end

-- ============================================================
-- Main loop
-- ============================================================
CreateThread(function()

    while true do

        -- ====================================================
        -- Disabled
        -- ====================================================
        if not CFG.FOOT_FOV_ENABLED then
            Wait(1000)
            goto continue
        end

        local ped = PlayerPedId()

        -- ====================================================
        -- Skip dead players
        -- ====================================================
        if DoesEntityExist(ped) and not IsEntityDead(ped) then

            local vehicle = GetVehiclePedIsIn(ped, false)
            local onFoot = vehicle == 0 and not IsPedInAnyVehicle(ped, false)

            -- =================================================
            -- On foot
            -- =================================================
            if onFoot then

                if not footCamActive then
                    footCamActive = true
                end

                local targetFov = GetFootTargetFov()

                currentFov = Lerp(
                    currentFov,
                    targetFov,
                    CFG.FOOT_FOV_LERP_SPEED
                )

                -- =============================================
                -- Avoid spamming native with tiny changes
                -- =============================================
                if math.abs(currentFov - lastAppliedFov) > 0.01 then
                    ApplyGameplayFov(currentFov)
                    lastAppliedFov = currentFov
                end

                Wait(0)

            else

                -- =============================================
                -- Leaving foot mode
                -- =============================================
                if footCamActive then

                    footCamActive = false

                    currentFov = CFG.FOV_DEFAULT
                    lastAppliedFov = CFG.FOV_DEFAULT

                    ApplyGameplayFov(CFG.FOV_DEFAULT)
                end

                Wait(150)
            end

        else
            Wait(500)
        end

        ::continue::
    end
end)