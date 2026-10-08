-- ================================================================
--  DX3_Fov — CONFIG  (Ultimate Edition v3.1)
--  This is the ONLY file you need to edit.
-- ================================================================

DX3_FOV_CONFIG = {

    -- ============================================================
    --  CAMERA POSITION (head bone attachment)
    -- ============================================================
    CAM_OFFSET_X  = 0.0,
    CAM_OFFSET_Y  = -0.0,
    CAM_OFFSET_Z  = 0.69,
    CAM_NEAR_CLIP = -0.0,

    -- ============================================================
    --  BASE FOV PER VEHICLE CLASS
    -- ============================================================
    FOV_DEFAULT = 78.0,

    FOV_BY_CLASS = {
        [0]  = 100.0, -- Compact
        [1]  = 100.0, -- Sedan
        [2]  = 100.0, -- SUV
        [3]  = 100.0, -- Coupe
        [4]  = 100.0, -- Muscle
        [5]  = 100.0, -- Sport
        [6]  = 100.0, -- Super
        [7]  = 80.0, -- Motorcycle
        [8]  = 100.0, -- Off-road
        [9]  = 100.0, -- Industrial
        [10] = 100.0, -- Utility
        [11] = 100.0, -- Van
        [14] = 100.0, -- Helicopter
        [15] = 100.0, -- Plane
        [17] = 100.0, -- Emergency
        [18] = 100.0, -- Military
        [19] = 100.0, -- Commercial
    },

    -- ============================================================
    --  SPEED-BASED FOV BREATHING
    -- ============================================================
    FOV_SPEED_ENABLED   = false,
    FOV_SPEED_MAX_BONUS = 5.0,
    FOV_SPEED_REF_MPH   = 150.0,

    -- ============================================================
    --  FOV TRANSITIONS
    -- ============================================================
    FOV_LERP_SPEED  = 0.06,
    TRANSITION_IN   = 500,
    TRANSITION_OUT  = 300,

    -- ============================================================
    --  MYOPIA
    -- ============================================================
    FOV_MYOPIA       = 100.0,
    FOV_GLASSES      = 100.0,
    BLUR_STRENGTH    = 0.8,
    BLUR_FADE_IN     = 1000,
    BLUR_FADE_OUT    = 500,
    BLUR_TIMECYCLE   = "Drunk",
    BLUR_ON_FOOT     = false,
    BLUR_POLL_MS     = 200,

    -- ============================================================
    --  MOUSE LOOK
    -- ============================================================
    MOUSE_SENSITIVITY = 5.0,

    PITCH_MIN = -40.0,
    PITCH_MAX =  40.0,

    YAW_MIN   = -90.0,
    YAW_MAX   =  90.0,

    YAW_AUTOCENTER_SPEED = 0.0,

    -- ============================================================
    --  HEAD BOB
    -- ============================================================
    HEADBOB_ENABLED     = false,
    HEADBOB_AMPLITUDE   = 0.7,
    HEADBOB_SPEED       = 1.8,
    HEADBOB_SPEED_SCALE = false,

    -- ============================================================
    --  CRASH SHAKE
    -- ============================================================
    CRASH_SHAKE_ENABLED   = false,
    CRASH_SHAKE_THRESHOLD = 9.0,
    CRASH_SHAKE_INTENSITY = 0.05,
    CRASH_SHAKE_DURATION  = 200,
    CRASH_SHAKE_DECAY     = 1.0,

    -- ============================================================
    --  CINEMATIC LETTERBOX
    -- ============================================================
    LETTERBOX_ENABLED   = false,
    LETTERBOX_SPEED_MPH = 80.0,
    LETTERBOX_MAX_MPH   = 140.0,
    LETTERBOX_MAX_SIZE  = 0.06,

    -- ============================================================
    --  ON-FOOT FOV SHIFTS
    -- ============================================================
    FOOT_FOV_ENABLED    = false,

    FOOT_FOV_DEFAULT    = 150.0,
    FOOT_FOV_SPRINT     = 120.0,
    FOOT_FOV_AIM        = 180.0,
    FOOT_FOV_COVER      = 90.0,

    FOOT_FOV_LERP_SPEED = 0.10,

    -- ============================================================
    --  HUD SPEEDOMETER
    -- ============================================================
    HUD_ENABLED     = false,
    HUD_UNITS       = "mph",

    HUD_POSITION_X  = 0.94,
    HUD_POSITION_Y  = 0.92,

    HUD_SCALE       = 0.55,

    HUD_SHOW_CLASS  = false,
    HUD_SHOW_GEAR   = false,

    HUD_COLOUR = {
        r = 255,
        g = 255,
        b = 255,
        a = 200
    },

    -- ============================================================
    --  DEBUG
    -- ============================================================
    DEBUG_ENABLED = false,
}