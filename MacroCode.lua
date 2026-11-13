-- Macro text read the way the game reads it, for the macro editor (MacroEditor.lua): lines, commands, [conditions],
-- @units, spells and their ranks, with byte offsets; the problems in it (each with a fix where one is certain); its
-- colours; what it would do right now; a one-line summary for lists; and what to offer as you type. Pure Lua except
-- C.commands (the client's slash commands), C.spells (your spellbook) and the live values (SecureCmdOptionParse).
-- The macros window (MacrosWindow.lua) and the loadout editor (LoadoutsEditor.lua) use it through MacroForm.lua.
local _, ns = ...
local C = {}
ns.macroCode = C
C.LIMIT = 255

-- Commands ----------------------------------------------------------------------------------------------------------

-- The commands that run as secure code and read [conditions] (Blizzard_ChatFrameBase's SlashCommands.lua registers
-- these with CheckAddSecureSlashCommand; the cast sequence and random ones are in their own files there)
local SECURE = {}
for key in ([[ABANDON ASSIST CANCELAURA CANCELFORM CANCELQUEUEDSPELL CAST CASTRANDOM CASTSEQUENCE CHANGEACTIONBAR
    CLEARFOCUS CLEARTARGET CLEAR_WORLD_MARKER CLICK DUEL DUEL_CANCEL EQUIP EQUIP_SET EQUIP_TO_SLOT FOCUS GUILD_DEMOTE
    GUILD_DISBAND GUILD_LEADER GUILD_LEAVE GUILD_PROMOTE GUILD_UNINVITE LOGOUT MAINASSISTOFF MAINASSISTON MAINTANKOFF
    MAINTANKON PET_AGGRESSIVE PET_ASSIST PET_ATTACK PET_AUTOCASTOFF PET_AUTOCASTON PET_AUTOCASTTOGGLE PET_DEFENSIVE
    PET_DEFENSIVEASSIST PET_DISMISS PET_FOLLOW PET_MOVE_TO PET_PASSIVE PET_STAY PING PING_ITEM PING_SPELL QUIT
    STARTATTACK STOPATTACK STOPCASTING STOPMACRO STOPSPELLTARGET SWAPACTIONBAR TARGET TARGET_EXACT TARGET_LAST_ENEMY
    TARGET_LAST_FRIEND TARGET_LAST_TARGET TARGET_NEAREST_ENEMY TARGET_NEAREST_ENEMY_PLAYER TARGET_NEAREST_FRIEND
    TARGET_NEAREST_FRIEND_PLAYER TARGET_NEAREST_PARTY TARGET_NEAREST_RAID USE USERANDOM USE_TOY WORLD_MARKER]]):gmatch("%S+") do
    SECURE[key] = true
end
-- Not secure, but they read [conditions] too (their handlers call SecureCmdOptionParse): /tm, /dismount, ...
local READS = {}
for key in ([[DISMISSBATTLEPET DISMOUNT LEAVEVEHICLE RANDOMFAVORITEPET RANDOMPET SET_TITLE SUMMON_BATTLE_PET
    TARGET_MARKER TRANSMOG_OUTFIT]]):gmatch("%S+") do
    READS[key] = true
end
-- commands whose words are spells (or items): checked against your spellbook, completed from it
local SPELL_LISTS = {CAST = "cast", CASTSEQUENCE = "cast", CASTRANDOM = "cast", USE = "use", USERANDOM = "use"}

-- Every slash command the client knows, alias (lower case, no slash) -> {key, secure, spells, emote}, read once from
-- the SLASH_<KEY><n> and EMOTE<n>_CMD<n> strings, so addons' commands (/ku) count too
local commands
function C.commands()
    if commands then return commands end
    commands = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "string" and v:sub(1, 1) == "/" then
            local key = k:match("^SLASH_(.-)%d+$")
            local emote = not key and k:find("^EMOTE%d+_CMD%d+$")
            local alias = v:sub(2):lower()
            if (key or emote) and alias:find("^[%w_]+$") and not commands[alias] then
                commands[alias] = {key = key or "EMOTE", secure = key and SECURE[key] or false,
                    conditions = key and (SECURE[key] or READS[key]) or false,
                    spells = key and SPELL_LISTS[key], emote = emote and true or nil}
            end
        end
    end
    return commands
end
-- read again once every addon has loaded (their commands too)
local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function() commands = nil end)

