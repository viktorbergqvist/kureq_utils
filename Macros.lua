-- Macros: make and edit your real macros (the game's, not a loadout's) in a window of their own (MacrosWindow.lua):
-- ready-made ones, your class's first; your character and account macros in the loadout editor's form
-- (MacroForm.lua), saved when you click Save; one picked up to drop on a bar; or one copied into a saved loadout.
-- Nothing changes a macro in combat (Blizzard blocks it) or while Blizzard's macro window is open (it would lose what
-- is typed there). A macro is known by its index and name, checked again before every change; two macros of one
-- name in one scope aren't changed here. Within Blizzard's slots (120 account, 18 character), 16 letters of name and
-- 255 characters of text. The game keeps the macros; Kureq Utils keeps their history (KureqUtilsDB.macros.history):
-- what each macro was before every save, rename, move and delete, the newest 20 per macro, account macros under
-- "account" and character ones under the character ("Name - Realm"), so a deleted macro can be put back.
local _, ns = ...
ns.AddModule("macros", "Macros",
    "Make and edit your macros, from ready-made ones for your class; drag them to your bars or copy them into a loadout.")
local L = ns.loadouts
local M = {}
ns.macros = M

local ACCOUNT, CHARACTER = MAX_ACCOUNT_MACROS or 120, MAX_CHARACTER_MACROS or 18
M.CAPS = {account = ACCOUNT, character = CHARACTER}
M.COMBAT = "not in combat: Blizzard blocks changing macros then"
M.MACRO_FRAME = "close Blizzard's macro window first: it would lose what you typed there"
M.CHANGED = "That macro changed in the game: pick it again."

ns.defaults.macros = {replaceBlizzard = false}

-- History -----------------------------------------------------------------------------------------------------------

M.KEEP = 20
local function charKey()
    local name = NameUtil and NameUtil.FormatUnitNameForDisplay and NameUtil.FormatUnitNameForDisplay("player")
    if not name or (issecretvalue ~= nil and issecretvalue(name)) then name = UnitName("player") end
    return (name or "?") .. " - " .. (GetRealmName() or "?")
