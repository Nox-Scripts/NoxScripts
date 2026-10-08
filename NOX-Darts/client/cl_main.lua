local resourceName = GetCurrentResourceName()
local _sessionSeed = "4f6f7e5e1f41bffc63c207d578fcf43c"

Dartboards = {}

-- === Dart state, dartboard prop / DUI texture setup =======================

local dartState = {
    trianglePoints = {
        [0] = 20, [1] = 1, [2] = 18, [3] = 4, [4] = 13, [5] = 6, [6] = 10, [7] = 15,
        [8] = 2, [9] = 17, [10] = 3, [11] = 19, [12] = 7, [13] = 16, [14] = 8, [15] = 11,
        [16] = 14, [17] = 9, [18] = 12, [19] = 5, [20] = 20,
    },
    previousDarts = {},
    activeDartProp = nil,
    animState = nil,
}

local dartboardBlackboardModel = "prop_blackboard_01"
local dartboardTxdName = "prp_dartboard_txd"
local dartboardTxnName = "prp_dartboard_txn"
local dartboardDuiUrl = ("nui://%s/dui/index.html"):format(resourceName)

local duiReady = true
local duiTexture = nil
local duiObject = nil

-- Cross-cutting session state, referenced from functions and net events
-- throughout this file.
local currentGame = nil
local currentGameUuid = nil
local isMyTurn = false
local turnGeneration = 0
local isAdmin = false
local spawnedDartboardEntities = {}
local BOARD_INTERACTION_TOLERANCE = 2.0
local DART_MISS_VISUAL_MAX_DISTANCE = 10.0

