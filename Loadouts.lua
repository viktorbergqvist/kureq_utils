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

-- The index of your macro called name among your general (account) or character macros, or nil. A name can be in
-- both, and GetMacroIndexByName finds only one of them.
local function macroIndex(name, account)
    local first = account and 1 or ACCOUNT_MACROS + 1
    for i = first, first + (account and ACCOUNT_MACROS or CHARACTER_MACROS) - 1 do
        if GetMacroInfo(i) == name then return i end
    end
end

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
function L.apply(lo, parts)
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
        if lo.pending then L.fillPending() end -- a restored spell may have been learned since
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
    local full = parts.macros and L.macroRoom(lo)
    if full then return nil, full end
    local backup, list = L.capture(true), L.backups()
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
    local report, why = L.apply(lo, parts)
    if report then -- what a restore must undo besides putting back what was there
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

-- Editing a saved loadout: each edit changes it in KureqUtilsDB at once (your character changes only on Load). The
-- first edit of a loadout keeps a copy of it, so Revert changes can put it back until the window closes.
L.MACRO_TEXT, L.MACRO_NAME = 255, 16
L.MACRO_CAPS = {character = CHARACTER_MACROS, account = ACCOUNT_MACROS}
local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end
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

-- Bars: an action ({type, id, name}) or nil on a slot, and two slots swapped
function L.setSlot(lo, slot, action)
    if not (type(slot) == "number" and slot >= 1 and slot <= L.SLOTS) then return end
    track(lo)
    lo.actions[slot] = action
end
function L.swapSlots(lo, a, b)
    if a == b then return end
    track(lo)
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
    if kind == "number" and not tonumber(value) then return nil, "That setting takes a number." end
    if #value > 256 then return nil, "That's too long for a setting." end
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
        text = "Casts on the unit under your mouse, else on your target.",
        make = function(o)
            local on = o.target == "harm" and "harm" or "help"
            return ("#showtooltip\n/cast [@mouseover,%s,nodead][] %s"):format(on, spellOf(o))
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
}
-- A ready-made macro's options, filled with the defaults
function L.readyOptions(kind, options)
    local o = {}
    for _, key in ipairs(L.READY[kind].options) do
        local v = options and options[key]
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
-- starts "KU2:" instead, the same format, so those versions refuse it rather than load part of it.
local PREFIX, PREFIX2, OLD_MACROS = "KU1:", "KU2:", 36
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
        actions = lo.actions, macros = lo.macros, bindings = lo.bindings, cvars = lo.cvars, bars = lo.bars}, out)
    return (needsKU2(lo) and PREFIX2 or PREFIX) .. table.concat(out)
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
    if not size(t.actions, L.SLOTS) then return nil end
    for slot, a in pairs(t.actions) do
        if not (int(slot, 1, L.SLOTS) and type(a) == "table" and str(a.type, 32) and a.type:find("^%a+$")
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
    if text:sub(1, #PREFIX) ~= PREFIX and text:sub(1, #PREFIX2) ~= PREFIX2 then return nil, NOT_A_LOADOUT end
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

local events = CreateFrame("Frame")
for _, e in ipairs({"SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB"}) do
    pcall(events.RegisterEvent, events, e) -- a client without one of them just doesn't send it
end
events:SetScript("OnEvent", function() if ns.db and ns.IsOn("loadouts") then L.fillPending() end end)
-- on again: spells learned while off go on now (in combat fillPending waits for it to end)
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
