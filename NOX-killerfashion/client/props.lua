-- ============================================================
-- KillerFashion Inc - PROPS (client)
--
--   * Use a finished item from the inventory -> it appears in your hand
--   * Street pitch -> the item you picked is held out to the pedestrian
--   * After a sale the buyer walks off holding it for a few seconds
--   * Supply pickup -> you carry a crate while loading
--   * Order delivery -> you carry the crate to the shop keeper and hand it over
--   * DEBUG MODE: live placement editor (see /kfprop below)
--
-- main.lua uses the global KFProps table defined here.
-- ============================================================

KFProps = {}

local QBCore = exports['qb-core']:GetCoreObject()

local Tweaks  = {}     -- Tweaks[key] = { model = 'name', hold = pose, sell = pose } (editor changes, this session only)
local Live    = {}     -- every object this script created, so nothing is ever left behind
local held             -- handle of the item currently held from the inventory
local monitoring = false
local editing    = false

-- editor speeds
local POS_SPEED = 0.12  -- metres per second
local ROT_SPEED = 45.0  -- degrees per second

-- ============================================================
-- HELPERS
-- ============================================================

local function dbg(...)
    if Config.Debug then print('^3[qb-killerfashion:props]^0', ...) end
end

local function Notify(msg, nType)
    lib.notify({ title = 'KillerFashion Inc', description = msg, type = nType or 'inform' })
end

local function Enabled()
    return Config.Props and Config.Props.enabled and true or false
end

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local function SortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

local function BoneId(bone)
    if type(bone) == 'number' then return bone end
    return (Config.PropBones and Config.PropBones[bone]) or 28422
end

-- config pose ({ bone, pos = vector3, rot = vector3 }) -> flat editable pose
local function FlatPose(p)
    p = p or {}
    local pos = p.pos or vector3(0.0, 0.0, 0.0)
    local rot = p.rot or vector3(0.0, 0.0, 0.0)
    return {
        bone = p.bone or 'rhand',
        x = pos.x + 0.0, y = pos.y + 0.0, z = pos.z + 0.0,
        rx = rot.x + 0.0, ry = rot.y + 0.0, rz = rot.z + 0.0,
    }
end

-- The pose for an item in a context ('hold' or 'sell'), with any editor tweaks applied.
local function GetPose(key, ctx)
    local def = Config.PropItems and Config.PropItems[key]
    if not def then return nil end

    local tw = Tweaks[key]
    if tw and tw[ctx] then return copy(tw[ctx]) end
    if def[ctx] then return FlatPose(def[ctx]) end
    if tw and tw.hold then return copy(tw.hold) end
    return FlatPose(def.hold)
end