local function IsManagedDartboardEntity(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return false
    end
    if spawnedDartboardEntities[entity] == true then
        return true
    end
    -- Any dartboard cabinet of the supported model (e.g. the ones already in the map).
    return Config.AllowAnyDartboard == true
        and (GetEntityModel(entity) & 0xFFFFFFFF) == (Config.DartboardModel & 0xFFFFFFFF)
end

local function IsOriginalDartboard(entity, originCoords)
    return IsManagedDartboardEntity(entity)
        and originCoords
        and #(GetEntityCoords(entity) - originCoords) <= BOARD_INTERACTION_TOLERANCE
end

RegisterNUICallback(("%s:duiLoaded"):format(resourceName), function(data, cb)
    Trace(("%s:duiLoaded"):format(resourceName))
    duiReady = true
    cb({})
end)

function LoadModel(model)
    local startTime = GetGameTimer()
    RequestModel(model)
    while not HasModelLoaded(model) do
        if GetGameTimer() - startTime >= 5000 then
            return false
        end
        Wait(0)
    end
    return true
end

function DestroyDartboardDui()
    if duiObject then
        DestroyDui(duiObject)
    end
    RemoveReplaceTexture(Config.DartboardModelName, dartboardBlackboardModel)
    duiTexture = nil
    duiObject = nil
end

function EnsureDartboardDui()
    if not duiReady then
        return false, "DUI_NOT_READY"
    end

    if duiTexture then
        DestroyDartboardDui()
        Wait(50)
    end

    if not LoadModel(Config.DartboardModel) then
        return false, "DARTBOARD_MODEL_FAILED_TO_LOAD"
    end

    duiObject = CreateDui(dartboardDuiUrl, 256, 512)
    local duiTimeout = GetGameTimer() + 5000
    while not IsDuiAvailable(duiObject) do
        if GetGameTimer() >= duiTimeout then
            DestroyDartboardDui()
            return false, "DUI_NOT_READY"
        end
        Wait(100)
    end
    Wait(300)

    local runtimeTxd = CreateRuntimeTxd(dartboardTxdName)
    duiTexture = GetDuiHandle(duiObject)
    CreateRuntimeTextureFromDuiHandle(runtimeTxd, dartboardTxnName, duiTexture)
    AddReplaceTexture(Config.DartboardModelName, dartboardBlackboardModel, dartboardTxdName, dartboardTxnName)

    return duiTexture
end

function SendStartGameToDui(players)
    if not duiObject then
        return false, "DUI_OBJ_DOESNT_EXIST"
    end
    SendDuiMessage(duiObject, json.encode({ event = "startGame", payload = { players } }))
    return true
end

function SendScoreToDui(playerKey, score)
    if not duiObject then
        Trace("DUI_OBJ_DOESNT_EXIST")
        return
    end
    SendDuiMessage(duiObject, json.encode({
        event = "setScore",
        payload = { player = currentGame.players[playerKey].duiId, score = score },
    }, { indent = 2 }))
end

-- === Lobby state ===========================================================

local currentLobby = nil
local gameOriginCoords = nil

-- Awaits a server callback, notifying and returning false on failure. `delay`
-- is ox_lib's per-event cooldown/rate-limit argument (not a response timeout).
-- On success, returns whatever the callback itself returned (some callbacks
-- return `true`, others return real data, e.g. the created lobby).
function AwaitServerCallback(eventName, delay, defaultErrorKey, ...)
    local ok, result, err = pcall(lib.callback.await, eventName, delay, ...)
    if not ok then
        Trace("Server callback failed", eventName, result)
        bridge.fw.notify("error", locale(defaultErrorKey))
        return false
    end
    if not result then
        bridge.fw.notify("error", locale(err or defaultErrorKey))
        return false
    end
    return result
end

function OpenDartboardLobbyMenu(entity)
    if not (entity and DoesEntityExist(entity)) then
        return false, "OBJECT_DOESNT_EXIST"
    end

    local dartboardCoords = GetEntityCoords(entity)
    local nearbyLobbies, spectatableGames = {}, {}
    if not currentLobby then
        local ok, lobbies, games = pcall(
            lib.callback.await,
            "prp-dartboard:server:checkLobbies",
            500,
            dartboardCoords
        )
        if not ok then
            Trace("Failed to check dartboard lobbies", lobbies)
            bridge.fw.notify("error", locale("FAILED_TO_CREATE_LOBBY"))
            return false
        end
        nearbyLobbies = lobbies or {}
        spectatableGames = games or {}
    end

    local options = {}

    if currentLobby then
        if currentLobby.owner == cache.serverId then
            local playerCount = GetKeyCount(currentLobby.players)
            Trace("Player Count", playerCount)
            if playerCount > 1 then
                options[#options + 1] = {
                    title = locale("START_GAME"),
                    description = locale("START_GAME_DESCRIPTION"),
                    args = currentLobby.id,
                    icon = "play",
                    onSelect = function()
                        AwaitServerCallback("prp-dartboard:server:attemptStartGame", 500, "FAILED_TO_START_GAME")
                    end,
                }
                options[#options + 1] = {
                    title = locale("KICK_OTHER_PLAYER"),
                    description = locale("KICK_OTHER_PLAYER_DESCRIPTION"),
                    args = currentLobby.id,
                    icon = "right-from-bracket",
                    onSelect = function()
                        AwaitServerCallback("prp-dartboard:server:kickPlayer", 500, "FAILED_TO_KICK_PLAYER")
                    end,
                }
            elseif currentLobby.soloAllowed then
                options[#options + 1] = {
                    title = locale("START_PRACTICE"),
                    description = locale("START_PRACTICE_DESCRIPTION"),
                    args = currentLobby.id,
                    icon = "bullseye",
                    onSelect = function()
                        AwaitServerCallback("prp-dartboard:server:attemptStartGame", 500, "FAILED_TO_START_GAME")
                    end,
                }
            end
            options[#options + 1] = {
                title = locale("CLOSE_LOBBY"),
                description = locale("CLOSE_LOBBY_DESCRIPTION"),
                icon = "circle-xmark",
                onSelect = function()
                    if not AwaitServerCallback("prp-dartboard:server:closeLobby", 500, "FAILED_TO_CLOSE_LOBBY", currentLobby.id) then
                        return
                    end
                    bridge.fw.notify("success", locale("SUCCESSFULLY_CLOSED_LOBBY"))
                    currentLobby = nil
                    gameOriginCoords = nil
                end,
            }
        else
            options[#options + 1] = {
                title = locale("EXIT_LOBBY"),
                description = locale("EXIT_LOBBY_DESCRIPTION"),
                icon = "right-from-bracket",
                onSelect = function()
                    if not AwaitServerCallback("prp-dartboard:server:leaveLobby", 500, "FAILED_TO_LEAVE_LOBBY", currentLobby.id) then
                        return
                    end
                    bridge.fw.notify("success", locale("LEFT_LOBBY"))
                    currentLobby = nil
                    gameOriginCoords = nil
                end,
            }
        end
    elseif GetKeyCount(spectatableGames) > 0 then
        -- Only ever offer to spectate the first game found at this board.
        for gameId in pairs(spectatableGames) do
            options[#options + 1] = {
                title = locale("SPECTATE_GAME"),
                description = locale("SPECTATE_GAME_DESCRIPTION"),
                icon = "eye",
                onSelect = function()
                    AwaitServerCallback("prp-dartboard:server:spectateGame", 500, "FAILED_TO_SPECTATE_GAME", gameId)
                end,
            }
            break
        end
    else
        local foundJoinableLobby = false
        for lobbyId, lobbyData in pairs(nearbyLobbies) do
            if lobbyData.ownerName then
                foundJoinableLobby = true
                options[#options + 1] = {
                    title = locale("REQUEST_JOIN_LOBBY", lobbyData.ownerName or "A Person"),
                    description = locale("REQUEST_JOIN_LOBBY_DESCRIPTION"),
                    icon = "right-to-bracket",
                    onSelect = function()
                        AwaitServerCallback("prp-dartboard:server:requestJoinLobby", 500, "JOIN_REQUEST_DENIED", lobbyId)
                    end,
                }
            end
        end

        if not foundJoinableLobby then
            options[#options + 1] = {
                title = locale("CREATE_A_LOBBY"),
                description = locale("CREATE_A_LOBBY_DESCRIPTION"),
                icon = "plus",
                onSelect = function()
                    local wager
                    while true do
                        Wait(100)
                        local input = bridge.fw.inputDialog(locale("DART_WAGER_INPUT_TITLE"), {
                            {
                                type = "number",
                                label = locale("DART_WAGER_INPUT_LABEL"),
                                description = locale("DART_WAGER_INPUT_DESCRIPTION", Wagers.Minimum, Wagers.Maximum),
                                required = true,
                                min = Wagers.Minimum,
                                max = Wagers.Maximum,
                            },
                        })
                        if not input or input[1] == nil then
                            return
                        end
                        wager = input[1]
                        if wager % 2 == 0 then
                            break
                        end
                        bridge.fw.notify("error", locale("NEED_EVEN_NUMBER"))
                        Wait(100)
                    end

                    local lobby = AwaitServerCallback("prp-dartboard:server:createLobby", false, "FAILED_TO_CREATE_LOBBY",
                        dartboardCoords, wager, GetEntityRotation(entity, 2))
                    if not lobby then
                        return
                    end
                    currentLobby = lobby
                    gameOriginCoords = lobby.dartboardCoords or dartboardCoords
                    bridge.fw.notify("success", locale("CREATED_LOBBY"))
                end,
            }
        end
    end

    bridge.fw.contextMenu({
        id = "darts-show-lobby",
        title = currentLobby and locale("REQUEST_JOIN_LOBBY", currentLobby.ownerName) or locale("DART_BOARD"),
        options = options,
    })
    bridge.fw.showContext("darts-show-lobby")
end

-- === Throwing =============================================================

function GetDartboardStandingOffset(entity)
    return GetOffsetFromEntityInWorldCoords(entity, 0.0, -2.75, -0.774731)
end

local isThrowSequenceActive = false

-- Applies one dart's score against the running turn total and reports the
-- outcome. Returns (newScoreOrSentinel, won, busted, missedDoubleOut, oneRemaining).
function EvaluateDartThrow(currentScore, pointsThisTurn, hitDouble)
    local remaining = currentScore - pointsThisTurn

    if remaining == 0 then
        if not hitDouble then
            return currentScore, false, false, true, false
        end
        return 0, true, false, false, false
    end

    if remaining == 1 then
        return currentScore, false, false, false, true
    end

    if remaining < 0 then
        return remaining, false, true, false, false
    end

    return remaining, false, false, false, false
end

-- Converts a dart's landing offset (in the dartboard's local space) into a
-- point value, using the standard 20-segment/double/triple ring layout.
function CalculateDartScore(hitDartboardModel, dartboardLocalOffset)
    local nudgedX = dartboardLocalOffset.x + 0.0041
    local nudgedZ = dartboardLocalOffset.z + 2.0e-4
    local distanceFromCenter = math.sqrt(nudgedX * nudgedX + nudgedZ * nudgedZ)
    local angle = GetAngleBetween_2dVectors(0.0, 1.0, nudgedX, nudgedZ)

    local pointValue = 0
    local multiplier = 1
    local isDouble = false

    if hitDartboardModel then
        if distanceFromCenter < 0.009 then
            pointValue = 50
            isDouble = true
        elseif distanceFromCenter < 0.021 then
            pointValue = 25
        elseif distanceFromCenter > 0.3 then
            pointValue = 0
        elseif distanceFromCenter >= 0.226 then
            pointValue = 0
        else
            if distanceFromCenter > 0.1285 and distanceFromCenter < 0.1405 then
                multiplier = 3
            elseif distanceFromCenter > 0.2132 and distanceFromCenter < 0.226 then
                multiplier = 2
                isDouble = true
            end

            if dartboardLocalOffset.x < 0 then
                angle = 360 - angle
            end

            local segmentAngleStart = 0.0
            for segmentIndex = 0, 20 do
                if angle >= segmentAngleStart - 9.0 and angle < segmentAngleStart + 9.0 then
                    pointValue = dartState.trianglePoints[segmentIndex] * multiplier
                end
                segmentAngleStart = segmentAngleStart + 18.0
            end
        end
    end

    return pointValue, isDouble