-- Markers: /tm takes a raid target's number, /wm and /cwm a world marker's (their own numbering; world marker n
-- shows a raid icon, paired as Blizzard_CompactRaidFrameManager's WORLD_RAID_MARKER_ORDER lists them)
local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local RAID = {what = "Raid target marker", prefix = true} -- only /tm reads ! and ~ (/wm and /cwm call tonumber)
for n, name in ipairs({"Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull"}) do
    RAID[n] = {name = name, icon = ICON .. n}
end
local WORLD = {what = "World marker"}
for n, m in ipairs({{6, "Blue Square"}, {4, "Green Triangle"}, {3, "Purple Diamond"}, {7, "Red Cross"},
    {1, "Yellow Star"}, {2, "Orange Circle"}, {5, "Silver Moon"}, {8, "White Skull"}}) do
    WORLD[n] = {name = m[2], icon = ICON .. m[1]}
end
C.MARKERS = {TARGET_MARKER = RAID, WORLD_MARKER = WORLD, CLEAR_WORLD_MARKER = WORLD}
-- The marker numbers in a parsed line: {{from, to, marker = {name, icon}, what}}
function C.markersIn(line)
    local set = line.info and C.MARKERS[line.info.key]
    local out = {}
    for _, cl in ipairs(set and line.clauses or {}) do
        local at, n = (cl.args and cl.args.text or ""):match(set.prefix and "^[!~]?%s*()(%d+)$" or "^()(%d+)$")
        local m = n and set[tonumber(n)]
        if m then
            local from = cl.args.from + at - 1
            out[#out + 1] = {from = from, to = from + #n - 1, marker = m, what = set.what}
        end
    end
    return out
end

-- Conditions --------------------------------------------------------------------------------------------------------

-- name -> {value = "none" (no :value), "opt" or "need", the values to offer, the text shown with it}; no = false
-- where a no form isn't read
local CONDITIONS = {
    exists = {value = "none", text = "The unit is there."},
    help = {value = "none", text = "You can help the unit."},
    harm = {value = "none", text = "You can attack the unit."},
    dead = {value = "none", text = "The unit is dead."},
    party = {value = "none", text = "The unit is in your party."},
    raid = {value = "none", text = "The unit is in your party or raid."},
    combat = {value = "none", text = "You're in combat."},
    mounted = {value = "none", text = "You're mounted."},
    swimming = {value = "none", text = "You're swimming."},
    flying = {value = "none", text = "You're flying."},
    flyable = {value = "none", text = "You can fly here."},
    indoors = {value = "none", text = "You're indoors."},
    outdoors = {value = "none", text = "You're outdoors."},
    stealth = {value = "none", text = "You're stealthed."},
    resting = {value = "none", text = "You're resting (an inn or a city)."},
    cursor = {value = "none", text = "Something is on your cursor."},
    modifier = {value = "opt", values = {"shift", "ctrl", "alt"}, text = "A key is held: shift, ctrl or alt."},
    button = {value = "need", values = {"1", "2", "3", "4", "5"}, text = "The mouse button that clicked (1 left, 2 right)."},
    actionbar = {value = "need", values = {"1", "2", "3", "4", "5", "6"}, text = "This action bar page is shown."},
    bonusbar = {value = "opt", values = {"1", "2", "3", "4", "5"}, text = "A stance or form bar is shown."},
    stance = {value = "opt", values = {"0", "1", "2", "3", "4", "5", "6"}, text = "You're in this stance or form (0 is none)."},
    channeling = {value = "opt", text = "You're channeling (this spell)."},
    equipped = {value = "need", values = {"Shields", "Two-Hand", "One-Hand", "Daggers", "Bows", "Guns", "Wands"},
        text = "You have this kind of item on."},
    pet = {value = "opt", text = "Your pet is out (this one, or this family)."},
    group = {value = "opt", values = {"party", "raid"}, text = "You're in a group (party or raid)."},
    known = {value = "need", no = true, text = "You know this spell."},
}
local ALIASES = {mod = "modifier", btn = "button", bar = "actionbar", form = "stance", worn = "equipped"}
for alias, name in pairs(ALIASES) do CONDITIONS[alias] = CONDITIONS[name] end
for name, c in pairs(CONDITIONS) do c.name = c.name or (ALIASES[name] and ALIASES[name] or name) end
C.CONDITIONS = CONDITIONS

-- The units @ and target= take; others are partyN, raidN and their pets, and any of them followed by "target"
local UNITS = {"player", "target", "mouseover", "focus", "pet", "targettarget", "pettarget", "focustarget",
    "mouseovertarget", "none", "party1", "party2", "party3", "party4", "partypet1", "raid1"}
local function knownUnit(u)
    local base = u:gsub("target$", "")
    if base == "" then return true end -- "target" itself
    for _, x in ipairs(UNITS) do if x == u or x == base then return true end end
    return base:find("^party[1-4]$") or base:find("^partypet[1-4]$") or base:find("^raid%d+$")
        or base:find("^raidpet%d+$") or base:find("^arena[1-5]$")
end

-- Reading the text --------------------------------------------------------------------------------------------------

local function skip(s, i, j) -- the first byte from i on (up to j) that isn't a space, or j + 1
    while i <= j and s:sub(i, i):find("^[ \t\r]") do i = i + 1 end
    return i
end
local function trim(s, i, j)
    i = skip(s, i, j)
    while j >= i and s:sub(j, j):find("^[ \t\r]") do j = j - 1 end
    return i, j
end

-- One condition, or the unit, from the bytes i..j of a [group]
local function readPart(s, i, j, g)
    local text = s:sub(i, j)
    if text:sub(1, 1) == "@" then
        local x, y = trim(s, i + 1, j)
        g.unit = {name = s:sub(x, y):lower(), from = i, to = j}
        return
    end
    local eq = text:lower():match("^target%s*=%s*()")
    if eq then
        g.unit = {name = s:sub(i + eq - 1, j):lower(), from = i, to = j}
        return
    end
    local word = text:match("^[%a_]*")
    local lower = word:lower()
    local c = {raw = word, from = i, to = j, nameFrom = i, nameTo = i + #word - 1, name = lower}
    if not CONDITIONS[lower] and lower:sub(1, 2) == "no" and CONDITIONS[lower:sub(3)] then
        c.no, c.name, c.nameFrom = true, lower:sub(3), i + 2
    end
    local colon = s:find("^%s*:", i + #word)
    if colon and colon <= j then
        c.colon = s:find(":", colon, true)
        c.valueFrom, c.valueTo = trim(s, c.colon + 1, j)
        c.value = s:sub(c.valueFrom, c.valueTo)
    end
    g.conds[#g.conds + 1] = c
end

-- The spells or items of a clause's words i..j, comma separated: {name, from, to, rank, rankFrom, rankTo}
local function readItems(s, i, j)
    local items, start = {}, i
    for p = i, j + 1 do
        if p > j or s:sub(p, p) == "," then
            local x, y = trim(s, start, p - 1)
            if s:sub(x, x + 5):lower() == "reset=" then -- /castsequence reset=target Spell
                x = skip(s, (s:find("[ \t]", x) or y + 1), y)
            end
            if s:sub(x, x) == "!" then x = skip(s, x + 1, y) end -- ! keeps a toggle on
            if x <= y then
                local item = {name = s:sub(x, y), from = x, to = y}
                local nameEnd, r1, rank, r2 = s:sub(x, y):match("^(.-)%s*%(%s*[Rr][Aa][Nn][Kk]%s+()(%d+)()%s*%)$")
                if nameEnd then
                    item.name, item.to, item.rank = nameEnd, x + #nameEnd - 1, tonumber(rank)
                    item.rankFrom, item.rankTo = x + r1 - 1, x + r2 - 2
                end
                items[#items + 1] = item
            end
            start = p + 1
        end
    end
    return items
end

-- The [groups], words and ; of a line from byte i to j into line.clauses
local function readClauses(s, i, j, line)
    while true do
        local cl = {groups = {}, from = i}
        i = skip(s, i, j)
        while i <= j and s:sub(i, i) == "[" do
            local close = s:find("]", i, true)
            local g = {from = i, closed = close ~= nil and close <= j, conds = {}}
            g.to = g.closed and close or j
            local inner = g.closed and close - 1 or j
            local start = i + 1
            for p = i + 1, inner + 1 do
                if p > inner or s:sub(p, p) == "," then
                    local x, y = trim(s, start, p - 1)
                    if x <= y then readPart(s, x, y, g) end
                    start = p + 1
                end
            end
            cl.groups[#cl.groups + 1] = g
            i = skip(s, g.to + 1, j)
        end
        local semi = s:find(";", i, true)
        if semi and semi > j then semi = nil end
        local x, y = trim(s, i, (semi or j + 1) - 1)
        if x <= y then cl.args = {from = x, to = y, text = s:sub(x, y), items = readItems(s, x, y)} end
        cl.to, cl.semi = (semi or j + 1) - 1, semi
        line.clauses[#line.clauses + 1] = cl
        if not semi then return end
        i = semi + 1
    end
end

local function readLine(s, a, b)
    local line = {from = a, to = b, text = s:sub(a, b), clauses = {}}
    local i = skip(s, a, b)
    local first = s:sub(i, i)
    if i > b then
        line.kind = "empty"
    elseif first == "#" or first == "/" then
        local word = s:match("^[%w_]*", i + 1)
        line.kind = first == "#" and "directive" or "command"
        line.cmd = {name = word:lower(), from = i, to = i + #word}
        line.info = first == "/" and C.commands()[word:lower()] or nil
        local rest = i + #word + 1
        if first == "#" or (line.info and line.info.conditions) then
            readClauses(s, rest, b, line)
        else
            local x, y = trim(s, rest, b)
            if x <= y then line.args = {from = x, to = y, text = s:sub(x, y)} end
        end
    else
        line.kind = "text"
    end
    return line
end

-- The macro's lines: {from, to (bytes in body), text, kind ("empty", "directive", "command", "text"), cmd, info (the
-- command's), clauses = {{groups = {{conds, unit, closed}}, args = {items}, semi}}}
function C.parse(body)
    body = type(body) == "string" and body or ""
    local lines, a = {}, 1
    while true do
        local nl = body:find("\n", a, true)
        lines[#lines + 1] = readLine(body, a, (nl or #body + 1) - 1)
        if not nl then break end
        a = nl + 1
    end
    return {text = body, lines = lines}
end

-- Problems ----------------------------------------------------------------------------------------------------------

-- The only word in list (an array of strings) that starts with typed and is longer, or nil
local function onlyStarting(list, typed)
    local found
    typed = typed:lower()
    for _, w in ipairs(list) do
        if #w > #typed and w:lower():sub(1, #typed) == typed then
            if found and found ~= w then return nil end
            found = w
        end
    end
    return found
end
local function names(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
end
local CONDITION_NAMES = names(CONDITIONS)

-- Your spellbook: {byName = {lower -> {name, ranks = {n -> true}, list = {n...}}}, list = {entries}}; your own
-- spells are never secret. Read afresh each time (a few hundred calls): it changes as you learn spells.
function C.spells()
    local byName, list = {}, {}
    local function add(name, sub)
        if type(name) ~= "string" or name == "" then return end
        local e = byName[name:lower()]
        if not e then
            e = {name = name, ranks = {}, list = {}}
            byName[name:lower()], list[#list + 1] = e, e
        end
        local rank = type(sub) == "string" and tonumber(sub:match("(%d+)"))
        if rank and not e.ranks[rank] then
            e.ranks[rank] = true
            e.list[#e.list + 1] = rank
            table.sort(e.list)
        end
    end
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
            for slot = line and line.itemIndexOffset + 1 or 1, line and line.itemIndexOffset + line.numSpellBookItems or 0 do
                local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                if item and not item.isPassive then add(item.name, item.subName) end
            end
        end
    elseif GetNumSpellTabs and GetSpellBookItemName then
        for i = 1, GetNumSpellTabs() do
            local _, _, offset, n = GetSpellTabInfo(i)
            for slot = offset + 1, offset + n do add(GetSpellBookItemName(slot, "spell")) end
        end
    end
    return {byName = byName, list = list}
end

local function problem(out, from, to, severity, text, fix)
    out[#out + 1] = {from = from, to = math.max(from, to), severity = severity, text = text, fix = fix}
end

local function checkCondition(c, out)
    local def = CONDITIONS[c.name]
    if not def then
        local guess = c.raw ~= "" and onlyStarting(CONDITION_NAMES, c.raw)
        problem(out, c.nameFrom, c.nameTo, "error", c.raw == "" and "An empty condition: remove the extra comma."
            or ("[%s] isn't a condition."):format(c.raw), guess and {from = c.from, to = c.nameTo, text = guess})
        return
    end
    if c.no and def.no == false then
        problem(out, c.from, c.nameTo, "error", ("[%s] has no \"no\" form."):format(c.raw))
    end
    if def.value == "none" and c.colon then
        problem(out, c.colon, c.to, "error", ("[%s] takes no value."):format(def.name),
            {from = c.nameTo + 1, to = c.to, text = ""})
    elseif def.value == "need" and (c.value or "") == "" then
        local example = def.values and def.values[1] or "a spell"
        problem(out, c.from, c.to, "error", ("[%s] needs a value: [%s:%s]."):format(def.name, def.name, example))
    end
end

local function checkSpells(line, ctx, out)
    local book = ctx.spells
    if not (book and line.info and line.info.spells == "cast") then return end
    local spellNames = {}
    for _, e in ipairs(book.list) do spellNames[#spellNames + 1] = e.name end
    for _, cl in ipairs(line.clauses) do
        for _, item in ipairs(cl.args and cl.args.items or {}) do
            local known = book.byName[item.name:lower()]
            if not known and not item.name:find("^%d+$") and not item.name:find("^%d+%s+%d+$") then
                local guess = onlyStarting(spellNames, item.name)
                problem(out, item.from, item.to, "warning", ("You don't know %s.%s"):format(item.name, ctx.note or ""),
                    guess and {from = item.from, to = item.to, text = guess})
            elseif known and item.rank and #known.list > 0 and not known.ranks[item.rank] then
                local best = known.list[#known.list]
                problem(out, item.rankFrom, item.rankTo, "warning",
                    ("You don't know rank %d of %s: your highest is %d."):format(item.rank, known.name, best),
                    {from = item.rankFrom, to = item.rankTo, text = tostring(best)})
            end
        end
    end
end

local function checkLine(line, ctx, out, known)
    if line.kind == "text" then
        problem(out, line.from, line.to, "warning", "No / at the start: this line is said in chat.")
        return
    end
    if line.kind == "empty" then return end
    local cmd = line.cmd
    if line.kind == "directive" then
        if cmd.name ~= "show" and cmd.name ~= "showtooltip" then
            local guess = cmd.name ~= "" and onlyStarting({"show", "showtooltip"}, cmd.name)
            problem(out, cmd.from, cmd.to, "error", "Only #showtooltip and #show are read here.",
                guess and {from = cmd.from, to = cmd.to, text = "#" .. guess})
        end
    elseif cmd.name == "" then
        problem(out, cmd.from, cmd.to, "error", "A / needs a command after it, such as /cast.")
    elseif not line.info and known then
        local guess = onlyStarting(known, cmd.name)
        problem(out, cmd.from, cmd.to, "error", ("/%s isn't a command."):format(cmd.name),
            guess and {from = cmd.from, to = cmd.to, text = "/" .. guess})
    elseif line.info and not line.info.conditions and line.args and line.args.text:sub(1, 1) == "[" then
        problem(out, line.args.from, line.args.to, "warning",
            ("/%s doesn't read [conditions]: they're sent as they are."):format(cmd.name))
    end
    local always -- the clause that always runs: the ones after it never do
    for _, cl in ipairs(line.clauses) do
        for _, g in ipairs(cl.groups) do
            if not g.closed then
                problem(out, g.from, g.to, "error", "This [ has no ].", {from = g.to + 1, to = g.to, text = "]"})
            end
            if g.unit and g.unit.name == "" then
                problem(out, g.unit.from, g.unit.to, "error", "Name a unit after it, such as @mouseover.")
            elseif g.unit and not knownUnit(g.unit.name) then
                problem(out, g.unit.from, g.unit.to, "warning", ("%s isn't a unit the game knows."):format(g.unit.name))
            end
            for _, c in ipairs(g.conds) do checkCondition(c, out) end
        end
        if always and (cl.args or #cl.groups > 0) then
            problem(out, cl.from, cl.to, "warning", "This part never runs: the one before it always does.",
                {from = always.semi, to = cl.to, text = ""})
        end
        local unconditional = #cl.groups == 0
        for _, g in ipairs(cl.groups) do if #g.conds == 0 then unconditional = true end end
        if unconditional and cl.args and not always and line.kind == "command" then always = cl end
        local set = line.info and C.MARKERS[line.info.key]
        local bang = set and not set.prefix and cl.args and cl.args.text:match("^[!~]%s*()")
        if bang then
            problem(out, cl.args.from, cl.args.from + bang - 2, "error",
                ("/%s doesn't take ! or ~ (only /tm does): it does nothing."):format(cmd.name),
                {from = cl.args.from, to = cl.args.from + bang - 2, text = ""})
        end
    end
    checkSpells(line, ctx, out)
end

-- The problems in body, by place: {from, to (bytes), severity ("error" or "warning"), text, fix = {from, to, text}
-- (replacing from..to with text) or nil}. ctx: spells (C.spells()), note (added to an unknown spell's text).
local known, knownFor -- the commands' aliases, sorted, and the table they're from
function C.check(body, ctx)
    ctx = ctx or {}
    local parsed = type(body) == "table" and body or C.parse(body)
    local out = {}
    local all = C.commands()
    if not all.cast then
        known = nil -- the client's commands weren't read: don't call any unknown
    elseif knownFor ~= all then
        known, knownFor = names(all), all
    end
    for _, line in ipairs(parsed.lines) do checkLine(line, ctx, out, known) end
    if #parsed.text > C.LIMIT then
        problem(out, C.LIMIT + 1, #parsed.text, "error",
            ("Too long: %d of %d characters."):format(#parsed.text, C.LIMIT))
    end
    table.sort(out, function(x, y)
        if x.from ~= y.from then return x.from < y.from end
        return x.text < y.text
    end)
    return out, parsed
end

-- Replaces fix's bytes in text: the new text and where the cursor goes (after the fix)
function C.applyFix(text, fix)
    return text:sub(1, fix.from - 1) .. fix.text .. text:sub(fix.to + 1), fix.from - 1 + #fix.text
end

-- Colours -----------------------------------------------------------------------------------------------------------

C.COLORS = {text = "ffd8d8d8", command = "ff5fb4ff", directive = "ffc792ea", condition = "ffe6c07b", unit = "ff56d6c2",
    value = "fff2a65a", punct = "ff7f848e", chat = "ff9aa0a8", spell = "ffffffff"}
local COLORS = C.COLORS

-- line as coloured text for a FontString: every | doubled, so it shows as typed
function C.highlight(line)
    local s = line.text
    if s == "" then return "" end
    local base, paint = line.from - 1, {}
    local function set(from, to, color)
        for p = math.max(1, from - base), math.min(#s, to - base) do paint[p] = color end
    end
    set(line.from, line.to, line.kind == "command" and (line.info and line.info.secure and COLORS.spell or COLORS.chat)
        or line.kind == "directive" and COLORS.spell or COLORS.chat)
    if line.cmd then set(line.cmd.from, line.cmd.to, line.kind == "directive" and COLORS.directive or COLORS.command) end
    for _, cl in ipairs(line.clauses) do
        for _, g in ipairs(cl.groups) do
            set(g.from, g.to, COLORS.punct)
            if g.unit then set(g.unit.from, g.unit.to, COLORS.unit) end
            for _, c in ipairs(g.conds) do
                set(c.from, c.nameTo, COLORS.condition)
                if c.valueFrom then set(c.valueFrom, c.valueTo, COLORS.value) end
            end
        end
        for _, item in ipairs(cl.args and cl.args.items or {}) do
            if item.rankFrom then set(item.rankFrom, item.rankTo, COLORS.value) end
        end
        if cl.semi then set(cl.semi, cl.semi, COLORS.punct) end
    end
    local out, runStart = {}, 1
    for p = 2, #s + 1 do
        if p > #s or paint[p] ~= paint[runStart] then
            out[#out + 1] = "|c" .. (paint[runStart] or COLORS.text) .. s:sub(runStart, p - 1):gsub("|", "||") .. "|r"
            runStart = p
        end
    end
    return table.concat(out)
end

-- Now, and in a list ------------------------------------------------------------------------------------------------

local function readable(v) return v ~= nil and not (issecretvalue ~= nil and issecretvalue(v)) and v or nil end

-- What the macro's first command that would do something does right now, as "/cast Flash of Light on Ku Req", or nil.
-- Lines with problems aren't asked (the game prints a bad condition to chat).
function C.now(parsed, problems)
    if not SecureCmdOptionParse then return nil end
    local bad = {}
    for _, p in ipairs(problems or {}) do if p.severity == "error" then bad[#bad + 1] = p end end
    for _, line in ipairs(parsed.lines) do
        local clean = true
        for _, p in ipairs(bad) do if p.from <= line.to + 1 and p.to >= line.from then clean = false end end
        if clean and line.info and line.info.conditions then
            local rest = parsed.text:sub(line.cmd.to + 1, line.to)
            local ok, action, target = pcall(SecureCmdOptionParse, rest)
            if ok and action ~= nil then
                local set = C.MARKERS[line.info.key]
                local how, n = action:match("^([!~]?)%s*(%d+)$")
                if how ~= "" and not (set and set.prefix) then n = nil end
                local after = ""
                if set and n and set[tonumber(n)] then -- "/tm 8" says "/tm Skull on target"
                    action = set[tonumber(n)].name
                    after = how == "!" and " (keeps it on)" or how == "~" and " (only if unmarked)" or ""
                    if line.info.key == "TARGET_MARKER" then target = target or "target" end
                end
                local text = "/" .. line.cmd.name .. (action ~= "" and " " .. action or "")
                local who = target and target ~= "" and target ~= "player" and readable(UnitName(target)) or target
                if who and who ~= "" then text = text .. " on " .. who end
                return text .. after
            end
        end
    end
end

-- A macro in a few words, for a list: the first spell (or item) it casts, with "+n" for the other choices, else
-- its first command
function C.summary(body)
    local parsed = C.parse(body)
    local first, more, command
    for _, line in ipairs(parsed.lines) do
        if line.info and line.info.spells then
            for _, cl in ipairs(line.clauses) do
                local item = cl.args and cl.args.items[1]
                if item and not first then first = item.name elseif item then more = (more or 0) + 1 end
            end
        elseif line.kind == "command" and not command and line.cmd.name ~= "" then
            command = "/" .. line.cmd.name .. (line.args and " " .. line.args.text or "")
        end
    end
    if first then return first .. (more and (" +%d"):format(more) or "") end
    return command or (body:find("%S") and body:match("^%s*([^\n]*)") or "Empty")
end

-- Completions -------------------------------------------------------------------------------------------------------

local function offer(items, typed, label, insert, detail, live)
    local l, t = label:lower(), typed:lower()
    local at = l:find(t, 1, true)
    if not at then return end
    items[#items + 1] = {label = label, insert = insert or label, detail = detail, live = live, order = at == 1 and 1 or 2}
end
local function finish(items, from, to)
    table.sort(items, function(x, y)
        if x.order ~= y.order then return x.order < y.order end
        if #x.label ~= #y.label and x.label:lower():sub(1, #y.label) == y.label:lower() then return #x.label < #y.label end
        return x.label:lower() < y.label:lower()
    end)
    while #items > 60 do items[#items] = nil end
    return {from = from, to = to, items = items}
end
local function wordEnd(text, p, pattern) -- the last byte of the word from p on
    local e = text:match("^" .. pattern .. "*()", p)
    return e - 1
end

-- yes or no: is condition name (no: its no form) true now? nil when it can't be asked without a value
function C.live(name, no)
    local def = CONDITIONS[name]
    if not (def and def.value ~= "need" and SecureCmdOptionParse) then return nil end
    local ok, v = pcall(SecureCmdOptionParse, "[" .. (no and "no" or "") .. name .. "] 1")
    if not ok then return nil end
    return v == "1" and "yes" or "no"
end

-- What to offer at cursor (the bytes before the caret) in text: {from, to (the bytes an item replaces), items =
-- {{label, insert, detail, live}}}, or nil
function C.complete(text, cursor, ctx)
    ctx = ctx or {}
    local parsed = C.parse(text)
    local line
    for _, l in ipairs(parsed.lines) do if cursor >= l.from - 1 and cursor <= l.to then line = l end end
    if not line then return nil end
    local before = text:sub(line.from, cursor)
    local items = {}
    local typed = before:match("^%s*#(%a*)$")
    if typed then
        offer(items, typed, "#showtooltip", nil, "Shows the spell's icon and tooltip on the button.")
        offer(items, typed, "#show", nil, "Shows the spell's icon on the button.")
        return finish(items, cursor - #typed, wordEnd(text, cursor + 1, "%a"))
    end
    typed = before:match("^%s*/([%w_]*)$")
    if typed then
        for alias, info in pairs(C.commands()) do
            offer(items, typed, "/" .. alias, nil, info.conditions and "Works with [conditions]" or info.emote and "Emote"
                or "Command")
        end
        return finish(items, cursor - #typed, wordEnd(text, cursor + 1, "[%w_]"))
    end
    local open, close = before:match(".*()%["), before:match(".*()%]")
    if open and (not close or close < open) then
        local seg = before:sub(open + 1):match("([^,]*)$"):gsub("^%s+", "")
        local unit = seg:match("^@(%w*)$") or seg:lower():match("^target%s*=%s*(%w*)$")
        if unit then
            for _, u in ipairs(UNITS) do offer(items, unit, u, nil, "Unit") end
            return finish(items, cursor - #unit + 1, wordEnd(text, cursor + 1, "%w"))
        end
        local name, value = seg:match("^(%a+)%s*:(.*)$")
        if name then
            local lower = name:lower()
            local def = CONDITIONS[lower] or (lower:sub(1, 2) == "no" and CONDITIONS[lower:sub(3)])
            value = value:match("([^/]*)$"):gsub("^%s+", "")
            for _, v in ipairs(def and def.values or {}) do offer(items, value, v, nil, def.text) end
            if def and def.name == "known" or def and def.name == "channeling" then
                for _, e in ipairs((ctx.spells or {list = {}}).list) do offer(items, value, e.name, nil, "Spell") end
            end
            return finish(items, cursor - #value + 1, wordEnd(text, cursor + 1, "[^,%]/;\n]"))
        end
        local word = seg:match("^(%a*)$")
        if word then
            local no = word:lower():sub(1, 2) == "no" and #word > 2
            for _, n in ipairs(CONDITION_NAMES) do
                local def = CONDITIONS[n]
                if not ALIASES[n] then
                    offer(items, word, n, nil, def.text, C.live(n))
                    if no and def.no ~= false then offer(items, word, "no" .. n, nil, def.text, C.live(n, true)) end
                end
            end
            return finish(items, cursor - #word + 1, wordEnd(text, cursor + 1, "%a"))
        end
        return nil
    end
    local set = line.info and C.MARKERS[line.info.key]
    if set then -- the marker after /tm (and its ! or ~), /wm or /cwm, by icon and name; the number goes in
        local word = before:sub((line.cmd.to - line.from) + 2):match("([^;%]]*)$"):gsub("^%s+", "")
        if set.prefix then word = word:gsub("^[!~]%s*", "") end
        if not word:find("^%w*$") then return nil end
        for n, m in ipairs(set) do
            local count = #items
            offer(items, word, n .. " " .. m.name, tostring(n), set.what)
            if items[count + 1] then items[count + 1].icon = m.icon end
        end
        if line.info.key == "CLEAR_WORLD_MARKER" then offer(items, word, "all", nil, "Every world marker") end
        if #items == 0 then return nil end
        return finish(items, cursor - #word + 1, wordEnd(text, cursor + 1, "%w"))
    end
    if not (line.info and line.info.spells) then return nil end
    -- a spell: the word after the last ; ] or , (and after a reset= or !)
    local tail = before:sub((line.cmd.to - line.from) + 2)
    local word = tail:match("([^;%],]*)$"):gsub("^%s+", ""):gsub("^[Rr][Ee][Ss][Ee][Tt]=%S*%s+", ""):gsub("^!%s*", "")
    if word == "" or word:find("^[Rr][Ee][Ss][Ee][Tt]=") then return nil end
    for _, e in ipairs((ctx.spells or {list = {}}).list) do
        offer(items, word, e.name, nil, "Spell")
        for _, r in ipairs(e.list) do offer(items, word, ("%s(Rank %d)"):format(e.name, r), nil, "Rank " .. r) end
    end
    if #items == 0 then return nil end
    return finish(items, cursor - #word + 1, wordEnd(text, cursor + 1, "[^,;\n]"))
end

-- Editing keys, as in a shell (zsh/emacs) and most editors. Each takes the text and the caret (bytes before it) and
-- returns the new text and caret, or nil when the key isn't one of these. ctrl/alt: whether held.
local function lineStart(t, pos) local s = pos; while s > 0 and t:sub(s, s) ~= "\n" do s = s - 1 end return s end
local function lineEnd(t, pos) local e = pos; while e < #t and t:sub(e + 1, e + 1) ~= "\n" do e = e + 1 end return e end
local function wordBack(t, pos)
    local p = pos
    while p > 0 and t:sub(p, p):match("%s") do p = p - 1 end
    while p > 0 and not t:sub(p, p):match("%s") do p = p - 1 end
    return p
end
local function wordForward(t, pos)
    local p = pos
    while p < #t and t:sub(p + 1, p + 1):match("%s") do p = p + 1 end
    while p < #t and not t:sub(p + 1, p + 1):match("%s") do p = p + 1 end
    return p
end
-- the keys, as the editor's (?) lists them
C.KEYS = {
    {"Ctrl+Z", "Undo"}, {"Ctrl+Shift+Z, Ctrl+Y", "Redo"},
    {"Ctrl+A / Ctrl+E", "Start / end of the line"},
    {"Ctrl+B / Ctrl+F", "A letter back / forward"},
    {"Alt+B / Alt+F, Ctrl+Left / Right", "A word back / forward"},
    {"Ctrl+W, Ctrl+Backspace", "Delete the word before"}, {"Alt+D", "Delete the next word"},
    {"Ctrl+U / Ctrl+K", "Delete to the start / end of the line"},
    {"Tab", "Take a suggestion, or fix a problem"}, {"Up / Down", "Choose a suggestion"},
    {"Shift+arrows", "Select"}, {"Ctrl+Shift+A", "Select everything"},
}
function C.editKey(key, text, pos, ctrl, alt)
    key = key and key:upper()
    if ctrl then
        if key == "A" then return text, lineStart(text, pos) end
        if key == "E" then return text, lineEnd(text, pos) end
        if key == "B" then return text, math.max(0, pos - 1) end
        if key == "F" then return text, math.min(#text, pos + 1) end
        if key == "W" or key == "BACKSPACE" then -- the word before the caret
            local s = wordBack(text, pos)
            return text:sub(1, s) .. text:sub(pos + 1), s
        end
        if key == "U" then local s = lineStart(text, pos) return text:sub(1, s) .. text:sub(pos + 1), s end
        if key == "K" then local e = lineEnd(text, pos) return text:sub(1, pos) .. text:sub(e + 1), pos end
        if key == "LEFT" then return text, wordBack(text, pos) end
        if key == "RIGHT" then return text, wordForward(text, pos) end
    elseif alt then
        if key == "B" or key == "LEFT" then return text, wordBack(text, pos) end
        if key == "F" or key == "RIGHT" then return text, wordForward(text, pos) end
        if key == "D" then local e = wordForward(text, pos) return text:sub(1, pos) .. text:sub(e + 1), pos end
        if key == "BACKSPACE" then local s = wordBack(text, pos) return text:sub(1, s) .. text:sub(pos + 1), s end
    end
end

-- Undo history: states {text, pos}; typing within a second joins the step before it.
function C.History(max)
    local h = {past = {}, future = {}, max = max or 100}
    function h:Record(text, pos, now)
        local last = self.past[#self.past]
        if last and last.text == text then return end
        if not (last and now and self.at and now - self.at < 1 and self.typing) then
            self.past[#self.past + 1] = {text = text, pos = pos}
            if #self.past > self.max then table.remove(self.past, 1) end
        end
        self.at, self.typing, self.future = now, true, {}
    end
    function h:Break() self.typing = false end -- the next change starts a new step
    function h:Undo(text, pos)
        local s = table.remove(self.past)
        if not s then return end
        self.future[#self.future + 1] = {text = text, pos = pos}
        self.typing = false
        return s.text, s.pos
    end
    function h:Redo(text, pos)
        local s = table.remove(self.future)
        if not s then return end
        self.past[#self.past + 1] = {text = text, pos = pos}
        self.typing = false
        return s.text, s.pos
    end
    function h:Reset() self.past, self.future, self.typing = {}, {}, false end
    return h
end
