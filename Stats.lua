-- Kill stats: counts every mob you kill for experience, per mob name, mob level and how far above (+) or below (-)
-- your level it was, with the experience it gave. Kills come from the "X dies, you gain N experience." chat message,
-- because WoW Forever keeps the combat log from addons; kills that give no experience (grey mobs) send none.
local _, ns = ...
ns.AddModule("stats", "Kill stats", "Every mob you kill for experience, with graphs, maps and kill XP on tooltips.")
local tinsert = table.insert
local S = {} -- shared with the window (StatsWindow.lua)
ns.stats = S
-- Settings are account-wide in KureqUtilsDB.stats, and so are the kills: KureqUtilsDB.killStats["Name - Realm"] =
-- {name, realm, class, kills, byLevel, byHour, mobs}, one per character, so the window shows any character or all
-- of them. S.mine is the character you're on. KureqStatsDB (per character, from when Kureq Stats was its own addon)
-- is only read once, to move its kills here.
ns.defaults.stats = {tooltip = true, chat = true, loot = true, toLevel = true, filter = "all", zone = 0, char = "all",
    recap = true}
local seen = {} -- mob name -> level, from the last time the target, mouseover or a nameplate showed it

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

local guidName, npcName = {}, {} -- creature GUID and NPC ID -> name, for loot (this session)
local function npcID(guid) return guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)") end
local function look(unit)
    if not UnitExists(unit) or UnitIsPlayer(unit) then return end
    local name, level = UnitName(unit), UnitLevel(unit)
    if name and level and not secret(name) and not secret(level) then seen[name] = level end
    local guid = UnitGUID(unit)
    if name and guid and not secret(name) and not secret(guid) then
        guidName[guid] = name
        local id = npcID(guid)
        if id then npcName[id] = name end
    end
end

-- COMBATLOG_XPGAIN_FIRSTPERSON ("%s dies, you gain %d experience.") as a pattern; the rested and group bonus
-- messages start the same way, so it matches them too.
-- shortcut: assumes the name comes before the number, as in enUS; use positional captures if a locale swaps them.
local function xpPattern(fmt)
    local p = fmt:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    return "^" .. p
end
local KILL = xpPattern(COMBATLOG_XPGAIN_FIRSTPERSON or "%s dies, you gain %d experience.")


-- Group kills split the XP (with a bonus for 3+ members), so every kill keeps the group size it was made in
-- (1: solo) and the window shows solo kills, group kills or both (KureqUtilsDB.stats.filter: "solo", "group", "all").
-- shortcut: counts everyone in the group, also members too far away to share the XP; fine for normal play.
local function groupSize() return math.max(1, GetNumGroupMembers and GetNumGroupMembers() or 0) end
-- The zone filter (KureqUtilsDB.stats.zone): 0 all zones, -1 kills with no zone (made before zones were kept), else a
-- map ID, or a dungeon's name (see instanceName).
local function wanted(r)
    local f, zone = ns.db.stats.filter, ns.db.stats.zone
    if zone ~= 0 and (r.map or -1) ~= zone then return false end
    return f == "all" or (f == "solo") == ((r.group or 1) == 1)
end
-- a bucket's kills and XP under the filters; gcount/gxp are its group kills (absent before group sizes were kept),
-- zones[map] the same counts per zone (absent before zones were kept)
local function filtered(v)
    if ns.db.stats.zone ~= 0 then
        v = v.zones and v.zones[ns.db.stats.zone]
        if not v then return 0, 0 end
    end
    local f, gc, gx = ns.db.stats.filter, v.gcount or 0, v.gxp or 0
    if f == "all" then return v.count, v.xp elseif f == "group" then return gc, gx end
    return v.count - gc, v.xp - gx
end

-- text in the mob's difficulty color, as Blizzard colors levels: grey, green, yellow, orange, red (?? mobs red)
local difficultyColor = GetCreatureDifficultyColor or GetQuestDifficultyColor
function S.levelColored(text, level)
    local c = difficultyColor and difficultyColor((level and level > 0) and level or UnitLevel("player") + 10)
    if not c then return tostring(text) end
    return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, tostring(text))
end

-- Inside dungeons the client hides mob levels and gives no map (user decision 2026-11-12): those kills take the
-- dungeon's name as their zone (a string where zones are otherwise map IDs) and, with no level, hidden = true.
local function instanceName()
    if not GetInstanceInfo then return nil end
    local name, kind = GetInstanceInfo()
    if name and kind and not secret(name) and not secret(kind) and kind ~= "none" then return name end
end

