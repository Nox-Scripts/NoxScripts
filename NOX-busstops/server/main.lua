local QBCore = exports['qb-core']:GetCoreObject()

local cooldowns = {}

-- ═══════════════════════════════════════════════════════════════
--  HELPERS
-- ═══════════════════════════════════════════════════════════════

local function notify(src, description, type, title)
    lib.notify(src, {
        title = title or 'Bus Service',
        description = description,
        type = type or 'inform',
        icon = 'bus'
    })
end

local function isOnCooldown(src)
    local last = cooldowns[src]
    if last and (os.time() - last) < Config.Cooldown then
        return true
    end
    cooldowns[src] = os.time()
    return false
end

local function getMoney(Player, account)
    if Player.Functions.GetMoney then
        local ok, amount = pcall(Player.Functions.GetMoney, account)
        if ok and amount then return amount end
    end
    return (Player.PlayerData.money and Player.PlayerData.money[account]) or 0
end

local function removeMoney(Player, account, amount, reason)
    return Player.Functions.RemoveMoney(account, amount, reason)
end

local function resolveAccount(requested)
    if requested == 'bank' and Config.AllowBankPayments then
        return 'bank'
    end
    return 'cash'
end

local function findStop(name)
    for _, loc in ipairs(Config.Locations) do
        if loc.name == name then return loc end
    end
    return nil
end

local function getCardItem(Player)
    return Player.Functions.GetItemByName(Config.Items.card)
end

local function giveItemBox(src, itemName, action)
    local itemData = QBCore.Shared.Items[itemName]
    if itemData then
        TriggerClientEvent('inventory:client:ItemBox', src, itemData, action)
    end
end

local function logWebhook(description, color)
    if not Config.LogTravel or Config.Webhook == '' then return end

    CreateThread(function()
        PerformHttpRequest(Config.Webhook, function() end, 'POST', json.encode({
            username = 'Bus Service',
            embeds = { { description = description, color = color or 3066993 } }
        }), { ['Content-Type'] = 'application/json' })
    end)
end

-- ═══════════════════════════════════════════════════════════════
--  CALLBACKS
-- ═══════════════════════════════════════════════════════════════

-- Wallet snapshot used to build the client-side menus
lib.callback.register('bus:server:getWalletInfo', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return {} end

    local ticketItem = Player.Functions.GetItemByName(Config.Items.ticket)
    local cardItem = getCardItem(Player)

    return {
        tickets = ticketItem and ticketItem.amount or 0,
        hasCard = cardItem ~= nil,
        cardBalance = (cardItem and cardItem.info and cardItem.info.balance) or 0,
        cardExpires = (cardItem and cardItem.info and cardItem.info.expires) or nil,
        cash = getMoney(Player, 'cash'),
        bank = getMoney(Player, 'bank')
    }
end)

-- Server-authoritative fare quotes for every destination, based on
-- the player's real current position (never trusts client input)
lib.callback.register('bus:server:getFareQuotes', function(source)
    local ped = GetPlayerPed(source)
    local originCoords = (ped and ped ~= 0) and GetEntityCoords(ped) or nil

    local quotes = {}
    for _, loc in ipairs(Config.Locations) do
        quotes[loc.name] = Config.CalculateFare(originCoords, loc.coords)
    end

    return quotes
end)

lib.callback.register('bus:server:buyTicket', function(source, account)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end

    account = resolveAccount(account)

    if getMoney(Player, account) < Config.TicketPrice then
        notify(source, ('You need $%d to buy a bus ticket.'):format(Config.TicketPrice), 'error')
        return false
    end

    if not removeMoney(Player, account, Config.TicketPrice, 'bus-ticket-purchase') then
        notify(source, 'Payment failed.', 'error')
        return false
    end

    Player.Functions.AddItem(Config.Items.ticket, 1)
    giveItemBox(source, Config.Items.ticket, 'add')
    notify(source, ('Purchased a bus ticket for $%d.'):format(Config.TicketPrice), 'success')
    return true
end)

lib.callback.register('bus:server:buyCard', function(source, account)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end

    if getCardItem(Player) then
        notify(source, 'You already own a bus card.', 'error')
        return false
    end

    account = resolveAccount(account)

    if getMoney(Player, account) < Config.CardPrice then
        notify(source, ('You need $%d to buy a bus card.'):format(Config.CardPrice), 'error')
        return false
    end

    if not removeMoney(Player, account, Config.CardPrice, 'bus-card-purchase') then
        notify(source, 'Payment failed.', 'error')
        return false
    end

    local info = { balance = Config.CardStartingBalance, purchased = os.time() }
    if Config.CardExpiryDays > 0 then
        info.expires = os.time() + (Config.CardExpiryDays * 86400)
    end

    Player.Functions.AddItem(Config.Items.card, 1, false, info)
    giveItemBox(source, Config.Items.card, 'add')
    notify(source, ('Purchased a bus card preloaded with $%d.'):format(Config.CardStartingBalance), 'success')
    return true
end)

