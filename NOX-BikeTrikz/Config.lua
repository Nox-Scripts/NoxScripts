--------------------------------------
--<!>-- TRAPREPUBLIC | BIKETRIKZ --<!>--
--------------------------------------
-- Custom merged build: combines the automatic wheelie-pose detection with
-- the Shift+Arrow manual trick poses into a single resource that shares
-- state cleanly. Based on the original Bodhix BDX-Bike-Tricks wheelie
-- system.

-- Controls References: https://docs.fivem.net/docs/game-references/controls/#c

Config = {}

Config.minimumSpeed = 10 -- km/h
Config.groundHeight = 2.5 -- minimum height to perform and autocancel the superman animation.
Config.helmet = false      -- Toggle (true/false) if you to put on the Helmet.
Config.AllowAllBikes = true

-- MERGED-IN: Shift + Arrow manual pose tricks (previously the separate "biketricks" resource)
Config.manualTrickHoldMs = 700 -- ms the auto-wheelie check pauses after a Shift+Arrow pose, so they don't fight over the animation

Config.allowedVehicles = {
    [`crf450`] = true,
    [`manchez`] = true,
    [`sanchez`] = true,
    [`diablous`] = true,
    [`seashark`] = true,
    [`fmx`] = true,
    [`bati`] = true,
    [`carbonrs`] = true,
    [`double`] = true,
    [`sanctus`] = true,
    [`daemon2`] = true,
    [`enduro`] = true,
    [`hakuchou2`] = true,
    [`akuma`] = true,
    [`ratbike`] = true,
    [`hakuchou`] = true,
    [`lectro`] = true,
    [`zombieb`] = true,
    [`diablous2`] = true,
    [`sovereign`] = true,
    [`defiler`] = true,
    [`nightblade`] = true,
    [`avarus`] = true,
    [`gargoyle`] = true,
    [`ruffian`] = true,
    [`shotaro`] = true,
    [`pcj`] = true,
    [`bati2`] = true,
    [`fcr`] = true,
    [`bf400`] = true,
    [`vortex`] = true,
    [`fcr2`] = true,
    [`sanchez2`] = true,
    [`innovation`] = true,
    [`thrust`] = true,
    [`esskey`] = true,
    [`pollacamax`] = true,
    [`claw`] = true,
    [`flhxs_streetglide_special18`] = true,
    [`GODzBMWS1000RR`] = true,
    [`GODzNINJAH2`] = true,
    [`GODzYAMR1`] = true,
    [`kawagala`] = true,
    [`km1000rr`] = true,
    [`mv2019`] = true,
    [`RoyalCustomKawasakiSH2`] = true,
    [`wazuma`] = true,
    [`yzfr6`] = true,
    [`yzfr7`] = true,
    [`z8r`] = true,
    [`zx10r`] = true,
    [`babayaga2`] = true,
    [`frankie`] = true,
    [`HBLTYPHOONE180CC`] = true,
    [`jcm1000rr`] = true,
    [`sloclaw`] = true,
    [`sloinquisitor`] = true,
    [`sloknuckle`] = true,
    [`ugc23h2r`] = true,
    [`zzninja33`] = true,


}

--You can Config All Controls on your Game Settings

--BIKE TRICKS & WHEELIES

--HOW TO WHEELIE:
--Press Left Contrl like normal wheelie and you manually control your speed, very simple and comfortable.

--HOW TO REVERSE WHEELIE:
--While your on speed, Break by Pressing Space and Press your Key (Caps Default) before your bike completly stop.

--HOW TO JUMP:
--While your doing a Break Wheelie reach over 40 degree of inclination then press your Key (X Default).

--HOW TO SWITCH POSE SIDE
--Press your Switch Side Key (Tab Default) on especific poses.

--HOW TO DO AN AIR TRICK:
--Press your Air Trick Key (G Default) while your falling on your Bike.

--HOW TO POSE ON BIKE
--There is some Poses that you can Set the Key for them, press his respective button.

--HOW TO DO A SHIFT+ARROW POSE TRICK (merged in from the old "biketricks" resource):
--Hold Left Shift and press Up, Down, Left, or Right while riding your bike above minimum speed.
--This now hands off cleanly with the automatic wheelie pose above instead of fighting it.
