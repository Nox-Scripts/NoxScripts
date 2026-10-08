-- ================================================================
--  DX3_Fov — hud.lua  (Ultimate Edition v3.0)
--  Handles: speedometer, gear indicator, vehicle class tag,
--           cinematic letterbox bars at high speed
-- ================================================================

local CFG = DX3_FOV_CONFIG

-- ============================================================
-- Helpers
-- ============================================================
local CLASS_NAMES = {
    [0]="COMPACT",[1]="SEDAN",[2]="SUV",[3]="COUPE",[4]="MUSCLE",
    [5]="SPORT",[6]="SUPER",[7]="MOTO",[8]="OFF-ROAD",
    [9]="INDUSTRIAL",[10]="UTILITY",[11]="VAN",[12]="BICYCLE",
    [13]="BOAT",[14]="HELICOPTER",[15]="PLANE",[16]="SERVICE",
    [17]="EMERGENCY",[18]="MILITARY",[19]="COMMERCIAL",[20]="TRAIN",
}

local function DrawTextAt(x, y, scale, r, g, b, a, text, font, centre)
    SetTextFont(font or 4)
    SetTextProportional(true)
    SetTextScale(scale, scale)
    SetTextColour(r, g, b, a)
    SetTextDropshadow(2, 0, 0, 0, 180)
    if centre then SetTextJustification(0) end
    SetTextEntry("STRING")
    AddTextComponentSubstringPlayerName(text)
    DrawText(x, y)
end

local function DrawRect2(x, y, w, h, r, g, b, a)
    DrawRect(x, y, w, h, r, g, b, a)
end

local function Lerp(a, b, t)
    return a + (b - a) * t
end

-- ============================================================
-- Letterbox state
-- ============================================================
local letterboxCurrent = 0.0

-- ============================================================
-- Main loop
-- ============================================================
CreateThread(function()
    while true do
        -- Nothing to draw: sleep instead of running every frame
        if not (CFG.HUD_ENABLED or CFG.LETTERBOX_ENABLED) then
            Wait(1000)
            goto continue
        end

        Wait(0)

        local ped     = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        local isDriver =
            vehicle ~= 0 and
            GetPedInVehicleSeat(vehicle, -1) == ped

        -- ======================================================
        -- SPEEDOMETER & HUD
        -- ======================================================
        if CFG.HUD_ENABLED and isDriver then
            local speedRaw = GetEntitySpeed(vehicle)
            local speed    = CFG.HUD_UNITS == "mph"
                             and speedRaw * 2.23694
                             or  speedRaw * 3.6

            local gear    = GetVehicleCurrentGear(vehicle)
            local maxGear = GetVehicleHighGear(vehicle)
            local rpm     = GetVehicleCurrentRpm(vehicle)
            local class   = GetVehicleClass(vehicle)

            local col     = CFG.HUD_COLOUR
            local px      = CFG.HUD_POSITION_X
            local py      = CFG.HUD_POSITION_Y
            local sc      = CFG.HUD_SCALE

            -- Speed number
            DrawTextAt(
                px, py,
                sc * 1.5,
                col.r, col.g, col.b, col.a,
                string.format("%.0f", speed),
                1, false
            )

            -- Unit label
            DrawTextAt(
                px + 0.022, py + 0.022,
                sc * 0.65,
                col.r, col.g, col.b, col.a - 60,
                string.upper(CFG.HUD_UNITS),
                4, false
            )

            -- Gear
            if CFG.HUD_SHOW_GEAR then
                local gearLabel = gear == 0 and "R" or tostring(gear)
                -- Highlight when at max gear
                local gr = gear == maxGear and 100 or col.r
                local gg = gear == maxGear and 255 or col.g
                local gb = gear == maxGear and 100 or col.b
                DrawTextAt(
                    px - 0.03, py,
                    sc * 1.1,
                    gr, gg, gb, col.a,
                    "G" .. gearLabel,
                    4, false
                )
            end

            -- Vehicle class tag
            if CFG.HUD_SHOW_CLASS then
                DrawTextAt(
                    px, py + 0.034,
                    sc * 0.50,
                    col.r, col.g, col.b, col.a - 80,
                    CLASS_NAMES[class] or "VEHICLE",
                    4, false
                )
            end

            -- RPM bar (thin horizontal bar above speed)
            local barW  = 0.06
            local barH  = 0.004
            local barX  = px + barW / 2 - 0.01
            local barY  = py - 0.015
            -- Background
            DrawRect2(barX, barY, barW, barH, 30, 30, 30, 180)
            -- Fill — goes red when RPM > 0.85
            local fillW  = barW * rpm
            local fillR  = rpm > 0.85 and 255 or col.r
            local fillG  = rpm > 0.85 and 60  or col.g
            local fillB  = rpm > 0.85 and 60  or col.b
            if fillW > 0.001 then
                DrawRect2(barX - (barW - fillW) / 2, barY, fillW, barH, fillR, fillG, fillB, 220)
            end
        end

        -- ======================================================
        -- CINEMATIC LETTERBOX
        -- ======================================================
        if CFG.LETTERBOX_ENABLED and isDriver then
            local speedMph  = GetEntitySpeed(vehicle) * 2.23694
            local minS      = CFG.LETTERBOX_SPEED_MPH
            local maxS      = CFG.LETTERBOX_MAX_MPH
            local targetBar = 0.0

            if speedMph > minS then
                local t   = math.min((speedMph - minS) / math.max(maxS - minS, 1.0), 1.0)
                targetBar = t * CFG.LETTERBOX_MAX_SIZE
            end

            letterboxCurrent = Lerp(letterboxCurrent, targetBar, 0.04)

            if letterboxCurrent > 0.001 then
                local h = letterboxCurrent
                -- Top bar
                DrawRect2(0.5, h / 2, 1.0, h, 0, 0, 0, 255)
                -- Bottom bar
                DrawRect2(0.5, 1.0 - h / 2, 1.0, h, 0, 0, 0, 255)
            end
        elseif not isDriver then
            -- Fade out letterbox when not driving
            letterboxCurrent = Lerp(letterboxCurrent, 0.0, 0.06)
            if letterboxCurrent > 0.001 then
                local h = letterboxCurrent
                DrawRect2(0.5, h / 2, 1.0, h, 0, 0, 0, 255)
                DrawRect2(0.5, 1.0 - h / 2, 1.0, h, 0, 0, 0, 255)
            end
        end

        ::continue::
    end
end)

