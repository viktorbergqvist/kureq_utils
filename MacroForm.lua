-- Macro editing pieces the loadouts editor (LoadoutsEditor.lua) and the macros window (MacrosWindow.lua) share, on
-- ns.loadouts: buttons, grey prompts and dialogs; your spellbook as a menu; the macro form (icon, name, character or
-- account, the text with its count, helpers and a spell picker); Blizzard's macro icons in a picker; a ready-made
-- macro's card and its options form. Each window decides what a change saves to.
local _, ns = ...
local L, St = ns.loadouts, ns.style
local Pane, Text = St.Pane, St.Text
local QUESTION_MARK = 134400
L.QUESTION_MARK = QUESTION_MARK

function L.Button(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    return b
end

-- A grey prompt in an empty InputBoxTemplate box
function L.Prompt(box, text)
    local prompt = Text(box, "GameFontDisable")
    prompt:SetPoint("LEFT", 2, 0)
    prompt:SetText(text)
    box:SetScript("OnEditFocusGained", function() prompt:Hide() end)
    box:SetScript("OnEditFocusLost", function(self) prompt:SetShown((self:GetText() or "") == "") end)
    return prompt
end

-- A pane over owner, centered on it: a title, a grey text, OK and Cancel
function L.Dialog(owner, w, h)
    local d = Pane(owner)
    d:SetFrameStrata("DIALOG")
    d:SetToplevel(true)
    d:EnableMouse(true) -- clicks don't fall through to the window
    d:SetSize(w, h)
    d:SetPoint("CENTER", owner, "CENTER")
    d:Hide()
    d.title = Text(d, "GameFontNormalLarge")
    d.title:SetPoint("TOPLEFT", 12, -12)
    d.title:SetPoint("RIGHT", -12, 0)
    d.text = Text(d, "GameFontDisableSmall")
    d.text:SetPoint("TOPLEFT", 12, -36)
    d.text:SetPoint("RIGHT", -12, 0)
    d.text:SetWordWrap(true)
    d.cancel = L.Button(d, "Cancel", 90)
    d.cancel:SetPoint("BOTTOMRIGHT", -12, 12)
    d.cancel:SetScript("OnClick", function() d:Hide() end)
    d.ok = L.Button(d, "OK", 90)
    d.ok:SetPoint("RIGHT", d.cancel, "LEFT", -8, 0)
    return d
end

-- Your spellbook: {name = its tab, spells = {names}}, active spells only (passive ones too when withPassive), each name once
function L.spellbook(withPassive)
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
                    if item and item.itemType == spellType and (withPassive or not item.isPassive) then add(list, seen, item.name) end
                end
                if #list > 0 then tabs[#tabs + 1] = {name = line.name, spells = list} end
            end
        end
    elseif GetNumSpellTabs then
        for i = 1, GetNumSpellTabs() do
            local name, _, offset, n = GetSpellTabInfo(i)
            local list, seen = {}, {}
            for slot = offset + 1, offset + n do
                if withPassive or not IsPassiveSpell(slot, "spell") then add(list, seen, (GetSpellBookItemName(slot, "spell"))) end
            end
            if #list > 0 then tabs[#tabs + 1] = {name = name, spells = list} end
        end
    end
    return tabs
end
-- A menu of your spellbook, a submenu per tab; picking a spell calls fn(name)
function L.spellMenu(root, fn)
    local tabs = L.spellbook()
    if #tabs == 0 then root:CreateTitle("Your spellbook is empty.") end
    for _, t in ipairs(tabs) do
        local sub = root:CreateButton(t.name)
        for _, spell in ipairs(t.spells) do sub:CreateButton(spell, function() fn(spell) end) end
        if sub.SetScrollMode then sub:SetScrollMode(400) end
    end
end

-- The macro form ---------------------------------------------------------------------------------------------------

-- Helpers: pieces of macro text, inserted where the cursor is
L.HELPERS = {
    {"#showtooltip", "#showtooltip\n"}, {"On mouseover, friendly", "[@mouseover,help,nodead,exists][@target,help,nodead,exists][@player]"},
    {"On mouseover, enemy", "[@mouseover,harm,nodead,exists][@target,harm,nodead,exists]"}, {"With Shift held", "[mod:shift]"}, {"In combat", "[combat]"},
    {"/stopcasting", "/stopcasting\n"}, {"/cast", "/cast "}, {"/use 13 (top trinket)", "/use 13\n"},
    {"/use 14 (bottom trinket)", "/use 14\n"}, {"/startattack", "/startattack\n"}, {"/targetenemy", "/targetenemy\n"},
}

-- The form, W wide and 108 + codeH high (codeH, the code panel's height, is 110 unless given; place it with SetPoint):
-- ed.icon (a button; the window opens the icon picker), ed.name, ed.scope (scope.get() is "character", "account" or
-- nil; picking one calls scope.set(account)), ed.code (the code editor, MacroEditor.lua) and ed.box its EditBox,
-- ed.count, ed.problem (why the last change wasn't saved), Insert and Insert spell. Spells you don't know are
-- underlined in the code, with note after why. ed.showCount(text) says when the text is too long. The window hooks
-- the boxes' scripts (HookScript on ed.box, the editor keeps its own): what a change saves to is its business.
-- ed:SetFormSize(W, codeH) resizes it (codeH kept when nil).
function L.MacroForm(parent, W, scope, note, codeH)
    codeH = codeH or 110
    local ed = CreateFrame("Frame", nil, parent)

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

    ed.name = St.EditBox(ed)
    ed.name:SetPoint("TOPLEFT", 50, -8)
    ed.name:SetWidth(150)
    ed.name:SetMaxLetters(L.MACRO_NAME)

    ed.scope = St.Dropdown(ed, 170, function()
        return scope.get() == "account" and "Account macro" or "Character macro"
    end, function(root)
        for _, s in ipairs({{"character", "Character macro (this character)"}, {"account", "Account macro (every character)"}}) do
            root:CreateRadio(s[2], function() return scope.get() == s[1] end, function() scope.set(s[1] == "account") end, s[1])
        end
    end)
    ed.scope:SetPoint("TOPLEFT", 214, -7)

    local status = CreateFrame("Frame", nil, ed)
    ed.code = ns.macroCode.Editor(ed, W, codeH, status)
    ed.code:SetPoint("TOPLEFT", 0, -44)
    ed.code.note = note
    ed.box, ed.count = ed.code.edit, ed.code.length

    ed.problem = Text(ed, "GameFontNormalSmall")
    ed.problem:SetTextColor(1, 0.3, 0.3)

    local function insert(text)
        ed.box:SetFocus()
        ed.box:Insert(text)
    end
    ed.insert = St.MenuButton(ed, 120, function() return "Insert" end, function(root)
        for _, h in ipairs(L.HELPERS) do root:CreateButton(h[1], function() insert(h[2]) end) end
    end)
    ed.insert:Refresh()
    ed.spell = St.MenuButton(ed, 120, function() return "Insert spell" end, function(root)
        L.spellMenu(root, function(spell) insert("/cast " .. spell .. "\n") end)
    end)
    ed.spell:SetPoint("LEFT", ed.insert, "RIGHT", 6, 0)
    ed.spell:Refresh()
    function ed:SetFormSize(w, h)
        W, codeH = w, h or codeH
        ed:SetSize(W, 108 + codeH)
        status:SetPoint("TOPLEFT", 0, -(48 + codeH))
        status:SetSize(W, 16)
        ed.problem:SetPoint("TOPLEFT", 0, -(68 + codeH))
        ed.problem:SetWidth(W)
        ed.insert:SetPoint("TOPLEFT", 0, -(86 + codeH))
        if ed.code:GetWidth() ~= W or ed.code:GetHeight() ~= codeH then ed.code:SetEditorSize(W, codeH) end
    end
    ed:SetFormSize(W, codeH)
    function ed.showCount(text)
        ed.code:Refresh()
        if #text > L.MACRO_TEXT then
            ed.problem:SetText(("Too long: not saved until it's %d characters or less."):format(L.MACRO_TEXT))
        elseif ed.problem:GetText() and ed.problem:GetText():find("^Too long") then
            ed.problem:SetText("")
        end
    end
    return ed
end

-- Icon picker: Blizzard's macro icons, a page at a time, over owner, with a search by name and a Spells / Items / All
-- filter. The search finds your spells, mounts and items by name, then (from 2 letters on) every icon in the game by its
-- file name and category words (Data/Icons.lua). d:Open() shows it; picking one hides it and calls onPick(icon).
-- d.cells, d.nextPage, d.search and d.filters are for the tests.
local gameIcons -- {spell = {...}, item = {...}, all = {...}}: the game's lists, all in the game's order
local function allIcons()
    if gameIcons then return gameIcons end
    gameIcons = {spell = {}, item = {}, all = {}}
    for _, f in ipairs({{GetLooseMacroIcons, "spell"}, {GetLooseMacroItemIcons, "item"}, {GetMacroIcons, "spell"},
        {GetMacroItemIcons, "item"}}) do
        if f[1] then
            local raw = {}
            f[1](raw)
            for _, t in ipairs(raw) do
                local icon = tonumber(t) or t
                table.insert(gameIcons[f[2]], icon)
                table.insert(gameIcons.all, icon)
            end
        end
    end
    return gameIcons
end

-- The game's icon index (Data/Icons.lua, written by tools/update_icons.py), decoded on the first open into parallel
-- lists: indexIcons[i] the icon, indexFiles[i] its file name, indexWords[i] its category words ("item, weapon"),
-- indexUse[i] "I" (items use it), "S" (spells), "B" (both) or "" (neither); indexed: icon (its ID or its lowercase file
-- name) -> i. Lines are "P<name>|<icon><use>|<word>..." in base 36, P the characters shared with the name before.
local indexIcons, indexFiles, indexWords, indexUse, indexed
local function loadIndex()
    if indexIcons then return end
    indexIcons, indexFiles, indexWords, indexUse, indexed = {}, {}, {}, {}, {}
    local data, prev = ns.iconIndex, ""
    if not data then return end
    for line in data.icons:gmatch("[^\n]+") do
        local rest, icon, refs = line:match("^([^|]*)|([^|]+)(.*)$")
        prev = prev:sub(1, tonumber(rest:sub(1, 1), 36)) .. rest:sub(2)
        local words = {}
        for r in refs:gmatch("[^|]+") do words[#words + 1] = data.words[tonumber(r, 36)] end
        local id, use = icon:match("^([%da-z]+)(%u?)$")
        local n = #indexIcons + 1
        indexIcons[n], indexFiles[n], indexWords[n], indexUse[n] = tonumber(id, 36), prev, table.concat(words, ", "), use
        indexed[indexIcons[n]], indexed[prev] = n, indexed[prev] or n
    end
end
-- The index entry of an icon given as a file ID or a texture path ("INV_Sword_04", "Interface\\Icons\\x.blp"), or nil
local function indexOf(icon)
    if type(icon) ~= "string" then return indexed[icon] end
    return indexed[icon:lower():gsub("^.*[\\/]", ""):gsub("%.blp$", "")]
end
-- Whether index entry i is shown under filter "spell" or "item": what uses it, else the file name (inv_ is an item's)
local function indexKind(i, filter)
    local use = indexUse[i]
    if use == "" then return (filter == "item") == (indexFiles[i]:sub(1, 4) == "inv_") end
    return use == "B" or use == (filter == "item" and "I" or "S")
end

-- The icons that have names: {icon, name, lower, kind ("spell" or "item")} for your spells and mounts, and the items in
-- your bags, bank and gear
local function itemName(link) return link and link:match("%[(.-)%]") end
function L.iconNames()
    local list = {}
    local function add(icon, name, kind)
        if icon and name and name ~= "" then
            list[#list + 1] = {icon = tonumber(icon) or icon, name = name, lower = name:lower(), kind = kind}
        end
    end
    local texture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
    for _, tab in ipairs(L.spellbook(true)) do
        for _, spell in ipairs(tab.spells) do add(texture(spell), spell, "spell") end
    end
    if C_MountJournal and C_MountJournal.GetMountIDs then
        for _, id in ipairs(C_MountJournal.GetMountIDs()) do
            local name, _, icon, _, _, _, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(id)
            if collected then add(icon, name, "spell") end
        end
    end
    -- Every container the client names (Enum.BagIndex differs per client): bags, reagent bag, keyring, bank, bank bags
    -- or tabs, the account bank. The bank reads empty until you've opened it this session.
    local bags = {}
    for _, bag in pairs(Enum.BagIndex) do bags[#bags + 1] = bag end
    table.sort(bags) -- pairs has no order; sorted keeps the results in one order
    for _, bag in ipairs(bags) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local it = C_Container.GetContainerItemInfo(bag, slot)
            if it then add(it.iconFileID, itemName(it.hyperlink), "item") end
        end
    end
    for slot = 1, 19 do
        add(GetInventoryItemTexture("player", slot), itemName(GetInventoryItemLink("player", slot)), "item")
    end
    return list
end

local FILTERS = {{"Spells", "spell"}, {"Items", "item"}, {"All", "all"}}
function L.IconPicker(owner, onPick)
    local COLS, ROWS, CELL = 10, 5, 36
    local d = L.Dialog(owner, COLS * CELL + 24, ROWS * CELL + 140)
    d.title:SetText("Pick an icon")
    d.text:ClearAllPoints()
    d.text:SetPoint("TOPLEFT", 12, -66)
    d.text:SetPoint("RIGHT", -12, 0)
    d.ok:Hide()
    d.cancel:SetText("Close")
    local page, filter, query = 1, "all", ""
    local index, byIcon = {}, {} -- L.iconNames(), made on Open; byIcon: icon -> its names
    local INDEX_MIN = 2 -- one letter matches most of the game's icons: it searches only your names
    local cells = {}
    local function list()
        if query == "" then
            local game = allIcons()[filter]
            if filter == "item" then return game end
            local l = {QUESTION_MARK}
            for _, icon in ipairs(game) do l[#l + 1] = icon end
            return l
        end
        local l, seen = {}, {}
        for _, e in ipairs(index) do
            if (filter == "all" or e.kind == filter) and not seen[e.icon] and e.lower:find(query, 1, true) then
                seen[e.icon] = true
                local i = indexOf(e.icon)
                if i then seen[indexIcons[i]] = true end -- a path's icon isn't listed again by its ID
                l[#l + 1] = e.icon
            end
        end
        if #query < INDEX_MIN then return l end
        for i, icon in ipairs(indexIcons) do
            local file = indexFiles[i]
            if not seen[icon] and (filter == "all" or indexKind(i, filter))
                and (file:find(query, 1, true) or indexWords[i]:find(query, 1, true)) then
                seen[icon] = true
                l[#l + 1] = icon
            end
        end
        return l
    end
    local function showPage()
        local q = (d.search:GetText() or ""):lower():match("^%s*(.-)%s*$")
        if q ~= query then query, page = q, 1 end
        local l = list()
        local pages = math.max(1, math.ceil(#l / (COLS * ROWS)))
        page = math.min(math.max(page, 1), pages)
        for n, b in ipairs(cells) do
            local icon = l[(page - 1) * COLS * ROWS + n]
            b.value = icon
            b.texture:SetTexture(icon and L.iconPath(icon))
            b:SetShown(icon ~= nil)
        end
        for _, t in ipairs(d.filters) do t:Set(t.name, t.kind == filter) end
        if query == "" then
            d.text:SetText(("Page %d of %d. A question mark shows the spell the macro casts."):format(page, pages))
        elseif #l == 0 then
            d.text:SetText(("No icon matches \"%s\": search your spells, mounts and items, or an icon's file name or kind (sword, fire)."):format(query))
        else
            d.text:SetText(("%d %s. Page %d of %d."):format(#l, #l == 1 and "match" or "matches", page, pages))
        end
    end
    d.search = CreateFrame("EditBox", nil, d, "SearchBoxTemplate")
    d.search:SetPoint("TOPLEFT", 18, -38)
    d.search:SetSize(170, 20)
    d.search:SetAutoFocus(false)
    d.search:HookScript("OnTextChanged", function() showPage() end)
    d.filters = {}
    local right -- the tabs line up from the right edge: Spells, Items, All
    for i = #FILTERS, 1, -1 do
        local t = St.TextTab(d, function(self) filter = self.kind; page = 1; showPage() end)
        t.name, t.kind = FILTERS[i][1], FILTERS[i][2]
        t:Set(t.name, t.kind == filter)
        if right then t:SetPoint("RIGHT", right, "LEFT") else t:SetPoint("TOPRIGHT", -8, -36) end
        right = t
        d.filters[i] = t
    end
    for n = 1, COLS * ROWS do
        local b = CreateFrame("Button", nil, d)
        b:SetSize(CELL - 4, CELL - 4)
        b:SetPoint("TOPLEFT", 12 + ((n - 1) % COLS) * CELL, -88 - math.floor((n - 1) / COLS) * CELL)
        b.texture = b:CreateTexture(nil, "ARTWORK")
        b.texture:SetAllPoints()
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.2)
        b:SetScript("OnClick", function(self)
            d:Hide()
            onPick(self.value)
        end)
        b:SetScript("OnEnter", function(self)
            -- your names first, then the icon's file name and category words
            local names, i = byIcon[self.value], indexOf(self.value)
            if not names and not i then return end
            local lines = names and {unpack(names, 2)} or {}
            if names and i then lines[#lines + 1] = indexFiles[i] end
            if i and indexWords[i] ~= "" then lines[#lines + 1] = indexWords[i] end
            St.Tooltip(self, names and names[1] or indexFiles[i], lines)
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cells[n] = b
    end
    local prevPage = L.Button(d, "Previous", 90)
    prevPage:SetPoint("BOTTOMLEFT", 12, 12)
    prevPage:SetScript("OnClick", function() page = page - 1; showPage() end)
    d.nextPage = L.Button(d, "Next", 90)
    d.nextPage:SetPoint("LEFT", prevPage, "RIGHT", 8, 0)
    d.nextPage:SetScript("OnClick", function() page = page + 1; showPage() end)
    d.cells = cells
    function d.Open()
        loadIndex()
        index, byIcon = L.iconNames(), {} -- once per open, so typing only filters
        local seen = {}
        for _, e in ipairs(index) do
            byIcon[e.icon] = byIcon[e.icon] or {}
            if not seen[e.icon .. "\0" .. e.name] then table.insert(byIcon[e.icon], e.name) end
            seen[e.icon .. "\0" .. e.name] = true
        end
        d.search:SetText("")
        showPage()
        d:Show()
    end
    return d
end

-- Ready-made macros ------------------------------------------------------------------------------------------------

-- A card for ready-made r, w by h: its icon, name and what it does (place it and set OnClick); card.kind is r's
function L.ReadyCard(parent, r, w, h)
    local card = CreateFrame("Button", nil, parent)
    card:SetSize(w, h)
    local pane = Pane(card)
    pane:SetAllPoints()
    local hl = card:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(32, 32)
    card.icon:SetPoint("TOPLEFT", 12, -12)
    card.icon:SetTexture(L.iconPath(r.icon))
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
    return card
end

-- A ready-made macro's options, W wide: form:Open(kind, options, name, addText) shows kind's options (filled from
-- options, else the defaults) and the macro's name (nil: the ready-made's, or empty with a prompt when it casts a
-- spell); form:Result() is the macro it writes {name, body, kind, options, icon}. form.add (its text is addText) and
-- form.back are the window's to script; form.rows, form.name, form.preview and form.problem are for the tests.
function L.ReadyForm(parent, W)
    local ROW = 32 -- the settings page's ticks are 29 high
    local form = CreateFrame("Frame", nil, parent)
    form:SetSize(W, 300)
    local rows = {} -- option key -> its row
    local preview -- the macro text the options write
    local function updatePreview()
        local text = L.readyText(form.kind, form.options) or ""
        preview:SetText("|cff999999" .. text .. "|r")
        form.text = text
        form.problem:SetText(#text > L.MACRO_TEXT and ("Too long: %d of %d characters."):format(#text, L.MACRO_TEXT) or "")
    end
    local function setOption(key, value)
        form.options[key] = value
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
            row.box = St.EditBox(row)
            row.box:SetPoint("LEFT", 126, 0)
            row.box:SetWidth(o.type == "spell" and 180 or 280)
            row.box:SetMaxLetters(200)
            if o.prompt then L.Prompt(row.box, o.prompt) end
            row.box:SetScript("OnTextChanged", function(self) if form.options then setOption(key, self:GetText() or "") end end)
            row.box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            row.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        end
        if o.type == "spell" then
            row.pick = St.MenuButton(row, 110, function() return "Spellbook" end, function(root)
                L.spellMenu(root, function(spell)
                    row.box:SetText(spell)
                    setOption(key, spell)
                end)
            end)
            row.pick:SetPoint("LEFT", row.box, "RIGHT", 8, 0)
            row.pick:Refresh()
        elseif o.type == "choice" then
            row.menu = St.Dropdown(row, 200, function()
                local v = form.options and form.options[key]
                for _, c in ipairs(o.choices) do
                    if c[1] == v then return c[2] end
                end
                return ""
            end, function(root)
                for _, c in ipairs(o.choices) do
                    root:CreateRadio(c[2], function() return form.options and form.options[key] == c[1] end,
                        function() setOption(key, c[1]) end, c[1])
                end
            end)
            row.menu:SetPoint("LEFT", 120, 0)
        elseif o.type == "check" then
            row.check = St.Checkbox(row)
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
    form.name = St.EditBox(form)
    form.name:SetWidth(150)
    form.name:SetMaxLetters(L.MACRO_NAME)
    local namePrompt = L.Prompt(form.name, "Or the spell's name")
    form.name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    form.name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    preview = Text(form, "GameFontHighlightSmall")
    preview:SetWidth(W)
    preview:SetWordWrap(true)
    form.preview = preview
    form.problem = Text(form, "GameFontNormalSmall")
    form.problem:SetTextColor(1, 0.3, 0.3)
    form.add = L.Button(form, "Add", 140)
    form.back = L.Button(form, "Back", 90)
    form.back:SetPoint("LEFT", form.add, "RIGHT", 8, 0)

    function form.Open(kind, options, name, addText)
        local r = L.READY[kind]
        form.kind, form.options = kind, L.readyOptions(kind, options)
        form.title:SetText(r.name .. " · |cff999999" .. r.text .. "|r")
        for _, row in pairs(rows) do row:Hide() end
        local y = -24
        for _, key in ipairs(r.options) do
            local row, v = rows[key], form.options[key]
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
        form.add:SetText(addText)
        form:SetHeight(-(y - 108) + 24)
        updatePreview()
        name = name or (form.options.spell ~= nil and "" or r.name)
        form.name:SetText(name:sub(1, L.MACRO_NAME))
        namePrompt:SetShown(name == "")
    end
    function form.Result()
        local text = L.readyText(form.kind, form.options)
        local name = ns.trim(form.name:GetText())
        if name == "" then name = ns.trim(form.options.spell or ""):sub(1, L.MACRO_NAME) end
        if name == "" then name = L.READY[form.kind].name:sub(1, L.MACRO_NAME) end
        local options = {}
        for k, v in pairs(form.options) do options[k] = v end
        return {name = name, body = text, kind = form.kind, options = options,
            icon = text:find("^#showtooltip") and QUESTION_MARK or L.READY[form.kind].icon}
    end
    return form
end