end

function TeleportToDartboardAndThrow(entity)
    DoScreenFadeOut(1000)
    while not IsScreenFadedOut() do
        Wait(50)
    end

    local throwingPosition = GetDartboardStandingOffset(entity)
    local dartboardHeading = GetEntityHeading(entity)
    SetEntityCoords(cache.ped, throwingPosition.x, throwingPosition.y, throwingPosition.z - 0.9, false, false, false, false)
    SetEntityHeading(cache.ped, dartboardHeading - 25.0)
    Wait(100)
    FreezeEntityPosition(cache.ped, true)

    RequestAnimDict("mini@darts")
    while not HasAnimDictLoaded("mini@darts") do
        Citizen.Wait(0)
    end

    local throwerCoords = GetEntityCoords(cache.ped)
    dartState.activeDartProp = CreateObject(-472443277, throwerCoords.x, throwerCoords.y, throwerCoords.z, false, false, false)
    AttachEntityToEntity(dartState.activeDartProp, cache.ped, GetPedBoneIndex(cache.ped, 57005),
        0.16, 0.05, 0.0, 300.0, 0.0, -20.0, false, false, false, true, 0, true)
    dartState.animState = "basic"
    isThrowSequenceActive = true
    local throwGeneration = turnGeneration

    DoScreenFadeIn(1000)

    CreateThread(function()
        if not HasStreamedTextureDictLoaded("darts") then
            RequestStreamedTextureDict("darts", false)
            while not HasStreamedTextureDictLoaded("darts") do
                Wait(0)
            end
        end

        local reticuleSize = 0.025
        local previousCamViewMode = GetFollowPedCamViewMode()

        bridge.fw.showTextUI(locale("DART_THROW_ACTION"), { position = "bottom-center", icon = "hand" })

        RequestAnimDict("mini@darts")
        while not HasAnimDictLoaded("mini@darts") do
            Citizen.Wait(0)
            RequestAnimDict("mini@darts")
        end

        if currentGame.myPoints < 100 then
            bridge.fw.notify("inform", locale("REMEMBER_TO_HIT_A_DOUBLE"))
        end

        local dartsThrownThisTurn = 0
        local turnTotal = 0

        while isThrowSequenceActive do
            DrawSprite("darts", "dart_reticules", 0.5, 0.5, reticuleSize, reticuleSize * GetAspectRatio(false), 0.0, 255, 255, 255, 255)

            DisableAllControlActions(0)
            local triggerPressed = IsDisabledControlJustPressed(0, Config.Keybinds.ThrowDarts)
            EnableControlAction(0, 1, true)
            EnableControlAction(0, 2, true)
            EnableControlAction(0, 3, true)
            EnableControlAction(0, 4, true)
            EnableControlAction(0, 249, true)

            if GetFollowPedCamViewMode() ~= 4 then
                SetFollowPedCamViewMode(4)
            end

            if triggerPressed and dartState.animState == "aim" then
                local hitCoords, hitEntity = RaycastFromCamera()
                local hitDartboardModel = false
                if hitCoords and hitEntity then
                    if IsEntityAnObject(hitEntity) and hitEntity ~= 0 and DoesEntityExist(hitEntity) then
                        -- Only the exact database-backed board that started this
                        -- throw can score. A nearby/world prop with the same model
                        -- is still treated as a miss.
                        hitDartboardModel = hitEntity == entity and IsManagedDartboardEntity(hitEntity)
                    end
                end

                local preThrowRotation = GetEntityRotation(dartState.activeDartProp, 0)
                dartState.animState = "throwing"
                TaskPlayAnim(cache.ped, "mini@darts", "throw_overlay", 8.0, -8.0, 8000, 0, 1, false, false, false)
                Citizen.Wait(200)
                DetachEntity(dartState.activeDartProp, false, false)
                SetEntityRotation(dartState.activeDartProp, preThrowRotation[1], preThrowRotation[2], preThrowRotation[3], 0, true)
                SetEntityCoordsNoOffset(dartState.activeDartProp, hitCoords.x, hitCoords.y, hitCoords.z, false, false, false)
                FreezeEntityPosition(dartState.activeDartProp, true)

                local pointsThisDart, hitDouble = 0, false
                if hitDartboardModel then
                    local dartWorldCoords = GetEntityCoords(dartState.activeDartProp)
                    local dartboardLocalOffset = GetOffsetFromEntityGivenWorldCoords(
                        hitEntity, dartWorldCoords.x, dartWorldCoords.y, dartWorldCoords.z)
                    pointsThisDart, hitDouble = CalculateDartScore(true, dartboardLocalOffset)
                end

                -- A raycast with no nearby collision can resolve very far away.
                -- Keep a miss visual near the active board so the server can
                -- safely sync the 0-point dart without accepting arbitrary world
                -- coordinates from the client.
                if pointsThisDart == 0 then
                    local boardCoords = GetEntityCoords(entity)
                    local dartCoords = GetEntityCoords(dartState.activeDartProp)
                    local delta = dartCoords - boardCoords
                    local distance = #delta
                    if distance > DART_MISS_VISUAL_MAX_DISTANCE and distance > 0.0 then
                        local clamped = boardCoords + (delta / distance) * DART_MISS_VISUAL_MAX_DISTANCE
                        SetEntityCoordsNoOffset(dartState.activeDartProp, clamped.x, clamped.y, clamped.z, false, false, false)
                    end
                end

                Citizen.Wait(500)

                local dartId = #dartState.previousDarts + 1
                dartState.previousDarts[dartId] = {
                    id = dartId,
                    entityCoords = GetEntityCoords(dartState.activeDartProp),
                    entityRotation = preThrowRotation,
                    -- Client values are only a prediction for immediate visuals.
                    -- The server recalculates score/double from the stored board
                    -- transform and returns the authoritative result below.
                    points = pointsThisDart,
                    isDouble = hitDouble,
                    entity = dartState.activeDartProp,
                }
                dartsThrownThisTurn = dartsThrownThisTurn + 1

                FreezeEntityPosition(dartState.activeDartProp, true)
                SetEntityCollision(dartState.activeDartProp, false, true)

                local callbackOk, synced, syncedDartOrError = pcall(
                    lib.callback.await,
                    "prp-dartboard:server:syncDart",
                    250,
                    dartState.previousDarts[dartId]
                )
                if not callbackOk or not synced then
                    if callbackOk and syncedDartOrError then
                        bridge.fw.notify("error", locale(syncedDartOrError))
                    else
                        Trace("Failed to sync dart callback", synced)
                        bridge.fw.notify("error", locale("FAILED_TO_UPDATE_SCORE"))
                    end
                    isThrowSequenceActive = false
                    break
                end

                -- Never use the client's predicted score to decide win/bust. If
                -- floating point/rotation math differs at a ring boundary, using
                -- the server result prevents an early turnFinished call from
                -- aborting an otherwise valid turn.
                if type(syncedDartOrError) == "table" then
                    pointsThisDart = tonumber(syncedDartOrError.points) or 0
                    hitDouble = syncedDartOrError.isDouble == true
                    dartState.previousDarts[dartId].points = pointsThisDart
                    dartState.previousDarts[dartId].isDouble = hitDouble
                end

                Trace("Player Starting Points", currentGame.myPoints, "Points This Turn", turnTotal,
                    "Authoritative Points This Dart", pointsThisDart, "New Total", turnTotal + pointsThisDart)
                turnTotal = turnTotal + pointsThisDart

                local newScore, won, busted, missedDoubleOut, oneRemaining = EvaluateDartThrow(currentGame.myPoints, turnTotal, hitDouble)

                if missedDoubleOut or busted or won or oneRemaining then
                    if missedDoubleOut then
                        if not AwaitServerCallback("prp-dartboard:server:turnFinished", 500, "FAILED_TO_UPDATE_SCORE", false, turnTotal) then
                            isThrowSequenceActive = false
                            break
                        end
                        bridge.fw.notify("error", locale("WIN_NO_DOUBLE"))
                        break
                    end
                    if busted then
                        if not AwaitServerCallback("prp-dartboard:server:turnFinished", 500, "FAILED_TO_UPDATE_SCORE", false, turnTotal) then
                            isThrowSequenceActive = false
                            break
                        end
                        bridge.fw.notify("error", locale("BUSTED"))
                        break
                    end
                    if oneRemaining then
                        if not AwaitServerCallback("prp-dartboard:server:turnFinished", 500, "FAILED_TO_UPDATE_SCORE", false, turnTotal) then
                            isThrowSequenceActive = false
                            break
                        end
                        bridge.fw.notify("error", locale("ONE_REMAINING"))
                        break
                    end
                    -- Only `won` can still be true here.
                    if not AwaitServerCallback("prp-dartboard:server:turnFinished", 500, "FAILED_TO_UPDATE_SCORE", false, turnTotal, hitDouble) then
                        isThrowSequenceActive = false
                        break
                    end
                    break
                end

                if dartsThrownThisTurn >= 3 then
                    if not AwaitServerCallback("prp-dartboard:server:turnFinished", 500, "FAILED_TO_UPDATE_SCORE", false, turnTotal) then
                        isThrowSequenceActive = false
                    end
                    break
                else
                    -- Only create the next held dart when the same turn is
                    -- actually continuing. Score state remains server-authoritative
                    -- and is updated through `setScores`.
                    dartState.activeDartProp = CreateObject(
                        -472443277, throwerCoords.x, throwerCoords.y, throwerCoords.z, false, false, false)
                    AttachEntityToEntity(dartState.activeDartProp, cache.ped, GetPedBoneIndex(cache.ped, 57005),
                        0.16, 0.05, 0.0, 300.0, 0.0, -20.0, 0, false, false, true, 0, true)

                    if not (dartState.animState and dartState.animState == "aim") then
                        ShakeGameplayCam("HAND_SHAKE", 2.0)
                        dartState.animState = "aim"
                    end
                    SetEntityHeading(cache.ped, dartboardHeading - 25.0)

                    if not IsEntityPlayingAnim(cache.ped, "mini@darts", "throw_idle_a", 3) then
                        TaskPlayAnim(cache.ped, "mini@darts", "throw_idle_a", 8.0, -8.0, -1, 1, 1, 0, 0, 0)
                    end
                    if not (dartState.animState and dartState.animState == "aim") then
                        ShakeGameplayCam("HAND_SHAKE", 2.0)
                        dartState.animState = "aim"
                    end
                end
            end

            Wait(0)
        end

        SetFollowPedCamViewMode(previousCamViewMode)
        ResetThrowState(throwGeneration)
    end)

    if not IsEntityPlayingAnim(cache.ped, "mini@darts", "throw_idle_a", 3) then
        TaskPlayAnim(cache.ped, "mini@darts", "throw_idle_a", 8.0, -8.0, -1, 1, 1, 0, 0, 0)
    end
    if not (dartState.animState and dartState.animState == "aim") then
        ShakeGameplayCam("HAND_SHAKE", 2.0)
        dartState.animState = "aim"
    end
