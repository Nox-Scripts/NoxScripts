# NOX-TurboFX

One FiveM/QBCore resource, two turbo-car effects that share some code but
run independently:

1. **Blow-off valve (BOV)** - a manual key (default `\`) plays a random
   turbo flutter/pop sound. By default it also fires on its own whenever
   the gearbox changes gear while RPM was recently high (an upshift under
   boost flutters a real BOV even if you never lifted the throttle - an
   automatic gearbox shifting at full throttle never "releases" the gas).
   There's also an optional throttle-lift auto-trigger (fires on any hard
   lift after holding the gas, regardless of gear) - it's **off** by
   default since it fires mid-gear with no shift happening, which reads as
   random; turn it on with `/turbo_bov_liftoff` if you want it too.
   Networked, so nearby players hear it too, and optionally spits a small
   flame from the exhaust.
2. **Backfire / pop-and-bang** - three independent trigger modes (pick one
   or run more than one at once, see `Config.PopMode`):
   - `hold` - the original behaviour: hold the gas, let off, it backfires
     `Config.ReleaseDelay` later.
   - `rpm` - fires **the instant** you lift off at high RPM, no charge-up
     and no delay, so it lines up with the same moment the game's own
     engine/exhaust would be doing something, rather than a separate
     scripted event a beat later.
   - rev-limiter crackle - occasional pops while bouncing off redline at
     full throttle, independent of the two modes above.

   Each fire is a sound plus an exhaust flame, sometimes popping 2 or 3
   times in a row, plus camera shake for whoever's actually riding in the
   car. Also networked.

Both effects only fire on vehicles with a turbo installed (mod slot 18) by
default, and both are independent - turning one off doesn't affect the
other.

## Install

1. Drop the whole `NOX-TurboFX` folder into your server's `resources`
   folder.
2. Add to your `server.cfg`:
   ```
   ensure NOX-TurboFX
   ```
   (make sure it's below `qb-core` in your cfg - the backfire half's
   commands use `QBCore.Functions.Notify`)
3. Restart your server / start the resource.

If you already have the old separate `NOX-TurboValves` and
`NOX-carbackfireEffect` resources installed, remove both of those from
`resources` and your `server.cfg` first - this one folder replaces them.

## Files

```
NOX-TurboFX/
├── fxmanifest.lua
├── config.lua              -- backfire tuning (see below)
├── client/
│   ├── shared_fx.lua        -- exhaust-flame + turbo-check helpers shared by both scripts (loads first)
│   ├── turbo_valves.lua     -- BOV: manual key, throttle-lift + gear-shift auto-trigger, its own tuning at the top
│   └── backfire.lua         -- backfire: hold / rpm / rev-limiter trigger modes, multi-pop, flame, camera shake
├── server/
│   ├── turbo_valves.lua     -- relays BOV sounds to nearby players
│   └── backfire.lua         -- validates + relays backfires to nearby players
└── html/
    ├── index.html           -- one NUI page, plays both effects' sounds
    └── sounds/
        ├── (5 BOV sounds)
        └── backfire1.mp3, backfire2.mp3
```

## Tuning

The two effects were built separately and keep their own tuning in their
own place:

- **Blow-off valve** - plain local variables at the top of
  `client/turbo_valves.lua`:
  - volume, cooldowns, pitch/volume jitter, camera shake, hearing distance
  - `TriggerOnThrottleLift` (off by default) / `AutoHoldThrottleThreshold` / `AutoHoldDurationMs` / `AutoThrottleDropThreshold` / `AutoMinSpeed` - throttle-lift auto-trigger
  - `TriggerOnGearShift` / `ShiftUpOnly` / `ShiftMinRpmWindow` / `ShiftHighRpmHoldMs` / `ShiftMinSpeed` / `ShiftCooldownMs` - gear-shift auto-trigger
  - `FlameOnValve` / `ValveFlameScale` / `ValveFlameJitter` - optional exhaust flame on every valve fire
- **Backfire** - `config.lua`, a `Config` table:

| Setting | What it does |
|---|---|
| `MaxHearingDistance` | How far away (units, ≈ meters) other players can hear it |
| `MaxVolume` | Volume for someone standing right next to the car |
| `Sounds` | List of files in `html/sounds/` to pick from at random |
| `MultiPop` | Whether each backfire fires a random 1-3 times instead of always once |
| `PopDelay` | Delay (ms) between each pop within a multi-pop burst |
| `PopWeights` | Relative odds of getting 1, 2, or 3 pops when `MultiPop` is on |
| `RequireTurbo` | Whether a vehicle needs a turbo installed for backfires to trigger/fire at all |
| `PopMode` | `'hold'`, `'rpm'`, or `'both'` - which trigger mode(s) are active |
| `HoldDuration` | How long (ms) accelerate must be held to "charge", for `hold`/`both` |
| `ReleaseDelay` | How long (ms) after releasing a charged hold before it fires, for `hold`/`both` |
| `PopRpmThreshold` | RPM (0.0-1.0) needed for a throttle lift to count, for `rpm`/`both` |
| `PopThrottleDropThreshold` | How sharp the throttle lift needs to be (0.0-1.0), for `rpm`/`both` |
| `PopMinSpeed` | Minimum speed (m/s) for `rpm`/`both` - ignores revving in place |
| `RevLimiterCrackle` | Whether occasional pops happen while bouncing off the rev limiter |
| `RevLimiterRpm` | RPM (0.0-1.0) that counts as "on the limiter" |
| `RevLimiterCrackleChance` | Odds (0.0-1.0) of a crackle on any single check at the limiter |
| `VehicleCooldown` | Minimum time (ms), after a backfire fires, before the same car can trigger again |
| `BackfireCameraShake` | Camera shake for whoever's riding in the car when it pops |
| `BackfireShakeIntensity` | Base shake strength (0.0-1.0), scaled up a bit for multi-pop |
| `FlameEffect` | Whether a flame particle spawns from the exhaust when a backfire fires |
| `FlameScale` | Size of the flame particle (1.0 ≈ default game scale) |
| `FlameScaleJitter` | Random +/- size variation per flame, for visual variety |
| `FlameBones` | Exhaust bone names to try the flame on; ones the vehicle doesn't have are skipped |

Turn on `Config.Debug = true` and watch the F8 console to see trigger
timing for whichever mode(s) are active.

## Commands

| Command | Effect |
|---|---|
| `/turbo_bov` (or the bound key, default `\`) | Manually fire a random BOV sound |
| `/turbo_bov_auto` | Master on/off for the whole auto-trigger loop (both of the two below stop if this is off) |
| `/turbo_bov_liftoff` | Toggle the throttle-lift auto-trigger on/off - **off by default** |
| `/turbo_bov_gearshift` | Toggle the gear-shift auto-trigger on/off - **on by default** |
| `/turbo_bov_hold <seconds>` | Change how long you must hold the gas before a lift-off auto-fires the BOV (only matters if the throttle-lift trigger is on) |
| `/turbo_bov_flame` | Toggle the exhaust flame that plays alongside the valve sound |
| `/togglebackfire` | Toggle the whole backfire effect on/off for yourself |
| `/togglemultipop` | Toggle multi-pop (1-3 pops) on/off - off means every backfire is a single pop |
| `/backfire_mode hold\|rpm\|both` | Switch which backfire trigger mode(s) are active |
| `/backfire_revlimiter` | Toggle rev-limiter crackle on/off |
| `/testbackfire` | Force a backfire on your current vehicle right now, bypassing all trigger detection (for testing the audio/flame pipeline) |

## Notes

- Both effects require a turbo (mod slot 18) by default - `RequireTurbo` at
  the top of `client/turbo_valves.lua` for the BOV, `Config.RequireTurbo`
  in `config.lua` for the backfire.
- There's no native/event GTA exposes for "the vehicle's own vanilla
  exhaust pop just happened" - Rockstar doesn't script-expose that. The
  `rpm` backfire mode and the gear-shift BOV trigger are built to react to
  the same underlying conditions (RPM + throttle behaviour) that produce
  that look in the base game, which is as close as a script can get to
  "syncing" with it - they can't guarantee frame-perfect alignment with
  something the game itself decides internally.
- Both broadcast to every connected client and let each one decide locally
  whether it's in range. That's simple and fine for how rarely these fire;
  for a very large server you could change either `server/*.lua` to loop
  over `GetPlayers()` and only target players near the vehicle instead.
- The NUI page (`html/index.html`) keeps the two effects' audio completely
  separate - the BOV always stops its own previous sound before playing a
  new one, while backfire pops can overlap each other, and neither one
  touches the other's audio.
