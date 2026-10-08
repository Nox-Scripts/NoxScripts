Config = {}

-- Print hold/charge/fire info to the F8 console, useful when tuning the
-- values below. Turn this on first if the script doesn't seem to be doing
-- anything.
Config.Debug = false

-- ---------------------------------------------------------------------------
-- Hearing / audio
-- ---------------------------------------------------------------------------

-- How far away (game units, ~= meters) other players can hear a backfire
Config.MaxHearingDistance = 80.0

-- Volume (0.0 - 1.0) for a player standing right next to the car.
-- It fades linearly down to 0 at Config.MaxHearingDistance.
Config.MaxVolume = 0.3

-- Sound files that live in html/sounds/ -- add or remove freely.
-- One is picked at random each time a backfire fires.
Config.Sounds = {
    'backfire1.mp3',
    'backfire2.mp3',
}

-- If true, each backfire fires a random number of times in a row (see
-- Config.PopWeights below) instead of always firing just once. Toggle
-- in-game any time with /togglemultipop.
Config.MultiPop = true

-- Delay (ms) between each pop within a multi-pop burst.
Config.PopDelay = 150

-- Odds of getting 1, 2, or 3 pops when Config.MultiPop is on. These are
-- relative weights, not percentages - they just need to be numbers, and
-- bigger means more likely. The values below (6/3/1, adding up to 10) work
-- out to roughly 60% single, 30% double, 10% triple.
Config.PopWeights = {
    [1] = 6,
    [2] = 3,
    [3] = 1,
}

-- ---------------------------------------------------------------------------
-- Detection / trigger tuning
-- ---------------------------------------------------------------------------

-- If true, backfires can only charge/fire on vehicles that actually have a
-- turbo installed (checked via the vehicle's toggle mods, mod slot 18 =
-- Turbo Tuning in GTA V). If false, works on any vehicle, same as before.
Config.RequireTurbo = true

-- How often (ms) each driver's client re-checks the accelerate control /
-- RPM / rev-limiter state. This is also the smallest granularity for
-- noticing a release, so keep it reasonably low.
Config.CheckInterval = 100

-- Which trigger mode(s) can fire a backfire. Change live with
-- /backfire_mode hold | rpm | both.
--   'hold' - the original behaviour: hold accelerate for
--            Config.HoldDuration, release it, and it fires
--            Config.ReleaseDelay ms later. Deliberate, on-demand feeling.
--   'rpm'  - fires the INSTANT you lift off the throttle at high RPM, no
--            charge-up and no delay. This is the one that actually lines
--            up with what the game's own engine/exhaust are doing on a
--            hard lift, since that's driven by RPM + throttle in the same
--            moment, not a timer - use this if you want the pop to feel
--            like it's happening exactly when the car "actually" pops
--            rather than a separate scripted event a second later.
--   'both' - both can fire; a lift that satisfies 'rpm' cancels any
--            in-progress 'hold' charge so you don't get doubled up.
Config.PopMode = 'both'

-- How long (ms) accelerate has to be held down, continuously, before it
-- counts as "charged" for 'hold'/'both' mode. 1400 = 1.4 seconds.
Config.HoldDuration = 2000

-- How long (ms) to wait after releasing a charged hold before the backfire
-- actually fires, for 'hold'/'both' mode. 1000 = 1 second.
Config.ReleaseDelay = 1000

-- RPM (0.0-1.0, from GetVehicleCurrentRpm) the engine has to be at for a
-- throttle lift to count as a "high-RPM lift" under 'rpm'/'both' mode.
Config.PopRpmThreshold = 0.85

-- How sharply (0.0-1.0) the throttle needs to drop in one check for 'rpm'/
-- 'both' mode to count it as a lift.
Config.PopThrottleDropThreshold = 0.45

-- Minimum speed (m/s) for 'rpm'/'both' mode - ignores revving in place.
Config.PopMinSpeed = 5.0

-- Occasional single pops while sitting on the rev limiter at full throttle
-- (bouncing off redline), like overrun crackle on a real engine. Runs
-- independently of Config.PopMode. Toggle live with /backfire_revlimiter.
Config.RevLimiterCrackle = true

-- RPM (0.0-1.0) that counts as "on the limiter".
Config.RevLimiterRpm = 0.97

-- Chance (0.0-1.0) of a crackle firing on any single check while sitting on
-- the limiter at full throttle - rolled once every Config.CheckInterval.
Config.RevLimiterCrackleChance = 0.12

-- Per-vehicle cooldown (ms), counted from the moment a backfire actually
-- fires (whichever mode caused it), before the same car can trigger again.
Config.VehicleCooldown = 4000

-- Camera shake when a backfire fires, felt only by whoever is actually
-- riding in the popping vehicle (not by bystanders who just hear it).
Config.BackfireCameraShake = true

-- Base shake strength, 0.0-1.0. Scaled up slightly for multi-pop bursts.
Config.BackfireShakeIntensity = 0.025

-- ---------------------------------------------------------------------------
-- Flame effect
-- ---------------------------------------------------------------------------

-- Spawn a flame/pop particle out of the exhaust when a backfire fires.
Config.FlameEffect = true

-- Size of the flame particle. 1.0 is roughly the game's natural scale for
-- this effect; bump it up for something more dramatic.
Config.FlameScale = 1.9

-- Random +/- size variation applied to Config.FlameScale each time, purely
-- for visual variety so every pop doesn't look identical. Set to 0 to
-- disable.
Config.FlameScaleJitter = 0.4

-- Bone names to try spawning the flame on. Most vehicles only have
-- "exhaust" and "exhaust_2" -- the rest just get skipped on models that
-- don't have them (trucks/vans with dual exhausts, etc).
Config.FlameBones = {
    'exhaust', 'exhaust_2', 'exhaust_3', 'exhaust_4',
    'exhaust_5', 'exhaust_6', 'exhaust_7', 'exhaust_8',
    'exhaust_9', 'exhaust_10', 'exhaust_11', 'exhaust_12',
    'exhaust_13', 'exhaust_14', 'exhaust_15', 'exhaust_16',
}
