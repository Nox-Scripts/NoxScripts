Config = {}

-- ============================================================
-- GENERAL
-- ============================================================
Config.RequiredJob        = false -- set to a job name string (e.g. 'unemployed') to lock this job, or false for anyone
Config.PayPerCar          = 100    -- cash paid per successful car extraction
Config.PayAccount         = 'cash' -- 'cash' or 'bank'
Config.ExtractDuration    = 8000  -- ms the extract progress bar takes
Config.MaxUsesPerWreck    = 3     -- extractions allowed from one wreck before it's picked clean
Config.RespawnMinutes     = 1    -- minutes before a picked-clean wreck resets and can be extracted again
Config.TargetDistance     = 2.5   -- qb-target interact distance
Config.ExtractAnim        = { dict = 'amb@world_human_welding@male@base', clip = 'base', flag = 1 } -- cutting saw / grinder pose
Config.ExtractProp        = { model = 'prop_weld_torch', bone = 28422, pos = vector3(0.0, 0.0, 0.0), rot = vector3(0.0, 0.0, 0.0) } -- SKEL_R_HAND

-- ============================================================
-- JOB ZONE
-- These props already exist on the map (Rockstar's junkyard set dressing),
-- so nothing gets spawned. Targeting works on any matching prop on the
-- WHOLE map, so JobRadius fences it to your scrapyard only - anything
-- outside this radius of StartCoords is rejected server-side.
-- ============================================================
Config.StartCoords = vector4(2390.65, 3126.65, 48.15, 0.0) -- tune heading with /scrapcoords
Config.JobRadius = 99.0 -- meters from StartCoords that targeting is allowed in

Config.NPCModel = 's_m_y_construct_02'
Config.NPCScenario = 'WORLD_HUMAN_HAMMERING'
Config.RequireShiftToExtract = true -- must Start Shift at the NPC before extracting pays out

Config.Blip = {
    sprite = 566,
    color = 47,
    scale = 0.8,
    label = 'Scrapyard'
}

-- ============================================================
-- CAR WRECK PROPS (main extraction points - $20 + random scrap item)
-- Targets any existing prop on the map using these models.
-- ============================================================
Config.WreckModels = {
    'prop_rub_carwreck_8',
    'prop_rub_carwreck_9',
    'prop_rub_carwreck_2',
    'prop_rub_carwreck_3',
    'prop_rub_carwreck_5',
    'prop_rub_carwreck_7',
    'prop_rub_carwreck_17',
    'prop_rub_carwreck_13',
    'prop_rub_carwreck_15',
    'prop_rub_carwreck_11',
    'prop_rub_carwreck_16',
    'prop_rub_carwreck_14',
    'prop_rub_carwreck_10',
    'prop_rub_carwreck_12',
    'sp1_03_carwreck_01',
    'sp1_03_carwreck_02',
    'sp1_03_carwreck_03',
    'sp1_03_carwreck_04',
    'sp1_03_carwreck_05',
    'sp1_03_carwreck_06',
    'sp1_03_carwreck_07',
    'sp1_03_carwreck_08',
}

-- ============================================================
-- TIRE PILES (bonus points - rubber only, no cash payout)
-- ============================================================
Config.TireModels = {
    'xs_propint3_waste_02_tires',
    'xs_propint4_waste_07_tires',
    'xs_propint3_waste_05_tires',
    'xs_propint4_waste_10_tires',
    'xs_propint3_waste_03_tires',
    'xs_propint3_waste_04_tires',
    'prop_rub_pile_01',
    'prop_rub_pile_04',
    'prop_rub_pile_02',
    'prop_rub_pile_03',
}

Config.TireExtractDuration = 5000
Config.TireLootMin = 1
Config.TireLootMax = 3
Config.MaxUsesPerTire = 5

-- ============================================================
-- LOOT TABLE (car wrecks only)
-- weight = relative chance, higher = more common. min/max = amount given.
-- Items must exist in your QBShared.Items list.
-- ============================================================
Config.LootTable = {
    { item = 'metalscrap',    min = 1, max = 2, weight = 30 },
    { item = 'plastic',       min = 1, max = 2, weight = 20 },
    { item = 'glass',         min = 1, max = 2, weight = 15 },
    { item = 'rubber',        min = 1, max = 1, weight = 15 },
    { item = 'copper',        min = 1, max = 1, weight = 8 },
    { item = 'iron',          min = 1, max = 1, weight = 6 },
    { item = 'aluminum',      min = 1, max = 1, weight = 6 },
    { item = 'steel',         min = 1, max = 1, weight = 5 },
    { item = 'carradio',      min = 1, max = 1, weight = 4 },
    { item = 'ironoxide',     min = 1, max = 1, weight = 3 },
    { item = 'aluminumoxide', min = 1, max = 1, weight = 3 },
    { item = 'veh_engine',    min = 1, max = 1, weight = 1 }, -- rare jackpot
}
