-- Settings for the built-in standalone layer (bridge/client.lua, bridge/server.lua).
-- This replaces prp-bridge: prp-dartboard now talks to qb-core directly.
CompatConfig = {
    -- Which target resource the dartboard interactions are registered with.
    --   "auto"      -> uses whichever of qb-target / ox_target is running
    --   "qb-target" -> force qb-target
    --   "ox_target" -> force ox_target
    Target = "auto",

    -- How notifications are shown to players.
    --   "ox_lib" -> ox_lib popups (lib.notify)
    --   "qb"     -> qb-core notifications (QBCore.Functions.Notify)
    Notify = "ox_lib",
}
