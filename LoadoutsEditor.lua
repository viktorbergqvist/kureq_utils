-- Editing a saved loadout in the loadouts window (LoadoutsWindow.lua shows it, Loadouts.lua changes it): the Macros
-- tab's macro editor (name, icon, text, scope, helpers, a spell picker) and its ready-made macros, dropping things on
-- the Bars tab's slots, binding keys on the Bindings tab and the Settings tab's values. Each edit saves at once to
-- the loadout only; your character changes when you Load it. Revert changes puts back the loadout as it was when the
-- window opened. Backups aren't edited.
local _, ns = ...
local L, St = ns.loadouts, ns.style
local U = L.ui
local Pane, Text = St.Pane, St.Text
local Button, Prompt = U.Button, U.Prompt
local frame, detail, content, status, summary = U.frame, U.detail, U.content, U.status, U.summary
local W, TOP = U.CONTENT_W, U.SUMMARY_H
local QUESTION_MARK = 134400

local view = "list" -- the Macros tab: "list", "macro" (editing one), "gallery" or "ready" (a ready-made's options)
local editing -- the macro's index in the macro and ready views (nil in the ready view: a new macro)
local readyKind, readyOptions -- the ready view's kind and the options being set
local shownLo, shownTab -- the view starts over on another loadout or tab
local listening -- {command, key it replaces} while a key is awaited

local function current() -- the chosen loadout, if it's a saved one (backups aren't edited)
    local lo, isBackup = U.chosen()
    if lo and not isBackup then return lo end
end
local function refresh() U.refresh() end
local function say(text) status:SetText(text) end
local function count(n, one, many) return n .. " " .. (n == 1 and one or many) end
local function actionName(command) return U.bindingName(command) end

-- Your spellbook: {name = its tab, spells = {names}}, active spells only, each name once
local function spellbook()
    local tabs = {}
    local function add(list, seen, spell)
        if spell and not seen[spell] then
            seen[spell] = true
            list[#list + 1] = spell
        end
    end
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1
        for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
            if line and not line.shouldHide then
                local list, seen = {}, {}
                for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                    local item = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
                    if item and item.itemType == spellType and not item.isPassive then add(list, seen, item.name) end
                end
                if #list > 0 then tabs[#tabs + 1] = {name = line.name, spells = list} end
            end
        end
    elseif GetNumSpellTabs then
        for i = 1, GetNumSpellTabs() do
            local name, _, offset, n = GetSpellTabInfo(i)
            local list, seen = {}, {}
            for slot = offset + 1, offset + n do
                if not IsPassiveSpell(slot, "spell") then add(list, seen, (GetSpellBookItemName(slot, "spell"))) end
            end
            if #list > 0 then tabs[#tabs + 1] = {name = name, spells = list} end
        end
    end
    return tabs
end
-- A menu of your spellbook, a submenu per tab; picking a spell calls fn(name)
local function spellMenu(root, fn)
    local tabs = spellbook()
    if #tabs == 0 then root:CreateTitle("Your spellbook is empty.") end
    for _, t in ipairs(tabs) do
        local sub = root:CreateButton(t.name)
        for _, spell in ipairs(t.spells) do sub:CreateButton(spell, function() fn(spell) end) end
        if sub.SetScrollMode then sub:SetScrollMode(400) end
    end
end

-- Toolbar: on the tabs' row, and Revert changes beside the name -------------------------------------------------------

local newButton = Button(detail, "New macro", 100)
newButton:SetPoint("TOPRIGHT", -12, -59)
local galleryButton = Button(detail, "Ready-made", 100)
galleryButton:SetPoint("RIGHT", newButton, "LEFT", -6, 0)
local revertButton = Button(detail, "Revert changes", 130)
revertButton:SetPoint("TOPRIGHT", -12, -13)
frame.newMacroButton, frame.galleryButton, frame.revertButton = newButton, galleryButton, revertButton

-- Macro editor -------------------------------------------------------------------------------------------------------

local ed = CreateFrame("Frame", nil, content)
ed:SetPoint("TOPLEFT", 0, -TOP)
ed:SetSize(W, 250)
ed:Hide()
frame.macroEditor = ed
local ED_H = 250

ed.icon = CreateFrame("Button", nil, ed)
ed.icon:SetSize(36, 36)
ed.icon:SetPoint("TOPLEFT")
ed.icon.texture = ed.icon:CreateTexture(nil, "ARTWORK")
ed.icon.texture:SetAllPoints()
local iconHl = ed.icon:CreateTexture(nil, "HIGHLIGHT")
iconHl:SetAllPoints()
iconHl:SetColorTexture(1, 1, 1, 0.15)
ed.icon:SetScript("OnEnter", function(self) St.Tooltip(self, "Icon", {"Click to pick another."}) end)
ed.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)

