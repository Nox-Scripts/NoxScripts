# DX3_Fov — Ultimate Edition v3.0

## What's new in v3

| Feature | Description |
|---|---|
| **Per-vehicle-class FOV** | Super cars, motorcycles, helicopters — each has its own base FOV tuned for that feel |
| **Speed-based FOV** | FOV widens as you go faster, snapping you into the action |
| **Head bob** | Subtle camera sway tied to vehicle speed — feels alive |
| **Crash shake** | Camera rattles on hard impacts, decays naturally |
| **Yaw auto-center** | Camera slowly drifts back to forward when you stop moving the mouse (configurable) |
| **Cinematic letterbox** | Black bars fade in at high speed for a cinematic feel |
| **On-foot FOV** | Separate FOV logic for walking, sprinting, and aiming |
| **Speedometer HUD** | Clean speed readout with gear, RPM bar, and vehicle class tag |
| **Speed motion blur** | Post FX motion blur at high speed |
| **Crash flash** | Quick white flash on very heavy impacts |
| **Debug overlay** | `/fov` command toggles a live stats overlay |
| **Single config.lua** | Every tunable value in one file, clearly documented |

## Files
```
DX3_fov/
├── config.lua              ← ONLY file you need to edit
├── fxmanifest.lua
├── client/
│   ├── fovdriver.lua       Camera, FOV, head bob, shake
│   ├── effects.lua         Blur, crash flash, motion blur
│   ├── hud.lua             Speedometer, letterbox
│   └── footfov.lua         On-foot FOV (sprint/aim)
└── server/
    └── main.lua            DB migration, player load, admin commands
```

## Installation
1. Drop `DX3_fov` into your resources folder
2. Add `ensure DX3_fov` to `server.cfg`
3. Done — DB migration runs automatically on first start

## Commands
| Command | Permission | What it does |
|---|---|---|
| `/fov` | everyone | Toggle debug overlay (shows FOV, speed, yaw, bob, shake) |
| `/setmiopia [0\|1]` | admin | Toggle your own myopia |
| `/setmiopiatarget [id] [0\|1]` | admin | Toggle another player's myopia |

## Quick config reference
Open `config.lua` — everything is documented inline. Most common tweaks:

- **Camera too high/low** → `CAM_OFFSET_Z` (default `0.65`)
- **FOV feels wrong** → `FOV_DEFAULT` or `FOV_BY_CLASS[class]`
- **Speed widening too aggressive** → lower `FOV_SPEED_MAX_BONUS`
- **Head bob annoying** → set `HEADBOB_ENABLED = false` or lower `HEADBOB_AMPLITUDE`
- **Letterbox bars** → `LETTERBOX_ENABLED = false` to remove entirely
- **HUD position** → `HUD_POSITION_X` / `HUD_POSITION_Y`
- **On-foot FOV** → `FOOT_FOV_ENABLED = false` to disable
