-- ================================================================
--  DX3_Fov — server/main.lua  (Ultimate Edition v3.0)
-- ================================================================

local QBCore = exports['qb-core']:GetCoreObject()

-- ============================================================
-- DB MIGRATION  (MySQL 8.4 compatible)
-- ============================================================
CreateThread(function()
    Wait(1000)
    local result = exports.oxmysql:executeSync([[
        SELECT COUNT(*) as count FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'players'
        AND COLUMN_NAME = 'esMiope'
    ]])

    if result and result[1] and result[1].count == 0 then
        exports.oxmysql:execute([[
            ALTER TABLE players
            ADD COLUMN esMiope TINYINT(1) NOT NULL DEFAULT 0
        ]], {}, function()
            print("[DX3_Fov] DB ready — 'esMiope' column added.")
        end)
    else
        print("[DX3_Fov] DB ready — 'esMiope' column already exists.")
    end
end)

-- ============================================================
-- PLAYER LOAD
-- ============================================================
RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local src    = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    exports.oxmysql:execute(
        'SELECT esMiope FROM players WHERE citizenid = ?',
        { Player.PlayerData.citizenid },
        function(result)
            local miope = result and result[1] and result[1].esMiope == 1 or false
            Player.Functions.SetMetaData("esMiope", miope)
            TriggerClientEvent('fzt_fov:setMiopia', src, miope)
        end
    )
end)

-- ============================================================
-- /setmiopia [0|1]  — toggle own myopia (admin)
-- ============================================================
QBCore.Commands.Add("setmiopia", "Toggle your myopia state (admin)", {
    { name = "state", help = "1 = myopic | 0 = normal" }
}, false, function(source, args)
    if not QBCore.Functions.HasPermission(source, "admin") then
        TriggerClientEvent("QBCore:Notify", source, "No permission.", "error")
        return
    end

    local Player  = QBCore.Functions.GetPlayer(source)
    if not Player then return end

    local miope = tonumber(args[1]) == 1
    Player.Functions.SetMetaData("esMiope", miope)

    exports.oxmysql:execute(
        'UPDATE players SET esMiope = ? WHERE citizenid = ?',
        { miope and 1 or 0, Player.PlayerData.citizenid }
    )

    TriggerClientEvent('fzt_fov:setMiopia', source, miope)
    TriggerClientEvent("QBCore:Notify", source,
        "Myopia " .. (miope and "enabled ✅" or "disabled ❌"), "success")
end)

-- ============================================================
-- /setmiopiatarget [id] [0|1]  — toggle another player's myopia (admin)
-- ============================================================
QBCore.Commands.Add("setmiopiatarget", "Toggle a player's myopia (admin)", {
    { name = "id",    help = "Target server ID" },
    { name = "state", help = "1 = myopic | 0 = normal" }
}, false, function(source, args)
    if not QBCore.Functions.HasPermission(source, "admin") then
        TriggerClientEvent("QBCore:Notify", source, "No permission.", "error")
        return
    end

    local Target = QBCore.Functions.GetPlayer(tonumber(args[1]))
    if not Target then
        TriggerClientEvent("QBCore:Notify", source, "Player not found.", "error")
        return
    end

    local miope = tonumber(args[2]) == 1
    Target.Functions.SetMetaData("esMiope", miope)

    exports.oxmysql:execute(
        'UPDATE players SET esMiope = ? WHERE citizenid = ?',
        { miope and 1 or 0, Target.PlayerData.citizenid }
    )

    TriggerClientEvent('fzt_fov:setMiopia', Target.PlayerData.source, miope)
    TriggerClientEvent("QBCore:Notify", source,
        "Player " .. args[1] .. " myopia " .. (miope and "enabled ✅" or "disabled ❌"), "success")
end)

-- ============================================================
-- Glasses update from radial menu / wardrobe
-- ============================================================
RegisterNetEvent("fzt_fov:updateGlasses", function(drawable, texture)
    local src    = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local props = Player.PlayerData.metadata["props"] or {}
    props["glasses"] = { drawable = drawable, texture = texture }
    Player.Functions.SetMetaData("props", props)

    local wearing = drawable ~= 0 and drawable ~= -1
    TriggerClientEvent("fzt_fov:setGlassesState", src, wearing)
end)