ed.name = CreateFrame("EditBox", nil, ed, "InputBoxTemplate")
ed.name:SetPoint("TOPLEFT", 50, -8)
ed.name:SetSize(150, 20)
ed.name:SetAutoFocus(false)
ed.name:SetMaxLetters(L.MACRO_NAME)

local function editedMacro()
    local lo = current()
    return lo, lo and editing and lo.macros[editing]
end
ed.scope = St.MenuButton(ed, 170, function()
    local _, m = editedMacro()
    return m and m.account and "Account macro" or "Character macro"
end, function(root)
    for _, s in ipairs({{"character", "Character macro (this character)"}, {"account", "Account macro (every character)"}}) do
        root:CreateRadio(s[2], function() local _, m = editedMacro(); return m and L.scope(m) == s[1] end, function()
            local lo, m = editedMacro()
            if not m then return end
            local ok, why = L.setMacro(lo, editing, {account = s[1] == "account"})
            ed.problem:SetText(ok and "" or why)
            refresh()
        end, s[1])
    end
end)
ed.scope:SetPoint("TOPLEFT", 214, -7)

ed.textPane = Pane(ed)
ed.textPane:SetPoint("TOPLEFT", 0, -44)
ed.textPane:SetSize(W, 110)
local textScroll = CreateFrame("ScrollFrame", nil, ed.textPane, "ScrollFrameTemplate")
textScroll:SetPoint("TOPLEFT", 8, -8)
textScroll:SetPoint("BOTTOMRIGHT", -26, 8)
ed.box = CreateFrame("EditBox", nil, textScroll)
ed.box:SetMultiLine(true)
ed.box:SetAutoFocus(false)
ed.box:SetFontObject("ChatFontNormal")
ed.box:SetWidth(W - 34)
textScroll:SetScrollChild(ed.box)
ed.textPane:EnableMouse(true)
ed.textPane:SetScript("OnMouseDown", function() ed.box:SetFocus() end)
ed.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

ed.count = Text(ed, "GameFontHighlightSmall")
ed.count:SetPoint("TOPRIGHT", 0, -158)
ed.count:SetJustifyH("RIGHT")
ed.problem = Text(ed, "GameFontNormalSmall") -- why the last change wasn't saved
ed.problem:SetPoint("TOPLEFT", 0, -158)
ed.problem:SetPoint("RIGHT", ed.count, "LEFT", -8, 0)
ed.problem:SetTextColor(1, 0.3, 0.3)

-- Helpers: pieces of macro text, inserted where the cursor is
local HELPERS = {
    {"#showtooltip", "#showtooltip\n"}, {"On mouseover, friendly", "[@mouseover,help,nodead]"},
    {"On mouseover, enemy", "[@mouseover,harm,nodead]"}, {"With Shift held", "[mod:shift]"}, {"In combat", "[combat]"},
    {"/stopcasting", "/stopcasting\n"}, {"/cast", "/cast "}, {"/use 13 (top trinket)", "/use 13\n"},
    {"/use 14 (bottom trinket)", "/use 14\n"}, {"/startattack", "/startattack\n"}, {"/targetenemy", "/targetenemy\n"},
}
local function insert(text)
    ed.box:SetFocus()
    ed.box:Insert(text)
end
ed.insert = St.MenuButton(ed, 120, function() return "Insert" end, function(root)
    for _, h in ipairs(HELPERS) do root:CreateButton(h[1], function() insert(h[2]) end) end
end)
ed.insert:SetPoint("TOPLEFT", 0, -178)
ed.insert:Refresh()
ed.spell = St.MenuButton(ed, 120, function() return "Insert spell" end, function(root)
    spellMenu(root, function(spell) insert("/cast " .. spell .. "\n") end)
end)
ed.spell:SetPoint("LEFT", ed.insert, "RIGHT", 6, 0)
ed.spell:Refresh()
ed.readyButton = Button(ed, "Ready-made options", 150)
ed.readyButton:SetPoint("LEFT", ed.spell, "RIGHT", 6, 0)
ed.warning = Text(ed, "GameFontDisableSmall") -- spells you don't know
ed.warning:SetPoint("TOPLEFT", 0, -206)
ed.warning:SetWidth(W)
ed.warning:SetWordWrap(true)
ed.back = Button(ed, "Back to macros", 130)
ed.back:SetPoint("TOPLEFT", 0, -226)
ed.delete = Button(ed, "Delete macro", 120)
ed.delete:SetPoint("TOPRIGHT", 0, -226)

