Config = {}

-- ═══════════════════════════════════════════════════════════════
--  GENERAL
-- ═══════════════════════════════════════════════════════════════
Config.Debug = false

-- qb-target interaction distance on bus stop props
Config.TargetDistance = 2.0

-- Seconds a player must wait between travel requests (anti-spam)
Config.Cooldown = 4

-- Allow paying with bank/card money in addition to cash
Config.AllowBankPayments = true

-- ═══════════════════════════════════════════════════════════════
--  ITEMS
--  (Add these to qb-core/shared/items.lua — see README.md)
-- ═══════════════════════════════════════════════════════════════
Config.Items = {
    ticket = 'bus_ticket', -- single-use, consumed per ride
    card   = 'bus_card'    -- reusable, rechargeable balance card
}

Config.TicketPrice        = 20   -- cash cost to buy ONE ticket
Config.CardPrice          = 100  -- cash cost to buy a new card
Config.CardStartingBalance = 50  -- balance preloaded onto a new card
Config.CardTopUpAmount    = 50   -- how much a single recharge action adds

-- Set to 0 to make cards never expire, or a number of days until they must be renewed
Config.CardExpiryDays = 0

-- ═══════════════════════════════════════════════════════════════
--  FARE PRICING
-- ═══════════════════════════════════════════════════════════════
Config.Fare = {
    Flat              = 25,     -- used when UseDistancePricing = false
    UseDistancePricing = false, -- true = price scales with distance traveled
    PricePerMeter     = 0.03,
    MinPrice          = 15,
    MaxPrice          = 120
}

--- Calculates the fare for a ride. Safe to call from server only
--- (relies on the player's real position for distance pricing).
---@param originCoords vector3|nil
---@param destCoords vector3|vector4
---@return number
function Config.CalculateFare(originCoords, destCoords)
    if not Config.Fare.UseDistancePricing or not originCoords then
        return Config.Fare.Flat
    end

    local dist = #(vector3(originCoords.x, originCoords.y, originCoords.z) - vector3(destCoords.x, destCoords.y, destCoords.z))
    local price = math.floor(dist * Config.Fare.PricePerMeter)

    if price < Config.Fare.MinPrice then price = Config.Fare.MinPrice end
    if price > Config.Fare.MaxPrice then price = Config.Fare.MaxPrice end

    return price
end

-- ═══════════════════════════════════════════════════════════════
--  LOGGING (optional)
-- ═══════════════════════════════════════════════════════════════
Config.LogTravel = false
Config.Webhook = '' -- Discord webhook URL, leave blank to disable

-- ═══════════════════════════════════════════════════════════════
--  BLIPS
-- ═══════════════════════════════════════════════════════════════
Config.Blips = true
Config.BlipSprite = 513
Config.BlipColor = 3
Config.BlipScale = 0.65
Config.BlipShortRange = true

-- ═══════════════════════════════════════════════════════════════
--  DESTINATIONS
--  name   = unique key (no spaces)
--  label  = display name
--  coords = vector4(x, y, z, heading) — heading = direction player faces on arrival
--  blip   = show a map blip for this stop
-- ═══════════════════════════════════════════════════════════════
Config.Locations = {
    { name = 'legion_square',  label = 'Legion Square',            coords = vector4(356.36, -1067.0, 29.56, 357.24), blip = true },
    { name = 'alta_street',    label = 'Alta Street',              coords = vector4(-250.29, -887.53, 30.07, 347.12), blip = true },
    { name = 'Del Perro',      label = 'Del Perro',                coords = vector4(-1527.39, -464.31, 35.4, 217.38), blip = true },
    { name = 'vespucci',       label = 'Vespucci Beach',           coords = vector4(-1170.06, -1474.35, 4.38, 306.87), blip = true },
    { name = 'sandy_shores',   label = 'Sandy Shores',             coords = vector4(1930.15, 3653.74, 33.5, 211.08), blip = true },
    { name = 'paleto_bay',     label = 'Paleto Bay',               coords = vector4(-149.41, 6210.35, 31.33, 58.52), blip = true },
    { name = 'grove_street',   label = 'Grove Street',             coords = vector4(-109.88, -1685.7, 29.31, 229.47), blip = true },
    { name = 'Mirror Park',    label = 'Mirror Park',              coords = vector4(1109.1, -646.98, 59.91, 92.32), blip = true },
}

-- ═══════════════════════════════════════════════════════════════
--  BUS STOP PROP MODELS
--  Every instance of these props anywhere on the map becomes
--  interactable via qb-target. The vec2 offsets are bench seat
--  positions used for the cosmetic "waiting" animation.
-- ═══════════════════════════════════════════════════════════════
Config.Models = {
    [`prop_busstop_02`] = {
        vec2(-0.05, -0.3),
        vec2(0.8, -0.3),
        vec2(1.6, -0.3)
    },
    [`prop_busstop_04`] = {
        vec2(-0.7, -0.1),
        vec2(0.0, -0.1),
        vec2(0.7, -0.1)
    },
    [`prop_busstop_05`] = {
        vec2(-0.1, -0.3),
        vec2(0.5, -0.3),
        vec2(1.0, -0.3)
    }
}
