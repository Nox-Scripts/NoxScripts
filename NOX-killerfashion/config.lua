Config = {}

-- Prints extra info to the F8 / server console and draws qb-target zone outlines.
Config.Debug = false

-- Leave false to let anyone work here (they just clock on at the start ped).
-- Set to a QBCore job name (e.g. 'tailor') to only let that job clock on.
Config.RequiredJob = false

-- Newer qb-inventory versions already pop up the "+ item" box by themselves.
-- If you never see item pop-ups when items are added/removed, set this to true.
Config.ManualItemBox = false

-- ============================================================
-- LOCATIONS
-- Tip: stand where you want something and type /kfcoords in-game.
-- It copies a ready-to-paste vector4 to your clipboard.
-- ============================================================

-- The manager ped. Target him to clock on/off, get the van, sell stock in bulk
-- and check your sewing level.
Config.StartJob = {
    coords   = vector4(708.69, -966.75, 30.4, 269.71),
    pedModel = `mp_m_waremech_01`,
    scenario = 'WORLD_HUMAN_CLIPBOARD', -- set to false for no idle animation
}

-- Work van (spawns here when you ask the manager for it)
Config.Van = {
    coords  = vector4(717.2, -988.05, 24.14, 276.13),
    model   = `moonbeam`,      -- speedo, boxville3, burrito3, etc. also work
    warpIn  = true,            -- put the player straight into the driver seat
    plate   = 'KFASH',         -- plate prefix, 3 random digits get added
}

-- Blip only: shows where the van bay is on the map
Config.VanBay = vector4(713.65, -977.72, 24.12, 179.97)

-- Fabric suppliers
-- Every time you clock on the server randomly picks ONE of these for you and you
-- keep it for the whole shift (clock off and on again to get a new random one).
-- Only that one is marked on your map / GPS and only that one lets you collect
-- supplies. Add as many as you like.
Config.Supply = {
    locations = {
        {
            driveTo = vector4(-129.99, -1776.72, 29.82, 147.62), -- GPS is set here after you get the van
            door    = vector4(-128.09, -1779.45, 29.82, 232.1),  -- the target zone you use to collect supplies
        },
        {
            driveTo = vector4(462.85, -693.89, 27.4, 88.05),
            door    = vector4(462.85, -693.89, 27.4, 88.05),
        },
    },

    cost    = 500,                -- what every supply pickup costs (0 = free)
    payFrom = { 'cash', 'bank' }, -- tried in this order; the first one that can cover the full price is used

    requireVan  = true,   -- work van must be parked near the door to load supplies
    vanRadius   = 40.0,
    cooldownSec = 30,    -- minimum time between supply pickups per player
    duration    = 6000,   -- ms to load the crates

    -- What one supply pickup gives (random amount between min and max of each)
    loot = {
        { item = 'fabric',      min = 14, max = 18 },
        { item = 'kf_thread',   min = 8,  max = 10 },
        { item = 'kf_buttons',  min = 6,  max = 8  },
        { item = 'kf_zipper',   min = 4,  max = 6  },
        { item = 'kf_denim',    min = 4,  max = 6  },
        { item = 'kf_leather',  min = 3,  max = 5  },
    },

    anim = { dict = 'random@domestic', clip = 'pickup_low', flag = 1 },
}

-- ============================================================
-- SEWING MACHINES
-- ============================================================

-- The shop area. Sewing is only allowed inside this radius (checked on the
-- server too), so nobody can sew from the other side of the map.
Config.Shop = {
    coords = Config.StartJob.coords,
    radius = 45.0,
}

-- Any prop with one of these models inside the shop area becomes a usable
-- sewing machine automatically - no coordinates needed. If your MLO uses a
-- different sewing machine prop, add its model here.
Config.SewingModels = {
    `prop_sewing_machine`,
    `m24_2_prop_m42_sewing_machine`,
}

-- OPTIONAL: fixed sewing stations at exact coordinates. Use these if your
-- machines are not one of the models above, or if you want the script to place
-- a machine for you (spawnProp = true).
-- Example:
--   { coords = vector4(710.5, -960.2, 30.4, 90.0), spawnProp = false },
Config.SewingStations = {
}
Config.SewingProp = `prop_sewing_machine` -- only used when a station has spawnProp = true

