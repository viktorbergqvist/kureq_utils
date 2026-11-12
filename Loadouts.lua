-- Loadouts: save a character's action bars, character macros, key bindings and interface settings under a name, and
-- load them on any character (a new paladin gets your old one's bars). Account-wide, in KureqUtilsDB.loadouts.
-- Spells are kept by name, so loading places the highest rank you know; a spell you don't know yet waits for its
-- slot and goes on when you learn it (pending, per character by GUID). Same-named character macros are replaced,
-- others kept. Nothing changes in combat: Blizzard blocks action bar and binding changes then. Each load first keeps
-- what you had as a backup for this character, and a loadout can be shared as a line of text.
local _, ns = ...
ns.AddModule("loadouts", "Loadouts",
    "Save your action bars, macros, key bindings and settings, and load them on another character.")
local tinsert = table.insert
local L = {}
ns.loadouts = L
ns.defaults.loadouts = {}

L.SLOTS = 120 -- every action slot: the six bars and the stance / form bars
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
function L.itemIcon(id) return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or GetItemIcon and GetItemIcon(id) end

local function charKey() return UnitGUID("player") end
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

-- What you have now, as a loadout (without its name)
function L.capture()
    local lo = {actions = {}, macros = {}, bindings = {}, cvars = {}, created = time()}
    lo.className, lo.class = UnitClass("player")
    lo.from = ns.notes and ns.notes.unitName("player") or UnitName("player")
    for slot = 1, L.SLOTS do
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
    local _, numChar = GetNumMacros()
    for i = ACCOUNT_MACROS + 1, ACCOUNT_MACROS + (numChar or 0) do
        local name, icon, body = GetMacroInfo(i)
        if name then tinsert(lo.macros, {name = name, icon = icon, body = body}) end
    end
    for i = 1, GetNumBindings() do
        local command, _, key1, key2 = GetBinding(i)
        if command and (key1 or key2) then lo.bindings[command] = {key1, key2} end
    end
    for name in pairs(L.cvarNames()) do
        local value, default = C_CVar.GetCVarInfo(name)
        if value ~= default then lo.cvars[name] = value end
    end
    if GetActionBarToggles then lo.bars = {GetActionBarToggles()} end
    return lo
end

function L.counts(lo)
    local actions, bindings, cvars = 0, 0, 0
    for _ in pairs(lo.actions) do actions = actions + 1 end
    for _ in pairs(lo.bindings) do bindings = bindings + 1 end
    for _ in pairs(lo.cvars) do cvars = cvars + 1 end
    return actions, #lo.macros, bindings, cvars
end

function L.save(name, id) -- a new loadout, or id's replaced; returns its id
    local lo = L.capture()
    lo.name = name
    local db = ns.db.loadouts
    if id and db.list[id] then
        lo.created = db.list[id].created
        lo.updated = time()
    else
        id = db.nextId
        db.nextId = id + 1
    end
    db.list[id] = lo
    return id
end

local function place(slot) PlaceAction(slot); ClearCursor() end
-- a slot holding something loading can't put back (a mount, a pet, a companion): a restore leaves it alone
local PLACEABLE = {spell = true, macro = true, item = true}
local function unplaceable(slot)
    local kind = GetActionInfo(slot)
    return kind ~= nil and not PLACEABLE[kind]
end
local function clearSlot(slot)
    if GetActionInfo(slot) then PickupAction(slot); ClearCursor() end
end

local COMBAT = "not in combat: Blizzard blocks changing action bars and bindings then"
L.ALL = {actions = true, macros = true, bindings = true, cvars = true}

-- Loads parts ({actions, macros, bindings, cvars} = true) of a loadout. Returns a report, or nil and why not.
function L.apply(lo, parts)
    if InCombatLockdown() then return nil, COMBAT end
    local report = {placed = 0, waiting = 0, skipped = 0, macros = 0, bindings = 0, cvars = 0}
    ClearCursor()
    if parts.macros then
        for _, m in ipairs(lo.macros) do
            local index = GetMacroIndexByName(m.name)
            local _, numChar = GetNumMacros()
            if index and index > ACCOUNT_MACROS then
                EditMacro(index, m.name, m.icon, m.body)
                report.macros = report.macros + 1
            elseif (numChar or 0) < CHARACTER_MACROS then
                CreateMacro(m.name, m.icon, m.body, true)
                report.macros = report.macros + 1
            end
        end
    end
    if parts.actions then
        local pending = {}
        for slot = 1, L.SLOTS do
            local a = lo.actions[slot]
            if lo.backup and unplaceable(slot) then -- left as it is
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
            else
                clearSlot(slot)
                report.skipped = report.skipped + 1
            end
        end
        for slot, name in pairs(lo.pending or {}) do -- a backup's spells that were still waiting, if the slot's free
            if not GetActionInfo(slot) then pending[slot] = name end
        end
        ns.db.loadouts.pending[charKey()] = next(pending) and pending or nil
    end
    if parts.bindings then
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
        for command, keys in pairs(lo.bindings) do
            for _, key in pairs(keys) do SetBinding(key, command) end
            report.bindings = report.bindings + 1
        end
        SaveBindings(GetCurrentBindingSet())
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
function L.load(lo, parts)
    if InCombatLockdown() then return nil, COMBAT end
    parts = parts or L.ALL
    local backup, list = L.capture(), L.backups()
    backup.name, backup.backup, backup.parts = "Before " .. lo.name, true, {}
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
    return L.apply(lo, parts)
end

-- What loading lo's bars does to each slot: changed[slot] when it ends up holding something else than now,
-- waiting[slot] when its spell isn't known yet (the slot is kept free for it)
local function nowHolds(slot)
    local kind, id = GetActionInfo(slot)
    if kind == "macro" then return "macro:" .. tostring(GetActionText(slot) or (GetMacroInfo(id))) end
    return kind and kind .. ":" .. tostring(id)
end
function L.preview(lo)
    local p = {changed = {}, waiting = {}, changes = 0, waits = 0}
    local macros = {} -- loading the macros makes these
    for _, m in ipairs(lo.macros) do macros[m.name] = true end
    for slot = 1, L.SLOTS do
        local a, holds = lo.actions[slot], nil
        if a and a.type == "spell" then
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
        end
        if lo.backup and unplaceable(slot) then holds = nowHolds(slot) end -- a restore leaves it
        if holds ~= nowHolds(slot) then p.changed[slot], p.changes = true, p.changes + 1 end
    end
    return p
end

-- Sharing: a loadout as one line of text, "KU1:" and its table. Strings are quoted, with %XX for " and % and for
-- anything outside printable ASCII; numbers are n<number>; booleans T and F; tables {key value key value ...}.
local PREFIX = "KU1:"
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
        actions = lo.actions, macros = lo.macros, bindings = lo.bindings, cvars = lo.cvars, bars = lo.bars}, out)
    return PREFIX .. table.concat(out)
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
local function size(t, max)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n <= max and n
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
    if not size(t.actions, L.SLOTS) then return nil end
    for slot, a in pairs(t.actions) do
        if not (int(slot, 1, L.SLOTS) and type(a) == "table" and str(a.type, 32) and a.type:find("^%a+$")
            and (a.id == nil or int(a.id, 0, 2 ^ 31)) and (a.name == nil or str(a.name, 255))) then return nil end
        if (a.type == "spell" and not (a.name or a.id)) or (a.type == "macro" and not a.name)
            or (a.type == "item" and not a.id) then return nil end
        lo.actions[slot] = {type = a.type, id = a.id, name = a.name}
    end
    local macros = size(t.macros, 36)
    if not macros or macros ~= #t.macros then return nil end
    for i, m in ipairs(t.macros) do
        if not (type(m) == "table" and str(m.name, 64) and m.name ~= "" and str(m.body, 1024)
            and (int(m.icon, 0, 2 ^ 31) or str(m.icon, 255))) then return nil end
        lo.macros[i] = {name = m.name, icon = m.icon, body = m.body}
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
    if text:sub(1, #PREFIX) ~= PREFIX then return nil, NOT_A_LOADOUT end
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
    local db = ns.db.loadouts
    local id = db.nextId
    db.nextId = id + 1
    db.list[id] = lo
    return id
end

-- Waiting spells go on when learned (the slot still free), at the highest rank; out of combat
function L.fillPending()
    local pending = L.pending()
    if not pending or InCombatLockdown() then return end
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

local events = CreateFrame("Frame")
for _, e in ipairs({"SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_REGEN_ENABLED"}) do
    pcall(events.RegisterEvent, events, e) -- a client without one of them just doesn't send it
end
events:SetScript("OnEvent", function() if ns.db and ns.IsOn("loadouts") then L.fillPending() end end)
-- on again: spells learned while off go on now (fillPending waits for PLAYER_REGEN_ENABLED in combat)
ns.OnModuleChange("loadouts", function(on) if on then L.fillPending() end end)

tinsert(ns.onLoad, function(root)
    local db = root.loadouts
    db.list = type(db.list) == "table" and db.list or {}
    db.pending = type(db.pending) == "table" and db.pending or {}
    db.backups = type(db.backups) == "table" and db.backups or {}
    db.nextId = db.nextId or 1
end)

ns.AddCommand("loadouts", "/ku loadouts - opens or closes the loadouts window", function() L.toggle() end, "loadouts")

local panel, category = ns.AddSettingsPage("Loadouts",
    "Save your action bars, macros, key bindings and interface settings, and load them on another character.", "loadouts")
L.category = category
ns.Label(panel, "Spells a character doesn't know yet are placed when it learns them.")
ns.Button(panel, "Open loadouts", 160, function() L.toggle() end, "Loadouts window")
