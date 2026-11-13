-- The character notes window (Notes.lua), in Kureq Utils' look (Style.lua): a name box to add someone, stat tiles,
-- the noted characters on the left (search, rating filter, Mine / Guild / All, sort tabs) and the chosen one on the
-- right: your stars and note (tab "Your note"), or the guild's notes on them, read-only ("Guild notes"). Everything
-- saves as you change it.
local _, ns = ...
local N, St = ns.notes, ns.style
local Pane, Text, Line, TextTab = St.Pane, St.Text, St.Line, St.TextTab

local W, H = 900, 600
local BW = St.bodySize(W, H)
local PAD, GAP = 12, 8
local TOP_H, TILE_H = 28, 62
local MAIN_Y = -(PAD + TOP_H + GAP + TILE_H + GAP)
local LIST_W, ROW_H = 320, 34
local EDITOR_W = BW - 2 * PAD - LIST_W - GAP -- the pane right of the list

local frame, body = St.Window("KureqNotesFrame", "Character Notes", W, H)
local selected -- the key of the note shown on the right
-- a note of yours on a player you only have guild notes on, not saved until something is written in it
local draft
local refresh, showEditor

local function stamp(t, long) return t and date(long and "%d %b %Y, %H:%M" or "%d %b", t) or "-" end
local function firstLine(text) return ((text or ""):match("^[^\n]*") or "") end

-- Top bar: search, rating filter, and a name box to add a note ----------------------------------------------------

local search = CreateFrame("EditBox", nil, body, "SearchBoxTemplate")
search:SetPoint("TOPLEFT", PAD + 6, -PAD - 4)
search:SetSize(150, 20)
search:SetAutoFocus(false)
search:HookScript("OnTextChanged", function() refresh() end)
frame.search = search

