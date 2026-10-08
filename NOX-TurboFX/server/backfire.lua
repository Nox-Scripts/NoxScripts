-- Relays a backfire event to every client, after checking the requested
-- sound file(s) are ones we actually ship (basic anti-tamper, since this is
-- a client-triggered event).
RegisterNetEvent('qb-carbackfire:server:broadcast', function(netId, coords, sounds)
    if type(sounds) ~= 'table' or #sounds == 0 then return end

    local function isShippedSound(s)
        for _, entry in ipairs(Config.Sounds) do
            if entry == s then return true end
        end
        return false
    end

    for _, s in ipairs(sounds) do
        if not isShippedSound(s) then return end
    end

    -- Broadcasting to everyone (-1) is simplest and totally fine for how
    -- infrequently this event fires. If you're running a very large server
    -- and want to be extra careful with bandwidth, you can swap this for a
    -- loop over GetPlayers() that only targets players within range of
    -- `coords` before triggering the client event.
    TriggerClientEvent('qb-carbackfire:client:play', -1, netId, coords, sounds)
end)
