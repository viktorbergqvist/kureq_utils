-- KU Ping (a smart macro, part of Macros): keeps KureqPing, an account macro that targets a mob (or a quest's
-- mobs, from Questie) and pings it. Nothing acts on its own: it rewrites the macro out of combat and you press it.
-- It's off until ticked (account-wide, KureqUtilsDB.smartMacros.on.ping); the old Ping macro module's players
-- start ticked. Like the other smart macros it's written only while it's ours (KureqUtilsDB.ping.made, account-wide as
-- the macro is), out of combat, with Blizzard's macro window closed and once macros are known, and a version is kept
-- before each rewrite. ns.build and ns.writeMacro also serve companion addons through the KureqUtils API.
local _, ns = ...
local SM = ns.macros.smart
local CUSTOM, OLD = "KureqPing", "KureqPingCustom" -- KureqPingCustom: its name until 2026-11-13
local fmt, tinsert = string.format, table.insert
local say, trim = ns.say, ns.trim

ns.defaults.ping = {action = "/ping [@target,nodead]", targetCmd = "/TargetExact", marker = 0, lastTarget = true,
    questClick = true}
local MARKERS = {"Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull"}

local db
ns.listeners = {}
ns.ping = {switched = {}} -- fn(on) when KU Ping is ticked or unticked, or Macros turned off or on (Alert.lua)

-- KU Ping is ticked (and Macros on)
local function pingOn()
    local s = ns.IsOn("macros") and SM.db()
    return s and s.on.ping == true or false
end
ns.ping.on = pingOn

-- Once per character, once macros are known: the Ping macro was its own module, on unless turned off. KU Ping starts
-- ticked when it was on and KureqPingCustom (its old name) exists, and adopts that macro as it is. Turned off, it also kept companion
-- addons' ping macros from being written: that stays off (pingCompanionsOff).
local function migrate()
    local s, c = SM.db(), ns.charDB
    -- per character; before smart macros were shared it was kept in the character's smartMacros
    if not s or c.pingMoved or type(c.smartMacros) == "table" and c.smartMacros.pingMoved then return end
    local modules = c.modules
    if modules.ping == false then
        -- account-wide now: only while no character has decided it yet
        if not s.pingCompanionsSet then s.pingCompanionsOff = true end
    else
        local m, twin = SM.find(OLD, true)
        if m and not twin then
            s.on.ping = true
            db.made = {name = OLD, body = m.body} -- renamed by rename() on the first write
        end
    end
    s.pingCompanionsSet = true -- the first character's choice stands for the account
    c.pingMoved = true
end
tinsert(ns.onLoad, function(root) db = root.ping end)

-- The macro's name: KureqPing, or KureqPingCustom while the one Kureq Utils made under that name can't be renamed yet
local function macroName()
    return db and type(db.made) == "table" and db.made.name == OLD and OLD or CUSTOM
end