end

-- === Lobby / spectating net events ========================================

RegisterNetEvent("prp-dartboard:client:lobbyUpdate", function(players, joined)
    if not currentLobby then
        return
    end

    if not players then
        if not joined then
            bridge.fw.notify("inform", locale("YOU_ARE_NO_LONGER_IN_LOBBY"))
        end
        currentLobby = nil
        gameOriginCoords = nil
        return
    end

    currentLobby.players = players
    if joined then
        bridge.fw.notify("inform", locale("JOINED_YOUR_LOBBY"))
    else
        bridge.fw.notify("inform", locale("LEFT_YOUR_LOBBY"))
    end
end)

RegisterNetEvent("prp-dartboard:client:lobbyJoined", function(lobby)
    bridge.fw.notify("inform", locale("LOBBY_JOINED"))
    currentLobby = lobby
    Trace("Joined Lobby", json.encode(currentLobby, { indent = 2 }))
    gameOriginCoords = lobby and lobby.dartboardCoords or GetEntityCoords(cache.ped)
end)

RegisterNetEvent("prp-dartboard:client:lobbyClosed", function()
    if currentLobby then
        bridge.fw.notify("inform", locale("LOBBY_CLOSED"))
    end
    currentLobby = nil
    gameOriginCoords = nil
end)

RegisterNetEvent("prp-dartboard:client:startedSpectating", function(game)
    if not game then
        bridge.fw.notify("error", locale("FAILED_TO_SPECTATE_GAME"))
        return false
    end

    if currentGame then
        bridge.fw.notify("error", locale("PLAYER_ALREADY_IN_GAME"))
        return false
    end

    currentGame = {
        isSpectating = true,
        uuid = game.uuid,
        dartboardPos = game.dartboardPos,
        players = game.players,
        ownerId = game.gameOwner,
        gameOwnerName = game.gameOwnerName,
        opponentId = game.opponentId,
        startingScore = game.startingScore or Config.StartingScore or 301,
    }
    currentGameUuid = game.uuid
    gameOriginCoords = game.dartboardPos

    for _, playerData in pairs(game.players) do
        currentGame.players[tostring(playerData.playerId)] = playerData
    end

    EnsureDartboardDui()

    local duiPlayers = {}
    local duiId = 1
    for playerKey, playerData in pairs(currentGame.players) do
        duiPlayers[tostring(duiId)] = {
            name = playerData.name,
            points = currentGame.startingScore,
        }
        currentGame.players[playerKey].duiId = duiId
        duiId = duiId + 1
    end
    SendStartGameToDui(duiPlayers)

    for playerKey, playerData in pairs(currentGame.players) do
        for i = 1, #playerData.score do
            SendScoreToDui(playerKey, playerData.score[i])
        end
    end

    for _, dart in ipairs(game.currentDarts or {}) do
        TriggerEvent("prp-dartboard:client:syncDart", dart)
    end
end)