local function record(name, xp)
    look("target") -- the mob you just killed is often still targeted
    local level, player = seen[name], UnitLevel("player")
    -- -1 is a ?? (skull) mob, whose level the client never tells
    local diff = (level and level > 0) and level - player or nil
    local group = groupSize()
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if secret(map) then map = nil end
    map = map or instanceName()
    local hidden = type(map) == "string" and level == nil or nil
    local key = name .. "|" .. tostring(level) .. "|" .. tostring(diff) .. "|" .. group .. "|" .. tostring(map)
    local row = S.mine.kills[key]
    if not row then
        row = {name = name, level = level, diff = diff, group = group, map = map, hidden = hidden, count = 0, xp = 0}
        S.mine.kills[key] = row
    end
    row.count, row.xp = row.count + 1, row.xp + xp
    -- totals per your level and per hour (time() / 3600) for the graphs; they start with this version
    for t, k in pairs({byLevel = player, byHour = math.floor(time() / 3600)}) do
        local bucket = S.mine[t][k] or {count = 0, xp = 0, zones = {}}
        S.mine[t][k] = bucket
        bucket.zones = bucket.zones or {}
        bucket.zones[map or -1] = bucket.zones[map or -1] or {count = 0, xp = 0}
        for _, b in ipairs({bucket, bucket.zones[map or -1]}) do
            b.count, b.xp = b.count + 1, b.xp + xp
            if group > 1 then b.gcount, b.gxp = (b.gcount or 0) + 1, (b.gxp or 0) + xp end
        end
    end
    -- per mob: when, how much per kill, and where (your position as the XP arrives, next to the kill)
    local mob = S.mine.mobs[name] or {first = time(), spots = {}, zones = {}}
    S.mine.mobs[name] = mob
    mob.last = time()
    local lo, hi = group > 1 and "gmin" or "min", group > 1 and "gmax" or "max" -- smallest and largest XP, solo and grouped
    mob[lo], mob[hi] = math.min(mob[lo] or xp, xp), math.max(mob[hi] or xp, xp)
    if map then
        mob.zones[map] = (mob.zones[map] or 0) + 1
        local pos = type(map) == "number" and C_Map.GetPlayerMapPosition(map, "player") -- nil inside instances
        local x, y
        if pos then x, y = pos:GetXY() end
        if x and not secret(x) and not secret(y) then
            table.insert(mob.spots, {map, math.floor(x * 1000 + 0.5) / 1000, math.floor(y * 1000 + 0.5) / 1000})
            -- shortcut: keeps the latest 300 spots per mob to bound SavedVariables; raise it if maps look thin
            if #mob.spots > 300 then table.remove(mob.spots, 1) end
        end
    end
    if ns.db.stats.chat then
        print(("|cffffd100Kureq Stats:|r %s (%s, %s): %s xp%s. %d killed, %d xp in all"):format(name,
            (level and level > 0) and level or "??", diff and (diff > 0 and "+" .. diff or diff) or "?",
            S.levelColored(xp, level), group > 1 and " in a group of " .. group or "", row.count, row.xp))
    end
    if S.refresh then S.refresh() end -- the window's
end

-- Classic's kill XP for a normal mob: 45 + 5 x your level, 5% more per level the mob is above you (counted up to +4),
-- less per level below until it turns grey. shortcut: Classic Era's formula, approximate on Forever; recorded
-- kills replace it once you have one for the mob at that level difference.
local function zeroDiff(pl)
    for _, z in ipairs({{7, 5}, {9, 6}, {11, 7}, {15, 8}, {19, 9}, {29, 11}, {39, 12}, {44, 13}, {49, 14}, {54, 15}, {59, 16}}) do
        if pl <= z[1] then return z[2] end
    end
    return 17
end
local function grayLevel(pl)
    if pl <= 5 then return 0 elseif pl <= 49 then return pl - math.floor(pl / 10) - 5
    elseif pl <= 59 then return pl - math.floor(pl / 5) - 1 end
    return pl - 9
end
local function formulaXp(pl, ml)
    local base = pl * 5 + 45
    if ml >= pl then return math.floor(base * (1 + 0.05 * math.min(ml - pl, 4)) + 0.5) end
    if ml <= grayLevel(pl) then return 0 end
    return math.floor(base * (1 - (pl - ml) / zeroDiff(pl)) + 0.5)
end
-- Classic splits a party kill's XP between the members, times 1.166 / 1.3 / 1.4 for a party of 3 / 4 / 5.
-- shortcut: a raid's share is taken as an even split; raids rarely kill for XP.
local PARTY_BONUS = {1, 1, 1.166, 1.3, 1.4}
local function groupShare(xp, size) return math.floor(xp * (PARTY_BONUS[size] or 1) / size + 0.5) end

-- XP a kill of the unit would give, and where the number comes from
local function expectedXp(name, level, elite)
    local diff, size = level > 0 and level - UnitLevel("player") or nil, groupSize()
    -- your kills of it at this level difference and the group size you're in now; else of any mob of that level
    -- (same level and difference: killed at your level), which learns the server's real XP; else the formula
    local count, xp, sameCount, sameXp = 0, 0, 0, 0
    for _, r in pairs(S.mine.kills) do
        if r.diff == diff and not r.hidden and (r.group or 1) == size then
            if r.name == name then count, xp = count + r.count, xp + r.xp
            elseif diff and r.level == level then sameCount, sameXp = sameCount + r.count, sameXp + r.xp end
        end
    end
    if count > 0 then return math.floor(xp / count + 0.5), count .. (count == 1 and " kill" or " kills") end
    if not diff then return nil end
    if sameCount > 0 then
        return math.floor(sameXp / sameCount * (elite and 2 or 1) + 0.5), "level " .. level .. " mobs", true
    end
    return groupShare(formulaXp(UnitLevel("player"), level) * (elite and 2 or 1), size), "estimate"
