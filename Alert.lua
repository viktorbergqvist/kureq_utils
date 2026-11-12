-- Nearby target alert: a sound and an on-screen message when a mob you're after shows up nearby.
-- It watches enemy nameplates, so it sees what your nameplates show (enemy nameplates on, the V key).
-- What to watch comes from named lists: the ping macro's custom target, and companion addons
-- through KureqUtils.SetWatchList.
local _, ns = ...
ns.AddModule("alert", "Nearby alert", "A sound and a message when a mob you're after shows up nearby.")
local tinsert = table.insert

ns.defaults.alert = {enabled = true, sound = true}
local MIN_GAP = 5 -- seconds; a pack showing up together alerts once

local db
tinsert(ns.onLoad, function(root) db = root.alert end)

local lists, watched, alerted = {}, {}, {}
local lastAlert = 0

local function show(text)
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or {r = 1, g = 0.8, b = 0})
    else
        UIErrorsFrame:AddMessage(text, 1, 0.8, 0)
    end
    if db.sound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
end

-- Each mob (by GUID) alerts once a session. Lists are resent on every quest log update, so a
-- changed list must not reset this, or every watched mob in view would alert again.
local function check(unit)
    if not (db and db.enabled and ns.IsOn("alert")) then return end
    local name = UnitName(unit)
    if not (name and watched[name:lower()]) or UnitIsDead(unit) or not UnitCanAttack("player", unit) then return end
    if UnitIsTapDenied and UnitIsTapDenied(unit) then return end -- tagged by someone else: no credit for you
    local guid = UnitGUID(unit)
    if guid then
        if alerted[guid] then return end
        alerted[guid] = true
    end
    if GetTime() - lastAlert < MIN_GAP then return end
    lastAlert = GetTime()
    show(name .. " nearby")
end

local function checkAll()
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then check(unit) end
    end
end

ns.OnModuleChange("alert", function(on) if on then checkAll() end end) -- mobs already in view when turned on

local watchLine
function ns.setWatch(source, names)
    lists[source] = names
    wipe(watched)
    local all = {}
    for _, list in pairs(lists) do
        for _, n in ipairs(list) do
            if not watched[n:lower()] then tinsert(all, n) end
            watched[n:lower()] = true
        end
    end
    if watchLine then watchLine:SetText(#all > 0 and table.concat(all, ", ") or "nothing yet") end
    checkAll()
end

-- Settings page ------------------------------------------------------------------------------

local panel = ns.AddSettingsPage("Nearby alert",
    "A sound and an on-screen message when a mob you're after shows up nearby: the ping macro's custom target, "
        .. "and the mobs companion addons add. It uses enemy nameplates, so turn those on (V).", "alert")

ns.Checkbox(panel, "Alert when nearby", "Show a message when one of the watched mobs appears.",
    function() return db and db.enabled end, function(v) db.enabled = v; if v then checkAll() end end)

ns.Checkbox(panel, "Play a sound", "Play the raid warning sound with the message.",
    function() return db and db.sound end, function(v) db.sound = v end)

ns.Button(panel, "Test", 100, function() show("Test mob nearby") end, "Try the alert")

ns.Header(panel, "Watching")
watchLine = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
watchLine:SetJustifyH("LEFT")
ns.place(panel, watchLine, 0, nil, true)
watchLine:SetText("nothing yet")

local f = CreateFrame("Frame")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:SetScript("OnEvent", function(_, _, unit) check(unit) end)
