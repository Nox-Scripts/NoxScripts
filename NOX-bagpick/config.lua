Config = {}

-- =============================================================================
-- General
-- =============================================================================

-- true = prints the framework detected by bridge/shared.lua to console
Config.Debug = false
Config.Locale = 'en'

-- 'auto' = automatic detection (ESX, QBox, QBCore) ; otherwise force 'esx' | 'qbox' | 'qbcore'
Config.Framework = 'auto'

-- =============================================================================
-- Keybinds
-- NOTE: if you change one of these, the icon shown in the on-screen prompt
-- (the ~INPUT_...~ tag in locales/en.lua and locales/fr.lua) is tied to the
-- specific control ID's name, not to this config. Update the matching
-- ~INPUT_...~ tag in the locale file too, or the icon shown won't match the
-- key that actually works.
-- =============================================================================

Config.Keys = {
    Steal  = 113, -- G  (INPUT_VEH_FLY_UNDERCARRIAGE) - attempt to steal the NPC's bag
    Pickup = 38,  -- E  (INPUT_CONTEXT)                - pick up a bag lying on the ground
    Search = 47,  -- G  (INPUT_DETONATE)               - search the bag you're holding, or one on the ground
    Drop   = 73,  -- X  (INPUT_VEH_DUCK)               - drop the bag you're holding
}

-- =============================================================================
-- Police
-- =============================================================================

Config.PoliceRequired = 0              -- Minimum number of police on duty (0 = no requirement)
Config.PoliceJobs     = { 'police' }   -- Job names that count as police

-- =============================================================================
-- Bag theft (pull animation + success chance)
-- =============================================================================

-- Duration of the bag-pull struggle (ms). Fixed duration if min = max.
Config.Tirsacmintime = 5000
Config.Tirsacmaxtime = 5000

-- Chance to succeed the bag theft (%, 0-100)
Config.reussitesac = 50

-- Player position/orientation relative to the victim during the theft animation
Config.BagpickAnimOffset        = { x = 0.879, y = 0.925, z = -0.053 }
Config.BagpickAnimHeadingOffset = -170.0

-- =============================================================================
-- Bag on the ground
-- =============================================================================

-- Time before an unclaimed dropped bag despawns (ms)
Config.BagDropTimeout = 60000

-- =============================================================================
-- Searching the bag (on the ground or in hand)
-- =============================================================================

Config.FouilleSacTime = 12000   -- Duration of the search (ms)

-- =============================================================================
-- Rewards
-- =============================================================================

-- Cash found in the bag: random amount between min and max
Config.money = { 60, 100 }

-- Possible items (item = ox_inventory name, label = displayed text, quantite = quantity given)
Config.item = {
    { item = 'lockpick',           label = 'Lockpicks',             quantite = 1 },
    { item = 'twerks_candy',       label = 'Candy',                 quantite = 1 },
    { item = 'whiskey',            label = 'Whiskey',               quantite = 1 },
    { item = 'joint',              label = 'Some Good Good',        quantite = 1 },
    { item = 'crack_baggy',        label = 'Some bad bad',          quantite = 1 },
    { item = 'trojan_usb',         label = 'NICE TROJAN',           quantite = 1 },
    { item = 'phone',              label = 'Smart Phone',           quantite = 1 },
    { item = 'laptop',             label = 'Fast Laptop',           quantite = 1 },
    { item = 'tablet',             label = 'Old Tablet',            quantite = 1 },
    { item = 'cryptostick',        label = 'Crypto',                quantite = 1 },
    { item = 'rolex',              label = 'Rolex',                 quantite = 1 },
    { item = 'lighter',            label = 'lighter',               quantite = 1 },
}