end
-- The history of account (or this character's) macros: name -> its versions, newest first. Saved data is checked
-- as it's read: anything that isn't a list of versions is dropped.
local function bucket(account)
    local db = ns.db and ns.db.macros
    if type(db) ~= "table" then return {} end
    if type(db.history) ~= "table" then db.history = {} end
    local key = account and "account" or charKey()
    local b = db.history[key]
    if type(b) ~= "table" then
        b = {}
        db.history[key] = b
    end
    for name, list in pairs(b) do
        if type(name) ~= "string" or type(list) ~= "table" then b[name] = nil end
    end
    return b
end
-- The versions kept of a macro: {name, icon, body, time, what}, newest first
function M.versions(account, name)
    local out = {}
    for _, v in ipairs(bucket(account)[name] or {}) do
        if type(v) == "table" and type(v.body) == "string" and type(v.name) == "string" then out[#out + 1] = v end
    end
    return out
end
-- Keeps macro m ({name, icon, body, account}, as the game has it) as it is before what ("Saved", "Deleted", ...)
local function remember(m, what)
    local b = bucket(m.account)
    local list = type(b[m.name]) == "table" and b[m.name] or {}
    table.insert(list, 1, {name = m.name, icon = m.icon, body = m.body or "", time = time(), what = what})
    while #list > M.KEEP do table.remove(list) end
    b[m.name] = list
end
M.remember = remember -- SmartMacros.lua keeps its macros' versions too
-- A macro's history goes with it to its new name or scope (merged by time with any already there)
local function carry(fromAccount, fromName, toAccount, toName)
    if fromName == toName and not fromAccount == not toAccount then return end
    local from, to = bucket(fromAccount), bucket(toAccount)
    local list = from[fromName]
    if not list then return end
    from[fromName] = nil
    local into = type(to[toName]) == "table" and to[toName] or {}
    for _, v in ipairs(list) do into[#into + 1] = v end
    table.sort(into, function(x, y) return (tonumber(x.time) or 0) > (tonumber(y.time) or 0) end)
    while #into > M.KEEP do table.remove(into) end
    to[toName] = into
end
-- The deleted macros of a scope that have history: {name, versions}, the last deleted first
function M.deleted(account)
    local live, out = {}, {}
    for _, m in ipairs(M.list()) do if not m.account == not account then live[m.name] = true end end
    for name in pairs(bucket(account)) do
        local versions = M.versions(account, name)
        if not live[name] and #versions > 0 then out[#out + 1] = {name = name, versions = versions} end
    end
    table.sort(out, function(x, y) return (tonumber(x.versions[1].time) or 0) > (tonumber(y.versions[1].time) or 0) end)
    return out
end

-- Import: pasted text as a macro's text (line ends evened out, blank lines at the ends dropped), or nil and why not.
-- A macro has a line that starts with / or #, fits Blizzard's 255 characters and has no errors (warnings are fine).
function M.importText(text)
    local body = (type(text) == "string" and text or ""):gsub("\r\n?", "\n"):gsub("^%s*\n", ""):gsub("[\n%s]+$", "")
    if body == "" then return nil, "Paste a macro's text first." end
    if not ("\n" .. body):find("\n%s*[/#]") then return nil, "That isn't a macro: none of its lines starts with / or #." end
    local problems = ns.macroCode.check(body, {spells = ns.macroCode.spells()})
    for _, p in ipairs(problems) do
        if p.severity == "error" then return nil, "Fix the underlined problems first: " .. p.text end
    end
    return body
end

local function scopeName(account) return account and "account" or "character" end
function M.ambiguous(m)
    return ("There are two %s macros called %s: rename one in Blizzard's macro window (/macro) first.")
        :format(scopeName(m.account), m.name)
end

-- Why no macro can change now, or nil. In combat it's said in chat too.
function M.blocked()
    if InCombatLockdown() then
        ns.say(M.COMBAT .. ".")
        return M.COMBAT
    end
    if MacroFrame and MacroFrame:IsShown() then return M.MACRO_FRAME end
end

-- Your macros, account ones first: {index, name, icon, body, account, twin}; twin when another macro in its scope
-- has the same name
function M.list()
    local list, seen = {}, {}
    local numAccount, numChar = GetNumMacros()
    for _, s in ipairs({{1, numAccount, true}, {ACCOUNT + 1, numChar, nil}}) do
        for i = s[1], s[1] + (s[2] or 0) - 1 do
            local name, icon, body = GetMacroInfo(i)
            if name then
                local m = {index = i, name = name, icon = icon, body = body or "", account = s[3]}
                local key = scopeName(s[3]) .. ":" .. name
                if seen[key] then seen[key].twin, m.twin = true, true end
                seen[key] = m
                list[#list + 1] = m
            end
        end
    end
    return list
end
-- The macro now at index called name, or, when the indexes moved, the only one of that name in its scope
function M.find(index, name, account)
    local byName, n = nil, 0
    for _, m in ipairs(M.list()) do
        if m.index == index and m.name == name then return m end
        if m.name == name and not m.account == not account then byName, n = m, n + 1 end
    end
    if n == 1 then return byName end -- two or more: which one isn't known
end
local function current(m) -- m as the game has it now, or nil and why not
    local now = M.find(m.index, m.name, m.account)
    if not now then return nil, M.CHANGED end
    if now.twin then return nil, M.ambiguous(now) end
    return now
end

function M.counts()
    local numAccount, numChar = GetNumMacros()
    return numAccount or 0, numChar or 0
end
-- Why there's no room for another account (or character) macro, or nil
function M.full(account)
    local numAccount, numChar = M.counts()
    local n, cap = account and numAccount or numChar, account and ACCOUNT or CHARACTER
    if n >= cap then
        return ("Your %s macros are full (%d of %d): delete one first."):format(scopeName(account), n, cap)
    end
end

-- Why macro m ({name, body, account}) can't be saved as it is (nil when it can); index is the macro it replaces
function M.problem(m, index)
    if type(m.name) ~= "string" or ns.trim(m.name) == "" then return "A macro needs a name." end
    if #m.name > L.MACRO_NAME then return ("A macro's name is %d letters at most."):format(L.MACRO_NAME) end
    if #(m.body or "") > L.MACRO_TEXT then return ("A macro's text is %d characters at most."):format(L.MACRO_TEXT) end
    for _, o in ipairs(M.list()) do
        if o.index ~= index and o.name == m.name and not o.account == not m.account then
            return ("You already have %s macro called %s."):format(m.account and "an account" or "a character", m.name)
        end
    end
end

-- The icon a macro shows as chosen (the question mark for one that shows its spell), not the spell's it shows
local function chosenIcon(m)
    return C_Macro and C_Macro.GetSelectedMacroIcon and C_Macro.GetSelectedMacroIcon(m.index) or m.icon
end

-- Makes macro m ({name, icon, body, account}). Returns it as M.list has it, or nil and why not.
function M.create(m)
    local why = M.blocked() or M.problem(m) or M.full(m.account)
    if why then return nil, why end
    CreateMacro(m.name, m.icon or L.QUESTION_MARK, m.body or "", not m.account or nil) -- nil: an account macro
    return M.find(nil, m.name, m.account)
end

-- Saves fields (name, icon, body; icon only when picked) to macro m, as it was loaded into the editor. When the game's
-- name or text differ from loaded (changed elsewhere since) it returns nil, "conflict", unless force. Returns the
-- macro as saved, or nil and why not.
function M.save(m, fields, loaded, force)
    local why = M.blocked()
    if why then return nil, why end
    local now
    now, why = current(m)
    if not now then return nil, why end
    if not force and (now.name ~= loaded.name or now.body ~= loaded.body) then return nil, "conflict" end
    local new = {name = fields.name or now.name, body = fields.body or now.body, account = now.account}
    why = M.problem(new, now.index)
    if why then return nil, why end
    if new.name ~= now.name or new.body ~= now.body or (fields.icon and fields.icon ~= chosenIcon(now)) then
        remember({name = now.name, icon = chosenIcon(now), body = now.body, account = now.account},
            new.name ~= now.name and "Renamed" or "Saved")
    end
    EditMacro(now.index, new.name, fields.icon, new.body) -- a nil icon keeps the one chosen
    carry(now.account, now.name, now.account, new.name)
    return M.find(nil, new.name, new.account)
end

-- Deletes macro m, and so takes it off your bars. Returns true, or nil and why not.
function M.delete(m)
    local why = M.blocked()
    if why then return nil, why end
    local now
    now, why = current(m)
    if not now then return nil, why end
    remember({name = now.name, icon = chosenIcon(now), body = now.body, account = now.account}, "Deleted")
    DeleteMacro(now.index)
    return true
end

-- Makes m an account macro (or a character one): a new macro there, put back on the bars the old one was on, and
-- the old one deleted. Returns the new macro, or nil and why not.
function M.move(m, account)
    if not m.account == not account then return current(m) end -- already there: nothing to do
    local why = M.blocked()
    if why then return nil, why end
    local now
    now, why = current(m)
    if not now then return nil, why end
    why = M.problem({name = now.name, body = now.body, account = account}) or M.full(account)
    if why then return nil, why end
    local slots = {}
    for slot = 1, L.SLOTS do
        local kind, index = GetActionInfo(slot)
        if kind == "macro" and index == now.index then slots[#slots + 1] = slot end
    end
    remember({name = now.name, icon = chosenIcon(now), body = now.body, account = now.account}, "Moved")
    CreateMacro(now.name, chosenIcon(now), now.body, not account or nil)
    DeleteMacro(now.index) -- the other scope's macros keep their indexes
    carry(now.account, now.name, account, now.name)
    local moved = M.find(nil, now.name, account)
    for _, slot in ipairs(slots) do
        PickupMacro(moved.index)
        PlaceAction(slot)
        ClearCursor()
    end
    return moved
end

-- Puts macro m on the cursor, to drop on an action bar. Returns true, or nil and why not.
function M.pickup(m)
    if InCombatLockdown() then return nil, "Put macros on your bars out of combat." end
    local now, why = current(m)
    if not now then return nil, why end
    ClearCursor()
    PickupMacro(now.index)
    return true
end

-- Copies macro m into saved loadout lo, as the loadout editor keeps macros. One of the same name there is replaced
-- only with replace (else it returns nil, "exists"). Returns "added" or "updated", or nil and why not.
function M.toLoadout(m, lo, replace)
    local now, why = current(m)
    if not now then return nil, why end
    local i = L.findMacro(lo, now.name)
    if i and not replace then return nil, "exists" end
    local icon, ok = chosenIcon(now), nil
    if i then
        ok, why = L.setMacro(lo, i, {icon = icon, body = now.body, account = now.account or false, kind = false,
            options = false})
    else
        ok, why = L.addMacro(lo, {name = now.name, icon = icon, body = now.body, account = now.account})
    end
    if not ok then return nil, why end
    -- no loadouts window open: no editing session to revert this in (its Revert changes would undo it)
    if not (L.frame and L.frame:IsShown()) then L.endEdits() end
    if L.changed then L.changed() end
    return i and "updated" or "added"
end

-- Kureq Utils' own commands as ready-made macros, one per /ku command (ns.commandList, so a new command shows up by
-- itself) and plain /ku for the settings. Made into L.READY kinds ("ku:<command>", r.ku the command) the first time
-- the gallery asks, after every file has added its commands. Icons as the minimap menu's.
local KU_ICONS = {[""] = "INV_Misc_Gear_01", stats = "INV_Misc_Bone_HumanSkull_01", notes = "INV_Misc_Note_01",
    note = "INV_Misc_Note_01", loadouts = "INV_Misc_Book_11", mail = "INV_Letter_15", macro = "INV_Misc_Book_09",
    delete = "INV_Misc_Bag_08", ping = "Ability_Hunter_MarkedForDeath"}
local SETTINGS = {name = "", usage = "/ku - opens the Kureq Utils settings"}
function M.commandMacros()
    local list = {}
    for i = 0, #ns.commandList do
        local c = i == 0 and SETTINGS or ns.commandList[i]
        local kind = "ku:" .. c.name
        local r = L.READY[kind]
        if not r then
            local command = c.name == "" and "/ku" or "/ku " .. c.name
            local what = c.usage:match(" %- (.+)$") or c.usage
            r = {kind = kind, ku = c, command = command, icon = KU_ICONS[c.name] or "INV_Misc_Gear_01",
                name = ("Ku " .. (c.name == "" and "settings" or c.name)):sub(1, L.MACRO_NAME),
                -- a command that takes words (its usage shows <...> or [...]) gets a box for them
                options = c.usage:find("^/ku %S+ [<%[]") and {"after"} or {},
                text = what:sub(1, 1):upper() .. what:sub(2) .. ".",
                make = function(o)
                    local after = ns.trim(o.after or "")
                    return command .. (after ~= "" and " " .. after or "")
                end}
            L.READY[#L.READY + 1], L.READY[kind] = r, r
        end
        list[#list + 1] = r
    end
    return list
end

-- The ready-made macros in the gallery's order: your class's templates, the shared ones, Kureq Utils' commands, then
-- other classes'
function M.ready()
    local _, class = UnitClass("player")
    local mine, shared, others = {}, {}, {}
    for _, r in ipairs(L.READY) do
        if not r.ku then
            local list = r.class == nil and shared or r.class == class and mine or others
            list[#list + 1] = r
        end
    end
    for _, list in ipairs({shared, M.commandMacros(), others}) do
        for _, r in ipairs(list) do mine[#mine + 1] = r end
    end
    return mine
end

local events = CreateFrame("Frame")
events:RegisterEvent("UPDATE_MACROS")
events:SetScript("OnEvent", function() if M.changed and ns.IsOn("macros") then M.changed() end end)

ns.AddCommand("macro", "/ku macro - opens or closes the macros window", function() M.toggle() end, "macros")
ns.commands.macros = ns.commands.macro -- the old name keeps working, unlisted

local panel = ns.AddSettingsPage("Macros",
    "Make and edit your character and account macros, starting from ready-made ones for your class. Drag one to "
        .. "your bars, or copy it into a saved loadout.", "macros")
ns.Label(panel, "Macros change only out of combat, and while Blizzard's macro window is closed.")
ns.Button(panel, "Open macros", 140, function() M.toggle() end, "Macros window")
ns.Checkbox(panel, "Open instead of the game's macros",
    "/macro, the game menu's Macros and the chat menu open this window instead of Blizzard's. Its \"Blizzard's "
        .. "window\" button still opens the game's own.",
    function() return ns.db and ns.db.macros.replaceBlizzard end,
    function(v) ns.db.macros.replaceBlizzard = v end)

-- Replacing Blizzard's macro window: after the game shows it (ShowMacroFrame, from /macro and the menus), hide it and
-- show ours. A post-hook only, so Blizzard's code runs untouched.
local bypass -- set while our own button opens the game's window
function M.openBlizzard()
    bypass = true
    if ShowMacroFrame then ShowMacroFrame() end
    bypass = false
end
if ShowMacroFrame then
    hooksecurefunc("ShowMacroFrame", function()
        if bypass or not (ns.db and ns.db.macros.replaceBlizzard and ns.IsOn("macros")) then return end
        if MacroFrame and MacroFrame:IsShown() then HideUIPanel(MacroFrame) end
        M.open()
    end)
end
ns.Header(panel, "Smart macros")
ns.Label(panel, "Macros that keep themselves up to date: your best potion, drink, food, bandage and mount, your pet, "
    .. "and KU Ping. Tick them and set them up in their own tab.")
ns.Button(panel, "Open smart macros", 160, function() M.open("smart") end, "Smart macros")
