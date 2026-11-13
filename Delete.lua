-- Delete the cheapest item: a key (Key Bindings > AddOns > Kureq Utils) or /ku delete deletes the
-- bag item with the lowest vendor value among those the settings allow, and reports the value
-- deleted and a running total. Only on a key press or typed command; nothing deletes on its own.
-- While the bags are full, the loot window marks loot worth more than what the key would delete.
local _, ns = ...
ns.AddModule("delete", "Delete items",
    "A key that deletes the cheapest bag item you allow, and marks better loot while your bags are full.")
local fmt, tinsert, tremove, floor = string.format, table.insert, table.remove, math.floor
local say, trim = ns.say, ns.trim

local BUTTON = "KureqUtilsDeleteButton"
local QUEST_ITEM, WEAPON, ARMOR = 12, 2, 4 -- item class IDs
local UNITS = {g = 10000, s = 100, c = 1}

ns.defaults.delete = {maxQuality = 0, keepQuest = true, keepGear = false, unsellable = false, maxValue = 0,
    never = {6948}, always = {}, fullPrompt = true, markLoot = true, confirm = false, -- 6948: Hearthstone
    neverRules = {}, alwaysRules = {}} -- name rules: {kind = "starts"|"ends"|"contains"|"pattern", text = "..."}

-- this client moved these into C_Item / C_CurrencyInfo; the globals are the older fallback
local GetItemInfo = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
local GetCoinTextureString = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString or _G.GetCoinTextureString

