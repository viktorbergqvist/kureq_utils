-- The kill stats window (Stats.lua), in the look of the character sheet and Road to Sixty: dark panes with the tooltip border on
-- the character sheet's background, page tabs under the window (Mobs, Graphs, Map, Deaths), a row of stat tiles, and below
-- either the mob list beside the chosen mob's map and numbers, or four charts. Every number follows the search
-- (list only), zone and Solo / Group filters.
local _, ns = ...
local S = ns.stats
local wanted, filtered = S.wanted, S.filtered

local St = ns.style
local W, H = 940, 620
local BW, BH = St.bodySize(W, H)
local PAD, GAP = 12, 8
local TOP_H, TILE_H = 28, 62
local MAIN_Y = -(PAD + TOP_H + GAP + TILE_H + GAP) -- where the panes below the tiles start
local LIST_W, ROW_H = 330, 34
local MAP_W, MAP_H = 330, 220
local DETAIL_W = BW - 2 * PAD - LIST_W - GAP -- the pane right of the list
local GOLD, commas = St.GOLD, St.commas
local Pane, Text, Line, TextTab, Tooltip = St.Pane, St.Text, St.Line, St.TextTab, St.Tooltip
local function short(n) return n >= 10000 and ("%.1fk"):format(n / 1000) or commas(n) end
local function signed(n) return n > 0 and "+" .. n or tostring(n) end
local function each(xp, count) return count > 0 and math.floor(xp / count + 0.5) or 0 end
local HIDDEN = "In dungeons (level hidden)" -- kills whose level the dungeon kept from addons
local function levels(low, high) return not low and "??" or low == high and tostring(low) or low .. "-" .. high end
local function mapName(map)
    if type(map) == "string" then return map end -- a dungeon, kept by its name
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    return info and info.name or ("Map " .. map)
end

-- Window ----------------------------------------------------------------------------------------------------------

local frame, body = St.Window("KureqStatsFrame", "Kill Stats", W, H) -- the frame name stays for its macros

local page = "mobs" -- or "graphs"
local refresh
local relaying -- set while a resize draws again: the data (V) and the fixed-size maps stay as they are
local V -- the data shown: S.view(), set at each refresh

-- Page tabs under the window; the top bar holds the character, zone and Solo / Group filters
local plaques = {}
for i, p in ipairs({{"Mobs", "mobs"}, {"Graphs", "graphs"}, {"Map", "map"}, {"Deaths", "deaths"}}) do
    local b = St.Tab(frame, p[1], function() page = p[2]; refresh() end)
    b.page = p[2]
    plaques[i] = b
end
frame.tableButton, frame.graphsButton, frame.mapButton, frame.deathsButton = plaques[1], plaques[2], plaques[3], plaques[4]

local GROUPS = {{"Solo and group kills", "all"}, {"Solo kills", "solo"}, {"Group kills", "group"}}
local function isGroup(f) return f == ns.db.stats.filter end
local function setGroup(f) ns.db.stats.filter = f; refresh() end
local groupMenu = St.Dropdown(body, 150, function()
    for _, g in ipairs(GROUPS) do if isGroup(g[2]) then return g[1] end end
end, function(root)
    for _, g in ipairs(GROUPS) do root:CreateRadio(g[1], isGroup, setGroup, g[2]) end
end)
groupMenu:SetPoint("TOPRIGHT", -PAD, -PAD - 3)
frame.groupMenu = groupMenu

-- Zones grouped by continent, dungeons and raids apart: Blizzard's map info names each zone's continent.
local MAP_TYPE = Enum and Enum.UIMapType or {}
local groupOf = {} -- map ID -> its group's name, worked out once
local function zoneGroup(map)
    if groupOf[map] then return groupOf[map] end
    local info, group = type(map) == "number" and C_Map.GetMapInfo and C_Map.GetMapInfo(map), "Other"
    if type(map) == "string" or info and info.mapType == MAP_TYPE.Dungeon then
        group = "Dungeons and raids"
    else
        for _ = 1, 10 do -- up the parents to the continent
            if not info then break end
            if info.mapType == MAP_TYPE.Continent then group = info.name; break end
            info = info.parentMapID and info.parentMapID ~= 0 and C_Map.GetMapInfo(info.parentMapID)
        end
    end
    groupOf[map] = group
    return group
end

