local QBCore = exports['qb-core']:GetCoreObject()

-- ============================================================
-- STATE
-- ============================================================

local PlayerData = QBCore.Functions.GetPlayerData() or {}
local working    = false   -- mirrors the server's clocked-on state
local busy       = false   -- sewing / loading / pitching: one thing at a time
local startPed, workVan, vanBlip
local spawningVan = false  -- guards against double-clicking "Get Work Van"
local nextSellAt = 0
local soldPeds   = {}      -- pedestrians we've already pitched to
local heldPed              -- the pedestrian currently frozen in place for a pitch
local stockCount = 0       -- how many sellable goods the player is carrying
local stationProps, stationPoints = {}, {}
local supplySite, supplyBlip -- which supplier the server picked for us (index) and its map blip
local shopPeds = {}          -- [shopIndex] = delivery shop keeper ped

local SellableSet = {}
for _, r in ipairs(Config.Recipes) do SellableSet[r.item] = true end

local ShopCenter = vector3(Config.Shop.coords.x, Config.Shop.coords.y, Config.Shop.coords.z)

-- ============================================================
-- HELPERS
-- ============================================================

local function dbg(...)
    if Config.Debug then print('^3[qb-killerfashion]^0', ...) end
end

local function Notify(msg, nType)
    lib.notify({ title = 'KillerFashion Inc', description = msg, type = nType or 'inform' })
end

-- shows the level-up message (and the promotion bonus if one was paid)
local function LevelUpNotice(res)
    if not (res and res.levelUp) then return end
    local text = ('Level up! You are now a %s (sewing level %d).'):format(res.title or 'better seamstress', res.level or 0)
    if res.cash and res.cash > 0 then
        text = text .. ('\nPromotion bonus: $%d'):format(res.cash)
    end
    Notify(text, 'success')
end

local function V3(c)
    return vector3(c.x, c.y, c.z)
end

local function ItemLabel(name)
    local item = QBCore.Shared.Items[name]
    return item and item.label or name
end

local function InShopArea()
    return #(GetEntityCoords(PlayerPedId()) - ShopCenter) <= Config.Shop.radius
end

-- Counts the sellable goods in the player's inventory from the data qb-core
-- already syncs to the client. Cheap enough to run on every inventory change,
-- and it means the "sell" target never has to ask the server every frame.
local function RefreshStock()
    local total = 0
    local items = PlayerData and PlayerData.items
    if items then
        for _, it in pairs(items) do
            if it and SellableSet[it.name] then total = total + (it.amount or 0) end
        end
    end
    stockCount = total
end

local function CreateBlip(coords, sprite, colour, label)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.8)
    SetBlipColour(blip, colour)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label)
    EndTextCommandSetBlipName(blip)
    return blip
end

local function TakeControl(entity)
    local tries = 0
    while not NetworkHasControlOfEntity(entity) and tries < 20 do
        NetworkRequestControlOfEntity(entity)
        Wait(50)
        tries = tries + 1
    end
    return NetworkHasControlOfEntity(entity)
end

-- ============================================================
-- WORK VAN (client side)
-- ============================================================

local function RemoveVanBlip()
    if vanBlip and DoesBlipExist(vanBlip) then RemoveBlip(vanBlip) end
    vanBlip = nil
end

local function ClearVanClient()
    RemoveVanBlip()
    workVan = nil
end

-- The server picks one supplier at random for us. Only that one gets a blip
-- and only that one can be used.
local function SetSupplySite(idx)
    supplySite = idx
    if supplyBlip and DoesBlipExist(supplyBlip) then RemoveBlip(supplyBlip) end
    supplyBlip = nil

    local site = idx and Config.Supply.locations[idx]
    if site then
        supplyBlip = CreateBlip(site.door, 478, 5, 'Fabric Supplier')
        SetBlipAsShortRange(supplyBlip, false)
    end
end

RegisterNetEvent('killerfashion:client:supplySite', function(idx)
    SetSupplySite(idx)
end)

local function GiveVanKeysAndFuel(veh)
    SetVehicleFuelLevel(veh, 100.0)
    pcall(function() Entity(veh).state:set('fuel', 100.0, true) end)              -- ox_fuel & friends
    if GetResourceState('LegacyFuel') == 'started' then
        pcall(function() exports['LegacyFuel']:SetFuel(veh, 100) end)
    end
    if GetResourceState('cdn-fuel') == 'started' then
        pcall(function() exports['cdn-fuel']:SetFuel(veh, 100) end)
    end

    local plate = (GetVehicleNumberPlateText(veh) or ''):gsub('%s+$', '')
    TriggerEvent('vehiclekeys:client:SetOwner', plate)                            -- qb-vehiclekeys
end

-- Tell the server about our van. Right after CreateVehicle the server may not
-- know the entity yet, so keep trying until it confirms (or we give up).
local function RegisterWorkVan(veh)
    for _ = 1, 8 do
        if not veh or not DoesEntityExist(veh) then return false end
        if NetworkGetEntityIsNetworked(veh) then
            local netId = VehToNet(veh)
            if netId and netId ~= 0 then
                if lib.callback.await('killerfashion:registerVan', false, netId) then
                    return true
                end
            end
        end
        Wait(750)
    end
    return false
end

local function SpawnWorkVan()
    if spawningVan then return end
    spawningVan = true

    local res = lib.callback.await('killerfashion:requestVan', false)
    if not res or not res.ok then
        if res and res.msg then Notify(res.msg, 'error') end
        spawningVan = false
        return
    end

    -- Already have one out: just point to it
    SetSupplySite(res.site or supplySite)

    if res.action == 'locate' then
        SetNewWaypoint(res.coords.x + 0.0, res.coords.y + 0.0)
        Notify('Your work van is marked on the map.', 'inform')
        spawningVan = false
        return
    end

    local c = Config.Van.coords
    if IsAnyVehicleNearPoint(c.x, c.y, c.z, 3.0) then
        Notify('Something is blocking the van bay. Try again in a moment.', 'error')
        spawningVan = false
        return
    end

    lib.requestModel(Config.Van.model)
    local veh = CreateVehicle(Config.Van.model, c.x, c.y, c.z, c.w, true, false)
    SetModelAsNoLongerNeeded(Config.Van.model)

    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleOnGroundProperly(veh)
    SetVehicleNumberPlateText(veh, ('%s%03d'):format(Config.Van.plate, math.random(0, 999)))
    SetVehicleDoorsLocked(veh, 1)
    GiveVanKeysAndFuel(veh)

    workVan = veh
    CreateThread(function()
        if not RegisterWorkVan(veh) then
            Notify("Couldn't link your van to your job. Return it and get a new one.", 'error')
        end
    end)

    RemoveVanBlip()
    vanBlip = AddBlipForEntity(veh)
    SetBlipSprite(vanBlip, 477)
    SetBlipColour(vanBlip, 47)
    SetBlipScale(vanBlip, 0.8)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Work Van')
    EndTextCommandSetBlipName(vanBlip)

    if Config.Van.warpIn then
        TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
    end

    local site = Config.Supply.locations[supplySite or 0]
    if site then SetNewWaypoint(site.driveTo.x, site.driveTo.y) end
    Notify('Van ready. The fabric supplier is marked on your GPS.', 'success')
    spawningVan = false
