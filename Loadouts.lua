-- Loadouts: save a character's action bars, character macros, key bindings and interface settings under a name, and
-- load them on any character (a new paladin gets your old one's bars). Account-wide, in KureqUtilsDB.loadouts.
-- Spells are kept by name, so loading places the highest rank you know; a spell you don't know yet waits for its
-- slot and goes on when you learn it (pending, per character by GUID). Same-named character macros are replaced,
-- others kept. Nothing changes in combat: Blizzard blocks action bar and binding changes then. Each load first keeps
-- what you had as a backup for this character, and a loadout can be shared as a line of text.
local _, ns = ...
ns.AddModule("loadouts", "Loadouts",
    "Save your action bars, macros, key bindings and Blizzard settings, and load them on another character.")
local tinsert = table.insert
local L = {}
ns.loadouts = L
ns.defaults.loadouts = {}

L.SLOTS = 120 -- the action slots every client has: the six bars and the stance / form bars
-- Forever's bars 6 to 8 (MultiBar5-7) are pages 13-15, slots 145-180; Classic Era has no such bars. Slots 121-144
-- hold no bar. L.MAX_SLOT caps a shared loadout's slots on any client.
L.FIRST_EXTRA, L.MAX_SLOT = 145, 180
function L.maxSlot() return math.max(L.SLOTS, (MULTIBAR_7_ACTIONBAR_PAGE or 0) * (NUM_ACTIONBAR_BUTTONS or 12)) end
function L.isSlot(slot)
    return type(slot) == "number" and slot >= 1 and (slot <= L.SLOTS or slot >= L.FIRST_EXTRA and slot <= L.maxSlot())
end
-- Every action slot this client has, in order
function L.slots()
    local list = {}
    for slot = 1, L.SLOTS do list[slot] = slot end
    for slot = L.FIRST_EXTRA, L.maxSlot() do list[#list + 1] = slot end
    return list
end
-- Whether loading lo leaves slot as it is: an ignored slot, or one past the slots lo was saved with (lo.lastSlot,
-- 120 when unset): a loadout saved on Classic Era or before bars 6 to 8 were kept has nothing for them, and leaves them
L.UNSAVED = "unsaved" -- lo.ignored[slot]: not saved (an older loadout's bars 6 to 8), not ignored by you
local UNSAVED = L.UNSAVED
function L.ignores(lo, slot) return (lo.ignored and lo.ignored[slot]) ~= nil or slot > (lo.lastSlot or L.SLOTS) end
local ACCOUNT_MACROS = MAX_ACCOUNT_MACROS or 120 -- character macros come after the general ones
local CHARACTER_MACROS = MAX_CHARACTER_MACROS or 18
-- interface settings: CVars in the Game and Combat categories, not graphics, sound, network or debug ones
local CVAR_CATEGORIES = {[3] = true, [4] = true}

-- name, spell ID and icon of a spell: by ID, or by name (then the highest rank in your spellbook)
function L.spellInfo(spell)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spell)
        if info then return info.name, info.spellID, info.iconID end
        return nil
    end
    local name, _, icon, _, _, _, id = GetSpellInfo(spell)
    return name, id, icon
end
local function known(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown then return C_SpellBook.IsSpellKnown(id) end
    return IsSpellKnown(id)
end
local function pickupSpell(id) if C_Spell and C_Spell.PickupSpell then C_Spell.PickupSpell(id) else PickupSpell(id) end end
local function pickupItem(id) if C_Item and C_Item.PickupItem then C_Item.PickupItem(id) else PickupItem(id) end end
-- A mount slot ("summonmount", the mount's ID): the journal picks it up by its place in the shown list; a mount the
-- journal's filters hide falls back to its spell. Returns whether the cursor holds something.
local function pickupMount(id)
    local J = C_MountJournal
    if not J then return false end
    ClearCursor()
    for i = 1, J.GetNumDisplayedMounts and J.GetNumDisplayedMounts() or 0 do
        if J.GetDisplayedMountID(i) == id then J.Pickup(i); break end
    end
    if not GetCursorInfo() and J.GetMountInfoByID then
        local _, spell = J.GetMountInfoByID(id)
        if spell then pickupSpell(spell) end
    end
    return GetCursorInfo() ~= nil
end
function L.itemIcon(id) return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or GetItemIcon and GetItemIcon(id) end

local function charKey() return UnitGUID("player") end
local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end

-- Your macros, general ones first (only with withAccount): {name, icon, body, account}
local function yourMacros(withAccount)
    local list = {}
    local numAccount, numChar = GetNumMacros()
    for i = 1, withAccount and numAccount or 0 do
        local name, icon, body = GetMacroInfo(i)
        if name then tinsert(list, {name = name, icon = icon, body = body, account = true}) end
    end
    for i = ACCOUNT_MACROS + 1, ACCOUNT_MACROS + (numChar or 0) do
        local name, icon, body = GetMacroInfo(i)
        if name then tinsert(list, {name = name, icon = icon, body = body}) end
    end
    return list
end
-- Key bindings to macros ("MACRO <name>") aren't in GetBinding's list: the commands of your macros and lo's
local function macroCommands(lo)
    local commands = {}
    for _, m in ipairs(yourMacros(true)) do commands["MACRO " .. m.name] = true end
    for _, m in ipairs(lo and lo.macros or {}) do commands["MACRO " .. m.name] = true end
    return commands
end
local function macroKeys(command)
    if not GetBindingKey then return {} end
    return {GetBindingKey(command)}
end
function L.list() return ns.db.loadouts.list end
function L.pending() return ns.db.loadouts.pending[charKey() or ""] end

-- The interface settings a loadout may hold (name = true): Game and Combat CVars you can change
function L.cvarNames()
    local names = {}
    if not (ConsoleGetAllCommands and C_CVar and C_CVar.GetCVarInfo) then return names end
    for _, c in ipairs(ConsoleGetAllCommands()) do
        if c.commandType == 0 and CVAR_CATEGORIES[c.category] then
            local value, _, _, _, locked, isSecure, readOnly = C_CVar.GetCVarInfo(c.command)
            if value and not (locked or isSecure or readOnly) then names[c.command] = true end
        end
    end
    return names
end

-- What you have now, as a loadout (without its name). Character macros only, unless withAccount (a load's backup,
-- so Restore can put back general macros it changed): a saved loadout gets account macros only from the editor.
function L.capture(withAccount)
    local lo = {actions = {}, macros = {}, bindings = {}, cvars = {}, created = time()}
    lo.className, lo.class = UnitClass("player")
    lo.from = ns.notes and ns.notes.unitName("player") or UnitName("player")
    for _, slot in ipairs(L.slots()) do
        local kind, id = GetActionInfo(slot)
        if kind == "spell" then
            lo.actions[slot] = {type = "spell", id = id, name = (L.spellInfo(id))}
        elseif kind == "macro" then
            local name = GetActionText(slot) or (GetMacroInfo(id))
            if name then lo.actions[slot] = {type = "macro", name = name} end
        elseif kind == "item" then
            lo.actions[slot] = {type = "item", id = id}
        elseif kind then
            lo.actions[slot] = {type = kind, id = id} -- kept for the preview; loading leaves these out
        end
    end
    lo.macros = yourMacros(withAccount)
    for i = 1, GetNumBindings() do
        local command, _, key1, key2 = GetBinding(i)
        if command and (key1 or key2) then lo.bindings[command] = {key1, key2} end
    end
    for _, m in ipairs(lo.macros) do -- keys bound to the macros it keeps
        local command = "MACRO " .. m.name
        local keys = macroKeys(command)
        if #keys > 0 then lo.bindings[command] = keys end
    end
    for name in pairs(L.cvarNames()) do
        local value, default = C_CVar.GetCVarInfo(name)
        if value ~= default then lo.cvars[name] = value end
    end
    if GetActionBarToggles then lo.bars = {GetActionBarToggles()} end
    if L.maxSlot() > L.SLOTS then lo.lastSlot = L.maxSlot() end
    return lo
end

function L.counts(lo)
    local actions, bindings, cvars = 0, 0, 0
    for _ in pairs(lo.actions) do actions = actions + 1 end
    for _ in pairs(lo.bindings) do bindings = bindings + 1 end
    for _ in pairs(lo.cvars) do cvars = cvars + 1 end
    return actions, #lo.macros, bindings, cvars
end

-- A new loadout, or id's replaced (Update from current); returns its id and, on a replace, how many of this client's
-- slots it left as they were: ignored ones, and ones the old loadout wasn't saved with (still not saved after).
-- Slots this client hasn't got (bars 6 to 8 on Classic Era) keep what the old loadout had too.
function L.save(name, id)
    local lo = L.capture()
    lo.name = name
    local db = ns.db.loadouts
    local kept
    if id and db.list[id] then
        local old = db.list[id]
        lo.created, lo.anyClass, lo.ignored = old.created, old.anyClass, copy(old.ignored) -- what you set on it stays
        local seen, oldLast = lo.lastSlot or L.SLOTS, old.lastSlot or L.SLOTS
        for s = math.max(L.FIRST_EXTRA, oldLast + 1), seen do
            lo.ignored = lo.ignored or {}
            lo.ignored[s] = lo.ignored[s] or UNSAVED
        end
        lo.lastSlot = math.max(seen, oldLast)
        if lo.lastSlot == L.SLOTS then lo.lastSlot = nil end
        kept = 0
        for slot = 1, L.MAX_SLOT do
            local ignored = L.ignores(old, slot)
            if ignored or slot > seen then lo.actions[slot] = copy(old.actions[slot]) end
            if ignored and L.isSlot(slot) then kept = kept + 1 end
        end
        lo.rules = old.rules
        lo.off = copy(old.off) -- a part that's off stays as it was
        if lo.off and lo.off.actions then
            lo.actions, lo.lastSlot, lo.ignored, kept = copy(old.actions), old.lastSlot, copy(old.ignored), 0
        end
        for _, part in ipairs({"macros", "bindings", "cvars"}) do
            if lo.off and lo.off[part] then lo[part] = copy(old[part]) end
        end
        if lo.off and lo.off.cvars then lo.bars = copy(old.bars) end -- bar toggles load with the Blizzard settings
        lo.updated = time()
    else
        id = db.nextId
        db.nextId = id + 1
    end
    db.list[id] = lo
    return id, kept
end

-- A full copy of lo (a saved loadout or a backup) as a new saved loadout named "<name> (copy)", a number added if
-- that's taken; returns its id. What only a backup has (what to restore and how) stays behind.
function L.clone(lo)
    local new = copy(lo)
    for _, k in ipairs({"backup", "parts", "pending", "madeMacros", "boundMacros", "bindingSet", "switchedSet",
        "updated"}) do new[k] = nil end
    local taken = {}
    for _, x in pairs(L.list()) do taken[x.name] = true end
    local base = lo.name
    if #base > 45 then base = base:sub(1, 45):gsub("[\192-\255][\128-\191]*$", "") end -- room for " (copy) 2"
    base = base .. " (copy)"
    local name, n = base, 1
    while taken[name] do
        n = n + 1
        name = base .. " " .. n
    end
    new.name, new.created, new.rules = name, time(), L.rulesOff(lo.rules)
    local db = ns.db.loadouts
    local id = db.nextId
    db.nextId = id + 1
    db.list[id] = new
    return id
end

local function place(slot) PlaceAction(slot); ClearCursor() end
-- a slot holding something loading can't put back (a mount, a pet, a companion): a restore leaves it alone
local PLACEABLE = {spell = true, macro = true, item = true, summonmount = true}
local function unplaceable(slot)
    local kind = GetActionInfo(slot)
    return kind ~= nil and not PLACEABLE[kind]
end
local function clearSlot(slot)
    if GetActionInfo(slot) then PickupAction(slot); ClearCursor() end
end

local COMBAT = "not in combat: Blizzard blocks changing action bars and bindings then"
L.ALL = {actions = true, macros = true, bindings = true, cvars = true}

-- The index of your macro called name among your general (account) or character macros, or nil. A name can be in
-- both, and GetMacroIndexByName finds only one of them.
local function macroIndex(name, account)
    local first = account and 1 or ACCOUNT_MACROS + 1
    for i = first, first + (account and ACCOUNT_MACROS or CHARACTER_MACROS) - 1 do
        if GetMacroInfo(i) == name then return i end
    end
end
L.macroIndex = macroIndex

-- Why loading lo's macros doesn't fit next to yours (nil when it does): the new ones it makes, per scope
function L.macroRoom(lo)
    local need = {character = 0, account = 0}
    for _, m in ipairs(lo.macros) do
        if not macroIndex(m.name, m.account) then need[L.scope(m)] = need[L.scope(m)] + 1 end
    end
    local numAccount, numChar = GetNumMacros()
    local over = {}
    for _, s in ipairs({{"character", numChar, CHARACTER_MACROS}, {"account", numAccount, ACCOUNT_MACROS}}) do
        local n = (s[2] or 0) + need[s[1]] - s[3]
        if n > 0 then over[#over + 1] = ("%d %s %s"):format(n, s[1], n == 1 and "macro" or "macros") end
    end
    if #over > 0 then return "there's no room for its macros: delete " .. table.concat(over, " and ") .. " first" end
end

-- Loads parts ({actions, macros, bindings, cvars} = true) of a loadout. Returns a report, or nil and why not.
-- Key binding sets (Enum.BindingSet on Forever): the account's, shared by your characters, and a character's own
local ACCOUNT_SET = Enum and Enum.BindingSet and Enum.BindingSet.Account or ACCOUNT_BINDINGS or 1
local CHARACTER_SET = Enum and Enum.BindingSet and Enum.BindingSet.Character or CHARACTER_BINDINGS or 2
-- characterSet: the bindings go to this character's own set, never the account's (the default for new characters)
function L.apply(lo, parts, characterSet)
    if InCombatLockdown() then return nil, COMBAT end
    local full = parts.macros and L.macroRoom(lo)
    if full then return nil, full end
    local report = {placed = 0, waiting = 0, skipped = 0, macros = 0, bindings = 0, cvars = 0}
    ClearCursor()
    report.madeMacros = {} -- the macros this load makes ({name, account}), so a restore can take them away
    if parts.macros then
        for _, m in ipairs(lo.madeMacros or {}) do -- a restore: the macros its load made go, and their keys
            local index = macroIndex(m.name, m.account)
            if index then
                for _, key in ipairs(macroKeys("MACRO " .. m.name)) do SetBinding(key) end
                DeleteMacro(index)
            end
        end
        for _, m in ipairs(lo.macros) do
            local index = macroIndex(m.name, m.account)
            local numAccount, numChar = GetNumMacros()
            if index then
                EditMacro(index, m.name, m.icon, m.body)
                report.macros = report.macros + 1
            elseif (m.account and numAccount or numChar or 0) < (m.account and ACCOUNT_MACROS or CHARACTER_MACROS) then
                CreateMacro(m.name, m.icon, m.body, not m.account or nil) -- general macros are for every character
                tinsert(report.madeMacros, {name = m.name, account = m.account})
                report.macros = report.macros + 1
            end
        end
    end
    if parts.actions then
        local pending = {}
        for slot, name in pairs(L.pending() or {}) do -- an ignored slot's waiting spell keeps waiting
            if L.ignores(lo, slot) then pending[slot] = name end
        end
        for _, slot in ipairs(L.slots()) do
            local a = lo.actions[slot]
            if L.ignores(lo, slot) then -- never touched
            elseif lo.backup and unplaceable(slot) then -- left as it is
            elseif not a then
                clearSlot(slot)
            elseif a.type == "spell" then
                local _, id = L.spellInfo(a.name or a.id)
                if id and known(id) then
                    pickupSpell(id)
                    place(slot)
                    report.placed = report.placed + 1
                else
                    clearSlot(slot) -- kept free for it
                    pending[slot] = a.name
                    report.waiting = report.waiting + 1
                end
            elseif a.type == "macro" and (GetMacroIndexByName(a.name) or 0) > 0 then
                PickupMacro(a.name)
                place(slot)
                report.placed = report.placed + 1
            elseif a.type == "item" then
                pickupItem(a.id)
                place(slot)
                report.placed = report.placed + 1
            elseif select(2, GetActionInfo(slot)) == a.id and GetActionInfo(slot) == a.type then
                report.placed = report.placed + 1 -- already there (a mount, a pet): nothing to put back
            elseif a.type == "summonmount" and pickupMount(a.id) then
                place(slot)
                report.placed = report.placed + 1
            elseif a.type ~= "spell" and a.type ~= "macro" and a.type ~= "item" then
                report.skipped = report.skipped + 1 -- can't put it back: leave the slot as it is
            else
                clearSlot(slot)
                report.skipped = report.skipped + 1
            end
        end
        for slot, name in pairs(lo.pending or {}) do -- a backup's spells that were still waiting, if the slot's free
            if not (L.ignores(lo, slot) or GetActionInfo(slot)) then pending[slot] = name end
        end
        ns.db.loadouts.pending[charKey()] = next(pending) and pending or nil
        if lo.pending then L.fillPending() end -- a restored spell may have been learned since
    end
    local now = parts.bindings and GetCurrentBindingSet()
    if parts.bindings and lo.switchedSet and now ~= ACCOUNT_SET and LoadBindings then
        -- a restore of an automatic load that moved you from the account's set to your own: back to the account's,
        -- which that load never changed
        LoadBindings(ACCOUNT_SET)
        SaveBindings(ACCOUNT_SET)
        for _ in pairs(lo.bindings) do report.bindings = report.bindings + 1 end
    elseif parts.bindings then
        local keep = {} -- every key the loadout binds; other bound keys are unbound, so the keys end up as saved
        for _, keys in pairs(lo.bindings) do
            for _, key in pairs(keys) do keep[key] = true end
        end
        for i = 1, GetNumBindings() do
            local _, _, key1, key2 = GetBinding(i)
            for _, key in ipairs({key1 or false, key2 or false}) do
                if key and not keep[key] then SetBinding(key) end
            end
        end
        local commands = macroCommands(lo)
        for _, command in ipairs(lo.boundMacros or {}) do commands[command] = true end -- a restore: what its load bound
        for command in pairs(commands) do
            for _, key in ipairs(macroKeys(command)) do
                if not keep[key] then SetBinding(key) end
            end
        end
        for command, keys in pairs(lo.bindings) do
            for _, key in pairs(keys) do SetBinding(key, command) end
            report.bindings = report.bindings + 1
        end
        SaveBindings(characterSet and CHARACTER_SET or lo.bindingSet or now)
    end
    if parts.cvars then
        for name, value in pairs(lo.cvars) do
            if pcall(SetCVar, name, value) then report.cvars = report.cvars + 1 end
        end
        if lo.bars and SetActionBarToggles then
            SetActionBarToggles(unpack(lo.bars))
            if MultiActionBar_Update then MultiActionBar_Update() end
        end
    end
    return report
end

-- Backups: before each load, this character's setup is kept as "Before <loadout>", the last L.BACKUPS, newest first
L.BACKUPS = 5
function L.backups()
    local all, key = ns.db.loadouts.backups, charKey() or "?"
    all[key] = all[key] or {}
    return all[key]
end

-- Loads parts (L.ALL when nil) of a loadout, keeping what you have now as a backup first. Returns as L.apply does.
function L.load(lo, parts, characterSet)
    if InCombatLockdown() then return nil, COMBAT end
    parts = parts or L.ALL
    if lo.off and not lo.backup then -- parts turned off in the loadout are skipped
        local on = {}
        for part, v in pairs(parts) do on[part] = v and not lo.off[part] or nil end
        if not next(on) then return nil, "the parts you picked are off in this loadout" end
        parts = on
    end
    local full = parts.macros and L.macroRoom(lo)
    if full then return nil, full end
    local backup, list = L.capture(true), L.backups()
    backup.name, backup.backup, backup.parts = "Before " .. lo.name, true, {}
    -- the slots this load leaves, a restore leaves too: past what either the backup or lo holds
    backup.ignored = copy(lo.ignored)
    backup.lastSlot = math.min(backup.lastSlot or L.SLOTS, lo.lastSlot or L.SLOTS)
    if backup.lastSlot == L.SLOTS then backup.lastSlot = nil end
    backup.bindingSet = GetCurrentBindingSet and GetCurrentBindingSet() -- a restore puts the set back too
    backup.switchedSet = characterSet and parts.bindings and backup.bindingSet == ACCOUNT_SET or nil
    for part, on in pairs(parts) do backup.parts[part] = on end -- a restore puts back only what this load changes
    for name in pairs(L.cvarNames()) do -- every setting, defaults too, so a restore can set them back
        backup.cvars[name] = backup.cvars[name] or (C_CVar.GetCVarInfo(name))
    end
    local pending = L.pending()
    if pending then
        backup.pending = {}
        for slot, name in pairs(pending) do backup.pending[slot] = name end
    end
    for _, b in ipairs(list) do
        if b == lo then backup.name = "Before restoring" end -- not "Before Before ..."
    end
    tinsert(list, 1, backup)
    for i = #list, L.BACKUPS + 1, -1 do list[i] = nil end
    local report, why = L.apply(lo, parts, characterSet)
    if report then -- what a restore must undo besides putting back what was there
        report.parts = parts
        backup.madeMacros = report.madeMacros
        backup.boundMacros = {}
        for command in pairs(parts.bindings and lo.bindings or {}) do
            if command:find("^MACRO ") then tinsert(backup.boundMacros, command) end
        end
    end
    return report, why
end

-- What loading lo's bars does to each slot: changed[slot] when it ends up holding something else than now,
-- waiting[slot] when its spell isn't known yet (the slot is kept free for it)
local function nowHolds(slot)
    local kind, id = GetActionInfo(slot)
    if kind == "macro" then return "macro:" .. tostring(GetActionText(slot) or (GetMacroInfo(id))) end
    return kind and kind .. ":" .. tostring(id)
end
function L.preview(lo)
    local p = {changed = {}, waiting = {}, changes = 0, waits = 0, ignores = 0}
    local macros = {} -- loading the macros makes these (none while its Macros are off: a missing one isn't placed)
    for _, m in ipairs(L.partOn(lo, "macros") and lo.macros or {}) do macros[m.name] = true end
    for _, slot in ipairs(L.slots()) do
        local a, holds = lo.actions[slot], nil
        if L.ignores(lo, slot) then
            holds, p.ignores = nowHolds(slot), p.ignores + 1 -- loading leaves it
        elseif a and a.type == "spell" then
            local _, id = L.spellInfo(a.name or a.id)
            if id and known(id) then
                holds = "spell:" .. id
            else
                p.waiting[slot], p.waits = true, p.waits + 1
            end
        elseif a and a.type == "macro" and (macros[a.name] or (GetMacroIndexByName(a.name) or 0) > 0) then
            holds = "macro:" .. a.name
        elseif a and a.type == "item" then
            holds = "item:" .. tostring(a.id)
        elseif a and a.type == "summonmount" then
            holds = "summonmount:" .. tostring(a.id)
        elseif a and a.type ~= "macro" and a.type ~= "spell" then
            holds = nowHolds(slot) -- what loading can't put back, it leaves
        end
        if lo.backup and unplaceable(slot) then holds = nowHolds(slot) end -- a restore leaves it
        if holds ~= nowHolds(slot) then p.changed[slot], p.changes = true, p.changes + 1 end
    end
    return p
end

-- Editing a saved loadout: each edit changes it in KureqUtilsDB at once (your character changes only on Load). The
-- first edit of a loadout keeps a copy of it, so Revert changes can put it back until the window closes.
L.MACRO_TEXT, L.MACRO_NAME = 255, 16
L.MACRO_CAPS = {character = CHARACTER_MACROS, account = ACCOUNT_MACROS}
local before = {} -- loadout -> its copy from before this window session's first edit
local function track(lo)
    if not before[lo] then
        before[lo] = copy(lo)
        lo.updated = time()
    end
end
function L.edited(lo) return before[lo] ~= nil end
function L.revert(lo)
    local old = before[lo]
    if not old then return end
    for k in pairs(lo) do lo[k] = nil end
    for k, v in pairs(copy(old)) do lo[k] = v end
    before[lo] = nil
end
function L.endEdits() wipe(before) end

function L.scope(m) return m.account and "account" or "character" end
-- how many of lo's macros are character and account ones
function L.macroCounts(lo)
    local n = {character = 0, account = 0}
    for _, m in ipairs(lo.macros) do n[L.scope(m)] = n[L.scope(m)] + 1 end
    return n
end
function L.findMacro(lo, name)
    for i, m in ipairs(lo.macros) do
        if m.name == name then return i, m end
    end
end

-- Why a macro can't be saved as it is (nil when it can): the game's limits, and names unique in the loadout
function L.macroProblem(lo, m, index)
    if type(m.name) ~= "string" or ns.trim(m.name) == "" then return "A macro needs a name." end
    if #m.name > L.MACRO_NAME then return ("A macro's name is %d letters at most."):format(L.MACRO_NAME) end
    local other = L.findMacro(lo, m.name)
    if other and other ~= index then return ("There's already a macro called %s."):format(m.name) end
    if #(m.body or "") > L.MACRO_TEXT then return ("A macro's text is %d characters at most."):format(L.MACRO_TEXT) end
    local scope = L.scope(m)
    local counts = L.macroCounts(lo)
    if not (index and L.scope(lo.macros[index]) == scope) and counts[scope] >= L.MACRO_CAPS[scope] then
        return ("A loadout holds %d %s macros at most."):format(L.MACRO_CAPS[scope], scope)
    end
end

-- A new macro ({name, icon, body, account, kind, options}) at the end; its index, or nil and why not
function L.addMacro(lo, m)
    m.icon, m.body = m.icon or 134400, m.body or ""
    local why = L.macroProblem(lo, m)
    if why then return nil, why end
    track(lo)
    tinsert(lo.macros, m)
    return #lo.macros
end

-- Bindings to a macro use the command "MACRO <name>"
local function moveMacroRefs(lo, old, new)
    for _, a in pairs(lo.actions) do
        if a.type == "macro" and a.name == old then a.name = new end
    end
    for slot, a in pairs(lo.actions) do
        if a.type == "macro" and a.name == nil then lo.actions[slot] = nil end
    end
    local keys = lo.bindings["MACRO " .. old]
    lo.bindings["MACRO " .. old] = nil
    if keys and new then lo.bindings["MACRO " .. new] = keys end
end

-- An account macro renamed outside the editor (KU Ping's KureqPingCustom): every saved loadout and backup, and the
-- editor's copies to revert to, point to it by its new name. A loadout keeping a character macro of the old name
-- leaves its slots and bindings to that one; one that already names new anywhere (a macro of the player's that had
-- that name) is left as it is, its old references then as any to a deleted macro.
function L.renameAccountMacro(old, new)
    local function holds(lo, name)
        for _, list in ipairs({lo.macros or {}, lo.madeMacros or {}}) do
            for _, m in ipairs(list) do if m.name == name then return true end end
        end
        for _, a in pairs(lo.actions or {}) do if a.type == "macro" and a.name == name then return true end end
        if lo.bindings and lo.bindings["MACRO " .. name] then return true end
        for _, command in ipairs(lo.boundMacros or {}) do if command == "MACRO " .. name then return true end end
    end
    local function each(lo)
        if type(lo) ~= "table" or holds(lo, new) then return end
        local charHas
        for _, m in ipairs(lo.macros or {}) do
            if m.name == old then if m.account then m.name = new else charHas = true end end
        end
        for _, m in ipairs(lo.madeMacros or {}) do -- a restore deletes these
            if m.account and m.name == old then m.name = new end
        end
        if charHas then return end
        if lo.actions and lo.bindings then moveMacroRefs(lo, old, new) end
        for i, command in ipairs(lo.boundMacros or {}) do
            if command == "MACRO " .. old then lo.boundMacros[i] = "MACRO " .. new end
        end
    end
    local db = ns.db.loadouts
    for _, lo in pairs(db.list or {}) do each(lo) end
    for _, list in pairs(db.backups or {}) do
        for _, lo in ipairs(type(list) == "table" and list or {}) do each(lo) end
    end
    for _, lo in pairs(before) do each(lo) end
end

-- Changes macro i (fields: name, icon, body, account, kind, options; options = false drops them). Renaming moves
-- every slot and binding that pointed to it. Returns true, or nil and why not.
function L.setMacro(lo, i, fields)
    local m = lo.macros[i]
    if not m then return nil end
    local new = copy(m)
    for k, v in pairs(fields) do
        if v == false and (k == "kind" or k == "options" or k == "account") then new[k] = nil else new[k] = v end
    end
    local why = L.macroProblem(lo, new, i)
    if why then return nil, why end
    track(lo)
    if new.name ~= m.name then moveMacroRefs(lo, m.name, new.name) end
    lo.macros[i] = new
    return true
end

-- Deletes macro i, and clears the slots and bindings that pointed to it
function L.deleteMacro(lo, i)
    local m = lo.macros[i]
    if not m then return end
    track(lo)
    table.remove(lo.macros, i)
    moveMacroRefs(lo, m.name, nil)
end

-- Moves macro i by step (-1 up, 1 down); the new index
function L.moveMacro(lo, i, step)
    local j = i + step
    if not (lo.macros[i] and lo.macros[j]) then return i end
    track(lo)
    lo.macros[i], lo.macros[j] = lo.macros[j], lo.macros[i]
    return j
end

-- Editing a slot past the ones lo was saved with (bars 6 to 8 on an older loadout) takes them in as ignored slots
-- marked UNSAVED, so loading still leaves the rest of them. Each edited slot drops its mark (a slot you ignored stays).
local function widen(lo, slot)
    if slot > (lo.lastSlot or L.SLOTS) then
        lo.ignored = lo.ignored or {}
        for s = math.max(L.FIRST_EXTRA, (lo.lastSlot or 0) + 1), L.maxSlot() do
            lo.ignored[s] = lo.ignored[s] or UNSAVED
        end
        lo.lastSlot = L.maxSlot()
    end
    if lo.ignored and lo.ignored[slot] == UNSAVED then
        lo.ignored[slot] = nil -- an empty table stays: L.setIgnored is still using it
    end
end

-- Bars: an action ({type, id, name}) or nil on a slot, and two slots swapped
function L.setSlot(lo, slot, action)
    if not L.isSlot(slot) then return end
    track(lo)
    widen(lo, slot)
    lo.actions[slot] = action
end
-- Clear: the slots load as empty; an ignored slot (or one not saved) stays so, holding nothing
function L.clearSlots(lo, slots)
    for _, slot in ipairs(slots) do
        if lo.actions[slot] then
            track(lo) -- only a real change counts as an edit
            lo.actions[slot] = nil
        end
    end
end
function L.swapSlots(lo, a, b)
    if a == b then return end
    track(lo)
    widen(lo, a)
    widen(lo, b)
    lo.actions[a], lo.actions[b] = lo.actions[b], lo.actions[a]
end

-- Bindings: key bound to command (replacing its key old, if given; a third key replaces the second). A key bound to
-- another command moves; that command is returned.
local function dropKey(lo, command, key)
    local keys = lo.bindings[command]
    if not keys then return false end
    for j = #keys, 1, -1 do
        if keys[j] == key then table.remove(keys, j) end
    end
    if #keys == 0 then lo.bindings[command] = nil end
    return true
end
function L.bind(lo, command, key, old)
    track(lo)
    local from
    for c, keys in pairs(lo.bindings) do
        for _, k in ipairs(keys) do
            if k == key and c ~= command then from = c end
        end
    end
    if from then dropKey(lo, from, key) end
    local keys = lo.bindings[command] or {}
    lo.bindings[command] = keys
    for j = #keys, 1, -1 do
        if keys[j] == key then table.remove(keys, j) end
    end
    for j, k in ipairs(keys) do
        if k == old then keys[j], old = key, nil end
    end
    if old or not (keys[1] == key or keys[2] == key) then
        keys[math.min(#keys + 1, 2)] = key
    end
    return from
end
function L.unbind(lo, command, key)
    if lo.bindings[command] then
        track(lo)
        dropKey(lo, command, key)
    end
end

-- Parts: lo.off[part] = true keeps a part (actions, macros, bindings, cvars) in the loadout but Load and Update from
-- current skip it. Absent means on, so older loadouts and imports load everything.
function L.partOn(lo, part) return not (lo.off and lo.off[part]) end
function L.setPartOn(lo, part, on)
    if L.partOn(lo, part) == on or not L.ALL[part] then return end
    track(lo)
    lo.off = lo.off or {}
    lo.off[part] = not on or nil
    if not next(lo.off) then lo.off = nil end
end
-- Clear all of a part; deleting the macros clears the slots and keys using them, as deleting one does
function L.clearPart(lo, part)
    if part == "macros" then
        while #lo.macros > 0 do L.deleteMacro(lo, #lo.macros) end
    elseif L.ALL[part] and (next(lo[part]) or part == "cvars" and lo.bars) then
        track(lo)
        lo[part] = {}
        if part == "cvars" then lo.bars = nil end -- the bar toggles load with the Blizzard settings
    end
end

-- Ignored slots: loading never touches them. on (true or false) for each slot in slots.
function L.setIgnored(lo, slots, on)
    track(lo)
    lo.ignored = lo.ignored or {}
    for _, slot in ipairs(slots) do
        if L.isSlot(slot) then
            if not on then widen(lo, slot) end
            lo.ignored[slot] = on or nil
        end
    end
    if not next(lo.ignored) then lo.ignored = nil end
end

-- Settings: only ones the loadout already holds. 0/1 stay 0/1, numbers stay numbers. Returns true, or nil and why.
function L.settingKind(value)
    if value == "0" or value == "1" then return "toggle" end
    return tonumber(value) and "number" or "text"
end
function L.setSetting(lo, name, value)
    local old = lo.cvars[name]
    if old == nil then return nil end
    value = ns.trim(tostring(value))
    local kind = L.settingKind(old)
    if kind == "toggle" and value ~= "0" and value ~= "1" then return nil, "Use 0 or 1." end
    if kind == "number" and not tonumber(value) then return nil, "That Blizzard setting takes a number." end
    if #value > 256 then return nil, "That's too long for a Blizzard setting." end
    if value ~= old then
        track(lo)
        lo.cvars[name] = value
    end
    return true
end
-- A readable name for the common settings, else the setting's own name
local SETTING_NAMES = {
    autoLootDefault = "Auto loot", autoSelfCast = "Auto self cast", lootUnderMouse = "Open loot window at mouse",
    interactOnLeftClick = "Interact on left click", autoDismountFlying = "Auto dismount", autoClearAFK = "Clear AFK when moving",
    nameplateShowEnemies = "Enemy nameplates", nameplateShowFriends = "Friendly nameplates",
    nameplateShowAll = "Always show nameplates", showTargetOfTarget = "Target of target",
    autoQuestWatch = "Track quests automatically", autoQuestProgress = "Track quests when they progress",
    chatBubbles = "Chat bubbles", chatBubblesParty = "Party chat bubbles", chatStyle = "Chat style",
    showTutorials = "Tutorials", ActionButtonUseKeyDown = "Cast on key down", deselectOnClick = "Sticky targeting",
    cameraDistanceMaxZoomFactor = "Camera zoom distance", cameraSmoothStyle = "Camera follow style",
    autoRangedCombat = "Auto ranged attack", stopAutoAttackOnTargetChange = "Stop attacking on a new target",
    assistAttack = "Attack on assist", showLootSpam = "Loot messages", UnitNameOwn = "My name",
    UnitNameFriendlyPlayerName = "Friendly player names", UnitNameEnemyPlayerName = "Enemy player names",
    UnitNameNPC = "NPC names", lockActionBars = "Lock action bars", alwaysShowActionBars = "Always show action bars",
    countdownForCooldowns = "Cooldown numbers", scriptErrors = "Show Lua errors",
    enableFloatingCombatText = "Floating combat text",
}
function L.settingName(name) return SETTING_NAMES[name] or name end

-- An icon as SetTexture takes it: a file ID, or an icon's file name from the macro icon list
function L.iconPath(icon)
    if type(icon) == "string" and not icon:find("\\", 1, true) then return "Interface\\Icons\\" .. icon end
    return icon or 134400
end

-- "Any class": loads on any class without the other-class warning (spells it can't use wait or are left out as ever)
function L.setAnyClass(lo, on)
    track(lo)
    lo.anyClass = on and true or nil
end

function L.removeSetting(lo, name)
    if lo.cvars[name] == nil then return end
    track(lo)
    lo.cvars[name] = nil
end

-- Ready-made macros: a kind and its options write the text. Options are flat (strings, booleans), so a shared
-- loadout stays readable by older versions; a cast sequence's spells are one comma-separated string.
local function spellOf(o) return ns.trim(o.spell or "") end
L.READY = {
    {kind = "mouseover", name = "Mouseover cast", icon = 135907, options = {"spell", "target"},
        text = "Casts on the unit under your mouse, else on your target (a friendly spell falls back to you).",
        make = function(o) -- "exists" too: [@mouseover,help,nodead] alone often isn't enough (user's macro)
            local on = o.target == "harm" and "harm" or "help"
            return ("#showtooltip\n/cast [@mouseover,%s,nodead,exists][@target,%s,nodead,exists]%s[] %s")
                :format(on, on, on == "help" and "[@player]" or "", spellOf(o))
        end},
    {kind = "focus", name = "Focus", icon = 132212, options = {"focus", "spell"},
        text = "Sets your focus to your mouseover or target, or casts a spell on your focus.",
        make = function(o)
            if o.focus == "cast" then return ("#showtooltip\n/cast [@focus,exists,nodead][] %s"):format(spellOf(o)) end
            return "/focus [@mouseover,exists][]"
        end},
    {kind = "sequence", name = "Cast sequence", icon = 132147, options = {"spells", "reset"},
        text = "Casts the spells in turn, one per press, starting over on the reset.",
        make = function(o)
            local list = {}
            for s in (o.spells or ""):gmatch("[^,\n]+") do
                if ns.trim(s) ~= "" then list[#list + 1] = ns.trim(s) end
            end
            local reset = ns.trim(o.reset or "")
            return ("#showtooltip\n/castsequence %s%s"):format(reset ~= "" and "reset=" .. reset .. " " or "",
                table.concat(list, ", "))
        end},
    {kind = "trinket", name = "Use trinket and cast", icon = 133434, options = {"slot13", "slot14", "spell"},
        text = "Uses your trinkets, then casts the spell.",
        make = function(o)
            local out = {"#showtooltip " .. spellOf(o)}
            if o.slot13 then out[#out + 1] = "/use 13" end
            if o.slot14 then out[#out + 1] = "/use 14" end
            out[#out + 1] = "/cast " .. spellOf(o)
            return table.concat(out, "\n")
        end},
    {kind = "stopcast", name = "Stop casting and cast", icon = 132219, options = {"spell"},
        text = "Stops what you're casting and casts the spell: for interrupts.",
        make = function(o) return ("#showtooltip\n/stopcasting\n/cast %s"):format(spellOf(o)) end},
    {kind = "startattack", name = "Start attack and cast", icon = 132349, options = {"spell"},
        text = "Starts your melee attack and casts the spell: for openers.",
        make = function(o) return ("#showtooltip\n/startattack\n/cast %s"):format(spellOf(o)) end},
    {kind = "pet", name = "Pet attack / follow", icon = 132270, options = {"pet"},
        text = "Sends your pet at your mouseover or target, or calls it back.",
        make = function(o)
            if o.pet == "follow" then return "/petfollow" end
            return "/petattack [@mouseover,harm,nodead][]"
        end},
}
-- Class templates: shown first in the macros window (MacrosWindow.lua) for their class, not in a loadout's gallery.
-- defaults fill their options before the shared ones.
local function mouseoverHeal(class, spell)
    return {kind = "heal" .. class:lower(), class = class, name = "Mouseover heal", icon = 135907, options = {"spell"},
        defaults = {spell = spell}, text = "Heals the friend under your mouse, else your friendly target, else you.",
        make = function(o) return L.READY.mouseover.make({spell = o.spell, target = "help"}) end}
end
for _, r in ipairs({
    {kind = "shardcast", class = "WARLOCK", name = "Soul Shard cast", icon = 134075, options = {"spell"},
        defaults = {spell = "Create Healthstone"},
        text = "Casts a spell that takes a Soul Shard, and says so on screen when you have none left.",
        make = function(o)
            return ('#showtooltip %s\n/run if C_Item.GetItemCount(6265) == 0 then UIErrorsFrame:AddMessage("No Soul '
                .. 'Shards", 1, 0.1, 0.1) end\n/cast %s'):format(spellOf(o), spellOf(o))
        end},
    {kind = "warlockpet", class = "WARLOCK", name = "Demon attack and cast", icon = 136218, options = {"spell"},
        defaults = {spell = "Corruption"},
        text = "Sends your demon at your mouseover or target and casts the spell on it.",
        make = function(o)
            return ("#showtooltip\n/petattack [@mouseover,harm,nodead,exists][]\n/cast [@mouseover,harm,nodead,exists][] %s")
                :format(spellOf(o))
        end},
    {kind = "autoshot", class = "HUNTER", name = "Auto Shot and cast", icon = 132222, options = {"spell"},
        defaults = {spell = "Arcane Shot"}, text = "Starts Auto Shot (without turning it off) and casts the spell.",
        make = function(o) return ("#showtooltip\n/cast !Auto Shot\n/cast %s"):format(spellOf(o)) end},
    mouseoverHeal("PRIEST", "Flash Heal"), mouseoverHeal("PALADIN", "Flash of Light"),
    mouseoverHeal("DRUID", "Healing Touch"), mouseoverHeal("SHAMAN", "Healing Wave"),
}) do L.READY[#L.READY + 1] = r end
for _, r in ipairs(L.READY) do L.READY[r.kind] = r end
-- Each option: what it is (spell, choice, check or text), its label, its choices and its default
L.READY_OPTIONS = {
    spell = {type = "spell", label = "Spell", default = ""},
    target = {type = "choice", label = "Cast on", default = "help",
        choices = {{"help", "Friendly (heals, buffs)"}, {"harm", "Enemy (attacks)"}}},
    focus = {type = "choice", label = "Does", default = "set", choices = {{"set", "Set focus"}, {"cast", "Cast on focus"}}},
    spells = {type = "text", label = "Spells, in order", default = "", prompt = "Spell, Spell, Spell"},
    reset = {type = "choice", label = "Starts over", default = "target", choices = {{"target", "On a new target"},
        {"combat", "After combat"}, {"5", "After 5 seconds"}, {"10", "After 10 seconds"}, {"30", "After 30 seconds"}}},
    slot13 = {type = "check", label = "Top trinket (13)", default = true},
    slot14 = {type = "check", label = "Bottom trinket (14)", default = false},
    pet = {type = "choice", label = "Pet", default = "attack", choices = {{"attack", "Attack"}, {"follow", "Follow"}}},
    after = {type = "text", label = "Typed after it", default = "", prompt = "Optional"}, -- a /ku command's words
}
-- A ready-made macro's options, filled with the defaults (the kind's own first)
function L.readyOptions(kind, options)
    local o, r = {}, L.READY[kind]
    for _, key in ipairs(r.options) do
        local v = options and options[key]
        if v == nil and r.defaults then v = r.defaults[key] end
        if v == nil then v = L.READY_OPTIONS[key].default end
        o[key] = v
    end
    return o
end
-- The text a ready-made macro of kind writes with options, or nil for an unknown kind
function L.readyText(kind, options)
    local r = L.READY[kind]
    return r and r.make(options or {})
end

-- The spell names a macro's /cast, /castsequence and #showtooltip lines name that you don't know (by name, any rank)
function L.unknownSpells(body)
    local missing, seen = {}, {}
    for line in (body or ""):gmatch("[^\n]+") do
        local cmd, rest = line:match("^%s*([#/]%a+)%s*(.*)$")
        cmd = cmd and cmd:lower()
        if cmd == "/cast" or cmd == "/castsequence" or cmd == "#showtooltip" then
            rest = rest:gsub("%b[]", ""):gsub("reset=%S+", "")
            for part in rest:gmatch("[^;,]+") do
                local name = ns.trim(part)
                name = name:gsub("%(.-%)$", "") -- "Holy Light(Rank 2)"
                name = ns.trim(name)
                if name ~= "" and not tonumber(name) and not seen[name] then
                    seen[name] = true
                    if not L.spellInfo(name) then missing[#missing + 1] = name end
                end
            end
        end
    end
    return missing
end

-- Sharing: a loadout as one line of text, "KU1:" and its table. Strings are quoted, with %XX for " and % and for
-- anything outside printable ASCII; numbers are n<number>; booleans T and F; tables {key value key value ...}.
-- A loadout using what versions before editing don't know (account macros, ready-made macros, more than 36 macros)
-- starts "KU2:" instead, the same format, so those versions refuse it rather than load part of it. One for any class
-- or with ignored slots starts "KU3:", so versions reading only KU2 refuse it rather than load over ignored slots.
local PREFIX, PREFIX2, PREFIX3, OLD_MACROS = "KU1:", "KU2:", "KU3:", 36
local function needsKU3(lo)
    return lo.anyClass or lo.ignored and next(lo.ignored) ~= nil or lo.rules and #lo.rules > 0
end
local function needsKU2(lo)
    if #lo.macros > OLD_MACROS then return true end
    for _, m in ipairs(lo.macros) do
        if m.account or m.kind or m.options then return true end
    end
end
L.MAX_IMPORT = 200 * 1024
local NOT_A_LOADOUT = "That text isn't a loadout."
local function encode(v, out)
    local t = type(v)
    if t == "string" then
        out[#out + 1] = '"' .. v:gsub('[^ !#$&-~]', function(c) return ("%%%02X"):format(c:byte()) end) .. '"'
    elseif t == "number" then
        out[#out + 1] = ("n%.17g;"):format(v)
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "table" then
        out[#out + 1] = "{"
        for k, x in pairs(v) do
            encode(k, out)
            encode(x, out)
        end
        out[#out + 1] = "}"
    end
end
function L.export(lo)
    local out = {}
    encode({name = lo.name, class = lo.class, className = lo.className, from = lo.from, created = lo.created,
        actions = lo.actions, macros = lo.macros, bindings = lo.bindings, cvars = lo.cvars, bars = lo.bars,
        anyClass = lo.anyClass, ignored = lo.ignored, rules = lo.rules, lastSlot = lo.lastSlot, off = lo.off}, out)
    return (needsKU3(lo) and PREFIX3 or needsKU2(lo) and PREFIX2 or PREFIX) .. table.concat(out)
end

-- Reads the text as data only, never as code: a value, or an error. Depth and size are capped.
local function decode(s)
    local pos, nodes = 1, 0
    local function value(depth)
        nodes = nodes + 1
        assert(nodes <= 20000 and depth <= 5)
        local c = s:sub(pos, pos)
        if c == '"' then
            local close = assert(s:find('"', pos + 1, true))
            local raw = s:sub(pos + 1, close - 1)
            pos = close + 1
            assert(not raw:gsub("%%%x%x", ""):find("%", 1, true)) -- a lone % isn't ours
            return (raw:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
        elseif c == "n" then
            local stop = assert(s:find(";", pos, true))
            local n = tonumber(s:sub(pos + 1, stop - 1))
            assert(n and n == n and n > -math.huge and n < math.huge and stop - pos <= 32)
            pos = stop + 1
            return n
        elseif c == "T" or c == "F" then
            pos = pos + 1
            return c == "T"
        elseif c == "{" then
            pos = pos + 1
            local t = {}
            while s:sub(pos, pos) ~= "}" do
                local k = value(depth + 1)
                assert(type(k) == "string" or type(k) == "number")
                t[k] = value(depth + 1)
            end
            pos = pos + 1
            return t
        end
        error("not a value")
    end
    local v = value(1)
    assert(pos == #s + 1)
    return v
end

-- Only the fields a loadout has, of the right types and sizes; nil when anything is off
local function str(v, max) return type(v) == "string" and #v <= max end
local function int(v, lo, hi) return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi end
-- a slot of bars 1 to 5, the stance bars or bars 6 to 8, whether or not this client has them
local function barSlot(v) return int(v, 1, L.MAX_SLOT) and (v <= L.SLOTS or v >= L.FIRST_EXTRA) end
local function size(t, max)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n <= max and n
end
-- A ready-made macro's options as each takes them (a choice it offers, a true/false, a short text), else nil.
-- Options it doesn't have are left out.
local function readyOptionsOf(kind, options)
    if type(options) ~= "table" or not size(options, 16) then return nil end
    local o = {}
    for _, key in ipairs(L.READY[kind].options) do
        local v, spec = options[key], L.READY_OPTIONS[key]
        if v ~= nil then
            local ok = spec.type == "check" and type(v) == "boolean" or (spec.type == "spell" or spec.type == "text")
                and str(v, 200)
            for _, c in ipairs(spec.type == "choice" and spec.choices or {}) do ok = ok or c[1] == v end
            if not ok then return nil end
            o[key] = v
        end
    end
    return o
end
local function check(t)
    if type(t) ~= "table" then return nil end
    for _, part in ipairs({"actions", "macros", "bindings", "cvars"}) do
        if type(t[part]) ~= "table" then return nil end
    end
    local lo = {actions = {}, macros = {}, bindings = {}, cvars = {}}
    for _, k in ipairs({"name", "class", "className", "from"}) do
        if t[k] ~= nil and not str(t[k], 60) then return nil end
        lo[k] = t[k]
    end
    if t.created ~= nil and not int(t.created, 0, 2 ^ 40) then return nil end
    lo.created = t.created or time()
    if t.anyClass ~= nil and type(t.anyClass) ~= "boolean" then return nil end
    lo.anyClass = t.anyClass or nil
    if t.ignored ~= nil then
        if type(t.ignored) ~= "table" or not size(t.ignored, L.MAX_SLOT) then return nil end
        lo.ignored = {}
        for slot, on in pairs(t.ignored) do
            if not (barSlot(slot) and (on == true or on == UNSAVED)) then return nil end
            lo.ignored[slot] = on
        end
        if not next(lo.ignored) then lo.ignored = nil end
    end
    if t.rules ~= nil then -- each rule checked field by field; their ids are given on import
        if type(t.rules) ~= "table" or size(t.rules, L.MAX_RULES) ~= #t.rules then return nil end
        lo.rules = {}
        local TRIGGER = {new = true, login = true, level = true, spell = true}
        for i, r in ipairs(t.rules) do
            if not (type(r) == "table" and TRIGGER[r.trigger] and (r.level == nil or int(r.level, 1, 100))
                and (r.spell == nil or str(r.spell, 100)) and (r.names == nil or str(r.names, 500))
                and (r.classes == nil or type(r.classes) == "table" and size(r.classes, 20))) then return nil end
            local rule = {trigger = r.trigger, level = r.level, spell = r.spell, names = r.names,
                except = r.except == true or nil, ask = r.ask == true or nil}
            for class, on in pairs(r.classes or {}) do
                if not (str(class, 20) and class:find("^%u+$") and on == true) then return nil end
                rule.classes = rule.classes or {}
                rule.classes[class] = true
            end
            lo.rules[i] = rule
        end
        if #lo.rules == 0 then lo.rules = nil end
    end
    if t.off ~= nil then -- parts turned off; versions before this ignore it and load them
        if type(t.off) ~= "table" or not size(t.off, 4) then return nil end
        for part, on in pairs(t.off) do
            if not (type(part) == "string" and L.ALL[part] and on == true) then return nil end
            lo.off = lo.off or {}
            lo.off[part] = true
        end
    end
    -- bars 6 to 8 come in on any client; one without them never loads them
    if t.lastSlot ~= nil and not int(t.lastSlot, L.SLOTS, L.MAX_SLOT) then return nil end
    lo.lastSlot = t.lastSlot
    if not size(t.actions, L.MAX_SLOT) then return nil end
    for slot, a in pairs(t.actions) do
        if not (barSlot(slot) and type(a) == "table" and str(a.type, 32) and a.type:find("^%a+$")
            and (a.id == nil or int(a.id, 0, 2 ^ 31)) and (a.name == nil or str(a.name, 255))) then return nil end
        if (a.type == "spell" and not (a.name or a.id)) or (a.type == "macro" and not a.name)
            or (a.type == "item" and not a.id) then return nil end
        lo.actions[slot] = {type = a.type, id = a.id, name = a.name}
    end
    local macros = size(t.macros, CHARACTER_MACROS + ACCOUNT_MACROS)
    if not macros or macros ~= #t.macros then return nil end
    for i, m in ipairs(t.macros) do
        if not (type(m) == "table" and str(m.name, 64) and m.name ~= "" and str(m.body, 1024)
            and (int(m.icon, 0, 2 ^ 31) or str(m.icon, 255))) then return nil end
        lo.macros[i] = {name = m.name, icon = m.icon, body = m.body, account = m.account == true or nil}
        -- a ready-made macro's kind and options: kept when known and well formed, else left out (fields this
        -- version doesn't know are left out too)
        local o = L.READY[m.kind] and readyOptionsOf(m.kind, m.options)
        if o then lo.macros[i].kind, lo.macros[i].options = m.kind, o end
    end
    if not size(t.bindings, 1000) then return nil end
    for command, keys in pairs(t.bindings) do
        if not (str(command, 128) and type(keys) == "table") then return nil end
        lo.bindings[command] = {}
        for i, key in pairs(keys) do
            if not (int(i, 1, 2) and str(key, 64)) then return nil end
            lo.bindings[command][i] = key
        end
    end
    if not size(t.cvars, 500) then return nil end
    local allowed = L.cvarNames() -- only the settings a loadout of yours could hold
    for name, value in pairs(t.cvars) do
        if not (str(name, 64) and str(value, 256)) then return nil end
        if allowed[name] then lo.cvars[name] = value end
    end
    if t.bars ~= nil then
        if type(t.bars) ~= "table" or size(t.bars, 8) ~= #t.bars then return nil end
        lo.bars = {}
        for i, on in ipairs(t.bars) do
            if type(on) ~= "boolean" then return nil end
            lo.bars[i] = on
        end
    end
    return lo
end

-- A loadout from shared text, or nil and why not
function L.decode(text)
    if type(text) ~= "string" or #text > L.MAX_IMPORT then return nil, NOT_A_LOADOUT end
    text = text:gsub("[\r\n]", "") -- a paste may wrap the line
    local prefix = text:sub(1, #PREFIX)
    if prefix ~= PREFIX and prefix ~= PREFIX2 and prefix ~= PREFIX3 then return nil, NOT_A_LOADOUT end
    local ok, t = pcall(decode, text:sub(#PREFIX + 1))
    local lo = ok and check(t)
    if not lo then return nil, NOT_A_LOADOUT end
    return lo
end

-- A new loadout from shared text, named name (or as it was shared); returns its id, or nil and why not
function L.import(text, name)
    local lo, why = L.decode(text)
    if not lo then return nil, why end
    lo.name = name ~= nil and name ~= "" and name or lo.name ~= "" and lo.name or "Imported"
    lo.updated = time()
    lo.rules = L.rulesOff(lo.rules) -- shared rules come in off: you turn on the ones you want
    local db = ns.db.loadouts
    local id = db.nextId
    db.nextId = id + 1
    db.list[id] = lo
    return id
end

-- Waiting spells go on when learned (the slot still free), at the highest rank; out of combat
function L.fillPending()
    local pending = L.pending()
    if not pending then return end
    if InCombatLockdown() then
        ns.CombatQueue.Defer("loadouts", function() if ns.db and ns.IsOn("loadouts") then L.fillPending() end end)
        return
    end
    for slot, name in pairs(pending) do
        local _, id = L.spellInfo(name)
        if GetActionInfo(slot) then
            pending[slot] = nil -- you've put something else there
        elseif id and known(id) then
            ClearCursor()
            pickupSpell(id)
            place(slot)
            pending[slot] = nil
            ns.say("placed %s on your action bar (slot %d), as your loadout had it.", name, slot)
        end
    end
    if not next(pending) then ns.db.loadouts.pending[charKey()] = nil end
    if L.changed then L.changed() end
end

-- Apply automatically: each loadout's rules ({id, trigger, level, spell, classes, names, except, ask, off}) load it
-- by themselves. A trigger: "new" (a new character: a level 1 character's first login, decided once per character,
-- KureqUtilsCharDB.loadoutsDefaultDone; by itself only with 0 XP and no earlier record in Kureq Utils, else it asks),
-- "login" (every real login, never a reload; nothing when loading would change nothing), "level" (reaching exactly
-- that level) or "spell" (learning that spell, by name). Level and spell fire once per character per rule
-- (KureqUtilsCharDB.loadoutRules[id]). classes (none = any) and names (only these, or all but these when except)
-- narrow it; ask asks first; off turns it off. Rules firing together apply in the list's order, out of combat, each
-- after a backup, with the bindings in the character's own key set.
L.TRIGGERS = {{"new", "New character"}, {"login", "Every login"}, {"level", "Reaching level"},
    {"spell", "Learning a spell"}}
L.MAX_RULES = 10
-- the loadouts in the list's order: newest first
function L.sorted()
    local out = {}
    for id, lo in pairs(L.list()) do out[#out + 1] = {id = id, lo = lo} end
    table.sort(out, function(a, b)
        local ta, tb = a.lo.updated or a.lo.created, b.lo.updated or b.lo.created
        if ta ~= tb then return ta > tb end
        return a.id > b.id
    end)
    return out
end
local function newRuleId()
    local db = ns.db.loadouts
    db.nextRule = (db.nextRule or 0) + 1
    return db.nextRule
end
-- a copy of lo's rules with new ids, all off (a clone or an import doesn't load by itself until you turn it on)
function L.rulesOff(rules)
    if not rules then return nil end
    local out = copy(rules)
    for _, r in ipairs(out) do r.id, r.off = newRuleId(), true end
    return out
end
local function spellKnown(name)
    local _, id = L.spellInfo(ns.trim(name or ""))
    return id ~= nil and known(id)
end
local seen = {} -- rule id -> whether its spell was known when last looked at, this session
function L.addRule(lo)
    lo.rules = lo.rules or {}
    if #lo.rules >= L.MAX_RULES then return nil, ("A loadout holds %d rules at most."):format(L.MAX_RULES) end
    track(lo)
    tinsert(lo.rules, {id = newRuleId(), trigger = "new"})
    return #lo.rules
end
-- Changes rule i: fields as in a rule, false clears one. A spell set now that you already know never fires here.
function L.setRule(lo, i, fields)
    local r = lo.rules and lo.rules[i]
    if not r then return end
    track(lo)
    for k, v in pairs(fields) do
        if v == false then r[k] = nil else r[k] = v end
    end
    if r.trigger == "spell" and (fields.spell ~= nil or fields.trigger or fields.off ~= nil) then
        seen[r.id] = spellKnown(r.spell) -- what learning it is measured against
        if seen[r.id] then ns.charDB.loadoutRules[r.id] = true end -- known already: never fires here
    end
end
function L.removeRule(lo, i)
    if not (lo.rules and lo.rules[i]) then return end
    track(lo)
    table.remove(lo.rules, i)
    if #lo.rules == 0 then lo.rules = nil end
end
-- What a rule does, in a few words: "every login", "reaching level 10", "learning Frostbolt"
function L.ruleText(r)
    if r.trigger == "level" then return "reaching level " .. tostring(r.level or "?") end
    if r.trigger == "spell" then return "learning " .. (r.spell and r.spell ~= "" and r.spell or "a spell") end
    return r.trigger == "login" and "every login" or "a new character"
end
function L.hasRules(lo)
    for _, r in ipairs(lo.rules or {}) do
        if not r.off then return true end
    end
    return false
end

local function nameKey(name) return ns.notes and ns.notes.key and ns.notes.key(name) or ns.trim(name):lower() end
-- whether rule r is on and fits this character
local function fits(r)
    if r.off then return false end
    local _, class = UnitClass("player")
    if r.classes and next(r.classes) and not r.classes[class] then return false end
    local names = {}
    for part in (r.names or ""):gmatch("[^,\n]+") do -- two-part names ("Ku Req") stay whole
        if ns.trim(part) ~= "" then names[nameKey(part)] = true end
    end
    if not next(names) then return true end
    local me = ns.notes and ns.notes.unitName and ns.notes.unitName("player") or UnitName("player")
    local listed = me ~= nil and names[nameKey(me)] == true
    if r.except then return not listed end
    return listed
end
-- The loadouts with a rule that fits now and passes test(r), in list order, one rule each: {id, rule}
local function due(test)
    local out, taken = {}, {}
    for _, item in ipairs(L.sorted()) do
        for _, r in ipairs(item.lo.rules or {}) do
            if fits(r) and test(r) and not taken[item.id] then
                taken[item.id] = true
                out[#out + 1] = {id = item.id, rule = r}
            end
        end
    end
    return out
end
local function fired() return ns.charDB.loadoutRules end

-- Whether loading lo (the parts that are on) would change anything here: its bars, macros' text, keys, settings or
-- bar toggles
local function sameKeys(a, b)
    local n = {}
    for _, k in pairs(a or {}) do n[k] = (n[k] or 0) + 1 end
    for _, k in pairs(b or {}) do n[k] = (n[k] or 0) - 1 end
    for _, c in pairs(n) do if c ~= 0 then return false end end
    return true
end
function L.wouldChange(lo)
    local on = function(part) return L.partOn(lo, part) end
    if on("actions") and L.preview(lo).changes > 0 then return true end
    for _, m in ipairs(on("macros") and lo.macros or {}) do
        local i = macroIndex(m.name, m.account)
        if not i or select(3, GetMacroInfo(i)) ~= m.body then return true end
    end
    local now = {}
    for i = 1, GetNumBindings() do
        local command, _, key1, key2 = GetBinding(i)
        if command and (key1 or key2) then now[command] = {key1, key2} end
    end
    for command in pairs(macroCommands(lo)) do
        local keys = macroKeys(command)
        if #keys > 0 then now[command] = keys end
    end
    if on("bindings") then
        for command, keys in pairs(lo.bindings) do
            if not sameKeys(keys, now[command]) then return true end
        end
        for command in pairs(now) do
            if not lo.bindings[command] then return true end
        end
    end
    if not on("cvars") then return false end
    for name, value in pairs(lo.cvars) do
        local v = C_CVar and C_CVar.GetCVarInfo and C_CVar.GetCVarInfo(name)
        if v ~= nil and v ~= value then return true end
    end
    if lo.bars and GetActionBarToggles then
        local t = {GetActionBarToggles()}
        for i, on in ipairs(lo.bars) do
            if (t[i] and true or false) ~= on then return true end
        end
    end
    return false
end

-- Kureq Utils had a record of this character before this login (even an empty one): kill stats, loadout backups or
-- waiting spells. Taken as saved variables load, before any utility starts a record for it (onLoad below, first).
local recorded = {guids = {}, names = {}}
tinsert(ns.onLoad, 1, function(root)
    local loadouts, kills = type(root.loadouts) == "table" and root.loadouts or {}, root.killStats
    for _, part in ipairs({"backups", "pending"}) do
        for guid in pairs(type(loadouts[part]) == "table" and loadouts[part] or {}) do recorded.guids[guid] = true end
    end
    for key in pairs(type(kills) == "table" and kills or {}) do recorded.names[key] = true end
end)
local function knownBefore()
    return recorded.guids[charKey() or "?"] or ns.stats and ns.stats.myKey and recorded.names[ns.stats.myKey()]
        or false
end
-- a new character's rule loads by itself only when it's still fresh: no XP, no earlier record
local function fresh() return not knownBefore() and (UnitXP("player") or 0) == 0 end

-- The rules waiting to apply, in order ({id, rule, ask, answer}); one at a time, asking where it should
local queue = {}
local POPUP = "KUREQUTILS_LOADOUT_RULE"
local step
local function current(item) -- the loadout and rule, if both are still there and on
    local lo = L.list()[item.id]
    for _, r in ipairs(lo and lo.rules or {}) do
        if r == item.rule and not r.off then return lo, r end
    end
end
local function applyRule(lo, r)
    local report, why = L.load(lo, nil, true)
    if report then
        ns.say("loaded %s (its rule: %s). To undo it, restore the newest backup in /ku loadouts.", lo.name,
            L.ruleText(r))
    else
        ns.say("didn't load %s (its rule: %s): %s.", lo.name, L.ruleText(r), why)
    end
    if L.changed then L.changed() end
end
local showing -- the item whose popup is up; the next one shows after it has closed
local function ask(item, lo, r)
    if showing then return end
    showing = item
    StaticPopupDialogs[POPUP] = {
        text = ("Load your loadout %s on this character? Its rule: %s."):format((lo.name:gsub("%%", "%%%%")),
            (L.ruleText(r):gsub("%%", "%%%%"))),
        button1 = "Load", button2 = "Not now", timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function() item.answer = true end,
        OnCancel = function() item.answer = false end,
        OnHide = function()
            if showing ~= item then return end
            showing = nil
            if item.answer == nil then item.answer = false end -- closed some other way: as Not now
            C_Timer.After(0, step)
        end}
    if not StaticPopup_Show(POPUP) then -- every popup frame busy: Blizzard cancels without OnHide, so try again later
        showing, item.answer = nil, nil
        C_Timer.After(5, step)
    end
end
step = function()
    if not ns.IsOn("loadouts") then return wipe(queue) end
    if InCombatLockdown() then return ns.CombatQueue.Defer("loadoutRules", step) end
    while queue[1] do
        local item = queue[1]
        local lo, r = current(item)
        local gone = not lo or not fits(r) or r.trigger == "new" and UnitLevel("player") ~= 1
        if not gone and r.trigger == "new" and not fresh() then item.ask = true end -- no longer fresh: asks
        if gone or r.trigger == "login" and not L.wouldChange(lo) then
            table.remove(queue, 1) -- gone, or nothing left to do
        elseif (item.ask or r.ask) and item.answer == nil then
            return ask(item, lo, r)
        else
            table.remove(queue, 1)
            if item.answer ~= false then applyRule(lo, r) end
        end
    end
end
local function run(items)
    for _, item in ipairs(items) do queue[#queue + 1] = item end
    if #items > 0 then step() end
end

-- Login: new character and every login rules, 3 s after a first login so the starting bars settle
function L.onLogin(isInitialLogin)
    if not isInitialLogin then return end
    local new = not ns.charDB.loadoutsDefaultDone and UnitLevel("player") == 1
        and #due(function(r) return r.trigger == "new" end) > 0
    if new then ns.charDB.loadoutsDefaultDone = true end -- decided once, whatever comes of it
    C_Timer.After(3, function()
        if not ns.IsOn("loadouts") then return end
        run(due(function(r) return r.trigger == "login" or new and r.trigger == "new" end))
    end)
end
function L.onLevel(level)
    local done = fired()
    run(due(function(r)
        if r.trigger ~= "level" or done[r.id] or r.level ~= level then return false end
        done[r.id] = true
        return true
    end))
end
-- a spell rule fires when its spell goes from unknown to known; known when first looked at, it never fires here
function L.onSpells()
    local done = fired()
    run(due(function(r)
        if r.trigger ~= "spell" or done[r.id] then return false end
        local now, was = spellKnown(r.spell), seen[r.id]
        seen[r.id] = now
        if now then done[r.id] = true end
        return now and was == false
    end))
end

local events = CreateFrame("Frame")
for _, e in ipairs({"SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP"}) do
    pcall(events.RegisterEvent, events, e) -- a client without one of them just doesn't send it
end
events:SetScript("OnEvent", function(_, event, arg)
    if not (ns.db and ns.IsOn("loadouts")) then return end
    if event == "PLAYER_ENTERING_WORLD" then
        L.onLogin(arg)
    elseif event == "PLAYER_LEVEL_UP" then
        return L.onLevel(arg)
    end
    L.onSpells()
    L.fillPending()
end)
ns.watch("Loadouts", events)
-- on again: spells learned while off go on now (in combat fillPending waits for it to end)
ns.OnModuleChange("loadouts", function(on)
    if on then return L.fillPending() end
    wipe(queue)
    showing = nil
    StaticPopup_Hide(POPUP)
end)

tinsert(ns.onLoad, function(root)
    local db = root.loadouts
    db.list = type(db.list) == "table" and db.list or {}
    db.pending = type(db.pending) == "table" and db.pending or {}
    db.backups = type(db.backups) == "table" and db.backups or {}
    db.nextId = db.nextId or 1
    -- the single "Default for new characters" of earlier test builds becomes a New character rule
    if type(db.default) == "number" and type(db.list[db.default]) == "table" then
        local lo = db.list[db.default]
        lo.rules = type(lo.rules) == "table" and lo.rules or {}
        tinsert(lo.rules, {id = newRuleId(), trigger = "new"})
    end
    db.default = nil
    local char = ns.charDB
    char.loadoutRules = type(char.loadoutRules) == "table" and char.loadoutRules or {}
end)

ns.AddCommand("loadouts", "/ku loadouts - opens or closes the loadouts window", function() L.toggle() end, "loadouts")

local panel, category = ns.AddSettingsPage("Loadouts",
    "Save your action bars, macros, key bindings and Blizzard settings, and load them on another character.", "loadouts")
L.category = category
ns.Label(panel, "Spells a character doesn't know yet are placed when it learns them.")
ns.Button(panel, "Open loadouts", 160, function() L.toggle() end, "Loadouts window")
