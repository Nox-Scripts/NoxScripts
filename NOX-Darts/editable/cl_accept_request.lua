RegisterNetEvent("prp-dartboard:client:joinRequest", function(requestToken, requestor, timeoutMs)
    if type(requestToken) ~= "string" or type(requestor) ~= "table" then
        return
    end

    local playerName = tostring(requestor.playerName or "Player")
    timeoutMs = math.max(1000, tonumber(timeoutMs) or 7000)

    -- bridge.fw.confirmDialog (bridge/client.lua) is the standard client confirmation
    -- surface. The request/response transport itself is a source-validated net
    -- event so the server does not retain an ox_lib client-callback entry.
    local alert = bridge.fw.confirmDialog(
        locale("JOIN_REQUEST_LABEL"),
        locale("LOBBY_REQUESTED_PROMPT", playerName),
        nil,
        math.max(1, math.floor(timeoutMs - 500))
    )

    TriggerServerEvent("prp-dartboard:server:joinRequestResponse", requestToken, alert == "confirm")
end)