lib.callback.register('bus:server:rechargeCard', function(source, account)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end

    local cardItem = getCardItem(Player)
    if not cardItem then
        notify(source, 'You do not own a bus card.', 'error')
        return false
    end

    account = resolveAccount(account)

    if getMoney(Player, account) < Config.CardTopUpAmount then
        notify(source, ('You need $%d to recharge your card.'):format(Config.CardTopUpAmount), 'error')
        return false
    end

    if not removeMoney(Player, account, Config.CardTopUpAmount, 'bus-card-recharge') then
        notify(source, 'Payment failed.', 'error')
        return false
    end

    local newInfo = cardItem.info or {}
    newInfo.balance = (newInfo.balance or 0) + Config.CardTopUpAmount

    Player.Functions.RemoveItem(Config.Items.card, 1, cardItem.slot)
    Player.Functions.AddItem(Config.Items.card, 1, cardItem.slot, newInfo)

    notify(source, ('Recharged $%d — new balance: $%d.'):format(Config.CardTopUpAmount, newInfo.balance), 'success')
    return true
end)

lib.callback.register('bus:server:travel', function(source, stopName, method)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return { ok = false } end

    if isOnCooldown(source) then
        notify(source, 'Please wait a moment before traveling again.', 'error')
        return { ok = false }
    end

    local stop = findStop(stopName)
    if not stop then
        return { ok = false, reason = 'Invalid destination' }
    end

    local ped = GetPlayerPed(source)
    local originCoords = (ped and ped ~= 0) and GetEntityCoords(ped) or nil
    local fare = Config.CalculateFare(originCoords, stop.coords)

    if method == 'ticket' then
        local ticketItem = Player.Functions.GetItemByName(Config.Items.ticket)
        if not ticketItem or ticketItem.amount < 1 then
            notify(source, 'You do not have a bus ticket.', 'error')
            return { ok = false }
        end

        Player.Functions.RemoveItem(Config.Items.ticket, 1, ticketItem.slot)
        giveItemBox(source, Config.Items.ticket, 'remove')

    elseif method == 'card' then
        local cardItem = getCardItem(Player)
        if not cardItem then
            notify(source, 'You do not have a bus card.', 'error')
            return { ok = false }
        end

        if Config.CardExpiryDays > 0 and cardItem.info.expires and os.time() > cardItem.info.expires then
            notify(source, 'Your bus card has expired. Please renew it.', 'error')
            return { ok = false }
        end

        local balance = (cardItem.info and cardItem.info.balance) or 0
        if balance < fare then
            notify(source, ('Insufficient card balance. Fare is $%d, balance is $%d.'):format(fare, balance), 'error')
            return { ok = false }
        end

        local newInfo = cardItem.info
        newInfo.balance = balance - fare
        Player.Functions.RemoveItem(Config.Items.card, 1, cardItem.slot)
        Player.Functions.AddItem(Config.Items.card, 1, cardItem.slot, newInfo)

    elseif method == 'cash' or method == 'bank' then
        local account = resolveAccount(method)
        if getMoney(Player, account) < fare then
            notify(source, ('You need $%d to pay the fare.'):format(fare), 'error')
            return { ok = false }
        end

        removeMoney(Player, account, fare, 'bus-fare')
    else
        return { ok = false, reason = 'Invalid payment method' }
    end

    logWebhook(('**%s** (`%s`) traveled to **%s** via `%s` — $%d'):format(
        GetPlayerName(source), Player.PlayerData.citizenid, stop.label, method, fare
    ))

    return { ok = true, coords = stop.coords, label = stop.label, fare = fare }
end)

-- ═══════════════════════════════════════════════════════════════
--  ADMIN COMMANDS (testing / support)
-- ═══════════════════════════════════════════════════════════════

QBCore.Commands.Add('givebuscard', 'Give a player a bus card (Admin Only)', {
    { name = 'id', help = 'Player ID' }
}, false, function(source, args)
    local targetId = tonumber(args[1])
    if not targetId then return end

    local Player = QBCore.Functions.GetPlayer(targetId)
    if not Player then return end

    Player.Functions.AddItem(Config.Items.card, 1, false, {
        balance = Config.CardStartingBalance,
        purchased = os.time()
    })
    TriggerClientEvent('QBCore:Notify', targetId, 'You received a bus card.', 'success')
end, 'admin')

QBCore.Commands.Add('givebusticket', 'Give a player bus tickets (Admin Only)', {
    { name = 'id', help = 'Player ID' },
    { name = 'amount', help = 'Amount' }
}, false, function(source, args)
    local targetId = tonumber(args[1])
    local amount = tonumber(args[2]) or 1
    if not targetId then return end

    local Player = QBCore.Functions.GetPlayer(targetId)
    if not Player then return end

    Player.Functions.AddItem(Config.Items.ticket, amount)
    TriggerClientEvent('QBCore:Notify', targetId, ('You received %d bus ticket(s).'):format(amount), 'success')
end, 'admin')

AddEventHandler('playerDropped', function()
    cooldowns[source] = nil
end)
