-- Nearby target alert: a sound and an on-screen message when a mob you're after shows up nearby.
-- It watches enemy nameplates, so it sees what your nameplates show (enemy nameplates on, the V key).
-- What to watch comes from named lists: the ping macro's custom target, and companion addons
-- through KureqUtils.SetWatchList. It's part of the Ping macro module (its settings are on that page) and is off until
-- the player turns it on.
local _, ns = ...
local tinsert = table.insert

ns.defaults.alert = {on = false, sound = true}
local MIN_GAP = 5 -- seconds; a pack showing up together alerts once

local db
tinsert(ns.onLoad, function(root)
    db = root.alert
    -- once: Nearby alert was its own module with "enabled" on by default; now it's off unless this character had
    -- turned that module on
    if db.enabled ~= nil then
        db.on, db.enabled = db.enabled and ns.charDB.modules.alert == true, nil
    end
    ns.charDB.modules.alert = nil
end)

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
    if not (db and db.on and ns.IsOn("ping")) then return end
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

ns.OnModuleChange("ping", function(on) if on then checkAll() end end) -- mobs already in view when turned on

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

local panel = ns.ping.panel
ns.Header(panel, "Nearby alert")
ns.GrowingText(panel, "GameFontDisable"):SetText("A sound and an on-screen message when the ping macro's mobs (or "
    .. "a companion addon's) show up nearby. It uses enemy nameplates, so turn those on (V).")

ns.Checkbox(panel, "Alert when nearby", "Show a message when one of the watched mobs appears. Off by default.",
    function() return db and db.on end, function(v) db.on = v; if v then checkAll() end end)

ns.Checkbox(panel, "Play a sound", "Play the raid warning sound with the message.",
    function() return db and db.sound end, function(v) db.sound = v end)

ns.Button(panel, "Test", 100, function() show("Test mob nearby") end, "Try the alert")

ns.Header(panel, "Watching")
watchLine = ns.GrowingText(panel)
watchLine:SetText("nothing yet")

local f = CreateFrame("Frame")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:SetScript("OnEvent", function(_, _, unit) check(unit) end)
