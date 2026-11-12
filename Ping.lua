-- Ping macro: keeps KureqPingCustom, a macro that targets a mob (or a quest's mobs, from Questie)
-- and pings it. Nothing acts on its own: it rewrites the macro out of combat and you press it.
-- ns.build and ns.writeMacro also serve companion addons through the KureqUtils API.
local _, ns = ...
ns.AddModule("ping", "Ping macro", "A macro that targets and pings a mob or a quest's mobs.")
local CUSTOM = "KureqPingCustom"
local fmt, tinsert = string.format, table.insert
local say, trim = ns.say, ns.trim

ns.defaults.ping = {action = "/ping [@target,nodead]", targetCmd = "/TargetExact", marker = 0, lastTarget = true,
    questClick = true}
local MARKERS = {"Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull"}

local db
ns.listeners = {}
tinsert(ns.onLoad, function(root) db = root.ping end)

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

function ns.writeMacro(name, text)
    if not ns.IsOn("ping") then return end
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
local function updateCustom()
    if not (db and ns.IsOn("ping")) then return end
    local names = customNames()
    if names and ns.setWatch then ns.setWatch("custom", names) end
    if not names then return end
    if InCombatLockdown() then ns.CombatQueue.Defer("ping", updateCustom) else ns.writeMacro(CUSTOM, ns.build(names)) end
end

local scheduled
local function scheduleCustom()
    if scheduled then return end
    scheduled = true
    C_Timer.After(2, function() scheduled = false; updateCustom() end)
end

-- Settings page ------------------------------------------------------------------------------

local panel = ns.AddSettingsPage("Ping macro",
    "These settings shape every ping macro: " .. CUSTOM .. " (/ku ping <name or quest link>) and the macros "
        .. "of companion addons.", "ping")
ns.ping = {panel = panel} -- Alert.lua adds its settings under the ping macro's

local preview
local function refreshPreview()
    if preview and db then preview:SetText(ns.build(customNames() or {"<target>"})) end
end

local function changed()
    updateCustom()
    for _, fn in ipairs(ns.listeners) do fn() end
    refreshPreview()
end
-- on again: rebuild every ping macro (each defers its own write while in combat)
ns.OnModuleChange("ping", function(on) if on then changed() end end)

ns.EditBox(panel, "Action line",
    "What the macro does after targeting. Default: " .. ns.defaults.ping.action .. ". Must start with /. "
        .. "Empty puts the default back.",
    function() return db and db.action end,
    function(text)
        text = trim(text)
        if text == "" then text = ns.defaults.ping.action end
        if text:sub(1, 1) ~= "/" then return say("the action line must start with /") end
        db.action = text
        changed()
    end)

ns.Dropdown(panel, "Targeting command", "How each mob line targets.", {
    {value = "/TargetExact", text = "/TargetExact (exact name)"},
    {value = "/target", text = "/target (names that start with it)"},
}, function() return db and db.targetCmd end, function(v) db.targetCmd = v; changed() end)

local markerOptions = {{value = 0, text = "None"}}
for i = #MARKERS, 1, -1 do
    tinsert(markerOptions, {value = i, text = MARKERS[i], icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i})
end
ns.Dropdown(panel, "Raid marker", "Also put this marker on the target (not on corpses). A marker that's already on stays on.",
    markerOptions, function() return db and db.marker end, function(v) db.marker = v; changed() end)

ns.Checkbox(panel, "Clear dead targets",
    "Clear the target when the targeting lines pick a corpse (adds /cleartarget [dead]).",
    function() return db and db.lastTarget end, function(v) db.lastTarget = v; changed() end)

local setCustom
ns.EditBox(panel, "Custom target",
    "The mob " .. CUSTOM .. " targets. For a quest's mobs, type /ku in chat and shift-click the quest.",
    function() return db and db.custom end,
    function(text)
        text = trim(text)
        if text ~= "" and text ~= db.custom then setCustom(text) end
    end)

ns.Checkbox(panel, "Alt-click quests",
    "Alt-click a quest in the quest log, or in Questie's tracker, to make " .. CUSTOM .. " target its mobs.",
    function() return db and db.questClick end, function(v) db.questClick = v end)

ns.Header(panel, "Preview of " .. CUSTOM)
preview = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
preview:SetJustifyH("LEFT")
ns.place(panel, preview, 0)
tinsert(panel.refreshers, refreshPreview)

-- Custom target ------------------------------------------------------------------------------

-- A quest's mobs become the target; label is how it's shown, e.g. "[Harpies Threaten]".
local function setQuest(id, label)
    local names, fromLog = safeQuestMobs(id)
    if not names then
        return say("no data for %s: it isn't in your quest log and QuestieDB isn't loaded", label)
    end
    db.custom, db.customQuest, db.customNames = label, id, nil
    updateCustom()
    say("%s pings the mobs of %s%s: %s%s", CUSTOM, label, InCombatLockdown() and " (after combat)" or "",
        #names > 0 and table.concat(names, ", ") or "none left",
        fromLog and " (from your quest log: kill objectives only; QuestieDB adds item drops)" or "")
    refreshPreview()
end

function setCustom(text)
    local id = tonumber(text:match("|Hquest:(%d+)"))
    if id then return setQuest(id, text:match("|h(%[.-%])|h") or ("quest " .. id)) end
    db.custom, db.customQuest, db.customNames = text, nil, nil
    updateCustom()
    say("%s pings %s%s", CUSTOM, text, InCombatLockdown() and " (after combat)" or "")
    refreshPreview()
end

-- A companion addon's names become the target, shown as label (e.g. "vendors of Woolen Cape").
function ns.setCustomNames(label, names)
    if not ns.IsOn("ping") then return end
    db.custom, db.customQuest, db.customNames = label, nil, names
    updateCustom()
    say("%s pings %s%s: %s", CUSTOM, label, InCombatLockdown() and " (after combat)" or "", table.concat(names, ", "))
    refreshPreview()
end

-- Alt-click a quest: Blizzard's quest log and Questie's tracker both select the quest, through
-- C_QuestLog.SetSelectedQuest (modern) or SelectQuestLogEntry (classic); with Alt held, that sets the target.
local lastPick, lastPickTime
local function onQuestSelected(id, title)
    if not (db and db.questClick and ns.IsOn("ping") and id and id > 0 and IsAltKeyDown()) then return end
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

-- /ku <quest link> works without "ping"; other links (items, spells) aren't targets
ns.linkHandler = ns.whenOn("ping", function(text)
    if not text:find("|Hquest:%d+") then return say("only quest links can be targets; try /ku ping <mob name>") end
    setCustom(text)
end)
ns.AddCommand("ping", "/ku ping <name or quest link> (or just /ku <quest link>) - what " .. CUSTOM .. " targets", function(rest)
    rest = trim(rest)
    if rest == "" then
        say("/ku ping <name or quest link>; %s targets %s.", CUSTOM, db.custom or "nothing yet")
    else
        setCustom(rest)
    end
end, "ping")

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("QUEST_LOG_UPDATE")
f:SetScript("OnEvent", function()
    -- combat may end before the timer: the macro then catches up as it ends
    if InCombatLockdown() and db and ns.IsOn("ping") then ns.CombatQueue.Defer("ping", updateCustom) end
    scheduleCustom()
end)
