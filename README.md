# Kureq Utils

Small utilities for WoW Forever (also loads in Classic Era). Each one is a module you turn on or off per character on
the settings page (`/ku`, or the minimap button).

| Module | What it does |
|---|---|
| Ping macro | A macro that targets and pings a mob, or the mobs of a quest. `/ku ping` |
| Nearby alert | A sound and a message when a mob you're after shows up nearby. |
| Delete items | One key deletes the cheapest bag item you allow (quality, value and name rules, a never-delete list). Optionally press twice: the first press says what would go. Marks loot worth more while your bags are full, and keeps deletion statistics. `/ku delete` |
| Kill stats | Every mob you kill for experience, with graphs, maps, deaths and kill XP on tooltips; one character or all added together. `/ku stats` |
| Character notes | A star rating and a note on anyone, shown on their tooltip and in the Looking For Group window; dungeons played together; a warning when someone you rated low joins your group; optionally decline their invites, duels and trades. `/ku note`, `/ku notes` |
| Loadouts | Save your action bars, macros, key bindings and settings, preview them, load any part on another character, undo a load, and share a loadout as text. `/ku loadouts` |

## Install

Download the latest zip from [Releases](https://github.com/viktorbergqvist/kureq_utils/releases) (or CurseForge /
Wago), and unzip it into `World of Warcraft/_forever_/Interface/AddOns/` (or `_classic_era_`), so you have
`Interface/AddOns/KureqUtils/KureqUtils.toc`. Restart the game.

## Saved data

Kill stats, notes, deletion statistics and loadouts are saved account-wide in `KureqUtilsDB`; module choices per
character in `KureqUtilsCharDB`. Turning a module off never deletes its data.

## Licence

GPL-3.0, see [LICENSE](LICENSE).
