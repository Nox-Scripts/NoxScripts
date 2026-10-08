-- ================================================================
--  DX3_Fov — fovdriver.lua  (Ultimate Edition v3.0)
--  Handles: vehicle camera, FOV per class, speed-based FOV,
--           head bob, crash shake, yaw auto-center, myopia
-- ================================================================

local CFG = DX3_FOV_CONFIG

-- ============================================================
-- State
-- ============================================================
local cameraActive   = false
local cam            = nil
local pitch          = 0.0
local offsetYaw      = 0.0
local currentFov     = CFG.FOV_DEFAULT

local esMiope        = false
local wearingGlasses = false

-- Head bob
local bobTimer       = 0.0
local bobOffset      = 0.0

-- Crash shake
local shakeAmount    = 0.0
local lastSpeed      = 0.0

-- ============================================================
-- Utilities
-- ============================================================
local function Lerp(a, b, t)
    return a + (b - a) * t
end

local function GetVehicleSpeedMph(vehicle)
    return GetEntitySpeed(vehicle) * 2.23694
end

local function GetVehicleClassName(class)
    local names = {
        [0]="Compact",[1]="Sedan",[2]="SUV",[3]="Coupe",[4]="Muscle",
        [5]="Sport",[6]="Super",[7]="Motorcycle",[8]="Off-road",
        [9]="Industrial",[10]="Utility",[11]="Van",[12]="Bicycle",
        [13]="Boat",[14]="Helicopter",[15]="Plane",[16]="Service",
        [17]="Emergency",[18]="Military",[19]="Commercial",[20]="Train",
    }
    return names[class] or "Vehicle"
end

-- ============================================================
-- FOV calculation
-- ============================================================
local function GetBaseFov(vehicle)
    -- Myopia overrides
    if esMiope and not wearingGlasses then return CFG.FOV_MYOPIA end
    if esMiope and wearingGlasses     then return CFG.FOV_GLASSES end

    -- Per-class base
    local class   = GetVehicleClass(vehicle)
    local base    = CFG.FOV_BY_CLASS[class] or CFG.FOV_DEFAULT

    -- Speed bonus
    if CFG.FOV_SPEED_ENABLED then
        local speedMph = GetVehicleSpeedMph(vehicle)
        local t        = math.min(speedMph / CFG.FOV_SPEED_REF_MPH, 1.0)
        base = base + t * CFG.FOV_SPEED_MAX_BONUS
    end

    return base
end

-- ============================================================
-- Head bob
-- ============================================================
local function UpdateHeadBob(vehicle, dt)
    if not CFG.HEADBOB_ENABLED then
        bobOffset = 0.0
        return
    end

    local speed    = GetEntitySpeed(vehicle)
    local maxSpeed = GetVehicleEstimatedMaxSpeed(vehicle)
    local t        = CFG.HEADBOB_SPEED_SCALE and math.min(speed / math.max(maxSpeed, 1.0), 1.0) or 1.0

    if speed < 0.5 then
        bobOffset = Lerp(bobOffset, 0.0, 0.1)
        return
    end

    bobTimer  = bobTimer + dt * CFG.HEADBOB_SPEED * (0.3 + t * 0.7)
    bobOffset = math.sin(bobTimer) * CFG.HEADBOB_AMPLITUDE * t
end

-- ============================================================
-- Crash shake
-- ============================================================
local function UpdateCrashShake(vehicle, dt)
    if not CFG.CRASH_SHAKE_ENABLED then
        shakeAmount = 0.0
        return
    end

    local speedNow  = GetEntitySpeed(vehicle)
    local delta     = lastSpeed - speedNow          -- positive = deceleration
    lastSpeed       = speedNow

    -- Impact detected
    if delta > CFG.CRASH_SHAKE_THRESHOLD then
        local intensity = math.min(delta / 20.0, 1.0) * CFG.CRASH_SHAKE_INTENSITY
        shakeAmount = math.max(shakeAmount, intensity)
    end

    -- Decay
    if shakeAmount > 0.01 then
        shakeAmount = shakeAmount * CFG.CRASH_SHAKE_DECAY
    else
        shakeAmount = 0.0
    end
end

local function GetShakeOffset()
    if shakeAmount < 0.01 then return 0.0, 0.0 end
    local px = (math.random() * 2 - 1) * shakeAmount
    local py = (math.random() * 2 - 1) * shakeAmount
    return px, py
end

