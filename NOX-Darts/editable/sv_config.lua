-- Public server configuration documented at:
-- https://docs.prodigyrp.net/civ/prp-dartboard/usage.html
Config = {
    -- Starting score for both players. Keep this aligned with editable/cl_config.lua.
    StartingScore = 301,

    -- Discord webhook used for wager and dartboard placement/removal logs.
    -- Leave empty to disable Discord logging.
    LogWebhookURL = "",

    -- Admin dartboard placement command (without the leading slash).
    PlaceDartboardCommandName = "placedartboard",

    -- Principal allowed to place/remove dartboards.
    PlaceDartboardCommandRestriction = "group.admin",

    -- Development-only: allow a lobby owner to start a zero-wager practice
    -- game without a second player. Disable this on production servers if you
    -- want to enforce the original two-player-only flow.
    DevelopmentSoloMode = true,

    -- true  = any dartboard cabinet in the world can be played (registered automatically
    --         the first time someone creates a lobby at it). Keep this the same as cl_config.lua.
    -- false = only boards placed with /placedartboard.
    AllowAnyDartboard = true,
}

-- Internal/server tuning values retained from the shipped resource.
ServerConfig = {
    BuildSignature = "4f6f7e5e1f41bffc63c207d578fcf43c",
    WagerMoneyType = "cash",
    LobbyProximity = 10.0,
    DartboardRemoveProximity = 2.0,
    BoardMatchTolerance = 1.5,
    DartSyncMaxDistance = 1.0,
    DartMissSyncMaxDistance = 15.0,
    DartBoardPlaneTolerance = 0.35,
    DartRotationMagnitudeLimit = 3600.0,
    AdminPlacementMaxDistance = 15.0,
    JoinRequestTimeoutMs = 7000,
    PayoutPersistenceRetryMs = 30000,
    PayoutDeliveryRetryMs = 60000,
    DatabaseRetryMs = 5000,
    GameAbandonDistance = 12.5,
    GameAbandonSeconds = 15,
    GameAbandonCheckIntervalMs = 1000,
}