end

S.expectedXp = expectedXp

-- How many kills giving xp each take you to your next level; nil at the level cap, for no XP, or with it turned off.
-- shortcut: rested XP isn't counted, so while rested it's fewer kills than this says.
function S.killsToLevel(xp)
    if not (ns.db.stats.toLevel and xp and xp > 0) then return nil end
    local cap = GetMaxPlayerLevel and GetMaxPlayerLevel() or MAX_PLAYER_LEVEL or 60
    local left = UnitXPMax("player") - UnitXP("player")
    if UnitLevel("player") >= cap or left <= 0 then return nil end
    return math.ceil(left / xp)
end

local function onTooltipUnit(tip)
    if not (ns.db and ns.db.stats.tooltip and ns.IsOn("stats")) then return end
    local _, unit = tip:GetUnit()
    if not unit or secret(unit) or not UnitExists(unit) or UnitIsPlayer(unit) or not UnitCanAttack("player", unit) then return end
    local name, level = UnitName(unit), UnitLevel(unit)
    if not name or not level or secret(name) or secret(level) then return end
    local class = UnitClassification(unit)
    local xp, from, approx = expectedXp(name, level, not secret(class) and (class == "elite" or class == "rareelite"))
    if xp then
        local toLevel = S.killsToLevel(xp)
        tip:AddLine(("Kill XP: %s%d (%s)%s"):format((approx or from == "estimate") and "~" or "", xp, from,
            toLevel and (" · %d to level"):format(toLevel) or ""), 0.6, 0.8, 1)
    end
end
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tip)
        if tip == GameTooltip then onTooltipUnit(tip) end
    end)
else
    GameTooltip:HookScript("OnTooltipSetUnit", onTooltipUnit)
end

-- Kills from before zones were kept get an approximate zone, once (user decision 2026-11-11: they were made where
-- the others were): each mob's go to the zone it died in most, with map spots copied from its recorded ones and
-- nudged so they don't stack; the per-level and per-hour totals put their unzoned part in that period's busiest
-- zone, or the character's. Rows filled this way are marked approxZone. Kills of a mob never seen in a zone stay
-- unknown. Dungeon kills (level hidden) are never guessed into a zone: a table whose unzoned parts may hold some is
-- left as it is.
local function busiest(zones) -- the map ID with the most kills; dungeons (names) aren't guessed into
    local best, most = nil, 0
    for map, v in pairs(zones or {}) do
        local n = type(v) == "table" and v.count or v
        if type(map) == "number" and map ~= -1 and n > most then best, most = map, n end
    end
    return best
