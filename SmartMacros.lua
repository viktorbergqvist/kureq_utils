-- Smart macros (part of Macros): General (account) macros Kureq Utils keeps up to date by itself, shared by all your
-- characters and written for the one logged in (its bags, class, spells and mounts). KU Potion, KU Mana, KU
-- Drink, KU Food and KU Bandage use the best one in your bags, by item ID (the strongest you can use; conjured first
-- on KU Drink and KU Food while that's ticked, Healthstone first on KU Potion while that's ticked); KU Hearth your
-- hearth item; KU Mount dismounts, else casts your fastest mount (a random favourite of that speed, picked again after
-- each ride; only favourites while "Favourites only" is ticked); KU Pet (hunters, warlocks) does what you set for no
-- key, Shift, Ctrl and Alt. Each is off until ticked in the Macros window's Smart macros tab (SmartMacrosWindow.lua;
-- account-wide, KureqUtilsDB.smartMacros). They're written out of combat (ns.CombatQueue) and
-- not while Blizzard's macro window is open, when bags, level, skills, spells, spell texts or your mount change. Only
-- macros it made are touched: smartMacros.made keeps each one's name and the text last written, and a macro whose text
-- changed elsewhere (or that's gone) is let go: unticked and never touched again. Every rewrite and delete keeps the
-- version before it in the Macros history.
local _, ns = ...
local M, C = ns.macros, ns.macroCode
local SM = {}
M.smart = SM

SM.KINDS = {"potion", "mana", "drink", "food", "bandage", "hearth", "mount", "pet"}
SM.NAMES = {potion = "KU Potion", mana = "KU Mana", drink = "KU Drink", food = "KU Food", bandage = "KU Bandage",
    hearth = "KU Hearth", mount = "KU Mount", pet = "KU Pet"}
SM.TEXT = {potion = "Drinks the strongest healing potion in your bags that your level allows.",
    mana = "Drinks the strongest mana potion in your bags that your level allows.",
    drink = "Drinks the best drink in your bags that your level allows.",
    food = "Eats the best food in your bags that your level allows.",
    bandage = "Uses the best bandage in your bags that your First Aid allows.",
    hearth = "Uses your Hearthstone, or another hearth item you carry.",
    mount = "Dismounts when you're mounted, else rides your fastest mount (a random favourite of that speed, picked "
        .. "again after each ride). Where you can't mount (indoors, in combat, swimming) or with no mount, it uses "
        .. "your travel form: Ghost Wolf, Travel, Cat or Aquatic Form, or Aspect of the Cheetah.",
    pet = "Your pet's actions: pick what it does with no key held, with Shift, with Ctrl and with Alt."}
SM.ICONS = {potion = "INV_Potion_54", mana = "INV_Potion_76", drink = "INV_Drink_07", food = "INV_Misc_Food_14",
    bandage = "INV_Misc_Bandage_15", hearth = "INV_Misc_Rune_01", mount = "Ability_Mount_RidingHorse",
    pet = "Ability_Hunter_BeastCall"}
local QUESTION_MARK = 134400
-- Healthstones (every size and talent rank): their data reads as any other healing item, so they're named here
local HEALTHSTONES = {}
for _, id in ipairs({5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009, 5510, 19010, 19011, 9421, 19012, 19013}) do
    HEALTHSTONES[id] = true
end
local HEARTH_SPELL = 8690 -- what a Hearthstone casts

-- Pet actions: key -> {spell IDs it casts, its label}. Names come from the game, in your language.
local function spellName(id)
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
    if type(info) == "table" then return info.name end
    return GetSpellInfo and GetSpellInfo(id) or nil
end
SM.PET_ACTIONS = {
    HUNTER = {{"callrevive", 883, 982, "Call Pet, or Revive Pet when it's dead"}, {"call", 883}, {"revive", 982},
        {"mend", 136}, {"dismiss", 2641}},
    WARLOCK = {{"imp", 688}, {"voidwalker", 697}, {"succubus", 712}, {"felhunter", 691}},
}
SM.ROWS = {{"none", "No key"}, {"shift", "Shift"}, {"ctrl", "Ctrl"}, {"alt", "Alt"}}
local DEFAULT_PET = {HUNTER = {none = "callrevive", shift = "mend", ctrl = "dismiss", alt = ""},
    WARLOCK = {none = "imp", shift = "voidwalker", ctrl = "succubus", alt = "felhunter"}}

-- The settings, account-wide in KureqUtilsDB.smartMacros (KU Pet's rows per class). Until 2026-11-13 they were per
-- character (KureqUtilsCharDB.smartMacros): the first character to log in after that seeds the shared settings, and
-- each character adds its own ticks, so no character loses a macro from its bars. Its old table stays (SM.moveOld
-- reads the macros it made).
local SEEDED = {"healthstone", "favourites", "noForm", "formFirst", "pingCompanionsOff"}
local function seed(s, old)
    for kind, v in pairs(type(old.on) == "table" and old.on or {}) do
        if v == true and type(kind) == "string" then s.on[kind] = true end
    end
    if not s.seeded then
        for _, k in ipairs(SEEDED) do if s[k] == nil then s[k] = old[k] end end
        if old.pingMoved then s.pingCompanionsSet = true end -- its companions setting was decided
        for _, k in ipairs({"drink", "food"}) do
            if type(old.conjured) == "table" and type(old.conjured[k]) == "boolean" then s.conjured[k] = old.conjured[k] end
        end
        s.seeded = true
    end
    local _, class = UnitClass("player")
    if DEFAULT_PET[class] and type(old.pet) == "table" and s.pet[class] == nil then
        local rows = {}
        for _, row in ipairs(SM.ROWS) do
            if type(old.pet[row[1]]) == "string" then rows[row[1]] = old.pet[row[1]] end
        end
        s.pet[class] = rows
    end
end
local function db()
    local root, c = ns.db, ns.charDB
    if type(root) ~= "table" or type(c) ~= "table" then return nil end
    local s = type(root.smartMacros) == "table" and root.smartMacros or {}
    root.smartMacros = s
    for _, k in ipairs({"on", "made", "pet", "conjured"}) do if type(s[k]) ~= "table" then s[k] = {} end end
    local old = c.smartMacros
    if type(old) == "table" and not old.shared then
        seed(s, old)
        old.shared = true
    end
    s.seeded = true -- whoever logs in first sets the account up: a character from before seeds only its ticks then
    if s.healthstone == nil then s.healthstone = true end
    for _, k in ipairs({"drink", "food"}) do if s.conjured[k] == nil then s.conjured[k] = true end end -- conjured first
    local _, class = UnitClass("player")
    if DEFAULT_PET[class] then
        local rows = type(s.pet[class]) == "table" and s.pet[class] or {}
        s.pet[class] = rows
        for row, v in pairs(DEFAULT_PET[class]) do if rows[row] == nil then rows[row] = v end end
    end
    return s
end
SM.db = db
-- KU Pet's rows (row -> action key) for the class you're on
function SM.petRows()
    local s = db()
    local _, class = UnitClass("player")
    return s and s.pet[class] or {}
end

-- Your bags -----------------------------------------------------------------------------------------------------------

local function largest(text) -- the biggest number in a text ("455 to 585" -> 585)
    local best = 0
    for n in (text or ""):gsub(",", ""):gmatch("%d+") do best = math.max(best, tonumber(n)) end
    return best
end
local textPending = {} -- spell IDs whose text was empty (not loaded yet): their SPELL_TEXT_UPDATE updates again
local function spellText(id)
    local get = C_Spell and C_Spell.GetSpellDescription or GetSpellDescription
    local text = id and get and get(id) or ""
    if id and text == "" then textPending[id] = true end
    return text
end
-- How much a use text restores of what ("health" or "mana"): "Restores 455 to 585 health", "Restores 61.2 health over
-- 18 sec", "Instantly restores 100 health"; nil for anything else: a buff to maximum health, or a cost in life or damage
-- (Demonic Rune)
function SM.restores(text, what)
    if text:find("maximum") or text:find("damage") or text:find("cost") or text:find(" life") then return nil end
    local _, high = text:match("restores ([%d%.]+) to ([%d%.]+) " .. what)
    return tonumber(high or text:match("restores ([%d%.]+) " .. what))
end
-- item ID -> {conjured, skill, instance} from its bag tooltip, kept: neither changes, and every bag change while
-- looting updates the macros, which read each usable item's tooltip again. A tooltip read before its data loaded gets
-- TOOLTIP_DATA_UPDATE for its data instance later, and is read again then.
local tipInfo = {}
-- data instance -> item ID of an empty tooltip in the last bag read (an empty one is never kept: every bag read reads
-- it again). Its update refreshes the macros by itself at most TIP_TRIES times per item a session (tipTries).
local tipEmpty, tipTries, TIP_TRIES = {}, {}, 3
local function tooltipLines(bag, slot)
    local data = C_TooltipInfo and C_TooltipInfo.GetBagItem and C_TooltipInfo.GetBagItem(bag, slot)
    local out = {}
    for _, line in ipairs(data and data.lines or {}) do out[#out + 1] = line.leftText or "" end
    return out, data and data.dataInstanceID
end
-- "Requires First Aid (150)" from the client's own string
local SKILL_PATTERN = ITEM_MIN_SKILL and "^" .. ITEM_MIN_SKILL:gsub("[%(%)%.%-%+%[%]]", "%%%0"):gsub("%%s", "(.+)")
    :gsub("%%d", "(%%d+)") .. "$"
local function skillRank(name)
    if C_SkillInfo and C_SkillInfo.GetNumSkillLines then
        for i = 1, C_SkillInfo.GetNumSkillLines() do
            local l = C_SkillInfo.GetSkillLineInfo(i)
            if l and l.name == name then return l.rank or 0 end
        end
    elseif GetNumSkillLines then
        for i = 1, GetNumSkillLines() do
            local n, _, _, rank = GetSkillLineInfo(i)
            if n == name then return rank or 0 end
        end
    end
    return 0
end

-- What one bag item is good for: {id, name, count, kinds = {kind -> true}, amounts = {kind -> how much}, level,
-- conjured, skill = {name, rank}} or nil. Kinds come from the item's class and use spell: a potion (Consumable or
-- Potion subclass, never an elixir or flask) whose spell restores health or mana, food and drink (eaten seated) that
-- restore them, a bandage is a consumable of the bandage subclass.
-- shortcut: health, mana and "seated" are read from the English spell text; other languages need the spell's
-- effect data (not exposed) or a word list.
function SM.read(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not (info and info.itemID) then return nil end
    local id = info.itemID
    local name, _, _, _, minLevel, _, _, _, _, _, _, classID, subclassID = C_Item.GetItemInfo(id)
    if not name then return nil end
    local _, spellID = C_Item.GetItemSpell(id)
    local item = {id = id, name = name, count = info.stackCount or 1, level = minLevel or 0, kinds = {}, amounts = {}}
    local text = spellText(spellID):lower():gsub(",", "")
    local function add(kind, amount) if amount then item.kinds[kind], item.amounts[kind] = true, amount end end
    if HEALTHSTONES[id] then
        item.healthstone = true
        add("potion", largest(text))
    elseif id == 6948 or spellID == HEARTH_SPELL then
        item.kinds.hearth = true
    elseif classID == 15 and subclassID == 5 then -- Miscellaneous: Mount
        item.kinds.mount = true
    elseif classID == 0 and subclassID == 7 then -- Consumable: Bandage
        add("bandage", largest(text))
    elseif classID == 0 and (subclassID == 0 or subclassID == 1 or subclassID == 5) then -- Consumable, Potion, Food
        local seated = text:find("seated")
        if seated or subclassID ~= 5 then
            add(seated and "food" or "potion", SM.restores(text, "health"))
            add(seated and "drink" or "mana", SM.restores(text, "mana"))
        end
    end
    if not next(item.kinds) then return nil end
    local tip = tipInfo[id]
    if not tip then
        local lines, instance = tooltipLines(bag, slot)
        tip = {instance = instance}
        for _, line in ipairs(lines) do
            if ITEM_CONJURED and line == ITEM_CONJURED then tip.conjured = true end
            local skill, rank
            if SKILL_PATTERN then skill, rank = line:match(SKILL_PATTERN) end
            if skill then tip.skill = {name = skill, rank = tonumber(rank)} end
        end
        if #lines > 0 then
            tipInfo[id] = tip
        elseif instance and (tipTries[id] or 0) < TIP_TRIES then -- never kept; its update may bring the next read
            tipEmpty[instance] = id
        end
    end
    item.conjured, item.skill = tip.conjured, tip.skill
    return item
end
function SM.bagItems()
    wipe(tipEmpty) -- only what's in the bags now waits for its tooltip
    local items = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local item = SM.read(bag, slot)
            if item then items[#items + 1] = item end
        end
    end
    return items
end

-- The item kind should use from items, or nil: one you can use (level, skill), the strongest, ties to the first found
-- (the macro uses the item, not a stack); conjured first while opts.conjured is set, a Healthstone first for potions
-- while opts.healthstone is
function SM.choose(kind, items, opts)
    opts = opts or {}
    local level, best = opts.level or UnitLevel("player") or 1, nil
    local function better(a, b)
        if opts.healthstone and kind == "potion" and a.healthstone ~= b.healthstone then return a.healthstone end
        if opts.conjured and (a.conjured or false) ~= (b.conjured or false) then return a.conjured end
        return (a.amounts[kind] or 0) > (b.amounts[kind] or 0)
    end
    for _, item in ipairs(items) do
        local usable = item.kinds[kind] and item.level <= level
            and not (item.skill and (opts.skill or skillRank)(item.skill.name) < item.skill.rank)
        if usable and (not best or better(item, best)) then best = item end
    end
    return best
end

-- Mounts --------------------------------------------------------------------------------------------------------------

-- How fast a mount is, from its spell text ("increases speed by 100%"; "very fast" 100, "fast" 60)
-- shortcut: English spell text, as for items above.
local function speed(text)
    text = (text or ""):lower()
    local n = tonumber(text:match("(%d+)%%"))
    if n then return n end
    if text:find("very fast") then return 100 end
    if text:find("fast") then return 60 end
    return 0
end
-- Your mounts: {name (to /cast or /use), speed, favorite, item}; journal mounts, else mount items in your bags
function SM.mounts(items)
    local out = {}
    local J = C_MountJournal
    if J and J.GetMountIDs then
        for _, id in ipairs(J.GetMountIDs() or {}) do
            local name, spellID, _, _, usable, _, favorite, _, _, hidden, collected = J.GetMountInfoByID(id)
            if name and usable and collected and not hidden then
                out[#out + 1] = {name = spellName(spellID) or name, speed = speed(spellText(spellID)), favorite = favorite}
            end
        end
    end
    for _, item in ipairs(items or {}) do
        if item.kinds.mount and item.level <= (UnitLevel("player") or 1) then
            out[#out + 1] = {name = item.name, speed = speed(spellText(select(2, C_Item.GetItemSpell(item.id)))), item = item.id}
        end
    end
    return out
end
-- The fastest mount, a random favourite among the fastest when there are any; with favouritesOnly, the fastest of
-- your favourites (any mount when you have none)
function SM.pickMount(mounts, random, favouritesOnly)
    if favouritesOnly then
        local favs = {}
        for _, m in ipairs(mounts) do if m.favorite then favs[#favs + 1] = m end end
        if #favs > 0 then mounts = favs end
    end
    local top, favs, all = -1, {}, {}
    for _, m in ipairs(mounts) do top = math.max(top, m.speed) end
    for _, m in ipairs(mounts) do
        if m.speed == top then
            all[#all + 1] = m
            if m.favorite then favs[#favs + 1] = m end
        end
    end
    local list = #favs > 0 and favs or all
    if #list == 0 then return nil end
    return list[#favs > 0 and (random or math.random)(#list) or 1]
end

-- The macros' text ------------------------------------------------------------------------------------------------------

local function none(kind)
    return ("#showtooltip\n/run print(\"%s: none in your bags.\")"):format(SM.NAMES[kind])
end
local function known(id)
    local name = spellName(id)
    return name and C.spells().byName[name:lower()] and name or nil
end
-- KU Pet's /cast lines from its rows (settings.pet: row -> action key), leaving out spells you don't know
function SM.petBody(class, rows)
    local actions = {}
    for _, a in ipairs(SM.PET_ACTIONS[class] or {}) do actions[a[1]] = a end
    local clauses, extra = {}, nil
    for i = 2, #SM.ROWS + 1 do
        local row = SM.ROWS[i] or SM.ROWS[1] -- the modifiers first, no key last
        local a = actions[rows[row[1]] or ""]
        local cond = row[1] ~= "none" and "[mod:" .. row[1] .. "]" or nil
        if a and a[1] == "callrevive" then
            local call, revive = known(883), known(982)
            if revive then clauses[#clauses + 1] = (cond and cond:sub(1, -2) .. "," or "[") .. "@pet,dead] " .. revive end
            if call then clauses[#clauses + 1] = (cond and cond:sub(1, -2) .. "," or "[") .. "nopet] " .. call end
            if call and revive then extra = ("/cast [nopet%s] %s"):format(cond and ",mod:" .. row[1] or ",nomod", revive) end
        elseif a then
            local name = known(a[2])
            if name then clauses[#clauses + 1] = (cond and cond .. " " or "") .. name end
        end
    end
    if #clauses == 0 then return nil end
    return "#showtooltip\n/cast " .. table.concat(clauses, "; ") .. (extra and "\n" .. extra or "")
end

-- Your class's way to move faster where you can't mount, as /cast clauses, leaving out what you don't know:
-- shaman Ghost Wolf, druid Aquatic Form swimming, Travel Form outdoors, else Cat Form, hunter Aspect of the Cheetah
local FORMS = {SHAMAN = {{"", 2645}}, HUNTER = {{"", 5118}},
    DRUID = {{"[swimming] ", 1066}, {"[outdoors] ", 783}, {"", 768}}}
function SM.formClauses(class)
    local out = {}
    for _, f in ipairs(FORMS[class] or {}) do
        local name = known(f[2])
        if name then out[#out + 1] = f[1] .. name end
    end
    return #out > 0 and table.concat(out, "; ") or nil
end
local RIDE = "[nomounted,outdoors,nocombat,noswimming]" -- where a mount can be ridden

-- The text kind's macro should have now
function SM.body(kind, items)
    local s = db() or {}
    if kind == "pet" then
        local _, class = UnitClass("player")
        if not SM.PET_ACTIONS[class] then return "#showtooltip\n/run print(\"KU Pet: your class has no pet.\")" end
        return SM.petBody(class, SM.petRows()) or ("#showtooltip\n/run print(\"KU Pet: you don't know those pet "
            .. "spells yet.\")")
    end
    items = items or SM.bagItems()
    if kind == "mount" then
        local m = SM.pickMount(SM.mounts(items), nil, s.favourites)
        local _, class = UnitClass("player")
        local form = not s.noForm and SM.formClauses(class) or nil -- "Travel form" ticked (the default)
        if form and s.formFirst then m = nil end -- "Form instead of a mount": the form everywhere
        if not m and not form then
            return "#showtooltip\n/dismount [mounted]\n/run print(\"KU Mount: no mount you can ride.\")"
        end
        local lines = {"#showtooltip", "/dismount [mounted]"}
        if m then
            lines[#lines + 1] = m.item and ("/use %s item:%d"):format(RIDE, m.item) or ("/cast %s %s"):format(RIDE, m.name)
        end
        if form then
            if m then lines[#lines + 1] = "/stopmacro [mounted][outdoors,nocombat,noswimming]" end -- it rode
            lines[#lines + 1] = "/cast " .. form
        end
        return table.concat(lines, "\n")
    end
    local item = SM.choose(kind, items, SM.opts(kind))
    if not item then return none(kind) end
    return "#showtooltip\n/use item:" .. item.id -- by ID: the item picked (a Healthstone's rank too), not its name
end
-- The settings SM.choose picks kind's item by
function SM.opts(kind)
    local s = db() or {conjured = {}}
    return {healthstone = s.healthstone, conjured = s.conjured[kind]}
end

-- What kind's macro uses now, as its row says it: "Major Healing Potion x3", "none in your bags", the mount, KU Pet's
-- no-key action, or "off" while it isn't ticked
function SM.uses(kind, items)
    local s = db()
    if not (s and s.on[kind]) then return "off" end
    if kind == "pet" then
        local _, class = UnitClass("player")
        for _, a in ipairs(SM.PET_ACTIONS[class] or {}) do
            if a[1] == SM.petRows().none then return "No key: " .. SM.actionLabel(a) end
        end
        return "No key: nothing"
    end
    items = items or SM.bagItems()
    if kind == "mount" then -- the mount picked last (a random favourite), as the macro has it
        local body = s.made.mount and s.made.mount.body or SM.body("mount", items)
        local id = tonumber(body:match("item:(%d+)"))
        local ride = (id and C_Item.GetItemInfo(id)) or body:match("/cast %[nomounted,outdoors,nocombat,noswimming%] ([^\n]+)")
        if ride and body:find("/stopmacro") then return ride .. ", else your travel form" end
        return ride or (body:find("\n/cast [^\n]*$") and not body:find("/run") and "Your travel form" or nil)
            or "no mount you can ride"
    end
    local item = SM.choose(kind, items, SM.opts(kind))
    if not item then return "none in your bags" end
    if kind == "hearth" then return item.name end
    local n = 0
    for _, it in ipairs(items) do if it.id == item.id then n = n + it.count end end
    return ("%s x%d"):format(item.name, n)
end

-- Writing them --------------------------------------------------------------------------------------------------------

local told = {} -- what was said in chat already this session
local function sayOnce(key, text)
    if told[key] then return end
    told[key] = true
    ns.say(text)
end
SM.sayOnce = sayOnce
-- The macro called name in a scope (account true, else character), and whether there are two
local function find(name, account)
    local found, n = nil, 0
    for _, m in ipairs(M.list()) do
        if not m.account == not account and m.name == name then found, n = m, n + 1 end
    end
    return found, n > 1
end
SM.find = find
-- Ticking a smart macro on takes over a macro of its name that's already there (one it gave up, say): ticking it is
-- the player asking for it. A name used twice is left alone.
function SM.adopt(holder, key, name, account)
    local m, twin = find(name, account)
    if m and not twin then holder[key] = {name = name, body = m.body} end
end

-- Macros are known once the world has loaded and the game has sent UPDATE_MACROS (or a moment after the world loads):
-- before that a missing macro may just not be listed yet, so nothing is written, made or let go.
SM.ready, SM.READY_DELAY, SM.onReady = false, 3, {}
local worldLoaded
local function becomeReady()
    if SM.ready or not worldLoaded then return end
    SM.ready = true
    for _, fn in ipairs(SM.onReady) do fn() end
    if SM.schedule then SM.schedule() end
end

-- Brings the macro called name (account or character) to body, or deletes it when body is nil, only while it's ours:
-- holder[key] keeps {name, body} as the game kept what was last written. A macro whose text differs from that, or
-- that's gone, is the player's now (holder[key] cleared, "lost"). Every rewrite and delete keeps the version before it
-- in the history. Returns "ok", "off", "lost", "twin", "taken" (one of that name isn't ours) or "full" and why. Call
-- it out of combat, with Blizzard's macro window closed, once SM.ready.
-- Two macro texts are the same text when they differ only in line endings or trailing space: after a reload the game
-- hands a macro back with \r\n line ends (and can add a last new line), which once gave up every smart macro.
local function plainText(t) return (tostring(t or ""):gsub("\r", ""):gsub("%s+$", "")) end
function SM.sameText(a, b) return plainText(a) == plainText(b) end
function SM.keep(holder, key, name, account, body, icon)
    local rec = holder[key]
    if type(rec) ~= "table" or rec.name ~= name or type(rec.body) ~= "string" then rec, holder[key] = nil, nil end
    local m, twin = find(name, account)
    if twin then return "twin" end
    if rec and not (m and SM.sameText(m.body, rec.body)) then
        holder[key] = nil
        return "lost"
    end
    local snapshot = m and {name = m.name, icon = m.icon, body = m.body, account = account}
    if not body then
        if rec then
            M.remember(snapshot, "Deleted")
            DeleteMacro(m.index)
            holder[key] = nil
        end
        return "off"
    end
    if m and not rec then return "taken" end
    if m then
        if not SM.sameText(m.body, body) then
            M.remember(snapshot, "Updated")
            EditMacro(m.index, nil, nil, body)
        end
    else
        local why = M.full(account)
        if why then return "full", why end
        CreateMacro(name, icon or QUESTION_MARK, body, not account or nil)
    end
    local now = find(name, account) -- read back: the text as the game keeps it
    holder[key] = {name = name, body = now and now.body or body}
    return "ok"
end

-- Once per character: the character macros it made before smart macros were shared (KureqUtilsCharDB.smartMacros.made)
-- give way to the General ones. Each goes on the same bar slots: moved to General when there's none of its name yet,
-- else deleted for the one another character made. One the player changed, or one whose name a General macro of the
-- player's has, is left as it is (the player's now). With the General macros full it says so once and keeps them all,
-- to try again next login.
function SM.moveOld(s)
    local old = ns.charDB and ns.charDB.smartMacros
    if type(old) ~= "table" or old.macrosMoved then return end
    local made = type(old.made) == "table" and old.made or {}
    for _, kind in ipairs(SM.KINDS) do
        local rec = made[kind]
        local m, twin
        if type(rec) == "table" and type(rec.name) == "string" then m, twin = find(rec.name, false) end
        if m and not twin and SM.sameText(m.body, rec.body) then
            local shared, sharedTwin = find(m.name, true)
            local ours = s.made[kind]
            if not shared then
                local moved, why = M.move(m, true)
                if not moved then
                    if M.full(true) then
                        sayOnce("movefull", ("Smart macros are shared by all your characters now, as General macros. "
                            .. "%s Until then this character keeps its own."):format(why))
                        return
                    end
                else
                    s.made[kind] = {name = moved.name, body = moved.body}
                end
            elseif not sharedTwin and type(ours) == "table" and ours.name == m.name and SM.sameText(shared.body, ours.body) then
                M.replace(m, shared)
            end
        elseif type(rec) == "table" and not twin and not s.made[kind] then
            s.on[kind] = nil -- changed or deleted before they were shared: the player's, unticked as before
        end
        made[kind] = nil
    end
    old.macrosMoved = true
end

SM.retry = 5
local schedule
-- Brings every smart macro up to date (out of combat, once macros are known; runs again later while Blizzard's macro
-- window is open)
function SM.update()
    local s = db()
    if not (s and ns.IsOn("macros") and SM.ready) then return end
    if InCombatLockdown() then return schedule() end
    if MacroFrame and MacroFrame:IsShown() then return C_Timer.After(SM.retry, schedule) end
    wipe(textPending)
    SM.moveOld(s)
    local items = next(s.on) and SM.bagItems() or nil -- none ticked: the bags aren't read
    for _, kind in ipairs(SM.KINDS) do
        local name = SM.NAMES[kind]
        local status, why = SM.keep(s.made, kind, name, true, s.on[kind] and SM.body(kind, items) or nil)
        local text
        if status == "lost" then
            s.on[kind] = nil
            text = SM.lostText(name)
            ns.say(text)
        elseif status == "twin" then
            text = ("You have two General macros called %s: delete one for Kureq Utils to keep it up to date.")
                :format(name)
        elseif status == "taken" then
            text = ("You already have a General macro called %s: rename it, and Kureq Utils makes its own."):format(name)
        elseif status == "full" then
            text = ("%s can't be made: %s"):format(name, why)
        end
        if text and status ~= "lost" then sayOnce(kind .. status, text) end
        SM.problems[kind] = text -- what the Smart macros tab says on Update now
    end
    if M.changed then M.changed() end -- the open tab shows counts and ticks even when no macro changed
end
SM.problems = {} -- kind -> why its last update didn't write it, or nil
function SM.lostText(name)
    return ("%s changed outside Kureq Utils, so it's yours now: Kureq Utils won't touch it (tick it again to have "
        .. "Kureq Utils make its own)."):format(name)
end
-- Waits a moment (bags fire many events at once), then updates out of combat
local pending
function schedule()
    if pending then return end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        ns.CombatQueue.Defer("smartmacros", function() SM.update() end) -- as it is then (Debug timing may wrap it)
    end)
end
SM.schedule = schedule

local events = CreateFrame("Frame")
for _, e in ipairs({"PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED",
    "SPELLS_CHANGED", "PLAYER_MOUNT_DISPLAY_CHANGED", "COMPANION_UPDATE"}) do
    events:RegisterEvent(e)
end
events:RegisterEvent("SPELL_TEXT_UPDATE")
events:RegisterEvent("UPDATE_MACROS")
events:SetScript("OnEvent", function(_, event, spellID)
    if event == "SPELL_TEXT_UPDATE" and not textPending[spellID] then return end -- only a text an update lacked
    if event == "PLAYER_ENTERING_WORLD" and not worldLoaded then
        worldLoaded = true
        C_Timer.After(SM.READY_DELAY, becomeReady)
    end
    if event == "UPDATE_MACROS" then becomeReady() end
    if ns.IsOn("macros") then schedule() end
end)
ns.OnModuleChange("macros", function(on) if on then schedule() end end)
-- a tooltip read before its data loaded: forgotten, and the macros updated with the whole tooltip
local tipEvents = CreateFrame("Frame")
pcall(tipEvents.RegisterEvent, tipEvents, "TOOLTIP_DATA_UPDATE") -- a client without the event errors on registering it
tipEvents:SetScript("OnEvent", function(_, _, instance)
    local dropped = false
    for key, id in pairs(tipEmpty) do
        if instance == nil or key == instance then
            tipTries[id], tipEmpty[key], dropped = (tipTries[id] or 0) + 1, nil, true
        end
    end
    if instance == nil then wipe(tipInfo) end -- any may have changed: read again on the next bag read
    for id, tip in pairs(tipInfo) do -- a kept tooltip that changed
        if tip.instance == instance then tipInfo[id], dropped = nil, true end
    end
    if dropped and ns.IsOn("macros") then schedule() end
end)
ns.watch("Smart macros", events)
ns.watch("Smart macros update", SM, "update")

-- For the Smart macros tab: a setting changed (fn gets the saved table), then the macros brought up to date
function SM.change(fn)
    local s = db()
    if s then fn(s) end
    schedule()
end
function SM.actionLabel(a) return a[4] or spellName(a[2]) or a[1] end