end

RegisterNetEvent('killerfashion:client:vanRemoved', function()
    ClearVanClient()
end)

RegisterNetEvent('killerfashion:client:setDuty', function(state)
    working = state
    if not state then
        ClearVanClient()
        SetSupplySite(nil)
    end
end)

-- ============================================================
-- SEWING MENU
-- ============================================================

local function MaxCraftable(recipe, counts)
    local max = math.huge
    for _, ing in ipairs(recipe.ingredients) do
        max = math.min(max, math.floor((counts[ing[1]] or 0) / ing[2]))
    end
    return max == math.huge and 0 or max
end

local function AskQuantity(recipe, counts, maxBatch)
    local max = math.min(MaxCraftable(recipe, counts), maxBatch or Config.MaxBatch)
    if max <= 1 then return 1 end

    local input = lib.inputDialog(recipe.label, {
        { type = 'number', label = 'How many do you want to make?', default = 1, min = 1, max = max, required = true },
    })
    if not input or not input[1] then return nil end
    return math.floor(input[1])
end

local OpenSewingMenu -- forward declaration (StartCraft reopens the menu)

-- sewing machine sound (played by html/audio.html)
-- yours plays locally; the server tells players nearby so they hear it too
local remoteSews, remoteWatcher = {}, false   -- [serverId] = expires at (game timer)
local sewPlaying = false                      -- our own machine sound is running

-- each player can turn the sewing sound down (or off) for themselves: /sewvolume 0-100
local function SewVolumeMult()
    local v = tonumber(GetResourceKvpString('kf_sew_volume'))
    if not v then return 1.0 end
    return math.min(math.max(v, 0), 100) / 100
end

-- Safe to call once per item: the sound keeps running through a whole batch
-- instead of cutting out and restarting between items. Each call just tells
-- the server (and so nearby players) that the machine is still going.
local function StartSewSound()
    local cfg = Config.SewSound
    if not cfg or not cfg.enabled then return end
    if not sewPlaying then
        sewPlaying = true
        SendNUIMessage({ action = 'kfSewPlay', id = 'self', file = 'sounds/sewing.mp3', volume = (cfg.volume or 0.6) * SewVolumeMult() })
    end
    if cfg.hearNearby then TriggerServerEvent('killerfashion:server:sewSound', true) end
end

local function StopSewSound()
    local cfg = Config.SewSound
    if not cfg or not cfg.enabled or not sewPlaying then return end
    sewPlaying = false
    SendNUIMessage({ action = 'kfSewStop', id = 'self', fade = cfg.fadeMs or 250 })
    if cfg.hearNearby then TriggerServerEvent('killerfashion:server:sewSound', false) end
end

RegisterCommand('sewvolume', function(_, args)
    local cfg = Config.SewSound
    if not cfg or not cfg.enabled then return end
    local n = tonumber(args[1])
    if not n then
        Notify(('Sewing sound volume: %d%%. Use /sewvolume 0-100 to change it.'):format(math.floor(SewVolumeMult() * 100 + 0.5)), 'inform')
        return
    end
    n = math.floor(math.min(math.max(n, 0), 100))
    SetResourceKvp('kf_sew_volume', tostring(n))
    if sewPlaying then
        SendNUIMessage({ action = 'kfSewVolume', id = 'self', volume = (cfg.volume or 0.6) * n / 100 })
    end
    Notify(('Sewing sound volume set to %d%%.'):format(n), 'success')
end, false)

-- how loud another player's machine is for us (nil = out of earshot)
local function RemoteSewVolume(serverId)
    local cfg = Config.SewSound
    local pid = GetPlayerFromServerId(serverId)
    if pid == -1 then return nil end
    local ped = GetPlayerPed(pid)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local range = cfg.hearDistance or 15.0
    local dist  = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ped))
    if dist >= range then return nil end
    local f = 1.0 - (dist / range)
    return (cfg.nearbyVolume or 0.5) * f * f * SewVolumeMult()
end

local function StopRemoteSew(serverId)
    remoteSews[serverId] = nil
    SendNUIMessage({ action = 'kfSewStop', id = 'p' .. serverId, fade = (Config.SewSound and Config.SewSound.fadeMs) or 250 })
end

local function WatchRemoteSews()
    if remoteWatcher then return end
    remoteWatcher = true
    CreateThread(function()
        while next(remoteSews) do
            local now = GetGameTimer()
            for serverId, expires in pairs(remoteSews) do
                local vol = now < expires and RemoteSewVolume(serverId) or nil
                if vol then
                    SendNUIMessage({ action = 'kfSewVolume', id = 'p' .. serverId, volume = vol })
                else
                    StopRemoteSew(serverId)
                end
            end
            Wait(250)
        end
        remoteWatcher = false
    end)
end

RegisterNetEvent('killerfashion:client:sewSound', function(serverId, state, duration)
    local cfg = Config.SewSound
    if not cfg or not cfg.enabled or not cfg.hearNearby then return end
    if type(serverId) ~= 'number' or serverId == GetPlayerServerId(PlayerId()) then return end

    if not state then
        if remoteSews[serverId] then StopRemoteSew(serverId) end
        return
    end

    -- safety net: it always stops by itself even if the stop message never arrives
    local expires = GetGameTimer() + (tonumber(duration) or 15000) + 3000
    if remoteSews[serverId] then
        remoteSews[serverId] = expires   -- still sewing (next item in a batch): keep it going
        return
    end

    local vol = RemoteSewVolume(serverId)
    if not vol then return end
    remoteSews[serverId] = expires
    SendNUIMessage({ action = 'kfSewPlay', id = 'p' .. serverId, file = 'sounds/sewing.mp3', volume = vol })
    WatchRemoteSews()
end)