-- === Turn / reset / cleanup ===============================================

function DeleteEntitySafely(entity)
    if not (entity and DoesEntityExist(entity)) then
        return
    end

    if NetworkGetEntityIsNetworked(entity) and not NetworkHasControlOfEntity(entity) then
        local giveUpAt = GetGameTimer() + 1000
        while not NetworkHasControlOfEntity(entity) and giveUpAt > GetGameTimer() do
            NetworkRequestControlOfEntity(entity)
            Wait(0)
        end
    end

    SetEntityAsMissionEntity(entity, true, true)
    DeleteEntity(entity)
end

function ClearPreviousDarts()
    if not dartState.previousDarts then
        return
    end

    for _, dart in pairs(dartState.previousDarts) do
        if dart.entity then
            DeleteEntitySafely(dart.entity)
        end
    end

    dartState.previousDarts = {}
end

function ResetThrowState(throwGeneration)
    -- A solo practice turn can advance back to this same client before the
    -- previous throw coroutine finishes its local cleanup. If beginThrow has
    -- already assigned a newer turn, preserve that assignment while still
    -- cleaning up the old props/animation/camera state.
    local preserveNewTurn = throwGeneration ~= nil
        and turnGeneration ~= throwGeneration
        and isMyTurn == true

    isThrowSequenceActive = false

    if IsEntityPlayingAnim(cache.ped, "mini@darts", "throw_idle_a", 3) then
        ClearPedTasks(cache.ped)
    end
    SetStreamedTextureDictAsNoLongerNeeded("darts")
    RemoveAnimDict("mini@darts")

    if dartState.activeDartProp then
        DeleteEntitySafely(dartState.activeDartProp)
        dartState.activeDartProp = nil
    end
    ClearPreviousDarts()

    if IsEntityPositionFrozen(cache.ped) then
        FreezeEntityPosition(cache.ped, false)
    end

    bridge.fw.hideTextUI()
    ShakeGameplayCam("HAND_SHAKE", 0.0)
    dartState.animState = "idle"
    if not preserveNewTurn then
        isMyTurn = false
    end

    if not currentGame then
        gameOriginCoords = nil
    end
end

function ClearCurrentGame()
    currentGame = nil
    currentGameUuid = nil
    gameOriginCoords = nil
    DestroyDartboardDui()
end

RegisterNetEvent("prp-dartboard:client:resetState", ResetThrowState)

RegisterNetEvent("prp-dartboard:client:beginThrow", function()
    ClearPreviousDarts()
    turnGeneration = turnGeneration + 1
    isMyTurn = true
    bridge.fw.notify("inform", locale("YOUR_TURN"))
end)

RegisterNetEvent("prp-dartboard:client:gameCancelled", function()
    if currentGame then
        bridge.fw.notify("inform", locale("GAME_CANCELLED"))
        ResetThrowState()
        ClearCurrentGame()
    end
end)

RegisterNetEvent("prp-dartboard:client:stoppedSpectating", function()
    Trace("prp-dartboard:client:stoppedSpectating", "Current Game?", currentGame and "yes" or "no")
    if currentGame then
        bridge.fw.notify("inform", locale("STOPPED_SPECTATING"))
        currentGame = nil
        currentGameUuid = nil
        gameOriginCoords = nil
        ClearPreviousDarts()
        DestroyDartboardDui()
    end
end)

RegisterNetEvent("prp-dartboard:client:gameFinished", function(uuid, winnerServerId, forfeited)
    if currentGame and currentGame.uuid == uuid then
        if winnerServerId == cache.serverId then
            if forfeited then
                bridge.fw.notify("success", locale("GAME_WON_FORFEIT"))
            else
                bridge.fw.notify("success", locale("GAME_WON"))
            end
        elseif forfeited then
            bridge.fw.notify("error", locale("GAME_LOST_FORFEIT"))
        else
            bridge.fw.notify("error", locale("GAME_LOST"))
        end
        ResetThrowState()
        ClearCurrentGame()
    end
end)

RegisterNetEvent("prp-dartboard:client:syncDart", function(dart)
    if not currentGame then
        return
    end
    if not dartState then
        return
    end
    if not (dart and dart.entityCoords and dart.entityRotation) then
        return
    end

    local dartId = #dartState.previousDarts + 1
    local throwerCoords = GetEntityCoords(cache.ped)
    local entity = CreateObject(-472443277, throwerCoords.x, throwerCoords.y, throwerCoords.z,
        false, false, false)

    dartState.previousDarts[dartId] = { entity = entity }

    SetEntityRotation(entity, dart.entityRotation[1], dart.entityRotation[2], dart.entityRotation[3], 0, true)
    SetEntityCoordsNoOffset(entity, dart.entityCoords.x, dart.entityCoords.y, dart.entityCoords.z, false, false, false)
    FreezeEntityPosition(entity, true)
    SetEntityCollision(entity, false, true)
end)

RegisterNetEvent("prp-dartboard:client:setScores", function(players, scoringPlayerId)
    if not players then
        Trace("Failed to update scores because `players` is invalid")
        return
    end
    if not currentGame then
        Trace("Failed to update scores because `currentGame` doesnt exist")
        return
    end

    Trace("Attempt Update Scores for player", scoringPlayerId, json.encode(players, { indent = 2 }))

    for playerKey, playerData in pairs(players) do
        if tonumber(playerKey) == scoringPlayerId then
            SendScoreToDui(playerKey, playerData.points)
            currentGame.players[playerKey].points = playerData.points
            if scoringPlayerId == cache.serverId and not currentGame.isSpectating then
                currentGame.myPoints = playerData.points
            end
        end
    end

    if currentGame.isSpectating then
        ClearPreviousDarts()
    end
end)