local function showCount(text)
    local over = #text > L.MACRO_TEXT
    ed.count:SetText(("%s%d / %d|r"):format(over and "|cffff4040" or "|cffffffff", #text, L.MACRO_TEXT))
    if over then
        ed.problem:SetText(("Too long: not saved until it's %d characters or less."):format(L.MACRO_TEXT))
    elseif ed.problem:GetText() and ed.problem:GetText():find("^Too long") then
        ed.problem:SetText("")
    end
    local missing = L.unknownSpells(text)
    ed.warning:SetText(#missing == 0 and "" or ("|cffff8040You don't know %s.|r That's fine if the loadout is for "
        .. "another character."):format(table.concat(missing, ", ")))
end

-- Boxes that save when you leave them keep what they were opened for (box.target, set on focus), so the save goes
-- there even after you've picked another loadout, macro or tab; commitPending saves them before such a switch.
local function saveName(box, quiet)
    local t = box.target
    box.target = nil
    local m = t and t.lo.macros[t.index]
    if not m then return end
    local name = ns.trim(box:GetText())
    if name == m.name then return end
    local ok, why = L.setMacro(t.lo, t.index, {name = name})
    if t.lo == current() then ed.problem:SetText(ok and "" or why) end
    if ok and not quiet then refresh() end
end
local function commitPending()
    if ed.name.target then
        saveName(ed.name, true)
        ed.name:ClearFocus()
    end
    for _, r in ipairs(U.lines) do
        if r.box and r.box.target then
            r.box.save(r.box)
            r.box:ClearFocus()
        end
    end
end
ed.name:SetScript("OnEditFocusGained", function(self) self.target = {lo = current(), index = editing} end)
ed.name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
ed.name:SetScript("OnEditFocusLost", function(self) saveName(self) end)
ed.name:SetScript("OnEscapePressed", function(self)
    self.target = nil
    local _, m = editedMacro()
    if m then self:SetText(m.name) end
    self:ClearFocus()
end)

U.commitPending = commitPending

local function openMacro(i)
    commitPending()
    local lo = current()
    local m = lo and lo.macros[i]
    if not m then return end
    view, editing = "macro", i
    ed.name:SetText(m.name)
    ed.box:SetText(m.body or "")
    ed.problem:SetText("")
    showCount(m.body or "")
    refresh()
end
ed.box:SetScript("OnTextChanged", function(self)
    local lo, m = editedMacro()
    if view ~= "macro" or not m then return end
    local text = self:GetText() or ""
    showCount(text)
    if text ~= m.body and #text <= L.MACRO_TEXT then
        local ok, why = L.setMacro(lo, editing, {body = text})
        if not ok then ed.problem:SetText(why) end
        revertButton:Show()
    end
end)
ed.back:SetScript("OnClick", function()
    commitPending()
    view, editing = "list", nil
    refresh()
end)

-- Delete and Revert ask first; what they act on is kept in a local
local asking
local function confirm(which, text, fn)
    StaticPopupDialogs[which] = {text = text, button1 = YES or "Yes", button2 = NO or "No",
        OnAccept = function() if asking and ns.IsOn("loadouts") then fn(asking) end end,
        timeout = 0, whileDead = true, hideOnEscape = true}
    StaticPopup_Show(which)
end
local function askDelete(lo, i)
    local m = lo.macros[i]
    if not m then return end
    asking = {lo = lo, macro = m}
    confirm("KUREQUTILS_DELETE_MACRO", ("Delete the macro %s from %s? Slots and keys using it are cleared too.")
        :format(m.name, lo.name), function(a)
        for j, x in ipairs(a.lo.macros) do
            if x == a.macro then
                L.deleteMacro(a.lo, j)
                if current() == a.lo then view, editing = "list", nil end
                say("Deleted the macro " .. x.name .. ".")
                return refresh()
            end
        end
    end)
end
ed.delete:SetScript("OnClick", function()
    local lo = editedMacro()
    if lo and editing then askDelete(lo, editing) end
end)
revertButton:SetScript("OnClick", function()
    local lo = current()
    if not (lo and L.edited(lo)) then return end
    asking = lo
    confirm("KUREQUTILS_REVERT_LOADOUT", ("Put %s back as it was when you opened the window?"):format(lo.name),
        function(target)
            commitPending() -- saved first, so a box left open can't write over what's put back
            L.revert(target)
            view, editing = "list", nil
            say("Put back as it was.")
            refresh()
        end)
end)

newButton:SetScript("OnClick", function()
    local lo = current()
    if not lo then return end
    local name, n = "New macro", 1
    while L.findMacro(lo, name) do
        n = n + 1
        name = "New macro " .. n
    end
    local i, why = L.addMacro(lo, {name = name, body = ""})
    if not i then return say(why) end
    openMacro(i)
end)

-- Icon picker: Blizzard's macro icons, a page at a time --------------------------------------------------------------

local COLS, ROWS, CELL = 10, 5, 36
local iconDialog = U.Dialog(COLS * CELL + 24, ROWS * CELL + 110)
iconDialog.title:SetText("Pick an icon")
iconDialog.ok:Hide()
iconDialog.cancel:SetText("Close")
local iconList
local function allIcons()
    if iconList then return iconList end
    local raw = {}
    for _, fill in ipairs({GetLooseMacroIcons or false, GetLooseMacroItemIcons or false, GetMacroIcons or false,
        GetMacroItemIcons or false}) do
        if fill then fill(raw) end
    end
    iconList = {QUESTION_MARK}
    for _, t in ipairs(raw) do iconList[#iconList + 1] = tonumber(t) or t end
    return iconList
end
local page = 1
local cells = {}
local function showPage()
    local list = allIcons()
    local pages = math.max(1, math.ceil(#list / (COLS * ROWS)))
    page = math.min(math.max(page, 1), pages)
    for n, b in ipairs(cells) do
        local icon = list[(page - 1) * COLS * ROWS + n]
        b.value = icon
        b.texture:SetTexture(icon and L.iconPath(icon))
        b:SetShown(icon ~= nil)
    end
    iconDialog.text:SetText(("Page %d of %d. A question mark shows the spell the macro casts."):format(page, pages))
end
for n = 1, COLS * ROWS do
    local b = CreateFrame("Button", nil, iconDialog)
    b:SetSize(CELL - 4, CELL - 4)
    b:SetPoint("TOPLEFT", 12 + ((n - 1) % COLS) * CELL, -58 - math.floor((n - 1) / COLS) * CELL)
    b.texture = b:CreateTexture(nil, "ARTWORK")
    b.texture:SetAllPoints()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.2)
    b:SetScript("OnClick", function(self)
        local lo, m = editedMacro()
        iconDialog:Hide()
        if not m then return end
        L.setMacro(lo, editing, {icon = self.value})
        refresh()
    end)
    cells[n] = b
end
local prevPage = Button(iconDialog, "Previous", 90)
prevPage:SetPoint("BOTTOMLEFT", 12, 12)
prevPage:SetScript("OnClick", function() page = page - 1; showPage() end)
local nextPage = Button(iconDialog, "Next", 90)
nextPage:SetPoint("LEFT", prevPage, "RIGHT", 8, 0)
nextPage:SetScript("OnClick", function() page = page + 1; showPage() end)
frame.iconDialog, frame.iconCells, frame.iconNext = iconDialog, cells, nextPage
ed.icon:SetScript("OnClick", function()
    showPage()
    iconDialog:Show()
end)

-- Ready-made macros: a gallery of cards, then a card's options --------------------------------------------------------

local gallery = CreateFrame("Frame", nil, content)
gallery:SetPoint("TOPLEFT", 0, -TOP)
gallery:Hide()
local CARD_W, CARD_H = math.floor((W - 8) / 2), 64
local cards = {}
for n, r in ipairs(L.READY) do
    local card = CreateFrame("Button", nil, gallery)
    card:SetSize(CARD_W, CARD_H)
    card:SetPoint("TOPLEFT", ((n - 1) % 2) * (CARD_W + 8), -math.floor((n - 1) / 2) * (CARD_H + 8))
    local pane = Pane(card)
    pane:SetAllPoints()
    local hl = card:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(32, 32)
    card.icon:SetPoint("TOPLEFT", 12, -12)
    card.icon:SetTexture(r.icon)
    card.title = Text(card, "GameFontHighlight")
    card.title:SetPoint("TOPLEFT", 52, -12)
    card.title:SetPoint("RIGHT", -10, 0)
    card.title:SetText(r.name)
    card.sub = Text(card, "GameFontDisableSmall")
    card.sub:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
    card.sub:SetPoint("RIGHT", -10, 0)
    card.sub:SetHeight(24)
    card.sub:SetWordWrap(true)
    card.sub:SetJustifyV("TOP")
    card.sub:SetText(r.text)
    card.kind = r.kind
    cards[n] = card
end
gallery:SetSize(W, math.ceil(#L.READY / 2) * (CARD_H + 8))
frame.readyCards = cards

local form = CreateFrame("Frame", nil, content)
form:SetPoint("TOPLEFT", 0, -TOP)
form:SetSize(W, 300)
form:Hide()
frame.readyForm = form
local ROW = 30
local rows = {} -- option key -> its row
local preview -- the macro text the options write
local function updatePreview()
    local text = L.readyText(readyKind, readyOptions) or ""
    preview:SetText("|cff999999" .. text .. "|r")
    form.text = text
    form.problem:SetText(#text > L.MACRO_TEXT and ("Too long: %d of %d characters."):format(#text, L.MACRO_TEXT) or "")
end
local function setOption(key, value)
    readyOptions[key] = value
    updatePreview()
    for _, row in pairs(rows) do
        if row.menu then row.menu:Refresh() end
    end
end
for key, o in pairs(L.READY_OPTIONS) do
    local row = CreateFrame("Frame", nil, form)
    row:SetSize(W, ROW)
    row.label = Text(row, "GameFontNormalSmall")
    row.label:SetPoint("LEFT")
    row.label:SetText(o.label)
    if o.type == "spell" or o.type == "text" then
        row.box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        row.box:SetPoint("LEFT", 126, 0)
        row.box:SetSize(o.type == "spell" and 180 or 280, 20)
        row.box:SetAutoFocus(false)
        row.box:SetMaxLetters(200)
        if o.prompt then Prompt(row.box, o.prompt) end
        row.box:SetScript("OnTextChanged", function(self) if readyOptions then setOption(key, self:GetText() or "") end end)
        row.box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        row.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    end
    if o.type == "spell" then
        row.pick = St.MenuButton(row, 110, function() return "Spellbook" end, function(root)
            spellMenu(root, function(spell)
                row.box:SetText(spell)
                setOption(key, spell)
            end)
        end)
        row.pick:SetPoint("LEFT", row.box, "RIGHT", 8, 0)
        row.pick:Refresh()
    elseif o.type == "choice" then
        row.menu = St.MenuButton(row, 200, function()
            local v = readyOptions and readyOptions[key]
            for _, c in ipairs(o.choices) do
                if c[1] == v then return c[2] end
            end
            return ""
        end, function(root)
            for _, c in ipairs(o.choices) do
                root:CreateRadio(c[2], function() return readyOptions and readyOptions[key] == c[1] end,
                    function() setOption(key, c[1]) end, c[1])
            end
        end)
        row.menu:SetPoint("LEFT", 120, 0)
    elseif o.type == "check" then
        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetSize(24, 24)
        row.check:SetPoint("LEFT", 120, 0)
        row.check:SetScript("OnClick", function(self) setOption(key, self:GetChecked() and true or false) end)
    end
    row:Hide()
    rows[key] = row
end
form.rows = rows
form.title = Text(form, "GameFontNormal")
form.title:SetPoint("TOPLEFT")
form.nameLabel = Text(form, "GameFontNormalSmall")
form.nameLabel:SetText("Macro name")
form.name = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
form.name:SetSize(150, 20)
form.name:SetAutoFocus(false)
form.name:SetMaxLetters(L.MACRO_NAME)
local namePrompt = Prompt(form.name, "Or the spell's name")
form.name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
form.name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
preview = Text(form, "GameFontHighlightSmall")
preview:SetWidth(W)
preview:SetWordWrap(true)
form.preview = preview
form.problem = Text(form, "GameFontNormalSmall")
form.problem:SetTextColor(1, 0.3, 0.3)
form.add = Button(form, "Add to loadout", 140)
form.back = Button(form, "Back", 90)
form.back:SetPoint("LEFT", form.add, "RIGHT", 8, 0)

local function layoutForm()
    local r = L.READY[readyKind]
    form.title:SetText(r.name .. " · |cff999999" .. r.text .. "|r")
    for _, row in pairs(rows) do row:Hide() end
    local y = -24
    for _, key in ipairs(r.options) do
        local row, v = rows[key], readyOptions[key]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, y)
        row:Show()
        if row.box then row.box:SetText(v or "") end
        if row.check then row.check:SetChecked(v == true) end
        if row.menu then row.menu:Refresh() end
        y = y - ROW
    end
    form.nameLabel:SetPoint("TOPLEFT", 0, y - 9)
    form.name:SetPoint("TOPLEFT", 126, y - 4)
    preview:SetPoint("TOPLEFT", 0, y - 34)
    form.problem:SetPoint("TOPLEFT", 0, y - 90)
    form.add:SetPoint("TOPLEFT", 0, y - 108)
    form.add:SetText(editing and "Save macro" or "Add to loadout")
    form:SetHeight(-(y - 108) + 24)
    updatePreview()
end

local function openReady(kind, i)
    commitPending()
    local lo = current()
    local m = lo and i and lo.macros[i]
    view, editing, readyKind = "ready", i, kind
    readyOptions = L.readyOptions(kind, m and m.options)
    layoutForm()
    local name = m and m.name or (readyOptions.spell ~= nil and "" or L.READY[kind].name)
    form.name:SetText(name:sub(1, L.MACRO_NAME))
    namePrompt:SetShown(name == "")
    refresh()
end
for _, card in ipairs(cards) do card:SetScript("OnClick", function(self) openReady(self.kind) end) end
ed.readyButton:SetScript("OnClick", function()
    local _, m = editedMacro()
    if m and L.READY[m.kind] then openReady(m.kind, editing) end
end)
galleryButton:SetScript("OnClick", function()
    commitPending()
    view, editing = "gallery", nil
    refresh()
end)
form.back:SetScript("OnClick", function()
    if editing then return openMacro(editing) end
    view = "gallery"
    refresh()
end)
form.add:SetScript("OnClick", function()
    local lo = current()
    if not lo then return end
    local text = L.readyText(readyKind, readyOptions)
    local name = ns.trim(form.name:GetText())
    if name == "" then name = ns.trim(readyOptions.spell or ""):sub(1, L.MACRO_NAME) end
    if name == "" then name = L.READY[readyKind].name:sub(1, L.MACRO_NAME) end
    local options = {}
    for k, v in pairs(readyOptions) do options[k] = v end
    local fields = {name = name, body = text, kind = readyKind, options = options,
        icon = text:find("^#showtooltip") and QUESTION_MARK or L.READY[readyKind].icon}
    local i, why
    if editing and lo.macros[editing] then
        fields.icon = nil -- keeps the icon picked
        i, why = L.setMacro(lo, editing, fields)
        i = i and editing
    else
        i, why = L.addMacro(lo, fields)
    end
    if not i then return form.problem:SetText(why) end
    say((editing and "Saved the macro %s." or "Added the macro %s to the loadout."):format(name))
    openMacro(i)
end)

-- Bars: drop from the cursor, drag to move, right-click to clear --------------------------------------------------------

local function cursorAction()
    local kind, a, _, spellID = GetCursorInfo()
    if kind == "spell" and spellID then
        return {type = "spell", id = spellID, name = (L.spellInfo(spellID))}
    elseif kind == "item" and a then
        return {type = "item", id = a}
    elseif kind == "macro" and a then
        local name = GetMacroInfo(a)
        return name and {type = "macro", name = name}
    end
    return nil, kind
end
local function drop(slot)
    local lo = current()
    if not lo or not GetCursorInfo() then return false end
    if InCombatLockdown() then
        say("Drop things on a loadout's bars out of combat.")
        return true
    end
    local action = cursorAction()
    ClearCursor()
    if not action then
        say("Only spells, items and macros go on a loadout's bars.")
    else
        L.setSlot(lo, slot, action)
        say("")
    end
    refresh()
    return true
end
local dragging
for slot, b in pairs(frame.icons) do
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnReceiveDrag", function() drop(slot) end)
    b:SetScript("OnClick", function(self, button)
        local lo = current()
        if not lo then return end
        if button == "RightButton" then -- one of the loadout's macros (even one only it has), or clear
            MenuUtil.CreateContextMenu(self, function(_, root)
                local put = root:CreateButton("Put a macro")
                if #lo.macros == 0 then put:CreateTitle("The loadout has no macros yet.") end
                for _, m in ipairs(lo.macros) do
                    put:CreateButton(m.name, function()
                        L.setSlot(lo, slot, {type = "macro", name = m.name})
                        refresh()
                    end)
                end
                if lo.actions[slot] then
                    root:CreateButton("Clear", function()
                        L.setSlot(lo, slot, nil)
                        refresh()
                    end)
                end
            end)
        else
            drop(slot)
        end
    end)
    b:SetScript("OnDragStart", function()
        local lo = current()
        dragging = lo and lo.actions[slot] and slot or nil
    end)
    b:SetScript("OnDragStop", function()
        local lo, from = current(), dragging
        dragging = nil
        if not (lo and from) then return end
        for to, other in pairs(frame.icons) do
            if other:IsVisible() and other:IsMouseOver() then
                L.swapSlots(lo, from, to)
                return refresh()
            end
        end
    end)
end

-- Bindings: click a key to change it, right-click to clear it, Add a binding for the loadout's macros and buttons -----

local catcher = CreateFrame("Frame", nil, detail) -- takes the next key press while listening
catcher:SetAllPoints()
catcher:EnableKeyboard(false)
frame.keyCatcher = catcher
local function stopListening()
    listening = nil
    catcher:EnableKeyboard(false)
end
local function listen(command, old)
    listening = {command, old}
    catcher:EnableKeyboard(true)
    say(("Press a key for %s (with Shift, Ctrl or Alt if you like). Escape cancels."):format(actionName(command)))
end
catcher:SetScript("OnKeyDown", function(_, key)
    if not listening then return end
    if key == "ESCAPE" then
        stopListening()
        return say("Not changed.")
    end
    if IsMetaKey and IsMetaKey(key) then return end -- wait for the key it goes with
    local chord = CreateKeyChordStringUsingMetaKeyState and CreateKeyChordStringUsingMetaKeyState(key) or key
    local command, old = listening[1], listening[2]
    stopListening()
    local lo = current()
    if not lo then return end
    local from = L.bind(lo, command, chord, old)
    local text = GetBindingText and GetBindingText(chord) or chord
    say(("Bound %s to %s."):format(text, actionName(command))
        .. (from and (" It was on %s."):format(actionName(from)) or ""))
    refresh()
end)
-- the loadout's macros, and the bar buttons it puts something on
local BUTTONS = {{1, "ACTIONBUTTON"}, {6, "MULTIACTIONBAR1BUTTON"}, {5, "MULTIACTIONBAR2BUTTON"},
    {3, "MULTIACTIONBAR3BUTTON"}, {4, "MULTIACTIONBAR4BUTTON"}}
local addBinding = St.MenuButton(detail, 130, function() return "Add a binding" end, function(root)
    local lo = current()
    if not lo then return end
    for _, m in ipairs(lo.macros) do
        local command = "MACRO " .. m.name
        root:CreateButton(actionName(command), function() listen(command) end)
    end
    for _, bar in ipairs(BUTTONS) do
        for i = 1, 12 do
            if lo.actions[(bar[1] - 1) * 12 + i] then
                local command = bar[2] .. i
                root:CreateButton(actionName(command), function() listen(command) end)
            end
        end
    end
    if root.SetScrollMode then root:SetScrollMode(400) end
end)
addBinding:SetPoint("TOPRIGHT", -12, -59)
addBinding:Refresh()
frame.addBinding = addBinding

-- Lines: what clicking each does, and the Settings tab's boxes ------------------------------------------------------------

local function lineClick(r, button)
    local lo = current()
    if not (lo and r.data) then return end
    if shownTab == "macros" then
        if button ~= "RightButton" then return openMacro(r.data) end
        local i = r.data
        MenuUtil.CreateContextMenu(r, function(_, root)
            root:CreateButton("Edit", function() openMacro(i) end)
            if i > 1 then root:CreateButton("Move up", function() L.moveMacro(lo, i, -1); refresh() end) end
            if i < #lo.macros then root:CreateButton("Move down", function() L.moveMacro(lo, i, 1); refresh() end) end
            root:CreateButton("Delete", function() askDelete(lo, i) end)
        end)
    elseif shownTab == "bindings" then
        local command, key = r.data[1], r.data[2]
        if button == "RightButton" then
            L.unbind(lo, command, key)
            say(("Cleared %s from %s."):format(GetBindingText and GetBindingText(key) or key, actionName(command)))
            return refresh()
        end
        listen(command, key)
    end
end

local function settingWidgets(r)
    if r.box then return end
    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetSize(22, 22)
    r.check:SetPoint("LEFT", 186, 0)
    r.check:SetScript("OnClick", function(self)
        local lo = current()
        if lo then L.setSetting(lo, r.data, self:GetChecked() and "1" or "0") end
        refresh()
    end)
    r.box = CreateFrame("EditBox", nil, r, "InputBoxTemplate")
    r.box:SetPoint("LEFT", 196, 0)
    r.box:SetSize(120, 18)
    r.box:SetAutoFocus(false)
    r.box:SetMaxLetters(256)
    function r.box.save(self) -- to the loadout and setting the box was opened for (see commitPending)
        local t = self.target
        self.target = nil
        if not (t and t.lo.cvars[t.name]) then return end
        local ok, why = L.setSetting(t.lo, t.name, self:GetText() or "")
        if not ok then
            say(why)
            if t.lo == current() and r.data == t.name then self:SetText(t.lo.cvars[t.name]) end
        end
    end
    r.box:SetScript("OnEditFocusGained", function(self) self.target = {lo = current(), name = r.data} end)
    r.box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    r.box:SetScript("OnEditFocusLost", function(self) self.save(self) end)
    r.box:SetScript("OnEscapePressed", function(self)
        self.target = nil
        local lo = current()
        if lo and lo.cvars[r.data] then self:SetText(lo.cvars[r.data]) end
        self:ClearFocus()
    end)
    r.hint = Text(r, "GameFontDisableSmall")
    r.hint:SetPoint("LEFT", r.box, "RIGHT", 8, 0)
    r.hint:SetText("text, not checked")
    r.remove = Button(r, "Remove", 70)
    r.remove:SetHeight(18)
    r.remove:SetPoint("RIGHT")
    r.remove:SetScript("OnClick", function()
        local lo = current()
        if not (lo and r.data) then return end
        L.removeSetting(lo, r.data)
        say(("Took %s out of the loadout."):format(L.settingName(r.data)))
        refresh()
    end)
end

local function decorateLine(r, tab, lo, editable)
    r:SetScript("OnClick", editable and (tab == "macros" or tab == "bindings") and lineClick or nil)
    local setting = editable and tab == "cvars" and r.data and lo.cvars[r.data]
    r.value:SetShown(not setting)
    if not setting then
        if r.box then
            for _, part in ipairs({r.check, r.box, r.hint, r.remove}) do part:Hide() end
        end
        return
    end
    settingWidgets(r)
    local kind = L.settingKind(setting)
    r.check:SetShown(kind == "toggle")
    r.check:SetChecked(setting == "1")
    r.box:SetShown(kind ~= "toggle")
    r.hint:SetShown(kind == "text")
    if not r.box:HasFocus() then r.box:SetText(setting) end
    r.remove:Show()
end

-- Called by the window after it draws a tab: the editor's views and controls; returns the content's height --------------

local function macroSummary(lo)
    local n = L.macroCounts(lo)
    if #lo.macros == 0 then return "No macros yet. Click New macro to write one, or Ready-made to start from one." end
    return ("%s. %d of %d character macros, %d of %d account ones. Click one to edit it, right-click for more.")
        :format(count(#lo.macros, "macro", "macros"), n.character, L.MACRO_CAPS.character, n.account,
            L.MACRO_CAPS.account)
end

function U.decorate(tab, lo, isBackup, height)
    local editable = not isBackup
    if lo ~= shownLo or tab ~= shownTab then
        commitPending()
        view, editing = "list", nil
        stopListening()
        shownLo, shownTab = lo, tab
    end
    newButton:SetShown(editable and tab == "macros")
    galleryButton:SetShown(editable and tab == "macros")
    addBinding:SetShown(editable and tab == "bindings")
    revertButton:SetShown(editable and L.edited(lo))
    ed:SetShown(false)
    gallery:SetShown(false)
    form:SetShown(false)
    for _, r in ipairs(U.lines) do decorateLine(r, tab, lo, editable) end
    if not editable then return height end
    if tab == "bars" then
        summary:SetText(summary:GetText() .. (InCombatLockdown() and " |cffff8040Out of combat, drop spells, items "
            .. "and macros on its slots.|r" or ""))
        return height
    elseif tab == "bindings" then
        summary:SetText(summary:GetText() .. " Click a key to change it, right-click to clear it.")
        return height
    elseif tab ~= "macros" then
        return height
    end
    if view == "macro" and not lo.macros[editing] then view, editing = "list", nil end
    if view == "list" then
        summary:SetText(macroSummary(lo))
        return height
    end
    for _, r in ipairs(U.lines) do r:Hide() end
    if view == "macro" then
        local m = lo.macros[editing]
        summary:SetText(("Editing %s: changes save as you type, to the loadout only."):format(m.name))
        ed:Show()
        ed.icon.texture:SetTexture(L.iconPath(m.icon))
        ed.scope:Refresh()
        ed.readyButton:SetShown(L.READY[m.kind] ~= nil)
        if not ed.name:HasFocus() then ed.name:SetText(m.name) end
        return ED_H
    elseif view == "gallery" then
        summary:SetText("Ready-made macros: pick one, set its options, and it writes the macro for you.")
        gallery:Show()
        return gallery:GetHeight()
    end
    summary:SetText(editing and "Changing the options rewrites the macro's text." or "Set the options, then add it.")
    form:Show()
    return form:GetHeight()
end

frame:HookScript("OnHide", function()
    L.endEdits()
    stopListening()
    iconDialog:Hide()
    view, editing, shownLo = "list", nil, nil
end)
ns.OnModuleChange("loadouts", function(on)
    if on then return end
    stopListening()
    iconDialog:Hide()
    for _, which in ipairs({"KUREQUTILS_DELETE_MACRO", "KUREQUTILS_REVERT_LOADOUT"}) do StaticPopup_Hide(which) end
end)