local function StartCraft(recipe, counts, categoryId, maxBatch)
    local qty = AskQuantity(recipe, counts, maxBatch)
    if not qty then return end

    busy = true
    KFProps.ClearHold()

    -- the item you're making appears in your hands while you sew
    -- (debug mode: tweak its placement first)
    local prop = Config.Props.showWhenCrafting and KFProps.ShowInHand(recipe.item, 'craft') or nil
    if prop and Config.Debug and Config.Props.editOnCraft then
        if KFProps.Edit(prop, recipe.item, 'craft') == 'cancel' then
            KFProps.Drop(prop)
            busy = false
            OpenSewingMenu(categoryId)
            return
        end
    end

    local made, stoppedByPlayer = 0, false

    for i = 1, qty do
        local begin = lib.callback.await('killerfashion:craftBegin', false, recipe.item)
        if not begin or not begin.ok then
            Notify(begin and begin.msg or 'Something went wrong.', 'error')
            break
        end

        if recipe.skill and Config.SkillCheck.enabled then
            local passed = lib.skillCheck(Config.SkillCheck.difficulty, Config.SkillCheck.inputs)
            if not passed then
                TriggerServerEvent('killerfashion:server:cancel')
                Notify('You botched the stitching. Nothing was used, try again.', 'error')
                break
            end
        end

        StartSewSound()
        local completed = lib.progressBar({
            duration = begin.time or recipe.time,
            label = qty > 1 and ('Sewing %s (%d/%d)'):format(recipe.label, i, qty) or ('Sewing %s...'):format(recipe.label),
            useWhileDead = false,
            canCancel = true,
            disable = { move = true, car = true, combat = true },
            anim = Config.CraftAnim,
        })
        -- keep the sound going into the next item of a batch (but not across a skill check)
        if not (completed and i < qty and not (recipe.skill and Config.SkillCheck.enabled)) then
            StopSewSound()
        end

        if not completed then
            TriggerServerEvent('killerfashion:server:cancel')
            Notify('You stopped sewing.', 'inform')
            stoppedByPlayer = true
            break
        end

        local fin = lib.callback.await('killerfashion:craftFinish', false, recipe.item)
        if not fin or not fin.ok then
            Notify(fin and fin.msg or 'Something went wrong.', 'error')
            break
        end

        made = made + (fin.bonus and 2 or 1)

        local lines = {}
        if fin.first then lines[#lines + 1] = ('First %s ever! +%d XP in total.'):format(recipe.label, fin.xp or 0) end
        if fin.bonus then lines[#lines + 1] = 'Lucky stitch! You made an extra piece.' end
        if fin.saved then lines[#lines + 1] = ('Efficient cutting: you saved a %s.'):format(fin.saved) end
        if #lines > 0 then Notify(table.concat(lines, '\n'), 'success') end
        LevelUpNotice(fin)
    end

    StopSewSound()
    KFProps.Drop(prop)
    busy = false

    if made > 0 then
        Notify(('Finished %dx %s.'):format(made, recipe.label), 'success')
    end
    if not stoppedByPlayer then
        OpenSewingMenu(categoryId)
    end
end

OpenSewingMenu = function(openCategory)
    if busy then return end

    local state = lib.callback.await('killerfashion:getState', false)
    if not state then
        Notify("Couldn't read your workshop data. Try again.", 'error')
        return
    end

    local counts, level = state.counts, state.level

    -- Header: level & XP progress
    local pct, xpText = 100, ('%d XP (max level)'):format(state.xp)
    if state.nextXp then
        pct = math.floor(((state.xp - state.levelXp) / (state.nextXp - state.levelXp)) * 100)
        xpText = ('%d / %d XP to level %d'):format(state.xp, state.nextXp, level + 1)
    end

    local mainOptions = {
        {
            title = ('%s - Level %d'):format(state.title or 'Sewer', level),
            description = xpText,
            icon = 'scissors',
            progress = pct,
            readOnly = true,
        },
    }

    if state.trend then
        mainOptions[#mainOptions + 1] = {
            title = ('Trending: %s'):format(state.trend),
            description = ('Pedestrians pay +%d%% for it right now.'):format(math.floor(Config.Sell.trendBonus * 100)),
            icon = 'fire',
            readOnly = true,
        }
    end

    for _, cat in ipairs(Config.Categories) do
        local options = {}

        for _, r in ipairs(Config.Recipes) do
            if r.category == cat.id then
                local locked   = level < r.level
                local maxCraft = MaxCraftable(r, counts)

                local meta = {}
                for _, ing in ipairs(r.ingredients) do
                    meta[#meta + 1] = { label = ItemLabel(ing[1]), value = ('%d / %d'):format(counts[ing[1]] or 0, ing[2]) }
                end
                meta[#meta + 1] = { label = 'Time', value = ('%ds'):format(math.floor(r.time * (1 - (state.speed or 0)) / 1000)) }
                meta[#meta + 1] = { label = 'XP', value = ('+%d'):format(r.xp) }
                if r.skill and Config.SkillCheck.enabled then
                    meta[#meta + 1] = { label = 'Needs', value = 'Steady hands (skill check)' }
                end

                local description
                if locked then
                    description = ('Locked - reach sewing level %d.'):format(r.level)
                elseif maxCraft < 1 then
                    description = 'Missing materials.'
                else
                    description = ('Sells for around $%d - $%d'):format(r.price.min, r.price.max)
                end

                options[#options + 1] = {
                    title = locked and ('%s (Lv %d)'):format(r.label, r.level) or r.label,
                    description = description,
                    icon = locked and 'lock' or r.icon,
                    metadata = meta,
                    disabled = locked or maxCraft < 1,
                    onSelect = function() StartCraft(r, counts, cat.id, state.maxBatch) end,
                }
            end
        end

        lib.registerContext({
            id = 'kf_cat_' .. cat.id,
            title = cat.label,
            menu = 'kf_sewing',
            options = options,
        })

        mainOptions[#mainOptions + 1] = {
            title = cat.label,
            description = cat.description,
            icon = cat.icon,
            menu = 'kf_cat_' .. cat.id,
            arrow = true,
        }
    end

    lib.registerContext({ id = 'kf_sewing', title = 'KillerFashion - Sewing Machine', options = mainOptions })
    lib.showContext(openCategory and ('kf_cat_' .. openCategory) or 'kf_sewing')
end

local function UseSewingMachine(entity)
    if busy then return end
    if entity and entity ~= 0 and DoesEntityExist(entity) then
        TaskTurnPedToFaceEntity(PlayerPedId(), entity, 600)
    end
    OpenSewingMenu()
end

-- ============================================================
-- SUPPLIES
-- ============================================================

local function CollectSupplies()
    if busy or not working then return end
    busy = true

    local begin = lib.callback.await('killerfashion:supplyBegin', false)
    if begin and not begin.ok and begin.code == 'novan' and workVan and DoesEntityExist(workVan) then
        if RegisterWorkVan(workVan) then
            begin = lib.callback.await('killerfashion:supplyBegin', false)
        end
    end
    if not begin or not begin.ok then
        Notify(begin and begin.msg or 'Something went wrong.', 'error')
        busy = false
        return
    end

    -- carry a crate while loading (the progress bar plays the carry pose)
    KFProps.ClearHold()
    local crate = Config.Props.supplyCrate and KFProps.ShowInHand('supply_crate', 'hold', { noAnim = true }) or nil

    local completed = lib.progressBar({
        duration = Config.Supply.duration,
        label = 'Loading supply crates...',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = crate and Config.Props.supplyAnim or Config.Supply.anim,
    })

    KFProps.Drop(crate)

    if not completed then
        TriggerServerEvent('killerfashion:server:cancel')
        Notify('You stopped loading.', 'inform')
        busy = false
        return
    end

    local fin = lib.callback.await('killerfashion:supplyFinish', false)
    busy = false
    if fin and fin.ok then
        Notify(fin.xp and fin.xp > 0 and ('%s (+%d XP)'):format(fin.msg, fin.xp) or fin.msg, 'success')
        LevelUpNotice(fin)
    else
        Notify(fin and fin.msg or 'Something went wrong.', 'error')
    end
end

-- ============================================================
-- SELLING: pedestrians
-- ============================================================

local function PickGoods(items)
    local p, done = promise.new(), false
    local function finish(value)
        if done then return end
        done = true
        p:resolve(value)
    end

    local options = {}
    for _, it in ipairs(items) do
        options[#options + 1] = {
            title = it.label .. (it.trending and '  (Trending)' or ''),
            description = ('Worth about $%d - $%d'):format(it.min, it.max),
            icon = it.icon,
            metadata = { { label = 'In stock', value = it.count } },
            onSelect = function() finish(it.item) end,
        }
    end

    lib.registerContext({
        id = 'kf_sell',
        title = 'What do you show them?',
        options = options,
        onExit = function() finish(nil) end,
    })
    lib.showContext('kf_sell')
    return Citizen.Await(p)
end

-- Lock a pedestrian in place, facing the player, for the whole pitch.
-- (TaskTurnPedToFaceEntity alone isn't enough: it ends as soon as they've
-- turned and their normal AI walks them off mid-pitch.)
local function HoldPed(ped, playerPed)
    heldPed = ped
    if not DoesEntityExist(ped) then return end
    TakeControl(ped)

    SetEntityAsMissionEntity(ped, true, true)     -- stop the engine despawning them mid-pitch
    SetBlockingOfNonTemporaryEvents(ped, true)    -- ignore traffic, gunshots, other peds...
    ClearPedTasksImmediately(ped)
    TaskTurnPedToFaceEntity(ped, playerPed, 1000)
    TaskLookAtEntity(ped, playerPed, Config.Sell.duration + 3000, 2048, 3)
    Wait(800)                                     -- let the turn finish

    if not DoesEntityExist(ped) then return end
    -- snap the heading exactly onto the player, then freeze
    local pc, mc = GetEntityCoords(ped), GetEntityCoords(playerPed)
    SetEntityHeading(ped, GetHeadingFromVector_2d(mc.x - pc.x, mc.y - pc.y))
    TaskStandStill(ped, Config.Sell.duration + 5000)
    FreezeEntityPosition(ped, true)
end

local function ReleasePed(ped)
    if heldPed == ped then heldPed = nil end
    if not ped or not DoesEntityExist(ped) then return end

    FreezeEntityPosition(ped, false)              -- always unfreeze, even if control was lost
    if NetworkHasControlOfEntity(ped) then
        SetBlockingOfNonTemporaryEvents(ped, false)
        ClearPedTasks(ped)
        TaskWanderStandard(ped, 10.0, 10)
        SetEntityAsMissionEntity(ped, false, false)
        SetPedAsNoLongerNeeded(ped)
    end
end

local function OfferGoods(ped)
    if busy or not working then return end
    if not ped or not DoesEntityExist(ped) or soldPeds[ped] then return end

    if GetGameTimer() < nextSellAt then
        Notify('Give it a moment before your next pitch.', 'error')
        return
    end

    busy = true

    local state = lib.callback.await('killerfashion:getSellState', false)
    if not state or #state.items < 1 then
        Notify("You don't have anything to sell.", 'error')
        busy = false
        return
    end

    -- The pedestrian turns to face you and stays put from the moment the menu
    -- opens until the sale is done. HoldPed runs in its own thread so the menu
    -- opens instantly; holdDone tells us when they've finished turning.
    local playerPed = PlayerPedId()
    KFProps.ClearHold()
    TaskTurnPedToFaceEntity(playerPed, ped, 800)
    PlayPedAmbientSpeechNative(ped, 'GENERIC_HI', 'SPEECH_PARAMS_STANDARD')

    local holdDone = false
    CreateThread(function()
        HoldPed(ped, playerPed)
        holdDone = true
    end)
    local function AwaitHold()
        while not holdDone do Wait(0) end
    end

    local choice = (#state.items == 1) and state.items[1].item or PickGoods(state.items)

    if not choice then
        AwaitHold()          -- never release before they've finished turning
        ReleasePed(ped)
        busy = false
        return
    end

    nextSellAt = GetGameTimer() + Config.Sell.cooldownMs
    AwaitHold()

    -- hold the item you picked out to them
    local prop = Config.Props.showWhenSelling and KFProps.ShowInHand(choice, 'sell') or nil

    -- DEBUG MODE: pause here so you can tweak the placement with the NPC frozen in front of you
    if prop and Config.Debug and Config.Props.editOnSell then
        if KFProps.Edit(prop, choice, 'sell') == 'cancel' then
            KFProps.Drop(prop)
            nextSellAt = 0
            ReleasePed(ped)
            busy = false
            return
        end
    end

    local finished = lib.progressBar({
        duration = Config.Sell.duration,
        label = 'Showing off your designs...',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = Config.Sell.anim,
    })

    if not finished then
        KFProps.Drop(prop)
        nextSellAt = 0
        ReleasePed(ped)
        busy = false
        return
    end

    soldPeds[ped] = true
    local res = lib.callback.await('killerfashion:sell', false, choice)

    if res and res.ok and res.sold then
        PlayPedAmbientSpeechNative(ped, 'GENERIC_THANKS', 'SPEECH_PARAMS_STANDARD')
        KFProps.GiveToPed(choice, ped)            -- the buyer walks off holding it
        Notify(res.xp and res.xp > 0 and ('Sold a %s for $%d (+%d XP).'):format(res.label, res.price, res.xp)
            or ('Sold a %s for $%d.'):format(res.label, res.price), 'success')
        LevelUpNotice(res)
    elseif res and res.ok then
        PlayPedAmbientSpeechNative(ped, 'GENERIC_BYE', 'SPEECH_PARAMS_STANDARD')
        Notify(res.msg or "They're not interested.", 'error')
    else
        Notify(res and res.msg or 'Something went wrong.', 'error')
    end

    KFProps.Drop(prop)
    Wait(Config.Sell.releaseDelayMs or 1500)      -- sale is done: they stay for a beat, then walk off
    ReleasePed(ped)
    busy = false
end

local function CanSellToPed(entity)
    if not working or busy or stockCount < 1 then return false end
    if entity == startPed or soldPeds[entity] then return false end
    if IsPedAPlayer(entity) or not IsPedHuman(entity) then return false end
    if IsPedDeadOrDying(entity, true) or IsPedInAnyVehicle(entity, false) then return false end
    if IsEntityPositionFrozen(entity) then return false end -- shopkeepers, other scripts' NPCs

    local pedType = GetPedType(entity)
    if pedType == 6 or pedType == 27 or pedType == 29 then return false end -- cops, SWAT, army

    local me = PlayerPedId()
    if IsPedInAnyVehicle(me, false) or IsEntityDead(me) then return false end
    if IsPedFleeing(entity) or IsPedInCombat(entity, me) then return false end

    return true
end

-- Forget pedestrians that no longer exist so the table can't grow forever
CreateThread(function()
    while true do
        Wait(60000)
        for ped in pairs(soldPeds) do
            if not DoesEntityExist(ped) then soldPeds[ped] = nil end
        end
    end
end)

-- ============================================================
-- SELLING: the manager (wholesale) & progress
-- ============================================================

local function SellToManager()
    if busy or not working then return end

    local state = lib.callback.await('killerfashion:getSellState', false)
    if not state or #state.items == 0 then
        Notify("You don't have any stock to sell.", 'error')
        return
    end

    local function sell(item, amount)
        local res = lib.callback.await('killerfashion:sellWholesale', false, item, amount)
        if res and res.ok then
            Notify(('Sold %dx %s to the manager for $%d.'):format(res.amount, res.label, res.total), 'success')
        else
            Notify(res and res.msg or 'Something went wrong.', 'error')
        end
    end

    local options = {}
    for _, it in ipairs(state.items) do
        options[#options + 1] = {
            title = it.label,
            description = ('Manager pays $%d each'):format(it.wholesale),
            icon = it.icon,
            metadata = { { label = 'In stock', value = it.count } },
            onSelect = function()
                local input = lib.inputDialog(it.label, {
                    { type = 'number', label = 'How many?', default = it.count, min = 1, max = it.count, required = true },
                })
                if input and input[1] then sell(it.item, input[1]) end
            end,
        }
    end

    options[#options + 1] = {
        title = 'Sell everything',
        description = 'Hand over all of your stock at wholesale price.',
        icon = 'sack-dollar',
        onSelect = function()
            for _, it in ipairs(state.items) do sell(it.item, it.count) end
        end,
    }

    lib.registerContext({ id = 'kf_wholesale', title = 'Sell Stock to the Manager', options = options })
    lib.showContext('kf_wholesale')
end

local function ShowProgress()
    local p = lib.callback.await('killerfashion:getProgress', false)
    if not p then return end

    local pct, xpText = 100, ('%d XP (max level)'):format(p.xp)
    if p.nextXp then
        pct = math.floor(((p.xp - p.levelXp) / (p.nextXp - p.levelXp)) * 100)
        xpText = ('%d / %d XP to level %d'):format(p.xp, p.nextXp, p.level + 1)
    end

    local options = {
        {
            title = ('%s - Level %d'):format(p.title or 'Sewer', p.level),
            description = xpText,
            icon = 'scissors',
            progress = pct,
            readOnly = true,
        },
        {
            title = 'Your record',
            description = ('Street prices +%d%% from your level'):format(p.sellBonusPct or 0),
            icon = 'chart-simple',
            readOnly = true,
            metadata = {
                { label = 'Pieces sewn', value = p.sewn },
                { label = 'Sold on the street', value = p.sold },
                { label = 'Customer orders done', value = p.orders },
                { label = 'Patterns tried', value = ('%d / %d'):format(p.patterns, #Config.Recipes) },
            },
        },
    }

    for _, perk in ipairs(p.perks) do
        options[#options + 1] = {
            title = perk.label,
            description = perk.text,
            icon = 'star',
            readOnly = true,
            metadata = { { label = 'Unlocked at', value = ('Level %d'):format(perk.level) } },
        }
    end
    if #p.perks == 0 then
        options[#options + 1] = { title = 'No perks yet', description = 'Your first one unlocks soon.', icon = 'lock', readOnly = true }
    end

    for _, perk in ipairs(p.upcoming) do
        options[#options + 1] = {
            title = ('Level %d: %s'):format(perk.level, perk.label),
            description = perk.text,
            icon = 'lock',
            readOnly = true,
        }
    end

    lib.registerContext({ id = 'kf_progress', title = 'Your Sewing Career', options = options })
    lib.showContext('kf_progress')
end

-- ============================================================
-- CUSTOMER ORDERS (rush orders board at the manager)
-- ============================================================

local function FmtTime(sec)
    return ('%d:%02d'):format(math.floor(sec / 60), sec % 60)
end

local OpenOrders

OpenOrders = function()
    if busy or not working then return end

    local state = lib.callback.await('killerfashion:getOrders', false)
    if not state or not state.ok then
        Notify(state and state.msg or 'The order board is closed.', 'error')
        return
    end

    if state.expired and state.expired > 0 then
        Notify(('%d order(s) ran out of time. Your streak was reset.'):format(state.expired), 'error')
    end

    local options = {}

    options[#options + 1] = {
        title = state.streak > 0 and ('Order streak: %d'):format(state.streak) or 'No streak yet',
        description = state.streakPct > 0
            and ('Orders currently pay +%d%% (streak and perks). Miss a deadline and the streak resets.'):format(state.streakPct)
            or 'Finish orders back to back for a payout bonus.',
        icon = 'fire',
        readOnly = true,
    }

    -- your accepted orders: pick one to deliver or drop it
    for _, o in ipairs(state.active) do
        local ctx = 'kf_order_' .. o.id
        lib.registerContext({
            id = ctx, title = ('%s%dx %s'):format(o.tag and ('[' .. o.tag .. '] ') or '', o.qty, o.label), menu = 'kf_orders',
            options = {
                {
                    title = ('Deliver to %s'):format(o.customer),
                    description = o.have >= o.qty
                        and ('Ready! Take it there in person for $%d + %d XP.'):format(o.pay, o.xp)
                        or ('Delivered in person. You still need %d more.'):format(o.qty - o.have),
                    icon = 'store',
                    readOnly = true,
                },
                {
                    title = 'Set GPS to the shop',
                    icon = 'location-dot',
                    onSelect = function()
                        local shop = Config.Orders.sites[o.shop]
                        if shop then
                            SetNewWaypoint(shop.coords.x, shop.coords.y)
                            Notify(('%s is marked on your GPS.'):format(shop.label), 'inform')
                        end
                        OpenOrders()
                    end,
                },
                {
                    title = 'Drop this order',
                    description = 'Gives the order up and resets your streak.',
                    icon = 'xmark',
                    onSelect = function()
                        local answer = lib.alertDialog({
                            header = 'Drop this order?',
                            content = ('%s will find someone else, and your streak goes back to 0.'):format(o.customer),
                            centered = true,
                            cancel = true,
                        })
                        if answer == 'confirm' then
                            lib.callback.await('killerfashion:orderCancel', false, o.id)
                            Notify('Order dropped.', 'inform')
                        end
                        OpenOrders()
                    end,
                },
            },
        })

        options[#options + 1] = {
            title = ('%s%dx %s - %s'):format(o.tag and ('[' .. o.tag .. '] ') or '', o.qty, o.label, o.customer),
            description = ('$%d + %d XP  |  %s left'):format(o.pay, o.xp, FmtTime(o.secondsLeft)),
            icon = o.icon,
            menu = ctx,
            progress = math.min(100, math.floor(o.have / o.qty * 100)),
            metadata = {
                { label = 'You have', value = ('%d / %d'):format(math.min(o.have, o.qty), o.qty) },
                { label = 'Deliver to', value = o.customer },
            },
        }
    end

    if #state.active == 0 then
        options[#options + 1] = { title = 'No active orders', description = 'Take one from the board below, then deliver it in person.', icon = 'clipboard', readOnly = true }
    end

    -- new orders on the board
    for _, o in ipairs(state.offers) do
        options[#options + 1] = {
            title = ('%s%s wants %dx %s'):format(o.tag and ('[' .. o.tag .. '] ') or '', o.customer, o.qty, o.label),
            description = ('Pays $%d + %d XP  |  %d min to finish'):format(o.pay, o.xp, o.minutes),
            metadata = { { label = 'Deliver to', value = o.customer } },
            icon = o.tagIcon or 'clipboard-list',
            disabled = #state.active >= state.maxActive,
            onSelect = function()
                local res = lib.callback.await('killerfashion:orderAccept', false, o.id)
                if res and res.ok then
                    Notify(('Order accepted: %dx %s for %s. Deliver it there in person within %d minutes. The shop is marked on your GPS.'):format(res.qty, res.label, res.customer, res.minutes), 'success')
                    local shop = res.shop and Config.Orders.sites[res.shop]
                    if shop then SetNewWaypoint(shop.coords.x, shop.coords.y) end
                else
                    Notify(res and res.msg or 'Something went wrong.', 'error')
                end
                OpenOrders()
            end,
        }
    end

    if #state.offers == 0 then
        options[#options + 1] = {
            title = 'The board is empty',
            description = ('New orders in about %d min.'):format(math.max(1, math.ceil(state.refreshIn / 60))),
            icon = 'hourglass-half',
            readOnly = true,
        }
    end

    lib.registerContext({ id = 'kf_orders', title = 'Customer Orders', options = options })
    lib.showContext('kf_orders')
end

-- ------------------------------------------------------------
-- IN-PERSON DELIVERY: hand the finished goods to the shop keeper
-- ------------------------------------------------------------

local OpenDeliveries

local function HandOver(order, shopIdx)
    busy = true
    KFProps.ClearHold()

    local site = Config.Orders.sites[shopIdx]
    local keeper = shopPeds[shopIdx]
    if keeper and DoesEntityExist(keeper) then
        TaskTurnPedToFaceEntity(PlayerPedId(), keeper, 600)
        Wait(400)
    end

    -- carry the goods over in a box, same pose as when loading supplies
    local crate = Config.Props.deliveryCrate and KFProps.ShowInHand('supply_crate', 'hold', { noAnim = true }) or nil

    local done = lib.progressBar({
        duration = (site and site.deliverDuration) or Config.Orders.deliverDuration or 2500,
        label = ('Handing over %dx %s...'):format(order.qty, order.label),
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = crate and Config.Props.supplyAnim or Config.Sell.anim,
    })

    KFProps.Drop(crate) -- the box leaves your hands
    if not done then
        busy = false
        Notify('You stopped the delivery.', 'inform')
        return false
    end

    local res = lib.callback.await('killerfashion:orderDeliver', false, order.id)
    busy = false
    if res and res.ok then
        -- ...and the shop keeper takes it
        if crate and keeper and DoesEntityExist(keeper) then
            KFProps.HandCrateToPed(keeper, function()
                if site and site.scenario and keeper and DoesEntityExist(keeper) then
                    TaskStartScenarioInPlace(keeper, site.scenario, 0, true)
                end
            end)
        end
        Notify(('%s paid $%d (+%d XP) for %dx %s. Streak: %d.'):format(res.customer, res.pay, res.xp, res.qty, res.label, res.streak), 'success')
        LevelUpNotice(res)
        return true
    end
    Notify(res and res.msg or 'Something went wrong.', 'error')
    return false
end

OpenDeliveries = function(shopIdx)
    if busy or not working then return end

    local state = lib.callback.await('killerfashion:getDeliveries', false, shopIdx)
    if not state or not state.ok then
        Notify(state and state.msg or 'Something went wrong.', 'error')
        return
    end

    if state.expired and state.expired > 0 then
        Notify(('%d order(s) ran out of time. Your streak was reset.'):format(state.expired), 'error')
    end

    if #state.orders == 0 then
        if state.elsewhere > 0 then
            Notify(("%s isn't expecting anything from you. Your other orders go to a different shop."):format(state.shopLabel), 'inform')
        else
            Notify(("%s isn't expecting anything from you. Pick up an order from the manager first."):format(state.shopLabel), 'inform')
        end
        return
    end

    local options = {}
    for _, o in ipairs(state.orders) do
        local ready = o.have >= o.qty
        options[#options + 1] = {
            title = ('%s%dx %s'):format(o.tag and ('[' .. o.tag .. '] ') or '', o.qty, o.label),
            description = ready
                and ('Pays $%d + %d XP  |  %s left'):format(o.pay, o.xp, FmtTime(o.secondsLeft))
                or ('You still need %d more.  |  %s left'):format(o.qty - o.have, FmtTime(o.secondsLeft)),
            icon = o.icon,
            disabled = not ready,
            progress = math.min(100, math.floor(o.have / o.qty * 100)),
            metadata = { { label = 'You have', value = ('%d / %d'):format(math.min(o.have, o.qty), o.qty) } },
            onSelect = function()
                HandOver(o, shopIdx)
                OpenDeliveries(shopIdx)
            end,
        }
    end

    lib.registerContext({ id = 'kf_deliveries', title = state.shopLabel .. ' - Deliveries', options = options })
    lib.showContext('kf_deliveries')
end

local function ShopPedOptions(shopIdx)
    return {
        {
            icon = 'fas fa-box-open', label = 'Deliver Order',
            canInteract = function() return working and not busy and Config.Orders and Config.Orders.enabled end,
            action = function() OpenDeliveries(shopIdx) end,
        },
    }
end

local function AddShopPedTarget(shopIdx)
    local ped = shopPeds[shopIdx]
    if ped and DoesEntityExist(ped) then
        exports['qb-target']:AddTargetEntity(ped, { options = ShopPedOptions(shopIdx), distance = 2.5 })
    end
end

local function SpawnShopPed(shopIdx)
    if shopPeds[shopIdx] and DoesEntityExist(shopPeds[shopIdx]) then return end

    local shop = Config.Orders.sites[shopIdx]
    lib.requestModel(shop.pedModel)

    local c = shop.coords
    local ped = CreatePed(4, shop.pedModel, c.x, c.y, c.z - 1.0, c.w, false, true)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityAsMissionEntity(ped, true, true)
    if shop.scenario then TaskStartScenarioInPlace(ped, shop.scenario, 0, true) end
    SetModelAsNoLongerNeeded(shop.pedModel)

    shopPeds[shopIdx] = ped
    AddShopPedTarget(shopIdx)
end

local function RemoveShopPed(shopIdx)
    local ped = shopPeds[shopIdx]
    if ped and DoesEntityExist(ped) then
        exports['qb-target']:RemoveTargetEntity(ped)
        DeleteEntity(ped)
    end
    shopPeds[shopIdx] = nil
end

-- Like the manager, each shop keeper only exists while you are nearby
if Config.Orders and Config.Orders.enabled then
    for i, shop in ipairs(Config.Orders.sites or {}) do
        lib.points.new({
            coords = V3(shop.coords),
            distance = 80.0,
            onEnter = function() SpawnShopPed(i) end,
            onExit = function() RemoveShopPed(i) end,
        })
    end
end

local function StartPedOptions()
    return {
        {
            icon = 'fas fa-sign-in-alt', label = 'Clock On',
            canInteract = function() return not working end,
            action = function() lib.callback.await('killerfashion:toggleDuty', false) end,
        },
        {
            icon = 'fas fa-sign-out-alt', label = 'Clock Off',
            canInteract = function() return working and not busy end,
            action = function() lib.callback.await('killerfashion:toggleDuty', false) end,
        },
        {
            icon = 'fas fa-truck', label = 'Get Work Van',
            canInteract = function() return working and not busy end,
            action = function() SpawnWorkVan() end,
        },
        {
            icon = 'fas fa-undo', label = 'Return Work Van',
            canInteract = function() return working and not busy end,
            action = function() lib.callback.await('killerfashion:returnVan', false) end,
        },
        {
            icon = 'fas fa-dollar-sign', label = 'Sell Stock to Manager',
            canInteract = function() return working and not busy and stockCount > 0 end,
            action = function() SellToManager() end,
        },
        {
            icon = 'fas fa-clipboard-list', label = 'Customer Orders',
            canInteract = function() return working and not busy and Config.Orders and Config.Orders.enabled end,
            action = function() OpenOrders() end,
        },
        {
            icon = 'fas fa-chart-line', label = 'Check My Progress',
            canInteract = function() return working end,
            action = function() ShowProgress() end,
        },
    }
end

local function AddStartPedTarget()
    if startPed and DoesEntityExist(startPed) then
        exports['qb-target']:AddTargetEntity(startPed, { options = StartPedOptions(), distance = 2.5 })
    end
end

local function SpawnStartPed()
    if startPed and DoesEntityExist(startPed) then return end

    local cfg = Config.StartJob
    lib.requestModel(cfg.pedModel)

    local c = cfg.coords
    startPed = CreatePed(4, cfg.pedModel, c.x, c.y, c.z - 1.0, c.w, false, true)
    SetEntityInvincible(startPed, true)
    FreezeEntityPosition(startPed, true)
    SetBlockingOfNonTemporaryEvents(startPed, true)
    SetEntityAsMissionEntity(startPed, true, true)
    if cfg.scenario then TaskStartScenarioInPlace(startPed, cfg.scenario, 0, true) end
    SetModelAsNoLongerNeeded(cfg.pedModel)

    AddStartPedTarget()
end

local function RemoveStartPed()
    if startPed and DoesEntityExist(startPed) then
        exports['qb-target']:RemoveTargetEntity(startPed)
        DeleteEntity(startPed)
    end
    startPed = nil
end

-- The ped only exists while you're near it, so it can never spawn under the map
lib.points.new({
    coords = V3(Config.StartJob.coords),
    distance = 80.0,
    onEnter = SpawnStartPed,
    onExit = RemoveStartPed,
})

-- Sewing machine target option (shared by prop models and fixed stations)
local function SewingOption(requireShopArea)
    return {
        icon = 'fas fa-cut',
        label = 'Use Sewing Machine',
        canInteract = function()
            if not working or busy then return false end
            return (not requireShopArea) or InShopArea()
        end,
        action = function(entity) UseSewingMachine(entity) end,
    }
end

local function RegisterTargets()
    -- Any sewing machine prop inside the shop
    exports['qb-target']:AddTargetModel(Config.SewingModels, {
        options = { SewingOption(true) },
        distance = 2.0,
    })

    -- Fabric supplier doors (only the one the server picked for you works)
    for i, site in ipairs(Config.Supply.locations) do
        local d, name = site.door, 'kf_supply_' .. i
        exports['qb-target']:AddBoxZone(name, V3(d), 1.6, 1.6, {
            name = name,
            heading = d.w,
            debugPoly = Config.Debug,
            minZ = d.z - 1.0,
            maxZ = d.z + 1.5,
        }, {
            options = {
                {
                    icon = 'fas fa-box-open',
                    label = (Config.Supply.cost or 0) > 0 and ('Collect Clothing Supplies ($%d)'):format(Config.Supply.cost) or 'Collect Clothing Supplies',
                    canInteract = function() return working and not busy and supplySite == i end,
                    action = function() CollectSupplies() end,
                },
            },
            distance = 2.0,
        })
    end

    -- Optional fixed sewing stations
    for i, station in ipairs(Config.SewingStations) do
        local name = 'kf_station_' .. i
        exports['qb-target']:AddBoxZone(name, V3(station.coords), 1.4, 1.4, {
            name = name,
            heading = station.coords.w,
            debugPoly = Config.Debug,
            minZ = station.coords.z - 1.0,
            maxZ = station.coords.z + 1.2,
        }, {
            options = { SewingOption(false) },
            distance = 2.0,
        })
    end

    -- Every pedestrian on the street
    exports['qb-target']:AddGlobalPed({
        options = {
            {
                icon = 'fas fa-tshirt',
                label = 'Offer Handmade Goods',
                canInteract = function(entity) return CanSellToPed(entity) end,
                action = function(entity) OfferGoods(entity) end,
            },
        },
        distance = Config.Sell.distance,
    })
end

local function UnregisterTargets()
    pcall(function()
        exports['qb-target']:RemoveTargetModel(Config.SewingModels, { 'Use Sewing Machine' })
        for i = 1, #Config.Supply.locations do
            exports['qb-target']:RemoveZone('kf_supply_' .. i)
        end
        for i = 1, #Config.SewingStations do
            exports['qb-target']:RemoveZone('kf_station_' .. i)
        end
        exports['qb-target']:RemoveGlobalPed({ 'Offer Handmade Goods' })
    end)
end

-- Optional placed sewing machine props (spawnProp = true), streamed by distance
for i, station in ipairs(Config.SewingStations) do
    if station.spawnProp then
        stationPoints[i] = lib.points.new({
            coords = V3(station.coords),
            distance = 60.0,
            onEnter = function()
                if stationProps[i] and DoesEntityExist(stationProps[i]) then return end
                lib.requestModel(Config.SewingProp)
                local obj = CreateObject(Config.SewingProp, station.coords.x, station.coords.y, station.coords.z, false, false, false)
                SetEntityHeading(obj, station.coords.w)
                FreezeEntityPosition(obj, true)
                SetModelAsNoLongerNeeded(Config.SewingProp)
                stationProps[i] = obj
            end,
            onExit = function()
                if stationProps[i] and DoesEntityExist(stationProps[i]) then DeleteEntity(stationProps[i]) end
                stationProps[i] = nil
            end,
        })
    end
end

-- Wait for qb-target, register, and re-register if it ever restarts
CreateThread(function()
    while GetResourceState('qb-target') ~= 'started' do Wait(200) end
    RegisterTargets()
    AddStartPedTarget()
    for i in pairs(shopPeds) do AddShopPedTarget(i) end
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= 'qb-target' then return end
    Wait(500)
    RegisterTargets()
    AddStartPedTarget()
    for i in pairs(shopPeds) do AddShopPedTarget(i) end
end)

-- ============================================================
-- BLIPS
-- ============================================================

CreateThread(function()
    CreateBlip(Config.StartJob.coords, 407, 2,  'KillerFashion Inc')
    CreateBlip(Config.VanBay,          477, 47, 'KillerFashion - Van Bay')

    -- the fabric supplier blip is created per player once the server picks one (see SetSupplySite)

    if Config.Orders and Config.Orders.enabled and Config.Orders.showShopBlips then
        for _, shop in ipairs(Config.Orders.sites or {}) do
            local b = shop.blip or {}
            CreateBlip(shop.coords, b.sprite or 73, b.colour or 3, shop.label .. ' (Deliveries)')
        end
    end
end)

-- ============================================================
-- PLAYER DATA
-- ============================================================

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
    RefreshStock()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    KFProps.ClearHold()
    PlayerData = {}
    working, busy, stockCount = false, false, 0
    ClearVanClient()
    SetSupplySite(nil)
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(val)
    PlayerData = val
    RefreshStock()
end)

-- The server fires this when you use a finished item from your inventory
RegisterNetEvent('killerfashion:client:useItem', function(item)
    if busy then
        Notify("Finish what you're doing first.", 'error')
        return
    end
    KFProps.ToggleHold(item)
end)

RefreshStock()

-- ============================================================
-- SETUP HELPER
-- ============================================================

-- /kfcoords copies your position as a vector4 so you can paste it into config.lua
RegisterCommand('kfcoords', function()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local text = ('vector4(%.2f, %.2f, %.2f, %.2f)'):format(c.x, c.y, c.z, GetEntityHeading(ped))
    lib.setClipboard(text)
    print(text)
    Notify('Copied to clipboard: ' .. text, 'success')
end, false)

-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    StopSewSound()
    UnregisterTargets()
    RemoveStartPed()
    for i in pairs(shopPeds) do RemoveShopPed(i) end
    RemoveVanBlip()
    SetSupplySite(nil)
    if heldPed then ReleasePed(heldPed) end

    for _, obj in pairs(stationProps) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
    if workVan and DoesEntityExist(workVan) then DeleteEntity(workVan) end
end)
