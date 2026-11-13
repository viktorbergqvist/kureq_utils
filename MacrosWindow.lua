-- The macros window (Macros.lua), in Kureq Utils' look (Style.lua), with the loadout editor's pieces (MacroForm.lua).
-- Three pages, tabs under the window: General (account macros) and Character (this character's), your macros on the
-- left (searchable, each with its icon and what it does) and the chosen one's form on the right (name, icon,
-- character or account, the code editor, helpers, spell picker), saved to the game on Save (asking first when the
-- game's copy changed since), Revert, an icon to drag to a bar, Add to loadout and Delete (both asked first); then
-- Ready-made, the ready-made macros as cards (your class's first) and the chosen one's options, where Create makes it a
-- character or account macro. On top: search, your macro counts, New macro, Import (paste a macro; it's checked
-- first) and History (earlier versions of the macro, and deleted macros, to put back). SmartMacrosWindow.lua adds a
-- fourth page, Smart macros, through M.ui.addPage.
local _, ns = ...
local M, L, St, C = ns.macros, ns.loadouts, ns.style, ns.macroCode
local Pane, Text, Line = St.Pane, St.Text, St.Line
local Button = L.Button

local W, H, CODE_H = 900, 620, 220
local BW = St.bodySize(W, H)
local PAD, GAP, TOP_H = 12, 8, 28
local MAIN_Y = -(PAD + TOP_H + GAP)
local LIST_W, ROW_H, CARD_H = 330, 34, 64
local FORM_W = BW - 2 * PAD - LIST_W - GAP - 24

local frame, body = St.Window("KureqMacrosFrame", "Macros", W, H)
local page = "account" -- "account" (General), "character" or "gallery"
-- Your macros: the chosen macro (as M.list has it), the form's load ({index, name, account, body} it was filled
-- from), an icon picked and not saved, and busy while a change is made
local selected, loaded, pickedIcon, busy
local readyKind -- Ready-made: the chosen card's kind
local makeAccount = false -- Ready-made: Create makes an account macro
local refresh, discardFirst
local kept -- Your macros: the form holds unsaved changes to a macro renamed or deleted elsewhere

local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) or "|cffffffff"
end
local function className(class) return LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class end

-- Pages, tabs and the top bar ----------------------------------------------------------------------------------------

local galleryPage, macrosPage = CreateFrame("Frame", nil, body), CreateFrame("Frame", nil, body)
for _, p in ipairs({galleryPage, macrosPage}) do p:SetAllPoints() end
local tabs = {}
local function scopeOf(p) return p == "account" end -- a macro page's scope: true for account macros
local function isMacros(p) return p == "account" or p == "character" end
-- the pages that aren't your macros: key -> {frame, refresh}; files after this one add theirs (M.ui.addPage)
local pages = {gallery = {frame = galleryPage}}
local function goTo(key)
    if key == page then return end
    -- another scope's list: the form gets another macro, so unsaved changes are asked about first
    local function go()
        page = key
        if isMacros(page) then selected = nil end
        refresh()
    end
    if isMacros(key) then discardFirst(go) else go() end
