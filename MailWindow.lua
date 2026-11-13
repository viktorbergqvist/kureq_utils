-- The mail rules window (Mail.lua), in Kureq Utils' look (Style.lua): page tabs Rules and Preview. Rules: the rule list
-- on the left (New rule, From template, Up, Down, Delete above it) and the chosen rule on the right: who gets it, the
-- on tick, item kinds, name rules, quality and how many to keep. Edits save as they change. Preview: what the rules
-- would send now, per recipient, with the rule that matched each stack and the postage.
local _, ns = ...
local M, St = ns.mail, ns.style
local Pane, Text, Line = St.Pane, St.Text, St.Line
local fmt, tinsert, tremove = string.format, table.insert, table.remove

local W, H = 900, 600
local BW = St.bodySize(W, H)
local PAD, GAP, TOP_H = 12, 8, 28
local MAIN_Y = -(PAD + TOP_H + GAP)
local LIST_W, ROW_H, LINE_H = 300, 34, 24
local DETAIL_W = BW - 2 * PAD - LIST_W - GAP
-- item classes offered in the kind menu (quest items, 12, are never mailed; 10 and 14 are unused)
local CLASSES = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 13, 15}

local frame, body = St.Window("KureqMailRulesFrame", "Mail rules", W, H)
local page = "rules"
local selected = 1 -- index into the rules
local refresh

local function rules() return M.db() and M.db().rules or {} end
local function chosen() return rules()[selected] end

local function Button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end
local function Box(parent, w, letters)
    local box = St.EditBox(parent)
    box:SetWidth(w)
    box:SetMaxLetters(letters)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end
local function at(widget, parent, x, y)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
end

-- Pages ------------------------------------------------------------------------------------------------------------