end
function S.fillZones(db)
    db.zonesFilled = true
    local overall, moved, hidden = {}, {}, 0
    for _, r in pairs(db.kills) do
        if r.map then overall[r.map] = (overall[r.map] or 0) + r.count end
        if r.hidden then hidden = hidden + r.count end
    end
    for key, r in pairs(db.kills) do
        local mob = db.mobs[r.name]
        local map = not r.map and mob and busiest(mob.zones)
        if map then moved[key] = map end
    end
    for key, map in pairs(moved) do
        local r = db.kills[key]
        db.kills[key] = nil
        local newKey = r.name .. "|" .. tostring(r.level) .. "|" .. tostring(r.diff) .. "|" .. (r.group or 1) .. "|" .. map
        local into = db.kills[newKey]
        if into then
            into.count, into.xp, into.approxZone = into.count + r.count, into.xp + r.xp, true
        else
            r.map, r.approxZone = map, true
            db.kills[newKey] = r
        end
        local mob = db.mobs[r.name]
        mob.zones[map] = (mob.zones[map] or 0) + r.count
        local own = {}
        for _, spot in ipairs(mob.spots) do
            if spot[1] == map then own[#own + 1] = spot end
        end
        for i = 1, math.min(r.count, #own > 0 and 300 or 0) do
            local from = own[(i - 1) % #own + 1]
            local dx, dy = ((i * 37) % 11 - 5) / 1000, ((i * 53) % 11 - 5) / 1000 -- a small fixed nudge per copy
            table.insert(mob.spots, {map, math.min(1, math.max(0, from[2] + dx)), math.min(1, math.max(0, from[3] + dy))})
        end
        while #mob.spots > 300 do table.remove(mob.spots, 1) end
    end
    local fallback = busiest(overall)
    for _, t in ipairs({"byLevel", "byHour"}) do
        local placed = 0 -- dungeon kills the totals already have under their dungeon
        for _, v in pairs(db[t]) do
            for map, z in pairs(v.zones or {}) do
                if type(map) == "string" then placed = placed + z.count end
            end
        end
        for _, v in pairs(placed >= hidden and db[t] or {}) do -- else some may be in the unzoned parts: left alone
            v.zones = v.zones or {}
            local rest = {count = v.count, xp = v.xp, gcount = v.gcount or 0, gxp = v.gxp or 0}
            for map, z in pairs(v.zones) do
                if map ~= -1 then
                    rest.count, rest.xp = rest.count - z.count, rest.xp - z.xp
                    rest.gcount, rest.gxp = rest.gcount - (z.gcount or 0), rest.gxp - (z.gxp or 0)
                end
            end
            local map = busiest(v.zones) or fallback
            if map and rest.count > 0 then
                local z = v.zones[map] or {count = 0, xp = 0}
                v.zones[map] = z
                z.count, z.xp = z.count + rest.count, z.xp + rest.xp
                if rest.gcount > 0 then z.gcount, z.gxp = (z.gcount or 0) + rest.gcount, (z.gxp or 0) + rest.gxp end
                v.zones[-1] = nil
            end
        end
    end
end

-- Dungeon kills from before they were kept have no level and no zone: they get their dungeon, from the mob's name,
-- once per character (user decision 2026-11-12), and hidden = true. The per-level and per-hour totals don't say which
-- dungeon their unzoned part is from, so it stays unknown unless it can only be one dungeon's (see below).
-- shortcut: the table only covers Uldaman's and Zul'Farrak's mobs (the dungeons played before this was kept); other
-- dungeons' old kills stay unknown. Add them here if they show up.
local OLD_DUNGEON = {}
for dungeon, names in pairs({
    ["Uldaman"] = {"Ancient Stone Keeper", "Archaedas", "Baelog", "Olaf", 'Eric "The Swift"', "Ironaya",
        "Galgann Firehammer", "Grimlok", "Revelosh", "Obsidian Sentinel", "Stone Keeper", "Stone Steward",
        "Jadespine Basilisk", "Deadly Cleft Scorpid", "Venomlash Scorpid", "Shrike Bat", "Shadowforge Archaeologist",
        "Shadowforge Darkcaster", "Shadowforge Geologist", "Shadowforge Sharpshooter"},
    ["Zul'Farrak"] = {"Antu'sul", "Servant of Antu'sul", "Gahz'rilla", "Chief Ukorz Sandscalp", "Ruuzlu",
        "Hydromancer Velratha", "Theka the Martyr", "Shadowpriest Sezz'ziz", "Nekrum Gutchewer", "Sergeant Bly",
        "Raven", "Oro Eyegouge", "Murta Grimgut", "Witch Doctor Zum'rah", "Scarab"},
}) do
    for _, name in ipairs(names) do OLD_DUNGEON[name] = dungeon end
end
local OLD_DUNGEON_PREFIX = {{"Stonevault ", "Uldaman"}, {"Earthen ", "Uldaman"}, {"Sandfury ", "Zul'Farrak"},
    {"Sul'lithuz ", "Zul'Farrak"}, {"Zul'Farrak ", "Zul'Farrak"}}
local function oldDungeon(name)
    if OLD_DUNGEON[name] then return OLD_DUNGEON[name] end
    for _, p in ipairs(OLD_DUNGEON_PREFIX) do
        if name:sub(1, #p[1]) == p[1] then return p[2] end
    end
end
function S.fillDungeons(db)
    db.dungeonsFilled = true
    for _, t in ipairs({"kills", "byLevel", "byHour", "mobs"}) do db[t] = db[t] or {} end
    local found, moved = {}, {} -- moved: dungeon -> {count, xp, gcount, gxp} of the kills given it
    for key, r in pairs(db.kills) do
        local d = not r.map and r.level == nil and oldDungeon(r.name)
        if d then found[key] = d end
    end
    for key, d in pairs(found) do
        local r = db.kills[key]
        db.kills[key] = nil
        r.map, r.hidden = d, true
        local newKey = r.name .. "|nil|nil|" .. (r.group or 1) .. "|" .. d
        local into = db.kills[newKey]
        if into then into.count, into.xp, into.hidden = into.count + r.count, into.xp + r.xp, true
        else db.kills[newKey] = r end
        local mob = db.mobs[r.name]
        if mob then
            mob.zones = mob.zones or {}
            mob.zones[d] = (mob.zones[d] or 0) + r.count
        end
        local m = moved[d] or {count = 0, xp = 0, gcount = 0, gxp = 0}
        moved[d] = m
        local grouped = (r.group or 1) > 1
        m.count, m.xp = m.count + r.count, m.xp + r.xp
        if grouped then m.gcount, m.gxp = m.gcount + r.count, m.gxp + r.xp end
    end
    -- The totals' unzoned parts go to a dungeon only when that's certain: one dungeon's kills were moved, every other
    -- kill row has a zone, and the unzoned parts add up to exactly its kills, XP and group kills. Else they stay unknown.
    local only = next(moved)
    if not only or next(moved, only) ~= nil then return end
    for _, r in pairs(db.kills) do
        if not r.map then return end
    end
    local want = moved[only]
    for _, t in ipairs({"byLevel", "byHour"}) do
        local sum = {count = 0, xp = 0, gcount = 0, gxp = 0}
        for _, v in pairs(db[t]) do
            local z = v.zones and v.zones[-1]
            if z then
                for k in pairs(sum) do sum[k] = sum[k] + (z[k] or 0) end
            end
        end
        if sum.count == want.count and sum.xp == want.xp and sum.gcount == want.gcount and sum.gxp == want.gxp then
            for _, v in pairs(db[t]) do
                local z = v.zones and v.zones[-1]
                if z then
                    local into = v.zones[only] or {count = 0, xp = 0}
                    v.zones[only], v.zones[-1] = into, nil
                    into.count, into.xp = into.count + z.count, into.xp + z.xp
                    if (z.gcount or 0) > 0 then into.gcount, into.gxp = (into.gcount or 0) + z.gcount, (into.gxp or 0) + z.gxp end
                end
            end
        end
    end
end

-- this character's name as the game shows it (Forever's two-part names joined) and its realm
local function myKey()
    local name = NameUtil and NameUtil.FormatUnitNameForDisplay and NameUtil.FormatUnitNameForDisplay("player")
    if not name or secret(name) then name = UnitName("player") end
    local realm = GetRealmName()
    return name .. " - " .. realm, name, realm
end
S.myKey = myKey

tinsert(ns.onLoad, function(root)
    root.killStats = type(root.killStats) == "table" and root.killStats or {}
    local key, name, realm = myKey()
    local me = root.killStats[key] or {}
    root.killStats[key] = me
    me.name, me.realm, me.class = name, realm, select(2, UnitClass("player"))
    for _, t in ipairs({"kills", "byLevel", "byHour", "mobs", "deaths"}) do me[t] = me[t] or {} end
    S.primeDeaths() -- a recap from before (the session before) isn't a new death
    -- What Kureq Stats kept on this character moves here once, with its settings and the window's filters
    local old = type(KureqStatsDB) == "table" and KureqStatsDB
    if old and old.kills then
        for _, t in ipairs({"kills", "byLevel", "byHour", "mobs"}) do
            for k, v in pairs(old[t] or {}) do me[t][k] = v end
        end
        me.zonesFilled = me.zonesFilled or old.zonesFilled
        for _, k in ipairs({"tooltip", "chat", "filter", "zone"}) do
            if old[k] ~= nil then root.stats[k] = old[k] end
        end
        KureqStatsDB = {movedTo = "KureqUtilsDB.killStats"}
    end
    -- kills from before group sizes were kept count as solo (user decision): key them like new solo kills
    local ungrouped = {}
    for k, r in pairs(me.kills) do
        if not r.group then ungrouped[k] = r end
    end
    for k, r in pairs(ungrouped) do
        me.kills[k], r.group = nil, 1
        me.kills[k .. "|1"] = r
    end
    for _, c in pairs(root.killStats) do -- every character's, as the window shows them all
        if type(c) == "table" and not c.dungeonsFilled then S.fillDungeons(c) end
    end
    if not me.zonesFilled then S.fillZones(me) end
    S.mine = me
end)

-- The window's data: one character's (ns.db.stats.char is its key), or every character's added together
local function addBucket(into, v)
    into.count, into.xp = (into.count or 0) + v.count, (into.xp or 0) + v.xp
    if v.gcount then into.gcount, into.gxp = (into.gcount or 0) + v.gcount, (into.gxp or 0) + v.gxp end
end
local function addLoot(into, t)
    if not t then return into end
    into = into or {n = 0, money = 0, items = {}}
    into.n, into.money = into.n + t.n, into.money + t.money
    if t.coinN then
        into.coinN = (into.coinN or 0) + t.coinN
        into.coinMin, into.coinMax = math.min(into.coinMin or t.coinMin, t.coinMin), math.max(into.coinMax or t.coinMax, t.coinMax)
    end
    for id, it in pairs(t.items) do
        local m = into.items[id] or {0, 0}
        into.items[id] = m
        m[1], m[2] = m[1] + it[1], m[2] + it[2]
    end
    return into
end
local function lowest(a, b) if a and b then return math.min(a, b) end return a or b end
local function highest(a, b) if a and b then return math.max(a, b) end return a or b end
function S.view()
    local chars = ns.db.killStats
    if ns.db.stats.char ~= "all" then return chars[ns.db.stats.char] or S.mine end
    local all = {kills = {}, byLevel = {}, byHour = {}, mobs = {}, deaths = {}}
    for key, c in pairs(chars) do
        for _, d in ipairs(c.deaths or {}) do
            local copy = {char = key}
            for k, v in pairs(d) do copy[k] = v end
            all.deaths[#all.deaths + 1] = copy
        end
        for key, r in pairs(c.kills) do
            local m = all.kills[key]
            if m then m.count, m.xp = m.count + r.count, m.xp + r.xp
            else all.kills[key] = {name = r.name, level = r.level, diff = r.diff, group = r.group, map = r.map,
                hidden = r.hidden, count = r.count, xp = r.xp} end
        end
        for _, t in ipairs({"byLevel", "byHour"}) do
            for k, v in pairs(c[t]) do
                local b = all[t][k] or {zones = {}}
                all[t][k] = b
                addBucket(b, v)
                for map, z in pairs(v.zones or {}) do
                    b.zones[map] = b.zones[map] or {}
                    addBucket(b.zones[map], z)
                end
            end
        end
        for name, mob in pairs(c.mobs) do
            local m = all.mobs[name] or {spots = {}, zones = {}}
            all.mobs[name] = m
            for _, spot in ipairs(mob.spots or {}) do m.spots[#m.spots + 1] = spot end
            for map, n in pairs(mob.zones or {}) do m.zones[map] = (m.zones[map] or 0) + n end
            m.min, m.gmin, m.first = lowest(m.min, mob.min), lowest(m.gmin, mob.gmin), lowest(m.first, mob.first)
            m.max, m.gmax, m.last = highest(m.max, mob.max), highest(m.gmax, mob.gmax), highest(m.last, mob.last)
            m.loot, m.skin = addLoot(m.loot, mob.loot), addLoot(m.skin, mob.skin)
        end
    end
    return all
end

-- Loot: what each mob drops, counted once per corpse: mob.loot = {n = corpses looted, money = copper, coinN = corpses
-- with coin, coinMin / coinMax = the least and most coin from one,
-- items = {[itemID] = {corpses that dropped it, how many in all}}}. Skinning (and mining or herb gathering a corpse)
-- goes to mob.skin instead: loot that opens right after one of those casts. The loot window names each item's corpse (GetLootSourceInfo), so area
-- loot splits right; without it the loot is your dead target's. Fishing is left out, and hidden (secret) GUIDs.
-- A corpse with nothing on it opens no loot window, so S.checkEmpty counts it (n + 1, no items, no coin) when you
-- target or mouse over it, or a second after its kill: dead, not tapped by others, and CanLootUnit says no loot. A
-- corpse you've just looted empty was counted by its loot already, so it isn't counted twice.
-- shortcut: only what you loot is seen; in a group, items others loot (or master loot) don't count, and a corpse
-- someone else emptied first counts as empty.
local GATHER_IDS = {8613, 8617, 8618, 10768, 2366, 2368, 3570, 11993, 2575, 2576, 3564, 10248}
local gatherIDs, gatherNames, gatheredAt = {}, nil, -10
for _, id in ipairs(GATHER_IDS) do gatherIDs[id] = true end
local function isGathering(spellID)
    if gatherIDs[spellID] then return true end
    if not gatherNames then -- the casts' names in the client's language, from the known IDs
        gatherNames = {}
        for _, id in ipairs(GATHER_IDS) do
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
            local name = info and info.name or (GetSpellInfo and GetSpellInfo(id))
            if name then gatherNames[name] = true end
        end
    end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    local name = info and info.name or (GetSpellInfo and GetSpellInfo(spellID))
    return name ~= nil and gatherNames[name] == true
end
local counted = {} -- "GUID loot" / "GUID skin" -> true: each corpse counts once per kind (this session)
local MONEY = Enum and Enum.LootSlotType and Enum.LootSlotType.Money or 2
-- c = {items = {[itemID] = how many}, money = copper} from one corpse; true when it was counted
local function countCorpse(guid, kind, c)
    local name = guidName[guid] or npcName[npcID(guid) or ""]
    if not name or counted[guid .. kind] then return false end
    counted[guid .. kind] = true
    local mob = S.mine.mobs[name] or {spots = {}, zones = {}}
    S.mine.mobs[name] = mob
    local t = mob[kind] or {n = 0, money = 0, items = {}}
    mob[kind] = t
    t.n, t.money = t.n + 1, t.money + c.money
    if c.money > 0 then -- corpses with coin, and the least and most from one
        t.coinN = (t.coinN or 0) + 1
        t.coinMin, t.coinMax = math.min(t.coinMin or c.money, c.money), math.max(t.coinMax or c.money, c.money)
    end
    for id, n in pairs(c.items) do -- {corpses that dropped it, how many in all}: chance = corpses / t.n
        local it = t.items[id] or {0, 0}
        t.items[id] = it
        it[1], it[2] = it[1] + 1, it[2] + n
    end
    return true
end
function S.onLoot()
    if IsFishingLoot and IsFishingLoot() then return end
    local kind = GetTime() - gatheredAt < 3 and "skin" or "loot"
    local corpses = {}
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        local id = link and tonumber(link:match("item:(%d+)"))
        local money = GetLootSlotType(slot) == MONEY
        local sources = GetLootSourceInfo and {GetLootSourceInfo(slot)} or {}
        if #sources == 0 then
            local _, _, quantity = GetLootSlotInfo(slot)
            sources = {UnitGUID("target") or false, quantity or 1}
        end
        for i = 1, #sources, 2 do
            local guid, quantity = sources[i], sources[i + 1] or 1
            if guid and not secret(guid) and not secret(quantity) and guid:match("^Creature") then
                local c = corpses[guid] or {items = {}, money = 0}
                corpses[guid] = c
                if money then c.money = c.money + quantity
                elseif id then c.items[id] = (c.items[id] or 0) + quantity end
            end
        end
    end
    for guid, c in pairs(corpses) do countCorpse(guid, kind, c) end
    if S.refresh then S.refresh() end
end
-- unit: a corpse the player can see; counted as an empty loot when it has nothing on it (see above)
function S.checkEmpty(unit)
    if not CanLootUnit or not UnitExists(unit) or UnitIsPlayer(unit) then return end
    local guid = UnitGUID(unit)
    if not guid or secret(guid) or not guid:match("^Creature") or counted[guid .. "loot"] then return end
    local dead, tapped = UnitIsDead(unit), UnitIsTapDenied(unit) -- any of these can be secret in instances
    if secret(dead) or secret(tapped) or not dead or tapped then return end
    local hasLoot = CanLootUnit(guid) -- nil when the client doesn't know
    if secret(hasLoot) or hasLoot ~= false then return end
    if countCorpse(guid, "loot", {items = {}, money = 0}) and S.refresh then S.refresh() end
end

-- Deaths: each of this character's deaths, in mine.deaths (newest last, the latest 500): {t, map, x, y, level,
-- group, killer, kind ("player", "pet", "world" for falling, drowning and lava, "mob"), spell, killerLevel, maxHp,
-- hits = the recap's last hits, killing blow first: {t, amount, overkill, absorbed, resisted, blocked, school,
-- spell, spellId, source, kind, hp}}. The
-- killer comes from the death recap (C_DeathRecap), as Forever's own death dialog reads it: its event 1 is the
-- killing blow. It can fill a moment after PLAYER_DEAD, so it's read again each second for 5 seconds; a killing
-- blow already used, or more than 30 seconds off both clocks, is an earlier death's. Secret names are left out.
local MAX_DEATHS, RECAP_TRIES, RECAP_STALE = 500, 5, 30
local lastBlow -- the killing blow last used, by its timestamp
local function plain(v) if v ~= nil and not secret(v) then return v end end
local function killingBlow()
    if type(C_DeathRecap) ~= "table" or type(C_DeathRecap.GetRecapEvents) ~= "function" then return end
    local ok, events = pcall(C_DeathRecap.GetRecapEvents)
    if not ok or type(events) ~= "table" or secret(events) then return end
    if canaccesstable and not canaccesstable(events) then return end -- a table kept from addons
    local blow = events[1]
    if type(blow) ~= "table" then return end
    local when = plain(blow.timestamp)
    if type(when) ~= "number" then return end
    -- every hit as plain values (secret ones left out), for the recap
    local hits = {}
    for _, e in ipairs(events) do
        if type(e) == "table" then
            local env = plain(e.event) == "ENVIRONMENTAL_DAMAGE"
            local guid = plain(e.sourceGUID)
            local envType = plain(e.environmentalType)
            local source = env and type(envType) == "string" and (_G["ACTION_ENVIRONMENTAL_DAMAGE_" .. envType:upper()] or envType)
                or not plain(e.hideCaster) and plain(e.sourceName) or nil
            hits[#hits + 1] = {t = plain(e.timestamp), amount = plain(e.amount), overkill = plain(e.overkill),
                absorbed = plain(e.absorbed), resisted = plain(e.resisted), blocked = plain(e.blocked),
                school = plain(e.school), spellId = plain(e.spellId),
                spell = not env and plain(e.event) ~= "SWING_DAMAGE" and plain(e.spellName) or nil,
                source = type(source) == "string" and source or nil, hp = plain(e.currentHP),
                kind = env and "world" or type(guid) == "string" and (guid:match("^Player%-") and "player"
                    or guid:match("^Pet%-") and "pet") or "mob"}
        end
    end
    local first = hits[1]
    if not first.source then return when, nil, nil, nil, hits end
    return when, first.source, first.kind, first.spell, hits
end
local function fillKiller(d, tries)
    local ok, when, killer, kind, spell, hits = pcall(killingBlow)
    local server = GetServerTime and GetServerTime() or time()
    local fresh = ok and when and when ~= lastBlow
        and (when < 1e9 or math.abs(when - time()) <= RECAP_STALE or math.abs(when - server) <= RECAP_STALE)
    if fresh then
        lastBlow = when
        d.killer, d.kind, d.spell, d.hits = killer, kind, spell, hits
        if kind == "mob" then d.killerLevel = seen[killer] end -- from your target, mouseover or nameplates
        local okMax, maxHp = pcall(function() return C_DeathRecap.GetRecapMaxHealth and C_DeathRecap.GetRecapMaxHealth() end)
        if okMax and type(maxHp) == "number" and not secret(maxHp) then d.maxHp = maxHp end
        if S.refresh then S.refresh() end
        if S.showRecap and ns.db.stats.recap then S.showRecap(d) end
    elseif tries > 1 and C_Timer then
        C_Timer.After(1, function() fillKiller(d, tries - 1) end)
    elseif S.showRecap and ns.db.stats.recap then
        S.showRecap(d) -- no recap came: the popup says so
    end
end
function S.primeDeaths()
    local ok, when = pcall(killingBlow)
    lastBlow = ok and when or nil
end
function S.onDeath()
    local d = {t = time(), level = UnitLevel("player"), group = groupSize()}
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if map and not secret(map) then
        d.map = map
        local pos = C_Map.GetPlayerMapPosition(map, "player")
        local x, y
        if pos then x, y = pos:GetXY() end
        if x and not secret(x) and not secret(y) then d.x, d.y = x, y end
    end
    S.mine.deaths = S.mine.deaths or {}
    table.insert(S.mine.deaths, d)
    while #S.mine.deaths > MAX_DEATHS do table.remove(S.mine.deaths, 1) end
    fillKiller(d, RECAP_TRIES)
    if S.refresh then S.refresh() end
end

local events = CreateFrame("Frame")
for _, e in ipairs({"CHAT_MSG_COMBAT_XP_GAIN", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "NAME_PLATE_UNIT_ADDED", "LOOT_READY", "LOOT_OPENED", "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_DEAD"}) do
    pcall(events.RegisterEvent, events, e) -- a client without one of them just doesn't send it
end
events:SetScript("OnEvent", function(_, event, arg, _, spellID)
    if not (ns.db and ns.IsOn("stats")) then return end -- before Kureq Utils has loaded its saved settings, or off
    if event == "PLAYER_DEAD" then
        S.onDeath()
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then -- both can fire; a corpse counts once
        if ns.db.stats.loot then S.onLoot() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if arg == "player" and not secret(spellID) and isGathering(spellID) then gatheredAt = GetTime() end
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        if secret(arg) then return end
        local name, xp = arg:match(KILL)
        if name then record(name, tonumber(xp)) end
        if name and ns.db.stats.loot and C_Timer then -- the corpse's loot flag can come a moment after its death
            C_Timer.After(1, function() if ns.db.stats.loot and ns.IsOn("stats") then S.checkEmpty("target") end end)
        end
    elseif event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" then
        local unit = event == "PLAYER_TARGET_CHANGED" and "target" or "mouseover"
        look(unit)
        if ns.db.stats.loot then S.checkEmpty(unit) end
    else look(arg) end -- NAME_PLATE_UNIT_ADDED gives the nameplate's unit
end)

-- Settings page under Kureq Utils
local panel, category = ns.AddSettingsPage("Kill stats",
    "Every mob you kill for experience: kills, XP, levels, zones and groups. Kills that give no XP aren't seen.", "stats")
S.category = category
ns.Checkbox(panel, "Show kill XP on mob tooltips", "Your average XP from that mob at the same level difference and group "
    .. "size, or an estimate (~) from the Classic XP formula until you have one.",
    function() return ns.db.stats.tooltip end, function(v) ns.db.stats.tooltip = v end)
ns.Checkbox(panel, "Print each kill to chat", "Mob, level, XP gained and its running totals after every kill.",
    function() return ns.db.stats.chat end, function(v) ns.db.stats.chat = v end)
ns.Checkbox(panel, "Show a recap when you die", "A small window with the last hits you took: damage by school, by "
    .. "attacker and by spell. Every death's recap is also on the Deaths page.",
    function() return ns.db.stats.recap end, function(v) ns.db.stats.recap = v end)
ns.Checkbox(panel, "Show kills to level", "How many more kills of a mob take you to your next level, on its tooltip and "
    .. "its page, for mobs that still give you XP. Rested XP isn't counted.",
    function() return ns.db.stats.toLevel end, function(v) ns.db.stats.toLevel = v end)
ns.Checkbox(panel, "Track loot", "Count what each mob drops (and what skinning it gives), for drop chances on its "
    .. "page. Only what you loot yourself is seen.", function() return ns.db.stats.loot end, function(v) ns.db.stats.loot = v end)
ns.Button(panel, "Open the window", 160, function() S.toggle() end, "Kill stats window")

-- Clearing, asked first: this character's loot data, or all its kill stats
local clearing
StaticPopupDialogs.KUREQUTILS_CLEAR_STATS = {
    text = "%s", button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function()
        if not ns.IsOn("stats") then return end
        if clearing == "loot" then
            for _, mob in pairs(S.mine.mobs) do mob.loot, mob.skin = nil, nil end
            ns.say("cleared this character's loot data.")
        elseif clearing == "all" then
            for _, t in ipairs({"kills", "byLevel", "byHour", "mobs", "deaths"}) do S.mine[t] = {} end
            ns.say("cleared all of this character's kill stats.")
        end
        clearing = nil
        if S.refresh then S.refresh() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
ns.OnModuleChange("stats", function(on) if not on then StaticPopup_Hide("KUREQUTILS_CLEAR_STATS") end end)
local function ask(what, text)
    clearing = what
    StaticPopup_Show("KUREQUTILS_CLEAR_STATS", text)
end
ns.Button(panel, "Clear loot data", 160, function()
    ask("loot", "Clear this character's loot data? Kills, XP and maps stay.")
end, "Loot data")
ns.Button(panel, "Clear all kill stats", 160, function()
    ask("all", "Clear all of this character's kill stats: kills, XP, maps, loot and deaths? This can't be undone.")
end, "Everything")

-- for the window
S.wanted, S.filtered, S.secret = wanted, filtered, secret
