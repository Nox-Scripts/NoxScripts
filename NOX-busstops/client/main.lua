local QBCore = exports['qb-core']:GetCoreObject()

local busstopModels = {}
for model, _ in pairs(Config.Models) do
    busstopModels[#busstopModels + 1] = model
end

-- ═══════════════════════════════════════════════════════════════
--  BLIPS
-- ═══════════════════════════════════════════════════════════════
CreateThread(function()
    if not Config.Blips then return end

    for _, loc in ipairs(Config.Locations) do
        if loc.blip then
            local blip = AddBlipForCoord(loc.coords.x, loc.coords.y, loc.coords.z)
            SetBlipSprite(blip, Config.BlipSprite)
            SetBlipDisplay(blip, 4)
            SetBlipScale(blip, Config.BlipScale)
            SetBlipColour(blip, Config.BlipColor)
            SetBlipAsShortRange(blip, Config.BlipShortRange)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(loc.label)
            EndTextCommandSetBlipName(blip)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
--  HELPERS
-- ═══════════════════════════════════════════════════════════════

local function formatExpiry(timestamp)
    if not timestamp then return 'Never' end
    local remaining = timestamp - os.time()
    if remaining <= 0 then return 'Expired' end
    return ('%d day(s)'):format(math.ceil(remaining / 86400))
end

-- Cosmetic-only: walks the player to a nearby bench seat and plays a
-- sit/wait animation while the progress bar runs. Purely visual.
local function waitAtBench(entity)
    local playerPed = PlayerPedId()
    local seats = entity and DoesEntityExist(entity) and Config.Models[GetEntityModel(entity)]

    if seats then
        local idx = math.random(1, #seats)
        local seatCoords = GetOffsetFromEntityInWorldCoords(entity, seats[idx].x, seats[idx].y, 0.0)
        local heading = GetEntityHeading(entity) + 180.0
        if heading >= 360.0 then heading = heading - 360.0 end

        local startTime = GetGameTimer()
        TaskGoStraightToCoord(playerPed, seatCoords.x, seatCoords.y, seatCoords.z, 1.0, -1, heading, 0)
        Wait(400)

        while not IsPedStopped(playerPed) and GetGameTimer() - startTime < 4000 do
            Wait(50)
        end

        ClearPedTasks(playerPed)
        SetEntityCoords(playerPed, seatCoords.x, seatCoords.y, seatCoords.z, true, false, false, false)
        SetEntityHeading(playerPed, heading)
    end

    lib.requestAnimDict('timetable@ron@ig_3_couch')
    TaskPlayAnim(playerPed, 'timetable@ron@ig_3_couch', 'base', 3.0, 3.0, -1, 1, 0, false, false, false)
end

local function choosePaymentAccount(title, parentMenu, onChoose)
    local options = {
        {
            title = 'Pay with Cash',
            icon = 'fas fa-money-bill-wave',
            onSelect = function() onChoose('cash') end
        }
    }

    if Config.AllowBankPayments then
        options[#options + 1] = {
            title = 'Pay with Bank Card',
            icon = 'fas fa-university',
            onSelect = function() onChoose('bank') end
        }
    end

    lib.registerContext({
        id = 'bus_account_menu',
        title = title,
        menu = parentMenu,
        options = options
    })
    lib.showContext('bus_account_menu')
end

-- ═══════════════════════════════════════════════════════════════
--  TRAVEL SEQUENCE
-- ═══════════════════════════════════════════════════════════════

local function performTravel(destCoords, label, entity)
    local playerPed = PlayerPedId()

    waitAtBench(entity)

    local finished = lib.progressBar({
        duration = 5000,
        label = ('Waiting for the bus to %s...'):format(label),
        useWhileDead = false,
        canCancel = false,
        disable = { move = true, car = true, combat = true }
    })

    ClearPedTasks(playerPed)
    RemoveAnimDict('timetable@ron@ig_3_couch')

    if not finished then return end

    PlaySoundFrontend(-1, 'Hover', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    DoScreenFadeOut(600)
    Wait(650)

    SetEntityCoords(playerPed, destCoords.x, destCoords.y, destCoords.z, false, false, false, true)
    SetEntityHeading(playerPed, destCoords.w or GetEntityHeading(playerPed))

    Wait(400)
    DoScreenFadeIn(600)

    lib.notify({
        title = 'Bus Service',
        description = ('You arrived at %s.'):format(label),
        type = 'success',
        icon = 'bus'
    })
end

local function confirmTravel(loc, method, entity)
    local result = lib.callback.await('bus:server:travel', false, loc.name, method)
    if result and result.ok then
        performTravel(result.coords, result.label, entity)
    end
end

local function openPaymentMenu(loc, fare, wallet, entity)
    local options = {}

    if wallet.hasCard then
        local expiryText = Config.CardExpiryDays > 0
            and (' • Expires in %s'):format(formatExpiry(wallet.cardExpires))
            or ''

        options[#options + 1] = {
            title = ('Use Bus Card (Balance: $%d)'):format(wallet.cardBalance),
            description = ('Deducts $%d from your card balance.%s'):format(fare, expiryText),
            icon = 'fas fa-credit-card',
            disabled = wallet.cardBalance < fare,
            onSelect = function() confirmTravel(loc, 'card', entity) end
        }
    end

    if wallet.tickets > 0 then
        options[#options + 1] = {
            title = ('Use Bus Ticket (You have %d)'):format(wallet.tickets),
            description = 'Uses one pre-purchased ticket for this ride.',
            icon = 'fas fa-ticket-alt',
            onSelect = function() confirmTravel(loc, 'ticket', entity) end
        }
    end

    options[#options + 1] = {
        title = ('Pay Cash ($%d)'):format(fare),
        description = ('Cash on hand: $%d'):format(wallet.cash),
        icon = 'fas fa-money-bill-wave',
        disabled = wallet.cash < fare,
        onSelect = function() confirmTravel(loc, 'cash', entity) end
    }

    if Config.AllowBankPayments then
        options[#options + 1] = {
            title = ('Pay by Bank Card ($%d)'):format(fare),
            description = ('Bank balance: $%d'):format(wallet.bank),
            icon = 'fas fa-university',
            disabled = wallet.bank < fare,
            onSelect = function() confirmTravel(loc, 'bank', entity) end
        }
    end

    lib.registerContext({
        id = 'bus_payment_menu',
        title = ('Travel to %s'):format(loc.label),
        menu = 'bus_travel_menu',
        options = options
    })
    lib.showContext('bus_payment_menu')
end

local function openTravelMenu(entity)
    local playerCoords = GetEntityCoords(PlayerPedId())

    local wallet = lib.callback.await('bus:server:getWalletInfo', false)
    local fares = lib.callback.await('bus:server:getFareQuotes', false)

    if not wallet or not fares then return end

    local stops = {}
    for _, loc in ipairs(Config.Locations) do
        local dist = #(vector3(loc.coords.x, loc.coords.y, loc.coords.z) - playerCoords)
        if dist > 15.0 then
            stops[#stops + 1] = { loc = loc, dist = dist }
        end
    end

    if #stops == 0 then
        lib.notify({ title = 'Bus Service', description = 'There are no other stops from here.', type = 'error' })
        return
    end

    table.sort(stops, function(a, b) return a.dist < b.dist end)

    local options = {}
    for _, entry in ipairs(stops) do
        local loc = entry.loc
        local fare = fares[loc.name] or Config.Fare.Flat

        options[#options + 1] = {
            title = loc.label,
            description = ('%.1f km away  •  Fare: $%d'):format(entry.dist / 1000, fare),
            icon = 'fas fa-map-marker-alt',
            onSelect = function() openPaymentMenu(loc, fare, wallet, entity) end
        }
    end

    lib.registerContext({
        id = 'bus_travel_menu',
        title = 'Select Destination',
        menu = 'bus_main_menu',
        options = options
    })
    lib.showContext('bus_travel_menu')
end

-- ═══════════════════════════════════════════════════════════════
--  MAIN MENU (opened via qb-target)
-- ═══════════════════════════════════════════════════════════════

local function openManageMenu(entity)
    local wallet = lib.callback.await('bus:server:getWalletInfo', false)
    if not wallet then return end

    local options = {
        {
            title = 'Travel',
            description = 'Choose a destination to travel to.',
            icon = 'fas fa-bus',
            onSelect = function() openTravelMenu(entity) end
        },
        {
            title = ('Buy Bus Ticket ($%d)'):format(Config.TicketPrice),
            description = 'A single-use ticket valid for one ride.',
            icon = 'fas fa-ticket-alt',
            onSelect = function()
                choosePaymentAccount('Pay for Bus Ticket', 'bus_main_menu', function(account)
                    lib.callback.await('bus:server:buyTicket', false, account)
                end)
            end
        }
    }

    if not wallet.hasCard then
        options[#options + 1] = {
            title = ('Buy Bus Card ($%d)'):format(Config.CardPrice),
            description = ('Reusable card preloaded with $%d.'):format(Config.CardStartingBalance),
            icon = 'fas fa-credit-card',
            onSelect = function()
                choosePaymentAccount('Pay for Bus Card', 'bus_main_menu', function(account)
                    lib.callback.await('bus:server:buyCard', false, account)
                end)
            end
        }
    else
        options[#options + 1] = {
            title = ('Recharge Bus Card (+$%d for $%d)'):format(Config.CardTopUpAmount, Config.CardTopUpAmount),
            description = ('Current balance: $%d'):format(wallet.cardBalance),
            icon = 'fas fa-sync-alt',
            onSelect = function()
                choosePaymentAccount('Recharge Bus Card', 'bus_main_menu', function(account)
                    lib.callback.await('bus:server:rechargeCard', false, account)
                end)
            end
        }
    end

    lib.registerContext({
        id = 'bus_main_menu',
        title = 'Bus Stop',
        options = options
    })
    lib.showContext('bus_main_menu')
end

-- ═══════════════════════════════════════════════════════════════
--  QB-TARGET REGISTRATION
--  Applies to every instance of the configured bus stop props
--  anywhere in the game world.
-- ═══════════════════════════════════════════════════════════════

exports['qb-target']:AddTargetModel(busstopModels, {
    options = {
        {
            icon = 'fas fa-bus',
            label = 'Use Bus Stop',
            action = function(entity)
                openManageMenu(entity)
            end,
        }
    },
    distance = Config.TargetDistance
})
