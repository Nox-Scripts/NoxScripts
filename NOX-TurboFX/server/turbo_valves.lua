-- Relays a triggered blow-off valve sound to every connected client, along
-- with where it happened. Each client works out its own volume based on how
-- far away that is (see the 'turbo_bov:play' handler in client.lua).

RegisterNetEvent('turbo_bov:broadcast')
AddEventHandler('turbo_bov:broadcast', function(file, coords, rate, sourceVolume)
    TriggerClientEvent('turbo_bov:play', -1, file, coords, rate, sourceVolume)
end)