-- The zone menu: All zones, a submenu per continent (or the zones themselves when they're all on one), and Unknown
-- zone for kills from before zones were kept. Each zone shows its kills under the Solo / Group filter; long lists
-- scroll. The button shows the zone's name without its count.
local function isZone(map) return map == ns.db.stats.zone end
local function setZone(map) ns.db.stats.zone = map; refresh() end
local function fillZones(root)
    local f, counts, unknown, total = ns.db.stats.filter, {}, 0, 0
    for _, r in pairs(V.kills) do
        if f == "all" or (f == "solo") == ((r.group or 1) == 1) then
            total = total + r.count
            if r.map then counts[r.map] = (counts[r.map] or 0) + r.count else unknown = unknown + r.count end
        end
    end
    local groups, names = {}, {}
    for map, count in pairs(counts) do
        local g = zoneGroup(map)
        if not groups[g] then groups[g], names[#names + 1] = {count = 0, zones = {}}, g end
        groups[g].count = groups[g].count + count
        table.insert(groups[g].zones, {map = map, name = mapName(map), count = count})
    end
    local function rank(g) return g == "Other" and 2 or g == "Dungeons and raids" and 1 or 0 end
    table.sort(names, function(a, b)
        if rank(a) ~= rank(b) then return rank(a) < rank(b) end
        return a < b
    end)
    local function label(text, count) return ("%s  |cff999999%s|r"):format(text, commas(count)) end
    root:SetScrollMode(420)
    root:CreateRadio(label("All zones", total), isZone, setZone, 0)
    for _, g in ipairs(names) do
        table.sort(groups[g].zones, function(a, b) return a.name < b.name end)
        local into = root
        if #names > 1 then
            into = root:CreateButton(label(g, groups[g].count))
            into:SetScrollMode(420)
        end
        for _, z in ipairs(groups[g].zones) do into:CreateRadio(label(z.name, z.count), isZone, setZone, z.map) end
    end
    if unknown > 0 then root:CreateRadio(label("Unknown zone", unknown), isZone, setZone, -1) end
end
local zoneMenu = St.Dropdown(body, 150, function()
    local map = ns.db.stats.zone
    return map == 0 and "All zones" or map == -1 and "Unknown zone" or mapName(map)
end, fillZones)
zoneMenu:SetPoint("RIGHT", groupMenu, "LEFT", -8, 0)
frame.zoneMenu = zoneMenu

-- Character: all of them (added together) or one, by name and realm, in its class color
local function isChar(k) return k == ns.db.stats.char end
local function setChar(k) ns.db.stats.char = k; refresh() end
local function charText(key)
    if key == "all" then return "All characters" end
    local c = ns.db.killStats[key]
    local color = c and c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
    return color and color.colorStr and ("|c%s%s|r"):format(color.colorStr, key) or key
end
local charMenu = St.Dropdown(body, 150, function() return charText(ns.db.stats.char) end, function(root)
    root:CreateRadio(charText("all"), isChar, setChar, "all")
    local keys = {}
    for key in pairs(ns.db.killStats) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do root:CreateRadio(charText(key), isChar, setChar, key) end
end)
charMenu:SetPoint("RIGHT", zoneMenu, "LEFT", -8, 0)
frame.charMenu = charMenu

local search = CreateFrame("EditBox", nil, body, "SearchBoxTemplate") -- placed in the mob list's header below
search:SetSize(140, 20)
search:SetAutoFocus(false)
search:HookScript("OnTextChanged", function() refresh() end)
frame.search = search

-- Stat tiles: a gold label, the number, a grey line under it
local TILES = {"Kills", "Experience", "Today", "Best hour", "Most killed"}
local tiles = {}
for i, label in ipairs(TILES) do
    local t = Pane(body)
    t.label = Text(t, "GameFontNormalSmall")
    t.label:SetPoint("TOPLEFT", 10, -8)
    t.label:SetText(label)
    t.value = Text(t, "GameFontHighlightLarge")
    t.value:SetPoint("TOPLEFT", t.label, "BOTTOMLEFT", 0, -4)
    t.value:SetPoint("RIGHT", -8, 0)
    t.sub = Text(t, "GameFontDisableSmall")
    t.sub:SetPoint("TOPLEFT", t.value, "BOTTOMLEFT", 0, -3)
    t.sub:SetPoint("RIGHT", -8, 0)
    tiles[i] = t
end
frame.tiles = tiles

-- Mob list ---------------------------------------------------------------------------------------------------------

local mobsView = CreateFrame("Frame", nil, body)
mobsView:SetPoint("TOPLEFT", 0, MAIN_Y)
mobsView:SetPoint("BOTTOMRIGHT")

local listPane = Pane(mobsView)
listPane:SetPoint("TOPLEFT", PAD, 0)
listPane:SetPoint("BOTTOMLEFT", PAD, PAD)
listPane:SetWidth(LIST_W)
search:SetParent(listPane)
search:SetPoint("TOPRIGHT", listPane, "TOPRIGHT", -12, -8)
local listTitle = Text(listPane, "GameFontNormal")
listTitle:SetPoint("TOPLEFT", 12, -12)
local listNote = Text(listPane, "GameFontDisableSmall")
listNote:SetPoint("LEFT", listTitle, "RIGHT", 8, 0)

-- Sorting: a text tab per order; the chosen one again reverses it. Name sorts A-Z first, numbers largest first;
-- a mob of unknown level (??) sorts below every known one.
local SORT = {
    {"Name", function(r) return r.name:lower() end},
    {"Level", function(r) return r.high or -math.huge end},
    {"Kills", function(r) return r.count end},
    {"XP", function(r) return r.xp end},
    {"Per kill", function(r) return r.xp / r.count end},
}
local sortCol, sortDesc = 3, true
local ARROW = {[true] = " |TInterface\\Buttons\\Arrow-Down-Up:10:10|t", [false] = " |TInterface\\Buttons\\Arrow-Up-Up:10:10|t"}
local sortTabs = {}
local function showSortTabs()
    for i, tab in ipairs(sortTabs) do tab:Set(SORT[i][1] .. (i == sortCol and ARROW[sortDesc] or ""), i == sortCol) end
end
for i in ipairs(SORT) do
    local tab = TextTab(listPane, function()
        if sortCol == i then sortDesc = not sortDesc else sortCol, sortDesc = i, i ~= 1 end
        showSortTabs()
        refresh()
    end)
    if i == 1 then tab:SetPoint("TOPLEFT", 0, -30) else tab:SetPoint("LEFT", sortTabs[i - 1], "RIGHT", 0, 0) end
    sortTabs[i] = tab
end
showSortTabs()
frame.sortTabs = sortTabs
local listLine = Line(listPane)
listLine:SetPoint("TOPLEFT", 6, -55)
listLine:SetPoint("TOPRIGHT", -6, -55)

local scroll = CreateFrame("ScrollFrame", nil, listPane, "ScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 6, -58)
scroll:SetPoint("BOTTOMRIGHT", -26, 6)
local list = CreateFrame("Frame", nil, scroll)
list:SetSize(LIST_W - 32, 1)
scroll:SetScrollChild(list)
local rows = {}
frame.rows = rows
local selected -- the mob shown on the right

local function Row(i)
    return St.ListRow(list, i, LIST_W - 32, ROW_H, function(self) selected = self.name; refresh() end)
end

-- The mobs under the filters and search, one entry per name: kills, XP and level range
local function mobList()
    local query = (search:GetText() or ""):lower()
    local merged, sorted = {}, {}
    for _, r in pairs(V.kills) do
        if wanted(r) and r.name:lower():find(query, 1, true) then
            local m = merged[r.name]
            if not m then
                m = {name = r.name, count = 0, xp = 0}
                merged[r.name], sorted[#sorted + 1] = m, m
            end
            m.count, m.xp = m.count + r.count, m.xp + r.xp
            if r.level and r.level > 0 then
                m.low, m.high = math.min(m.low or r.level, r.level), math.max(m.high or r.level, r.level)
            end
        end
    end
    local key = SORT[sortCol][2]
    table.sort(sorted, function(a, b)
        local ka, kb = key(a), key(b)
        if ka ~= kb then
            if sortDesc then return ka > kb end
            return ka < kb
        end
        return a.name < b.name -- ties: by name
    end)
    return sorted
end

-- the zone a mob died in most, for its row
local function mainZone(name)
    local mob, best, most = V.mobs[name], nil, 0
    for map, count in pairs(mob and mob.zones or {}) do
        if count > most then best, most = map, count end
    end
    return best and mapName(best)
end

local function refreshList(sorted)
    listTitle:SetText("Mobs")
    listNote:SetText(#sorted == 1 and "1 mob" or #sorted .. " mobs")
    for i, m in ipairs(sorted) do
        local b = rows[i] or Row(i)
        rows[i] = b
        b.name = m.name
        b.nameText:SetText(m.name)
        b.count:SetText(commas(m.count))
        local zone = mainZone(m.name)
        b.sub:SetText("Level " .. levels(m.low, m.high) .. (zone and " · " .. zone or ""))
        b.each:SetText(commas(each(m.xp, m.count)) .. " xp each")
        b:SetPicked(m.name == selected)
        b:Show()
    end
    for i = #sorted + 1, #rows do rows[i]:Hide() end
    list:SetHeight(math.max(1, #sorted * ROW_H))
end

-- Mob detail -------------------------------------------------------------------------------------------------------

local detail = Pane(mobsView)
detail:SetPoint("TOPLEFT", listPane, "TOPRIGHT", GAP, 0)
detail:SetPoint("BOTTOMRIGHT", -PAD, PAD)
frame.detail = detail
local mobTitle = Text(detail, "GameFontNormalLarge")
mobTitle:SetPoint("TOPLEFT", 12, -12)
mobTitle:SetPoint("RIGHT", -12, 0)
local mobSub = Text(detail, "GameFontDisableSmall")
mobSub:SetPoint("TOPLEFT", mobTitle, "BOTTOMLEFT", 0, -4)
local empty = Text(detail, "GameFontDisable")
empty:SetPoint("CENTER")
empty:SetText("No kills yet. Kill something that gives experience.")

-- Overview (map, numbers, breakdowns) and Loot (drop chances), switched by text tabs at the top right
local overview = CreateFrame("Frame", nil, detail)
overview:SetAllPoints()
local lootView = CreateFrame("Frame", nil, detail)
lootView:SetAllPoints()
lootView:Hide()
frame.lootView = lootView
local detailTab = "overview"
local detailTabs = {}
for i, t in ipairs({{"Overview", "overview"}, {"Loot", "loot"}}) do
    local tab = TextTab(detail, function() detailTab = t[2]; refresh() end)
    tab.page = t[2]
    tab.title = t[1]
    if i == 1 then tab:SetPoint("TOPRIGHT", -80, -8) else tab:SetPoint("LEFT", detailTabs[1], "RIGHT", 0, 0) end
    detailTabs[i] = tab
end
frame.detailTabs = detailTabs

local mapBox = Pane(overview)
mapBox:SetPoint("TOPLEFT", 12, -50)
mapBox:SetSize(MAP_W + 8, MAP_H + 8)
-- the mob's map: its zone's art with a dot per kill spot, zoomable (MapView.lua)
local mobMap = St.MapView(mapBox, MAP_W, MAP_H)
mobMap.view:SetPoint("TOPLEFT", 4, -4)
frame.mapView = mobMap.view
local function resetZoom() mobMap:Reset() end
frame.resetZoom = resetZoom
local drawnMap
local function drawMap(map, spots)
    drawnMap = map
    local marks = {}
    for _, spot in ipairs(spots) do
        if spot[1] == map then marks[#marks + 1] = {x = spot[2], y = spot[3]} end
    end
    mobMap:Draw(type(map) == "number" and map or nil, marks, type(map) == "string" and "No map inside dungeons"
        or map and "No map for this zone" or "No kill locations yet: kills before zones were kept have none")
end
local zoomHint = Text(overview, "GameFontDisableSmall")
zoomHint:SetPoint("BOTTOMRIGHT", mapBox, "TOPRIGHT", -2, 4)
zoomHint:SetJustifyH("RIGHT")
zoomHint:SetText("Scroll to zoom · drag to move · right-click: whole zone")

-- zone tabs under the map, most kills first; the chosen one shows on the map. The row keeps inside the pane: when
-- the names don't fit, each tab gets an equal share and its name ends in "..." (the full name on hover).
local ZONE_TABS, ZONE_TAB_GAP = 4, 2
local zoneTabs, shownMap = {}, nil
local function refreshZoneTabs(mob)
    local zones = {}
    for map, count in pairs(mob and mob.zones or {}) do zones[#zones + 1] = {map = map, count = count} end
    table.sort(zones, function(a, b) return a.count > b.count end)
    local known = false
    for _, z in ipairs(zones) do known = known or z.map == shownMap end
    if not known then shownMap = zones[1] and zones[1].map end
    local n = math.min(ZONE_TABS, #zones)
    local share = n > 0 and math.floor((DETAIL_W - 24 - (n - 1) * ZONE_TAB_GAP) / n)
    for i = 1, math.max(ZONE_TABS, #zoneTabs) do
        local z, tab = i <= ZONE_TABS and zones[i], zoneTabs[i]
        if z and not tab then
            tab = TextTab(overview, function(self) shownMap = self.map; refresh() end)
            if i == 1 then tab:SetPoint("TOPLEFT", mapBox, "BOTTOMLEFT", 0, -2)
            else tab:SetPoint("LEFT", zoneTabs[i - 1], "RIGHT", ZONE_TAB_GAP, 0) end
            zoneTabs[i] = tab
        end
        if z then
            tab.map = z.map
            tab:Set(("%s  %d"):format(mapName(z.map), z.count), z.map == shownMap, share)
            tab:Show()
        elseif tab then
            tab:Hide()
        end
    end
end
frame.zoneTabs = zoneTabs

-- label / value pairs to the right of the map: one column, as the map leaves room for no more
local FACTS_X = 12 + MAP_W + 8 + 16
local facts = St.Facts(overview, 8, FACTS_X, -54, DETAIL_W - FACTS_X - 12, 1)
frame.facts = facts

-- two small tables under the map: by mob level and by group size, each row with a bar for its share of the kills
local BREAK_ROWS = 4
local function Breakdown(title, anchorX, width)
    local t = {rows = {}}
    t.title = Text(overview, "GameFontNormal")
    t.title:SetPoint("TOPLEFT", mapBox, "BOTTOMLEFT", anchorX, -32)
    t.title:SetText(title)
    local line = Line(overview)
    line:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -4)
    line:SetWidth(width)
    function t:Resize(w)
        line:SetWidth(w)
        for _, r in ipairs(self.rows) do r:Resize(w) end
    end
    for i = 1, BREAK_ROWS do
        local r = St.BarRow(overview, width, {0.25, 0.6, 1})
        r:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -4 - (i - 1) * 22)
        t.rows[i] = r
    end
    return t
end
local byLevel = Breakdown("By mob level", 0, MAP_W + 8)
local byGroup = Breakdown("By group size (every kill)", MAP_W + 24, DETAIL_W - MAP_W - 48)
frame.byLevel, frame.byGroup = byLevel, byGroup

local function fillBreakdown(t, items, total)
    for i, r in ipairs(t.rows) do
        local item = items[i]
        r:SetShown(item ~= nil)
        if item then r:Set(item.label, item.value, item.count / math.max(1, total)) end
    end
end

local function stamp(t) return t and date("%d %b, %H:%M", t) or "-" end

-- The loot view: how often you looted it, its money, and each item with its drop chance (corpses that dropped it /
-- corpses looted), skinning apart. Hover an item for its tooltip.
local LOOT_ROWS, LOOT_ROW_H = 12, 20
local lootFacts = St.Facts(lootView, 6, 12, -54, math.floor((DETAIL_W - 24 - 16) / 2), 2)
for i, label in ipairs({"Looted", "Skinned", "Coin in all", "Coin per loot", "Drops coin", "Coin range"}) do
    lootFacts[i].label:SetText(label)
end
frame.lootFacts = lootFacts
local function LootList(title, x, width)
    local l = {rows = {}}
    l.title = Text(lootView, "GameFontNormal")
    l.title:SetPoint("TOPLEFT", x, -124)
    l.title:SetText(title)
    l.note = Text(lootView, "GameFontDisableSmall")
    l.note:SetPoint("LEFT", l.title, "RIGHT", 8, 0)
    local line = Line(lootView)
    line:SetPoint("TOPLEFT", l.title, "BOTTOMLEFT", 0, -4)
    line:SetWidth(width)
    function l:Place(lx, w) -- at x in the loot view, w wide
        self.title:SetPoint("TOPLEFT", lx, -124)
        line:SetWidth(w)
        for _, b in ipairs(self.rows) do b:SetWidth(w) end
    end
    l.empty = Text(lootView, "GameFontDisable")
    l.empty:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -8)
    for i = 1, LOOT_ROWS do
        local b = CreateFrame("Button", nil, lootView)
        b:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -4 - (i - 1) * LOOT_ROW_H)
        b:SetSize(width, LOOT_ROW_H)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("LEFT", 2, 0)
        b.icon:SetSize(16, 16)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.nameText = Text(b, "GameFontHighlightSmall")
        b.nameText:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
        b.nameText:SetPoint("RIGHT", -96, 0)
        b.chance = Text(b, "GameFontHighlightSmall")
        b.chance:SetPoint("RIGHT", -44, 0)
        b.chance:SetJustifyH("RIGHT")
        b.count = Text(b, "GameFontDisableSmall")
        b.count:SetPoint("RIGHT", -4, 0)
        b.count:SetJustifyH("RIGHT")
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. self.id)
            GameTooltip:AddLine(self.tip, 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        l.rows[i] = b
    end
    return l
end
local SKINS_W = 160
local drops = LootList("Drops", 12, DETAIL_W - 24 - 16 - SKINS_W)
drops.tip = "Dropped by %d of %d corpses looted (%.1f%%), %s in all"
local skins = LootList("Skinning", DETAIL_W - 12 - SKINS_W, SKINS_W)
skins.tip = "Came from %d of %d skins (%.1f%%), %s in all"
frame.drops, frame.skins = drops, skins

local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local waitingItems -- items asked from the server; their names come with GET_ITEM_INFO_RECEIVED
local function itemText(id)
    local name, _, quality = GetItemInfo(id)
    if not name then
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        waitingItems = true
        return "Item " .. id
    end
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return color and color.hex and (color.hex .. name .. "|r") or name
end
local function fillLoot(l, t)
    local list = {}
    for id, it in pairs(t and t.items or {}) do list[#list + 1] = {id = id, corpses = it[1], total = it[2]} end
    table.sort(list, function(a, b)
        if a.corpses ~= b.corpses then return a.corpses > b.corpses end
        return a.id < b.id
    end)
    l.empty:SetShown(#list == 0)
    l.note:SetText(#list > LOOT_ROWS and ("the %d most dropped of %d"):format(LOOT_ROWS, #list) or "")
    for i, b in ipairs(l.rows) do
        local item = list[i]
        b:SetShown(item ~= nil)
        if item then
            b.id = item.id
            b.icon:SetTexture(C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item.id)
                or GetItemIcon and GetItemIcon(item.id) or 134400)
            b.nameText:SetText(itemText(item.id))
            b.chance:SetText(("%.1f%%"):format(100 * item.corpses / t.n))
            b.count:SetText(item.corpses)
            b.tip = (l.tip):format(item.corpses, t.n, 100 * item.corpses / t.n, commas(item.total))
        end
    end
end
-- "1g 95s 33c" with the coin icons; leading zero parts left out. Our own: Forever has no global GetCoinTextureString.
local COIN = "%d|TInterface\\MoneyFrame\\UI-%sIcon:14:14:2:0|t"
local function money(copper)
    copper = math.floor(copper + 0.5)
    local gold, silver = math.floor(copper / 10000), math.floor(copper / 100) % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = COIN:format(gold, "Gold") end
    if gold > 0 or silver > 0 then parts[#parts + 1] = COIN:format(silver, "Silver") end
    parts[#parts + 1] = COIN:format(copper % 100, "Copper")
    return table.concat(parts, " ")
end
local function refreshLoot(mob, kills)
    local loot, skin = mob and mob.loot, mob and mob.skin
    -- grey mobs (no XP, so no kill recorded) can still be looted: then just the corpses
    lootFacts[1].value:SetText(not loot and "not yet" or loot.n <= kills and ("%d of %d kills"):format(loot.n, kills)
        or ("%d corpses"):format(loot.n))
    lootFacts[2].value:SetText(skin and (skin.n == 1 and "once" or skin.n .. " times") or "not yet")
    local coin = loot and loot.money > 0
    lootFacts[3].value:SetText(coin and money(loot.money) or "-")
    lootFacts[4].value:SetText(coin and money(loot.money / loot.n) or "-")
    -- corpses with coin: counted since this was added; older loot only has the total
    lootFacts[5].value:SetText(coin and loot.coinN and ("%.0f%% of corpses"):format(100 * loot.coinN / loot.n) or "-")
    lootFacts[6].value:SetText(coin and loot.coinMin and (money(loot.coinMin) .. " - " .. money(loot.coinMax)) or "-")
    drops.empty:SetText(ns.db.stats.loot and "Nothing looted from it yet." or "Loot tracking is off (Kill stats settings).")
    skins.empty:SetText("Not skinned yet.")
    fillLoot(drops, loot)
    fillLoot(skins, skin)
end
lootView:RegisterEvent("GET_ITEM_INFO_RECEIVED")
lootView:SetScript("OnEvent", function(self)
    if waitingItems and self:IsVisible() then
        waitingItems = nil
        refresh()
    end
end)

local function refreshDetail()
    local name, mob = selected, selected and V.mobs[selected]
    for _, part in ipairs({mobTitle, mobSub, mapBox, zoomHint}) do part:SetShown(name ~= nil) end
    overview:SetShown(name ~= nil and detailTab == "overview")
    lootView:SetShown(name ~= nil and detailTab == "loot")
    for _, tab in ipairs(detailTabs) do
        tab:SetShown(name ~= nil)
        tab:Set(tab.title, tab.page == detailTab)
    end
    empty:SetShown(name == nil)
    if not name then
        for _, f in ipairs(facts) do f.label:SetText(""); f.value:SetText("") end
        fillBreakdown(byLevel, {}, 0)
        fillBreakdown(byGroup, {}, 0)
        byLevel.title:Hide(); byGroup.title:Hide()
        refreshZoneTabs(nil)
        return
    end
    byLevel.title:Show(); byGroup.title:Show()
    local kills, xp, all, low, high, diffs, byKey, groups = 0, 0, 0, nil, nil, {}, {}, {}
    for _, r in pairs(V.kills) do
        if r.name == name then -- XP per group size whatever the filter: it shows how much grouping costs
            local g = groups[r.group or 1] or {group = r.group or 1, count = 0, xp = 0}
            groups[g.group], g.count, g.xp = g, g.count + r.count, g.xp + r.xp
        end
        if wanted(r) then
            all = all + r.count
            if r.name == name then
                kills, xp = kills + r.count, xp + r.xp
                if r.level and r.level > 0 then low, high = math.min(low or r.level, r.level), math.max(high or r.level, r.level) end
                local key = tostring(r.level) .. "|" .. tostring(r.diff) .. "|" .. tostring(r.hidden)
                local d = byKey[key] or {level = r.level, diff = r.diff, hidden = r.hidden, count = 0, xp = 0}
                if not byKey[key] then byKey[key], diffs[#diffs + 1] = d, d end
                d.count, d.xp = d.count + r.count, d.xp + r.xp
            end
        end
    end
    mobTitle:SetText(name)
    local zone = mainZone(name)
    mobSub:SetText("Level " .. levels(low, high) .. (zone and " · " .. zone or ""))

    local f = ns.db.stats.filter
    local lo = mob and (f == "solo" and mob.min or f == "group" and mob.gmin or math.min(mob.min or math.huge, mob.gmin or math.huge))
    local hi = mob and (f == "solo" and mob.max or f == "group" and mob.gmax or math.max(mob.max or -1, mob.gmax or -1))
    local toLevel = high and S.killsToLevel((S.expectedXp(name, high))) -- at its highest level, your group size now
    local list = {
        {"Kills", commas(kills)},
        {"Experience", commas(xp)},
        {"Per kill", commas(each(xp, kills)) .. " xp"},
        {"Range", (lo and lo ~= math.huge) and (commas(lo) .. " - " .. commas(hi) .. " xp") or "-"},
        {"Share of your kills", ("%.1f%%"):format(all > 0 and 100 * kills / all or 0)},
        {"First killed", stamp(mob and mob.first)},
        {"Last killed", stamp(mob and mob.last)},
        toLevel and {"Kills to level", commas(toLevel)} or {"", ""},
    }
    for i, fact in ipairs(facts) do
        fact.label:SetText(list[i][1])
        fact.value:SetText(list[i][2])
    end

    table.sort(diffs, function(a, b)
        local la, lb = (a.level and a.level > 0) and a.level or -math.huge, (b.level and b.level > 0) and b.level or -math.huge
        if la ~= lb then return la > lb end
        return (a.diff or -math.huge) > (b.diff or -math.huge)
    end)
    local items = {}
    for _, d in ipairs(diffs) do
        items[#items + 1] = {count = d.count, label = d.hidden and HIDDEN or ("Level %s  (%s)"):format(
            (d.level and d.level > 0) and d.level or "??", d.diff and signed(d.diff) or "?"), value = ("%d kills · %s xp each"):format(d.count, commas(each(d.xp, d.count)))}
    end
    fillBreakdown(byLevel, items, kills)

    local sizes, every = {}, 0
    for _, g in pairs(groups) do sizes[#sizes + 1] = g; every = every + g.count end
    table.sort(sizes, function(a, b) return a.group < b.group end)
    items = {}
    for _, g in ipairs(sizes) do
        items[#items + 1] = {count = g.count, label = g.group == 1 and "Solo" or "Group of " .. g.group,
            value = commas(each(g.xp, g.count)) .. " xp"}
    end
    fillBreakdown(byGroup, items, every)

    local everyKill = 0 -- the loot view counts every kill of it, whatever the filters (loot isn't split by them)
    for _, r in pairs(V.kills) do
        if r.name == name then everyKill = everyKill + r.count end
    end
    refreshLoot(mob, everyKill)

    refreshZoneTabs(mob)
    if relaying then return end
    if name ~= frame.zoomedMob or shownMap ~= drawnMap then resetZoom() end -- a new mob or zone starts whole
    frame.zoomedMob = name
    drawMap(shownMap, mob and mob.spots or {})
end

-- Graphs -----------------------------------------------------------------------------------------------------------

local graphsView = CreateFrame("Frame", nil, body)
graphsView:SetPoint("TOPLEFT", 0, MAIN_Y)
graphsView:SetPoint("BOTTOMRIGHT")
graphsView:Hide()
-- the charts' size: a quarter of the page each, set by the window's size (layout below)
local CHART_W, CHART_H

local function ChartPane(title, col, row)
    local c = Pane(graphsView)
    function c:Place(w, h)
        self:SetPoint("TOPLEFT", PAD + (col - 1) * (w + GAP), -(row - 1) * (h + GAP))
        self:SetSize(w, h)
        if self.Fit then self:Fit(w, h) end
    end
    c.title = Text(c, "GameFontNormal")
    c.title:SetPoint("TOPLEFT", 12, -12)
    c.title:SetText(title)
    c.note = Text(c, "GameFontDisableSmall")
    c.note:SetPoint("LEFT", c.title, "RIGHT", 8, 0)
    c.empty = Text(c, "GameFontDisable")
    c.empty:SetPoint("CENTER", 0, -8)
    c.empty:SetText("Nothing recorded yet")
    return c
end

-- Horizontal bars: a breakdown row each (St.BarRow), the longest bar the largest; as many as the pane is tall for
-- (8 at the design size), c.n of them
local function HBarChart(title, col, row, color)
    local c = ChartPane(title, col, row)
    c.bars = {}
    function c:Fit(w, h)
        self.n = math.max(1, math.floor((h - 42) / 21))
        for i = 1, math.max(self.n, #self.bars) do
            local b = self.bars[i]
            if not b and i <= self.n then
                b = St.BarRow(self, w - 24, color)
                b:SetPoint("TOPLEFT", 12, -32 - (i - 1) * 21)
                b:Hide()
                self.bars[i] = b
            end
            if i <= self.n then b:Resize(w - 24) else b:Hide() end
        end
    end
    function c:Draw(items) -- {label, size, text}, in the order given
        local max = 0
        for i = 1, math.min(#items, self.n) do max = math.max(max, items[i].size) end
        self.empty:SetShown(#items == 0)
        for i, b in ipairs(self.bars) do
            local item = i <= self.n and items[i]
            b:SetShown(item ~= nil and item ~= false)
            if item then b:Set(item.label, item.text, item.size / math.max(1, max)) end
        end
    end
    return c
end

-- Columns over four grid lines, a label under each; hover one for its numbers
local COLUMNS = 12
local function ColumnChart(title, col, row, color)
    local c = ChartPane(title, col, row)
    local plot = CreateFrame("Frame", nil, c)
    plot:SetPoint("TOPLEFT", 52, -40)
    plot:SetPoint("BOTTOMRIGHT", -14, 28)
    local plotW, plotH
    c.grid, c.gridLabels, c.cols = {}, {}, {}
    for i = 0, 3 do
        local line = plot:CreateTexture(nil, "BACKGROUND", nil, 1)
        line:SetHeight(1)
        line:SetColorTexture(1, 1, 1, i == 0 and 0.25 or 0.08)
        local label = Text(c, "GameFontDisableSmall")
        label:SetPoint("RIGHT", line, "LEFT", -6, 0)
        label:SetJustifyH("RIGHT")
        c.grid[i], c.gridLabels[i] = line, label
    end
    for i = 1, COLUMNS do
        local b = CreateFrame("Button", nil, plot)
        b.share = 0
        b.bar = b:CreateTexture(nil, "ARTWORK")
        b.bar:SetPoint("BOTTOM")
        St.Striped(b.bar, color, true)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)
        b.label = Text(b, "GameFontDisableSmall")
        b.label:SetPoint("TOP", b, "BOTTOM", 0, -4)
        b.label:SetJustifyH("CENTER")
        b:SetScript("OnEnter", function(self) Tooltip(self, self.item.tip, self.item.lines) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        c.cols[i] = b
    end
    function c:Fit(w, h) -- the plot's grid lines and columns at the pane's size
        plotW, plotH = w - 66, h - 68
        for i = 0, 3 do
            self.grid[i]:SetPoint("BOTTOMLEFT", 0, plotH * i / 3)
            self.grid[i]:SetWidth(plotW)
        end
        local slot = plotW / COLUMNS
        for i, b in ipairs(self.cols) do
            b:SetPoint("BOTTOMLEFT", (i - 1) * slot, 0)
            b:SetSize(slot, plotH)
            b.bar:SetWidth(math.min(30, slot - 8))
            b.bar:SetHeight(math.max(1, plotH * b.share))
        end
    end
    function c:Draw(items) -- {label, size, tip, lines}, oldest first
        local max = 0
        for _, item in ipairs(items) do max = math.max(max, item.size) end
        self.empty:SetShown(#items == 0)
        for i = 0, 3 do
            self.grid[i]:SetShown(#items > 0)
            self.gridLabels[i]:SetShown(#items > 0)
            self.gridLabels[i]:SetText(short(math.floor(max * i / 3 + 0.5)))
        end
        for i, b in ipairs(self.cols) do
            local item = items[i]
            b:SetShown(item ~= nil)
            if item then
                b.item = item
                b.label:SetText(item.label)
                b.share = item.size / math.max(1, max)
                b.bar:SetHeight(math.max(1, plotH * b.share))
            end
        end
    end
    return c
end

local charts = {
    mobs = HBarChart("Most killed mobs", 1, 1, {0.25, 0.6, 1}),
    levels = ColumnChart("Kill XP per character level", 2, 1, {1, 0.75, 0.2}),
    hours = ColumnChart("Kill XP per hour", 1, 2, {0.64, 0.21, 0.93}),
    diffs = HBarChart("Kills by mob level vs yours", 2, 2, {0.3, 0.8, 0.35}),
}
frame.charts = charts

local function newest(t, n) -- the n largest keys of t whose bucket has kills under the filters, ascending
    local keys = {}
    for k, v in pairs(t) do
        if filtered(v) > 0 then keys[#keys + 1] = k end
    end
    table.sort(keys)
    local list = {}
    for i = math.max(1, #keys - n + 1), #keys do list[#list + 1] = keys[i] end
    return list
end

local function refreshGraphs()
    local mobs, diffs = {}, {}
    for _, r in pairs(V.kills) do
        if wanted(r) then
            mobs[r.name] = (mobs[r.name] or 0) + r.count
            local d = r.hidden and "hidden" or r.diff or "?"
            diffs[d] = diffs[d] or {count = 0, xp = 0}
            diffs[d].count, diffs[d].xp = diffs[d].count + r.count, diffs[d].xp + r.xp
        end
    end

    local items = {}
    for name, count in pairs(mobs) do items[#items + 1] = {label = name, size = count, text = commas(count) .. " kills"} end
    table.sort(items, function(a, b)
        if a.size ~= b.size then return a.size > b.size end
        return a.label < b.label
    end)
    charts.mobs:Draw(items)

    items = {}
    for _, lvl in ipairs(newest(V.byLevel, COLUMNS)) do
        local count, xp = filtered(V.byLevel[lvl])
        items[#items + 1] = {label = tostring(lvl), size = xp, tip = "Level " .. lvl,
            lines = {commas(xp) .. " xp from kills", commas(count) .. " kills, " .. commas(each(xp, count)) .. " xp each"}}
    end
    charts.levels:Draw(items)

    items = {}
    for _, h in ipairs(newest(V.byHour, COLUMNS)) do
        local count, xp = filtered(V.byHour[h])
        items[#items + 1] = {label = date("%H:00", h * 3600), size = xp, tip = date("%d %b %Y, %H:00", h * 3600),
            lines = {commas(xp) .. " xp from kills", commas(count) .. " kills"}}
    end
    charts.hours.note:SetText("the latest hours with kills")
    charts.hours:Draw(items)

    -- the most killed differences, lowest to highest (unknown last)
    items = {}
    for d, v in pairs(diffs) do
        items[#items + 1] = {d = d, label = d == "?" and "Unknown level" or d == "hidden" and HIDDEN
            or (d == 0 and "Your level" or signed(d)),
            size = v.count, text = ("%s · %s xp each"):format(commas(v.count), commas(each(v.xp, v.count)))}
    end
    table.sort(items, function(a, b) return a.size > b.size end)
    for i = charts.diffs.n + 1, #items do items[i] = nil end
    local function order(d) return d == "?" and math.huge or d == "hidden" and 1e9 or d end
    table.sort(items, function(a, b) return order(a.d) < order(b.d) end)
    charts.diffs:Draw(items)
end

-- Map page ---------------------------------------------------------------------------------------------------------

-- Every kill on the map: the world and its continents show a bubble per zone with your kills there (bigger for
-- more); click one (or a list entry, or the map) to zoom in. A zone shows every kill spot, colored by mob, with the
-- mobs listed beside it. The character and Solo / Group filters apply; the zone filter doesn't (the map picks it).
local BIG_W, BIG_H = 600, 400
local sideN = 15 -- the side list's rows: as many as the pane is tall for (layout below)
local PALETTE = {{1, 0.3, 0.2}, {0.3, 0.6, 1}, {0.3, 0.85, 0.35}, {1, 0.82, 0}, {0.75, 0.4, 1}, {1, 0.55, 0.15},
    {0.3, 0.9, 0.9}, {1, 0.5, 0.75}}
local OTHER = {0.7, 0.7, 0.7}
local mapPage = CreateFrame("Frame", nil, body)
mapPage:SetPoint("TOPLEFT", 0, MAIN_Y)
mapPage:SetPoint("BOTTOMRIGHT")
mapPage:Hide()
local bigBox = Pane(mapPage)
bigBox:SetPoint("TOPLEFT", PAD, 0)
bigBox:SetSize(BIG_W + 8, BIG_H + 8)
local big = St.MapView(bigBox, BIG_W, BIG_H)
big.view:SetPoint("TOPLEFT", 4, -4)
frame.bigMap = big
local bigHint = Text(mapPage, "GameFontDisableSmall")
bigHint:SetPoint("TOPLEFT", bigBox, "BOTTOMLEFT", 2, -6)
bigHint:SetText("Click a zone to zoom in · scroll to zoom · drag to move · right-click to go back out")

local side = Pane(mapPage)
side:SetPoint("TOPLEFT", bigBox, "TOPRIGHT", GAP, 0)
side:SetPoint("BOTTOMRIGHT", -PAD, PAD)
local crumbs = {} -- World > Kalimdor > Feralas: click one to go back to it
frame.crumbs = crumbs
local sideTitle = Text(side, "GameFontNormalLarge")
sideTitle:SetPoint("TOPLEFT", 12, -34)
sideTitle:SetPoint("RIGHT", -12, 0)
local sideNote = Text(side, "GameFontDisableSmall")
sideNote:SetPoint("TOPLEFT", sideTitle, "BOTTOMLEFT", 0, -3)
local sideLine = Line(side)
sideLine:SetPoint("TOPLEFT", 8, -70)
sideLine:SetPoint("TOPRIGHT", -8, -70)
local sideRows = {}
local function SideRow(i)
    local b = CreateFrame("Button", nil, side)
    b:SetPoint("TOPLEFT", 8, -74 - (i - 1) * 22)
    b:SetPoint("RIGHT", -8, 0)
    b:SetHeight(22)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    b.swatch = b:CreateTexture(nil, "ARTWORK")
    b.swatch:SetPoint("LEFT", 4, 0)
    b.swatch:SetSize(10, 10)
    b.nameText = Text(b, "GameFontHighlight")
    b.nameText:SetPoint("LEFT", b.swatch, "RIGHT", 8, 0)
    b.nameText:SetPoint("RIGHT", -60, 0)
    b.count = Text(b, "GameFontHighlight")
    b.count:SetPoint("RIGHT", -4, 0)
    b.count:SetJustifyH("RIGHT")
    b:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
    b:Hide()
    sideRows[i] = b
end
frame.sideRows = sideRows
local sideMore = Text(side, "GameFontDisableSmall")
local function fitSide(n)
    sideN = n
    for i = #sideRows + 1, n do SideRow(i) end
    for i = n + 1, #sideRows do sideRows[i]:Hide() end
    sideMore:SetPoint("TOPLEFT", side, "TOPLEFT", 12, -74 - n * 22 - 4)
end

local shownPlace -- the map shown; nil for the world
local function worldMap() return C_Map.GetFallbackWorldMapID and C_Map.GetFallbackWorldMapID() or 947 end
local function goTo(map)
    shownPlace = map
    big:Reset()
    refresh()
end
local function isZoneLevel(info)
    return info and info.mapType ~= nil and MAP_TYPE.Zone ~= nil and info.mapType >= MAP_TYPE.Zone
end
-- where zone sits on map (0-1), when it's inside it
local function centerOn(zone, map)
    if zone == map or not C_Map.GetMapRectOnMap then return nil end
    local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, zone, map)
    if not ok or not minX or maxX <= minX or maxY <= minY then return nil end
    return (minX + maxX) / 2, (minY + maxY) / 2
end

local function refreshMapPage()
    local map = shownPlace or worldMap()
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    -- kills per zone (and per mob in each) under the character and Solo / Group filters
    local f, zones, mobsIn = ns.db.stats.filter, {}, {}
    for _, r in pairs(V.kills) do
        if type(r.map) == "number" and (f == "all" or (f == "solo") == ((r.group or 1) == 1)) then -- dungeons have no map
            zones[r.map] = (zones[r.map] or 0) + r.count
            mobsIn[r.map] = mobsIn[r.map] or {}
            mobsIn[r.map][r.name] = (mobsIn[r.map][r.name] or 0) + r.count
        end
    end
    local marks, items, total = {}, {}, 0
    if isZoneLevel(info) then
        -- a zone: every spot, colored by mob (the most killed get the palette's colors, the rest grey)
        for name, n in pairs(mobsIn[map] or {}) do items[#items + 1] = {name = name, count = n} end
        table.sort(items, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return a.name < b.name
        end)
        local colors = {}
        for i, item in ipairs(items) do
            item.color = PALETTE[i] or OTHER
            colors[item.name] = item.color
            total = total + item.count
            item.onClick = function() selected, page = item.name, "mobs"; refresh() end
        end
        for name, mob in pairs(V.mobs) do
            for _, spot in ipairs(mob.spots or {}) do
                if spot[1] == map then
                    local c = colors[name] or OTHER
                    marks[#marks + 1] = {x = spot[2], y = spot[3], size = 6, color = {c[1], c[2], c[3], 0.95}}
                end
            end
        end
        sideNote:SetText(("%s kills · %d mobs · click one for its page"):format(commas(total), #items))
    else
        -- the world or a continent: a bubble per zone inside it, sized by its kills
        local most = 0
        for zone, n in pairs(zones) do
            local x, y = centerOn(zone, map)
            if x then items[#items + 1] = {zone = zone, name = mapName(zone), count = n, x = x, y = y} end
            if x and n > most then most = n end
        end
        table.sort(items, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return a.name < b.name
        end)
        for _, item in ipairs(items) do
            total = total + item.count
            item.color = St.GOLD
            item.onClick = function() goTo(item.zone) end
            marks[#marks + 1] = {x = item.x, y = item.y, size = 18 + 22 * math.sqrt(item.count / most),
                color = {1, 0.82, 0, 0.85}, label = short(item.count), onClick = item.onClick,
                tip = {item.name, {commas(item.count) .. " kills", "Click to zoom in"}}}
        end
        sideNote:SetText(("%s kills in %d %s"):format(commas(total), #items, #items == 1 and "zone" or "zones"))
    end
    sideTitle:SetText(info and info.name or "World")
    for i, b in ipairs(sideRows) do
        local item = i <= sideN and items[i]
        b:SetShown(item ~= nil and item ~= false)
        if item then
            b.swatch:SetColorTexture(item.color[1], item.color[2], item.color[3], 1)
            b.nameText:SetText(item.name)
            b.count:SetText(commas(item.count))
            b.onClick = item.onClick
        end
    end
    sideMore:SetText(#items > sideN and ("and %d more"):format(#items - sideN)
        or #items == 0 and "No kills here yet." or "")

    -- the way back up: this map's parents, from the world down
    local path, at = {}, info
    while at do
        table.insert(path, 1, at)
        if at.mapID == worldMap() or not at.parentMapID or at.parentMapID == 0 then break end
        at = C_Map.GetMapInfo(at.parentMapID)
    end
    for i = 1, math.max(#path, #crumbs) do
        local p, tab = path[i], crumbs[i]
        if p and not tab then
            tab = TextTab(side, function(self) goTo(self.map) end)
            if i == 1 then tab:SetPoint("TOPLEFT", 0, -6) else tab:SetPoint("LEFT", crumbs[i - 1], "RIGHT", 0, 0) end
            crumbs[i] = tab
        end
        if p then
            tab.map = p.mapID
            tab:Set((i > 1 and "› " or "") .. p.name, i == #path)
            tab:Show()
        elseif tab then
            tab:Hide()
        end
    end

    big.onClick = function(x, y) -- the world or a continent: zoom into what's under the click
        if isZoneLevel(info) or not C_Map.GetMapInfoAtPosition then return end
        local child = C_Map.GetMapInfoAtPosition(map, x, y)
        if child and child.mapID ~= map then goTo(child.mapID) end
    end
    big.onBack = path[#path - 1] and function() goTo(path[#path - 1].mapID) end or nil
    if not relaying then big:Draw(map, marks, "No map art for this place") end
end

-- Deaths page ------------------------------------------------------------------------------------------------------

-- Every death: the list on the left (newest first), the chosen one on the right with its zone's map (every death
-- there, this one red and bigger) and your deadliest killers. The character, Solo / Group and zone filters apply.
local KIND = {player = "a player", pet = "a player's pet", world = "the world", mob = "a mob"}
local deathsView = CreateFrame("Frame", nil, body)
deathsView:SetPoint("TOPLEFT", 0, MAIN_Y)
deathsView:SetPoint("BOTTOMRIGHT")
deathsView:Hide()
frame.deathsView = deathsView
local deathList = Pane(deathsView)
deathList:SetPoint("TOPLEFT", PAD, 0)
deathList:SetPoint("BOTTOMLEFT", PAD, PAD)
deathList:SetWidth(LIST_W)
local deathTitle = Text(deathList, "GameFontNormal")
deathTitle:SetPoint("TOPLEFT", 12, -12)
deathTitle:SetText("Deaths")
local deathCount = Text(deathList, "GameFontDisableSmall")
deathCount:SetPoint("LEFT", deathTitle, "RIGHT", 8, 0)
local deathLine = Line(deathList)
deathLine:SetPoint("TOPLEFT", 6, -30)
deathLine:SetPoint("TOPRIGHT", -6, -30)
local deathScroll = CreateFrame("ScrollFrame", nil, deathList, "ScrollFrameTemplate")
deathScroll:SetPoint("TOPLEFT", 6, -34)
deathScroll:SetPoint("BOTTOMRIGHT", -26, 6)
local deathRows = CreateFrame("Frame", nil, deathScroll)
deathRows:SetSize(LIST_W - 32, 1)
deathScroll:SetScrollChild(deathRows)
local dRows = {}
frame.deathRows = dRows
local pickedDeath -- the death shown on the right
local pickedKey -- and which it is: its time and character (on All the view's copies are new at each refresh)
local function deathKey(d) return d.t end -- by its time: the popup's death and the All view's copy match

local function killerText(d)
    if not d.killer then return "Unknown" end
    if d.kind == "world" then return d.killer end
    if d.kind == "player" then return "|cffff6060" .. d.killer .. "|r" end
    return d.killer
end
local function deathTitleText(d)
    if not d.killer then return "Died" end
    if d.kind == "world" then return "Died: " .. d.killer end
    return "Killed by " .. killerText(d)
end

local dPane = Pane(deathsView)
dPane:SetPoint("TOPLEFT", deathList, "TOPRIGHT", GAP, 0)
dPane:SetPoint("BOTTOMRIGHT", -PAD, PAD)
local dTitle = Text(dPane, "GameFontNormalLarge")
dTitle:SetPoint("TOPLEFT", 12, -12)
dTitle:SetPoint("RIGHT", -12, 0)
local dSub = Text(dPane, "GameFontDisableSmall")
dSub:SetPoint("TOPLEFT", dTitle, "BOTTOMLEFT", 0, -4)
local dEmpty = Text(dPane, "GameFontDisable")
dEmpty:SetPoint("CENTER")
dEmpty:SetText("No deaths recorded. May it stay that way.")
local dMapBox = Pane(dPane)
dMapBox:SetPoint("TOPLEFT", 12, -50)
dMapBox:SetSize(MAP_W + 8, MAP_H + 8)
local dMap = St.MapView(dMapBox, MAP_W, MAP_H)
dMap.view:SetPoint("TOPLEFT", 4, -4)
frame.deathMap = dMap
local dFacts = St.Facts(dPane, 7, FACTS_X, -54, DETAIL_W - FACTS_X - 12, 1)
frame.deathFacts = dFacts
local topTitle = Text(dPane, "GameFontNormal")
topTitle:SetPoint("TOPLEFT", dMapBox, "BOTTOMLEFT", 0, -12)
topTitle:SetText("Deadliest")
local topLine = Line(dPane)
topLine:SetPoint("TOPLEFT", topTitle, "BOTTOMLEFT", 0, -4)
topLine:SetPoint("RIGHT", -12, 0)
local topRows = {}
for i = 1, 4 do
    topRows[i] = St.BarRow(dPane, DETAIL_W - 24, {1, 0.3, 0.25})
    topRows[i]:SetPoint("TOPLEFT", topLine, "BOTTOMLEFT", 0, -4 - (i - 1) * 22)
end
frame.deadliest = topRows

-- a player who killed you: your note on them (Kureq Utils' character notes), and a button to add or edit it
local noteButton = CreateFrame("Button", nil, dPane, "UIPanelButtonTemplate")
noteButton:SetPoint("BOTTOMRIGHT", -12, 8)
noteButton:SetSize(110, 22)
noteButton:SetScript("OnClick", function(self) if self.name and ns.notes then ns.notes.open(self.name) end end)
frame.deathNoteButton = noteButton
local noteLine = Text(dPane, "GameFontHighlightSmall")
noteLine:SetPoint("LEFT", dPane, "BOTTOMLEFT", 12, 19)
noteLine:SetPoint("RIGHT", noteButton, "LEFT", -10, 0)
frame.deathNoteLine = noteLine

-- Overview (map, facts, deadliest) or Recap (the last hits), switched by text tabs at the top right
local deathTab = "overview"
local deathTabs = {}
for i, t in ipairs({{"Overview", "overview"}, {"Recap", "recap"}}) do
    local tab = TextTab(dPane, function() deathTab = t[2]; refresh() end)
    tab.page, tab.title = t[2], t[1]
    if i == 1 then tab:SetPoint("TOPRIGHT", -80, -8) else tab:SetPoint("LEFT", deathTabs[1], "RIGHT", 0, 0) end
    deathTabs[i] = tab
end
frame.deathTabs = deathTabs
local dRecap = S.RecapPanel(dPane, DETAIL_W - 24, true)
dRecap.frame:SetPoint("TOPLEFT", 12, -46) -- its last hit ends 9 above the note button
frame.deathRecap = dRecap

-- the deaths under the filters, newest first
local function filteredDeaths()
    local f, zone, list = ns.db.stats.filter, ns.db.stats.zone, {}
    for _, d in ipairs(V.deaths or {}) do
        local grouped = (d.group or 1) > 1
        local inZone = zone == 0 or (d.map or -1) == zone
        if inZone and (f == "all" or (f == "group") == grouped) then list[#list + 1] = d end
    end
    table.sort(list, function(a, b) return a.t > b.t end)
    return list
end

local function refreshDeaths()
    local list = filteredDeaths()
    deathCount:SetText(#list == 1 and "1 death" or #list .. " deaths")
    pickedDeath = nil
    for _, d in ipairs(list) do
        if deathKey(d) == pickedKey then pickedDeath = d end
    end
    pickedDeath = pickedDeath or list[1]
    pickedKey = pickedDeath and deathKey(pickedDeath)
    for i, d in ipairs(list) do
        local b = dRows[i] or St.ListRow(deathRows, i, LIST_W - 32, ROW_H, function(self)
            pickedKey = deathKey(self.death)
            refresh()
        end)
        dRows[i] = b
        b.death = d
        b.nameText:SetText(killerText(d))
        b.count:SetText(date("%d %b", d.t))
        local place = d.map and mapName(d.map) or "Unknown place"
        local who = d.char and (" · " .. (d.char:match("^(.-) %- ") or d.char)) or "" -- the character, on All
        b.sub:SetText(("%s · level %s%s"):format(place, d.level or "?", who))
        b.each:SetText(date("%H:%M", d.t))
        b:SetPicked(d == pickedDeath)
        b:Show()
    end
    for i = #list + 1, #dRows do dRows[i]:Hide() end
    deathRows:SetHeight(math.max(1, #list * ROW_H))

    local d = pickedDeath
    local overview = d ~= nil and deathTab == "overview"
    for _, part in ipairs({dTitle, dSub}) do part:SetShown(d ~= nil) end
    for _, part in ipairs({dMapBox, topTitle, topLine}) do part:SetShown(overview) end
    for _, f in ipairs(dFacts) do f.label:SetShown(overview); f.value:SetShown(overview) end
    for _, r in ipairs(topRows) do r:Hide() end
    for _, tab in ipairs(deathTabs) do
        tab:SetShown(d ~= nil)
        tab:Set(tab.title, tab.page == deathTab)
    end
    dRecap.frame:SetShown(d ~= nil and deathTab == "recap")
    if d and deathTab == "recap" then dRecap:Show(d) end
    dEmpty:SetShown(d == nil)
    local playerKiller = d and d.killer and (d.kind == "player" or d.kind == "pet") and ns.notes and ns.IsOn("notes")
    noteButton:SetShown(playerKiller and d.kind == "player" or false)
    noteLine:SetShown(playerKiller and d.kind == "player" or false)
    if playerKiller and d.kind == "player" then -- a pet has no owner in the recap, so no note for it
        local note = ns.notes.get(d.killer)
        noteButton.name = d.killer
        noteButton:SetText(note and "Edit note" or "Add note")
        if note then
            local parts = {ns.notes.stars(note.rating, 11)}
            local tags = ns.notes.tagsText(note)
            if tags ~= "" then parts[#parts + 1] = tags end
            local first = (note.note or ""):match("^[^\n]*")
            if first and first ~= "" then parts[#parts + 1] = first end
            noteLine:SetText("Your note: " .. table.concat(parts, "  "))
        else
            noteLine:SetText("No note on " .. d.killer .. " yet: rate them or note \"kill on sight\".")
        end
    end
    if not d then
        for _, f in ipairs(dFacts) do f.label:SetText(""); f.value:SetText("") end
        return
    end
    dTitle:SetText(deathTitleText(d))
    dSub:SetText(date("%d %b %Y, %H:%M", d.t) .. (d.map and (" · " .. mapName(d.map)) or ""))
    local facts = {
        {"Killer", d.killer and KIND[d.kind or "mob"] or "not known"},
        {"Killing blow", d.spell or (d.killer and d.kind ~= "world" and "melee") or "-"},
        {"Killer level", d.killerLevel and (d.killerLevel > 0 and tostring(d.killerLevel) or "??") or "-"},
        {"Your level", tostring(d.level or "?")},
        {"Group", (d.group or 1) > 1 and ("group of " .. d.group) or "solo"},
        {"Character", d.char or (ns.db.stats.char ~= "all" and ns.db.stats.char) or "-"},
        {"When", date("%d %b %Y, %H:%M", d.t)},
    }
    for i, f in ipairs(dFacts) do f.label:SetText(facts[i][1]); f.value:SetText(facts[i][2]) end
    -- the zone's map: every death there, this one red and bigger
    local marks = {}
    for _, other in ipairs(list) do
        if other.map == d.map and other.x and other ~= d then
            marks[#marks + 1] = {x = other.x, y = other.y, size = 7, color = {0.8, 0.8, 0.8, 0.8}}
        end
    end
    if d.x then marks[#marks + 1] = {x = d.x, y = d.y, size = 12, color = {1, 0.15, 0.1, 1}} end
    if not relaying then
        if d.map ~= frame.deathMapShown then dMap:Reset() end
        frame.deathMapShown = d.map
        dMap:Draw(d.map, marks, d.map and "No map for this zone" or "Where isn't known (inside an instance?)")
    end
    -- who killed you most
    local by = {}
    for _, other in ipairs(list) do
        local who = other.killer and (other.kind == "world" and other.killer or killerText(other)) or "Unknown"
        by[who] = (by[who] or 0) + 1
    end
    local top = {}
    for who, n in pairs(by) do top[#top + 1] = {who = who, n = n} end
    table.sort(top, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.who < b.who
    end)
    for i, r in ipairs(topRows) do
        local item = overview and top[i]
        r:SetShown(item ~= nil and item ~= false)
        if item then r:Set(item.who, item.n == 1 and "1 death" or item.n .. " deaths", item.n / #list) end
    end
end

-- Tiles ------------------------------------------------------------------------------------------------------------

local TILE_LABELS = {kills = {"Kills", "Experience", "Today", "Best hour", "Most killed"},
    deaths = {"Deaths", "By players", "Deadliest", "Deadliest zone", "Last death"}}
local function refreshDeathTiles()
    local list = filteredDeaths()
    local players, by, zones = 0, {}, {}
    for _, d in ipairs(list) do
        if d.kind == "player" or d.kind == "pet" then players = players + 1 end
        local who = d.killer or "Unknown"
        by[who] = (by[who] or 0) + 1
        if d.map then zones[d.map] = (zones[d.map] or 0) + 1 end
    end
    local function most(t)
        local best, n = nil, 0
        for k, c in pairs(t) do
            if c > n or (c == n and tostring(k) < tostring(best)) then best, n = k, c end
        end
        return best, n
    end
    local killer, kn = most(by)
    local zone, zn = most(zones)
    local last = list[1]
    local values = {
        {commas(#list), "none yet"},
        {commas(players), "players and their pets"},
        {killer or "-", killer and (kn == 1 and "1 death" or kn .. " deaths") or ""},
        {zone and mapName(zone) or "-", zone and (zn == 1 and "1 death" or zn .. " deaths") or ""},
        {last and date("%d %b, %H:%M", last.t) or "-", last and deathTitleText(last) or ""},
    }
    local grouped = 0
    for _, d in ipairs(list) do if (d.group or 1) > 1 then grouped = grouped + 1 end end
    if #list > 0 then values[1][2] = grouped == 0 and "all solo" or grouped .. " in groups" end
    for i, t in ipairs(tiles) do
        t.label:SetText(TILE_LABELS.deaths[i])
        t.value:SetText(values[i][1])
        t.sub:SetText(values[i][2])
    end
end
local function refreshTiles()
    if page == "deaths" then return refreshDeathTiles() end
    for i, t in ipairs(tiles) do t.label:SetText(TILE_LABELS.kills[i]) end
    local kills, xp, names, top, topCount = 0, 0, {}, nil, 0
    for _, r in pairs(V.kills) do
        if wanted(r) then
            kills, xp = kills + r.count, xp + r.xp
            names[r.name] = (names[r.name] or 0) + r.count
        end
    end
    local different = 0
    for name, count in pairs(names) do
        different = different + 1
        if count > topCount or (count == topCount and name < top) then top, topCount = name, count end
    end
    local now = date("*t", time())
    local today = math.floor(time({year = now.year, month = now.month, day = now.day, hour = 0}) / 3600)
    local todayKills, todayXp, bestHour, bestXp = 0, 0, nil, 0
    for h, v in pairs(V.byHour) do
        local c, x = filtered(v)
        if h >= today then todayKills, todayXp = todayKills + c, todayXp + x end
        if x > bestXp then bestHour, bestXp = h, x end
    end
    local values = {
        {commas(kills), different == 1 and "1 mob" or commas(different) .. " different mobs"},
        {commas(xp), commas(each(xp, kills)) .. " xp per kill"},
        {commas(todayXp) .. " xp", commas(todayKills) .. " kills"},
        {bestHour and commas(bestXp) .. " xp" or "-", bestHour and date("%d %b, %H:00", bestHour * 3600) or "no kills yet"},
        {top or "-", top and commas(topCount) .. " kills" or ""},
    }
    for i, t in ipairs(tiles) do
        t.value:SetText(values[i][1])
        t.sub:SetText(values[i][2])
    end
end

-- Refresh ----------------------------------------------------------------------------------------------------------

function refresh()
    if not frame:IsShown() then return end
    if not ns.db.killStats[ns.db.stats.char] then ns.db.stats.char = "all" end
    if not (relaying and V) then V = S.view() end
    for _, menu in ipairs({groupMenu, zoneMenu, charMenu}) do menu:Refresh() end
    for _, p in ipairs(plaques) do p:SetOn(p.page == page) end
    mobsView:SetShown(page == "mobs")
    graphsView:SetShown(page == "graphs")
    mapPage:SetShown(page == "map")
    deathsView:SetShown(page == "deaths")
    search:SetShown(page == "mobs")
    zoneMenu:SetShown(page ~= "map") -- on the map page the map picks the zone
    refreshTiles()
    if page == "graphs" then
        refreshGraphs()
    elseif page == "map" then
        refreshMapPage()
    elseif page == "deaths" then
        refreshDeaths()
    else
        local sorted = mobList()
        local known = false
        for _, m in ipairs(sorted) do known = known or m.name == selected end
        if not known then selected = sorted[1] and sorted[1].name end
        refreshList(sorted)
        refreshDetail()
    end
end
S.refresh = refresh
frame:SetScript("OnShow", refresh)

-- Resizing: the panes stretch on their anchors; this re-lays what is sized by the window (the tiles, the detail's
-- columns and bars, the charts, the map page's list) and draws again
St.Resizable(frame, function(w, h)
    BW, BH = St.bodySize(w, h)
    DETAIL_W = BW - 2 * PAD - LIST_W - GAP
    local tileW = math.floor((BW - 2 * PAD - (#TILES - 1) * GAP) / #TILES)
    for i, t in ipairs(tiles) do
        t:SetPoint("TOPLEFT", PAD + (i - 1) * (tileW + GAP), -(PAD + TOP_H + GAP))
        -- the last one takes what rounding left, so the row ends where the panes below do
        t:SetSize(i < #TILES and tileW or BW - 2 * PAD - (#TILES - 1) * (tileW + GAP), TILE_H)
    end
    facts:SetColumnWidth(DETAIL_W - FACTS_X - 12)
    dFacts:SetColumnWidth(DETAIL_W - FACTS_X - 12)
    byGroup:Resize(DETAIL_W - MAP_W - 48)
    lootFacts:SetColumnWidth(math.floor((DETAIL_W - 24 - 16) / 2))
    drops:Place(12, DETAIL_W - 24 - 16 - SKINS_W)
    skins:Place(DETAIL_W - 12 - SKINS_W, SKINS_W)
    for _, r in ipairs(topRows) do r:Resize(DETAIL_W - 24) end
    CHART_W = math.floor((BW - 2 * PAD - GAP) / 2)
    CHART_H = math.floor((BH + MAIN_Y - PAD - GAP) / 2)
    for _, c in pairs(charts) do c:Place(CHART_W, CHART_H) end
    fitSide(math.max(1, math.floor((BH + MAIN_Y - PAD - 94) / 22)))
    if V then -- drawn before: draw again at this size from the same data (refresh skips a hidden window)
        relaying = true
        refresh()
        relaying = false
    end
end)

function S.toggle() frame:SetShown(not frame:IsShown()) end
ns.OnModuleChange("stats", function(on) if not on then frame:Hide() end end)
ns.OnModuleChange("notes", function() if frame:IsShown() then refresh() end end) -- the Deaths page's note button
function S.openDeaths(d) -- the Deaths page, on death d, its recap showing
    page, deathTab = "deaths", "recap"
    if d then pickedKey = deathKey(d) end
    if frame:IsShown() then refresh() else frame:Show() end
end
ns.AddCommand("stats", "/ku stats - opens the kill stats window (/ku stats settings: its settings)", function(rest)
    if rest:lower():match("^settings") then return ns.OpenSettings(S.category) end
    S.toggle()
end, "stats")
SLASH_KUREQSTATS1 = "/kstats" -- Kureq Stats' own command, kept
SlashCmdList.KUREQSTATS = function(msg) SlashCmdList.KUREQUTILS("stats " .. (msg or "")) end
