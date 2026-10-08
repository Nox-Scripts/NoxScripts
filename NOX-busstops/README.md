# qb-busstops

Advanced bus stop travel system for **QBCore**, built on **qb-target** and **ox_lib**.

Right-click any bus stop prop on the map to open a smooth, menu-driven system where
players buy a **single-use ticket** or a **rechargeable bus card**, then travel between
configurable destinations for a fare (flat or distance-based).

## Features

- **qb-target** integration — every `prop_busstop_02/04/05` on the map becomes interactive, no prop placement needed.
- **Two payment items**:
  - `bus_ticket` — single-use, consumed per ride.
  - `bus_card` — rechargeable balance card (like a real transit TAP card), with an optional expiry date.
- Cash **or** cash+ticket/card fares — riders can also just pay cash/bank directly per ride.
- **Server-authoritative pricing** — fares (flat or distance-based) are calculated server-side from the player's real position, never trusted from the client.
- **ox_lib** context menus, progress bars, and notifications for a clean, modern UI.
- Cosmetic "waiting at the bus stop" sequence — the ped walks to a bench seat and plays a sit animation while the progress bar runs, then a screen-fade teleport to the destination.
- Distance sorted destination list with live fare quotes and km-away readout.
- Configurable map blips per stop.
- Anti-spam cooldown and full server-side validation on every transaction.
- Optional Discord webhook logging of every paid ride.
- Admin commands (`/givebuscard`, `/givebusticket`) for support/testing.

## Requirements

- [qb-core](https://github.com/qbcore-framework/qb-core)
- [qb-target](https://github.com/qbcore-framework/qb-target)
- [qb-inventory](https://github.com/qbcore-framework/qb-inventory) (for item metadata support)
- [ox_lib](https://github.com/overextended/ox_lib)

## Installation

1. Drop the `qb-busstops` folder into your `resources` directory.
2. Add the two items below to `qb-core/shared/items.lua`.
3. Copy `images/buscard.png` into your inventory's image folder (e.g. `qb-inventory/html/images/`). Supply your own `bus_ticket.png` the same way (any ticket-style icon works).
4. Add `ensure qb-busstops` to your `server.cfg`, **after** `qb-core`, `qb-target`, `qb-inventory`, and `ox_lib`.
5. Adjust `config.lua` to taste (see below).
6. Restart your server / start the resource.

### items.lua snippet

```lua
['bus_ticket'] = {
    ['name'] = 'bus_ticket',
    ['label'] = 'Bus Ticket',
    ['weight'] = 10,
    ['type'] = 'item',
    ['image'] = 'bus_ticket.png',
    ['unique'] = false,
    ['useable'] = false,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'A single-use ticket for the bus.'
},

['bus_card'] = {
    ['name'] = 'bus_card',
    ['label'] = 'Bus Card',
    ['weight'] = 5,
    ['type'] = 'item',
    ['image'] = 'buscard.png',
    ['unique'] = true,
    ['useable'] = false,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'A rechargeable transit card.'
},
```

> `unique = true` on the card is important — it keeps every card its own inventory
> stack so each one can carry its own balance in metadata without merging with others.

## Configuration highlights (`config.lua`)

| Setting | What it does |
|---|---|
| `Config.Locations` | The list of destinations. Add/remove/rename freely — `coords` is a `vector4(x, y, z, heading)`. |
| `Config.Fare.UseDistancePricing` | `false` = everyone pays `Config.Fare.Flat`. `true` = fare scales with real distance traveled, clamped between `MinPrice`/`MaxPrice`. |
| `Config.TicketPrice` / `Config.CardPrice` | Cash cost to buy each item. |
| `Config.CardStartingBalance` / `Config.CardTopUpAmount` | How much balance a new card starts with, and how much each recharge adds. |
| `Config.CardExpiryDays` | `0` = cards never expire. Any other number requires renewal after that many days. |
| `Config.AllowBankPayments` | Lets players pay fares/purchases from their bank account, not just cash. |
| `Config.Blips` / `Config.BlipSprite` / etc. | Map blip appearance for each stop. |
| `Config.Webhook` / `Config.LogTravel` | Optional Discord audit log of every paid ride. |

## How it plays

1. Player right-clicks a bus stop → **Bus Stop** menu opens (Travel / Buy Ticket / Buy or Recharge Card).
2. **Travel** shows every other configured stop, sorted by distance, each with its live fare.
3. Picking a stop opens a payment menu: **Bus Card** (if owned, shows balance) → **Bus Ticket** (if owned, shows count) → **Cash** → **Bank**. Options the player can't afford are grayed out.
4. On confirmation the server validates and charges the fare, then the client plays a short "waiting for the bus" sequence (bench animation + progress bar) before fading to the destination.

## Possible future upgrades

This is built as a clean, solid base — a few natural extensions if you want to go further:

- Swap the instant-teleport sequence for an actual drivable bus following a route/path.
- Per-stop schedules (buses only "arrive" on a timer).
- Job-restricted bus driver role that drives real NPC/player-passengers between stops.
- Player-facing UI showing card balance/expiry via a HUD component instead of the menu.