-- KureqPingCustom became KureqPing: the one Kureq Utils made (and the player didn't change) is renamed in place, so
-- its bar slots keep it (EditMacro, as Blizzard's own rename), and its ownership record, history and the loadouts'
-- references move with it. A General macro
-- of the player's already called KureqPing blocks it: said once, and KureqPingCustom is kept until that one's gone. A
-- changed one isn't ours: SM.keep lets it go as before. Call it as SM.keep (out of combat, macro window closed).
local function rename()
    local rec = db.made
    if type(rec) ~= "table" or rec.name ~= OLD then return end
    local m, twin = SM.find(OLD, true)
    if not m or twin or not SM.sameText(m.body, rec.body) then return end
    if SM.find(CUSTOM, true) then
        return SM.sayOnce("pingrename", ("KU Ping's macro is called %s now, but you already have a macro of that name: "
            .. "KU Ping keeps using %s until you rename or delete yours."):format(CUSTOM, OLD))
    end
    -- the Macros rename: its history goes with it
    local now = ns.macros.save(m, {name = CUSTOM}, {name = m.name, body = m.body})
    if not now then return end
    db.made = {name = CUSTOM, body = now.body}
    ns.loadouts.renameAccountMacro(OLD, CUSTOM) -- saved loadouts and backups put it on their slots by name
end

-- The lines after the target lines: the marker, the action, and dropping a corpse picked by them.
local function tail()
    local lines = {}
    if db.marker > 0 then tinsert(lines, fmt("/tm [nodead] !%d", db.marker)) end -- "!": don't toggle it off
    tinsert(lines, db.action)
    -- /cleartarget, not /targetlasttarget: right after a kill the last target is that corpse, so going back stuck
    -- the macro on dead mobs.
    if db.lastTarget then tinsert(lines, "/cleartarget [dead]") end
    return table.concat(lines, "\n")
end

-- One targeting line per name, then the tail. The last line that finds a mob wins, so later names
-- are the higher priority and are the ones kept when the 255-character macro runs out of room.
function ns.build(names)
    local action = tail()
    local room = 255 - #action - 1
    local lines = ""
    for i = #names, 1, -1 do
        local line = fmt("%s %s\n", db.targetCmd, names[i])
        if #lines + #line > room then break end
        lines = line .. lines
    end
    return lines .. action
end

local updateCustom, switched
local retrying
local function writeCustom(text)
    if not (db and pingOn() and SM.ready) then return end -- not ready: SM.onReady writes it
    if MacroFrame and MacroFrame:IsShown() then -- it would lose what's typed there: later
        if not retrying then
            retrying = true
            C_Timer.After(SM.retry, function() retrying = false; updateCustom() end)
        end
        return
    end
    rename()
    local name = macroName()
    local existed = GetMacroInfo(name)
    local status, why = SM.keep(db, "made", name, true, text, "Ability_Hunter_SniperShot")
    local problem
    if status == "ok" and not existed then
        say("macro %s created. Drag it from your general macros to a bar.", name)
    elseif status == "lost" then
        SM.db().on.ping = nil
        problem = SM.lostText(name)
        say(problem)
        switched(false)
    elseif status == "taken" then
        problem = ("You already have a macro called %s that Kureq Utils didn't make: rename it, and KU Ping makes its "
            .. "own."):format(name)
        SM.sayOnce("pingtaken", problem)
    elseif status == "twin" then
        problem = ("You have two macros called %s: delete one for KU Ping to keep it up to date."):format(name)
        SM.sayOnce("pingtwin", problem)
    elseif status == "full" then
        problem = ("%s can't be made: %s"):format(name, why)
        SM.sayOnce("pingfull", problem)
    end
    SM.problems.ping = problem
    if ns.macros.changed then ns.macros.changed() end -- the open tab, even when nothing changed
end

function ns.writeMacro(name, text)
    if not ns.IsOn("macros") then return end
    if name == CUSTOM or name == OLD then return writeCustom(text) end
    -- companion addons' macros have their own switches, and this one
    local s = SM.db()
    if not s or s.pingCompanionsOff then return end
    local exists = GetMacroInfo(name)
    if not exists and GetNumMacros() < 119 then
        CreateMacro(name, "Ability_Hunter_SniperShot", "")
        say("macro %s created. Drag it from your general macros to a bar.", name)
        exists = true
    end
    if exists and GetMacroBody(name) ~= text then EditMacro(name, name, nil, text) end
end

local function questLogIndex(questId)
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then return C_QuestLog.GetLogIndexForQuestID(questId) or 0 end
    return GetQuestLogIndexByID and GetQuestLogIndexByID(questId) or 0
end

-- Quest data getters (id, field): the QuestieDB addon, which works with or without Questie, or
-- Questie's own module on versions without it. nil when neither is loaded.
local function questData()
    local lib = _G.LibQuestieDB
    if lib and lib.Quest and lib.Npc and lib.Item then return lib.Quest.Get, lib.Npc.Get, lib.Item.Get end
    local loader = _G.QuestieLoader
    local qdb = loader and loader:ImportModule("QuestieDB")
    if qdb and qdb.QueryQuestSingle then return qdb.QueryQuestSingle, qdb.QueryNPCSingle, qdb.QueryItemSingle end
end

-- A match pattern for one of the client's own (localized) objective formats: "%s slain: %d/%d" matches
-- "Witherbark Harpy slain: 3/10" and captures "Witherbark Harpy". Placeholders, including positional %1$s,
-- are swapped for markers before the rest is escaped.
local function objectivePattern(format)
    return "^" .. format:gsub("%%%d*%$?s", "\1"):gsub("%%%d*%$?d", "\2")
        :gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0"):gsub("\1", "(.-)"):gsub("\2", "%%d+") .. "$"
end
local killedPattern = objectivePattern(QUEST_MONSTERS_KILLED or "%s slain: %d/%d")
local foundPattern = objectivePattern(QUEST_OBJECTS_FOUND or "%s: %d/%d")

-- The lowercased mob or item an objective text names ("Boar Tusk: 1/5" -> "boar tusk"), else the whole
-- text, so a finished objective matches only its own name (not "Night Web Spider" in "Young Night Web Spider").
function ns.objectiveName(text)
    return (text:match(killedPattern) or text:match(foundPattern) or text):lower()
end

-- Mob names for a quest's objectives: kill targets, kill credit, and the mobs that drop its items,
-- from QuestieDB. Without QuestieDB data, a quest in your log still gives its kill objectives
-- (fromLog is then true). Objectives the quest log shows as finished are skipped. nil: no data.
local function questMobs(questId)
    local finishedNames, logKills, index = {}, {}, questLogIndex(questId)
    for j = 1, index > 0 and GetNumQuestLeaderBoards(index) or 0 do
        local text, kind, finished = GetQuestLogLeaderBoard(j, index)
        if text and finished then
            finishedNames[ns.objectiveName(text)] = true
        elseif text and kind == "monster" then
            local name = text:match(killedPattern)
            if name then tinsert(logKills, name) end
        end
    end

    local getQuest, getNpc, getItem = questData()
    local objectives = getQuest and getQuest(questId, "objectives")
    if type(objectives) ~= "table" then
        if index > 0 then return logKills, true end
        return
    end

    local function finished(label) return type(label) == "string" and finishedNames[label:lower()] == true end

    local names, seen = {}, {}
    local function add(npcId)
        local name = getNpc(npcId, "name")
        if name and not seen[name] then seen[name] = true; tinsert(names, name) end
    end
    local function slot(i) return type(objectives[i]) == "table" and objectives[i] or {} end
    for _, o in ipairs(slot(1)) do -- creatures: {npcId, text, icon}
        if type(o) == "table" and o[1] and not finished(getNpc(o[1], "name")) then add(o[1]) end
    end
    for _, o in ipairs(slot(5)) do -- kill credit: {npcIds, baseId, baseText, icon}
        if type(o) == "table" and type(o[1]) == "table" and not finished(o[3] or getNpc(o[2], "name")) then
            for _, id in ipairs(o[1]) do add(id) end
        end
    end
    for _, o in ipairs(slot(3)) do -- items: {itemId, text, icon}
        if type(o) == "table" and o[1] and not finished(getItem(o[1], "name")) then
            for _, id in ipairs(getItem(o[1], "npcDrops") or {}) do add(id) end
        end
    end
    return names, false
end

-- QuestieDB is another addon; a failing lookup must not throw on every quest log update
local function safeQuestMobs(questId)
    local ok, names, fromLog = pcall(questMobs, questId)
    if ok then return names, fromLog end
end

local function customNames()
    if db.customQuest then return safeQuestMobs(db.customQuest) end
    if db.customNames then return db.customNames end -- a companion addon's list
    if db.custom then return {db.custom} end
end

-- Macros can't be edited in combat; the combat queue calls this again when it ends. A quest is looked up
-- again each time, so its finished objectives drop out. The nearby alert watches the same names.
function updateCustom()
    if not (db and pingOn()) then return end
    local names = customNames()
    if names and ns.setWatch then ns.setWatch("custom", names) end
    if not names then
        SM.problems.ping = "KU Ping has no target yet: type one in Custom target, use /ku ping <name>, or Alt-click a quest."
        return
    end
    if InCombatLockdown() then ns.CombatQueue.Defer("ping", updateCustom) else ns.writeMacro(CUSTOM, ns.build(names)) end
end

local scheduled
local function scheduleCustom()
    if scheduled then return end
    scheduled = true
    C_Timer.After(2, function() scheduled = false; updateCustom() end)
end

-- Its settings, for the Macros window's Smart macros tab (SmartMacrosWindow.lua) --------------------------------------

-- the window shows the macro's text and what it targets: redrawn after each change
local function refreshPreview() if ns.macros.changed then ns.macros.changed() end end

local function changed()
    updateCustom()
    for _, fn in ipairs(ns.listeners) do fn() end
    refreshPreview()
end
-- on again: rebuild every ping macro (each defers its own write while in combat)
function switched(on)
    if on then changed() end
    for _, fn in ipairs(ns.ping.switched) do fn(on) end
end
ns.OnModuleChange("macros", function(on) if SM.db() and SM.db().on.ping then switched(on) end end)

local P = ns.ping
P.NAME, P.MARKERS, P.update, P.macroName = CUSTOM, MARKERS, updateCustom, macroName
P.TARGET_COMMANDS = {{"/TargetExact", "/TargetExact (exact name)"}, {"/target", "/target (names that start with it)"}}
function P.db() return db end
-- The macro's text as it's built now (a placeholder for the target while there's none)
function P.preview() return db and ns.build(customNames() or {"<target>"}) or "" end
-- KU Ping ticked or unticked
function P.setOn(v)
    local s = SM.db()
    if not s then return end
    s.on.ping = v or nil
    if v and db then
        SM.adopt(db, "made", macroName(), true)
        if not db.made then SM.adopt(db, "made", OLD, true) end -- one from before the rename: renamed on the next write
    end
    switched(v)
end
-- One of targetCmd, marker, lastTarget, questClick
function P.set(key, v)
    if not db then return end
    db[key] = v
    if key ~= "questClick" then changed() else refreshPreview() end
end
-- The line after targeting: empty puts the default back. Returns nil and why when it can't be used.
function P.setAction(text)
    if not db then return end
    text = trim(text or "")
    if text == "" then text = ns.defaults.ping.action end
    if text:sub(1, 1) ~= "/" then return nil, "The action line must start with /." end
    db.action = text
    changed()
    return true
end
function P.companionsOn() local s = SM.db(); return s and not s.pingCompanionsOff or false end
function P.setCompanions(v)
    local s = SM.db()
    if s then s.pingCompanionsOff, s.pingCompanionsSet = not v or nil, true end
    if v then changed() else refreshPreview() end
end
local setCustom
-- What it targets: a mob's name, or a quest link
function P.setCustom(text)
    text = trim(text or "")
    if db and text ~= "" and text ~= db.custom then setCustom(text) end
end

-- Custom target ------------------------------------------------------------------------------

-- A quest's mobs become the target; label is how it's shown, e.g. "[Harpies Threaten]".
local function setQuest(id, label)
    local names, fromLog = safeQuestMobs(id)
    if not names then
        return say("no data for %s: it isn't in your quest log and QuestieDB isn't loaded", label)
    end
    db.custom, db.customQuest, db.customNames = label, id, nil
    updateCustom()
    say("%s pings the mobs of %s%s: %s%s", macroName(), label, InCombatLockdown() and " (after combat)" or "",
        #names > 0 and table.concat(names, ", ") or "none left",
        fromLog and " (from your quest log: kill objectives only; QuestieDB adds item drops)" or "")
    refreshPreview()
end

function setCustom(text)
    local id = tonumber(text:match("|Hquest:(%d+)"))
    if id then return setQuest(id, text:match("|h(%[.-%])|h") or ("quest " .. id)) end
    db.custom, db.customQuest, db.customNames = text, nil, nil
    updateCustom()
    say("%s pings %s%s", macroName(), text, InCombatLockdown() and " (after combat)" or "")
    refreshPreview()
end

-- A companion addon's names become the target, shown as label (e.g. "vendors of Woolen Cape").
function ns.setCustomNames(label, names)
    if not pingOn() then return end
    db.custom, db.customQuest, db.customNames = label, nil, names
    updateCustom()
    say("%s pings %s%s: %s", macroName(), label, InCombatLockdown() and " (after combat)" or "", table.concat(names, ", "))
    refreshPreview()
end

-- Alt-click a quest: Blizzard's quest log and Questie's tracker both select the quest, through
-- C_QuestLog.SetSelectedQuest (modern) or SelectQuestLogEntry (classic); with Alt held, that sets the target.
local lastPick, lastPickTime
local function onQuestSelected(id, title)
    if not (db and db.questClick and pingOn() and id and id > 0 and IsAltKeyDown()) then return end
    if id == lastPick and GetTime() - lastPickTime < 1 then return end -- one click can select twice
    lastPick, lastPickTime = id, GetTime()
    title = title or (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id))
    setQuest(id, title and ("[" .. title .. "]") or ("quest " .. id))
end
if C_QuestLog and C_QuestLog.SetSelectedQuest then
    hooksecurefunc(C_QuestLog, "SetSelectedQuest", function(id) onQuestSelected(id) end)
end
if SelectQuestLogEntry then
    hooksecurefunc("SelectQuestLogEntry", function(index)
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(index)
            if info and not info.isHeader then onQuestSelected(info.questID, info.title) end
        elseif GetQuestLogTitle then
            local title, _, _, isHeader, _, _, _, id = GetQuestLogTitle(index)
            if not isHeader then onQuestSelected(id, title) end
        end
    end)
end

-- While KU Ping is unticked its commands only say so
local function whenTicked(fn)
    return function(...)
        if pingOn() then return fn(...) end
        say("KU Ping is off; tick it in the Smart macros tab of /ku macro.")
    end
end
-- /ku <quest link> works without "ping"; other links (items, spells) aren't targets
ns.linkHandler = ns.whenOn("macros", whenTicked(function(text)
    if not text:find("|Hquest:%d+") then return say("only quest links can be targets; try /ku ping <mob name>") end
    setCustom(text)
end))
ns.AddCommand("ping", "/ku ping <name or quest link> (or just /ku <quest link>) - what " .. CUSTOM .. " targets", whenTicked(function(rest)
    rest = trim(rest)
    if rest == "" then
        say("/ku ping <name or quest link>; %s targets %s.", macroName(), db.custom or "nothing yet")
    else
        setCustom(rest)
    end
end), "macros")

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("QUEST_LOG_UPDATE")
tinsert(SM.onReady, function()
    if db then migrate() end
    scheduleCustom()
end)
f:SetScript("OnEvent", function()
    -- combat may end before the timer: the macro then catches up as it ends
    if InCombatLockdown() and db and pingOn() then ns.CombatQueue.Defer("ping", updateCustom) end
    scheduleCustom()
end)
ns.watch("KU Ping", f)