-- Animation played while sewing (ox_lib progress bar)
Config.CraftAnim = {
    dict = 'mini@repair',
    clip = 'fixing_a_ped',
    flag = 1
}

-- Sewing machine sound, plays while the sewing progress bar runs and stops
-- when it finishes or you cancel. Players nearby hear it too (hearNearby).
-- volume: 0.0 - 1.0
Config.SewSound = {
    enabled       = true,
    volume        = 0.6,    -- what you hear from your own machine (0.0 - 1.0)
    fadeMs        = 250,    -- fade-out time when it stops
    hearNearby    = true,   -- other players close to the machine hear it too
    hearDistance  = 15.0,   -- metres; it fades out smoothly with distance
    nearbyVolume  = 0.5,    -- how loud it is for someone standing right next to you
}

-- Max items you can queue in one go from the sewing menu
Config.MaxBatch = 10

-- Recipes marked skill = true make you pass a quick ox_lib skill check first.
-- Failing wastes your time but costs no materials.
Config.SkillCheck = {
    enabled    = true,
    difficulty = { 'easy', 'medium' },
    inputs     = { 'e' },
}

-- ============================================================
-- PROGRESSION
-- ============================================================

-- XP needed for each level (index = level). Stored in the player's metadata,
-- no database changes needed. 20 levels; add or remove numbers to change the cap
-- (and add a matching title below).
Config.Levels = {
    0, 25, 70, 140, 240, 370, 530, 720, 950, 1220,          -- levels 1 - 10
    1530, 1880, 2270, 2700, 3170, 3680, 4230, 4820, 5450, 6120, -- levels 11 - 20
}

Config.LevelTitles = {
    'Trainee', 'Stitcher', 'Seamstress', 'Tailor', 'Pattern Cutter',
    'Designer', 'Couturier', 'Head Designer', 'Master Tailor', 'Fashion Icon',
    'Runway Regular', 'Trendsetter', 'Atelier Owner', 'House Designer', 'Creative Director',
    'Fashion Mogul', 'Haute Couture', 'Legend of the Loom', 'Living Legend', 'KillerFashion Legend',
}