RegisterNetEvent("prp-dartboard:client:gameStarted", function(uuid, players, startingTurnPlayerId, playerTwoId, dartboardPos, soloGame)
    if not uuid then
        return
    end

    currentGameUuid = uuid

    local playerNum = soloGame and 1 or (playerTwoId ~= cache.serverId and 1 or 2)
    local opponentNum = playerNum == 1 and 2 or 1
    local opponentId
    for _, playerData in pairs(players) do
        if playerData.playerId ~= cache.serverId then
            opponentId = playerData.playerId
            break
        end
    end

    local game = {
        uuid = uuid,
        playerNum = playerNum,
        opponentNum = opponentNum,
        dartboardPos = dartboardPos,
        players = players,
        opponentId = opponentId,
        playerTurn = startingTurnPlayerId,
        solo = soloGame == true,
    }

    local myPlayerData = players[tostring(cache.serverId)]
    game.myPoints = (myPlayerData and myPlayerData.points) or Config.StartingScore or 301
    currentGame = game

    EnsureDartboardDui()

    local duiPlayers = {}
    local duiId = 1
    for playerKey, playerData in pairs(currentGame.players) do
        duiPlayers[tostring(duiId)] = playerData
        currentGame.players[playerKey].duiId = tonumber(duiId)
        duiId = duiId + 1
    end
    if game.solo and not duiPlayers["2"] then
        duiPlayers["2"] = {
            name = locale("PRACTICE_TARGET"),
            points = game.myPoints,
        }
    end
    SendStartGameToDui(duiPlayers)

    isMyTurn = startingTurnPlayerId == cache.serverId
    currentLobby = nil
    gameOriginCoords = dartboardPos or GetEntityCoords(cache.ped)

end)

-- === Camera raycasting (glm) ==============================================

local glm = require("glm")
local glmRad = glm.rad
local glmCross = glm.cross
local glmMat3 = glm.mat3
local glmDegrees = glm.degrees
local glmQuatEulerAngleZYX = glm.quatEulerAngleZYX
local glmRayPicking = glm.rayPicking
local glmUp = glm.up()
local glmForward = glm.forward()

local cachedScreenInfo = {}

function BuildCameraRay()
    if next(cachedScreenInfo) == nil then
        cachedScreenInfo.ratio = GetAspectRatio(true)
        cachedScreenInfo.fov = GetGameplayCamFov()
    end

    local camCoord = GetGameplayCamCoord()
    local camRot = glmRad(GetGameplayCamRot(2))
    local camQuat = glmQuatEulerAngleZYX(camRot.z, camRot.y, camRot.x)

    return camCoord, glmRayPicking(camQuat * glmForward, camQuat * glmUp,
        glmRad(cachedScreenInfo.fov), cachedScreenInfo.ratio, 0.1, 10000.0, 0, 0)
end

RaycastFromCamera = function()
    local origin, direction = BuildCameraRay()
    local farPoint = origin + 10000 * direction

    local shapeTest = StartShapeTestLosProbe(origin.x, origin.y, origin.z, farPoint.x, farPoint.y, farPoint.z,
        4294967295, cache.ped, 0)
    while true do
        local retval, _, endCoords, _, hitEntity = GetShapeTestResult(shapeTest)
        if retval ~= 1 then
            return endCoords.xyz, hitEntity
        end
        Wait(0)
    end
end

-- === ox_target options =====================================================

local aimDartOption = {
    name = "dartboard_aim",
    icon = "fas fa-bullseye",
    label = locale("TARGET_AIM_LABEL"),
    data = {},
    distance = 6.0,
    canInteract = function(entity)
        if not IsManagedDartboardEntity(entity) then
            return false
        end
        if not currentGame then
            return false
        end
        if not isMyTurn then
            return false
        end
        if isThrowSequenceActive then
            return false
        end
        return true
    end,
    onSelect = function(data)
        if not IsOriginalDartboard(data.entity, gameOriginCoords) then
            Trace("NOT_OG_DARTBOARD")
            bridge.fw.notify("error", locale("NOT_ORIGINAL_DARTBOARD"))
            return false
        end
        TeleportToDartboardAndThrow(data.entity)
    end,
}

local viewScoresOption = {
    name = "dartboard_view_scores",
    icon = "fas fa-list",
    label = locale("TARGET_VIEW_SCORE_LABEL"),
    data = {},
    distance = 6.0,
    canInteract = function(entity)
        if not IsManagedDartboardEntity(entity) then
            return false
        end
        if not currentGame then
            return false
        end
        if isThrowSequenceActive then
            return false
        end
        return true
    end,
    onSelect = function(data)
        if not IsOriginalDartboard(data.entity, gameOriginCoords) then
            Trace("NOT_OG_DARTBOARD")
            bridge.fw.notify("error", locale("NOT_ORIGINAL_DARTBOARD"))
            return false
        end

        local options = {}
        for _, playerData in pairs(currentGame.players) do
            options[#options + 1] = {
                title = playerData.name,
                description = tostring(playerData.points),
                icon = "bullseye",
            }
        end

        bridge.fw.contextMenu({ id = "darts-view-scores", title = locale("VIEW_SCORE_LIST_TITLE"), options = options })
        bridge.fw.showContext("darts-view-scores")
    end,
}

local forfeitOption = {
    name = "dartboard_forfeit",
    icon = "fas fa-face-angry",
    label = locale("TARGET_FORFEIT_LABEL"),
    data = {},
    distance = 6.0,
    canInteract = function(entity)
        if not IsManagedDartboardEntity(entity) then
            return false
        end
        if not currentGame then
            return false
        end
        if currentGame.isSpectating then
            return false
        end
        if isThrowSequenceActive then
            return false
        end
        return true
    end,
    onSelect = function(data)
        if not IsOriginalDartboard(data.entity, gameOriginCoords) then
            Trace("NOT_OG_DARTBOARD")
            bridge.fw.notify("error", locale("NOT_ORIGINAL_DARTBOARD"))
            return false
        end
        TriggerServerEvent("prp-dartboard:server:playerLeftGame", true)
    end,
}

local stopSpectatingOption = {
    name = "dartboard_stop_spectating",
    icon = "fas fa-eye-slash",
    label = locale("TARGET_STOP_SPECTATING_LABEL"),
    data = {},
    distance = 6.0,
    canInteract = function(entity)
        if not IsManagedDartboardEntity(entity) then
            return false
        end
        if not currentGame then
            return false
        end
        return currentGame.isSpectating
    end,
    onSelect = function(data)
        if not IsOriginalDartboard(data.entity, currentGame.dartboardPos) then
            Trace("NOT_OG_DARTBOARD")
            bridge.fw.notify("error", locale("NOT_ORIGINAL_DARTBOARD"))
            return false
        end
        AwaitServerCallback("prp-dartboard:server:stopSpectating", false, "FAILED_TO_STOP_SPECTATING", currentGame.uuid)
    end,
}

