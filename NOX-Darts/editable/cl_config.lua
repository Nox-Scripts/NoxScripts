Config = {
    BuildRevision = "4f6f7e5e1f41bffc63c207d578fcf43c",
    DartboardModel = GetHashKey('prop_dart_bd_cab_01'),
    DartboardModelName = "prop_dart_bd_cab_01",
    StartingScore = 301,

    -- Press E near a dartboard to open a menu with the same options as qb-target.
    -- Only needed if qb-target ever stops showing the options. true = on, false = off.
    KeyFallback = false,

    -- true  = every dartboard cabinet in the world (the standard GTA one, prop_dart_bd_cab_01)
    --         can be played, not just boards placed with /placedartboard.
    -- false = only boards placed with /placedartboard. Keep this the same as sv_config.lua.
    AllowAnyDartboard = true,
}

-- Controls list: https://docs.fivem.net/docs/game-references/controls/
Config.Keybinds = {
    ThrowDarts = 142, -- LMB
    ConfirmPlaceDartboard = 24, -- LMB
    CancelPlaceDartboard = 200, -- ESC
}

Config.DartboardsRenderDistance = 50.0