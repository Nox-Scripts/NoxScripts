Bridge.RegisterCallback('laugh_bagpick:checkCops', function(src, cb)
    local players = Bridge.GetOnlinePlayers()

    local police = 0
    for i = 1, #players do
        local job = Bridge.GetPlayerJob(players[i])
        for k, v in pairs(Config.PoliceJobs) do
            if job == v then
                police = police + 1
            end
        end
    end

    cb(police >= Config.PoliceRequired)
end)

-- Discord webhooks (optional)
--   set bagpick_webhook_money "https://discord.com/api/webhooks/..."
--   set bagpick_webhook_item  "https://discord.com/api/webhooks/..."
local function sendWebhook(convarName, embed)
    local url = GetConvar(convarName, '')
    if url == '' then return end
    PerformHttpRequest(url, function(err, text, headers) end, 'POST', json.encode({ embeds = { embed } }), { ['Content-Type'] = 'application/json' })
end

local function getSteamId(src)
    for k, v in pairs(GetPlayerIdentifiers(src)) do
        if string.sub(v, 1, 6) == "steam:" then
            return v
        end
    end
    return "Not found"
end

local function grantRandomReward(src)
    if not Bridge.PlayerExists(src) then return end

    local coords = Bridge.GetPlayerCoords(src)
    local pos = string.format("X: %.2f, Y: %.2f, Z: %.2f", coords.x, coords.y, coords.z)
    local name = Bridge.GetPlayerName(src)
    local steamID = getSteamId(src)

    if math.random() < 0.5 then
        local amount = math.random(Config.money[1], Config.money[2])
        Bridge.AddMoney(src, amount)
        Bridge.Notify(src, "You found ~g~" .. amount .. "$~s~ in the bag!")

        sendWebhook('bagpick_webhook_money', {
            ["title"] = "Handbag theft",
            ["description"] = string.format("**Name:** %s\n**Steam ID:** %s\n**Coordinates:** %s\n**Amount stolen:** $%d", name, steamID, pos, amount),
            ["color"] = 16711680,
        })
    else
        local item = Config.item[math.random(#Config.item)]
        local qty = math.max(1, math.floor(tonumber(item.quantite) or 1))
        if not Bridge.AddItem(src, item.item, qty) then
            Bridge.Notify(src, "~r~You can't carry this item.")
            return
        end
        Bridge.Notify(src, "~g~Item found~s~: You got ~g~" .. qty .. " " .. item.label)

        sendWebhook('bagpick_webhook_item', {
            ["title"] = "Handbag theft",
            ["description"] = string.format("**Name:** %s\n**Steam ID:** %s\n**Coordinates:** %s\n**Item stolen:** %s x%d", name, steamID, pos, item.label, qty),
            ["color"] = 16711680,
        })
    end
end

-- Prevents 2 players robbing the same NPC, indexed by NetworkId (valid server + all clients)
local busyNpcs = {}

RegisterServerEvent('laugh_bagpick:npcBusy')
AddEventHandler('laugh_bagpick:npcBusy', function(netID)
    busyNpcs[netID] = true
    TriggerClientEvent('laugh_bagpick:syncBusyNpcs', -1, busyNpcs)
end)

RegisterServerEvent('laugh_bagpick:npcFreed')
AddEventHandler('laugh_bagpick:npcFreed', function(netID)
    busyNpcs[netID] = nil
    TriggerClientEvent('laugh_bagpick:syncBusyNpcs', -1, busyNpcs)
end)

Bridge.RegisterCallback('laugh_bagpick:isNpcBusy', function(src, cb, netID)
    cb(busyNpcs[netID] ~= nil)
end)

local pendingHandReward = {}

RegisterServerEvent('laugh_bagpick:theftSuccess')
AddEventHandler('laugh_bagpick:theftSuccess', function()
    local src = source
    pendingHandReward[src] = true
    -- Window must comfortably outlast Config.FouilleSacTime (the search animation itself)
    -- plus realistic time for the player to reposition/hide before pressing Search.
    -- Previously a flat 20000ms, which is barely above the default 12000ms search time
    -- and left almost no margin, so legitimate searches expired mid-animation and
    -- failed with zero feedback.
    local window = (Config.FouilleSacTime or 12000) + 120000
    SetTimeout(window, function()
        if pendingHandReward[src] then
            pendingHandReward[src] = nil
        end
    end)
end)

RegisterServerEvent('laugh_bagpick:claimHandReward')
AddEventHandler('laugh_bagpick:claimHandReward', function()
    local src = source
    if not pendingHandReward[src] then
        -- Previously failed completely silently. Notify so a genuine expiry/edge case
        -- is visible instead of looking like the bag was simply empty.
        Bridge.Notify(src, "~r~That bag is no longer worth searching.")
        return
    end
    pendingHandReward[src] = nil
    grantRandomReward(src)
end)

AddEventHandler('playerDropped', function()
    pendingHandReward[source] = nil
end)

local droppedBags = {}
local nextBagId = 1

local function generateBagId()
    local id = "bagpick_" .. nextBagId .. "_" .. os.time()
    nextBagId = nextBagId + 1
    return id
end

-- ANTI-CHEAT
local function isPlayerNearBag(src, data, maxDist)
    if not data or not data.coords then return false end
    local pc = Bridge.GetPlayerCoords(src)
    return #(vector3(pc.x, pc.y, pc.z) - data.coords) <= (maxDist or 3.0)
end

RegisterServerEvent('laugh_bagpick:dropBag')
AddEventHandler('laugh_bagpick:dropBag', function(coords)
    local src = source
    if not coords then return end
    pendingHandReward[src] = nil
    local x = coords.x or 0
    local y = coords.y or 0
    local z = coords.z or 0
    local bagId = generateBagId()
    local coordsVec = vector3(x, y, z)

    droppedBags[bagId] = { coords = coordsVec, droppedBy = src }
    TriggerClientEvent('laugh_bagpick:createDroppedBag', -1, bagId, x, y, z)

    SetTimeout(Config.BagDropTimeout or 60000, function()
        if droppedBags[bagId] then
            droppedBags[bagId] = nil
            TriggerClientEvent('laugh_bagpick:removeDroppedBag', -1, bagId)
        end
    end)
end)

RegisterServerEvent('laugh_bagpick:searchBag')
AddEventHandler('laugh_bagpick:searchBag', function(bagId)
    local src = source
    local data = droppedBags[bagId]
    if not data or not isPlayerNearBag(src, data) then return end
    droppedBags[bagId] = nil
    TriggerClientEvent('laugh_bagpick:removeDroppedBag', -1, bagId)
    grantRandomReward(src)
end)

RegisterServerEvent('laugh_bagpick:pickupBag')
AddEventHandler('laugh_bagpick:pickupBag', function(bagId)
    local src = source
    local data = droppedBags[bagId]
    if not data or not isPlayerNearBag(src, data) then return end
    droppedBags[bagId] = nil
    TriggerClientEvent('laugh_bagpick:removeDroppedBag', -1, bagId)
    TriggerClientEvent('laugh_bagpick:pickupBagSuccess', src)
end)