local joinLobbyOption = {
    name = "dartboard_lobby_join",
    icon = "fas fa-user-plus",
    label = locale("TARGET_JOIN_GAME_LABEL"),
    data = {},
    distance = 6.0,
    canInteract = function(entity, distance)
        if not IsManagedDartboardEntity(entity) then
            return false
        end
        if currentGame then
            return false
        end
        return not currentLobby
    end,
    onSelect = function(data)
        OpenDartboardLobbyMenu(data.entity)
    end,
}

local manageLobbyOption = {
    name = "dartboard_lobby_manage",
    icon = "fas fa-people-group",
    label = locale("TARGET_MANAGE_LOBBY_LABEL"),
    data = {},
    distance = 6.0,
    canInteract = function(entity, distance)
        if not IsManagedDartboardEntity(entity) then
            return false
        end
        if currentGame then
            return false
        end
        return currentLobby ~= nil
    end,
    onSelect = function(data)
        if not IsOriginalDartboard(data.entity, gameOriginCoords) then
            Trace("NOT_OG_DARTBOARD")
            bridge.fw.notify("error", locale("NOT_ORIGINAL_DARTBOARD"))
            return false
        end
        OpenDartboardLobbyMenu(data.entity)
    end,
}

local removeDartboardOption = {
    name = "dartboard_remove",
    icon = "fas fa-trash",
    label = locale("TARGET_REMOVE_DARTBOARD_LABEL"),
    data = {},
    distance = 6.0,
    canInteract = function(entity, distance)
        -- Only boards placed with /placedartboard can be removed; map boards cannot.
        return isAdmin and spawnedDartboardEntities[entity] == true
    end,
    onSelect = function(data)
        local coords = GetEntityCoords(data.entity)
        TriggerServerEvent("prp-dartboard:server:removeDartboard", coords.x, coords.y, coords.z)
    end,
}

local dartboardTargetOptions = {
    aimDartOption, viewScoresOption, forfeitOption, stopSpectatingOption,
    joinLobbyOption, manageLobbyOption, removeDartboardOption,
}

CreateThread(function()
    Wait(2000)

    local optionNames = {}
    for _, option in ipairs(dartboardTargetOptions) do
        optionNames[#optionNames + 1] = option.name
    end

    Wait(500)
    bridge.target.removeModel(Config.DartboardModel, optionNames)
    Wait(500)
    bridge.target.addModel(Config.DartboardModel, dartboardTargetOptions)

    TriggerServerEvent("prp-dartboard:server:requestDartboards")
end)

-- === Keyboard fallback (E) + debug ==========================================
-- Builds a menu from the very same options qb-target uses, so everything still works
-- if the target eye never shows up.

local KEY_PROMPT = "[E] Dartboard"

local function GetNearestManagedBoard(maxDistance)
    local pedCoords = GetEntityCoords(cache.ped)
    if Config.AllowAnyDartboard == true then
        local object = GetClosestObjectOfType(pedCoords.x, pedCoords.y, pedCoords.z, maxDistance, Config.DartboardModel, false, false, false)
        if object and object ~= 0 then
            return object
        end
    end
    local nearest, nearestDistance
    for entity in pairs(spawnedDartboardEntities) do
        if DoesEntityExist(entity) then
            local distance = #(pedCoords - GetEntityCoords(entity))
            if distance <= maxDistance and (not nearestDistance or distance < nearestDistance) then
                nearest, nearestDistance = entity, distance
            end
        end
    end
    return nearest
end

local function OpenBoardKeyMenu(entity)
    local entries = {}
    for _, option in ipairs(dartboardTargetOptions) do
        local ok, allowed = pcall(option.canInteract, entity, 0.0)
        if ok and allowed then
            local icon = option.icon and (option.icon:gsub("^fas? fa%-", "")) or nil
            entries[#entries + 1] = {
                title = option.label,
                icon = icon,
                onSelect = function()
                    option.onSelect({
                        entity = entity,
                        coords = GetEntityCoords(entity),
                        distance = 0.0,
                        name = option.name,
                    })
                end,
            }
        end
    end

    if #entries == 0 then
        return
    end

    bridge.fw.contextMenu({ id = "darts-key-menu", title = locale("DART_BOARD"), options = entries })
    bridge.fw.showContext("darts-key-menu")
end

CreateThread(function()
    if Config.KeyFallback == false then
        return
    end

    while true do
        local sleep = 500
        local entity = (not isThrowSequenceActive) and GetNearestManagedBoard(2.5) or nil
        local open, text = lib.isTextUIOpen()

        if entity then
            sleep = 0
            if not open then
                lib.showTextUI(KEY_PROMPT, { position = "right-center", icon = "bullseye" })
            end
            if IsControlJustPressed(0, 38) then
                OpenBoardKeyMenu(entity)
            end
        elseif open and text == KEY_PROMPT then
            lib.hideTextUI()
        end

        Wait(sleep)
    end
end)

RegisterCommand("dartdebug", function()
    local n = 0
    for entity in pairs(spawnedDartboardEntities) do
        n = n + 1
        print(("[NOX-Darts] spawned board entity %s exists=%s coords=%s"):format(entity, tostring(DoesEntityExist(entity)), GetEntityCoords(entity)))
    end
    local summary = ("boards known: %d | spawned nearby: %d | qb-target: %s | assets: %s | model ok: %s | admin: %s"):format(
        GetKeyCount(Dartboards), n, GetResourceState("qb-target"), GetResourceState("NOX-DartsAssets"),
        tostring(IsModelInCdimage(Config.DartboardModel)), tostring(isAdmin))
    print("[NOX-Darts] " .. summary)
    bridge.fw.notify("inform", summary, "Dartboard debug", 10000)

    -- What are you looking at? Handy to find out the model of another dartboard.
    local _, target = RaycastFromCamera()
    if target and target ~= 0 then
        local looking = ("looking at model %s | supported dartboard: %s"):format(
            GetEntityModel(target), tostring(IsManagedDartboardEntity(target)))
        print("[NOX-Darts] " .. looking)
        bridge.fw.notify("inform", looking, "Dartboard debug", 10000)
    end
end, false)

AddEventHandler("onResourceStop", function(stoppedResource)
    if stoppedResource ~= resourceName then
        return
    end

    isThrowSequenceActive = false
    isMyTurn = false
    DestroyDartboardDui()
    ClearPreviousDarts()
    if dartState.activeDartProp then
        DeleteEntitySafely(dartState.activeDartProp)
        dartState.activeDartProp = nil
    end

    ClearPedTasksImmediately(cache.ped)
    if IsEntityPositionFrozen(cache.ped) then
        FreezeEntityPosition(cache.ped, false)
    end
    bridge.fw.hideTextUI()
    ShakeGameplayCam("HAND_SHAKE", 0.0)

    if IsScreenFadedOut() then
        DoScreenFadeIn(0)
    end
end)

-- === Placing dartboards ====================================================

function ScreenRaycast(ignoreEntity)
    local screenX = GetDisabledControlNormal(0, 239)
    local screenY = GetDisabledControlNormal(0, 240)
    local origin, direction = GetWorldCoordFromScreenCoord(screenX, screenY)

    local nearPoint = origin - direction * 0.1
    local farPoint = origin + direction * 1000.0

    local shapeTest = StartExpensiveSynchronousShapeTestLosProbe(nearPoint.x, nearPoint.y, nearPoint.z,
        farPoint.x, farPoint.y, farPoint.z, 511, ignoreEntity, 0)
    local _, hit, endCoords, surfaceNormal = GetShapeTestResult(shapeTest)
    return hit, endCoords, surfaceNormal
end

function GetSurfaceAlignedRotation(surfaceNormal)
    local right = glmCross(glmUp, surfaceNormal)
    local forward = glmCross(surfaceNormal, right)
    local basis = glmMat3(surfaceNormal, right, forward)
    local euler = glmDegrees(glm.vec(basis:extractEulerAngleZYX()))
    return euler.zyx + vec3(0.0, 0.0, 90.0)
end

function RunDartboardPlacementLoop(previewEntity)
    local hit, hitCoords, surfaceNormal

    bridge.fw.showTextUI(locale("PLACE_DARTBOARD_INSTRUCTIONS"), { position = "bottom-center", icon = "mouse-pointer" })
    SetCursorLocation(0.7, 0.5)

    while true do
        DisableAllControlActions(0)
        SetMouseCursorActiveThisFrame()

        hit, hitCoords, surfaceNormal = ScreenRaycast(previewEntity)
        if hit and hitCoords then
            SetEntityCoordsNoOffset(previewEntity, hitCoords.x, hitCoords.y, hitCoords.z, false, false, false)
            local rotation = GetSurfaceAlignedRotation(surfaceNormal)
            SetEntityRotation(previewEntity, rotation.x, rotation.y, rotation.z, 2, true)
        end

        if IsDisabledControlJustPressed(0, Config.Keybinds.ConfirmPlaceDartboard) and hit and hitCoords then
            bridge.fw.hideTextUI()
            return { coords = GetEntityCoords(previewEntity), rotation = GetEntityRotation(previewEntity, 2) }
        end

        if IsDisabledControlJustPressed(0, Config.Keybinds.CancelPlaceDartboard) then
            bridge.fw.hideTextUI()
            return nil
        end

        Wait(0)
    end
end

function PlaceDartboard()
    if not LoadModel(Config.DartboardModel) then
        return
    end

    local spawnPos = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 1.5, 0.0)
    local previewEntity = CreateObject(Config.DartboardModel, spawnPos.x, spawnPos.y, spawnPos.z, false, true, true)
    SetEntityAsMissionEntity(previewEntity, true, true)
    FreezeEntityPosition(previewEntity, true)
    SetEntityNoCollisionEntity(previewEntity, cache.ped, false)
    SetEntityCompletelyDisableCollision(previewEntity, true, true)

    local placement = RunDartboardPlacementLoop(previewEntity)
    DeleteEntity(previewEntity)

    if not placement then
        return
    end

    TriggerServerEvent("prp-dartboard:server:addDartboard",
        placement.coords.x, placement.coords.y, placement.coords.z,
        placement.rotation.x, placement.rotation.y, placement.rotation.z)