end
local function addTab(label, key)
    local b = St.Tab(frame, label, function() goTo(key) end)
    b.page = key
    tabs[#tabs + 1] = b
end
for _, t in ipairs({{"General", "account"}, {"Character", "character"}, {"Ready-made", "gallery"}}) do addTab(t[1], t[2]) end

local search = CreateFrame("EditBox", nil, macrosPage, "SearchBoxTemplate")
search:SetPoint("TOPLEFT", PAD + 6, -PAD - 4)
search:SetSize(190, 20)
search:SetAutoFocus(false)
search:HookScript("OnTextChanged", function() refresh() end)
local counts = Text(body, "GameFontHighlight") -- your macros and Blizzard's limits
counts:SetPoint("TOPLEFT", PAD + 214, -PAD - 6)
local newButton = Button(macrosPage, "New macro", 100)
newButton:SetPoint("TOPRIGHT", -PAD, -PAD - 3)
local importButton = Button(macrosPage, "Import", 80)
importButton:SetPoint("RIGHT", newButton, "LEFT", -6, 0)
local historyButton = Button(macrosPage, "History", 80)
historyButton:SetPoint("RIGHT", importButton, "LEFT", -6, 0)
local blizzardButton = Button(macrosPage, "Blizzard's window", 130) -- the game's own macro window
blizzardButton:SetPoint("RIGHT", historyButton, "LEFT", -6, 0)
blizzardButton:SetScript("OnClick", function() frame:Hide(); M.openBlizzard() end)

-- Pick mode (M.pick, from a loadout's slot menu): a banner over the top bar says where the macro goes; clicking a row
-- hands that macro over and closes the window. Cancel, Escape or closing either window ends it.
local picking -- {text, fn} while a loadout slot waits for a macro
local banner = Pane(body)
banner:SetPoint("TOPLEFT", PAD, -PAD + 2)
banner:SetPoint("TOPRIGHT", -PAD, -PAD + 2)
banner:SetHeight(TOP_H + 4)
banner:SetFrameLevel(macrosPage:GetFrameLevel() + 10)
banner.text = Text(banner, "GameFontNormal")
banner.text:SetPoint("LEFT", 12, 0)
banner.cancel = Button(banner, "Cancel", 90)
banner.cancel:SetPoint("RIGHT", -6, 0)
banner:Hide()
local TOP_BAR = {search, counts, newButton, importButton, historyButton, blizzardButton}

-- A list pane left and a detail pane right, as on both pages
local function panes(parent, title)
    local list = Pane(parent)
    list:SetPoint("TOPLEFT", PAD, MAIN_Y)
    list:SetPoint("BOTTOMLEFT", PAD, PAD)
    list:SetWidth(LIST_W)
    list.title = Text(list, "GameFontNormal")
    list.title:SetPoint("TOPLEFT", 12, -12)
    list.title:SetText(title)
    list.count = Text(list, "GameFontDisableSmall")
    list.count:SetPoint("TOPRIGHT", -12, -14)
    list.count:SetJustifyH("RIGHT")
    local line = Line(list)
    line:SetPoint("TOPLEFT", 6, -30)
    line:SetPoint("TOPRIGHT", -6, -30)
    local scroll = CreateFrame("ScrollFrame", nil, list, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -34)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    list.child = CreateFrame("Frame", nil, scroll)
    list.child:SetSize(LIST_W - 32, 1)
    scroll:SetScrollChild(list.child)
    local detail = Pane(parent)
    detail:SetPoint("TOPLEFT", list, "TOPRIGHT", GAP, 0)
    detail:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    detail.status = Text(detail, "GameFontHighlightSmall") -- what the last action did
    detail.status:SetPoint("BOTTOMLEFT", 12, 12)
    detail.status:SetPoint("RIGHT", -12, 0)
    detail.status:SetWordWrap(true)
    return list, detail
end
local cardList, galleryDetail = panes(galleryPage, "Ready-made macros")
local macroList, macroDetail = panes(macrosPage, "Your macros")
local function say(text)
    galleryDetail.status:SetText(text)
    macroDetail.status:SetText(text)
end

-- Ready-made: cards, and the chosen one's options --------------------------------------------------------------------

local form = L.ReadyForm(galleryDetail, FORM_W)
form:SetPoint("TOPLEFT", 12, -12)
form.back:Hide()
form.make = St.Dropdown(form, 170, function() return makeAccount and "Account macro" or "Character macro" end,
    function(root)
        for _, s in ipairs({{false, "Character macro (this character)"}, {true, "Account macro (every character)"}}) do
            root:CreateRadio(s[2], function() return makeAccount == s[1] end, function()
                makeAccount = s[1]
                form.make:Refresh()
            end, s[1])
        end
    end)
form.make:SetPoint("LEFT", form.add, "RIGHT", 8, 0)
form.make:Refresh()

local function openReady(kind)
    readyKind = kind
    form.Open(kind, nil, nil, "Create")
end
local cards = {} -- made as the gallery first shows each ready-made (the /ku ones exist only then)
local function card(r)
    if cards[r.kind] then return cards[r.kind] end
    local c = L.ReadyCard(cardList.child, r, LIST_W - 32, CARD_H)
    if r.class then c.title:SetText(("%s%s|r · %s"):format(classColor(r.class), className(r.class), r.name)) end
    if r.ku then c.title:SetText("|cffffd100Kureq Utils|r · " .. r.command) end
    c.pick = c:CreateTexture(nil, "BACKGROUND", nil, 1) -- lit gold when chosen, as a list row
    c.pick:SetPoint("TOPLEFT", 3, -3)
    c.pick:SetPoint("BOTTOMRIGHT", -3, 3)
    c.pick:SetColorTexture(St.GOLD[1], St.GOLD[2], St.GOLD[3], 0.12)
    c:SetScript("OnClick", function(self)
        openReady(self.kind)
        refresh()
    end)
    cards[r.kind] = c
    return c
end
frame.cards = cards

local function refreshGallery()
    local list = M.ready()
    if not readyKind then openReady(list[1].kind) end
    local _, class = UnitClass("player")
    local mine = 0
    for i, r in ipairs(list) do
        local c = card(r)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", 0, -(i - 1) * (CARD_H + 6))
        c.pick:SetShown(r.kind == readyKind)
        local off = r.ku and r.ku.key and not ns.IsOn(r.ku.key) -- its module is off: greyed, and says so
        c:SetAlpha(off and 0.5 or 1)
        c.sub:SetText(off and ("%s is off: turn it on in /ku."):format(r.ku.moduleName) or r.text)
        if r.class == class then mine = mine + 1 end
    end
    cardList.child:SetHeight(#list * (CARD_H + 6))
    cardList.count:SetText(mine > 0 and ("%d for your class"):format(mine) or #list)
    form.make:Refresh()
end

-- Changes to the game's macros fire UPDATE_MACROS at once: the window waits until a change is done (busy)
local function quietly(fn, ...)
    busy = true
    local ok, a, b = pcall(fn, ...)
    busy = false
    if not ok then error(a, 0) end
    return a, b
end

-- Your macros: the list, and the chosen one's form ------------------------------------------------------------------

local rows = {}
frame.rows = rows
local emptyText = Text(macroDetail, "GameFontDisable")
emptyText:SetPoint("CENTER")
emptyText:SetWidth(380)
emptyText:SetWordWrap(true)
emptyText:SetJustifyH("CENTER")
emptyText:SetText("No macros here yet. Click New macro to write one, Import to paste one, or make one from the Ready-made tab.")

local function chosen() return selected and M.find(selected.index, selected.name, selected.account) end
local function target() return loaded and {index = loaded.index, name = loaded.name, account = loaded.account} end
local ed
-- Fills the form from macro m as the game has it
local function fill(m)
    loaded, pickedIcon = {index = m.index, name = m.name, account = m.account, body = m.body}, nil
    ed.problem:SetText(m.twin and M.ambiguous(m) or "")
    ed.name:SetText(m.name)
    ed.box:SetText(m.body)
end
local function dirty()
    return loaded ~= nil and ((ed.box:GetText() or "") ~= loaded.body or ns.trim(ed.name:GetText() or "") ~= loaded.name
        or pickedIcon ~= nil)
end
local unsaved, saveButton -- set below
local function updateMark()
    unsaved:SetShown(dirty())
    saveButton:SetEnabled(dirty())
end

ed = L.MacroForm(macroDetail, FORM_W, {
    get = function() local m = chosen(); return m and (m.account and "account" or "character") end,
    set = function(account)
        local m = chosen()
        if not m or not m.account == not account then return end -- already that: nothing changes
        if dirty() then return ed.problem:SetText("Save or revert your changes first.") end
        local moved, why = quietly(M.move, target(), account)
        if not moved then return ed.problem:SetText(why or "") end
        selected, page = moved, account and "account" or "character"
        fill(moved)
        say(("%s is now %s macro."):format(moved.name, account and "an account" or "a character"))
        refresh()
    end,
}, nil, CODE_H)
ed:SetPoint("TOPLEFT", 12, -12)
frame.editor = ed
ed.name:SetScript("OnTextChanged", function() updateMark() end)
ed.name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
ed.name:SetScript("OnEscapePressed", function(self)
    if loaded then self:SetText(loaded.name) end
    self:ClearFocus()
end)
ed.box:HookScript("OnTextChanged", function(self)
    ed.showCount(self:GetText() or "")
    updateMark()
end)

local iconDialog = L.IconPicker(frame, function(icon)
    pickedIcon = icon
    ed.icon.texture:SetTexture(L.iconPath(icon))
    updateMark()
end)
frame.iconDialog = iconDialog
ed.icon:SetScript("OnClick", function() iconDialog.Open() end)

-- Save and Revert, with a mark while what's in the form isn't saved
saveButton = Button(macroDetail, "Save", 90)
saveButton:SetPoint("TOPLEFT", 12, -(18 + 108 + CODE_H))
local revertButton = Button(macroDetail, "Revert", 90)
revertButton:SetPoint("LEFT", saveButton, "RIGHT", 8, 0)
unsaved = Text(macroDetail, "GameFontNormalSmall")
unsaved:SetPoint("LEFT", revertButton, "RIGHT", 10, 0)
unsaved:SetText("Unsaved changes")
unsaved:Hide()
local conflict -- what the overwrite-or-reload popup is open for: the form's load
local function save(force)
    if not loaded then return end
    local fields = {name = ns.trim(ed.name:GetText() or ""), body = ed.box:GetText() or "", icon = pickedIcon}
    local saved, why = quietly(M.save, target(), fields, loaded, force)
    if why == "conflict" then
        conflict = loaded
        StaticPopupDialogs.KUREQUTILS_MACRO_CONFLICT = {
            text = ("%s was changed in the game since you opened it here. Save yours over it, or reload it?"):format(loaded.name),
            button1 = "Overwrite", button2 = "Reload", timeout = 0, whileDead = true, hideOnEscape = true,
            OnAccept = function()
                if conflict and conflict == loaded and ns.IsOn("macros") then save(true) end
                conflict = nil
            end,
            OnCancel = function(_, _, reason)
                local m = conflict == loaded and chosen()
                conflict = nil
                if reason == "clicked" and m then
                    fill(m)
                    refresh()
                end
            end}
        return StaticPopup_Show("KUREQUTILS_MACRO_CONFLICT")
    end
    if not saved then return ed.problem:SetText(why or M.CHANGED) end
    selected = saved
    fill(saved)
    say(("Saved the macro %s."):format(saved.name))
    refresh()
end
saveButton:SetScript("OnClick", function() save(false) end)
revertButton:SetScript("OnClick", function()
    local m = chosen()
    if m then fill(m) end
    refresh()
end)
frame.saveButton, frame.revertButton, frame.unsaved = saveButton, revertButton, unsaved

-- Below: the macro's icon to drag to a bar, Add to loadout, Delete
local drag = CreateFrame("Button", nil, macroDetail)
drag:SetSize(36, 36)
drag:SetPoint("TOPLEFT", 12, -(52 + 108 + CODE_H))
drag.texture = drag:CreateTexture(nil, "ARTWORK")
drag.texture:SetAllPoints()
local dragHl = drag:CreateTexture(nil, "HIGHLIGHT")
dragHl:SetAllPoints()
dragHl:SetColorTexture(1, 1, 1, 0.15)
drag:RegisterForDrag("LeftButton")
local function pickup()
    local m = chosen()
    if not m then return end
    local ok, why = M.pickup(m)
    if not ok and why then say(why) end
end
drag:SetScript("OnDragStart", pickup)
drag:SetScript("OnClick", pickup)
drag:SetScript("OnEnter", function(self)
    St.Tooltip(self, "Drag to bar", {"Drag it to an action bar, or click it and then click a slot."})
end)
drag:SetScript("OnLeave", function() GameTooltip:Hide() end)
drag.label = Text(macroDetail, "GameFontNormalSmall")
drag.label:SetPoint("LEFT", drag, "RIGHT", 8, 0)
drag.label:SetText("Drag to bar")
frame.dragButton = drag

local replacing -- what the replace popup is open for: {macro, loadout}
local function addTo(m, lo, replace)
    local done, why = M.toLoadout(m, lo, replace)
    if why == "exists" then
        replacing = {m = m, lo = lo}
        StaticPopupDialogs.KUREQUTILS_REPLACE_LOADOUT_MACRO = {
            text = ("The loadout %s already has a macro called %s. Replace it with this one?"):format(lo.name, m.name),
            button1 = YES or "Yes", button2 = NO or "No", timeout = 0, whileDead = true, hideOnEscape = true,
            OnAccept = function()
                local r = replacing
                replacing = nil
                if not (r and ns.IsOn("macros") and ns.IsOn("loadouts")) then return end
                for _, x in pairs(L.list()) do
                    if x == r.lo then return addTo(r.m, r.lo, true) end -- still saved
                end
            end}
        return StaticPopup_Show("KUREQUTILS_REPLACE_LOADOUT_MACRO")
    end
    say(done and (done == "updated" and "Updated %s in the loadout %s." or "Added %s to the loadout %s.")
        :format(m.name, lo.name) or ("Not added to %s: %s"):format(lo.name, why))
end
local toLoadout = St.MenuButton(macroDetail, 140, function() return "Add to loadout" end, function(root)
    local los = {}
    for id, lo in pairs(L.list()) do los[#los + 1] = {id = id, lo = lo} end
    table.sort(los, function(a, b)
        if a.lo.name ~= b.lo.name then return a.lo.name < b.lo.name end
        return a.id < b.id
    end)
    if #los == 0 then root:CreateTitle("No saved loadouts yet: save one in the loadouts window.") end
    for _, e in ipairs(los) do
        root:CreateButton(e.lo.name, function()
            local m = chosen()
            if m and ns.IsOn("macros") then addTo(m, e.lo) end
        end)
    end
    if root.SetScrollMode then root:SetScrollMode(400) end
end)
toLoadout:SetPoint("LEFT", drag.label, "RIGHT", 16, 0)
toLoadout:Refresh()
frame.toLoadout = toLoadout

local deleteButton = Button(macroDetail, "Delete macro", 120)
deleteButton:SetPoint("TOPRIGHT", -12, -(59 + 108 + CODE_H))
frame.deleteButton = deleteButton
local asking -- the macro the delete popup is open for
deleteButton:SetScript("OnClick", function()
    local m = chosen()
    if not m then return end
    if m.twin then return ed.problem:SetText(M.ambiguous(m)) end
    asking = m
    StaticPopupDialogs.KUREQUTILS_DELETE_GAME_MACRO = {
        text = ("Delete the macro %s? It goes from your action bars too."):format(m.name),
        button1 = YES or "Yes", button2 = NO or "No", timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function()
            local a = asking
            asking = nil
            if not (a and ns.IsOn("macros")) then return end
            local ok, why = quietly(M.delete, a)
            if not ok then return say(why) end
            selected, loaded = nil, nil
            say(("Deleted the macro %s."):format(a.name))
            refresh()
        end}
    StaticPopup_Show("KUREQUTILS_DELETE_GAME_MACRO")
end)

newButton:SetScript("OnClick", function() discardFirst(function()
    local account = scopeOf(page) -- in the tab you're on
    local name, n = "New macro", 1
    while M.find(nil, name, account) do
        n = n + 1
        name = "New macro " .. n
    end
    local made, why = quietly(M.create, {name = name, icon = L.QUESTION_MARK, body = "", account = account or nil})
    if not made then return say(why) end
    selected = made
    fill(made)
    say("")
    refresh()
end) end)

form.add:SetScript("OnClick", function() discardFirst(function()
    local r = form.Result()
    local made, why = quietly(M.create, {name = r.name, icon = r.icon, body = r.body, account = makeAccount or nil})
    if not made then return form.problem:SetText(why) end
    form.problem:SetText("")
    selected, page = made, made.account and "account" or "character"
    fill(made)
    say(("Made the macro %s. Drag it to a bar from here."):format(made.name))
    refresh()
end) end)

-- Leaving a form with unsaved changes (another macro, a new one) asks first; fn runs once it may
local leaving -- what the discard popup is open for: {loaded, fn}
function discardFirst(fn)
    if not dirty() then return fn() end
    leaving = {loaded = loaded, fn = fn}
    StaticPopupDialogs.KUREQUTILS_DISCARD_MACRO_EDITS = {
        text = ("Discard your changes to %s?"):format(loaded.name), button1 = "Discard", button2 = "Keep editing",
        timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function()
            local l = leaving
            leaving = nil
            if l and l.loaded == loaded and ns.IsOn("macros") then
                loaded = nil -- not this form's any more
                l.fn()
            end
        end}
    StaticPopup_Show("KUREQUTILS_DISCARD_MACRO_EDITS")
end

local FORM_PARTS = {ed, drag, drag.label, deleteButton, saveButton, revertButton}
local function pickRow(self)
    local x = self.macro
    if picking then
        local why = picking.fn(x) -- a refusal keeps pick mode
        if why then return say(why) end
        picking = nil
        frame:Hide()
        return
    end
    if loaded and x.index == loaded.index and x.name == loaded.name then return end -- the one in the form
    discardFirst(function()
        selected = x
        refresh()
    end)
end
-- the form's macro is m: same name and scope (and index, between two of a name); the indexes move as macros are made
local function same(m)
    return loaded and m.name == loaded.name and not m.account == not loaded.account and (not m.twin or m.index == loaded.index)
end
-- A list row with the macro's icon left of its name and what it does
local function macroRow(i)
    local r = St.ListRow(macroList.child, i, LIST_W - 32, ROW_H, pickRow)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(26, 26)
    r.icon:SetPoint("LEFT", 6, 0)
    r.nameText:ClearAllPoints()
    r.nameText:SetPoint("TOPLEFT", 40, -4)
    r.nameText:SetPoint("RIGHT", -70, 0)
    r.sub:ClearAllPoints()
    r.sub:SetPoint("BOTTOMLEFT", 40, 5)
    r.sub:SetPoint("RIGHT", -8, 0)
    r:RegisterForDrag("LeftButton") -- a row drags its macro to a bar, as the form's icon does
    r:SetScript("OnDragStart", function(self)
        local ok, why = M.pickup(self.macro)
        if not ok and why then say(why) end
    end)
    return r
end
local function refreshMacros()
    local query = (search:GetText() or ""):lower()
    local list, all, book = {}, M.list(), C.spells()
    for _, x in ipairs(all) do
        if not x.account == not scopeOf(page) then
            x.summary = C.summary(x.body)
            if query == "" or x.name:lower():find(query, 1, true) or x.summary:lower():find(query, 1, true) then
                list[#list + 1] = x
            end
        end
    end
    local m = chosen()
    if m and not m.account ~= not scopeOf(page) then m = nil end -- moved to the other tab elsewhere
    -- the form's macro was renamed or deleted elsewhere: unsaved changes stay in the form, no row lit; else the first
    local keep = not m and dirty()
    if not m and not keep then
        selected = list[1]
        m = chosen()
    end
    for i, x in ipairs(list) do
        local r = rows[i] or macroRow(i)
        rows[i] = r
        r.macro = x
        r.icon:SetTexture(L.iconPath(x.icon))
        r.nameText:SetText(x.name)
        local errors = 0
        for _, p in ipairs((C.check(x.body, {spells = book}))) do
            if p.severity == "error" then errors = errors + 1 end
        end
        r.count:SetText(errors > 0 and ("|cffff4040%d %s|r"):format(errors, errors == 1 and "problem" or "problems") or "")
        r.sub:SetText(x.summary)
        r.each:SetText("")
        r:SetPicked(m ~= nil and x.index == m.index)
        r:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    macroList.child:SetHeight(math.max(1, #list * ROW_H))
    macroList.title:SetText(scopeOf(page) and "General macros" or "Character macros")
    macroList.count:SetText(#list)
    for _, part in ipairs(FORM_PARTS) do part:SetShown(m ~= nil or keep) end
    toLoadout:SetShown(m ~= nil and ns.IsOn("loadouts"))
    emptyText:SetShown(m == nil and not keep)
    if keep then
        kept = true
        ed.problem:SetText(M.CHANGED .. " Your changes stay here until you pick another.")
        return updateMark()
    end
    if kept and m then -- it's back
        kept = false
        ed.problem:SetText(m.twin and M.ambiguous(m) or "")
    end
    if not m then
        loaded = nil
        return unsaved:Hide()
    end
    selected = m
    if not same(m) then
        fill(m) -- another macro
    else
        loaded.index = m.index
        -- changed elsewhere (Blizzard's window): a form with nothing unsaved shows it; else Save asks
        if not dirty() and m.body ~= loaded.body then fill(m) end
    end
    ed.showCount(ed.box:GetText() or "")
    local icon = pickedIcon or m.icon
    ed.icon.texture:SetTexture(L.iconPath(icon))
    drag.texture:SetTexture(L.iconPath(m.icon))
    ed.scope:Refresh()
    updateMark()
end

-- Import: paste a macro, see its problems in the code editor, then make it in the tab you're on ---------------------

local importDialog = L.Dialog(frame, 540, 410)
importDialog.title:SetText("Import a macro")
importDialog.ok:SetText("Import")
importDialog.name = St.EditBox(importDialog)
importDialog.name:SetPoint("TOPLEFT", 18, -70)
importDialog.name:SetWidth(160)
importDialog.name:SetMaxLetters(L.MACRO_NAME)
L.Prompt(importDialog.name, "Its name")
local importStatus = CreateFrame("Frame", nil, importDialog)
importStatus:SetPoint("TOPLEFT", 12, -306)
importStatus:SetSize(516, 16)
importDialog.code = C.Editor(importDialog, 516, 200, importStatus)
importDialog.code:SetPoint("TOPLEFT", 12, -100)
importDialog.problem = Text(importDialog, "GameFontNormalSmall")
importDialog.problem:SetPoint("TOPLEFT", 12, -330)
importDialog.problem:SetWidth(516)
importDialog.problem:SetWordWrap(true)
importDialog.problem:SetTextColor(1, 0.3, 0.3)
local importInto -- the scope the dialog was opened for: true for account macros
importButton:SetScript("OnClick", function() discardFirst(function()
    importInto = scopeOf(page)
    importDialog.text:SetText(("Paste a macro's text from a website or another character. It's checked before it's "
        .. "made in your %s macros."):format(importInto and "General" or "Character"))
    importDialog.name:SetText("")
    importDialog.code.edit:SetText("")
    importDialog.code:Refresh()
    importDialog.problem:SetText("")
    importDialog:Show()
end) end)
importDialog.ok:SetScript("OnClick", function()
    if not ns.IsOn("macros") then return end
    local body, why = M.importText(importDialog.code.edit:GetText())
    if not body then return importDialog.problem:SetText(why) end
    local name = ns.trim(importDialog.name:GetText() or "")
    if name == "" then name = C.summary(body):gsub(" %+%d+$", ""):sub(1, L.MACRO_NAME) end
    local made
    made, why = quietly(M.create, {name = name, icon = L.QUESTION_MARK, body = body, account = importInto or nil})
    if not made then return importDialog.problem:SetText(why) end
    importDialog:Hide()
    selected, page = made, made.account and "account" or "character"
    fill(made)
    say(("Imported the macro %s."):format(made.name))
    refresh()
end)

-- History: this macro's earlier versions, and the tab's deleted macros, to put back ---------------------------------

local historyDialog = L.Dialog(frame, 600, 430)
historyDialog.title:SetText("History")
historyDialog.ok:SetText("Restore")
local historyRows, historyView, historyPick = {}, "versions", 1 -- the rows, "versions" or "deleted", the chosen row
local historyTabs = {}
local historyList = CreateFrame("ScrollFrame", nil, historyDialog, "ScrollFrameTemplate")
historyList:SetPoint("TOPLEFT", 12, -92)
historyList:SetSize(240, 280)
historyList.child = CreateFrame("Frame", nil, historyList)
historyList.child:SetSize(240, 1)
historyList:SetScrollChild(historyList.child)
local preview = Pane(historyDialog) -- the chosen version's text, coloured
preview:SetPoint("TOPLEFT", 276, -92)
preview:SetSize(312, 280)
preview.text = preview:CreateFontString(nil, "OVERLAY")
preview.text:SetFontObject("ChatFontNormal")
preview.text:SetPoint("TOPLEFT", 10, -10)
preview.text:SetWidth(292)
preview.text:SetJustifyH("LEFT")
preview.text:SetJustifyV("TOP")
preview.text:SetWordWrap(true)
local historyEmpty = Text(historyDialog, "GameFontDisable")
historyEmpty:SetPoint("TOPLEFT", 18, -100)
historyEmpty:SetWidth(230)
historyEmpty:SetWordWrap(true)
local historyFor -- {account, name} of the macro the dialog was opened on, or nil
local historyPage, historyShown -- the page it was opened on, and the entry it shows (what Restore acts on)
local function when(t) return date("%d %b %H:%M", tonumber(t) or 0) end
local function historyEntries()
    if historyView == "deleted" then return M.deleted(scopeOf(historyPage)) end
    local out = {}
    for _, v in ipairs(historyFor and M.versions(historyFor.account, historyFor.name) or {}) do out[#out + 1] = {version = v} end
    return out
end
local function drawHistory()
    for _, t in ipairs(historyTabs) do t:Set(t.tabText, t.view == historyView) end
    local list = historyEntries()
    historyPick = math.min(historyPick, #list)
    for i, e in ipairs(list) do
        local r = historyRows[i] or St.ListRow(historyList.child, i, 220, ROW_H, function(self)
            historyPick = self.n
            drawHistory()
        end)
        historyRows[i], r.n = r, i
        local v = e.version or e.versions[1]
        r.nameText:SetText(e.version and when(v.time) or e.name)
        r.count:SetText("|cff999999" .. (e.version and (v.what or "") or when(v.time)) .. "|r")
        r.sub:SetText(C.summary(v.body))
        r:SetPicked(i == historyPick)
        r:Show()
    end
    for i = #list + 1, #historyRows do historyRows[i]:Hide() end
    historyList.child:SetHeight(math.max(1, #list * ROW_H))
    local e = list[historyPick]
    historyShown = e
    local v = e and (e.version or e.versions[1])
    local lines = {}
    for _, line in ipairs(v and C.parse(v.body).lines or {}) do lines[#lines + 1] = C.highlight(line) end
    preview.text:SetText(table.concat(lines, "\n"))
    historyDialog.ok:SetEnabled(v ~= nil)
    historyEmpty:SetShown(#list == 0)
    historyEmpty:SetText(historyView == "deleted" and "No deleted macros here. Macros you delete in this window can be "
        .. "put back from here." or "No earlier versions yet. Each Save keeps the version before it here.")
end
for i, t in ipairs({{"This macro", "versions"}, {"Deleted", "deleted"}}) do
    local b = St.TextTab(historyDialog, function()
        historyView, historyPick = t[2], 1
        drawHistory()
    end)
    b.tabText, b.view = t[1], t[2]
    if i == 1 then b:SetPoint("TOPLEFT", 0, -60) else b:SetPoint("LEFT", historyTabs[1], "RIGHT", 4, 0) end
    historyTabs[i] = b
end
local function openHistory(view)
    local m = chosen()
    historyFor = m and {account = m.account, name = m.name} or nil
    historyPage = page
    historyView, historyPick = historyFor and view or "deleted", 1
    historyDialog.text:SetText(("The versions of your %s macros before each change, the newest %d per macro."):format(
        scopeOf(page) and "General" or "Character", M.KEEP))
    historyDialog:Show()
    drawHistory()
end
historyButton:SetScript("OnClick", function() openHistory("versions") end)
-- Restore: an earlier version goes into the form, unsaved (Save keeps it); a deleted macro is made again
historyDialog.ok:SetScript("OnClick", function()
    if not ns.IsOn("macros") then return end
    local e = historyShown
    if not e then return end
    if e.version then return discardFirst(function() -- unsaved changes in the form are asked about first
        local m = chosen()
        if not (m and historyFor and m.name == historyFor.name and not m.account == not historyFor.account) then
            return historyDialog.text:SetText(M.CHANGED)
        end
        historyDialog:Hide()
        fill(m) -- the form is this macro's again (the discard let go of it)
        ed.name:SetText(e.version.name)
        ed.box:SetText(e.version.body)
        if e.version.icon ~= nil and e.version.icon ~= m.icon then
            pickedIcon = e.version.icon
            ed.icon.texture:SetTexture(L.iconPath(pickedIcon))
        end
        ed.showCount(e.version.body)
        updateMark()
        say(("Put back the version from %s: Save to keep it."):format(when(e.version.time)))
    end) end
    discardFirst(function()
        local v = e.versions[1]
        local made, why = quietly(M.create, {name = e.name, icon = v.icon or L.QUESTION_MARK, body = v.body,
            account = scopeOf(historyPage) or nil})
        if not made then return historyDialog.text:SetText(why) end
        historyDialog:Hide()
        selected = made
        fill(made)
        say(("Put back the macro %s."):format(made.name))
        refresh()
    end)
end)

-- Refresh ------------------------------------------------------------------------------------------------------------

function refresh()
    if busy or not frame:IsShown() then return end
    if historyDialog:IsShown() and historyPage ~= page then historyDialog:Hide() end -- it shows another page's macros
    for key, p in pairs(pages) do p.frame:SetShown(page == key) end
    macrosPage:SetShown(isMacros(page))
    for _, t in ipairs(tabs) do t:SetOn(t.page == page) end
    banner:SetShown(picking ~= nil)
    banner.text:SetText(picking and picking.text or "")
    for _, part in ipairs(TOP_BAR) do part:SetShown(not picking) end
    local numAccount, numChar = M.counts()
    local function part(label, n, cap) return ("%s%s %d of %d|r"):format(n >= cap and "|cffff4040" or "", label, n, cap) end
    counts:SetText(part("General", numAccount, M.CAPS.account) .. "  ·  "
        .. part("Character", numChar, M.CAPS.character))
    if page == "gallery" then refreshGallery() elseif pages[page] then pages[page].refresh() else refreshMacros() end
end
frame:SetScript("OnShow", refresh)
local DIALOGS = {iconDialog, importDialog, historyDialog}
frame:SetScript("OnHide", function()
    picking = nil
    for _, d in ipairs(DIALOGS) do d:Hide() end
end)
M.changed = refresh

function M.toggle()
    if frame:IsShown() then frame:Hide() else frame:Show() end
end
-- Opens the window on a page: "account", "character", "gallery" or one added with M.ui.addPage
function M.open(key)
    frame:Show()
    goTo(key or page or "account") -- no page asked for: the one you were on, else General
    refresh()
end
-- Pick mode: text on the banner; clicking a General or Character macro calls fn(macro), which returns why it refuses
-- it, or nothing. account: start on General.
function M.pick(text, fn, account)
    picking = {text = text, fn = fn}
    search:SetText("") -- hidden while picking, so it mustn't filter
    M.open(account and "account" or "character")
end
function M.endPick()
    if not picking then return end
    picking = nil
    refresh()
end
banner.cancel:SetScript("OnClick", M.endPick)
-- Adds a page after the others, with its tab, a list pane and a detail pane (as the other pages); draw() fills it
-- while it shows. Returns the list pane and the detail pane.
local function addPage(label, key, title, draw)
    local p = CreateFrame("Frame", nil, body)
    p:SetAllPoints()
    pages[key] = {frame = p, refresh = draw}
    addTab(label, key)
    return panes(p, title)
end
M.frame = frame
-- what the tests drive
M.ui = {frame = frame, tabs = tabs, counts = counts, form = form, cards = cards, rows = rows, editor = ed,
    newButton = newButton, drag = drag, toLoadout = toLoadout, deleteButton = deleteButton, iconDialog = iconDialog,
    emptyText = emptyText, status = macroDetail.status, saveButton = saveButton, revertButton = revertButton,
    unsaved = unsaved, search = search, importButton = importButton, importDialog = importDialog,
    historyButton = historyButton, blizzardButton = blizzardButton, historyDialog = historyDialog, historyRows = historyRows, historyTabs = historyTabs,
    preview = preview, banner = banner, addPage = addPage, quietly = quietly, LIST_W = LIST_W, ROW_H = ROW_H}

-- Resizing: the list and detail panes stretch on their anchors (the lists show more rows); the code editor grows with
-- the detail pane, the action rows (Save, Drag to bar, Delete macro) staying under it. The ready-made form keeps its design width.
St.Resizable(frame, function(w, h)
    local codeH = CODE_H + h - H
    ed:SetFormSize(w - W + FORM_W, codeH)
    saveButton:SetPoint("TOPLEFT", 12, -(18 + 108 + codeH))
    drag:SetPoint("TOPLEFT", 12, -(52 + 108 + codeH))
    deleteButton:SetPoint("TOPRIGHT", -12, -(59 + 108 + codeH))
end)

local POPUPS = {"KUREQUTILS_DELETE_GAME_MACRO", "KUREQUTILS_DISCARD_MACRO_EDITS", "KUREQUTILS_MACRO_CONFLICT", "KUREQUTILS_REPLACE_LOADOUT_MACRO"}
ns.OnModuleChange("macros", function(on)
    if on then return end
    frame:Hide()
    for _, d in ipairs(DIALOGS) do d:Hide() end
    for _, which in ipairs(POPUPS) do StaticPopup_Hide(which) end
end)
