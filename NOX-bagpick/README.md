# Bagpick

<img width="1672" height="941" alt="bagpick" src="https://github.com/user-attachments/assets/26973dd6-4dfa-4b8f-9639-8735c6e67d0b" />

NPC handbag theft script.

## Installation

1. Copy the resource folder into `resources/`.
2. Add `ensure bagpick` (or the folder name) to your `server.cfg`.
3. Adjust `config.lua` if needed (see below).

## Configuration

- `Config.Locale` - message language (`fr` / `en`, see `locales/`).
- `Config.Framework` - `auto` (detects ESX / QBox / QBCore) or force one, see `bridge/`.
- `Config.Keys` - keybinds for stealing, picking up, searching, and dropping a bag.
- `Config.PoliceRequired` / `Config.PoliceJobs` - number of police on duty required to steal.
- `Config.Tirsacmintime` / `Config.Tirsacmaxtime` / `Config.reussitesac` - duration of the bag pull and success chance.
- `Config.BagDropTimeout` / `Config.FouilleSacTime` - delay before a dropped bag despawns, and search duration.
- `Config.money` / `Config.item` - cash or items given as a reward (items are handled via ox_inventory, otherwise via the framework).

## Debug

`Config.Debug = true` prints the framework detected by `bridge/shared.lua` to console.

---

No support! Join my [Discord server](https://discord.gg/6wdkx6X).
