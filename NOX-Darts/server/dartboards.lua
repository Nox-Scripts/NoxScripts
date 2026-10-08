Dartboards = {}
DartboardsLoaded = false

local PendingBoardPlacements = {}
local WaitingForDartboards = {}
local databaseLoaderRunning = false

local adminPrincipal = (Config and Config.PlaceDartboardCommandRestriction) or "group.admin"
local placeCommandName = (Config and Config.PlaceDartboardCommandName) or "placedartboard"
local placeCommandAce = ("command.%s"):format(placeCommandName)

local function SendWebhookLog(title, message, args)
    local webhook = Config and Config.LogWebhookURL
    if type(webhook) ~= "string" or webhook == "" then
        return
    end

    local ok, err = pcall(bridge.log.send, webhook, title, message, args)
    if not ok then
        Trace("Failed to send dartboard webhook log", err)
    end
end

-- bridge.fw.registerCommand (bridge/server.lua) delegates the documented principal restriction
-- to ox_lib. ox_lib maps that principal to `command.<commandName>`; use the
-- same ACE for the placement/removal net events so command and target security
-- cannot drift apart.
function IsServerAdmin(source)
    if tonumber(source) == 0 then
        return true
    end

    if IsPlayerAceAllowed(tostring(source), placeCommandAce) then
        return true
    end

    -- Fallback: any QBCore admin / god may place and remove dartboards.
    return bridge.fw.isQbAdmin(source)
end

local function ToFiniteNumber(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return nil
    end
    return value
end

local function GetPlayerDistanceToCoords(src, x, y, z)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then
        return math.huge
    end

    local coords = GetEntityCoords(ped)
    local dx, dy, dz = coords.x - x, coords.y - y, coords.z - z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function EnsurePayoutSchema()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `prp_dartboard_payouts` (
            `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(128) NOT NULL,
            `amount` BIGINT UNSIGNED NOT NULL,
            `money_type` VARCHAR(32) NOT NULL,
            `reason` VARCHAR(255) NULL,
            `status` VARCHAR(16) NOT NULL DEFAULT 'pending',
            `delivery_token` VARCHAR(128) NULL,
            `processing_at` TIMESTAMP NULL,
            `settlement_key` VARCHAR(191) NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_prp_dartboard_payouts_identifier` (`identifier`),
            KEY `idx_prp_dartboard_payouts_pending` (`identifier`, `status`),
            UNIQUE KEY `uq_prp_dartboard_payouts_settlement` (`settlement_key`)
        )
    ]])

    -- Upgrade v5 installations automatically. The public dartboard docs say no
    -- manual SQL should be required, so migrations live in resource startup.
    local columns = MySQL.query.await([[
        SELECT COLUMN_NAME FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'prp_dartboard_payouts'
    ]]) or {}
    local present = {}
    for _, row in ipairs(columns) do
        present[row.COLUMN_NAME or row.column_name] = true
    end

    -- Keep migrations ordered and independent. Do not use pairs() here: Lua table
    -- iteration order is undefined, and the old AFTER clauses made later columns
    -- depend on earlier ones having already been created. That could make an
    -- upgrade attempt `delivery_token AFTER status` before `status` existed.
    local alters = {
        { "status", [[ALTER TABLE `prp_dartboard_payouts` ADD COLUMN `status` VARCHAR(16) NOT NULL DEFAULT 'pending']] },
        { "delivery_token", [[ALTER TABLE `prp_dartboard_payouts` ADD COLUMN `delivery_token` VARCHAR(128) NULL]] },
        { "processing_at", [[ALTER TABLE `prp_dartboard_payouts` ADD COLUMN `processing_at` TIMESTAMP NULL]] },
        { "settlement_key", [[ALTER TABLE `prp_dartboard_payouts` ADD COLUMN `settlement_key` VARCHAR(191) NULL]] },
    }
    for _, migration in ipairs(alters) do
        local column, query = migration[1], migration[2]
        if not present[column] then
            MySQL.query.await(query)
            present[column] = true
        end
    end

    local indexes = MySQL.query.await([[SHOW INDEX FROM `prp_dartboard_payouts`]]) or {}
    local indexPresent = {}
    for _, row in ipairs(indexes) do
        indexPresent[row.Key_name or row.key_name] = true
    end
    if not indexPresent.idx_prp_dartboard_payouts_pending then
        MySQL.query.await([[ALTER TABLE `prp_dartboard_payouts` ADD KEY `idx_prp_dartboard_payouts_pending` (`identifier`, `status`)]])
    end
    if not indexPresent.uq_prp_dartboard_payouts_settlement then
        MySQL.query.await([[ALTER TABLE `prp_dartboard_payouts` ADD UNIQUE KEY `uq_prp_dartboard_payouts_settlement` (`settlement_key`)]])
    end
end