-- Extra ways to earn XP (sewing gives the recipe's own xp, orders give their bonus xp)
Config.XP = {
    sale        = 2,    -- XP for every street sale
    supply      = 3,    -- XP for every supply run
    firstCraft  = 15,   -- one-time bonus the first time you ever sew each pattern
    levelUpCash = 50,   -- promotion bonus paid in cash on level-up: this x the new level (0 = off)
}

-- PERKS: unlocked by level, permanent, and they stack up as tiers.
-- Each line is { level needed, value }; you get the highest tier you qualify for.
-- Remove a whole line (or a tier) to disable it.
Config.Perks = {
    speed      = { { 3, 0.05 }, { 7, 0.10 }, { 11, 0.15 }, { 15, 0.20 }, { 20, 0.25 } }, -- sewing is X% faster
    saver      = { { 5, 0.05 }, { 9, 0.08 }, { 13, 0.12 }, { 17, 0.16 } },               -- chance a piece uses one less material
    yield      = { { 8, 0.05 }, { 12, 0.08 }, { 16, 0.12 }, { 20, 0.15 } },              -- chance of a free extra piece
    batch      = { { 6, 15 }, { 12, 20 }, { 18, 30 } },                                   -- biggest batch you can queue (base is Config.MaxBatch)
    orderSlots = { { 9, 1 }, { 16, 2 } },                                                 -- extra customer orders you can hold at once
    orderPay   = { { 10, 0.05 }, { 14, 0.10 }, { 18, 0.15 } },                           -- customer orders pay X% more
}

-- ============================================================
-- RECIPES
-- ingredients = { { 'item_name', amount }, ... }
-- level = sewing level needed, time = ms per item, xp = XP per item
-- price = street sale range (before level/trend bonuses)
-- ============================================================

Config.Categories = {
    { id = 'clothing',    label = 'Clothing',           icon = 'shirt',        description = 'Everyday wear and outerwear' },
    { id = 'accessories', label = 'Bags & Accessories', icon = 'bag-shopping', description = 'Beach bags and designer purses' },
}

Config.Recipes = {
    -- CLOTHING ---------------------------------------------------------
    {
        item = 'kf_tshirt', label = 'T-Shirt', category = 'clothing', icon = 'shirt',
        level = 1, time = 7000, xp = 4,
        ingredients = { { 'fabric', 2 }, { 'kf_thread', 1 } },
        price = { min = 500, max = 600 },
    },
    {
        item = 'kf_cap', label = 'Baseball Cap', category = 'clothing', icon = 'hat-cowboy',
        level = 1, time = 7000, xp = 4,
        ingredients = { { 'fabric', 1 }, { 'kf_thread', 1 }, { 'kf_buttons', 1 } },
        price = { min = 280, max = 380 },
    },
    {
        item = 'kf_jeans', label = 'Jeans', category = 'clothing', icon = 'shirt',
        level = 2, time = 9000, xp = 8,
        ingredients = { { 'kf_denim', 2 }, { 'kf_thread', 1 }, { 'kf_buttons', 1 }, { 'kf_zipper', 1 } },
        price = { min = 780, max = 980 },
    },
    {
        item = 'kf_hoodie', label = 'Zip Hoodie', category = 'clothing', icon = 'shirt',
        level = 3, time = 10000, xp = 10,
        ingredients = { { 'fabric', 4 }, { 'kf_thread', 2 }, { 'kf_zipper', 1 } },
        price = { min = 720, max = 930 },
    },
    {
        item = 'kf_dress', label = 'Sundress', category = 'clothing', icon = 'person-dress',
        level = 4, time = 11000, xp = 12,
        ingredients = { { 'fabric', 4 }, { 'kf_thread', 2 }, { 'kf_buttons', 2 } },
        price = { min = 900, max = 1400 },
    },
    {
        item = 'kf_denimjacket', label = 'Denim Jacket', category = 'clothing', icon = 'shirt',
        level = 6, time = 13000, xp = 16, skill = true,
        ingredients = { { 'kf_denim', 3 }, { 'kf_thread', 2 }, { 'kf_buttons', 3 } },
        price = { min = 720, max = 920 },
    },
    {
        item = 'kf_leatherjacket', label = 'Leather Jacket', category = 'clothing', icon = 'shirt',
        level = 8, time = 15000, xp = 22, skill = true,
        ingredients = { { 'kf_leather', 3 }, { 'fabric', 2 }, { 'kf_thread', 2 }, { 'kf_zipper', 1 } },
        price = { min = 700, max = 1000 },
    },

    -- BAGS & ACCESSORIES (the original KillerFashion products) ---------
    {
        item = 'beachbag04', label = 'Beach Bag - Style A', category = 'accessories', icon = 'bag-shopping',
        level = 1, time = 8000, xp = 6,
        ingredients = { { 'fabric', 3 }, { 'kf_thread', 1 } },
        price = { min = 420, max = 840 },
    },
    {
        item = 'beachbag02', label = 'Beach Bag - Style B', category = 'accessories', icon = 'bag-shopping',
        level = 2, time = 8000, xp = 6,
        ingredients = { { 'fabric', 3 }, { 'kf_thread', 1 } },
        price = { min = 740, max = 960 },
    },
    {
        item = 'beachbag06', label = 'Beach Bag - Style C', category = 'accessories', icon = 'bag-shopping',
        level = 3, time = 8000, xp = 6,
        ingredients = { { 'fabric', 3 }, { 'kf_thread', 1 } },
        price = { min = 1000, max = 1500 },
    },
    {
        item = 'ldpurse01', label = 'Designer Purse', category = 'accessories', icon = 'bag-shopping',
        level = 5, time = 12000, xp = 14, skill = true,
        ingredients = { { 'kf_leather', 1 }, { 'fabric', 1 }, { 'kf_thread', 1 }, { 'kf_zipper', 1 } },
        price = { min = 1500, max = 2000 },
    },
}

-- ============================================================
-- SELLING
-- ============================================================

Config.Sell = {
    chance        = 75,     -- % chance a pedestrian agrees to buy
    cooldownMs    = 8000,   -- minimum time between pitches (enforced on the server)
    distance      = 2.5,    -- qb-target distance to a pedestrian
    duration      = 3500,   -- ms of "showing off your designs"
    anim          = { dict = 'mp_common', clip = 'givetake1_a', flag = 49 }, -- pose while pitching (props follow your hand)
    releaseDelayMs = 1500,  -- the pedestrian stays put this long after the sale, then walks off

    levelBonus    = 0.02,   -- +2% sale price per sewing level above 1...
    levelBonusCap = 0.20,   -- ...up to +20%

    trendMinutes  = 20,     -- every X minutes one product becomes "trending"
    trendBonus    = 0.25,   -- trending products sell for +25% on the street
}

-- ============================================================
-- CUSTOMER ORDERS (rush orders)
-- The manager keeps a board of orders from local shops. Accept one, sew what
-- it asks for, then deliver it in person to that shop before the deadline:
-- guaranteed money well above street price, bonus XP, and a streak bonus for
-- finishing orders back to back.
-- Orders are per player, only last while you're clocked on, and only ask for
-- patterns you have already unlocked.
-- ============================================================

Config.Orders = {
    enabled        = true,
    offers         = 3,       -- orders on your board at a time
    maxActive      = 2,       -- orders you can hold at once
    refreshMinutes = 15,      -- your board reshuffles every X minutes

    baseMinutes    = 12,      -- deadline = baseMinutes + minutesPerItem * quantity
    minutesPerItem = 2,

    bonusMin       = 1.20,    -- an order pays 120% - 150% of the average street price
    bonusMax       = 1.50,    -- (before level and streak bonuses)
    xpBonus        = 0.5,     -- bonus XP = 50% of the XP the sewing itself gave

    streakBonus    = 0.05,    -- +5% payout for every order in a row...
    streakCap      = 0.25,    -- ...up to +25%. Missing a deadline or cancelling resets it.

    -- how many pieces an order asks for, by average street price of the item
    qty = {
        { upTo = 250,       min = 3, max = 8 },
        { upTo = 500,       min = 2, max = 5 },
        { upTo = math.huge, min = 1, max = 3 },
    },

    -- Orders are delivered IN PERSON. Each order sends you to one of these shops
    -- (decided by your sewing level when the order is generated) and you hand the
    -- goods to the shop keeper standing there. The shop name is the customer.
    -- minLevel = lowest sewing level that gets sent to this shop (you get the
    -- highest shop you qualify for). Add or remove shops freely, keep at least one.
    deliveryShops = {
        {
            label    = 'Textile Row Discount',   -- poor clothing shop
            minLevel = 1,                        -- low levels
            coords   = vector4(451.92, -802.97, 27.57, 265.84),
            pedModel = `s_f_y_shop_low`,
            scenario = false,                    -- idle animation, e.g. 'WORLD_HUMAN_STAND_IMPATIENT' (false = none)
        },
        {
            label    = 'Del Perro Threads',      -- middle class clothing shop
            minLevel = 7,                        -- medium levels
            coords   = vector4(-1326.55, -268.27, 41.66, 129.26),
            pedModel = `s_f_y_shop_mid`,
            scenario = false,
        },
        {
            label    = 'Velvet Lane Boutique',   -- high end clothing shop
            minLevel = 14,                       -- high levels
            coords   = vector4(-706.81, -170.95, 36.92, 121.13),
            pedModel = `s_f_m_shop_high`,
            scenario = false,
        },
    },

    showShopBlips = true,     -- show the delivery shops on the map
    deliverDuration = 2500,   -- ms of handing the goods over

    -- BULK ORDERS: much bigger orders that show up on the same board as the
    -- normal ones (in addition to them). Each tier unlocks at its own level, is
    -- delivered in person to one of its sites (picked at random when the order is
    -- generated) and has its own size, pay and deadline.
    --   qtyMult  = the normal order size for that item is multiplied by a random
    --              number between these two (so cheap items ask for more pieces)
    --   offers   = how many of this tier are on your board at a time
    --   bonusMin/bonusMax = pays this x the average street price (normal orders: 1.20 - 1.50)
    --   deadline = baseMinutes + minutesPerItem * quantity
    bulk = {
        enabled = true,
        tiers = {
            {
                id = 'supermarket', tag = 'Bulk', icon = 'cart-shopping',
                minLevel = 8, offers = 1,
                qtyMult = { 5, 8 },
                bonusMin = 1.25, bonusMax = 1.50, xpBonus = 0.5,
                baseMinutes = 20, minutesPerItem = 2,
                deliverDuration = 5000,
                sites = {
                    {
                        label    = 'Sandy Shores Supermarket',
                        coords   = vector4(1955.9, 3853.13, 33.61, 289.65),
                        pedModel = `mp_m_shopkeep_01`,
                        scenario = false,
                        blip     = { sprite = 52, colour = 2 },
                    },
                    {
                        label    = 'Hawick Supermarket',
                        coords   = vector4(132.42, 269.97, 109.97, 347.23),
                        pedModel = `mp_m_shopkeep_01`,
                        scenario = false,
                        blip     = { sprite = 52, colour = 2 },
                    },
                },
            },
            {
                -- the biggest order in the game: a whole shipment for a cargo ship
                id = 'ship', tag = 'Cargo', icon = 'ship',
                minLevel = 15, offers = 1,
                qtyMult = { 12, 18 },
                bonusMin = 1.40, bonusMax = 1.80, xpBonus = 0.5,
                baseMinutes = 30, minutesPerItem = 2,
                deliverDuration = 8000,
                sites = {
                    {
                        label    = 'Elysian Island Cargo Ship',
                        coords   = vector4(1014.24, -2898.23, 11.97, 91.73),
                        pedModel = `s_m_y_dockwork_01`,
                        scenario = false,
                        blip     = { sprite = 455, colour = 5 }, -- change the icon here if it looks off on your build
                    },
                },
            },
        },
    },
}

-- ------------------------------------------------------------
-- DO NOT EDIT: flattens the normal delivery shops and every bulk site into one
-- list. An order remembers its destination as an index into this list (the
-- normal shops always come first, so their numbers never change).
-- ------------------------------------------------------------
Config.Orders.sites = {}
Config.Orders.bulkSites = {} -- [tier number] = { site index, ... }
do
    local function add(site, tier)
        site.deliverDuration = site.deliverDuration or (tier and tier.deliverDuration) or Config.Orders.deliverDuration
        Config.Orders.sites[#Config.Orders.sites + 1] = site
        return #Config.Orders.sites
    end
    for _, shop in ipairs(Config.Orders.deliveryShops) do add(shop) end
    for t, tier in ipairs(Config.Orders.bulk.tiers) do
        Config.Orders.bulkSites[t] = {}
        for _, site in ipairs(tier.sites) do
            local idx = add(site, tier)
            Config.Orders.bulkSites[t][#Config.Orders.bulkSites[t] + 1] = idx
        end
    end
end

-- The manager buys stock in bulk at a fixed, lower price. Reliable money when
-- pedestrians aren't cooperating.
Config.Wholesale = {
    multiplier = 0.55,      -- % of the average street price he pays per item
}

-- ============================================================
-- PROPS
-- Clothes and bags show up in your hand. Every position below is a starting
-- point: turn on Config.Debug and use the live editor (see the README) to
-- line each one up, then paste the line it gives you back in here.
-- ============================================================

Config.Props = {
    enabled          = true,

    useFromInventory = true,   -- use a finished item from your inventory -> it appears in your hand (use it again to put it away)
    showWhenSelling  = true,   -- the item you pick is held out to the pedestrian during the pitch
    giveToBuyer      = true,   -- after a sale the buyer walks off holding it...
    buyerKeepMs      = 12000,  -- ...for this long, then it disappears
    supplyCrate      = true,   -- carry a crate while loading supplies at the fabric supplier
    deliveryCrate    = true,   -- carry the goods over in a box when delivering an order, and the shop keeper takes it
    deliveryKeepMs   = 6000,   -- ...the shop keeper holds the box this long, then it disappears
    showWhenCrafting = true,   -- the item you're sewing appears in your hands while you work at the machine

    -- DEBUG MODE ONLY: pause every street pitch in the placement editor so you
    -- can nudge the prop while the pedestrian is frozen in front of you.
    editOnSell       = true,
    editOnCraft      = true,   -- same, once at the start of each sewing batch (placement is the 'craft' pose)

    -- Pose while holding an item from the inventory. false = no animation
    -- (arm just hangs, good for bags). Any item can override with holdAnim = false / { ... }
    -- CONFIDENCE: medium. If it looks odd, swap for any upper-body (flag 49) clip you like.
    holdAnim   = { dict = 'cellphone@', clip = 'cellphone_text_read_base', flag = 49 },

    -- Pose while carrying the supply crate. CONFIDENCE: medium-high.
    supplyAnim = { dict = 'anim@heists@box_carry@', clip = 'idle', flag = 49 },

    -- Tried in order if none of an item's own models exist in your game build,
    -- so you always get *a* prop instead of nothing.
    fallbackModels = { 'prop_cs_box_clothes', 'prop_paper_bag_01' },
}

-- Bone names you can use in a pose (or use a raw bone id number).
Config.PropBones = {
    rhand     = 28422,  -- PH_R_Hand  (the "hold something" bone, best default)
    lhand     = 60309,  -- PH_L_Hand
    rforearm  = 28252,
    lforearm  = 61163,
    rshoulder = 10706,  -- clavicle
    lshoulder = 64729,
    chest     = 24818,  -- spine 3
    back      = 24816,  -- spine 2
    head      = 31086,
}
-- Order the editor cycles through when you press G
Config.PropBoneCycle = { 'rhand', 'lhand', 'rforearm', 'lforearm', 'chest', 'back', 'rshoulder', 'lshoulder', 'head' }

-- pose(bone, x, y, z, rotX, rotY, rotZ): where the prop sits relative to the bone.
local function pose(bone, x, y, z, rx, ry, rz)
    return { bone = bone, pos = vector3(x, y, z), rot = vector3(rx, ry, rz) }
end

-- One entry per item (same names as your recipes) plus 'supply_crate'.
--   models = tried in order, first one your game has wins. NOTE: these names are
--            from memory and not verified - in debug mode run /kfpropcheck to see
--            which ones your build accepts, and /kfprop <item> hold|sell <model>
--            to try any other model live.
--   hold   = pose when held from the inventory (and what the buyer carries off)
--   sell   = pose during the street pitch (optional - falls back to hold)
--   craft  = pose while sewing at the machine (optional - falls back to hold)
Config.PropItems = {
    -- CLOTHING (models: medium confidence) -------------------------------
    kf_tshirt        = { models = { 'prop_cs_shirt_01', 'prop_ld_shirt_01' },                       hold = pose('rhand', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) },
    kf_cap           = { models = { 'prop_ld_hat_01' },                                              hold = pose('rhand', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) },
    kf_jeans         = { models = { 'prop_ld_jeans_01', 'prop_ld_jeans_02' },                        hold = pose('rhand', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) },
    kf_hoodie        = { models = { 'prop_ld_shirt_01', 'prop_cs_shirt_01' },                        hold = pose('rhand', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) },
    kf_dress         = { models = { 'prop_cs_shirt_01', 'prop_ld_shirt_01' },                        hold = pose('rhand', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) },
    kf_denimjacket   = { models = { 'prop_ld_jacket_01', 'prop_ld_shirt_01', 'prop_cs_shirt_01' },  hold = pose('rhand', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) },
    kf_leatherjacket = { models = { 'prop_ld_jacket_01', 'prop_ld_shirt_01', 'prop_cs_shirt_01' },  hold = pose('rhand', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) },

    -- BAGS (models: medium-high confidence; carried at your side, no hold pose) --
    beachbag04       = { models = { 'prop_beachbag_04' }, holdAnim = false, hold = pose('rhand', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) },
    beachbag02       = { models = { 'prop_beachbag_02' }, holdAnim = false, hold = pose('rhand', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) },
    beachbag06       = { models = { 'prop_beachbag_06' }, holdAnim = false, hold = pose('rhand', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) },
    ldpurse01        = { models = { 'prop_ld_purse_01', 'prop_ld_handbag' }, holdAnim = false, hold = pose('rhand', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) },

    -- SUPPLIES ------------------------------------------------------------
    -- The default crate pose is the classic two-handed box carry (offsets are tuned for
    -- hei_prop_heist_box, so it's listed first). CONFIDENCE: medium - if the box sits
    -- off, line it up with /kfprop supply_crate hold.
    supply_crate     = { models = { 'hei_prop_heist_box', 'prop_cs_cardbox_01', 'prop_cs_box_clothes' }, hold = pose('lhand', 0.025, 0.08, 0.255, -145.0, 290.0, 0.0) },
}

