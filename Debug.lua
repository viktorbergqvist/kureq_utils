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

-- Timing: while Debug checks are on, each watched handler (ns.watch) is wrapped to count its calls and time them with
-- debugprofilestop, per event for an event frame; off, the handlers are put back as they were. "Show performance"
-- prints each addon's memory and the handlers that took longest since timing started.
local timings, since = {}, nil -- label -> {calls, ms, max}; GetTime() when timing started
local function add(label, start, ...)
    local ms = debugprofilestop() - start
    local t = timings[label]
    if not t then
        t = {calls = 0, ms = 0, max = 0}
        timings[label] = t
    end
    t.calls, t.ms, t.max = t.calls + 1, t.ms + ms, math.max(t.max, ms)
    return ...
end
function ns.debug.wrap(w)
    if w.wrapper then return end
    if w.key then
        local fn = w.target[w.key]
        if type(fn) ~= "function" then return end
        w.original = fn
        w.wrapper = function(...) return add(w.name, debugprofilestop(), fn(...)) end
        w.target[w.key] = w.wrapper
    else
        local fn = w.target:GetScript("OnEvent")
        if not fn then return end
        local labels = {}
        w.original = fn
        w.wrapper = function(frame, event, ...)
            local label = labels[event]
            if not label then
                label = w.name .. ": " .. tostring(event)
                labels[event] = label
            end
            return add(label, debugprofilestop(), fn(frame, event, ...))
        end
        w.target:SetScript("OnEvent", w.wrapper)
    end
end
local function unwrap(w)
    if not w.wrapper then return end
    if w.key then
        if w.target[w.key] == w.wrapper then w.target[w.key] = w.original end
    elseif w.target:GetScript("OnEvent") == w.wrapper then
        w.target:SetScript("OnEvent", w.original)
    end
    w.wrapper, w.original = nil, nil
end
local function setTiming(on)
    ns.debug.timing = on
    if on and not since then since = GetTime() end
    for _, w in ipairs(ns.watched) do
        if on then ns.debug.wrap(w) else unwrap(w) end
    end
end
tinsert(ns.onLoad, function(root) if root.debug.on then setTiming(true) end end)

local ADDONS = {"KureqUtils", "KureqProfessionsGuide", "KureqRestedXp"}
function ns.debug.report()
    if UpdateAddOnMemoryUsage then UpdateAddOnMemoryUsage() end
    local mem = {}
    for _, name in ipairs(ADDONS) do
        local ok, kb = pcall(GetAddOnMemoryUsage, name)
        if ok and type(kb) == "number" and kb > 0 then mem[#mem + 1] = fmt("%s %.0f KB", name, kb) end
    end
    ns.say("memory: %s", #mem > 0 and concat(mem, ", ") or "unknown")
    if not since then return ns.say("timing: turn Debug checks on, play a while, then show it again.") end
    local labels = {}
    for label in pairs(timings) do labels[#labels + 1] = label end
    sort(labels, function(a, b) return timings[a].ms > timings[b].ms end)
    ns.say("timing over %.0f min%s:", (GetTime() - since) / 60, #labels > 15 and ", the 15 slowest" or "")
    for i = 1, math.min(#labels, 15) do
        local t = timings[labels[i]]
        ns.say("%s: %d calls, %.1f ms in all, %.3f ms each, %.2f ms at most", labels[i], t.calls, t.ms, t.ms / t.calls,
            t.max)
    end
    if #labels == 0 then ns.say("nothing timed yet.") end
    -- kept after turning the checks off (decision 2026-11-13): Reset timing clears them
    if not ns.debug.timing then ns.say("Debug checks are off: these are from while they were on.") end
end

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
        setTiming(on)
        if on then run(mapChecks) end
    end)
ns.Label(panel, "Prints a line the first time a result is seen in a place, or when it changes there.",
    "GameFontDisable")
ns.Button(panel, "Clear results", 120, function()
    ns.db.debug.results = {}
    ns.refresh(panel)
end)
ns.Button(panel, "Show performance", 160, function() ns.debug.report() end, "Memory and timing")
ns.Button(panel, "Reset timing", 120, function()
    wipe(timings)
    since = ns.debug.timing and GetTime() or nil
end)
resultsTop = panel.y
resultsLine = ns.Label(panel, "", "GameFontHighlightSmall")
tinsert(panel.refreshers, function()
    local text, count = resultsText()
    resultsLine:SetText(text)
    panel.y = resultsTop - math.max(count, 1) * 14 - 8 -- the label grows down; the page's scroll height follows
end)