local function EnsureActiveGameSchema()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `prp_dartboard_active_games` (
            `game_uuid` VARCHAR(64) NOT NULL,
            `board_id` INT UNSIGNED NULL,
            `player_one_identifier` VARCHAR(128) NOT NULL,
            `player_two_identifier` VARCHAR(128) NOT NULL,
            `wager` BIGINT UNSIGNED NOT NULL,
            `money_type` VARCHAR(32) NOT NULL,
            `outcome` VARCHAR(16) NOT NULL DEFAULT 'active',
            `winner_identifier` VARCHAR(128) NULL,
            `settlement_reason` VARCHAR(255) NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`game_uuid`)
        )
    ]])
end

function LoadDartboardsFromDatabase()
    DartboardsLoaded = false

    local success, rows = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS `prp_dartboards` (
                `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
                `x` FLOAT NOT NULL,
                `y` FLOAT NOT NULL,
                `z` FLOAT NOT NULL,
                `rot_x` FLOAT NOT NULL,
                `rot_y` FLOAT NOT NULL,
                `rot_z` FLOAT NOT NULL,
                PRIMARY KEY (`id`)
            )
        ]])

        EnsurePayoutSchema()
        EnsureActiveGameSchema()
        return MySQL.query.await("SELECT id, x, y, z, rot_x, rot_y, rot_z FROM prp_dartboards", {})
    end)

    if not success then
        print(("[%s] Failed to initialize dartboard database schema: %s"):format(GetCurrentResourceName(), tostring(rows)))
        return false
    end

    local loaded = {}
    for _, row in ipairs(rows or {}) do
        loaded[row.id] = { id = row.id, data = { row.x, row.y, row.z, row.rot_x, row.rot_y, row.rot_z } }
    end
    Dartboards = loaded
    DartboardsLoaded = true

    print(("^2[%s] Loaded %d dartboard(s) from the database.^0"):format(GetCurrentResourceName(), GetKeyCount(loaded)))
    if next(loaded) == nil then
        print(("^3[%s] No dartboards placed yet. Join the server as an admin/god and use /%s to place one.^0"):format(
            GetCurrentResourceName(), placeCommandName))
    end

    for src in pairs(WaitingForDartboards) do
        if GetPlayerName(src) then
            SendDartboardsToPlayer(src)
        end
        WaitingForDartboards[src] = nil
    end

    return true
end

function SendDartboardsToPlayer(source)
    -- Map boards ("world" boards) already exist in the game world; clients must not spawn copies.
    local placed = {}
    for id, board in pairs(Dartboards) do
        if not board.world then
            placed[id] = board
        end
    end
    TriggerClientEvent("prp-dartboard:client:setDartboards", source, placed, IsServerAdmin(source))
end

RegisterNetEvent("prp-dartboard:server:requestDartboards", function()
    local src = source
    if DartboardsLoaded then
        SendDartboardsToPlayer(src)
        return
    end

    -- Keep the source queued until the database loader eventually succeeds.
    -- This survives transient oxmysql/database outages that last longer than a
    -- fixed startup timeout.
    WaitingForDartboards[src] = true
end)

RegisterNetEvent("prp-dartboard:server:addDartboard", function(x, y, z, rotX, rotY, rotZ)
    local src = source
    if not IsServerAdmin(src) or not DartboardsLoaded then
        return
    end

    x, y, z = ToFiniteNumber(x), ToFiniteNumber(y), ToFiniteNumber(z)
    rotX, rotY, rotZ = ToFiniteNumber(rotX), ToFiniteNumber(rotY), ToFiniteNumber(rotZ)
    if not (x and y and z and rotX and rotY and rotZ) then
        return
    end
    if GetPlayerDistanceToCoords(src, x, y, z) > (ServerConfig.AdminPlacementMaxDistance or 15.0) then
        return
    end

    local duplicateTolerance = ServerConfig.BoardMatchTolerance or 1.5
    for _, dartboard in pairs(Dartboards) do
        local dx, dy, dz = dartboard.data[1] - x, dartboard.data[2] - y, dartboard.data[3] - z
        if math.sqrt(dx * dx + dy * dy + dz * dz) <= duplicateTolerance then
            bridge.fw.notify(src, "error", locale("DARTBOARD_ALREADY_EXISTS"))
            return
        end
    end
    for _, pending in pairs(PendingBoardPlacements) do
        local dx, dy, dz = pending.x - x, pending.y - y, pending.z - z
        if math.sqrt(dx * dx + dy * dy + dz * dz) <= duplicateTolerance then
            bridge.fw.notify(src, "error", locale("DARTBOARD_ALREADY_EXISTS"))
            return
        end
    end

    -- Serialize overlapping placements across the asynchronous SQL insert.
    local placementToken = {}
    PendingBoardPlacements[placementToken] = { x = x, y = y, z = z }
    local insertOk, insertId = pcall(MySQL.insert.await,
        "INSERT INTO prp_dartboards (x, y, z, rot_x, rot_y, rot_z) VALUES (?, ?, ?, ?, ?, ?)",
        { x, y, z, rotX, rotY, rotZ }
    )
    PendingBoardPlacements[placementToken] = nil
    if not insertOk or not insertId then
        Trace("Failed to insert new dartboard into the database", insertId)
        return
    end

    Dartboards[insertId] = { id = insertId, data = { x, y, z, rotX, rotY, rotZ } }

    local logMessage = locale("PLACED_DARTBOARD_LOG", GetPlayerName(src), x, y, z, rotX, rotY, rotZ)
    print(logMessage)
    SendWebhookLog("Dartboard Placed", logMessage)
    bridge.fw.notify(src, "success", locale("DARTBOARD_PLACED_NOTIFICATION"))

    TriggerClientEvent("prp-dartboard:client:addDartboard", -1, insertId, x, y, z, rotX, rotY, rotZ)
end)

RegisterNetEvent("prp-dartboard:server:removeDartboard", function(x, y, z)
    local src = source
    if not IsServerAdmin(src) or not DartboardsLoaded then
        return
    end

    x, y, z = ToFiniteNumber(x), ToFiniteNumber(y), ToFiniteNumber(z)
    if not (x and y and z) then
        return
    end

    local closestId, closestDist = nil, ServerConfig.DartboardRemoveProximity
    for id, dartboard in pairs(Dartboards) do
        if not dartboard.removing and not dartboard.world then
            local dx, dy, dz = dartboard.data[1] - x, dartboard.data[2] - y, dartboard.data[3] - z
            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            if dist <= closestDist then
                closestId, closestDist = id, dist
            end
        end
    end

    if not closestId then
        return
    end

    local stored = Dartboards[closestId]
    local storedX, storedY, storedZ = stored.data[1], stored.data[2], stored.data[3]
    if GetPlayerDistanceToCoords(src, storedX, storedY, storedZ) > (ServerConfig.AdminPlacementMaxDistance or 15.0) then
        return
    end
    if IsDartboardInUse and IsDartboardInUse(closestId) then
        bridge.fw.notify(src, "error", locale("DARTBOARD_IN_USE"))
        return
    end

    -- Mark the canonical board unavailable before yielding to SQL. Without this,
    -- a new lobby can be created during the DELETE await and end up attached to
    -- a board that is removed underneath it.
    stored.removing = true
    local deleteOk, affectedRows = pcall(MySQL.update.await, "DELETE FROM prp_dartboards WHERE id = ?", { closestId })
    if not deleteOk or not affectedRows or affectedRows < 1 then
        stored.removing = nil
        Trace("Failed to remove dartboard from the database", closestId, affectedRows)
        return
    end
    Dartboards[closestId] = nil

    local logMessage = locale("REMOVED_DARTBOARD_LOG", GetPlayerName(src), storedX, storedY, storedZ)
    print(logMessage)
    SendWebhookLog("Dartboard Removed", logMessage)
    bridge.fw.notify(src, "success", locale("DARTBOARD_REMOVED"))

    TriggerClientEvent("prp-dartboard:client:removeDartboard", -1, closestId, storedX, storedY, storedZ)
end)

-- Register through the built-in bridge so the documented command restriction is handled
-- consistently across supported frameworks and ox_lib adds the command ACE.
-- The command itself is open; the admin check happens inside IsServerAdmin so QBCore
-- admins/gods work without any ACE / principal setup.
bridge.fw.registerCommand(
    placeCommandName,
    locale("CMD_DARTBOARD_PLACE_HELP"),
    nil,
    nil,
    function(src)
        if src == 0 then
            return
        end
        if not IsServerAdmin(src) then
            bridge.fw.notify(src, "error", "Only admins can place dartboards.")
            return
        end
        TriggerClientEvent("prp-dartboard:client:placeDartboard", src)
    end
)

-- Re-send the boards once the character has loaded so the admin-only "Remove" option is
-- correct (permissions are not known yet when the resource first starts on the client).
AddEventHandler("prp-dartboard:server:playerLoad", function(src)
    src = tonumber(src)
    if src and src > 0 and DartboardsLoaded then
        SendDartboardsToPlayer(src)
    end
end)

local function StartDatabaseLoader()
    if databaseLoaderRunning then
        return
    end
    databaseLoaderRunning = true

    CreateThread(function()
        local retryMs = math.max(1000, tonumber(ServerConfig.DatabaseRetryMs) or 5000)
        repeat
            if LoadDartboardsFromDatabase() then
                break
            end
            Wait(retryMs)
        until false
        databaseLoaderRunning = false
    end)
end

AddEventHandler("onResourceStart", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    StartDatabaseLoader()
end)

AddEventHandler("playerDropped", function()
    WaitingForDartboards[source] = nil
end)

AddEventHandler("prp-dartboard:server:playerUnload", function(src)
    src = tonumber(src) or source
    if src and src ~= 0 then
        WaitingForDartboards[src] = nil
    end
end)