local rulesPage, previewPage = CreateFrame("Frame", nil, body), CreateFrame("Frame", nil, body)
for _, p in ipairs({rulesPage, previewPage}) do p:SetAllPoints() end
local tabs = {}
for _, t in ipairs({{"Rules", "rules"}, {"Preview", "preview"}}) do
    local b = St.Tab(frame, t[1], function() page = t[2]; refresh() end)
    b.page = t[2]
    tabs[#tabs + 1] = b
end

-- Rules: top bar ---------------------------------------------------------------------------------------------------

local function pick(i) selected = i; M.notify() end
local newButton = Button(rulesPage, "New rule", 100, function() M.newRule(); pick(#rules()) end)
newButton:SetPoint("TOPLEFT", PAD, -PAD - 3)
local templateMenu = St.MenuButton(rulesPage, 130, function() return "From template" end, function(root)
    for i, t in ipairs(M.TEMPLATES) do
        root:CreateRadio(t.name, function() return false end, function() M.newRule(i); pick(#rules()) end, i)
    end
end)
templateMenu:SetPoint("LEFT", newButton, "RIGHT", 6, 0)
templateMenu:Refresh()
local function move(by)
    local list, to = rules(), selected + by
    if not list[selected] or not list[to] then return end
    list[selected], list[to] = list[to], list[selected]
    pick(to)
end
local upButton = Button(rulesPage, "Up", 60, function() move(-1) end)
upButton:SetPoint("LEFT", templateMenu, "RIGHT", 6, 0)
local downButton = Button(rulesPage, "Down", 60, function() move(1) end)
downButton:SetPoint("LEFT", upButton, "RIGHT", 6, 0)

local deleting -- the rule the dialog asks about, kept here as the dialog's data differs between clients
StaticPopupDialogs.KUREQUTILS_DELETE_MAIL_RULE = {text = "Delete the rule that mails to %s?", button1 = YES or "Yes",
    button2 = NO or "No", timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function()
        if not (deleting and ns.IsOn("mail")) then return end
        for i, r in ipairs(rules()) do
            if r == deleting then tremove(rules(), i); break end
        end
        deleting = nil
        M.notify()
    end}
local deleteButton = Button(rulesPage, "Delete", 80, function()
    local rule = chosen()
    if not rule then return end
    deleting = rule
    StaticPopup_Show("KUREQUTILS_DELETE_MAIL_RULE", ns.trim(rule.to) ~= "" and rule.to or "nobody yet")
end)
deleteButton:SetPoint("LEFT", downButton, "RIGHT", 6, 0)

-- Rules: the list --------------------------------------------------------------------------------------------------

local listPane = Pane(rulesPage)
listPane:SetPoint("TOPLEFT", PAD, MAIN_Y)
listPane:SetPoint("BOTTOMLEFT", PAD, PAD)
listPane:SetWidth(LIST_W)
local listTitle = Text(listPane, "GameFontNormal")
listTitle:SetPoint("TOPLEFT", 12, -12)
listTitle:SetText("Rules")
local listCount = Text(listPane, "GameFontDisableSmall")
listCount:SetPoint("TOPRIGHT", -12, -14)
listCount:SetJustifyH("RIGHT")
local listLine = Line(listPane)
listLine:SetPoint("TOPLEFT", 6, -30)
listLine:SetPoint("TOPRIGHT", -6, -30)
local scroll = CreateFrame("ScrollFrame", nil, listPane, "ScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 6, -34)
scroll:SetPoint("BOTTOMRIGHT", -26, 6)
local list = CreateFrame("Frame", nil, scroll)
list:SetSize(LIST_W - 32, 1)
scroll:SetScrollChild(list)
local listHint = Text(listPane, "GameFontDisableSmall")
listHint:SetPoint("BOTTOMLEFT", 12, 12)
listHint:SetPoint("RIGHT", -12, 0)
listHint:SetText("The first rule that matches a stack sends it.")
local rows = {}

-- Rules: the chosen rule -------------------------------------------------------------------------------------------

local detail = Pane(rulesPage)
detail:SetPoint("TOPLEFT", listPane, "TOPRIGHT", GAP, 0)
detail:SetPoint("BOTTOMRIGHT", -PAD, PAD)
local emptyText = Text(detail, "GameFontDisable")
emptyText:SetPoint("CENTER")
emptyText:SetWidth(380)
emptyText:SetWordWrap(true)
emptyText:SetJustifyH("CENTER")
emptyText:SetText("No rules yet. Click New rule, or From template for herbs, ore, cloth, leather or enchanting mats, "
    .. "then type who gets them.")
local editor = CreateFrame("Frame", nil, detail)
editor:SetAllPoints()

local title = Text(editor, "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 12, -12)
title:SetPoint("RIGHT", -140, 0)
local facts = Text(editor, "GameFontDisableSmall")
facts:SetPoint("TOPLEFT", 12, -34)
facts:SetPoint("RIGHT", -12, 0)
local onBox = St.Checkbox(editor)
onBox:SetPoint("TOPRIGHT", -110, -8)
onBox.Text:SetText("Use this rule")
onBox.Text:SetFontObject("GameFontHighlight")
onBox:SetScript("OnClick", function(self)
    local rule = chosen()
    if rule then rule.on = self:GetChecked() and true or false; M.notify() end
end)

-- the conditions scroll under the header, so a long rule stays reachable
local conditions = CreateFrame("ScrollFrame", nil, editor, "ScrollFrameTemplate")
conditions:SetPoint("TOPLEFT", 0, -54)
conditions:SetPoint("BOTTOMRIGHT", -26, 6)
local content = CreateFrame("Frame", nil, conditions)
content:SetSize(DETAIL_W - 30, 1)
conditions:SetScrollChild(content)

local function Label(text)
    local l = Text(content, "GameFontNormalSmall")
    l:SetText(text)
    return l
end
local VALUE_X = 110
local toLabel, kindLabel, nameLabel = Label("Send to"), Label("Item kinds"), Label("Name rules")
local qualityLabel, keepLabel = Label("Quality"), Label("Keep at least")

local toBox = Box(content, 200, 60)
toBox:SetScript("OnTextChanged", function(self, userInput)
    local rule = chosen()
    if userInput and rule then rule.to = self:GetText() or ""; M.notify() end
end)
local charMenu = St.MenuButton(content, 150, function() return "Your characters" end, function(root)
    local names = {}
    for _, name in pairs(ns.notes.myChars()) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        root:CreateRadio(name, function(n) local r = chosen(); return r and r.to == n end, function(n)
            local r = chosen()
            if r then r.to = n; toBox:SetText(n); M.notify() end
        end, name)
    end
end)
charMenu:SetPoint("LEFT", toBox, "RIGHT", 10, 0)
charMenu:Refresh()

-- "7" is a whole class, "7:9" a subclass
local function kindKey(k) return k.sub and (k.class .. ":" .. k.sub) or tostring(k.class) end
local function hasKind(rule, key)
    for _, k in ipairs(rule.kinds) do if kindKey(k) == key then return true end end
    return false
end
local kindMenu = St.MenuButton(content, 150, function() return "Add item kind" end, function(root)
    local function isSel(key) local r = chosen(); return r ~= nil and hasKind(r, key) end
    local function add(key)
        local r = chosen()
        if not r or hasKind(r, key) then return end
        local class, sub = key:match("^(%d+):?(%d*)$")
        tinsert(r.kinds, {class = tonumber(class), sub = tonumber(sub)})
        M.notify()
    end
    for _, class in ipairs(CLASSES) do
        local name = M.className(class)
        if name then
            local menu = root:CreateButton(name)
            menu:CreateRadio(fmt("Any %s", name), isSel, add, tostring(class))
            for sub = 0, 30 do
                local subName = M.subclassName(class, sub)
                if subName then menu:CreateRadio(subName, isSel, add, class .. ":" .. sub) end
            end
            menu:SetScrollMode(400)
        end
    end
end)
kindMenu:Refresh()

local nameKind = "ends"
local KIND_NAMES = {}
for _, k in ipairs(ns.delete.KINDS) do KIND_NAMES[k[1]] = k[2] end
local nameKindMenu = St.Dropdown(content, 110, function() return KIND_NAMES[nameKind] end, function(root)
    for _, k in ipairs(ns.delete.KINDS) do
        root:CreateRadio(k[2], function(v) return v == nameKind end, function(v) nameKind = v; refresh() end, k[1])
    end
end)
local nameBox = Box(content, 180, 100)
local function addName()
    local r, text = chosen(), nameBox:GetText() or ""
    nameBox:SetText("")
    nameBox:ClearFocus()
    if not r or ns.trim(text) == "" then return end
    for _, n in ipairs(r.nameRules) do if n.kind == nameKind and n.text == text then return end end
    tinsert(r.nameRules, {kind = nameKind, text = text})
    M.notify()
end
nameBox:SetScript("OnEnterPressed", addName)
local addNameButton = Button(content, "Add", 60, addName)
nameKindMenu:SetScript("OnEnter", function(self) St.Tooltip(self, "Name rules", {ns.delete.KIND_HELP}) end)
nameKindMenu:SetScript("OnLeave", function() GameTooltip:Hide() end)

local qualityMenu = St.Dropdown(content, 200, function()
    local r, names = chosen(), {}
    for _, q in ipairs(M.QUALITIES) do if r and r.qualities[q[1]] then names[#names + 1] = q[2] end end
    return #names > 0 and table.concat(names, ", ") or "Any quality"
end, function(root)
    root:CreateRadio("Any quality", function() local r = chosen(); return r ~= nil and next(r.qualities) == nil end,
        function() local r = chosen(); if r then r.qualities = {}; M.notify() end end, -1)
    for _, q in ipairs(M.QUALITIES) do
        root:CreateRadio(q[2], function(v) local r = chosen(); return r ~= nil and r.qualities[v] == true end, function(v)
            local r = chosen()
            if not r then return end
            r.qualities[v] = not r.qualities[v] or nil -- each pick turns one on or off
            M.notify()
        end, q[1])
    end
end)

local keepBox = Box(content, 50, 5)
keepBox:SetNumeric(true)
keepBox:SetScript("OnTextChanged", function(self, userInput)
    local rule = chosen()
    if userInput and rule then rule.keep = tonumber(self:GetText()) or 0; M.notify() end
end)
local keepHint = Text(content, "GameFontDisableSmall")
keepHint:SetText("of each item in your bags; 0 sends all. Whole stacks only.")

-- one line per kind or name rule: its text and a Remove button
local lines = {}
local function lineAt(i)
    if lines[i] then return lines[i] end
    local l = CreateFrame("Frame", nil, content)
    l:SetSize(DETAIL_W - VALUE_X - 54, LINE_H) -- DETAIL_W follows the window's size
    l.text = Text(l, "GameFontHighlightSmall")
    l.text:SetPoint("LEFT")
    l.text:SetPoint("RIGHT", -80, 0)
    l.remove = Button(l, "Remove", 70, function() if l.onRemove then l.onRemove(); M.notify() end end)
    l.remove:SetPoint("RIGHT")
    lines[i] = l
    return l
end

local function refreshDetail()
    local rule = chosen()
    emptyText:SetShown(rule == nil)
    editor:SetShown(rule ~= nil)
    for _, l in ipairs(lines) do l:Hide() end
    if not rule then return end
    rule.kinds, rule.nameRules, rule.qualities = rule.kinds or {}, rule.nameRules or {}, rule.qualities or {}
    title:SetText(ns.trim(rule.to) ~= "" and rule.to or "New rule")
    local problem = M.problem(rule)
    facts:SetText(problem and ("|cffff6060" .. problem .. "|r") or rule.on == false and "Off: this rule sends nothing."
        or "Sends what matches every condition below; inside one, any entry may match.")
    onBox:SetChecked(rule.on ~= false)
    if not toBox:HasFocus() then toBox:SetText(rule.to or "") end
    if not keepBox:HasFocus() then keepBox:SetText(tostring(tonumber(rule.keep) or 0)) end
    local y, n = -8, 0
    local function line(text, onRemove)
        n = n + 1
        local l = lineAt(n)
        at(l, content, VALUE_X, y)
        l.text:SetText(text)
        l.onRemove = onRemove
        l:Show()
        y = y - LINE_H
    end
    at(toLabel, content, 12, y - 4); at(toBox, content, VALUE_X + 6, y)
    y = y - 34
    at(kindLabel, content, 12, y - 4); at(kindMenu, content, VALUE_X, y)
    y = y - 32
    for i, k in ipairs(rule.kinds) do line(M.kindName(k), function() tremove(rule.kinds, i) end) end
    y = y - 10
    at(nameLabel, content, 12, y - 4); at(nameKindMenu, content, VALUE_X, y)
    at(nameBox, content, VALUE_X + 120, y); at(addNameButton, content, VALUE_X + 310, y)
    y = y - 32
    for i, r in ipairs(rule.nameRules) do
        local bad = r.kind == "pattern" and not ns.delete.validPattern(r.text) and " |cff808080(invalid pattern)|r" or ""
        line(fmt('%s: "%s"%s', KIND_NAMES[r.kind] or r.kind, r.text:gsub("|", "||"), bad),
            function() tremove(rule.nameRules, i) end)
    end
    y = y - 10
    at(qualityLabel, content, 12, y - 4); at(qualityMenu, content, VALUE_X, y)
    y = y - 34
    at(keepLabel, content, 12, y - 4); at(keepBox, content, VALUE_X + 6, y)
    keepHint:ClearAllPoints()
    keepHint:SetPoint("LEFT", keepBox, "RIGHT", 10, 0)
    content:SetHeight(-(y - 34)) -- down to the keep row's bottom
    for _, menu in ipairs({nameKindMenu, qualityMenu}) do menu:Refresh() end
end

local function refreshList()
    local list_ = rules()
    if selected > #list_ then selected = #list_ end
    if selected < 1 then selected = 1 end
    for i, rule in ipairs(list_) do
        local b = rows[i] or St.ListRow(list, i, LIST_W - 32, ROW_H, function(self) pick(self.index) end)
        rows[i] = b
        b.index = i
        b.nameText:SetText(ns.trim(rule.to) ~= "" and rule.to or "|cff808080Nobody yet|r")
        b.count:SetText(rule.on == false and "|cff808080off|r" or "")
        b.sub:SetText(M.problem(rule) or M.summary(rule))
        b.each:SetText("")
        b:SetPicked(i == selected)
        b:Show()
    end
    for i = #list_ + 1, #rows do rows[i]:Hide() end
    listCount:SetText(#list_)
    list:SetHeight(math.max(1, #list_ * ROW_H))
    upButton:SetEnabled(selected > 1)
    downButton:SetEnabled(selected < #list_)
    deleteButton:SetEnabled(#list_ > 0)
end

-- Preview ----------------------------------------------------------------------------------------------------------

local previewPane = Pane(previewPage)
previewPane:SetPoint("TOPLEFT", PAD, -PAD)
previewPane:SetPoint("BOTTOMRIGHT", -PAD, PAD)
local previewTitle = Text(previewPane, "GameFontNormal")
previewTitle:SetPoint("TOPLEFT", 12, -12)
previewTitle:SetText("What the rules send now")
local previewCount = Text(previewPane, "GameFontDisableSmall")
previewCount:SetPoint("TOPRIGHT", -12, -14)
previewCount:SetJustifyH("RIGHT")
local previewLine = Line(previewPane)
previewLine:SetPoint("TOPLEFT", 6, -30)
previewLine:SetPoint("TOPRIGHT", -6, -30)
local previewScroll = CreateFrame("ScrollFrame", nil, previewPane, "ScrollFrameTemplate")
previewScroll:SetPoint("TOPLEFT", 6, -34)
previewScroll:SetPoint("BOTTOMRIGHT", -26, 6)
local previewList = CreateFrame("Frame", nil, previewScroll)
previewList:SetSize(BW - 2 * PAD - 32, 1)
previewScroll:SetScrollChild(previewList)
local previewEmpty = Text(previewPane, "GameFontDisable")
previewEmpty:SetPoint("CENTER")
previewEmpty:SetWidth(420)
previewEmpty:SetWordWrap(true)
previewEmpty:SetJustifyH("CENTER")
previewEmpty:SetText("Nothing to send. Add a rule on the Rules tab, or bring the items it asks for.")
local previewRows = {}
local function previewRow(i)
    if previewRows[i] then return previewRows[i] end
    local r = CreateFrame("Frame", nil, previewList)
    r:SetSize(BW - 2 * PAD - 32, 22) -- BW follows the window's size
    r:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", 22, 0)
    r.left = Text(r, "GameFontHighlight")
    r.right = Text(r, "GameFontDisableSmall")
    r.right:SetPoint("RIGHT", -8, 0)
    r.right:SetJustifyH("RIGHT")
    previewRows[i] = r
    return r
end

local function refreshPreview()
    local plan = M.current()
    local n, stacks, postage = 0, 0, 0
    local function row(icon, left, right, header)
        n = n + 1
        local r = previewRow(n)
        r.icon:SetShown(icon ~= nil)
        r.icon:SetTexture(icon)
        r.left:ClearAllPoints()
        r.left:SetPoint("LEFT", header and 6 or 46, 0)
        r.left:SetPoint("RIGHT", r.right, "LEFT", -8, 0)
        r.left:SetFontObject(header and "GameFontNormal" or "GameFontHighlight")
        r.left:SetText(left)
        r.right:SetText(right)
        r:Show()
    end
    for _, p in ipairs(plan) do
        local cost = M.POSTAGE * #p.items
        stacks, postage = stacks + #p.items, postage + cost
        row(nil, p.to, fmt("%s · postage %s", M.plural(#p.mails, "mail", "mails"), M.money(cost)), true)
        for _, it in ipairs(p.items) do
            row(it.icon, fmt("%s x%d", it.name, it.count), M.summary(it.rule))
        end
    end
    for i = n + 1, #previewRows do previewRows[i]:Hide() end
    previewList:SetHeight(math.max(1, n * 22))
    previewEmpty:SetShown(#plan == 0)
    previewCount:SetText(#plan > 0 and fmt("%s to %s · postage %s", M.plural(stacks, "item", "items"),
        M.plural(#plan, "character", "characters"), M.money(postage)) or "")
end

function refresh()
    if not frame:IsShown() then return end
    rulesPage:SetShown(page == "rules")
    previewPage:SetShown(page == "preview")
    for _, t in ipairs(tabs) do t:SetOn(t.page == page) end
    if page == "rules" then
        refreshList()
        refreshDetail()
    else
        refreshPreview()
    end
end
frame:SetScript("OnShow", refresh)
M.changed = refresh

function M.toggle()
    if frame:IsShown() then frame:Hide() else frame:Show() end
end
function M.showPreview()
    page = "preview"
    if frame:IsShown() then refresh() else frame:Show() end
end
ns.OnModuleChange("mail", function(on)
    if on then return end
    frame:Hide()
    StaticPopup_Hide("KUREQUTILS_DELETE_MAIL_RULE")
end)

-- Resizing: the panes stretch on their anchors; this widens the rule's conditions and the preview's rows
St.Resizable(frame, function(w)
    BW = St.bodySize(w, H)
    DETAIL_W = BW - 2 * PAD - LIST_W - GAP
    content:SetWidth(DETAIL_W - 30)
    for _, l in ipairs(lines) do l:SetWidth(DETAIL_W - VALUE_X - 54) end
    previewList:SetWidth(BW - 2 * PAD - 32)
    for _, r in ipairs(previewRows) do r:SetWidth(BW - 2 * PAD - 32) end
end)

-- what the tests drive
M.ui = {frame = frame, rows = rows, tabs = tabs, newButton = newButton, templateMenu = templateMenu, upButton = upButton,
    downButton = downButton, deleteButton = deleteButton, toBox = toBox, onBox = onBox, kindMenu = kindMenu,
    nameKindMenu = nameKindMenu, nameBox = nameBox, addNameButton = addNameButton, qualityMenu = qualityMenu,
    keepBox = keepBox, charMenu = charMenu, lines = lines, title = title, facts = facts, previewRows = previewRows,
    previewCount = previewCount, previewEmpty = previewEmpty, content = content, detail = detail}