-- ============================================================
-- Camera create / destroy
-- ============================================================
local function CreateVehicleCamera(ped)
    cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)

    AttachCamToPedBone(
        cam, ped,
        GetPedBoneIndex(ped, 12844),
        CFG.CAM_OFFSET_X,
        CFG.CAM_OFFSET_Y,
        CFG.CAM_OFFSET_Z,
        true
    )

    local vehicle  = GetVehiclePedIsIn(ped, false)
    currentFov     = GetBaseFov(vehicle)
    lastSpeed      = GetEntitySpeed(vehicle)
    bobTimer       = 0.0

    SetCamFov(cam, currentFov)
    SetCamNearClip(cam, CFG.CAM_NEAR_CLIP)
    RenderScriptCams(true, true, CFG.TRANSITION_IN, true, true)
end

local function DestroyVehicleCamera()
    RenderScriptCams(false, true, CFG.TRANSITION_OUT, true, true)
    DestroyCam(cam, false)
    cam         = nil
    pitch       = 0.0
    offsetYaw   = 0.0
    bobOffset   = 0.0
    shakeAmount = 0.0
end

-- ============================================================
-- Server sync
-- ============================================================
RegisterNetEvent("fzt_fov:setMiopia", function(state)
    esMiope = state
end)

RegisterNetEvent("fzt_fov:setGlassesState", function(state)
    wearingGlasses = state
end)

-- ============================================================
-- Debug command  /fov
-- ============================================================
RegisterCommand("fov", function()
    CFG.DEBUG_ENABLED = not CFG.DEBUG_ENABLED
    local state = CFG.DEBUG_ENABLED and "~g~ON" or "~r~OFF"
    TriggerEvent("chatMessage", "DX3_Fov", {255,200,0}, "Debug overlay " .. state)
end, false)

-- ============================================================
-- Main loop
-- ============================================================
local lastTime = GetGameTimer()

CreateThread(function()
    while true do
        Wait(0)

        local now = GetGameTimer()
        local dt  = (now - lastTime) / 1000.0
        lastTime  = now

        local ped     = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        local shouldUseCamera =
            vehicle ~= 0 and
            GetPedInVehicleSeat(vehicle, -1) == ped and
            GetFollowVehicleCamViewMode() == 4

        if shouldUseCamera then
            if not cameraActive then
                cameraActive = true
                CreateVehicleCamera(ped)
            end

            -- FOV with smooth lerp
            local targetFov = GetBaseFov(vehicle)
            currentFov      = Lerp(currentFov, targetFov, CFG.FOV_LERP_SPEED)
            SetCamFov(cam, currentFov)

            -- Head bob & crash shake
            UpdateHeadBob(vehicle, dt)
            UpdateCrashShake(vehicle, dt)

            -- Mouse look
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)

            local mouseX = GetDisabledControlNormal(0, 1)
            local mouseY = GetDisabledControlNormal(0, 2)

            offsetYaw = offsetYaw - mouseX * CFG.MOUSE_SENSITIVITY
            pitch     = pitch     - mouseY * CFG.MOUSE_SENSITIVITY

            -- Auto-center yaw when mouse is idle
            if CFG.YAW_AUTOCENTER_SPEED > 0 and math.abs(mouseX) < 0.001 then
                offsetYaw = Lerp(offsetYaw, 0.0, CFG.YAW_AUTOCENTER_SPEED)
            end

            offsetYaw = math.max(CFG.YAW_MIN, math.min(CFG.YAW_MAX, offsetYaw))
            pitch     = math.max(CFG.PITCH_MIN, math.min(CFG.PITCH_MAX, pitch))

            -- Apply bob + shake on top of mouse rotation
            local sx, sy = GetShakeOffset()
            SetCamRot(
                cam,
                pitch + bobOffset + sy,
                0.0,
                GetEntityHeading(vehicle) + offsetYaw + sx,
                2
            )

            -- Debug overlay
            if CFG.DEBUG_ENABLED then
                local speedMph = GetVehicleSpeedMph(vehicle)
                local class    = GetVehicleClass(vehicle)
                DrawText2d(0.01, 0.05, 0.40,
                    string.format(
                        "~y~DX3_Fov Debug~w~\nFOV: %.1f / %.1f\nSpeed: %.0f mph\nClass: %d (%s)\nYaw: %.1f  Pitch: %.1f\nBob: %.3f  Shake: %.3f",
                        currentFov, targetFov, speedMph,
                        class, GetVehicleClassName(class),
                        offsetYaw, pitch, bobOffset, shakeAmount
                    )
                )
            end

        else
            if cameraActive then
                cameraActive = false
                DestroyVehicleCamera()
            end
        end

        -- Slight wait when camera is inactive to save CPU
        if not cameraActive then Wait(50) end
    end
end)

-- ============================================================
-- Minimal text draw helper (used for debug)
-- ============================================================
function DrawText2d(x, y, scale, text)
    SetTextFont(0)
    SetTextProportional(true)
    SetTextScale(scale, scale)
    SetTextColour(255, 255, 255, 220)
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentSubstringPlayerName(text)
    DrawText(x, y)
end