-- The never and always lists: item IDs, or names whose item the client hasn't found yet. Older versions saved a
-- typed string, "Hearthstone, 2589" (names, IDs or links); toList reads both forms into a new list.
local LIST_MAX = 40
local function toList(v)
    if type(v) == "table" then return {unpack(v)} end
    local list = {}
    for entry in (v or ""):gmatch("[^,]+") do
        entry = tonumber(entry:match("item:(%d+)") or entry) or trim(entry:match("|h%[(.-)%]|h") or entry)
        if entry ~= "" then list[#list + 1] = entry end
    end
    return list
end

local function idOf(name)
    local _, link = GetItemInfo(name)
    return link and tonumber(link:match("item:(%d+)"))
end

-- the entry stands for this item ID: the ID itself, or the item's name
local function same(entry, id)
    if entry == id then return true end
    local name = type(entry) == "string" and GetItemInfo(id)
    return name and name:lower() == entry:lower() or false
end

local function find(list, id)
    for i, e in ipairs(list) do if same(e, id) then return i end end
end

-- Names become IDs once the client knows the item; duplicates that leaves are dropped.
local function resolveList(list)
    for i = #list, 1, -1 do
        local id = type(list[i]) == "string" and idOf(list[i])
        if id then list[i] = id end
    end
    local seen = {}
    for i = #list, 1, -1 do
        local key = type(list[i]) == "string" and list[i]:lower() or list[i]
        if seen[key] then tremove(list, i) else seen[key] = true end
    end
    return list
end

local db
local function key(e) return type(e) == "string" and e:lower() or e end
-- Resolves both lists; an item left on both (an old save, or two names for one item) stays only on never, which wins.
function ns.resolveLists()
    resolveList(db.never)
    resolveList(db.always)
    for i = #db.always, 1, -1 do
        local a = db.always[i]
        for _, n in ipairs(db.never) do
            if key(a) == key(n) or type(n) == "number" and same(a, n) or type(a) == "number" and same(n, a) then
                tremove(db.always, i)
                break
            end
        end
    end
end

local OTHER = {never = "always", always = "never"}
local LIST_NAME = {never = "Never delete", always = "Allow delete"} -- "always" stays the saved key
-- which: "never" or "always". An item is on one list at most, so adding it takes it off the other.
function ns.addToList(which, id)
    local list, other = db[which], db[OTHER[which]]
    local i = find(list, id)
    if i then
        list[i] = id -- a name entry becomes its ID
    elseif #list >= LIST_MAX then
        return say("the %s list is full (%d items); right-click one to remove it", LIST_NAME[which], LIST_MAX)
    else
        tinsert(list, id)
    end
    i = find(other, id)
    while i do tremove(other, i); i = find(other, id) end
end

-- Name rules ------------------------------------------------------------------------------------

-- Lua only raises a bad pattern's error when matching reaches the bad part, so this walks the pattern the way
-- Lua 5.1's matcher does and says whether any part of it would error.
local function classEnd(p, j) -- the index after the single-char class at j, or nil if it's malformed
    local c = p:sub(j, j)
    if c == "%" then return j + 1 <= #p and j + 2 or nil end
    if c ~= "[" then return j + 1 end
    j = j + 1
    if p:sub(j, j) == "^" then j = j + 1 end
    repeat -- the first char is always part of the set, so "[]]" is a set of "]"
        if j > #p then return nil end
        if p:sub(j, j) == "%" then j = j + 1 end
        j = j + 1
    until p:sub(j, j) == "]"
    return j + 1
end
local MAX_CAPTURES = 32 -- Lua 5.1's LUA_MAXCAPTURES
local function validPattern(p)
    local caps, i = {}, p:sub(1, 1) == "^" and 2 or 1 -- caps[n]: true once capture n is closed
    while i <= #p do
        local c, nx = p:sub(i, i), p:sub(i + 1, i + 1)
        if c == "(" and nx == ")" then caps[#caps + 1], i = true, i + 2
        elseif c == "(" then caps[#caps + 1], i = false, i + 1
        elseif c == ")" then
            local open
            for n = #caps, 1, -1 do if not caps[n] then open = n; break end end
            if not open then return false end
            caps[open], i = true, i + 1
        elseif c == "%" and nx == "b" then
            if i + 3 > #p then return false end
            i = i + 4
        elseif c == "%" and nx == "f" then
            if p:sub(i + 2, i + 2) ~= "[" then return false end
            i = classEnd(p, i + 2)
            if not i then return false end
        elseif c == "%" and nx:match("%d") then
            if not caps[tonumber(nx)] then return false end
            i = i + 2
        else
            i = classEnd(p, i)
            if not i then return false end
            if p:sub(i, i):match("[%*%+%-%?]") then i = i + 1 end
        end
    end
    if #caps > MAX_CAPTURES then return false end
    for _, closed in ipairs(caps) do if not closed then return false end end
    return true
end

-- The text of a bag item's tooltip, lowercased, its lines joined by new lines; nil when it can't be read: in combat
-- (tooltip data may be restricted then), a secret value, an error, or a client without C_TooltipInfo.
local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function tooltipText(bag, slot)
    if not (bag and C_TooltipInfo and C_TooltipInfo.GetBagItem) or InCombatLockdown() then return nil end
    local ok, text = pcall(function()
        local data = C_TooltipInfo.GetBagItem(bag, slot)
        if not data or secret(data) or secret(data.lines) then return nil end
        local lines = {}
        for _, line in ipairs(data.lines or {}) do
            if secret(line.leftText) or secret(line.rightText) then return nil end
            lines[#lines + 1] = (line.leftText or "") .. " " .. (line.rightText or "")
        end
        return table.concat(lines, "\n"):lower()
    end)
    return ok and text or nil
end

-- Starts with, ends with and contains are plain text in any case; a pattern is a Lua pattern on the name as shown;
-- "tooltip" is plain text anywhere in the item's tooltip ("Classes: Mage"), read by tip() (lowercased); when the
-- tooltip can't be read it returns nil (unknown), and the caller decides (a Never rule keeps, an Allow rule doesn't).
-- A pattern shown as invalid never matches (Lua would search some, such as ")", as plain text).
local function ruleMatches(rule, name, tip)
    local text = rule.text
    if rule.kind == "tooltip" then
        local t = tip and tip()
        if t == nil then return nil end
        return t:find(text:lower(), 1, true) ~= nil
    end
    if rule.kind == "pattern" then
        if not validPattern(text) then return false end
        local ok, hit = pcall(string.find, name, text)
        return ok and hit ~= nil
    end
    name, text = name:lower(), text:lower()
    if rule.kind == "starts" then return name:sub(1, #text) == text end
    if rule.kind == "ends" then return #text <= #name and name:sub(-#text) == text end
    return name:find(text, 1, true) ~= nil
end

ns.delete = {validPattern = validPattern, ruleMatches = ruleMatches, tooltipText = tooltipText}

-- tip: the bag slot's tooltip text, read only when a tooltip rule needs it, once
local function slotTip(bag, slot)
    local text, read
    return function()
        if not read then text, read = tooltipText(bag, slot), true end
        return text
    end
end
-- unknown: what a rule whose answer is unknown (an unreadable tooltip) counts as
local function anyRule(rules, name, tip, unknown)
    for _, r in ipairs(rules) do
        local hit = ruleMatches(r, name, tip)
        if hit == nil then hit = unknown end
        if hit then return true end
    end
    return false
end

-- "Name - Realm" with Forever's two-part name joined ("Ku Req - Realm"); UnitName alone gives only the first part
local function playerKey()
    local name = NameUtil and NameUtil.FormatUnitNameForDisplay and NameUtil.FormatUnitNameForDisplay("player")
    if not name or (issecretvalue ~= nil and issecretvalue(name)) then name = UnitName("player") end
    return fmt("%s - %s", name or "?", GetRealmName and GetRealmName() or "?")
end

local function resetStats() db.stats = {value = 0, items = 0, deletions = 0, byChar = {}, byItem = {}} end
tinsert(ns.onLoad, function(root)
    db = root.delete
    db.never, db.always = toList(db.never), toList(db.always)
    db.neverRules, db.alwaysRules = {unpack(db.neverRules)}, {unpack(db.alwaysRules)} -- not the defaults' tables
    ns.resolveLists()
    if type(db.stats) ~= "table" then resetStats() end
    -- once: older versions keyed a character by its first name alone ("Ku - Realm"); move that to the whole name
    local s, key, first = db.stats, playerKey(), UnitName("player")
    local old = first and first .. " - " .. (GetRealmName and GetRealmName() or "?")
    if old and old ~= key and s.byChar[old] then
        s.byChar[key], s.byChar[old] = (s.byChar[key] or 0) + s.byChar[old], nil
    end
    -- items deleted before per-character counts: exact only while one character has deleted anything
    local only = next(s.byChar)
    if only and next(s.byChar, only) == nil then
        for _, e in pairs(s.byItem) do
            e.byChar = e.byChar or {[only] = {count = e.count, value = e.value}}
        end
    end
end)
local session = 0 -- value deleted since login

local C = C_Container
local numSlots = C and C.GetContainerNumSlots or GetContainerNumSlots
local numFree = C and C.GetContainerNumFreeSlots or GetContainerNumFreeSlots
local pickup = C and C.PickupContainerItem or PickupContainerItem

local function slotItem(bag, slot)
    if C and C.GetContainerItemInfo then
        local info = C.GetContainerItemInfo(bag, slot)
        if info then return info.itemID, info.stackCount, info.isLocked, info.hyperlink end
        return
    end
    local _, count, locked, _, _, _, link, _, _, id = GetContainerItemInfo(bag, slot)
    return id, count, locked, link
end

-- The slot's quest info flags quest items and quest starters that item class and binding don't
local function questSlot(bag, slot)
    local q = C and C.GetContainerItemQuestInfo and C.GetContainerItemQuestInfo(bag, slot)
    return q and (q.isQuestItem or q.questID ~= nil)
end

-- a list (or an old saved string) -> set of item IDs and lowercased names
local function itemSet(v)
    local set = {}
    for _, e in ipairs(toList(v)) do set[type(e) == "string" and e:lower() or e] = true end
    return set
end

local function money(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return fmt("%dg %ds %dc", floor(copper / 10000), floor(copper / 100) % 100, copper % 100)
end

-- "1g 20s", "50s", "75c", or a plain number of copper; nil if unreadable
local function parseMoney(text)
    text = trim(text):lower()
    if text == "" then return 0 end
    if text:match("^%d+$") then return tonumber(text) end
    local total = 0
    local rest = text:gsub("(%d+)%s*([gsc])", function(n, unit)
        total = total + tonumber(n) * UNITS[unit]
        return ""
    end)
    if trim(rest) ~= "" then return nil end
    return total
end

local function moneyText(copper)
    if copper == 0 then return "0" end
    local parts = {}
    for u, n in pairs({g = floor(copper / 10000), s = floor(copper / 100) % 100, c = copper % 100}) do
        if n > 0 then parts[#parts + 1] = {u, n} end
    end
    table.sort(parts, function(a, b) return UNITS[a[1]] > UNITS[b[1]] end)
    for i, p in ipairs(parts) do parts[i] = p[2] .. p[1] end
    return table.concat(parts, " ")
end

-- The allowed bag item with the lowest vendor value: {bag, slot, id, count, link, value}.
-- The never list and rules always win; the always list and rules skip the other limits.
local function cheapest()
    local never, always = itemSet(db.never), itemSet(db.always)
    local best
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local _, bagType = numFree(bag)
        for slot = 1, bagType == 0 and numSlots(bag) or 0 do -- normal bags only: no quivers or soul bags
            local id, count, locked, link = slotItem(bag, slot)
            if id and not locked then
                local name, _, quality, _, _, _, _, _, _, _, price, classID, _, bindType = GetItemInfo(id)
                if name then
                    local key = name:lower()
                    price, count = price or 0, count or 1
                    local value = price * count
                    local tip = slotTip(bag, slot)
                    local keep = never[id] or never[key] or anyRule(db.neverRules, name, tip, true)
                    local allowed = not keep and (always[id] or always[key] or anyRule(db.alwaysRules, name, tip, false) or (
                        (quality or 0) <= db.maxQuality
                        and (price > 0 or db.unsellable)
                        and not (db.keepQuest and (classID == QUEST_ITEM or bindType == 4 or questSlot(bag, slot)))
                        and not (db.keepGear and (classID == WEAPON or classID == ARMOR))
                        and (db.maxValue == 0 or value <= db.maxValue)))
                    if allowed and (not best or value < best.value) then
                        best = {bag = bag, slot = slot, id = id, count = count, link = link or name, name = name, value = value}
                    end
                end
            end
        end
    end
    return best
end

-- Statistics are saved for all characters: totals, per character, and per item.
local function record(item)
    local s = db.stats
    s.value, s.items, s.deletions = s.value + item.value, s.items + item.count, s.deletions + 1
    local who = playerKey()
    s.byChar[who] = (s.byChar[who] or 0) + item.value
    local e = s.byItem[item.id] or {value = 0, count = 0, byChar = {}}
    e.link, e.value, e.count = item.link, e.value + item.value, e.count + item.count
    e.byChar = e.byChar or {} -- entries from before per-character counts
    local c = e.byChar[who] or {count = 0, value = 0}
    c.count, c.value = c.count + item.count, c.value + item.value
    e.byChar[who] = c
    s.byItem[item.id] = e
    session = session + item.value
end

local refreshNext, refreshStats
local pending -- with "Press twice to delete": the item the first press named, and when
local function deleteCheapest()
    if not db then return end
    if GetCursorInfo() then return say("put down what's on the cursor first; nothing deleted") end
    local item = cheapest()
    if not item then pending = nil; return say("nothing in your bags is allowed to be deleted (settings: /ku)") end
    if db.confirm then
        local p = pending
        pending = nil
        if not (p and GetTime() - p.t <= 10 and p.bag == item.bag and p.slot == item.slot and p.id == item.id
            and p.count == item.count) then -- a new item, a changed stack or too late: name it again
            item.t, pending = GetTime(), item
            return say("press again to delete %s x%d, worth %s", item.link, item.count, money(item.value))
        end
    end
    pickup(item.bag, item.slot)
    local kind, cursorId = GetCursorInfo()
    if kind ~= "item" or cursorId ~= item.id then -- never delete anything but the item we chose
        ClearCursor()
        return say("couldn't pick up %s; nothing deleted", item.link)
    end
    DeleteCursorItem()
    if GetCursorInfo() then
        ClearCursor()
        return say("WoW didn't delete %s; it's back in your bags", item.link)
    end
    record(item)
    say("deleted %s x%d, worth %s. Deleted so far: %s", item.link, item.count, money(item.value), money(db.stats.value))
    refreshNext()
    refreshStats()
end

-- When looting fails on full bags, say what the delete key would remove (at most every 10 seconds;
-- auto-loot raises the error once per item).
local function deleteHow()
    local key = GetBindingKey("CLICK " .. BUTTON .. ":LeftButton")
    return key and ("press " .. (GetBindingText and GetBindingText(key) or key))
        or "type /ku delete (or bind a key in Key Bindings > AddOns > Kureq Utils)"
end

local lastPrompt = 0
local notes, lootOpen, hinted = {}, false, false -- hinted: this loot window has had its one hint
local function bagsFull()
    if hinted or not (db and db.fullPrompt and ns.IsOn("delete")) or GetTime() - lastPrompt < 10 then return end
    lastPrompt, hinted = GetTime(), lootOpen
    local item = cheapest()
    if not item then return say("bags full, and nothing is allowed to be deleted (rules: /ku)") end
    say("bags full: %s to delete %s x%d, worth %s", deleteHow(), item.link, item.count, money(item.value))
end

-- Loot window --------------------------------------------------------------------------------

-- Which loot slots get a note: those worth more than the item the key would delete, only while no normal
-- bag slot is free. loot is a list of {slot, value}; value is nil for money, currency, quest items and
-- items without a known price. Returns slot -> note text, short enough for one line under the name.
function ns.betterLoot(loot, item, free)
    local notes = {}
    if free > 0 or not item then return notes end
    for _, l in ipairs(loot) do
        if l.value and l.value > item.value then
            notes[l.slot] = fmt("> %s (%s)", item.name, moneyText(item.value))
        end
    end
    return notes
end

local function freeSlots() -- the bags cheapest() scans
    local free = 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local n, bagType = numFree(bag)
        if bagType == 0 then free = free + n end
    end
    return free
end

local LOOT_ITEM = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1
local function lootSlots()
    local loot = {}
    for slot = 1, GetNumLootItems() do
        local _, _, quantity, currencyID, _, _, isQuestItem, questID = GetLootSlotInfo(slot)
        local link = GetLootSlotType(slot) == LOOT_ITEM and not (currencyID or isQuestItem or questID)
            and GetLootSlotLink(slot)
        local price, classID
        if link then price, classID = select(11, GetItemInfo(link)) end
        local value = price and price > 0 and classID ~= QUEST_ITEM and price * (quantity or 1) or nil
        loot[#loot + 1] = {slot = slot, value = value}
    end
    return loot
end

-- Rows are recycled, so every update sets or clears the note. A noted row's name gives up its second line to the
-- note, which sits right under it.
local function noteOn(row, slot)
    local text = slot and notes[slot]
    local note = row.kureqNote
    if not note then
        if not text then return end
        local name = row.Text or _G[row:GetName() .. "Text"] -- scrolling window: parentKey; old LootButtonN: $parentText
        note = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        note:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
        note:SetWidth(name:GetWidth())
        note:SetJustifyH("LEFT")
        note:SetWordWrap(false)
        note:SetTextColor(0.1, 1, 0.1)
        row.kureqNote, row.kureqName, row.kureqNameHeight = note, name, name:GetHeight()
    end
    row.kureqName:SetHeight(text and 14 or row.kureqNameHeight) -- 14: one GameFontNormal line
    note:SetText(text or "")
    note:SetShown(text and true or false)
end

local function eachRow(fn)
    if LootFrame and LootFrame.ScrollBox then
        LootFrame.ScrollBox:ForEachFrame(function(row) fn(row, row:GetSlotIndex()) end)
    else
        for i = 1, LOOTFRAME_NUMBUTTONS or 4 do
            local b = _G["LootButton" .. i]
            if b then fn(b, b:IsShown() and b:IsEnabled() and b.slot) end
        end
    end
end

local function refreshLoot()
    notes = {}
    if lootOpen and db and db.markLoot and ns.IsOn("delete") then
        local free = freeSlots()
        local item = free == 0 and cheapest() or nil
        notes = ns.betterLoot(lootSlots(), item, free)
        if next(notes) and not hinted then
            hinted = true
            say("%s to delete %s x%d (%s) and make room", deleteHow(), item.link, item.count, money(item.value))
        end
    end
    eachRow(noteOn)
end

-- The key binding clicks this button; a key press is the hardware event deleting needs.
BINDING_HEADER_KUREQUTILS = "Kureq Utils"
_G["BINDING_NAME_CLICK " .. BUTTON .. ":LeftButton"] = "Delete the cheapest allowed item"
local button = CreateFrame("Button", BUTTON, UIParent)
button:SetScript("OnClick", ns.whenOn("delete", deleteCheapest))

ns.AddCommand("delete", "/ku delete - delete the cheapest allowed bag item now", deleteCheapest, "delete")

-- Settings page ------------------------------------------------------------------------------

local panel = ns.AddSettingsPage("Delete items",
    "Deletes the bag item with the lowest vendor value among the ones allowed here. Bind a key in Key Bindings "
        .. "> AddOns > Kureq Utils, or type /ku delete. Quivers and soul bags are left alone. While your bags are full, "
        .. "the loot window marks loot worth more than it.", "delete")

local nextLine, totalLine
function refreshNext()
    if not (db and nextLine and panel:IsVisible()) then return end
    local item = cheapest()
    nextLine:SetText(item and fmt("%s x%d, worth %s", item.link, item.count, money(item.value)) or "nothing is allowed")
    totalLine:SetText("Deleted so far: " .. money(db.stats.value) .. " (see Deletion statistics)")
end
local function changed() ns.refresh(panel) end

ns.Header(panel, "Rules")

ns.Dropdown(panel, "Highest quality", "Items above this quality are kept unless they're on the allow delete list.", {
    {value = 0, text = "|cff9d9d9dPoor (gray)|r"},
    {value = 1, text = "|cffffffffCommon (white)|r"},
    {value = 2, text = "|cff1eff00Uncommon (green)|r"},
}, function() return db and db.maxQuality end, function(v) db.maxQuality = v; changed() end)

ns.Checkbox(panel, "Keep quest items", "Never delete quest items.",
    function() return db and db.keepQuest end, function(v) db.keepQuest = v; changed() end)

ns.Checkbox(panel, "Keep weapons and armor", "Never delete weapons or armor.",
    function() return db and db.keepGear end, function(v) db.keepGear = v; changed() end)

ns.Checkbox(panel, "Delete unsellable items",
    "May delete items with no vendor price. Off keeps them, such as keys and quest items.",
    function() return db and db.unsellable end, function(v) db.unsellable = v; changed() end)

ns.Checkbox(panel, "Press twice to delete",
    "The first press says in chat what would be deleted; press again within 10 seconds to delete it.",
    function() return db and db.confirm end, function(v) db.confirm = v; pending = nil end)

ns.EditBox(panel, "Max stack value",
    "The most a deleted stack may be worth at a vendor, e.g. 50s, 1g 20s or 75c (a plain number is copper). "
        .. "0 means no limit.",
    function() return db and moneyText(db.maxValue) end,
    function(text)
        local value = parseMoney(text)
        if not value then return say("couldn't read %s; write it like 50s or 1g 20s", text) end
        db.maxValue = value
        changed()
    end)

ns.Header(panel, "Lists")

local KINDS = {{"starts", "Starts with"}, {"ends", "Ends with"}, {"contains", "Contains"}, {"pattern", "Pattern"},
    {"tooltip", "Tooltip has"}}
local KIND_HELP = "Starts with, Ends with and Contains: plain text, any case. Pattern: a Lua pattern on the name, "
    .. "case-sensitive, e.g. Page %d+$ for names that end in a page number. Tooltip has: plain text anywhere in the "
    .. "item's tooltip, any case, e.g. Classes: Mage."
ns.delete.KINDS, ns.delete.KIND_HELP = KINDS, KIND_HELP -- Mail rules' name rules too
for _, l in ipairs({
    {"never", LIST_NAME.never, "Always kept, whatever the rules say.", "are always kept."},
    {"always", LIST_NAME.always, "May be deleted even above the quality and value limits, when it's the cheapest.",
        "may be deleted even above the quality and value limits."},
}) do
    ns.ItemList(panel, l[2], l[3] .. " An item is on one list at most.",
        function() if db then ns.resolveLists(); return db[l[1]] end end,
        function(id) ns.addToList(l[1], id) end,
        function(i) tremove(db[l[1]], i) end)
    local rules = l[1] .. "Rules"
    ns.RuleList(panel, "Name rules", "Items whose name matches a rule " .. l[4] .. " " .. KIND_HELP, KINDS,
        function() return db and db[rules] end,
        function(kind, text)
            for _, r in ipairs(db[rules]) do if r.kind == kind and r.text == text then return end end
            tinsert(db[rules], {kind = kind, text = text})
        end,
        function(i) tremove(db[rules], i) end,
        function(r) return r.kind == "pattern" and not validPattern(r.text) and "(invalid pattern)" or nil end)
end

ns.Header(panel, "Full bags")

ns.Checkbox(panel, "Say what to delete",
    "When looting fails because your bags are full, say in chat which item the delete key would remove.",
    function() return db and db.fullPrompt end, function(v) db.fullPrompt = v end)

ns.Checkbox(panel, "Mark better loot when bags are full",
    "While no bag slot is free, the loot window marks loot worth more at a vendor than the item the delete key "
        .. "would remove.",
    function() return db and db.markLoot end, function(v) db.markLoot = v; refreshLoot() end)
ns.OnModuleChange("delete", function() refreshLoot() end) -- off clears the marks, on brings them back

ns.Header(panel, "Next to delete")
nextLine = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
nextLine:SetJustifyH("LEFT")
ns.place(panel, nextLine, 22)
totalLine = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
totalLine:SetJustifyH("LEFT")
ns.place(panel, totalLine, 22)
tinsert(panel.refreshers, refreshNext)

-- Statistics page ----------------------------------------------------------------------------

local statsPanel = ns.AddSettingsPage("Deletion statistics",
    "The vendor value of everything the delete key has deleted, saved for all your characters.", "delete")

StaticPopupDialogs.KUREQUTILS_RESET_STATS = {
    text = "Reset all Kureq Utils deletion statistics?",
    button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function() if ns.IsOn("delete") then resetStats(); refreshStats(); refreshNext() end end,
}
ns.OnModuleChange("delete", function(on) if not on then StaticPopup_Hide("KUREQUTILS_RESET_STATS") end end)
ns.Button(statsPanel, "Reset", 100, function() StaticPopup_Show("KUREQUTILS_RESET_STATS") end, "Reset statistics")

-- Tiles, then a search and a character choice over a scrolling table (click a column header to sort by it) of the items deleted. Laid out at a
-- fixed width. shortcut: fixed W fits Blizzard's settings canvas (~600 wide); measure the page if it gets narrower.
local St = ns.style
local W, TILE_H, ROW_H, TABLE_H = 540, 62, 22, 300
local function block(height) -- a frame W wide at the page's next row
    local b = CreateFrame("Frame", nil, statsPanel)
    b:SetSize(W, height)
    ns.place(statsPanel, b, height + 8)
    return b
end

local TILES = {"Total value", "This session", "Items", "Deletions"}
local tiles, tileW = {}, math.floor((W - 3 * 8) / #TILES)
local tileRow = block(TILE_H)
for i, label in ipairs(TILES) do
    local t = St.Pane(tileRow)
    t:SetPoint("TOPLEFT", (i - 1) * (tileW + 8), 0)
    t:SetSize(i < #TILES and tileW or W - (#TILES - 1) * (tileW + 8), TILE_H) -- the last ends at W exactly
    t.label = St.Text(t, "GameFontNormalSmall")
    t.label:SetPoint("TOPLEFT", 10, -8)
    t.label:SetText(label)
    t.value = St.Text(t, "GameFontHighlightLarge")
    t.value:SetPoint("TOPLEFT", t.label, "BOTTOMLEFT", 0, -4)
    t.value:SetPoint("RIGHT", -8, 0)
    t.sub = St.Text(t, "GameFontDisableSmall")
    t.sub:SetPoint("TOPLEFT", t.value, "BOTTOMLEFT", 0, -3)
    t.sub:SetPoint("RIGHT", -8, 0)
    tiles[i] = t
end

local who, sortBy, ascending = nil, "value", false -- who: the character shown, nil for all
local bar = block(28)
local search = CreateFrame("EditBox", nil, bar, "SearchBoxTemplate")
search:SetPoint("LEFT", 6, 0)
search:SetSize(160, 20)
search:SetAutoFocus(false)
search:HookScript("OnTextChanged", function() refreshStats() end)
local charMenu = St.MenuButton(bar, 170, function() return who or "All characters" end, function(root)
    local function radio(text, key)
        root:CreateRadio(text, function() return who == key end, function() who = key; refreshStats() end, key or false)
    end
    radio("All characters", nil)
    local keys = {}
    for k in pairs(db.stats.byChar) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do radio(k, k) end
end)
charMenu:SetPoint("LEFT", search, "RIGHT", 10, 0)
local note = St.Text(statsPanel, "GameFontDisableSmall")
ns.place(statsPanel, note, 18, 37 + 6)
note:SetText("Deletions from before this table count only under All characters.")

local pane = St.Pane(block(TABLE_H))
pane:SetAllPoints()
-- column headers sort the table: a click sorts by that column (names A-Z, numbers highest first), again reverses it
local headers = {}
for _, h in ipairs({{"Item", "name", "TOPLEFT", 12}, {"Count", "count", "TOPRIGHT", -130}, {"Value", "value", "TOPRIGHT", -32}}) do
    local b = CreateFrame("Button", nil, pane)
    b:SetSize(60, 18)
    b.label = St.Text(b, "GameFontNormalSmall")
    b.label:SetText(h[1])
    b.arrow = b:CreateTexture(nil, "ARTWORK")
    b.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    b.arrow:SetSize(9, 8)
    if h[3] == "TOPLEFT" then -- Item: text from the left, arrow after it
        b:SetPoint("TOPLEFT", h[4], -7)
        b.label:SetPoint("LEFT")
        b.arrow:SetPoint("LEFT", b.label, "RIGHT", 3, 0)
    else -- numbers: text right-aligned over the column, arrow before it
        b:SetPoint("TOPRIGHT", h[4], -7)
        b.label:SetPoint("RIGHT")
        b.arrow:SetPoint("RIGHT", b.label, "LEFT", -3, 0)
    end
    b.key = h[2]
    b:SetScript("OnClick", function()
        if sortBy == h[2] then ascending = not ascending else sortBy, ascending = h[2], h[2] == "name" end
        refreshStats()
    end)
    headers[#headers + 1] = b
end
St.Line(pane):SetPoint("TOPLEFT", 6, -26)
St.Line(pane):SetPoint("TOPRIGHT", -6, -26)
local scroll = CreateFrame("ScrollFrame", nil, pane, "ScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 6, -30)
scroll:SetPoint("BOTTOMRIGHT", -26, 6)
local list = CreateFrame("Frame", nil, scroll)
list:SetSize(W - 32, 1)
scroll:SetScrollChild(list)
local empty = St.Text(pane, "GameFontDisable")
empty:SetPoint("CENTER")
empty:SetWidth(W - 80)
empty:SetWordWrap(true)
empty:SetJustifyH("CENTER")
local rows = {}
local function row(i)
    if rows[i] then return rows[i] end
    local b = CreateFrame("Button", nil, list)
    b:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    b:SetSize(W - 32, ROW_H)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("LEFT", 6, 0)
    b.icon:SetSize(16, 16)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.nameText = St.Text(b, "GameFontHighlightSmall")
    b.nameText:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.nameText:SetPoint("RIGHT", -170, 0)
    b.count = St.Text(b, "GameFontHighlightSmall")
    b.count:SetPoint("RIGHT", -106, 0)
    b.count:SetJustifyH("RIGHT")
    b.value = St.Text(b, "GameFontHighlightSmall")
    b.value:SetPoint("RIGHT", -6, 0)
    b.value:SetJustifyH("RIGHT")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. self.id)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = b
    return b
end

-- the item's name from its link ("|cff9d9d9d|Hitem:...|h[Name]|h|r"), in the link's quality color
local function itemName(id, link)
    local name = link and link:match("%[(.-)%]") or GetItemInfo(id) or ("Item " .. id)
    local color = link and link:match("^(|c.-)|H")
    return name, color and (color .. name .. "|r") or name
end

local function shownItems()
    local query, shown = (search:GetText() or ""):lower(), {}
    for id, e in pairs(db.stats.byItem) do
        local name, text = itemName(id, e.link)
        local c = not who and e or e.byChar and e.byChar[who]
        if c and (query == "" or name:lower():find(query, 1, true)) then
            shown[#shown + 1] = {id = id, name = name, text = text, count = c.count, value = c.value}
        end
    end
    table.sort(shown, function(a, b)
        if a[sortBy] ~= b[sortBy] then
            if ascending then return a[sortBy] < b[sortBy] end
            return a[sortBy] > b[sortBy]
        end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return shown
end

function refreshStats()
    if not (db and statsPanel:IsVisible()) then return end
    local s, chars, kinds, old = db.stats, 0, 0, false
    for _ in pairs(s.byChar) do chars = chars + 1 end
    for _, e in pairs(s.byItem) do kinds, old = kinds + 1, old or not e.byChar end
    local facts = {
        {money(s.value), fmt("on %d character%s", chars, chars == 1 and "" or "s")},
        {money(session), "since you logged in"},
        {St.commas(s.items), fmt("%d different", kinds)},
        {St.commas(s.deletions), s.deletions > 0 and ("about " .. money(floor(s.value / s.deletions)) .. " each") or ""},
    }
    for i, t in ipairs(tiles) do t.value:SetText(facts[i][1]); t.sub:SetText(facts[i][2]) end
    charMenu:Refresh()
    for _, h in ipairs(headers) do -- an arrow on the sorted column: down for highest (or A) first, up when reversed
        h.arrow:SetShown(h.key == sortBy)
        if ascending then h.arrow:SetTexCoord(0, 0.5625, 1, 0) else h.arrow:SetTexCoord(0, 0.5625, 0, 1) end
    end
    note:SetShown(who ~= nil and old)
    local shown = shownItems()
    for i, it in ipairs(shown) do
        local b = row(i)
        b.id = it.id
        b.icon:SetTexture(C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(it.id)
            or GetItemIcon and GetItemIcon(it.id) or 134400) -- 134400: the question mark icon
        b.nameText:SetText(it.text)
        b.count:SetText(St.commas(it.count))
        b.value:SetText(money(it.value))
        b:Show()
    end
    for i = #shown + 1, #rows do rows[i]:Hide() end
    list:SetHeight(math.max(1, #shown * ROW_H))
    empty:SetText(s.deletions == 0 and "Nothing deleted yet. Press your delete key to delete the cheapest allowed item."
        or #shown == 0 and "No items match." or "")
end
tinsert(statsPanel.refreshers, refreshStats)

local f = CreateFrame("Frame")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("UI_ERROR_MESSAGE")
f:RegisterEvent("LOOT_OPENED")
f:RegisterEvent("LOOT_CLOSED")
f:RegisterEvent("LOOT_SLOT_CHANGED")
f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
f:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "BAG_UPDATE_DELAYED" then
        if lootOpen then refreshLoot() end
        return refreshNext()
    end
    if event == "LOOT_OPENED" or event == "LOOT_CLOSED" then
        lootOpen, hinted = event == "LOOT_OPENED", false
        return refreshLoot()
    end
    -- an uncached loot item's price arrived (itemID, success), or a slot changed
    if event == "LOOT_SLOT_CHANGED" or event == "GET_ITEM_INFO_RECEIVED" then
        if lootOpen and (event == "LOOT_SLOT_CHANGED" or a2) then refreshLoot() end
        return
    end
    local message = type(a1) == "string" and a1 or a2 -- (errorType, message) here; older clients pass only the message
    if message == ERR_INV_FULL then bagsFull() end
end)

-- New rows pick up the current notes: the scrolling loot window signals each row it fills; the old one updates
-- LootButton1-4 through LootFrame_UpdateButton.
if LootFrame and LootFrame.ScrollBox and ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
    ScrollUtil.AddInitializedFrameCallback(LootFrame.ScrollBox, function(_, row) noteOn(row, row:GetSlotIndex()) end, f)
elseif LootFrame_UpdateButton then
    hooksecurefunc("LootFrame_UpdateButton", function(i)
        local b = _G["LootButton" .. i]
        noteOn(b, b:IsShown() and b:IsEnabled() and b.slot)
    end)
end