-- Model names to try for an item, best first (editor override, own models, fallbacks)
local function CandidateModels(key)
    local out, seen = {}, {}
    local function add(m)
        if m and not seen[m] then
            seen[m] = true
            out[#out + 1] = m
        end
    end
    local def = Config.PropItems and Config.PropItems[key]
    add(Tweaks[key] and Tweaks[key].model)
    for _, m in ipairs(def and def.models or {}) do add(m) end
    for _, m in ipairs(Config.Props.fallbackModels or {}) do add(m) end
    return out
end

local function ModelHash(m)
    return type(m) == 'number' and m or joaat(m)
end

local function ModelExists(m)
    local hash = ModelHash(m)
    return IsModelInCdimage(hash) and IsModelValid(hash)
end

local function ValidModels(key)
    local out = {}
    for _, m in ipairs(CandidateModels(key)) do
        if ModelExists(m) then out[#out + 1] = m end
    end
    return out
end

-- first candidate your game build actually has -> hash, name
local function ResolveModel(key)
    for _, m in ipairs(CandidateModels(key)) do
        if ModelExists(m) then return ModelHash(m), m end
    end
end

local function Attach(obj, ped, p)
    local bone = GetPedBoneIndex(ped, BoneId(p.bone))
    AttachEntityToEntity(obj, ped, bone, p.x, p.y, p.z, p.rx, p.ry, p.rz, true, true, false, true, 1, true)
end

-- localOnly = true makes a non-networked object (needed when the ped it attaches to is
-- a local ped, like the delivery shop keepers)
local function MakeObject(hash, ped, p, localOnly)
    local ok = pcall(lib.requestModel, hash, 3000)
    if not ok then return nil end

    local c = GetEntityCoords(ped)
    local obj = CreateObject(hash, c.x, c.y, c.z + 0.3, not localOnly, not localOnly, false)
    SetModelAsNoLongerNeeded(hash)
    if not obj or obj == 0 or not DoesEntityExist(obj) then return nil end

    SetEntityCollision(obj, false, false)
    SetEntityAsMissionEntity(obj, true, true)
    Attach(obj, ped, p)
    Live[obj] = true
    return obj
end

local function SpawnFor(key, ped, ctx, localOnly)
    local hash, name = ResolveModel(key)
    if not hash then
        dbg(('no valid model for "%s" (not even the fallbacks)'):format(key))
        return nil
    end
    local obj = MakeObject(hash, ped, GetPose(key, ctx), localOnly)
    if not obj then return nil end
    return obj, name
end

local function AnimFor(key, ctx)
    if key == 'supply_crate' then return Config.Props.supplyAnim or nil end
    if ctx == 'craft' then return Config.CraftAnim or nil end
    if ctx == 'sell' then return Config.Sell.anim or nil end
    local def = Config.PropItems and Config.PropItems[key]
    if def and def.holdAnim ~= nil then return def.holdAnim or nil end
    return Config.Props.holdAnim or nil
end

local function PlayAnim(ped, a)
    if not a then return false end
    if not pcall(lib.requestAnimDict, a.dict, 3000) then return false end
    TaskPlayAnim(ped, a.dict, a.clip, 3.0, 3.0, -1, a.flag or 49, 0.0, false, false, false)
    return true
end

local function StopAnim(ped, a)
    if a and DoesEntityExist(ped) and IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then
        StopAnimTask(ped, a.dict, a.clip, 3.0)
    end
end

local function HasItem(name)
    local data = QBCore.Functions.GetPlayerData()
    for _, it in pairs(data and data.items or {}) do
        if it and it.name == name and (it.amount or 0) > 0 then return true end
    end
    return false
end

-- ============================================================
-- PUBLIC API
-- ============================================================

-- Puts the prop for `key` in the player's hand. ctx = 'hold' | 'sell'.
-- Returns a handle you pass to Drop() / Edit(), or nil if props are off or no model loaded.
function KFProps.ShowInHand(key, ctx, opts)
    opts = opts or {}
    if not Enabled() or not Config.PropItems[key] then return nil end

    local ped = PlayerPedId()
    local obj, name = SpawnFor(key, ped, ctx or 'hold')
    if not obj then return nil end

    local handle = { key = key, ctx = ctx or 'hold', obj = obj, model = name, ped = ped }
    if not opts.noAnim then
        local anim = AnimFor(key, handle.ctx)
        if anim and PlayAnim(ped, anim) then handle.anim = anim end
    end
    return handle
end

-- Removes a prop (and stops the pose that came with it).
function KFProps.Drop(handle)
    if not handle then return end
    if handle.anim then StopAnim(handle.ped or PlayerPedId(), handle.anim) end
    if handle.obj then
        Live[handle.obj] = nil
        if DoesEntityExist(handle.obj) then DeleteEntity(handle.obj) end
        handle.obj = nil
    end
end

-- The buyer walks off with the item for a few seconds.
function KFProps.GiveToPed(key, ped)
    if not Enabled() or not Config.Props.giveToBuyer then return end
    if not ped or not DoesEntityExist(ped) or not Config.PropItems[key] then return end

    local obj = SpawnFor(key, ped, 'hold')
    if not obj then return end

    SetTimeout(Config.Props.buyerKeepMs or 12000, function()
        Live[obj] = nil
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end)
end

-- The delivery shop keeper takes the box: the crate appears in their hands with
-- the same carry pose for a few seconds, then disappears. onDone runs afterwards
-- (used to restart the keeper's idle scenario).
function KFProps.HandCrateToPed(ped, onDone)
    if not Enabled() or not Config.Props.deliveryCrate then return end
    if not ped or not DoesEntityExist(ped) then return end

    local obj = SpawnFor('supply_crate', ped, 'hold', true)
    if not obj then return end

    local anim = Config.Props.supplyAnim
    local played = anim and PlayAnim(ped, anim)

    SetTimeout(Config.Props.deliveryKeepMs or 6000, function()
        Live[obj] = nil
        if DoesEntityExist(obj) then DeleteEntity(obj) end
        if played and anim then StopAnim(ped, anim) end
        if onDone then onDone() end
    end)
end

-- ---------- held from the inventory ----------

function KFProps.ClearHold()
    if not held then return end
    local h = held
    held = nil
    KFProps.Drop(h)
end

local function StartMonitor()
    if monitoring then return end
    monitoring = true
    CreateThread(function()
        while held do
            Wait(400)
            if not held then break end
            local ped = PlayerPedId()
            if not held.obj or not DoesEntityExist(held.obj)
                or IsEntityDead(ped)
                or IsPedInAnyVehicle(ped, false)
                or not HasItem(held.key) then
                KFProps.ClearHold()
            end
        end
        monitoring = false
    end)
end

-- Called when the player uses the item from the inventory. Using it again puts it away.
function KFProps.ToggleHold(key)
    if not Enabled() or not Config.Props.useFromInventory then return end
    if editing or not Config.PropItems[key] or key == 'supply_crate' then return end

    if held and held.key == key then
        KFProps.ClearHold()
        Notify('You put it away.', 'inform')
        return
    end

    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then
        Notify("You can't hold that right now.", 'error')
        return
    end

    KFProps.ClearHold()
    local h = KFProps.ShowInHand(key, 'hold')
    if not h then
        Notify("Couldn't load a prop for this item.", 'error')
        return
    end
    held = h
    StartMonitor()
end

function KFProps.Cleanup()
    KFProps.ClearHold()
    for obj in pairs(Live) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
    Live = {}
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    KFProps.Cleanup()
end)

-- ============================================================
-- DEBUG: LIVE PLACEMENT EDITOR
-- ============================================================

local function PoseLine(ctx, p)
    local bone = type(p.bone) == 'string' and ("'%s'"):format(p.bone) or tostring(p.bone)
    return ('%s = pose(%s, %.3f, %.3f, %.3f, %.1f, %.1f, %.1f),'):format(ctx, bone, p.x, p.y, p.z, p.rx, p.ry, p.rz)
end

local function ExportSnippet(key, ctx, p, modelName, modelChanged)
    local lines = { ('-- %s  [%s]'):format(key, ctx) }
    if modelChanged and modelName then
        lines[#lines + 1] = ("-- model: '%s'  (put it FIRST in this item's models = { ... })"):format(modelName)
    end
    lines[#lines + 1] = PoseLine(ctx, p)
    local text = table.concat(lines, '\n')
    lib.setClipboard(text)
    print('^2[qb-killerfashion:props] copied to clipboard:^0\n' .. text)
    return text
end

local function DrawText2D(x, y, text, r, g, b)
    SetTextFont(4)
    SetTextScale(0.34, 0.34)
    SetTextColour(r or 255, g or 255, b or 255, 255)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function DrawEditorHud(key, ctx, p, model, mi, mcount, rotate, mult)
    DrawRect(0.165, 0.245, 0.31, 0.43, 0, 0, 0, 170)

    local applies = 'street pitch'
    if key == 'supply_crate' then applies = 'supply loading'
    elseif ctx == 'craft' then applies = 'sewing at the machine'
    elseif ctx == 'hold' then applies = 'inventory hold + buyer' end

    local x, y, dy = 0.022, 0.040, 0.0265
    local function line(text, r, g, b) DrawText2D(x, y, text, r, g, b); y = y + dy end

    line(('PROP EDITOR   %s  [%s]'):format(key, ctx), 255, 200, 60)
    line('applies to: ' .. applies, 180, 180, 180)
    line(('model: %s  (%d/%d)'):format(model or '?', mi, mcount))
    line(('bone:  %s'):format(tostring(p.bone)))
    line(('pos   X %.3f   Y %.3f   Z %.3f'):format(p.x, p.y, p.z), rotate and 160 or 120, rotate and 160 or 255, rotate and 160 or 120)
    line(('rot   X %.1f   Y %.1f   Z %.1f'):format(p.rx, p.ry, p.rz), rotate and 255 or 160, rotate and 170 or 160, rotate and 60 or 160)
    line(('mode: %s   speed x%.1f'):format(rotate and 'ROTATE (shift held)' or 'MOVE', mult))
    y = y + 0.008
    line('Arrows = X / Y      PgUp,PgDn or E,Q = Z', 220, 220, 220)
    line('Hold SHIFT = rotate instead of move', 220, 220, 220)
    line('CTRL = fine     ALT = coarse', 220, 220, 220)
    line('G = next bone    H = next model    Z = reset', 220, 220, 220)
    line('ENTER = keep + copy to clipboard', 120, 255, 120)
    line('BACKSPACE = undo changes and cancel', 255, 120, 120)
end

local function SwapModel(handle, name, p)
    if not ModelExists(name) then return false end
    local obj = MakeObject(ModelHash(name), handle.ped or PlayerPedId(), p)
    if not obj then return false end

    Live[handle.obj] = nil
    if DoesEntityExist(handle.obj) then DeleteEntity(handle.obj) end
    handle.obj, handle.model = obj, name
    return true
end

-- Blocks until you press ENTER ('save') or BACKSPACE ('cancel').
-- `handle` is what ShowInHand returned; ctx is 'hold', 'sell' or 'craft'.
function KFProps.Edit(handle, key, ctx)
    if editing then return 'cancel' end
    if not handle or not handle.obj or not DoesEntityExist(handle.obj) then return 'cancel' end

    local ped = handle.ped or PlayerPedId()
    local cur = GetPose(key, ctx)
    if not cur then return 'cancel' end

    local orig = copy(cur)
    local modelChanged = false

    local models = ValidModels(key)
    local mi = 1
    for i, m in ipairs(models) do
        if m == handle.model then mi = i end
    end

    local boneList = Config.PropBoneCycle or {}
    local bi = 0
    for i, b in ipairs(boneList) do
        if b == cur.bone then bi = i end
    end

    editing = true
    Wait(250) -- swallow the click / ENTER that opened the editor

    local result = 'cancel'
    local dirty = true

    while true do
        Wait(0)

        DisableAllControlActions(0)
        EnableControlAction(0, 1, true) -- look left/right
        EnableControlAction(0, 2, true) -- look up/down

        local dt = GetFrameTime()
        local mult = 1.0
        if IsDisabledControlPressed(0, 36) then mult = 0.2         -- CTRL = fine
        elseif IsDisabledControlPressed(0, 19) then mult = 4.0 end -- ALT  = coarse
        local rotate = IsDisabledControlPressed(0, 21)             -- SHIFT

        local ax = (IsDisabledControlPressed(0, 175) and 1 or 0) - (IsDisabledControlPressed(0, 174) and 1 or 0)
        local ay = (IsDisabledControlPressed(0, 172) and 1 or 0) - (IsDisabledControlPressed(0, 173) and 1 or 0)
        local up   = IsDisabledControlPressed(0, 10) or IsDisabledControlPressed(0, 38)
        local down = IsDisabledControlPressed(0, 11) or IsDisabledControlPressed(0, 44)
        local az = (up and 1 or 0) - (down and 1 or 0)

        if ax ~= 0 or ay ~= 0 or az ~= 0 then
            if rotate then
                local d = ROT_SPEED * mult * dt
                cur.rx = cur.rx + ax * d
                cur.ry = cur.ry + ay * d
                cur.rz = cur.rz + az * d
            else
                local d = POS_SPEED * mult * dt
                cur.x = cur.x + ax * d
                cur.y = cur.y + ay * d
                cur.z = cur.z + az * d
            end
            dirty = true
        end

        if IsDisabledControlJustPressed(0, 47) and #boneList > 0 then -- G
            bi = bi % #boneList + 1
            cur.bone = boneList[bi]
            dirty = true
        end

        if IsDisabledControlJustPressed(0, 74) and #models > 1 then -- H
            mi = mi % #models + 1
            if SwapModel(handle, models[mi], cur) then modelChanged = true end
            dirty = false
        end

        if IsDisabledControlJustPressed(0, 20) then -- Z = back to the config default
            local def = Config.PropItems[key]
            cur = FlatPose(def[ctx] or def.hold)
            dirty = true
        end

        if dirty and handle.obj and DoesEntityExist(handle.obj) then
            Attach(handle.obj, ped, cur)
            dirty = false
        end

        DrawEditorHud(key, ctx, cur, handle.model, mi, #models, rotate, mult)

        if IsDisabledControlJustPressed(0, 191) then result = 'save'; break end   -- ENTER
        if IsDisabledControlJustPressed(0, 177) then result = 'cancel'; break end -- BACKSPACE
        if not handle.obj or not DoesEntityExist(handle.obj) or IsEntityDead(ped) then
            result = 'cancel'
            break
        end
    end

    editing = false

    if result == 'save' then
        Tweaks[key] = Tweaks[key] or {}
        Tweaks[key][ctx] = copy(cur)
        if modelChanged then Tweaks[key].model = handle.model end
        ExportSnippet(key, ctx, cur, handle.model, modelChanged)
        Notify(('Saved for this session and copied to your clipboard. Paste it into Config.PropItems.%s'):format(key), 'success')
    else
        -- undo: Tweaks[key].model is only written on save, so this resolves the original model
        if modelChanged then
            local _, name = ResolveModel(key)
            if name then SwapModel(handle, name, orig) end
        end
        if handle.obj and DoesEntityExist(handle.obj) then Attach(handle.obj, ped, orig) end
    end

    return result
end

-- ============================================================
-- DEBUG COMMANDS (only exist when Config.Debug = true)
-- ============================================================

if Config.Debug then
    local function ItemList()
        return table.concat(SortedKeys(Config.PropItems), ', ')
    end

    -- /kfprop <item> [hold|sell|craft] [model]
    RegisterCommand('kfprop', function(_, args)
        if editing then return end
        local key = args[1]
        local ctx = args[2] or 'hold'
        if not key or not Config.PropItems[key] then
            Notify('Usage: /kfprop <item> [hold|sell|craft] [model]. Items: ' .. ItemList(), 'error')
            return
        end
        if ctx ~= 'hold' and ctx ~= 'sell' and ctx ~= 'craft' then
            Notify("Context must be 'hold', 'sell' or 'craft'.", 'error')
            return
        end

        if args[3] then
            if not ModelExists(args[3]) then
                Notify(("Model '%s' doesn't exist in your game build."):format(args[3]), 'error')
                return
            end
            Tweaks[key] = Tweaks[key] or {}
            Tweaks[key].model = args[3]
        end

        KFProps.ClearHold()
        local handle = KFProps.ShowInHand(key, ctx)
        if not handle then
            Notify("Couldn't spawn a prop for that item. Run /kfpropcheck.", 'error')
            return
        end

        KFProps.Edit(handle, key, ctx)
        KFProps.Drop(handle)
    end, false)

    -- /kfpropcheck : which model each item actually resolved to on this game build
    RegisterCommand('kfpropcheck', function()
        local bad, fallback = 0, 0
        print('^3[qb-killerfashion:props] model check^0')
        for _, key in ipairs(SortedKeys(Config.PropItems)) do
            local def = Config.PropItems[key]
            local _, name = ResolveModel(key)
            if not name then
                bad = bad + 1
                print(('  ^1[NONE]^0     %s  -> no valid model at all'):format(key))
            else
                local own = false
                for _, m in ipairs(def.models or {}) do
                    if m == name then own = true end
                end
                if own then
                    print(('  ^2[ok]^0       %s  -> %s'):format(key, name))
                else
                    fallback = fallback + 1
                    print(('  ^3[fallback]^0 %s  -> %s  (none of its own models exist; try /kfprop %s hold <model>)'):format(key, name, key))
                end
            end
        end
        Notify(('Prop check done: %d missing, %d using a fallback. See F8.'):format(bad, fallback), bad > 0 and 'error' or 'inform')
    end, false)

    -- /kfpropdump : every placement you changed this session, ready to paste
    RegisterCommand('kfpropdump', function()
        local out = {}
        for _, key in ipairs(SortedKeys(Tweaks)) do
            local tw = Tweaks[key]
            out[#out + 1] = ('-- %s'):format(key)
            if tw.model then
                out[#out + 1] = ("-- model: '%s'  (put it FIRST in models = { ... })"):format(tw.model)
            end
            if tw.hold then out[#out + 1] = PoseLine('hold', tw.hold) end
            if tw.sell then out[#out + 1] = PoseLine('sell', tw.sell) end
            if tw.craft then out[#out + 1] = PoseLine('craft', tw.craft) end
            out[#out + 1] = ''
        end
        if #out == 0 then
            Notify("You haven't changed any placements this session.", 'inform')
            return
        end
        local text = table.concat(out, '\n')
        lib.setClipboard(text)
        print('^2[qb-killerfashion:props] all tweaks (copied to clipboard):^0\n' .. text)
        Notify('All your tweaks were copied to the clipboard (and printed in F8).', 'success')
    end, false)

    -- /kfpropreset [item] : drop this session's tweaks and go back to config.lua
    RegisterCommand('kfpropreset', function(_, args)
        if args[1] then
            Tweaks[args[1]] = nil
            Notify(('Tweaks for %s cleared.'):format(args[1]), 'success')
        else
            Tweaks = {}
            Notify('All tweaks cleared.', 'success')
        end
    end, false)

    CreateThread(function()
        Wait(1500)
        TriggerEvent('chat:addSuggestion', '/kfprop', 'KillerFashion: live prop placement editor', {
            { name = 'item', help = ItemList() },
            { name = 'context', help = 'hold (inventory/buyer), sell (street pitch) or craft (sewing)' },
            { name = 'model', help = 'optional: try any prop model name' },
        })
        TriggerEvent('chat:addSuggestion', '/kfpropcheck', 'KillerFashion: show which prop model each item resolved to')
        TriggerEvent('chat:addSuggestion', '/kfpropdump', 'KillerFashion: copy all your placement tweaks')
        TriggerEvent('chat:addSuggestion', '/kfpropreset', 'KillerFashion: clear placement tweaks', { { name = 'item', help = 'optional' } })
    end)
end

-- Works in any mode: drop the item you're holding
RegisterCommand('kfputaway', function()
    if held then
        KFProps.ClearHold()
        Notify('You put it away.', 'inform')
    end
end, false)
