# Changelog

## v1.11 (2026-11-13)

### Macros

- New smart macro KU Enchant: enchants the item whose tooltip shows with the enchant chosen in your Enchanting window.
- Works on items in your bags or on your character, whichever addon draws them.
- Its settings: say yes to replacing an enchant (on), and to making the item soulbound (off).

## v1.10 (2026-11-13)

### Loadouts

- Action bars 6 to 8 are saved and loaded too.
- Loadouts saved before this leave bars 6 to 8 alone; save one again to include them.

### Macros

- Search the icon picker by spell, mount and item name, or by the icon's file name and kind (sword, potion, fire).
- Hover any icon to see its name; a Spells / Items / All filter sorts them.
- KU Ping's macro is now called KureqPing; it stays on your bars, with its history, and your loadouts follow.

### Kill stats

- The open window redraws at most once a second during fast pulls.

### Performance

- Smart macros read each item's tooltip once a session and skip your bags while none is ticked.
- The kill XP line, the Professions guide's map pins and trainer marks, and the group warning do less work.
- Debug page: Show performance prints memory and, while Debug checks are on, how long handlers took.

## v1.9 (2026-11-13)

### Macros

- Smart macros are General macros shared by all your characters, rewritten for the one you log in on.
- Their ticks and settings are shared too; each character's old copies move to the same bar slots.
- Drag a macro straight from any list to your bars.
- The code editor grows with the window, and a Wrap lines tick lets long lines scroll sideways.
- /tm, /wm and /cwm suggest the markers by icon and name, and the Now line names them.
- No false conditions warning on /tm, /dismount and the pet commands.
- Long condition chains wrap instead of being cut off with "...".
- Clicks land on the right letter with UI addons that change all game fonts.
- Problem underlines sit under their own line.
- /macro in combat opens Kureq Macros instead of Blizzard's window too.

### Key bindings

- Open Kill stats, Character notes, Loadouts, Macros, Mail rules and the settings from a key.

### Fixes

- An error in one part at login no longer leaves the others without their settings.

## v1.8 (2026-11-13)

### Macros

- New: /ku macro, a window for your General and Character macros with search, history and import.
- A code editor with colours, problem underlines with fixes, suggestions as you type, undo and shell keys.
- Ready-made macros for your class and for Kureq Utils' own commands.
- Smart macros that keep themselves up to date: potion, mana, drink, food, bandage, hearth, mount and pet.
- KU Mount uses Ghost Wolf, Travel or Cat Form, or Aspect of the Cheetah where you can't mount.
- The Ping macro module is gone: it moved into Macros as KU Ping, in the Smart macros tab.
- Your Ping settings, /ku ping and Nearby alert carry over; KU Ping is ticked for you if you used it.
- Optional: open this window instead of the game's macros.

### Loadouts

- Any class, and ignored action bar slots, for one loadout that suits all your characters.
- Rules load a loadout by themselves: new characters, every login, a level or a learned spell.
- Clone a loadout or a backup.

### Delete items

- Optional: look in the reagent bag.
- Class bags: keep at most N Soul Shards, delete old ammo, keep at most N ammo stacks, look in special bags.

### Mail rules

- Items in the reagent bag are sent too.
- The mailbox button stays inside the mail frame; right-click it for the preview.

### General

- Windows can be resized from their bottom-right corner.
- Windows use the settings page's checkboxes, dropdowns and text boxes.
- The minimap menu shows an icon beside each window.

## v1.7.2 (2026-11-13)

### Delete items

- Name rules can match text in the item's tooltip (Tooltip has "Classes: Mage" for mage scrolls)
- Tooltip rules never error in combat; an unreadable tooltip keeps the item

## v1.7.1 (2026-11-13)

### Settings

- Empty item lists show a clear slot and say to drop an item there
- An empty name rule list no longer hides the rest of the page (Allow delete on Delete items)

## v1.7 (2026-11-13)

### Loadouts

- Mouseover macros fall back to your target, then you, and check the unit exists
- Loading puts your mounts back on the bars instead of clearing them

### Mail rules

- New: send herbs, ore, cloth and other items to your other characters from the mailbox, by rules you set (item kind, name starts with / ends with / contains, quality, keep some back). Ready-made rules, a Never send list, a preview of what goes to whom, and a chat line after sending. /ku mail.

## v1.6.1 (2026-11-12)

### Ping macro

- The preview and Nearby alert text no longer overlap on the settings page

## v1.6 (2026-11-12)

### General

- Your version beside the settings title, and a Changelog page of what changed in each release

## v1.5 (2026-11-12)

### Character notes

- Shared guild notes: turn on **Share guild notes** and your notes go to guildmates with the addon (tick **Private**
  to keep one to yourself). Guild notes show with their author in the notes window, tooltips and the Looking For
  Group window, count toward group warnings, and are passed along to guildmates who weren't online at the same time.
- **Clear guild notes** removes every note you didn't write, for good.

### Loadouts

- Edit a saved loadout: write macros (icon, text with a 255 counter, character or account), insert helpers and
  spells, or add a ready-made macro (mouseover cast, focus, cast sequence, trinket and cast, stop casting, start
  attack, pet).
- Edit its bars (drop spells, items and macros on slots, drag to swap, right-click to put a macro or clear), key
  bindings (click, then press a key) and settings. **Revert changes** undoes your edits.
- Loading saves and restores account macros and macro key bindings too, and refuses a load that has no room for its
  macros before changing anything.
- Loadouts using new features share as `KU2:`; plain ones stay `KU1:` for older versions.

### Ping macro

- Nearby alert is now part of the Ping macro, on its settings page, and off until you tick **Alert when nearby**.

### Kill stats

- Page tabs in WoW Forever's style, under the window.

### General

- Settings that can't open in combat, and macros and bars that change after combat, now all wait for combat to end
  the same way.

## v1.4 (2026-11-12)

### General

- Now on Wago

## v1.3 (2026-11-12)

- First public release: ping macro, nearby alert, delete items, kill stats, character notes and loadouts.