end

RegisterNetEvent("prp-dartboard:client:placeDartboard", PlaceDartboard)

function SpawnDartboardEntity(propPoint)
    if not LoadModel(Config.DartboardModel) then
        return
    end
    local entity = CreateObject(Config.DartboardModel, propPoint.coords.x, propPoint.coords.y, propPoint.coords.z, false, true, true)
    SetEntityAsMissionEntity(entity, true, true)
    FreezeEntityPosition(entity, true)
    SetEntityCoordsNoOffset(entity, propPoint.coords.x, propPoint.coords.y, propPoint.coords.z, false, false, false)
    SetEntityRotation(entity, propPoint.rot.x, propPoint.rot.y, propPoint.rot.z, 2, true)

    propPoint.entity = entity
    spawnedDartboardEntities[entity] = true
end

function DespawnDartboardEntity(propPoint)
    local entity = propPoint.entity
    if not entity then
        return
    end

    -- Clear bookkeeping even if another resource/engine cleanup already
    -- removed the local prop; otherwise stale handles remain marked managed.
    spawnedDartboardEntities[entity] = nil
    propPoint.entity = nil

    if DoesEntityExist(entity) then
        SetEntityAsMissionEntity(entity, true, true)
        DeleteEntity(entity)
    end
end

AddEventHandler("onResourceStop", function(stoppedResource)
    if stoppedResource ~= resourceName then
        return
    end

    for entity in pairs(spawnedDartboardEntities) do
        if DoesEntityExist(entity) then
            SetEntityAsMissionEntity(entity, true, true)
            DeleteEntity(entity)
        end
    end
end)

function CreateDartboardPropPoint(dartboard)
    local data = dartboard.data
    local propPoint = lib.points.new({
        coords = vec3(data[1], data[2], data[3]),
        rot = vec3(data[4], data[5], data[6]),
        id = dartboard.id,
        distance = Config.DartboardsRenderDistance or 50.0,
    })
    propPoint.onEnter = SpawnDartboardEntity
    propPoint.onExit = DespawnDartboardEntity

    Dartboards[dartboard.id].propPoint = propPoint
end

RegisterNetEvent("prp-dartboard:client:setDartboards", function(dartboards, admin)
    if not dartboards then
        print("ERROR: Failed to set dartboards because `dartboards` was nil")
        return
    end

    -- A refresh can happen more than once during a client session. Tear down
    -- the old points/entities first so a second snapshot cannot duplicate props.
    for _, existing in pairs(Dartboards) do
        if existing.propPoint then
            DespawnDartboardEntity(existing.propPoint)
            existing.propPoint:remove()
        end
    end

    Dartboards = dartboards
    isAdmin = admin == true

    for _, dartboard in pairs(Dartboards) do
        CreateDartboardPropPoint(dartboard)
    end
end)

RegisterNetEvent("prp-dartboard:client:addDartboard", function(id, x, y, z, rotX, rotY, rotZ)
    local existing = Dartboards[id]
    if existing and existing.propPoint then
        DespawnDartboardEntity(existing.propPoint)
        existing.propPoint:remove()
    end

    Dartboards[id] = { id = id, data = { x, y, z, rotX, rotY, rotZ } }
    CreateDartboardPropPoint(Dartboards[id])
end)

RegisterNetEvent("prp-dartboard:client:removeDartboard", function(id, x, y, z)
    local dartboard = Dartboards[id]
    if not dartboard then
        return
    end

    if dartboard.propPoint then
        DespawnDartboardEntity(dartboard.propPoint)
        dartboard.propPoint:remove()
    end

    Dartboards[id] = nil
end)
