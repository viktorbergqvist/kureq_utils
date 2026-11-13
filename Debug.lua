-- Debug checks: while on, finds out which values WoW Forever hides from addons (secret values), per place. Each
-- check prints one chat line the first time its result is seen in a place, or when it changes there; every result
-- is saved (KureqUtilsDB.debug.results[place][check]) and listed on the Debug settings page. Not a module.
local ADDON, ns = ...
local fmt, tinsert, sort, concat = string.format, table.insert, table.sort, table.concat

ns.defaults.debug = {on = false, results = {}}

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function shown(v) return secret(v) and "secret" or v == nil and "nil" or tostring(v) end

-- {name, fn}: fn returns a short result string
local targetChecks = {
    {"target level", function() return shown(UnitLevel("target")) end},
    {"target name", function() return secret(UnitName("target")) and "secret" or "readable" end},
    {"target GUID", function()
        local guid = UnitGUID("target")
        return secret(guid) and "secret" or guid == nil and "nil" or "readable"
    end},
    {"target classification", function() return shown(UnitClassification("target")) end},
    {"player level", function() return shown(UnitLevel("player")) end},
}
local mapChecks = {
    {"player map", function() return shown(C_Map.GetBestMapForUnit("player")) end},
    {"instance info", function()
        local name, kind, _, _, _, _, _, id = GetInstanceInfo()
        return fmt("%s, %s, %s", shown(name), shown(kind), shown(id))
    end},
}

-- on death, 2 seconds later (the recap fills a moment after): did Kill stats see it, and what the recap hides
local deathChecks = {
    {"death: kill stats on", function() return tostring(ns.IsOn("stats")) end},
    {"death: recap", function()
        if type(C_DeathRecap) ~= "table" or not C_DeathRecap.GetRecapEvents then return "no API" end
        local events = C_DeathRecap.GetRecapEvents()
        if secret(events) then return "secret" end
        if canaccesstable and not canaccesstable(events) then return "not accessible" end
        return type(events) == "table" and (#events .. " hits") or shown(events)
    end},
    {"death: killing blow source", function()
        local blow = C_DeathRecap.GetRecapEvents()[1]
        if type(blow) ~= "table" then return "none" end
        local guid = blow.sourceGUID
        local kind = secret(guid) and "secret GUID" or type(guid) == "string" and guid:match("^(%a+)%-") or shown(guid)
        return fmt("name %s, %s, hidden %s", secret(blow.sourceName) and "secret" or blow.sourceName and "readable" or "nil",
            kind, shown(blow.hideCaster))
    end},
    {"death: saved", function()
        local deaths = ns.stats and ns.stats.mine and ns.stats.mine.deaths
        local d = deaths and deaths[#deaths]
        return d and math.abs(d.t - time()) <= 10 and fmt("yes, killer %s (%s)", tostring(d.killer), tostring(d.kind)) or "no"
    end},
}

local panel, resultsLine, resultsTop

local function place()
    local name, kind = GetInstanceInfo()
    if kind and not secret(kind) and not secret(name) and kind ~= "none" then return name end -- secret first: comparing one errors
    return "Open world"
end

local function run(checks)
    local db = ns.db and ns.db.debug
    if not (db and db.on) then return end
    local where = place()
    db.results[where] = db.results[where] or {}
    local saved = db.results[where]
    for _, check in ipairs(checks) do
        local ok, value = pcall(check[2])
        value = ok and tostring(value) or "error: " .. tostring(value)
        if not saved[check[1]] or saved[check[1]].value ~= value then
            ns.say("debug: %s · %s: %s", where, check[1], value)
        end
        saved[check[1]] = {value = value, t = time()}
    end
    if panel:IsVisible() then ns.refresh(panel) end
end

-- other files' checks: ns.debug.run({{name, fn}, ...}) when they find something out (Mail rules' chained send)
ns.debug = {run = run}

-- the page's results, one line per check: "Zul'Farrak · target level: secret"
local function resultsText()
    local results = ns.db and ns.db.debug.results or {}
    local places, lines = {}, {}
    for where in pairs(results) do places[#places + 1] = where end
    sort(places)
    for _, where in ipairs(places) do
        local names = {}
        for name in pairs(results[where]) do names[#names + 1] = name end
        sort(names)
        for _, name in ipairs(names) do
            lines[#lines + 1] = fmt("%s · %s: %s", where, name, results[where][name].value)
        end
    end
    return #lines > 0 and concat(lines, "\n") or "No results yet. Turn the checks on and target a mob.", #lines
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("PLAYER_DEAD")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_DEAD" then
        if C_Timer then C_Timer.After(2, function() run(deathChecks) end) else run(deathChecks) end
        return
    end
    if event ~= "PLAYER_TARGET_CHANGED" then return run(mapChecks) end
    local ok, mob = pcall(function() return UnitExists("target") and not UnitIsPlayer("target") end)
    if ok and mob then run(targetChecks) end
end)

-- Settings page ------------------------------------------------------------------------------

panel = ns.AddSettingsPage("Debug", "Checks for testing in game, such as which values the game hides from addons "
    .. "inside dungeons.")
ns.Checkbox(panel, "Debug checks", "Runs the checks by themselves when you target a mob or change zone.",
    function() return ns.db and ns.db.debug.on end,
    function(on)
        ns.db.debug.on = on
        if on then run(mapChecks) end
    end)
ns.Label(panel, "Prints a line the first time a result is seen in a place, or when it changes there.",
    "GameFontDisable")
ns.Button(panel, "Clear results", 120, function()
    ns.db.debug.results = {}
    ns.refresh(panel)
end)
resultsTop = panel.y
resultsLine = ns.Label(panel, "", "GameFontHighlightSmall")
tinsert(panel.refreshers, function()
    local text, count = resultsText()
    resultsLine:SetText(text)
    panel.y = resultsTop - math.max(count, 1) * 14 - 8 -- the label grows down; the page's scroll height follows
end)