local ratingFilter = "all" -- "all" every note, 0-5 that rating, -1 no rating, "blocked" the blocked ones
local RATINGS = {{"All ratings", "all"}}
for r = 5, 0, -1 do RATINGS[#RATINGS + 1] = {r == 1 and "1 star" or r .. " stars", r} end
RATINGS[#RATINGS + 1] = {"No rating", -1}
RATINGS[#RATINGS + 1] = {"Blocked", "blocked"}
local function isShownRating(v) return v == ratingFilter end
local function showRating(v) ratingFilter = v; refresh() end
local filterMenu = St.Dropdown(body, 150, function()
    for _, e in ipairs(RATINGS) do if isShownRating(e[2]) then return e[1] end end
end, function(root)
    for _, e in ipairs(RATINGS) do root:CreateRadio(e[1], isShownRating, showRating, e[2]) end
end)
filterMenu:SetPoint("LEFT", search, "RIGHT", 12, 0)
frame.filterMenu = filterMenu

-- Category filter: every category, Any category, or None
local categoryFilter = 0 -- 0 any, -1 none, else a category id
local function isCategory(v) return v == categoryFilter end
local function setCategory(v) categoryFilter = v; refresh() end
local categoryMenu = St.Dropdown(body, 150, function()
    return categoryFilter == 0 and "All categories" or categoryFilter == -1 and "No category"
        or N.categoryText(categoryFilter)
end, function(root)
    root:CreateRadio("All categories", isCategory, setCategory, 0)
    for _, c in ipairs(N.categoryList()) do root:CreateRadio(N.categoryText(c.id), isCategory, setCategory, c.id) end
    root:CreateRadio("No category", isCategory, setCategory, -1)
end)
categoryMenu:SetPoint("LEFT", filterMenu, "RIGHT", 8, 0)
frame.categoryMenu = categoryMenu

-- Whose notes: yours, the guild's (players with a guildmate's note), or both
local SOURCES = {{"All notes", "all"}, {"My notes", "mine"}, {"Guild notes", "guild"}}
local source = "all"
local function isSource(v) return v == source end
local function setSource(v) source = v; refresh() end
local sourceMenu = St.Dropdown(body, 100, function()
    for _, e in ipairs(SOURCES) do if isSource(e[2]) then return e[1] end end
end, function(root)
    for _, e in ipairs(SOURCES) do root:CreateRadio(e[1], isSource, setSource, e[2]) end
end)
sourceMenu:SetPoint("LEFT", categoryMenu, "RIGHT", 8, 0)
frame.sourceMenu = sourceMenu

local addButton = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
addButton:SetPoint("TOPRIGHT", -PAD, -PAD - 3)
addButton:SetSize(90, 22)
addButton:SetText("Add note")
local nameBox = St.EditBox(body)
nameBox:SetPoint("RIGHT", addButton, "LEFT", -10, 0)
nameBox:SetWidth(140)
local namePrompt = Text(nameBox, "GameFontDisable")
namePrompt:SetPoint("LEFT", 2, 0)
namePrompt:SetText("Character name")
nameBox:SetScript("OnEditFocusGained", function() namePrompt:Hide() end)
nameBox:SetScript("OnEditFocusLost", function(self) namePrompt:SetShown((self:GetText() or "") == "") end)
local function addTyped()
    local name = ns.trim(nameBox:GetText())
    if name == "" then return end
    nameBox:SetText("")
    nameBox:ClearFocus()
    namePrompt:Show()
    N.open(name)
end
addButton:SetScript("OnClick", addTyped)
nameBox:SetScript("OnEnterPressed", addTyped)
nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
frame.nameBox, frame.addButton = nameBox, addButton

-- Tiles ------------------------------------------------------------------------------------------------------------

local TILES = {"Characters", "Liked", "Avoid", "Last noted"}
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

-- List -------------------------------------------------------------------------------------------------------------

local listPane = Pane(body)
listPane:SetPoint("TOPLEFT", PAD, MAIN_Y)
listPane:SetPoint("BOTTOMLEFT", PAD, PAD)
listPane:SetWidth(LIST_W)
local listTitle = Text(listPane, "GameFontNormal")
listTitle:SetPoint("TOPLEFT", 12, -12)
listTitle:SetText("Notes")
local listNote = Text(listPane, "GameFontDisableSmall")
listNote:SetPoint("LEFT", listTitle, "RIGHT", 8, 0)

-- Sorting: Name A-Z first, Rating and Updated highest and newest first; the chosen tab again reverses it
local SORT = {
    {"Name", function(e) return e.name:lower() end},
    {"Rating", function(e) return e.rating or -1 end},
    {"Updated", function(e) return e.updated or 0 end},
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
local BLOCKED_MARK = "|TInterface\\Buttons\\UI-GroupLoot-Pass-Up:14:14|t " -- Blizzard's red loot-pass cross

local tab = "mine" -- the detail shows "mine" (your note) or "guild" (the guild's notes)
-- name: a player with only guild notes gets a draft note of yours, saved once something is written in it
local function pick(key, name)
    if key == selected then return end
    local had = key and N.people()[key]
    N.prune(had) -- a note left with neither stars nor text goes
    draft = not had and key and name and {key = key, name = name, note = "", updated = time()} or nil
    selected = key
    tab = had and "mine" or "guild" -- only the guild's notes on them: those first
    refresh()
    showEditor()
end

-- the notes under the search, filters and Mine / Guild / All, sorted. A player with only guild notes stands in with
-- the guild's average for a rating and its newest note's time.
local function noteList()
    local query = (search:GetText() or ""):lower()
    local shown = {}
    local function add(key, e, guild, avg)
        local rated = ratingFilter == "all" or (ratingFilter == -1 and not e.rating) or e.rating == ratingFilter
            or (ratingFilter == "blocked" and e.block)
        local tagged = categoryFilter == 0 or (categoryFilter == -1 and not next(e.tags or {}))
            or (e.tags and e.tags[categoryFilter])
        rated = rated and tagged
        local found = query == "" or e.name:lower():find(query, 1, true) or (e.note or ""):lower():find(query, 1, true)
        for _, g in ipairs(guild) do found = found or (g.note or ""):lower():find(query, 1, true) end
        if rated and found then shown[#shown + 1] = {key = key, entry = e, guild = guild, avg = avg} end
    end
    local yours = {} -- your notes with something in them; an empty one isn't yours yet
    for key, e in pairs(N.people()) do
        local guild, avg = N.guildRating(e.name)
        if not N.isEmpty(e) or #guild == 0 then
            yours[key] = true
            if source ~= "guild" or #guild > 0 then add(key, e, guild, avg) end
        end
    end
    if source ~= "mine" then
        for key, byAuthor in pairs(N.guildStore() or {}) do
            local _, any = next(byAuthor)
            local guild, avg = N.guildRating(any and any.player)
            if not yours[key] and #guild > 0 then
                add(key, {name = guild[1].player, rating = N.round(avg), updated = guild[1].at, guildOnly = true}, guild, avg)
            end
        end
    end
    local sortKey = SORT[sortCol][2]
    table.sort(shown, function(a, b)
        local ka, kb = sortKey(a.entry), sortKey(b.entry)
        if ka ~= kb then
            if sortDesc then return ka > kb end
            return ka < kb
        end
        return a.key < b.key
    end)
    return shown
end

local function refreshList(shown)
    listNote:SetText(#shown == 1 and "1 character" or #shown .. " characters")
    for i, item in ipairs(shown) do
        local b = rows[i] or St.ListRow(list, i, LIST_W - 32, ROW_H, function(self) pick(self.key, self.name) end)
        rows[i] = b
        local e = item.entry
        b.key, b.name = item.key, e.name
        b.nameText:SetText((e.block and BLOCKED_MARK or "") .. N.colored(e))
        b.count:SetText(N.stars(e.rating, 11))
        local line = firstLine(e.note)
        local tags = N.tagsText(e)
        if e.guildOnly then b.sub:SetText(N.guildText(#item.guild, item.avg))
        elseif tags ~= "" and line ~= "" then b.sub:SetText(tags .. "  |cff999999" .. line .. "|r")
        elseif tags == "" and line == "" and #item.guild > 0 then b.sub:SetText(N.guildText(#item.guild, item.avg))
        else b.sub:SetText(tags ~= "" and tags or line ~= "" and line or "No note") end
        b.each:SetText(stamp(e.updated))
        b:SetPicked(item.key == selected)
        b:Show()
    end
    for i = #shown + 1, #rows do rows[i]:Hide() end
    list:SetHeight(math.max(1, #shown * ROW_H))
end

-- Editor -----------------------------------------------------------------------------------------------------------

local editor = Pane(body)
editor:SetPoint("TOPLEFT", listPane, "TOPRIGHT", GAP, 0)
editor:SetPoint("BOTTOMRIGHT", -PAD, PAD)
frame.editor = editor
local who = Text(editor, "GameFontNormalLarge")
who:SetPoint("TOPLEFT", 12, -12)
who:SetPoint("RIGHT", -250, 0)
local when = Text(editor, "GameFontDisableSmall")
when:SetPoint("TOPLEFT", who, "BOTTOMLEFT", 0, -4)
local emptyText = Text(editor, "GameFontDisable")
emptyText:SetPoint("CENTER")
emptyText:SetWidth(360)
emptyText:SetWordWrap(true)
emptyText:SetJustifyH("CENTER")
emptyText:SetText("No notes yet. Right-click a player and choose Add note, type a name above, or use /ku note on your target.")

local ratingLabel = Text(editor, "GameFontNormal")
ratingLabel:SetPoint("TOPLEFT", 12, -62)
ratingLabel:SetText("Rating")
local starButtons = {}
local function entry()
    if not selected then return nil end
    return N.people()[selected] or (draft and draft.key == selected and draft) or nil
end
-- the note to write in: a draft becomes yours here
local function edit()
    local e = entry()
    if e == draft and e then
        N.people()[selected] = e
        e.key, draft = nil, nil
    end
    return e
end
local function setRating(r)
    local e = edit()
    if not e then return end
    e.rating = r
    N.touch(e)
    showEditor()
    refresh()
end
for r = 1, 5 do
    local b = CreateFrame("Button", nil, editor)
    b:SetSize(26, 26)
    b:SetPoint("TOPLEFT", ratingLabel, "BOTTOMLEFT", r * 30, -6)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(N.STAR)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(N.STAR)
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.4)
    b:SetScript("OnClick", function()
        local e = entry()
        if e and e.rating == r then setRating(nil) else setRating(r) end -- the same star again clears it
    end)
    b:SetScript("OnEnter", function(self)
        St.Tooltip(self, r == 1 and "1 star" or r .. " stars", {"Click again to clear the rating."})
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    starButtons[r] = b
end
frame.starButtons = starButtons
-- 0 stars, the lowest rating, left of the stars
local zeroButton = CreateFrame("Button", nil, editor)
zeroButton:SetSize(26, 26)
zeroButton:SetPoint("TOPLEFT", ratingLabel, "BOTTOMLEFT", 0, -6)
zeroButton.text = Text(zeroButton, "GameFontNormalLarge")
zeroButton.text:SetPoint("CENTER")
zeroButton.text:SetText("0")
zeroButton:SetScript("OnClick", function()
    local e = entry()
    if e and e.rating == 0 then setRating(nil) else setRating(0) end
end)
zeroButton:SetScript("OnEnter", function(self)
    St.Tooltip(self, "0 stars", {"Click again to clear the rating."})
end)
zeroButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
frame.zeroButton = zeroButton
local ratingWord = Text(editor, "GameFontHighlight")
ratingWord:SetPoint("LEFT", starButtons[5], "RIGHT", 12, 0)

-- Categories: a chip per category, lit when the character is in it; click to put them in or take them out,
-- right-click to rename, recolor or delete it. "+ New category" and Rename open the name box under the chips.
local CAT_W = EDITOR_W - 24
local cats = CreateFrame("Frame", nil, editor)
cats:SetPoint("TOPLEFT", ratingLabel, "BOTTOMLEFT", 0, -42)
cats:SetSize(CAT_W, 40)
frame.cats = cats
local catLabel = Text(cats, "GameFontNormal")
catLabel:SetPoint("TOPLEFT")
catLabel:SetText("Categories")
local catHint = Text(cats, "GameFontDisableSmall")
catHint:SetPoint("LEFT", catLabel, "RIGHT", 8, 0)
catHint:SetText("click to set, right-click to edit")
local chips = {}
frame.chips = chips

local chipClick -- set below
local function Chip()
    local b = CreateFrame("Button", nil, cats)
    b:SetHeight(20)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.edge = b:CreateTexture(nil, "BORDER")
    b.edge:SetPoint("TOPLEFT")
    b.edge:SetPoint("BOTTOMLEFT")
    b.edge:SetWidth(3)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    b.label = Text(b, "GameFontHighlightSmall")
    b.label:SetPoint("LEFT", 9, 0)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, button) chipClick(self, button) end)
    return b
end

-- the name box: new category (editing.id nil) or renaming one, with its color
local editing -- {id = category id or nil, color = {r, g, b}}
local catEdit = CreateFrame("Frame", nil, cats)
catEdit:SetSize(CAT_W, 24)
catEdit:Hide()
local catName = St.EditBox(catEdit)
catName:SetPoint("LEFT", 6, 0)
catName:SetWidth(170)
catName:SetMaxLetters(30)
local swatch = CreateFrame("Button", nil, catEdit)
swatch:SetPoint("LEFT", catName, "RIGHT", 10, 0)
swatch:SetSize(20, 20)
swatch.border = swatch:CreateTexture(nil, "BACKGROUND")
swatch.border:SetAllPoints()
swatch.border:SetColorTexture(0.8, 0.8, 0.8, 1)
swatch.color = swatch:CreateTexture(nil, "ARTWORK")
swatch.color:SetPoint("TOPLEFT", 1, -1)
swatch.color:SetPoint("BOTTOMRIGHT", -1, 1)
local catSave = CreateFrame("Button", nil, catEdit, "UIPanelButtonTemplate")
catSave:SetPoint("LEFT", swatch, "RIGHT", 10, 0)
catSave:SetSize(64, 22)
catSave:SetText("Save")
local catCancel = CreateFrame("Button", nil, catEdit, "UIPanelButtonTemplate")
catCancel:SetPoint("LEFT", catSave, "RIGHT", 4, 0)
catCancel:SetSize(64, 22)
catCancel:SetText("Cancel")
frame.catName, frame.catSave, frame.swatch = catName, catSave, swatch
local layoutCategories

local function pickColor(color, apply)
    local old = {color[1], color[2], color[3]}
    ColorPickerFrame:SetupColorPickerAndShow({r = old[1], g = old[2], b = old[3],
        swatchFunc = function() apply({ColorPickerFrame:GetColorRGB()}) end,
        cancelFunc = function() apply(old) end})
end
local function startEdit(id)
    local c = id and ns.db.notes.categories[id]
    editing = {id = id, color = c and {c.color[1], c.color[2], c.color[3]} or {0.4, 0.7, 1}}
    catName:SetText(c and c.name or "")
    swatch.color:SetColorTexture(editing.color[1], editing.color[2], editing.color[3])
    layoutCategories()
    catName:SetFocus()
end
local function stopEdit()
    editing = nil
    catName:ClearFocus()
    layoutCategories()
end
swatch:SetScript("OnClick", function()
    pickColor(editing.color, function(c)
        editing.color = c
        swatch.color:SetColorTexture(c[1], c[2], c[3])
    end)
end)
local function saveEdit()
    local name = ns.trim(catName:GetText()):gsub("%s+", " ")
    if name == "" then return end
    if editing.id then
        local c = ns.db.notes.categories[editing.id]
        c.name, c.color = name, editing.color
        N.changed()
    else
        local id = N.addCategory(name, editing.color)
        local e = edit()
        if e then -- a new category goes on the character it was made for
            e.tags = e.tags or {}
            e.tags[id] = true
            N.touch(e)
        end
    end
    stopEdit()
    refresh()
end
catSave:SetScript("OnClick", saveEdit)
catName:SetScript("OnEnterPressed", saveEdit)
catName:SetScript("OnEscapePressed", stopEdit)
catCancel:SetScript("OnClick", stopEdit)

local deletingCategory
StaticPopupDialogs.KUREQUTILS_DELETE_CATEGORY = {
    text = "Delete the category %s? It comes off %s.", button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function()
        if not (deletingCategory and ns.IsOn("notes")) then return end
        N.deleteCategory(deletingCategory)
        deletingCategory = nil
        refresh()
        layoutCategories()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
local function categoryMenuFor(chip)
    local id = chip.id
    MenuUtil.CreateContextMenu(chip, function(_, root)
        root:CreateTitle(N.categoryText(id))
        root:CreateButton("Rename", function() startEdit(id) end)
        root:CreateButton("Change color", function()
            local c = ns.db.notes.categories[id]
            pickColor(c.color, function(color)
                c.color = color
                N.changed()
                refresh()
                layoutCategories()
            end)
        end)
        root:CreateButton("Delete", function()
            deletingCategory = id
            local n = N.inCategory(id)
            StaticPopup_Show("KUREQUTILS_DELETE_CATEGORY", ns.db.notes.categories[id].name,
                n == 1 and "1 character" or n .. " characters")
        end)
    end)
end

-- Lays the chips out in rows across the block, then the name box, and sizes the block to fit
function layoutCategories()
    local e = entry()
    local list = N.categoryList()
    local x, y = 0, -22
    local function place(b, w)
        if x > 0 and x + w > CAT_W then x, y = 0, y - 24 end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", x, y)
        b:SetWidth(w)
        x = x + w + 6
    end
    for i = 1, #list + 1 do
        local b = chips[i] or Chip()
        chips[i] = b
        local c = list[i]
        if c then
            local on = e and e.tags and e.tags[c.id]
            b.id, b.isNew = c.id, nil
            b.label:SetText(c.name)
            b.on = on and true or false
            b.bg:SetColorTexture(c.color[1], c.color[2], c.color[3], on and 0.45 or 0.08)
            b.edge:SetColorTexture(c.color[1], c.color[2], c.color[3], 1)
            if on then b.label:SetTextColor(1, 1, 1) else b.label:SetTextColor(c.color[1], c.color[2], c.color[3]) end
        else -- the last chip makes a new one
            b.id, b.isNew, b.on = nil, true, false
            b.label:SetText("+ New category")
            b.label:SetTextColor(0.7, 0.7, 0.7)
            b.bg:SetColorTexture(1, 1, 1, 0.05)
            b.edge:SetColorTexture(0.5, 0.5, 0.5, 1)
        end
        place(b, math.ceil(b.label:GetStringWidth()) + 18)
        b:Show()
    end
    for i = #list + 2, #chips do chips[i]:Hide() end
    catEdit:SetShown(editing ~= nil)
    if editing then
        x, y = 0, y - 26
        catEdit:ClearAllPoints()
        catEdit:SetPoint("TOPLEFT", 0, y + 2)
    end
    cats:SetHeight(-y + 22)
end

function chipClick(b, button)
    if b.isNew then return startEdit(nil) end
    if button == "RightButton" then return categoryMenuFor(b) end
    local e = edit()
    if not e then return end
    e.tags = e.tags or {}
    e.tags[b.id] = (not e.tags[b.id]) or nil
    N.touch(e)
    layoutCategories()
    refresh()
end

-- Dungeons played together: a line per dungeon in two columns, newest first ("The Deadmines ×3, last 2026-11-10"),
-- right-click one to remove it; Add dungeon adds a run of one by hand. Three rows show, the rest scroll.
local DUNGEON_ROW, DUNGEON_ROWS = 16, 3
local dungeonW = math.floor((CAT_W - 26) / 2)
local dungeons = CreateFrame("Frame", nil, editor)
dungeons:SetPoint("TOPLEFT", cats, "BOTTOMLEFT", 0, -6)
dungeons:SetSize(CAT_W, 22 + DUNGEON_ROW)
frame.dungeons = dungeons
local dungeonLabel = Text(dungeons, "GameFontNormal")
dungeonLabel:SetPoint("TOPLEFT", 0, -4)
dungeonLabel:SetText("Dungeons")
local dungeonHint = Text(dungeons, "GameFontDisableSmall")
dungeonHint:SetPoint("LEFT", dungeonLabel, "RIGHT", 8, 0)
dungeonHint:SetText("right-click one to remove it")
local dungeonEmpty = Text(dungeons, "GameFontDisableSmall")
dungeonEmpty:SetPoint("TOPLEFT", 0, -26)
dungeonEmpty:SetText("No dungeons yet. They're added when you enter one together.")
frame.dungeonEmpty = dungeonEmpty
local dungeonScroll = CreateFrame("ScrollFrame", nil, dungeons, "ScrollFrameTemplate")
dungeonScroll:SetPoint("TOPLEFT", 0, -24)
dungeonScroll:SetPoint("BOTTOMRIGHT", -20, 0)
-- the bar only while there are more rows than show; else its arrows sit under Add dungeon
if type(dungeonScroll.ScrollBar) == "table" and dungeonScroll.ScrollBar.SetHideIfUnscrollable then
    dungeonScroll.ScrollBar:SetHideIfUnscrollable(true)
end
local dungeonList = CreateFrame("Frame", nil, dungeonScroll)
dungeonList:SetSize(CAT_W - 26, 1)
dungeonScroll:SetScrollChild(dungeonList)
local dungeonLines = {}
frame.dungeonLines = dungeonLines
local layoutDungeons

local addDungeon = St.MenuButton(dungeons, 110, function() return "Add dungeon" end, function(root)
    root:CreateTitle("Played together")
    for _, d in ipairs(N.DUNGEONS) do
        root:CreateButton(d[2], function()
            local e = edit()
            if not e then return end
            N.addDungeon(e, d[2])
            N.touch(e)
            layoutDungeons()
            refresh()
        end)
    end
end)
addDungeon:SetPoint("TOPRIGHT", 0, 0)
addDungeon:Refresh()
frame.addDungeon = addDungeon

local removing -- {key, dungeon} the dialog asks about
StaticPopupDialogs.KUREQUTILS_REMOVE_DUNGEON = {
    text = "Remove %s from your note on %s?", button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function()
        local e = removing and ns.IsOn("notes") and N.people()[removing[1]]
        if not e then return end
        N.removeDungeon(e, removing[2])
        N.touch(e)
        removing = nil
        layoutDungeons()
        refresh()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
local function dungeonMenu(line)
    MenuUtil.CreateContextMenu(line, function(_, root)
        root:CreateTitle(line.dungeon)
        root:CreateButton("Remove", function()
            local e = entry()
            if not e then return end
            removing = {selected, line.dungeon}
            StaticPopup_Show("KUREQUTILS_REMOVE_DUNGEON", line.dungeon, e.name)
        end)
    end)
end

function layoutDungeons()
    local e = entry()
    local list = e and N.dungeonList(e) or {}
    for i, d in ipairs(list) do
        local b = dungeonLines[i]
        if not b then
            b = CreateFrame("Button", nil, dungeonList)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.08)
            b.text = Text(b, "GameFontHighlightSmall")
            b.text:SetPoint("LEFT", 2, 0)
            b.text:SetPoint("RIGHT", -2, 0)
            b:RegisterForClicks("RightButtonUp")
            b:SetScript("OnClick", function(self) dungeonMenu(self) end)
            dungeonLines[i] = b
        end
        b:SetSize(dungeonW, DUNGEON_ROW)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", ((i - 1) % 2) * (dungeonW + 6), -math.floor((i - 1) / 2) * DUNGEON_ROW)
        b.dungeon = d.name
        b.text:SetText(("%s |cff999999×%d, last %s|r"):format(d.name, d.runs, date("%Y-%m-%d", d.last)))
        b:Show()
    end
    for i = #list + 1, #dungeonLines do dungeonLines[i]:Hide() end
    local rows = math.ceil(#list / 2)
    dungeonList:SetHeight(math.max(1, rows * DUNGEON_ROW))
    dungeonEmpty:SetShown(#list == 0)
    dungeonHint:SetShown(#list > 0)
    dungeonScroll:SetShown(#list > 0)
    dungeons:SetHeight(24 + math.max(1, math.min(rows, DUNGEON_ROWS)) * DUNGEON_ROW)
end

local noteLabel = Text(editor, "GameFontNormal")
noteLabel:SetPoint("TOPLEFT", dungeons, "BOTTOMLEFT", 0, -8)
noteLabel:SetText("Note")
local noteHint = Text(editor, "GameFontDisableSmall")
noteHint:SetPoint("LEFT", noteLabel, "RIGHT", 8, 0)
noteHint:SetText("shown on their tooltip; saves as you type")
local noteBox = Pane(editor)
noteBox:SetPoint("TOPLEFT", noteLabel, "BOTTOMLEFT", -4, -6)
noteBox:SetPoint("BOTTOMRIGHT", -12, 44)
local noteScroll = CreateFrame("ScrollFrame", nil, noteBox, "ScrollFrameTemplate")
noteScroll:SetPoint("TOPLEFT", 8, -8)
noteScroll:SetPoint("BOTTOMRIGHT", -26, 8)
local noteEdit = CreateFrame("EditBox", nil, noteScroll)
noteEdit:SetMultiLine(true)
noteEdit:SetAutoFocus(false)
noteEdit:SetFontObject("ChatFontNormal")
noteEdit:SetMaxLetters(1000)
noteEdit:SetWidth(EDITOR_W - 60)
noteScroll:SetScrollChild(noteEdit)
noteEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
noteEdit:SetScript("OnTextChanged", function(self, userInput)
    if not userInput then return end
    local e = edit()
    if not e then return end
    e.note = self:GetText()
    N.touch(e)
    refresh()
end)
-- Private: kept out of the guild's notes (shown while sharing is on)
local privateBox = St.Checkbox(editor)
privateBox:SetPoint("LEFT", noteHint, "RIGHT", 12, 0)
privateBox.Text:SetText("Private")
privateBox.Text:SetFontObject("GameFontHighlight")
privateBox:SetScript("OnClick", function(self)
    local e = edit()
    if not e then return end
    e.private = self:GetChecked() and true or nil
    N.touch(e)
end)
privateBox:SetScript("OnEnter", function(self)
    St.Tooltip(self, "Private", {"Keeps this note to yourself: it isn't shared with your guild."})
end)
privateBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
frame.privateBox = privateBox
noteBox:EnableMouse(true)
noteBox:SetScript("OnMouseDown", function() noteEdit:SetFocus() end) -- a click anywhere in the box writes
frame.noteEdit = noteEdit

local deleteButton = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
deleteButton:SetPoint("BOTTOMRIGHT", -12, 12)
deleteButton:SetSize(110, 22)
deleteButton:SetText("Delete note")
local deleting -- the key the dialog asks about
StaticPopupDialogs.KUREQUTILS_DELETE_NOTE = {
    text = "Delete your note on %s?", button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function()
        if not (deleting and ns.IsOn("notes")) then return end
        N.people()[deleting] = nil
        N.changed()
        if selected == deleting then selected = nil end
        deleting = nil
        refresh()
        showEditor()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
deleteButton:SetScript("OnClick", function()
    local e = selected and N.people()[selected]
    if not e then return end
    deleting = selected
    StaticPopup_Show("KUREQUTILS_DELETE_NOTE", e.name)
end)
frame.deleteButton = deleteButton

-- Block: a checkbox per kind in a row along the bottom
local blockLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
blockLabel:SetPoint("BOTTOMLEFT", 12, 17)
blockLabel:SetText("Block")
local BLOCK_TIPS = {
    group = "Declines their group invites.",
    guild = "Declines their guild invites.",
    trade = "Declines their trade requests and closes trades they open.",
    duel = "Declines their duels.",
}
local blockBoxes, lastBlock = {}, nil
for _, b in ipairs(N.BLOCKS) do
    local kind, label = b[1], b[2]
    local box = St.Checkbox(editor)
    if lastBlock then
        box:SetPoint("LEFT", lastBlock.Text, "RIGHT", 8, 0)
    else
        box:SetPoint("LEFT", blockLabel, "RIGHT", 4, 0)
    end
    box.Text:SetText(label)
    box.Text:SetFontObject("GameFontHighlight")
    box:SetScript("OnClick", function(self)
        local e = entry()
        if e then N.setBlocked(e.name, kind, self:GetChecked() and true or false) end
    end)
    box:SetScript("OnEnter", function(self) St.Tooltip(self, label, {BLOCK_TIPS[kind]}) end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    blockBoxes[kind], lastBlock = box, box
end
frame.blockBoxes = blockBoxes

-- Your note / Guild notes: tabs at the top right of the detail; your note comes first
local tabs = {}
tabs.guild = TextTab(editor, function() tab = "guild"; showEditor() end)
tabs.guild:SetPoint("TOPRIGHT", -6, -8)
tabs.mine = TextTab(editor, function() tab = "mine"; showEditor() end)
tabs.mine:SetPoint("RIGHT", tabs.guild, "LEFT", 0, 0)
frame.tabs = tabs

-- The guild's notes on the chosen player, read-only, newest first: the author and their stars, the date (and "passed
-- along" when it didn't come from its author), the author's categories in their colors, then the note.
local GUILD_W = EDITOR_W - 60
local guildScroll = CreateFrame("ScrollFrame", nil, editor, "ScrollFrameTemplate")
guildScroll:SetPoint("TOPLEFT", 12, -62)
guildScroll:SetPoint("BOTTOMRIGHT", -32, 12)
local guildList = CreateFrame("Frame", nil, guildScroll)
guildList:SetSize(GUILD_W, 1)
guildScroll:SetScrollChild(guildList)
local guildEmpty = Text(editor, "GameFontDisable")
guildEmpty:SetPoint("CENTER")
guildEmpty:SetWidth(360)
guildEmpty:SetWordWrap(true)
guildEmpty:SetJustifyH("CENTER")
local guildRows = {}
frame.guildRows, frame.guildEmpty = guildRows, guildEmpty
local function guildRow(i)
    local r = guildRows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, guildList)
    r:SetWidth(GUILD_W)
    r.head = Text(r, "GameFontHighlight")
    r.head:SetPoint("TOPLEFT", 0, 0)
    r.date = Text(r, "GameFontDisableSmall")
    r.date:SetPoint("TOPRIGHT", 0, -1)
    r.cats = Text(r, "GameFontHighlightSmall")
    r.cats:SetPoint("TOPLEFT", r.head, "BOTTOMLEFT", 0, -4)
    r.cats:SetWidth(GUILD_W)
    r.cats:SetJustifyH("LEFT")
    r.note = Text(r, "GameFontHighlightSmall")
    r.note:SetWidth(GUILD_W)
    r.note:SetJustifyH("LEFT")
    r.note:SetWordWrap(true)
    r.line = Line(r)
    r.line:SetPoint("BOTTOMLEFT", 0, 0)
    r.line:SetPoint("BOTTOMRIGHT", 0, 0)
    guildRows[i] = r
    return r
end
local function layoutGuild(name)
    local list = N.guildNotes(name)
    local y = 0
    for i, g in ipairs(list) do
        local r = guildRow(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -y)
        r.head:SetText(g.author .. (g.rating and "  " .. N.stars(g.rating, 12) .. " " .. N.WORDS[g.rating] or ""))
        r.date:SetText(stamp(g.at, true) .. (g.relay and " · passed along" or ""))
        local tags = N.guildTagsText(g)
        r.cats:SetText(tags)
        r.note:ClearAllPoints()
        r.note:SetPoint("TOPLEFT", tags ~= "" and r.cats or r.head, "BOTTOMLEFT", 0, -4)
        r.note:SetText(g.note or "")
        local h = 16 + (tags ~= "" and 16 or 0) + math.ceil(r.note:GetStringHeight()) + 12
        r:SetHeight(h)
        r:Show()
        y = y + h + 8
    end
    for i = #list + 1, #guildRows do guildRows[i]:Hide() end
    guildList:SetHeight(math.max(1, y))
    guildEmpty:SetText(ns.db.notes.share and "No guild notes on " .. name .. " yet."
        or "No guild notes on " .. name .. ". Turn on Share guild notes in the settings to share notes with your guild.")
    guildEmpty:SetShown(#list == 0)
    return #list
end

function showEditor()
    local e = entry()
    local count = e and #N.guildNotes(e.name) or 0
    local mine = e ~= nil and tab == "mine"
    for _, part in ipairs({ratingLabel, ratingWord, cats, dungeons, noteLabel, noteHint, noteBox, deleteButton, blockLabel}) do
        part:SetShown(mine)
    end
    who:SetShown(e ~= nil)
    when:SetShown(e ~= nil)
    for _, b in ipairs(starButtons) do b:SetShown(mine) end
    zeroButton:SetShown(mine)
    for _, b in pairs(blockBoxes) do b:SetShown(mine) end
    privateBox:SetShown(mine and ns.db.notes.share == true)
    tabs.mine:SetShown(e ~= nil)
    tabs.guild:SetShown(e ~= nil)
    guildScroll:SetShown(e ~= nil and not mine)
    guildEmpty:SetShown(false)
    emptyText:SetShown(e == nil)
    if not e then return end
    tabs.mine:Set("Your note", mine)
    tabs.guild:Set(count > 0 and "Guild notes (" .. count .. ")" or "Guild notes", not mine)
    who:SetText(N.colored(e))
    if not mine then
        local _, avg = N.guildRating(e.name)
        when:SetText(count > 0 and N.guildText(count, avg) or "No guild notes")
        layoutGuild(e.name)
        return
    end
    privateBox:SetChecked(e.private == true)
    when:SetText("Updated " .. stamp(e.updated, true))
    for r, b in ipairs(starButtons) do
        local on = e.rating and r <= e.rating
        b.icon:SetDesaturated(not on)
        b.icon:SetAlpha(on and 1 or 0.35)
    end
    if e.rating == 0 then zeroButton.text:SetTextColor(unpack(N.COLORS[0])) else zeroButton.text:SetTextColor(0.5, 0.5, 0.5) end
    ratingWord:SetText(e.rating and N.WORDS[e.rating] or "No rating")
    if e.rating then
        local c = N.COLORS[e.rating]
        ratingWord:SetTextColor(c[1], c[2], c[3])
    else
        ratingWord:SetTextColor(0.6, 0.6, 0.6)
    end
    for kind, b in pairs(blockBoxes) do b:SetChecked(N.blocked(e.name, kind)) end
    if noteEdit:GetText() ~= (e.note or "") then noteEdit:SetText(e.note or "") end
    layoutCategories()
    layoutDungeons()
end

-- Refresh ----------------------------------------------------------------------------------------------------------

local function refreshTiles()
    local count, liked, avoid, last = 0, 0, 0, nil
    for _, e in pairs(N.people()) do
        count = count + 1
        if e.rating and e.rating >= 4 then liked = liked + 1 end
        if e.rating and e.rating <= 2 then avoid = avoid + 1 end
        if not last or (e.updated or 0) > (last.updated or 0) then last = e end
    end
    local values = {
        {St.commas(count), count == 1 and "character noted" or "characters noted"},
        {St.commas(liked), "rated 4 or 5 stars"},
        {St.commas(avoid), "rated 0 to 2 stars"},
        {last and N.colored(last) or "-", last and stamp(last.updated, true) or "nothing yet"},
    }
    for i, t in ipairs(tiles) do
        t.value:SetText(values[i][1])
        t.sub:SetText(values[i][2])
    end
end

function refresh()
    if not frame:IsShown() then return end
    if not ns.db.notes.categories[categoryFilter] and categoryFilter > 0 then categoryFilter = 0 end
    filterMenu:Refresh()
    categoryMenu:Refresh()
    sourceMenu:Refresh()
    refreshTiles()
    refreshList(noteList())
end

frame:SetScript("OnShow", function()
    refresh()
    showEditor()
end)
frame:SetScript("OnHide", function() N.prune() end)

-- Opens the window, on name's note when given (made if there's none yet)
N.open = ns.whenOn("notes", function(name)
    if name then
        local e = N.ensure(name)
        selected = N.key(e.name)
        tab = "mine"
        search:SetText("") -- so it shows in the list
        ratingFilter = "all"
    end
    if frame:IsShown() then
        refresh()
        showEditor()
    else
        frame:Show() -- OnShow fills it
    end
    if name then noteEdit:SetFocus() end
end)
N.toggle = ns.whenOn("notes", function()
    if frame:IsShown() then frame:Hide() else N.open() end
end)
N.frame = frame

-- Resizing: the list and the editor stretch on their anchors; this re-lays the tiles and what is as wide as the
-- editor (categories, dungeons, the note, the guild's notes), then lays the shown note out again
St.Resizable(frame, function(w)
    local BW = St.bodySize(w, H)
    local tileW = math.floor((BW - 2 * PAD - (#TILES - 1) * GAP) / #TILES)
    for i, t in ipairs(tiles) do
        t:SetPoint("TOPLEFT", PAD + (i - 1) * (tileW + GAP), -(PAD + TOP_H + GAP))
        -- the last one takes what rounding left, so the row ends where the panes below do
        t:SetSize(i < #TILES and tileW or BW - 2 * PAD - (#TILES - 1) * (tileW + GAP), TILE_H)
    end
    EDITOR_W = BW - 2 * PAD - LIST_W - GAP
    CAT_W, GUILD_W = EDITOR_W - 24, EDITOR_W - 60
    dungeonW = math.floor((CAT_W - 26) / 2)
    for _, part in ipairs({cats, catEdit, dungeons}) do part:SetWidth(CAT_W) end
    dungeonList:SetWidth(CAT_W - 26)
    noteEdit:SetWidth(EDITOR_W - 60)
    guildList:SetWidth(GUILD_W)
    for _, r in ipairs(guildRows) do
        r:SetWidth(GUILD_W)
        r.cats:SetWidth(GUILD_W)
        r.note:SetWidth(GUILD_W)
    end
    if frame:IsShown() then showEditor() end
end)
ns.OnModuleChange("notes", function(on)
    if on then return end
    frame:Hide()
    StaticPopup_Hide("KUREQUTILS_DELETE_NOTE")
    StaticPopup_Hide("KUREQUTILS_DELETE_CATEGORY")
    StaticPopup_Hide("KUREQUTILS_REMOVE_DUNGEON")
end)
