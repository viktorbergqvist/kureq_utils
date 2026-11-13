-- Editing a saved loadout in the loadouts window (LoadoutsWindow.lua shows it, Loadouts.lua changes it): the Macros
-- tab's macro editor (name, icon, text, scope, helpers, a spell picker) and its ready-made macros, dropping things on
-- the Bars tab's slots, binding keys on the Bindings tab and the Settings tab's values. Each edit saves at once to
-- the loadout only; your character changes when you Load it. Revert changes puts back the loadout as it was when the
-- window opened. Backups aren't edited.
local _, ns = ...
local L, St = ns.loadouts, ns.style
local U = L.ui
local Text = St.Text
local Button = U.Button
local frame, detail, content, status, summary = U.frame, U.detail, U.content, U.status, U.summary
local W, TOP = U.CONTENT_W, U.SUMMARY_H

local view = "list" -- the Macros tab: "list", "macro" (editing one), "gallery" or "ready" (a ready-made's options)
local editing -- the macro's index in the macro and ready views (nil in the ready view: a new macro)
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

-- Toolbar: on the tabs' row, and Revert changes beside the name -------------------------------------------------------

local newButton = Button(detail, "New macro", 100)
newButton:SetPoint("TOPRIGHT", -12, -59)
local galleryButton = Button(detail, "Ready-made", 100)
galleryButton:SetPoint("RIGHT", newButton, "LEFT", -6, 0)
local revertButton = Button(detail, "Revert changes", 130)
revertButton:SetPoint("TOPRIGHT", -12, -13)
frame.newMacroButton, frame.galleryButton, frame.revertButton = newButton, galleryButton, revertButton

-- Macro editor -------------------------------------------------------------------------------------------------------

local function editedMacro()
    local lo = current()
    return lo, lo and editing and lo.macros[editing]
end
local ed
ed = L.MacroForm(content, W, {
    get = function() local _, m = editedMacro(); return m and L.scope(m) end,
    set = function(account)
        local lo, m = editedMacro()
        if not m then return end
        local ok, why = L.setMacro(lo, editing, {account = account})
        ed.problem:SetText(ok and "" or why)
        refresh()
    end,
}, " That's fine if the loadout is for another character.")
ed:SetPoint("TOPLEFT", 0, -TOP)
ed:Hide()
U.resized[#U.resized + 1] = function(w) ed:SetFormSize(w) end -- the code editor grows with the window
frame.macroEditor = ed
local ED_H = 250
local showCount = ed.showCount
ed.readyButton = Button(ed, "Ready-made options", 150)
ed.readyButton:SetPoint("LEFT", ed.spell, "RIGHT", 6, 0)
ed.back = Button(ed, "Back to macros", 130)
ed.back:SetPoint("TOPLEFT", 0, -226)
ed.delete = Button(ed, "Delete macro", 120)
ed.delete:SetPoint("TOPRIGHT", 0, -226)

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
ed.box:HookScript("OnTextChanged", function(self)
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
    local target = asking -- each popup keeps its own, so another one asking meanwhile can't swap it
    StaticPopupDialogs[which] = {text = text, button1 = YES or "Yes", button2 = NO or "No",
        OnAccept = function() if target and ns.IsOn("loadouts") then fn(target) end end,
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

-- Icon picker: Blizzard's macro icons (MacroForm.lua) ----------------------------------------------------------------

local iconDialog = L.IconPicker(frame, function(icon)
    local lo, m = editedMacro()
    if not m then return end
    L.setMacro(lo, editing, {icon = icon})
    refresh()
end)
frame.iconDialog, frame.iconCells, frame.iconNext = iconDialog, iconDialog.cells, iconDialog.nextPage
ed.icon:SetScript("OnClick", function() iconDialog.Open() end)

-- Ready-made macros: a gallery of cards, then a card's options --------------------------------------------------------

local gallery = CreateFrame("Frame", nil, content)
gallery:SetPoint("TOPLEFT", 0, -TOP)
gallery:Hide()
local CARD_W, CARD_H = math.floor((W - 8) / 2), 64
local cards = {}
for _, r in ipairs(L.READY) do
    if not (r.class or r.ku) then -- class and /ku templates are the macros window's (MacrosWindow.lua)
        local n = #cards + 1
        local card = L.ReadyCard(gallery, r, CARD_W, CARD_H)
        card:SetPoint("TOPLEFT", ((n - 1) % 2) * (CARD_W + 8), -math.floor((n - 1) / 2) * (CARD_H + 8))
        cards[n] = card
    end
end
gallery:SetSize(W, math.ceil(#cards / 2) * (CARD_H + 8))
frame.readyCards = cards

local form = L.ReadyForm(content, W)
form:SetPoint("TOPLEFT", 0, -TOP)
form:Hide()
frame.readyForm = form

local function openReady(kind, i)
    commitPending()
    local lo = current()
    local m = lo and i and lo.macros[i]
    view, editing = "ready", i
    form.Open(kind, m and m.options, m and m.name, i and "Save macro" or "Add to loadout")
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
    local fields = form.Result()
    local name = fields.name
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

-- Bars: drop from the cursor, drag to move, right-click to clear or ignore ----------------------------------------------

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
                -- cleared: loads as empty; ignored: loading leaves the slot (or the whole bar of 12) as it is
                local first, bar, all = slot - (slot - 1) % 12, {}, true
                for s = first, first + 11 do
                    bar[#bar + 1] = s
                    all = all and L.ignores(lo, s)
                end
                root:CreateButton("Clear this slot", function()
                    L.clearSlots(lo, {slot})
                    refresh()
                end)
                root:CreateButton("Clear this bar", function()
                    L.clearSlots(lo, bar)
                    refresh()
                end)
                local ignored = L.ignores(lo, slot)
                root:CreateButton(ignored and "Stop ignoring this slot" or "Ignore this slot", function()
                    L.setIgnored(lo, {slot}, not ignored)
                    refresh()
                end)
                root:CreateButton(all and "Stop ignoring this bar" or "Ignore this bar", function()
                    L.setIgnored(lo, bar, not all)
                    refresh()
                end)
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
    {3, "MULTIACTIONBAR3BUTTON"}, {4, "MULTIACTIONBAR4BUTTON"}, {13, "MULTIACTIONBAR5BUTTON"},
    {14, "MULTIACTIONBAR6BUTTON"}, {15, "MULTIACTIONBAR7BUTTON"}}
local addBinding = St.MenuButton(detail, 130, function() return "Add a binding" end, function(root)
    local lo = current()
    if not lo then return end
    for _, m in ipairs(lo.macros) do
        local command = "MACRO " .. m.name
        root:CreateButton(actionName(command), function() listen(command) end)
    end
    for _, bar in ipairs(BUTTONS) do
        for i = 1, 12 do
            local slot = (bar[1] - 1) * 12 + i
            if lo.actions[slot] and L.isSlot(slot) then
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
    r.check = St.Checkbox(r)
    r.check:SetPoint("LEFT", 186, 0)
    r.check:SetScript("OnClick", function(self)
        local lo = current()
        if lo then L.setSetting(lo, r.data, self:GetChecked() and "1" or "0") end
        refresh()
    end)
    r.box = St.EditBox(r)
    r.box:SetPoint("LEFT", 196, 0)
    r.box:SetWidth(120)
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

local function decorateTab(tab, lo, isBackup, height)
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

-- Each part's row over its tab: "Load these" (off: Load and Update from current skip it) and Clear all, which asks
local PART = {bars = "actions", macros = "macros", bindings = "bindings", cvars = "cvars"}
local CLEAR_ASK = {actions = "Empty every bar slot in %s?", macros = "Delete every macro in %s? Slots and keys using "
    .. "them are cleared too.", bindings = "Clear every key binding in %s?", cvars = "Take every Blizzard setting out of %s?"}
local PART_H = 32
local partRow = CreateFrame("Frame", nil, detail)
partRow:SetPoint("TOPLEFT", detail, "TOPLEFT", 12, -88) -- over the content, which moves down under it
partRow:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
partRow:SetHeight(PART_H)
partRow:Hide()
local partBox = St.Checkbox(partRow, "Load these")
partBox:SetPoint("LEFT", -4, 0)
local clearAll = Button(partRow, "Clear all", 90)
clearAll:SetPoint("RIGHT")
frame.partRow, frame.partBox, frame.clearAllButton = partRow, partBox, clearAll
partBox:SetScript("OnClick", function(self)
    local lo = current()
    if lo and PART[shownTab] then L.setPartOn(lo, PART[shownTab], self:GetChecked() and true or false) end
    refresh()
end)
clearAll:SetScript("OnClick", function()
    local lo, part = current(), PART[shownTab]
    if not (lo and part) then return end
    asking = {lo = lo, part = part}
    confirm("KUREQUTILS_CLEAR_PART", CLEAR_ASK[part]:format(lo.name) .. " Revert changes undoes it.", function(a)
        L.clearPart(a.lo, a.part)
        say(("Cleared the %s of %s."):format(L.PART_NAMES[a.part], a.lo.name))
        refresh()
    end)
end)
local function decoratePart(tab, lo, isBackup)
    local part = PART[tab]
    local shown = lo ~= nil and not isBackup and part ~= nil and (tab ~= "macros" or view == "list")
    partRow:SetShown(shown)
    U.contentScroll:SetPoint("TOPLEFT", 12, shown and -(90 + PART_H) or -90)
    if not shown then return end
    partBox:SetChecked(L.partOn(lo, part))
    if not L.partOn(lo, part) then
        summary:SetText("|cffff8040Off: Load and Update from current skip these.|r " .. summary:GetText())
    end
end
function U.decorate(tab, lo, isBackup, height)
    height = decorateTab(tab, lo, isBackup, height)
    decoratePart(tab, lo, isBackup)
    return height
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
    for _, which in ipairs({"KUREQUTILS_DELETE_MACRO", "KUREQUTILS_REVERT_LOADOUT", "KUREQUTILS_CLEAR_PART"}) do StaticPopup_Hide(which) end
end)
