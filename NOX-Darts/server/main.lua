local _serverRevision = "4f6f7e5e1f41bffc63c207d578fcf43c"
local Lobbies = {}
local Games = {}
local PlayerLobby = {}
local PlayerGame = {}
local PlayerSpectating = {}
local PendingPayouts = {}
local PayoutProcessing = {}
local PayoutCleanupPending = {}
local PendingSettlements = {}
local PendingJoinRequests = {}
local ProcessPendingPayouts
local nextLobbyId = 1
local nextJoinRequestId = 1

local DART_SEGMENTS = {
    [0] = 20, [1] = 1, [2] = 18, [3] = 4, [4] = 13, [5] = 6, [6] = 10, [7] = 15,
    [8] = 2, [9] = 17, [10] = 3, [11] = 19, [12] = 7, [13] = 16, [14] = 8, [15] = 11,
    [16] = 14, [17] = 9, [18] = 12, [19] = 5,
}

local function DistanceBetween(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function GetDartboardCoords(dartboard)
    local data = dartboard and dartboard.data
    if not data then
        return nil
    end
    return vector3(data[1], data[2], data[3])
end

local function GetDartboardRotation(dartboard)
    local data = dartboard and dartboard.data
    if not data then
        return nil
    end
    return vector3(data[4], data[5], data[6])
end

local function ResolveStoredDartboard(coords)
    if type(Dartboards) ~= "table" then
        return nil
    end

    local tolerance = ServerConfig.BoardMatchTolerance or 1.5
    local closestBoard, closestDistance
    for _, dartboard in pairs(Dartboards) do
        local boardCoords = dartboard and not dartboard.removing and GetDartboardCoords(dartboard)
        if boardCoords then
            local distance = DistanceBetween(coords, boardCoords)
            if distance <= tolerance and (not closestDistance or distance < closestDistance) then
                closestBoard, closestDistance = dartboard, distance
            end
        end
    end

    return closestBoard
end

-- FiveM rotation order 2 uses ZXY. The board placement flow stores rotations
-- with that order, so project the submitted world-space dart coordinate back
-- into the stored board's local coordinate system before classifying score.
local function WorldToBoardLocal(boardCoords, boardRotation, worldCoords)
    local rx = math.rad(boardRotation.x)
    local ry = math.rad(boardRotation.y)
    local rz = math.rad(boardRotation.z)
    local sx, cx = math.sin(rx), math.cos(rx)
    local sy, cy = math.sin(ry), math.cos(ry)
    local sz, cz = math.sin(rz), math.cos(rz)

    -- R = Rz * Rx * Ry; R^T is the inverse for this orthonormal basis.
    local r11 = cz * cy - sz * sx * sy
    local r12 = -sz * cx
    local r13 = cz * sy + sz * sx * cy
    local r21 = sz * cy + cz * sx * sy
    local r22 = cz * cx
    local r23 = sz * sy - cz * sx * cy
    local r31 = -cx * sy
    local r32 = sx
    local r33 = cx * cy

    local dx = worldCoords.x - boardCoords.x
    local dy = worldCoords.y - boardCoords.y
    local dz = worldCoords.z - boardCoords.z

    return vector3(
        r11 * dx + r21 * dy + r31 * dz,
        r12 * dx + r22 * dy + r32 * dz,
        r13 * dx + r23 * dy + r33 * dz
    )
end

local function CalculateAuthoritativeDartScore(game, worldCoords)
    if not game.dartboardRotation then
        return 0, false
    end

    local localOffset = WorldToBoardLocal(game.dartboardCoords, game.dartboardRotation, worldCoords)
    if math.abs(localOffset.y) > (ServerConfig.DartBoardPlaneTolerance or 0.35) then
        return 0, false
    end

    -- Match the tiny center offset and ring radii used by the client visual
    -- scoring helper so the server and client classify the same board regions.
    local x = localOffset.x + 0.0041
    local z = localOffset.z + 0.0002
    local radius = math.sqrt(x * x + z * z)

    if radius < 0.009 then
        return 50, true
    elseif radius < 0.021 then
        return 25, false
    elseif radius >= 0.226 then
        return 0, false
    end

    local multiplier = 1
    local isDouble = false
    if radius > 0.1285 and radius < 0.1405 then
        multiplier = 3
    elseif radius > 0.2132 and radius < 0.226 then
        multiplier = 2
        isDouble = true
    end

    local angle = math.deg(math.atan(x, z))
    if angle < 0 then
        angle = angle + 360
    end
    local segmentIndex = math.floor(((angle + 9.0) % 360.0) / 18.0)
    local segment = DART_SEGMENTS[segmentIndex]
    if not segment then
        return 0, false
    end

    return segment * multiplier, isDouble
end

local function ResetTurnTracking(game)
    game.turnDarts = {}
    game.turnTotal = 0
    game.lastDartDouble = false
end

local function HasMatchingIdentifier(src, identifier)
    if not src or not identifier or not GetPlayerName(src) then
        return false
    end

    local currentIdentifier = bridge.fw.getIdentifier(src)
    return currentIdentifier ~= nil and tostring(currentIdentifier) == tostring(identifier)
end

local function QueuePayout(identifier, amount, reason, moneyType)
    amount = tonumber(amount) or 0
    if not identifier or amount <= 0 then
        return
    end

    identifier = tostring(identifier)
    moneyType = tostring(moneyType or ServerConfig.WagerMoneyType or "cash")
    local inserted, insertId = pcall(
        MySQL.insert.await,
        [[INSERT INTO prp_dartboard_payouts
            (identifier, amount, money_type, reason, status)
          VALUES (?, ?, ?, ?, 'pending')]],
        { identifier, amount, moneyType, reason or "Deferred dart payout" }
    )
    if inserted and insertId then
        Trace("Queued persistent dart payout", identifier, amount, moneyType, insertId)
        return
    end

    local byMoneyType = PendingPayouts[identifier]
    if not byMoneyType then
        byMoneyType = {}
        PendingPayouts[identifier] = byMoneyType
    end
    byMoneyType[moneyType] = (byMoneyType[moneyType] or 0) + amount
    Trace("Failed to persist dart payout; using memory fallback", identifier, amount, moneyType, insertId)
end

local function PayPlayerOrQueue(src, identifier, amount, reason, moneyType)
    amount = tonumber(amount) or 0
    if amount <= 0 then
        return true
    end
    if not identifier then
        return false
    end

    moneyType = tostring(moneyType or ServerConfig.WagerMoneyType or "cash")

    -- Server IDs are connection-scoped while framework identifiers (citizenid) are
    -- character-scoped. Never credit a delayed payout to a source that has
    -- already loaded a different character.
    if HasMatchingIdentifier(src, identifier) and bridge.fw.addMoney(src, moneyType, amount, reason) then
        return true
    end

    QueuePayout(identifier, amount, reason, moneyType)
    return false
end

local function PersistMemoryPayoutsForIdentifier(identifier)
    local byMoneyType = PendingPayouts[identifier]
    if type(byMoneyType) ~= "table" then
        return
    end

    for moneyType, amount in pairs(byMoneyType) do
        amount = tonumber(amount) or 0
        if amount > 0 then
            local inserted, insertId = pcall(
                MySQL.insert.await,
                [[INSERT INTO prp_dartboard_payouts
                    (identifier, amount, money_type, reason, status)
                  VALUES (?, ?, ?, ?, 'pending')]],
                { identifier, amount, moneyType, "Deferred dart payout (memory recovery)" }
            )
            if inserted and insertId then
                -- Remove only the amount that was actually persisted. A new
                -- fallback payout may have been appended while the INSERT yielded.
                local current = PendingPayouts[identifier]
                local currentAmount = current and tonumber(current[moneyType]) or 0
                if currentAmount <= amount then
                    if current then
                        current[moneyType] = nil
                        if next(current) == nil then
                            PendingPayouts[identifier] = nil
                        end
                    end
                else
                    current[moneyType] = currentAmount - amount
                end
                Trace("Persisted memory fallback payout", identifier, amount, moneyType, insertId)
            end
        end
    end
end

local function FlushMemoryPayoutsToDatabase()
    local identifiers = {}
    for identifier in pairs(PendingPayouts) do
        identifiers[#identifiers + 1] = identifier
    end

    for _, identifier in ipairs(identifiers) do
        if not PayoutProcessing[identifier] then
            PayoutProcessing[identifier] = "persist"
            local ok, err = pcall(PersistMemoryPayoutsForIdentifier, identifier)
            PayoutProcessing[identifier] = nil
            if not ok then
                Trace("Failed to persist memory fallback payout", identifier, err)
            end
        end
    end
end

local function GenerateGameUuid()
    local uuid
    repeat
        uuid = ("%s-%s-%s"):format(os.time(), GetGameTimer(), math.random(100000, 999999))
    until not Games[uuid]
    return uuid
end

local function PersistActiveWager(uuid, lobby, playerOrder, playerIdentifiers, moneyType)
    if (tonumber(lobby.wager) or 0) <= 0 then
        return true
    end

    local playerOneIdentifier = playerIdentifiers[tostring(playerOrder[1])]
    local playerTwoIdentifier = playerIdentifiers[tostring(playerOrder[2])]
    if not playerOneIdentifier or not playerTwoIdentifier then
        return false
    end

    local ok, affected = pcall(
        MySQL.update.await,
        [[INSERT INTO prp_dartboard_active_games
            (game_uuid, board_id, player_one_identifier, player_two_identifier, wager, money_type, outcome)
          VALUES (?, ?, ?, ?, ?, ?, 'active')]],
        {
            uuid,
            tonumber(lobby.dartboardId),
            tostring(playerOneIdentifier),
            tostring(playerTwoIdentifier),
            math.floor(tonumber(lobby.wager) or 0),
            tostring(moneyType),
        }
    )
    return ok and tonumber(affected) and tonumber(affected) >= 1
end

local function FinalizeWinnerEscrow(uuid, winnerIdentifier, reason)
    if not uuid or not winnerIdentifier then
        return false
    end

    local settlementKey = ("game:%s:winner"):format(uuid)
    local ok, committed = pcall(MySQL.transaction.await, {
        {
            query = [[INSERT IGNORE INTO prp_dartboard_payouts
                (identifier, amount, money_type, reason, status, settlement_key)
              SELECT `winner_identifier`, `wager` * 2, `money_type`, COALESCE(`settlement_reason`, ?), 'pending', ?
              FROM prp_dartboard_active_games
              WHERE game_uuid = ? AND outcome = 'winner' AND winner_identifier = ?]],
            values = { reason or "Dart game winnings", settlementKey, uuid, tostring(winnerIdentifier) },
        },
        {
            query = [[DELETE FROM prp_dartboard_active_games
                      WHERE game_uuid = ? AND outcome = 'winner' AND winner_identifier = ?]],
            values = { uuid, tostring(winnerIdentifier) },
        },
    })
    return ok and committed == true
end

local function FinalizeRefundEscrow(uuid, reason)
    if not uuid then
        return false
    end

    local keyOne = ("game:%s:refund:1"):format(uuid)
    local keyTwo = ("game:%s:refund:2"):format(uuid)
    local refundReason = reason or "Dart game interrupted refund"
    local ok, committed = pcall(MySQL.transaction.await, {
        {
            query = [[INSERT IGNORE INTO prp_dartboard_payouts
                (identifier, amount, money_type, reason, status, settlement_key)
              SELECT `player_one_identifier`, `wager`, `money_type`, ?, 'pending', ?
              FROM prp_dartboard_active_games WHERE game_uuid = ?]],
            values = { refundReason, keyOne, uuid },
        },
        {
            query = [[INSERT IGNORE INTO prp_dartboard_payouts
                (identifier, amount, money_type, reason, status, settlement_key)
              SELECT `player_two_identifier`, `wager`, `money_type`, ?, 'pending', ?
              FROM prp_dartboard_active_games WHERE game_uuid = ?]],
            values = { refundReason, keyTwo, uuid },
        },
        {
            query = [[DELETE FROM prp_dartboard_active_games WHERE game_uuid = ?]],
            values = { uuid },
        },
    })
    return ok and committed == true
end

local function QueueWinnerSettlement(game, winnerSid, reason)
    if not game or (tonumber(game.wager) or 0) <= 0 then
        return true
    end

    local winnerIdentifier = game.playerIdentifiers and game.playerIdentifiers[tostring(winnerSid)]
    if not winnerIdentifier then
        return false
    end

    local marked, affected = pcall(
        MySQL.update.await,
        [[UPDATE prp_dartboard_active_games
          SET outcome = 'winner', winner_identifier = ?, settlement_reason = ?
          WHERE game_uuid = ?]],
        { tostring(winnerIdentifier), reason or "Dart game winnings", game.uuid }
    )
    if not marked or not affected or affected < 1
        or not FinalizeWinnerEscrow(game.uuid, winnerIdentifier, reason) then
        PendingSettlements[game.uuid] = {
            uuid = game.uuid,
            winnerIdentifier = tostring(winnerIdentifier),
            reason = reason or "Dart game winnings",
        }
        print(("[%s] Delayed dart wager settlement for game %s; it will be retried"):format(
            GetCurrentResourceName(), tostring(game.uuid)))
        return false
    end

    PendingSettlements[game.uuid] = nil
    if ProcessPendingPayouts then
        CreateThread(function()
            local loadedSource = bridge.fw.getSrcFromIdentifier(tostring(winnerIdentifier))
            if loadedSource then
                ProcessPendingPayouts(loadedSource)
            end
        end)
    end
    return true
end

local function RecoverAbandonedActiveGames()
    local ok, rows = pcall(
        MySQL.query.await,
        [[SELECT game_uuid, outcome, winner_identifier, settlement_reason
          FROM prp_dartboard_active_games ORDER BY created_at]],
        {}
    )
    if not ok then
        Trace("Failed to inspect interrupted dart games", rows)
        return false
    end

    local recovered = 0
    for _, row in ipairs(rows or {}) do
        local settled
        if row.outcome == "winner" and row.winner_identifier then
            settled = FinalizeWinnerEscrow(row.game_uuid, row.winner_identifier, row.settlement_reason)
        else
            -- No process survived to establish a forfeit/winner. Treat a hard
            -- restart as the documented no-forfeit cancellation and refund both stakes.
            settled = FinalizeRefundEscrow(row.game_uuid, "Dart game interrupted refund")
        end
        if settled then
            recovered = recovered + 1
        else
            print(("[%s] Failed to recover interrupted dart game %s; keeping escrow row for retry"):format(
                GetCurrentResourceName(), tostring(row.game_uuid)))
        end
    end

    if recovered > 0 then
        print(("[%s] Recovered %d interrupted dart wager escrow(s)"):format(GetCurrentResourceName(), recovered))
    end
    return true
end

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

local function NormalizeLobbyId(lobbyId)
    return tonumber(lobbyId) or lobbyId
end

local function ToFiniteNumber(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return nil
    end
    return value
end

local function NormalizeCoords(coords)
    if not coords then
        return nil
    end

    local x = ToFiniteNumber(coords.x)
    local y = ToFiniteNumber(coords.y)
    local z = ToFiniteNumber(coords.z)
    if not (x and y and z) then
        return nil
    end

    return vector3(x, y, z)
end

function GetDistanceToPlayer(source, coords)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 or not coords then
        return math.huge
    end

    local playerCoords = GetEntityCoords(ped)
    local dx, dy, dz = playerCoords.x - coords.x, playerCoords.y - coords.y, playerCoords.z - coords.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function GetNearbyLobbiesAndGames(dartboardId, routingBucket)
    local nearbyLobbies, spectatableGames = {}, {}

    for id, lobby in pairs(Lobbies) do
        if lobby.dartboardId == dartboardId and lobby.routingBucket == routingBucket
            and not lobby.starting and GetKeyCount(lobby.players) < 2 then
            nearbyLobbies[tostring(id)] = { ownerName = lobby.ownerName }
        end
    end

    for uuid, game in pairs(Games) do
        if game.dartboardId == dartboardId and game.routingBucket == routingBucket
            and not game.ending and not game.solo then
            spectatableGames[uuid] = { ownerName = game.ownerName }
        end
    end

    return nearbyLobbies, spectatableGames
end

function IsDartboardInUse(dartboardId, routingBucket)
    dartboardId = tonumber(dartboardId) or dartboardId
    for _, lobby in pairs(Lobbies) do
        if lobby.dartboardId == dartboardId and (routingBucket == nil or lobby.routingBucket == routingBucket) then
            return true
        end
    end
    for _, game in pairs(Games) do
        if game.dartboardId == dartboardId and (routingBucket == nil or game.routingBucket == routingBucket) then
            return true
        end
    end
    return false
end

function BuildPublicPlayers(game)
    local players = {}
    for sid, player in pairs(game.players) do
        players[sid] = player
    end
    return players
end

function EndGame(uuid, winnerSource, forfeited)
    local game = Games[uuid]
    if not game then
        return
    end

    for _, sid in ipairs(game.playerOrder) do
        PlayerGame[sid] = nil
        TriggerClientEvent("prp-dartboard:client:gameFinished", sid, uuid, winnerSource, forfeited)
    end
    for spectatorId in pairs(game.spectators) do
        PlayerSpectating[spectatorId] = nil
        TriggerClientEvent("prp-dartboard:client:stoppedSpectating", spectatorId)
    end

    Games[uuid] = nil
end

local function EndGameByForfeit(uuid, leavingSid, logTitle)
    local game = Games[uuid]
    if not game or game.ending then
        return false
    end

    if game.solo then
        game.ending = true
        for _, sid in ipairs(game.playerOrder) do
            PlayerGame[sid] = nil
            if GetPlayerName(sid) then
                TriggerClientEvent("prp-dartboard:client:gameCancelled", sid)
            end
        end
        for spectatorId in pairs(game.spectators) do
            PlayerSpectating[spectatorId] = nil
            TriggerClientEvent("prp-dartboard:client:stoppedSpectating", spectatorId)
        end
        Games[uuid] = nil
        return true
    end

    local winnerSid
    for _, sid in ipairs(game.playerOrder) do
        if sid ~= leavingSid then
            winnerSid = sid
            break
        end
    end
    if not winnerSid then
        Games[uuid] = nil
        return false
    end

    -- Mark terminal before money/log operations so duplicate disconnect,
    -- unload, abandonment, or client-forfeit events cannot pay the pot twice.
    game.ending = true

    local winnings = game.wager * 2
    if winnings > 0 then
        QueueWinnerSettlement(game, winnerSid, "Dart game winnings")
    end

    local winnerName = GetPlayerName(winnerSid) or "Player"
    local winnerIdentifier = bridge.fw.getIdentifier(winnerSid)
        or game.playerIdentifiers[tostring(winnerSid)]
        or "unknown"
    local logMessage = locale("WON_BY_FORFEIT_LOG", winnerName, winnerIdentifier, winnings)
    print(logMessage)
    SendWebhookLog(logTitle or "Dart Wager Won By Forfeit", logMessage, {
        Wager = game.wager,
        Payout = winnings,
        Game = uuid,
    })

    EndGame(uuid, winnerSid, true)
    return true
end

function AdvanceTurn(game, finishedPlayerSid)
    TriggerClientEvent("prp-dartboard:client:resetState", finishedPlayerSid)

    local nextPlayerSid
    for _, sid in ipairs(game.playerOrder) do
        if sid ~= finishedPlayerSid then
            nextPlayerSid = sid
        end
    end

    if not nextPlayerSid and game.solo then
        nextPlayerSid = finishedPlayerSid
    end

    ResetTurnTracking(game)
    game.turnPlayer = nextPlayerSid
    if nextPlayerSid then
        TriggerClientEvent("prp-dartboard:client:beginThrow", nextPlayerSid)
    end
end

function RecordTurnScore(game, player)
    player.score[#player.score + 1] = player.points
    local publicPlayers = BuildPublicPlayers(game)
    for _, sid in ipairs(game.playerOrder) do
        TriggerClientEvent("prp-dartboard:client:setScores", sid, publicPlayers, player.playerId)
    end
    for spectatorId in pairs(game.spectators) do
        TriggerClientEvent("prp-dartboard:client:setScores", spectatorId, publicPlayers, player.playerId)
    end
end

lib.callback.register("prp-dartboard:server:checkLobbies", function(source, coords)
    coords = NormalizeCoords(coords)
    if not coords then
        return {}, {}
    end

    local dartboard = ResolveStoredDartboard(coords)
    local boardCoords = GetDartboardCoords(dartboard)
    if not dartboard or not boardCoords or GetDistanceToPlayer(source, boardCoords) > ServerConfig.LobbyProximity then
        return {}, {}
    end

    return GetNearbyLobbiesAndGames(dartboard.id, GetPlayerRoutingBucket(source))
end)

-- Boards that are not placed with /placedartboard (e.g. the ones already in the map) are
-- registered in memory the first time somebody creates a lobby at them. They are never
-- saved to the database and never sent to clients to spawn.
local MAX_WORLD_BOARDS = 500
local worldBoardCount = 0

local function RegisterWorldDartboard(source, coords, rotation)
    if Config.AllowAnyDartboard ~= true or not DartboardsLoaded or type(Dartboards) ~= "table" then
        return nil
    end
    if type(rotation) ~= "vector3" and type(rotation) ~= "table" then
        return nil
    end

    local rx, ry, rz = ToFiniteNumber(rotation.x), ToFiniteNumber(rotation.y), ToFiniteNumber(rotation.z)
    if not (rx and ry and rz) then
        return nil
    end
    if GetDistanceToPlayer(source, coords) > (ServerConfig.LobbyProximity or 10.0) then
        return nil
    end
    if worldBoardCount >= MAX_WORLD_BOARDS then
        return nil
    end

    worldBoardCount = worldBoardCount + 1
    local id = ("world:%d"):format(worldBoardCount)
    local board = { id = id, world = true, data = { coords.x, coords.y, coords.z, rx, ry, rz } }
    Dartboards[id] = board
    return board
end

lib.callback.register("prp-dartboard:server:createLobby", function(source, coords, wager, rotation)
    coords = NormalizeCoords(coords)
    if not coords then
        return false, "FAILED_TO_CREATE_LOBBY"
    end

    local dartboard = ResolveStoredDartboard(coords) or RegisterWorldDartboard(source, coords, rotation)
    local boardCoords = GetDartboardCoords(dartboard)
    local boardRotation = GetDartboardRotation(dartboard)
    if not dartboard or not boardCoords or not boardRotation then
        return false, "FAILED_TO_CREATE_LOBBY"
    end
    if PlayerSpectating[source] then
        return false, "PLAYER_ALREADY_SPECTATING"
    end
    if PlayerLobby[source] or PlayerGame[source] then
        return false, "ALREADY_ACTIVE_LOBBY"
    end
    if GetDistanceToPlayer(source, boardCoords) > ServerConfig.LobbyProximity then
        return false, "TOO_FAR_FROM_BOARD"
    end
    local routingBucket = GetPlayerRoutingBucket(source)
    if IsDartboardInUse(dartboard.id, routingBucket) then
        return false, "FAILED_TO_CREATE_LOBBY"
    end

    wager = ToFiniteNumber(wager)
    local minimumWager = tonumber(Wagers.Minimum) or 0
    local maximumWager = tonumber(Wagers.Maximum) or minimumWager
    if not wager or wager % 1 ~= 0 or wager % 2 ~= 0 or wager < minimumWager or wager > maximumWager then
        return false, "FAILED_TO_CREATE_LOBBY"
    end

    local ownerName = GetPlayerName(source)
    if not ownerName then
        return false, "FAILED_TO_CREATE_LOBBY"
    end

    local lobbyId = nextLobbyId
    nextLobbyId = nextLobbyId + 1

    local lobby = {
        id = lobbyId,
        owner = source,
        ownerName = ownerName,
        wager = wager,
        dartboardId = dartboard.id,
        dartboardCoords = boardCoords,
        dartboardRotation = boardRotation,
        routingBucket = routingBucket,
        soloAllowed = Config.DevelopmentSoloMode == true,
        players = {
            [tostring(source)] = { playerId = source, playerName = ownerName },
        },
    }
    Lobbies[lobbyId] = lobby
    PlayerLobby[source] = lobbyId

    return lobby
end)

lib.callback.register("prp-dartboard:server:requestJoinLobby", function(source, lobbyId)
    lobbyId = NormalizeLobbyId(lobbyId)
    local lobby = Lobbies[lobbyId]
    if not lobby then
        return false, "LOBBY_DOESNT_EXIST"
    end
    if lobby.starting or lobby.pendingJoin then
        return false, "JOIN_REQUEST_DENIED"
    end
    if PlayerSpectating[source] then
        return false, "PLAYER_ALREADY_SPECTATING"
    end
    if PlayerLobby[source] or PlayerGame[source] then
        return false, "ALREADY_ACTIVE_LOBBY"
    end
    if GetKeyCount(lobby.players) > 1 then
        return false, "JOIN_REQUEST_DENIED"
    end
    if GetPlayerRoutingBucket(source) ~= lobby.routingBucket then
        return false, "JOIN_REQUEST_DENIED"
    end
    if GetDistanceToPlayer(source, lobby.dartboardCoords) > ServerConfig.LobbyProximity then
        return false, "TOO_FAR_FROM_BOARD"
    end

    local requesterName = GetPlayerName(source)
    if not requesterName then
        return false, "JOIN_REQUEST_DENIED"
    end

    lobby.pendingJoin = source

    local requestId = nextJoinRequestId
    nextJoinRequestId = nextJoinRequestId + 1
    if nextJoinRequestId > 2147483647 then
        nextJoinRequestId = 1
    end

    local requestToken = ("%s:%s:%s:%s"):format(
        lobbyId,
        requestId,
        GetGameTimer(),
        math.random(100000, 999999)
    )
    local pendingRequest = {
        owner = lobby.owner,
        requester = source,
        lobbyId = lobbyId,
        response = nil,
    }
    PendingJoinRequests[requestToken] = pendingRequest

    TriggerClientEvent(
        "prp-dartboard:client:joinRequest",
        lobby.owner,
        requestToken,
        { playerId = source, playerName = requesterName },
        math.max(1000, tonumber(ServerConfig.JoinRequestTimeoutMs) or 7000)
    )

    local requestExpiresAt = GetGameTimer() + (ServerConfig.JoinRequestTimeoutMs or 7000)
    while pendingRequest.response == nil and GetGameTimer() < requestExpiresAt do
        Wait(50)
    end

    PendingJoinRequests[requestToken] = nil
    local accepted = pendingRequest.response == true

    if Lobbies[lobbyId] == lobby and lobby.pendingJoin == source then
        lobby.pendingJoin = nil
    end
    if not accepted then
        return false, "JOIN_REQUEST_DENIED"
    end

    -- Revalidate everything after the owner dialog yields. The lobby may have
    -- been closed, started, moved to another state, or the requester may have
    -- joined another activity while the prompt was open.
    if Lobbies[lobbyId] ~= lobby or lobby.starting
        or PlayerLobby[source] or PlayerGame[source] or PlayerSpectating[source]
        or GetKeyCount(lobby.players) > 1
        or not GetPlayerName(lobby.owner)
        or not GetPlayerName(source)
        or GetPlayerRoutingBucket(source) ~= lobby.routingBucket
        or GetPlayerRoutingBucket(lobby.owner) ~= lobby.routingBucket
        or GetDistanceToPlayer(source, lobby.dartboardCoords) > ServerConfig.LobbyProximity
        or GetDistanceToPlayer(lobby.owner, lobby.dartboardCoords) > ServerConfig.LobbyProximity then
        return false, "JOIN_REQUEST_DENIED"
    end

    lobby.players[tostring(source)] = { playerId = source, playerName = GetPlayerName(source) }
    PlayerLobby[source] = lobbyId

    TriggerClientEvent("prp-dartboard:client:lobbyJoined", source, lobby)
    TriggerClientEvent("prp-dartboard:client:lobbyUpdate", lobby.owner, lobby.players, true)

    return true
end)

RegisterNetEvent("prp-dartboard:server:joinRequestResponse", function(requestToken, accepted)
    local src = source
    if type(requestToken) ~= "string" or #requestToken > 128 or type(accepted) ~= "boolean" then
        return
    end

    local pendingRequest = PendingJoinRequests[requestToken]
    if not pendingRequest or pendingRequest.owner ~= src or pendingRequest.response ~= nil then
        return
    end

    local lobby = Lobbies[pendingRequest.lobbyId]
    if not lobby or lobby.owner ~= src or lobby.pendingJoin ~= pendingRequest.requester then
        pendingRequest.response = false
        return
    end

    pendingRequest.response = accepted
end)

lib.callback.register("prp-dartboard:server:closeLobby", function(source, lobbyId)
    lobbyId = NormalizeLobbyId(lobbyId)
    local lobby = Lobbies[lobbyId]
    if not lobby then
        return false, "LOBBY_DOESNT_EXIST"
    end
    if lobby.owner ~= source then
        return false, "NOT_LOBBY_OWNER"
    end
    if lobby.starting then
        return false, "FAILED_TO_CLOSE_LOBBY"
    end

    for _, player in pairs(lobby.players) do
        PlayerLobby[player.playerId] = nil
        if player.playerId ~= source then
            TriggerClientEvent("prp-dartboard:client:lobbyClosed", player.playerId)
        end
    end
    Lobbies[lobbyId] = nil

    return true
end)

lib.callback.register("prp-dartboard:server:leaveLobby", function(source, lobbyId)
    lobbyId = NormalizeLobbyId(lobbyId)
    local lobby = Lobbies[lobbyId]
    if not lobby or not lobby.players[tostring(source)] then
        return false, "LOBBY_DOESNT_EXIST"
    end
    if lobby.starting then
        return false, "FAILED_TO_LEAVE_LOBBY"
    end
    if lobby.owner == source then
        return false, "FAILED_TO_LEAVE_LOBBY"
    end

    lobby.players[tostring(source)] = nil
    PlayerLobby[source] = nil

    TriggerClientEvent("prp-dartboard:client:lobbyUpdate", lobby.owner, lobby.players, false)
    return true
end)

lib.callback.register("prp-dartboard:server:kickPlayer", function(source)
    local lobbyId = PlayerLobby[source]
    local lobby = lobbyId and Lobbies[lobbyId]
    if not lobby then
        return false, "LOBBY_DOESNT_EXIST"
    end
    if lobby.owner ~= source then
        return false, "NOT_LOBBY_OWNER"
    end
    if lobby.starting then
        return false, "FAILED_TO_KICK_PLAYER"
    end

    for sid, player in pairs(lobby.players) do
        if player.playerId ~= source then
            lobby.players[sid] = nil
            PlayerLobby[player.playerId] = nil
            TriggerClientEvent("prp-dartboard:client:lobbyUpdate", player.playerId, nil, false)
        end
    end

    TriggerClientEvent("prp-dartboard:client:lobbyUpdate", lobby.owner, lobby.players, false)
    return true
end)

lib.callback.register("prp-dartboard:server:attemptStartGame", function(source)
    local lobbyId = PlayerLobby[source]
    local lobby = lobbyId and Lobbies[lobbyId]
    if not lobby then
        return false, "LOBBY_DOESNT_EXIST"
    end
    if lobby.owner ~= source then
        return false, "NOT_LOBBY_OWNER"
    end
    if lobby.starting then
        return false, "FAILED_TO_START_GAME"
    end
    local playerCount = GetKeyCount(lobby.players)
    local soloGame = playerCount == 1 and Config.DevelopmentSoloMode == true
    if playerCount ~= 2 and not soloGame then
        return false, "NO_OPPONENT"
    end
    if soloGame and (tonumber(lobby.wager) or 0) > 0 then
        return false, "SOLO_WAGER_NOT_ALLOWED"
    end

    -- Lock before bridge money operations/yields so a second start request,
    -- kick, close, or join cannot race the same lobby into a second game.
    lobby.starting = true
    local function FailStart(errorKey)
        if Lobbies[lobbyId] == lobby then
            lobby.starting = nil
        end
        return false, errorKey
    end

    local storedBoard = Dartboards and Dartboards[lobby.dartboardId]
    if not storedBoard or storedBoard.removing then
        return FailStart("FAILED_TO_START_GAME")
    end

    local boardCoords = GetDartboardCoords(storedBoard)
    local boardRotation = GetDartboardRotation(storedBoard)
    if not boardCoords or not boardRotation then
        return FailStart("FAILED_TO_START_GAME")
    end
    lobby.dartboardCoords = boardCoords
    lobby.dartboardRotation = boardRotation

    local playerOrder = { lobby.owner }
    if not soloGame then
        local opponentSid
        for _, player in pairs(lobby.players) do
            if player.playerId ~= lobby.owner then
                opponentSid = player.playerId
                break
            end
        end
        if not opponentSid then
            return FailStart("NO_OPPONENT")
        end
        playerOrder[#playerOrder + 1] = opponentSid
    end

    for _, sid in ipairs(playerOrder) do
        if not GetPlayerName(sid) or PlayerLobby[sid] ~= lobbyId
            or GetPlayerRoutingBucket(sid) ~= lobby.routingBucket
            or GetDistanceToPlayer(sid, boardCoords) > ServerConfig.LobbyProximity then
            return FailStart("SOMEONE_TOO_FAR_FROM_BOARD")
        end
    end

    local playerIdentifiers = {}
    for _, sid in ipairs(playerOrder) do
        local identifier = bridge.fw.getIdentifier(sid)
        if not identifier then
            return FailStart("FAILED_TO_START_GAME")
        end
        playerIdentifiers[tostring(sid)] = tostring(identifier)
    end

    local uuid = GenerateGameUuid()
    local moneyType = tostring(ServerConfig.WagerMoneyType or "cash")

    local function RefundChargedPlayers(charged)
        for _, refundSid in ipairs(charged) do
            PayPlayerOrQueue(
                refundSid,
                playerIdentifiers[tostring(refundSid)],
                lobby.wager,
                "Dart wager refund",
                moneyType
            )
            if GetPlayerName(refundSid) then
                bridge.fw.notify(refundSid, "success", locale("BANK_DESCRIPTION", lobby.wager), locale("BANK_TITLE"))
            end
        end
    end

    local charged = {}
    if lobby.wager > 0 then
        for _, sid in ipairs(playerOrder) do
            local expectedIdentifier = playerIdentifiers[tostring(sid)]
            if not HasMatchingIdentifier(sid, expectedIdentifier) then
                return FailStart("FAILED_TO_START_GAME")
            end
            local balance = tonumber(bridge.fw.getMoney(sid, moneyType)) or 0
            if balance < lobby.wager then
                return FailStart("CANNOT_AFFORD")
            end
        end

        for _, sid in ipairs(playerOrder) do
            local expectedIdentifier = playerIdentifiers[tostring(sid)]
            if not HasMatchingIdentifier(sid, expectedIdentifier)
                or not bridge.fw.removeMoney(sid, moneyType, lobby.wager, "Dart wager") then
                RefundChargedPlayers(charged)
                return FailStart("CANNOT_AFFORD")
            end
            charged[#charged + 1] = sid
        end

        -- Bridge/framework calls can yield or race character unloads. Recheck
        -- the locked lobby and player state before committing the charged pot.
        if Lobbies[lobbyId] ~= lobby or not lobby.starting or GetKeyCount(lobby.players) ~= playerCount then
            RefundChargedPlayers(charged)
            return false, "FAILED_TO_START_GAME"
        end
        for _, sid in ipairs(playerOrder) do
            if not GetPlayerName(sid) or PlayerLobby[sid] ~= lobbyId
                or PlayerGame[sid] or PlayerSpectating[sid]
                or GetPlayerRoutingBucket(sid) ~= lobby.routingBucket
                or GetDistanceToPlayer(sid, boardCoords) > ServerConfig.LobbyProximity then
                RefundChargedPlayers(charged)
                return FailStart("SOMEONE_TOO_FAR_FROM_BOARD")
            end
        end
        local currentBoard = Dartboards and Dartboards[lobby.dartboardId]
        if currentBoard ~= storedBoard or storedBoard.removing then
            RefundChargedPlayers(charged)
            return FailStart("FAILED_TO_START_GAME")
        end

        -- From this point the deducted pot has a durable owner. If FXServer is
        -- killed before normal payout/refund code runs, startup recovery can
        -- convert this escrow row back into character-bound payouts.
        if not PersistActiveWager(uuid, lobby, playerOrder, playerIdentifiers, moneyType) then
            RefundChargedPlayers(charged)
            return FailStart("FAILED_TO_START_GAME")
        end
    end

    -- Zero-wager starts do not enter the bridge money branch above, so they
    -- need the same final state validation before the lobby is committed.
    -- Wagered starts have already passed this validation before their escrow
    -- row is created; do not perform a post-escrow rollback here.
    if lobby.wager <= 0 then
        if Lobbies[lobbyId] ~= lobby or not lobby.starting or GetKeyCount(lobby.players) ~= playerCount then
            return FailStart("FAILED_TO_START_GAME")
        end
        for _, sid in ipairs(playerOrder) do
            if not GetPlayerName(sid) or PlayerLobby[sid] ~= lobbyId
                or PlayerGame[sid] or PlayerSpectating[sid]
                or GetPlayerRoutingBucket(sid) ~= lobby.routingBucket
                or GetDistanceToPlayer(sid, boardCoords) > ServerConfig.LobbyProximity then
                return FailStart("SOMEONE_TOO_FAR_FROM_BOARD")
            end
        end
        local finalBoard = Dartboards and Dartboards[lobby.dartboardId]
        if finalBoard ~= storedBoard or storedBoard.removing then
            return FailStart("FAILED_TO_START_GAME")
        end
    end

    local startingScore = tonumber(Config.StartingScore) or 301
    startingScore = math.floor(startingScore)
    if startingScore < 2 or startingScore > 10000 then
        startingScore = 301
    end

    local startingTurnPlayer = playerOrder[math.random(1, #playerOrder)]
    local playerTwo = playerOrder[2]

    local players = {}
    for _, sid in ipairs(playerOrder) do
        players[tostring(sid)] = {
            playerId = sid,
            name = GetPlayerName(sid) or "Player",
            points = startingScore,
            score = {},
        }
    end

    local game = {
        uuid = uuid,
        dartboardId = lobby.dartboardId,
        dartboardCoords = boardCoords,
        dartboardRotation = boardRotation,
        wager = lobby.wager,
        moneyType = moneyType,
        ownerName = lobby.ownerName,
        players = players,
        playerOrder = playerOrder,
        playerIdentifiers = playerIdentifiers,
        turnPlayer = startingTurnPlayer,
        startingScore = startingScore,
        spectators = {},
        turnDarts = {},
        turnTotal = 0,
        lastDartDouble = false,
        awaySince = {},
        routingBucket = lobby.routingBucket,
        solo = soloGame,
    }

    -- Commit server state before notifying clients. From this point the board
    -- is occupied by Games rather than Lobbies and no second start can win.
    Lobbies[lobbyId] = nil
    Games[uuid] = game
    for _, sid in ipairs(playerOrder) do
        PlayerLobby[sid] = nil
        PlayerGame[sid] = uuid
    end

    for _, sid in ipairs(playerOrder) do
        TriggerClientEvent(
            "prp-dartboard:client:gameStarted",
            sid,
            uuid,
            players,
            startingTurnPlayer,
            playerTwo,
            boardCoords,
            soloGame
        )
    end

    return true
end)

lib.callback.register("prp-dartboard:server:turnFinished", function(source)
    local uuid = PlayerGame[source]
    local game = uuid and Games[uuid]
    if not game or game.ending then
        return false, "GAME_DOESNT_EXIST"
    end
    if game.turnPlayer ~= source then
        return false, "GAME_DOESNT_EXIST"
    end

    local player = game.players[tostring(source)]
    local dartCount = #(game.turnDarts or {})
    local turnTotal = game.turnTotal or 0
    if dartCount < 1 or dartCount > 3 then
        return false, "FAILED_TO_UPDATE_SCORE"
    end

    local remaining = player.points - turnTotal
    local terminalThrow = remaining <= 1
    if not terminalThrow and dartCount < 3 then
        -- A normal turn only finishes after all three darts. Early finishes are
        -- only valid for a win/bust/one-remaining condition.
        return false, "FAILED_TO_UPDATE_SCORE"
    end

    if remaining == 0 and game.lastDartDouble then
        game.ending = true
        player.points = 0
        RecordTurnScore(game, player)

        local winnings = game.wager * 2
        if winnings > 0 then
            QueueWinnerSettlement(game, source, "Dart game winnings")
        end
        local winnerName = GetPlayerName(source) or "Player"
        local winnerIdentifier = bridge.fw.getIdentifier(source)
            or game.playerIdentifiers[tostring(source)]
            or "unknown"
        local logMessage = locale("WON_LOG", winnerName, winnerIdentifier, winnings)
        print(logMessage)
        SendWebhookLog("Dart Wager Won", logMessage, {
            Wager = game.wager,
            Payout = winnings,
            Game = uuid,
        })

        EndGame(uuid, source, false)
        return true
    end

    if remaining > 1 then
        player.points = remaining
    end
    -- Bust / one remaining / no-double-out: points stay unchanged.

    RecordTurnScore(game, player)
    AdvanceTurn(game, source)

    return true
end)

lib.callback.register("prp-dartboard:server:syncDart", function(source, dart)
    local uuid = PlayerGame[source]
    local game = uuid and Games[uuid]
    if not game or game.ending then
        return false, "GAME_DOESNT_EXIST"
    end
    if game.turnPlayer ~= source then
        return false, "GAME_DOESNT_EXIST"
    end
    if GetPlayerRoutingBucket(source) ~= game.routingBucket then
        return false, "TOO_FAR_FROM_BOARD"
    end
    if GetDistanceToPlayer(source, game.dartboardCoords) > ServerConfig.LobbyProximity then
        return false, "TOO_FAR_FROM_BOARD"
    end
    if type(dart) ~= "table" then
        return false, "FAILED_TO_UPDATE_SCORE"
    end

    local coords = NormalizeCoords(dart.entityCoords)
    local rotation = dart.entityRotation
    local rotX = rotation and ToFiniteNumber(rotation[1]) or nil
    local rotY = rotation and ToFiniteNumber(rotation[2]) or nil
    local rotZ = rotation and ToFiniteNumber(rotation[3]) or nil
    local dartId = ToFiniteNumber(dart.id)
    local maxRotationMagnitude = ServerConfig.DartRotationMagnitudeLimit or 3600.0
    local rotationIsReasonable = rotX and rotY and rotZ
        and math.abs(rotX) <= maxRotationMagnitude
        and math.abs(rotY) <= maxRotationMagnitude
        and math.abs(rotZ) <= maxRotationMagnitude

    local expectedId = #(game.turnDarts or {}) + 1
    if not coords or not rotationIsReasonable or not dartId or dartId % 1 ~= 0
        or dartId ~= expectedId or dartId > 3 then
        return false, "FAILED_TO_UPDATE_SCORE"
    end

    local boardDistance = DistanceBetween(coords, game.dartboardCoords)
    if boardDistance > (ServerConfig.DartMissSyncMaxDistance or 15.0) then
        return false, "FAILED_TO_UPDATE_SCORE"
    end

    -- The client still chooses the world-space landing coordinate (FiveM's
    -- physical throw/raycast is client-authored), but points and double-state
    -- are never accepted from the client. Classify near-board landings from
    -- the exact stored board transform; bounded remote misses are worth zero.
    local points, isDouble = 0, false
    if boardDistance <= (ServerConfig.DartSyncMaxDistance or 1.0) then
        points, isDouble = CalculateAuthoritativeDartScore(game, coords)
    end

    local syncedDart = {
        id = dartId,
        entityCoords = coords,
        entityRotation = { rotX, rotY, rotZ },
        points = points,
        isDouble = isDouble,
    }

    game.turnDarts[expectedId] = syncedDart
    game.turnTotal = (game.turnTotal or 0) + points
    game.lastDartDouble = isDouble

    for _, sid in ipairs(game.playerOrder) do
        if sid ~= source then
            TriggerClientEvent("prp-dartboard:client:syncDart", sid, syncedDart)
        end
    end
    for spectatorId in pairs(game.spectators) do
        TriggerClientEvent("prp-dartboard:client:syncDart", spectatorId, syncedDart)
    end

    return true, syncedDart
end)

RegisterNetEvent("prp-dartboard:server:playerLeftGame", function()
    local src = source
    local uuid = PlayerGame[src]
    if uuid then
        EndGameByForfeit(uuid, src, "Dart Wager Won By Forfeit")
    end
end)

lib.callback.register("prp-dartboard:server:spectateGame", function(source, gameUuid)
    local game = Games[gameUuid]
    if not game or game.ending or game.solo then
        return false, "GAME_DOESNT_EXIST"
    end
    if PlayerLobby[source] then
        return false, "ALREADY_ACTIVE_LOBBY"
    end
    if PlayerGame[source] then
        return false, "PLAYER_ALREADY_IN_GAME"
    end
    if PlayerSpectating[source] then
        return false, "PLAYER_ALREADY_SPECTATING"
    end
    if GetPlayerRoutingBucket(source) ~= game.routingBucket then
        return false, "TOO_FAR_FROM_BOARD"
    end
    if GetDistanceToPlayer(source, game.dartboardCoords) > ServerConfig.LobbyProximity then
        return false, "TOO_FAR_FROM_BOARD"
    end

    game.spectators[source] = true
    PlayerSpectating[source] = gameUuid

    TriggerClientEvent("prp-dartboard:client:startedSpectating", source, {
        uuid = game.uuid,
        dartboardPos = game.dartboardCoords,
        players = BuildPublicPlayers(game),
        gameOwner = game.playerOrder[1],
        gameOwnerName = game.ownerName,
        opponentId = game.playerOrder[2],
        startingScore = game.startingScore,
        currentDarts = game.turnDarts,
    })

    return true
end)

lib.callback.register("prp-dartboard:server:stopSpectating", function(source, gameUuid)
    local currentGameUuid = PlayerSpectating[source]
    if not currentGameUuid then
        return false, "PLAYER_NOT_SPECTATING"
    end
    if gameUuid and gameUuid ~= currentGameUuid then
        return false, "PLAYER_NOT_SPECTATING"
    end

    local game = Games[currentGameUuid]
    if game then
        game.spectators[source] = nil
    end
    PlayerSpectating[source] = nil

    TriggerClientEvent("prp-dartboard:client:stoppedSpectating", source)

    return true
end)

local function HandlePlayerDeparture(src)
    for _, pendingRequest in pairs(PendingJoinRequests) do
        if pendingRequest.owner == src or pendingRequest.requester == src then
            pendingRequest.response = false
        end
    end

    local lobbyId = PlayerLobby[src]
    if lobbyId and Lobbies[lobbyId] then
        local lobby = Lobbies[lobbyId]
        if lobby.owner == src then
            for _, player in pairs(lobby.players) do
                PlayerLobby[player.playerId] = nil
                TriggerClientEvent("prp-dartboard:client:lobbyClosed", player.playerId)
            end
            Lobbies[lobbyId] = nil
        else
            lobby.players[tostring(src)] = nil
            PlayerLobby[src] = nil
            TriggerClientEvent("prp-dartboard:client:lobbyClosed", src)
            if GetPlayerName(lobby.owner) then
                TriggerClientEvent("prp-dartboard:client:lobbyUpdate", lobby.owner, lobby.players, false)
            end
        end
    end

    local uuid = PlayerGame[src]
    if uuid then
        EndGameByForfeit(uuid, src, "Dart Wager Won By Disconnect")
    end
    PlayerGame[src] = nil

    if PlayerSpectating[src] then
        local specGame = Games[PlayerSpectating[src]]
        if specGame then
            specGame.spectators[src] = nil
        end
        PlayerSpectating[src] = nil
        TriggerClientEvent("prp-dartboard:client:stoppedSpectating", src)
    end
end

-- Distance/abandonment is authoritative on the server. The client no longer
-- has a separate hardcoded timer that can drift from these tunables.
CreateThread(function()
    while true do
        Wait(ServerConfig.GameAbandonCheckIntervalMs or 1000)

        local now = GetGameTimer()
        local timeoutMs = math.max(1, tonumber(ServerConfig.GameAbandonSeconds) or 15) * 1000
        local maxDistance = math.max(1.0, tonumber(ServerConfig.GameAbandonDistance) or 12.5)
        local forfeits = {}

        for uuid, game in pairs(Games) do
            if not game.ending then
                game.awaySince = game.awaySince or {}
                for _, sid in ipairs(game.playerOrder) do
                    if GetPlayerRoutingBucket(sid) ~= game.routingBucket
                        or GetDistanceToPlayer(sid, game.dartboardCoords) > maxDistance then
                        game.awaySince[sid] = game.awaySince[sid] or now
                        if now - game.awaySince[sid] >= timeoutMs then
                            forfeits[#forfeits + 1] = { uuid = uuid, sid = sid }
                            break
                        end
                    else
                        game.awaySince[sid] = nil
                    end
                end
            end
        end

        for _, forfeiture in ipairs(forfeits) do
            EndGameByForfeit(forfeiture.uuid, forfeiture.sid, "Dart Wager Won By Abandonment")
        end
    end
end)

CreateThread(function()
    while true do
        Wait(math.max(5000, tonumber(ServerConfig.PayoutPersistenceRetryMs) or 30000))
        if next(PendingPayouts) ~= nil and DartboardsLoaded then
            local ok, err = pcall(FlushMemoryPayoutsToDatabase)
            if not ok then
                Trace("Failed to persist memory fallback payouts", err)
            end
        end
    end
end)

AddEventHandler("playerDropped", function()
    HandlePlayerDeparture(source)
end)

-- Character unloads can happen without the network source disconnecting
-- (for example, character switching). bridge/server.lua emits this lifecycle
-- event, so clear lobby/game/spectator state there as well.
AddEventHandler("prp-dartboard:server:playerUnload", function(src)
    src = tonumber(src) or source
    if not src or src == 0 then
        return
    end
    HandlePlayerDeparture(src)
end)

ProcessPendingPayouts = function(src)
    src = tonumber(src)
    if not src or src == 0 or not GetPlayerName(src) then
        return
    end

    local identifier = bridge.fw.getIdentifier(src)
    if not identifier then
        return
    end
    identifier = tostring(identifier)

    -- Serialize persistence + delivery for this character. Without the shared
    -- lock, a memory fallback can be copied into SQL while another coroutine
    -- totals both copies and credits the character twice.
    if PayoutProcessing[identifier] then
        return
    end
    PayoutProcessing[identifier] = "delivery"

    local ok, err = pcall(function()
        PersistMemoryPayoutsForIdentifier(identifier)
        if not HasMatchingIdentifier(src, identifier) then
            return
        end

        local rows = MySQL.query.await([[
            SELECT id, amount, money_type, reason
            FROM prp_dartboard_payouts
            WHERE identifier = ? AND status = 'pending'
            ORDER BY id
        ]], { identifier }) or {}

        for _, row in ipairs(rows) do
            if not HasMatchingIdentifier(src, identifier) then
                return
            end

            local amount = tonumber(row.amount) or 0
            local moneyType = tostring(row.money_type or "")
            if amount > 0 and moneyType ~= "" then
                local token = ("%s:%s:%s:%s"):format(
                    identifier,
                    tostring(row.id),
                    GetGameTimer(),
                    math.random(100000, 999999)
                )
                local claimed = MySQL.update.await([[
                    UPDATE prp_dartboard_payouts
                    SET status = 'processing', delivery_token = ?, processing_at = CURRENT_TIMESTAMP
                    WHERE id = ? AND identifier = ? AND status = 'pending'
                ]], { token, row.id, identifier })

                if tonumber(claimed) and tonumber(claimed) >= 1 then
                    if not HasMatchingIdentifier(src, identifier) then
                        MySQL.update.await([[
                            UPDATE prp_dartboard_payouts
                            SET status = 'pending', delivery_token = NULL, processing_at = NULL
                            WHERE id = ? AND delivery_token = ? AND status = 'processing'
                        ]], { row.id, token })
                        return
                    end

                    local moneyCallOk, added = pcall(
                        bridge.fw.addMoney,
                        src,
                        moneyType,
                        amount,
                        row.reason or "Deferred dart game payout"
                    )

                    if moneyCallOk and added then
                        local deletedOk, deleted = pcall(
                            MySQL.update.await,
                            [[DELETE FROM prp_dartboard_payouts
                              WHERE id = ? AND delivery_token = ? AND status = 'processing']],
                            { row.id, token }
                        )
                        if not deletedOk or not tonumber(deleted) or tonumber(deleted) < 1 then
                            -- Money was already reported as credited. Never reset
                            -- this row to pending automatically or a DB outage can
                            -- turn into a duplicate payout on the next login.
                            print(("[%s] WARNING: payout %s was credited to %s but could not be cleared; "
                                .. "it remains status=processing for manual review"):format(
                                GetCurrentResourceName(), tostring(row.id), identifier))
                        else
                            Trace("Applied deferred dart game payout", identifier, moneyType, amount, row.id)
                        end
                    elseif moneyCallOk then
                        local resetOk, resetResult = pcall(
                            MySQL.update.await,
                            [[UPDATE prp_dartboard_payouts
                              SET status = 'pending', delivery_token = NULL, processing_at = NULL
                              WHERE id = ? AND delivery_token = ? AND status = 'processing']],
                            { row.id, token }
                        )
                        if not resetOk then
                            print(("[%s] Failed to reset undelivered dart payout %s: %s"):format(
                                GetCurrentResourceName(), tostring(row.id), tostring(resetResult)))
                        end
                    else
                        -- An exception from the framework money call has an
                        -- ambiguous outcome; leave the row claimed instead of
                        -- risking an automatic duplicate credit.
                        print(("[%s] WARNING: payout %s money call errored for %s; "
                            .. "status=processing retained for manual review: %s"):format(
                            GetCurrentResourceName(), tostring(row.id), identifier, tostring(added)))
                    end
                end
            end
        end
    end)

    PayoutProcessing[identifier] = nil
    if not ok then
        print(("[%s] Failed to process deferred dart payout for %s: %s"):format(
            GetCurrentResourceName(), identifier, tostring(err)))
    end
end

local function ReportAmbiguousPayouts()
    local ok, rows = pcall(MySQL.query.await, [[
        SELECT id, identifier, amount, money_type, processing_at
        FROM prp_dartboard_payouts
        WHERE status = 'processing'
        ORDER BY id
    ]], {})
    if not ok then
        return
    end

    for _, row in ipairs(rows or {}) do
        print(("[%s] WARNING: payout %s for %s (%s %s) is status=processing from an interrupted/ambiguous delivery. "
            .. "It is intentionally not auto-retried to prevent duplicate money."):format(
            GetCurrentResourceName(), tostring(row.id), tostring(row.identifier),
            tostring(row.amount), tostring(row.money_type)))
    end
end


AddEventHandler("prp-dartboard:server:playerLoad", function(src)
    src = tonumber(src) or source
    if src and src ~= 0 then
        ProcessPendingPayouts(src)
    end
end)

local function RetryDeliveredPayoutCleanup()
    local ids = {}
    for payoutId in pairs(PayoutCleanupPending) do
        ids[#ids + 1] = payoutId
    end
    if #ids == 0 then
        return
    end

    local placeholders = {}
    for i = 1, #ids do
        placeholders[i] = "?"
    end
    local ok, affectedOrErr = pcall(
        MySQL.update.await,
        ("DELETE FROM prp_dartboard_payouts WHERE id IN (%s)"):format(table.concat(placeholders, ",")),
        ids
    )
    if not ok then
        Trace("Failed retrying delivered payout cleanup", affectedOrErr)
        return
    end

    -- Rows may already have been removed by an earlier cleanup attempt. A
    -- successful DELETE query is enough to release all local suppression ids.
    for _, payoutId in ipairs(ids) do
        PayoutCleanupPending[payoutId] = nil
    end
end

-- A transient database/framework failure during the one-shot playerLoad hook
-- should not strand an owed payout until the next character login or resource
-- restart. Retry delivery for currently loaded players at a conservative rate.
CreateThread(function()
    while true do
        Wait(math.max(5000, tonumber(ServerConfig.PayoutDeliveryRetryMs) or 60000))
        if DartboardsLoaded then
            RetryDeliveredPayoutCleanup()
            for _, playerId in ipairs(GetPlayers()) do
                ProcessPendingPayouts(playerId)
            end
        end
    end
end)

-- A dartboard resource restart can happen while characters are already loaded,
-- so playerLoad will not fire again. Retry persisted payouts for online players
-- once this resource's database initialization has completed.
AddEventHandler("onResourceStart", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    CreateThread(function()
        local expiresAt = GetGameTimer() + 10000
        while not DartboardsLoaded and GetGameTimer() < expiresAt do
            Wait(100)
        end
        for _, playerId in ipairs(GetPlayers()) do
            ProcessPendingPayouts(playerId)
        end
    end)
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    -- Best effort for manual restarts: return active wagers while the bridge
    -- and framework are still available. Failed/offline credits are backed by
    -- prp_dartboard_payouts instead of existing only in process memory.
    for _, game in pairs(Games) do
        if not game.ending then
            for _, sid in ipairs(game.playerOrder) do
                PayPlayerOrQueue(
                    sid,
                    game.playerIdentifiers and game.playerIdentifiers[tostring(sid)],
                    game.wager,
                    "Dart resource stop refund"
                )
            end
        end
    end
end)
