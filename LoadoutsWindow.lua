-- The loadouts window (Loadouts.lua), in Kureq Utils' look (Style.lua): a name box to save what you have now and an
-- Import button, tiles, the saved loadouts and this character's backups on the left, and the chosen one on the right:
-- its name (edit to rename), where it's from, tabs showing its bars, macros, key bindings and settings, and Load
-- (asks which parts) / Update / Export / Delete, or Restore for a backup. Each change is asked first.
local _, ns = ...
local L, St = ns.loadouts, ns.style
local Pane, Text, Line = St.Pane, St.Text, St.Line
local GOLD = St.GOLD

local W, H = 900, 600
local BW = St.bodySize(W, H)
local PAD, GAP = 12, 8
local TOP_H, TILE_H = 28, 62
local MAIN_Y = -(PAD + TOP_H + GAP + TILE_H + GAP)
local LIST_W, ROW_H = 300, 34
local CONTENT_W = BW - 2 * PAD - LIST_W - GAP - 12 - 30
local ICON, BAR_H, LINE_H, SUMMARY_H = 22, 24, 20, 22
local SETTING_H = 32 -- a Settings line holds a tick or a text box (29 and 22 high), the settings page's

local frame, body = St.Window("KureqLoadoutsFrame", "Loadouts", W, H)
local selected -- the loadout shown on the right: a saved one's id, or a backup (its table)
local tab = "bars"
local refresh
-- saves a name or setting still being typed in the editor (LoadoutsEditor.lua), before acting on the loadout
local function flush() if L.ui and L.ui.commitPending then L.ui.commitPending() end end

local function stamp(t) return t and date("%d %b %Y, %H:%M", t) or "-" end
local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) or "|cffffffff"
end
local function count(n, one, many) return n .. " " .. (n == 1 and one or many) end
local function cleanName(box) return (ns.trim(box:GetText()):gsub("%s+", " ")) end

-- the chosen loadout, and whether it's a backup
local function chosen()
    if type(selected) == "table" then
        for _, b in ipairs(L.backups()) do
            if b == selected then return b, true end
        end
        return nil
    end
    return selected and L.list()[selected], false
end

local Button, Prompt = L.Button, L.Prompt -- MacroForm.lua

-- Top bar: search, Import, and a name box that saves what you have now ---------------------------------------------

local search = CreateFrame("EditBox", nil, body, "SearchBoxTemplate")
search:SetPoint("TOPLEFT", PAD + 6, -PAD - 4)
search:SetSize(200, 20)
search:SetAutoFocus(false)
search:HookScript("OnTextChanged", function() refresh() end)
frame.search = search

local saveButton = Button(body, "Save current", 120)
saveButton:SetPoint("TOPRIGHT", -PAD, -PAD - 3)
local nameBox = St.EditBox(body)
nameBox:SetPoint("RIGHT", saveButton, "LEFT", -10, 0)
nameBox:SetWidth(200)
nameBox:SetMaxLetters(40)
local namePrompt = Prompt(nameBox, "Loadout name")
local importButton = Button(body, "Import", 90)
importButton:SetPoint("RIGHT", nameBox, "LEFT", -12, 0)
local status -- set below: the result line in the detail pane
local function saveTyped()
    local name = cleanName(nameBox)
    if name == "" then name = (UnitClass("player") or "Loadout") .. " " .. date("%d %b") end -- "Paladin 11 Nov"
    if InCombatLockdown() then return ns.say("loadouts save out of combat.") end
    selected = L.save(name)
    nameBox:SetText("")
    nameBox:ClearFocus()
    namePrompt:Show()
    refresh()
    status:SetText("Saved what you have now as " .. name .. ".")
end
saveButton:SetScript("OnClick", saveTyped)
nameBox:SetScript("OnEnterPressed", saveTyped)
nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
frame.nameBox, frame.saveButton, frame.importButton = nameBox, saveButton, importButton

-- Tiles ------------------------------------------------------------------------------------------------------------

local TILES = {"Loadouts", "This character", "Waiting to place"}
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

-- List: the saved loadouts, then this character's backups ---------------------------------------------------------

local listPane = Pane(body)
listPane:SetPoint("TOPLEFT", PAD, MAIN_Y)
listPane:SetPoint("BOTTOMLEFT", PAD, PAD)
listPane:SetWidth(LIST_W)
local listTitle = Text(listPane, "GameFontNormal")
listTitle:SetPoint("TOPLEFT", 12, -12)
listTitle:SetText("Saved loadouts")
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
local rows, backupRows = {}, {}
frame.rows, frame.backupRows = rows, backupRows
local backupTitle = Text(list, "GameFontNormal")
backupTitle:SetText("Backups")
local backupHint = Text(list, "GameFontDisableSmall")
backupHint:SetPoint("LEFT", backupTitle, "RIGHT", 8, 0)
backupHint:SetText("kept before each load")
local backupLine = Line(list)
frame.backupTitle = backupTitle

local function shownLoadouts() -- newest first, under the search
    local query = (search:GetText() or ""):lower()
    local shown = {}
    for _, item in ipairs(L.sorted()) do
        local lo = item.lo
        local found = query == "" or lo.name:lower():find(query, 1, true) or (lo.className or ""):lower():find(query, 1, true)
        if found then shown[#shown + 1] = item end
    end
    return shown
end

-- Detail: header, tabs, the tab's content, buttons -----------------------------------------------------------------

local detail = Pane(body)
detail:SetPoint("TOPLEFT", listPane, "TOPRIGHT", GAP, 0)
detail:SetPoint("BOTTOMRIGHT", -PAD, PAD)
frame.detail = detail
local emptyText = Text(detail, "GameFontDisable")
emptyText:SetPoint("CENTER")
emptyText:SetWidth(380)
emptyText:SetWordWrap(true)
emptyText:SetJustifyH("CENTER")
emptyText:SetText("No loadouts yet. Type a name above and click Save current to keep your bars, macros, bindings and "
    .. "settings, or click Import to add one someone shared.")

local renameBox = St.EditBox(detail) -- the name; edit it to rename
renameBox:SetPoint("TOPLEFT", 20, -12)
renameBox:SetSize(260, 24)
renameBox:SetMaxLetters(40)
renameBox:SetFontObject("GameFontNormalLarge")
local function rename()
    local lo = chosen()
    local name = cleanName(renameBox)
    if lo and name ~= "" then lo.name = name end
    renameBox:ClearFocus()
    refresh()
end
renameBox:SetScript("OnEnterPressed", rename)
renameBox:SetScript("OnEditFocusLost", rename)
renameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
frame.renameBox = renameBox
local from = Text(detail, "GameFontDisableSmall")
from:SetPoint("TOPLEFT", 12, -42)
from:SetPoint("RIGHT", -12, 0)
frame.from = from

local TABS = {{"bars", "Bars"}, {"macros", "Macros"}, {"bindings", "Bindings"}, {"cvars", "Settings"},
    {"rules", "Rules"}} -- "Rules": "Apply automatically" would run under the Macros tab's buttons
local tabs = {}
for i, t in ipairs(TABS) do
    local b = St.TextTab(detail, function()
        tab = t[1]
        refresh()
    end)
    if i == 1 then b:SetPoint("TOPLEFT", 0, -58) else b:SetPoint("LEFT", tabs[TABS[i - 1][1]], "RIGHT", 0, 0) end
    tabs[t[1]] = b
end
frame.tabs = tabs
local tabLine = Line(detail)
tabLine:SetPoint("TOPLEFT", 6, -83)
tabLine:SetPoint("TOPRIGHT", -6, -83)

local contentScroll = CreateFrame("ScrollFrame", nil, detail, "ScrollFrameTemplate")
contentScroll:SetPoint("TOPLEFT", 12, -90)
contentScroll:SetPoint("BOTTOMRIGHT", -30, 96)
local content = CreateFrame("Frame", nil, contentScroll)
content:SetSize(CONTENT_W, 1)
contentScroll:SetScrollChild(content)
local summary = Text(content, "GameFontDisableSmall") -- a grey line on what the tab shows
summary:SetPoint("TOPLEFT")
summary:SetWidth(CONTENT_W)
summary:SetWordWrap(true)
frame.summary = summary

-- Bars: a row of 12 slots per bar, in the order Edit Mode numbers them; hover a slot for what it is
local BARS = {{1, "Bar 1"}, {2, "Bar 1, page 2"}, {6, "Bar 2"}, {5, "Bar 3"}, {3, "Bar 4"}, {4, "Bar 5"},
    {7, "Stance bar 1"}, {8, "Stance bar 2"}, {9, "Stance bar 3"}, {10, "Stance bar 4"}}
local barRows, icons = {}, {}
for _, bar in ipairs(BARS) do
    local row = CreateFrame("Frame", nil, content)
    row:SetSize(CONTENT_W, BAR_H)
    row.label = Text(row, "GameFontNormalSmall")
    row.label:SetPoint("LEFT")
    row.label:SetWidth(100)
    row.label:SetText(bar[2])
    for i = 1, 12 do
        local slot = (bar[1] - 1) * 12 + i
        local b = CreateFrame("Button", nil, row, "BackdropTemplate")
        b:SetSize(ICON, ICON)
        b:SetPoint("LEFT", 104 + (i - 1) * BAR_H, 0)
        -- a gold edge when loading changes the slot
        b:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2})
        b:SetBackdropColor(1, 1, 1, 0.05)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 2, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.cross = b:CreateTexture(nil, "OVERLAY") -- an ignored slot is crossed out
        b.cross:SetPoint("TOPLEFT", 3, -3)
        b.cross:SetPoint("BOTTOMRIGHT", -3, 3)
        -- the ready check's red cross: an atlas on Forever, a file on Classic Era
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("UI-LFG-DeclineMark") then
            b.cross:SetAtlas("UI-LFG-DeclineMark")
        else
            b.cross:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
        end
        b.cross:Hide()
        b.slot = slot
        b:SetScript("OnEnter", function(self)
            if not (self.what or self.changed or self.editable or self.ignored) then return end
            local lines = {("%s, slot %d"):format(bar[2], i)}
            if self.ignored then lines[#lines + 1] = "Ignored: loading leaves this slot as it is." end
            if self.waiting then lines[#lines + 1] = "You don't know it yet: it goes on when you learn it." end
            if self.changed then lines[#lines + 1] = self.what and "Loading puts it on your bar." or "Loading empties this slot." end
            if self.editable then -- LoadoutsEditor.lua
                lines[#lines + 1] = "|cff999999Drop a spell, item or macro here. Drag to move it, right-click for more.|r"
            end
            St.Tooltip(self, self.what or "Empty", lines)
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        icons[slot] = b
    end
    barRows[bar[1]] = row
end
frame.icons = icons

-- Macros, Bindings and Settings: lines of an optional icon, a gold label and a white value; data is what the line
-- shows (a macro's index, {command, key}, a setting's name), for the editor
local lines = {}
local lineH = LINE_H -- the shown tab's line height: taller on Settings
local function setLine(i, icon, label, value, data)
    local r = lines[i]
    if not r then
        r = CreateFrame("Button", nil, content)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        r:SetWidth(CONTENT_W) -- set again on resizing
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(18, 18)
        r.icon:SetPoint("LEFT")
        r.label = Text(r, "GameFontNormalSmall")
        r.value = Text(r, "GameFontHighlightSmall")
        r.value:SetPoint("LEFT", 190, 0)
        r.value:SetPoint("RIGHT")
        lines[i] = r
    end
    r:SetHeight(lineH)
    r:SetPoint("TOPLEFT", 0, -(SUMMARY_H + (i - 1) * lineH))
    r.icon:SetShown(icon ~= nil)
    if icon then r.icon:SetTexture(icon) end
    r.label:ClearAllPoints()
    r.label:SetPoint("LEFT", icon and 24 or 0, 0)
    r.label:SetWidth(icon and 160 or 184)
    r.label:SetText(label)
    r.value:SetText(value)
    r.data = data
    r:Show()
end
frame.lines = lines

status = Text(detail, "GameFontHighlightSmall")
status:SetPoint("BOTTOMLEFT", 12, 40)
status:SetPoint("RIGHT", -12, 0)
status:SetWordWrap(true) -- a load's report takes two lines
frame.status = status

-- Ticks on a saved loadout, over the status line
local function Tick(label, tip, x, onClick)
    local box = St.Checkbox(detail)
    box:SetPoint("BOTTOMLEFT", x, 66)
    box.Text:SetText(label)
    box.Text:SetFontObject("GameFontHighlightSmall")
    box:SetScript("OnClick", function(self)
        flush()
        local lo, isBackup = chosen()
        if lo and not isBackup then onClick(lo, self:GetChecked() and true or false) end
        refresh()
    end)
    box:SetScript("OnEnter", function(self) St.Tooltip(self, label, {tip}) end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return box
end
local anyClassBox = Tick("Any class", "Loads on any class without a warning. Spells your class doesn't know wait "
    .. "until you learn them, and ones it can't use are left out.", 8, function(lo, on) L.setAnyClass(lo, on) end)
frame.anyClassBox = anyClassBox

local loadButton = Button(detail, "Load", 80)
loadButton:SetPoint("BOTTOMLEFT", 12, 12)
local updateButton = Button(detail, "Update from current", 140)
updateButton:SetPoint("LEFT", loadButton, "RIGHT", 8, 0)
local exportButton = Button(detail, "Export", 80)
exportButton:SetPoint("LEFT", updateButton, "RIGHT", 8, 0)
local deleteButton = Button(detail, "Delete", 80)
deleteButton:SetPoint("BOTTOMRIGHT", -12, 12)
local restoreButton = Button(detail, "Restore", 110)
restoreButton:SetPoint("BOTTOMLEFT", 12, 12)
local cloneButton = Button(detail, "Clone", 80) -- beside Export, or Restore for a backup
frame.loadButton, frame.updateButton, frame.deleteButton = loadButton, updateButton, deleteButton
frame.exportButton, frame.restoreButton, frame.cloneButton = exportButton, restoreButton, cloneButton

local function report(r, parts, done)
    local out = {}
    if parts.actions then
        out[#out + 1] = count(r.placed, "action", "actions") .. " placed"
        if r.waiting > 0 then out[#out + 1] = count(r.waiting, "spell goes", "spells go") .. " on when learned" end
        if r.skipped > 0 then out[#out + 1] = r.skipped .. " left out (mounts, pets and the like)" end
    end
    if parts.macros then out[#out + 1] = count(r.macros, "macro", "macros") end
    if parts.bindings then out[#out + 1] = count(r.bindings, "key binding", "key bindings") end
    if parts.cvars then out[#out + 1] = count(r.cvars, "setting", "settings") end
    return done .. ": " .. table.concat(out, ", ") .. ". Undo it with the newest backup."
end
local function load(lo, parts, done)
    local r, why = L.load(lo, parts)
    status:SetText(r and report(r, parts, done) or "Not " .. done:lower() .. ": " .. why)
    refresh()
end

-- Dialogs over the window: what each acts on is kept in a local, never read back from the list ---------------------

local function Dialog(w, h) return L.Dialog(frame, w, h) end

-- Load: which parts, all ticked
local loadDialog = Dialog(330, 244)
loadDialog.ok:SetText("Load")
local loading -- the loadout the load dialog is open for
local PARTS = {{"actions", "Action bars"}, {"macros", "Macros"}, {"bindings", "Key bindings"}, {"cvars", "Interface settings"}}
local boxes = {}
for i, p in ipairs(PARTS) do
    local box = St.Checkbox(loadDialog)
    box:SetPoint("TOPLEFT", 8, -68 - (i - 1) * 32) -- 32 apart: the ticks are 29 high
    box.Text:SetText(p[2])
    box.Text:SetFontObject("GameFontHighlight")
    box:SetScript("OnClick", function()
        local any = false
        for _, b in pairs(boxes) do any = any or b:GetChecked() and true end
        loadDialog.ok:SetEnabled(any)
    end)
    boxes[p[1]] = box
end
frame.loadDialog, frame.partBoxes = loadDialog, boxes
loadDialog.ok:SetScript("OnClick", function()
    flush()
    loadDialog:Hide()
    if not (loading and ns.IsOn("loadouts")) then return end
    local parts = {}
    for key, box in pairs(boxes) do parts[key] = box:GetChecked() and true or nil end
    load(loading, parts, "Loaded")
end)

-- Export and Import: one text box; Export's is read-only and selected, Import's takes a paste and a name
local share = Dialog(460, 320)
local sharePane = Pane(share)
sharePane:SetPoint("TOPLEFT", 12, -60)
sharePane:SetPoint("BOTTOMRIGHT", -12, 66)
local shareScroll = CreateFrame("ScrollFrame", nil, sharePane, "ScrollFrameTemplate")
shareScroll:SetPoint("TOPLEFT", 8, -8)
shareScroll:SetPoint("BOTTOMRIGHT", -26, 8)
local shareBox = CreateFrame("EditBox", nil, shareScroll)
shareBox:SetMultiLine(true)
shareBox:SetAutoFocus(false)
shareBox:SetFontObject("ChatFontNormal")
shareBox:SetMaxLetters(L.MAX_IMPORT + 1) -- one over, so a longer paste is refused rather than cut
shareBox:SetWidth(460 - 24 - 34)
shareScroll:SetScrollChild(shareBox)
sharePane:EnableMouse(true)
sharePane:SetScript("OnMouseDown", function() shareBox:SetFocus() end)
shareBox:SetScript("OnEscapePressed", function() share:Hide() end)
shareBox:SetScript("OnTextChanged", function(self, userInput)
    if userInput and share.exported then -- Export's text stays as it is
        self:SetText(share.exported)
        self:HighlightText()
    end
end)
local shareName = St.EditBox(share)
shareName:SetPoint("BOTTOMLEFT", 18, 13)
shareName:SetWidth(200)
shareName:SetMaxLetters(40)
local shareNamePrompt = Prompt(shareName, "Name (or keep the shared one)")
local shareError = Text(share, "GameFontNormalSmall")
shareError:SetPoint("BOTTOMLEFT", 12, 44)
shareError:SetPoint("RIGHT", -12, 0)
shareError:SetTextColor(1, 0.3, 0.3)
share.ok:SetText("Import")
frame.share, frame.shareBox, frame.shareName, frame.shareError = share, shareBox, shareName, shareError

local function openShare(exported, title, text)
    loadDialog:Hide()
    share.exported = exported
    share.title:SetText(title)
    share.text:SetText(text)
    shareBox:SetText(exported or "")
    shareName:SetText("")
    shareNamePrompt:Show()
    shareError:SetText("")
    for _, part in ipairs({share.ok, shareName}) do part:SetShown(not exported) end
    share.cancel:SetText(exported and "Close" or "Cancel")
    share:Show()
    shareBox:SetFocus()
    if exported then shareBox:HighlightText() end
end
importButton:SetScript("OnClick", function()
    openShare(nil, "Import a loadout",
        "Paste a loadout's text below (Ctrl+V) and click Import. You can look it over before you load it.")
end)
exportButton:SetScript("OnClick", function()
    flush()
    local lo, isBackup = chosen()
    if not lo or isBackup then return end
    openShare(L.export(lo), "Export " .. lo.name,
        "Press Ctrl+C to copy it, then share it. Anyone with Kureq Utils can click Import and paste it.")
end)
share.ok:SetScript("OnClick", function()
    if share.exported or not ns.IsOn("loadouts") then return end
    local id, why = L.import(shareBox:GetText(), cleanName(shareName))
    if not id then return shareError:SetText(why) end
    share:Hide()
    selected, tab = id, "bars"
    status:SetText("Imported " .. L.list()[id].name .. ". Look over its tabs before you load it.")
    refresh()
end)

-- Popups for the rest: the loadout travels in a local, as the dialog's data differs between clients
local asking
local POPUPS = {"KUREQUTILS_RESTORE_LOADOUT", "KUREQUTILS_UPDATE_LOADOUT", "KUREQUTILS_DELETE_LOADOUT"}
local function confirm(which, text, fn)
    StaticPopupDialogs[which] = {text = text, button1 = YES or "Yes", button2 = NO or "No",
        OnAccept = function() if asking and ns.IsOn("loadouts") then fn(asking) end end,
        timeout = 0, whileDead = true, hideOnEscape = true}
    StaticPopup_Show(which)
end

loadButton:SetScript("OnClick", function()
    flush()
    local lo, isBackup = chosen()
    if not lo or isBackup then return end
    loading = lo
    share:Hide()
    loadDialog.title:SetText("Load " .. lo.name .. "?")
    loadDialog.text:SetText("Tick what it replaces. What you have now is kept as a backup first.")
    for _, box in pairs(boxes) do box:SetChecked(true) end
    loadDialog.ok:SetEnabled(true)
    loadDialog:Show()
end)
restoreButton:SetScript("OnClick", function()
    local lo, isBackup = chosen()
    if not (lo and isBackup) then return end
    asking = lo
    confirm("KUREQUTILS_RESTORE_LOADOUT", ("Restore your setup from %s? It puts back what that load changed. What you "
        .. "have now is kept as a backup first."):format(stamp(lo.created)),
        function(backup) load(backup, backup.parts or L.ALL, "Restored") end)
end)
updateButton:SetScript("OnClick", function()
    flush()
    local lo, isBackup = chosen()
    if not lo or isBackup then return end
    asking = selected
    confirm("KUREQUTILS_UPDATE_LOADOUT", ("Replace %s with what you have now?"):format(lo.name), function(id)
        local old = L.list()[id]
        if not old then return end
        if InCombatLockdown() then return ns.say("loadouts save out of combat.") end
        L.save(old.name, id)
        status:SetText("Updated " .. old.name .. " from what you have now.")
        refresh()
    end)
end)
cloneButton:SetScript("OnClick", function()
    flush()
    local lo = chosen()
    if not (lo and ns.IsOn("loadouts")) then return end
    selected = L.clone(lo)
    status:SetText(("Made %s, a copy of %s."):format(L.list()[selected].name, lo.name))
    refresh()
end)
deleteButton:SetScript("OnClick", function()
    flush()
    local lo, isBackup = chosen()
    if not lo or isBackup then return end
    asking = selected
    confirm("KUREQUTILS_DELETE_LOADOUT", ("Delete the loadout %s?"):format(lo.name), function(id)
        L.list()[id] = nil
        if selected == id then selected = nil end
        status:SetText("")
        refresh()
    end)
end)

-- Showing the chosen loadout ---------------------------------------------------------------------------------------

local function iconOf(lo, a)
    if a.type == "spell" then
        local name, _, icon = L.spellInfo(a.id or a.name)
        return icon, a.name or name
    elseif a.type == "macro" then
        for _, m in ipairs(lo.macros) do
            if m.name == a.name then return m.icon, "Macro: " .. a.name end
        end
        return 134400, "Macro: " .. a.name -- a general macro (question mark icon)
    elseif a.type == "item" then
        local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(a.id)
        return L.itemIcon(a.id), name or ("Item " .. a.id)
    end
    return 134400, a.type .. " (not loaded)"
end

local function showBars(lo, editable)
    local p = L.preview(lo)
    local shown = 0
    for _, bar in ipairs(BARS) do
        local row, first = barRows[bar[1]], (bar[1] - 1) * 12
        local any = false
        for slot = first + 1, first + 12 do any = any or lo.actions[slot] ~= nil end
        any = any or editable -- a saved loadout shows every bar, to drop things on
        row:SetShown(any)
        for slot = first + 1, first + 12 do icons[slot].editable = editable end
        if any then
            shown = shown + 1
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(SUMMARY_H + (shown - 1) * BAR_H))
            for slot = first + 1, first + 12 do
                local b, a = icons[slot], lo.actions[slot]
                if a then
                    local icon, what = iconOf(lo, a)
                    b.icon:SetTexture(icon or 134400)
                    b.what = what
                else
                    b.what = nil
                end
                b.icon:SetShown(a ~= nil)
                b.changed, b.waiting, b.editable = p.changed[slot], p.waiting[slot], editable
                b.ignored = lo.ignored and lo.ignored[slot] or nil
                b:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], b.changed and 1 or 0)
                -- a spell you don't know yet would wait; an ignored slot isn't loaded
                b.icon:SetDesaturated(b.waiting == true or b.ignored == true)
                b.icon:SetAlpha((b.waiting or b.ignored) and 0.45 or 1)
                b.cross:SetShown(b.ignored == true)
            end
        end
    end
    local text = not next(lo.actions) and "No action bars saved." or ("%s, %s. Gold edges change your bars; dim spells wait."):format(
        count(p.changes, "slot changes", "slots change"), count(p.waits, "spell waits until learned", "spells wait until learned"))
    if p.ignores > 0 then
        text = text .. (" %s: loading leaves %s."):format(count(p.ignores, "slot is crossed out", "slots are crossed out"),
            p.ignores == 1 and "it" or "them")
    end
    local _, class = UnitClass("player")
    if lo.class and class and lo.class ~= class and not lo.anyClass then
        text = text .. (" |cffff8040Saved on a %s: its spells won't match yours.|r"):format(lo.className or lo.class)
    end
    summary:SetText(text)
    return shown * BAR_H
end

local function bindingName(command)
    local macro = command:match("^MACRO (.+)$")
    if macro then return "Macro: " .. macro end
    return GetBindingName and GetBindingName(command) or _G["BINDING_NAME_" .. command] or command
end
local function showLines(lo)
    local n = 0
    lineH = tab == "cvars" and SETTING_H or LINE_H
    local function add(...) n = n + 1; setLine(n, ...) end
    if tab == "macros" then
        for i, m in ipairs(lo.macros) do
            add(L.iconPath(m.icon), m.name, "|cff999999" .. (m.body or ""):match("^[^\n]*") .. "|r", i)
        end
        summary:SetText(n == 0 and "No character macros saved."
            or count(n, "macro", "macros") .. ". Loading replaces your macros with the same names and keeps the others.")
    elseif tab == "bindings" then
        local keys = {}
        for command, ks in pairs(lo.bindings) do
            for _, key in pairs(ks) do keys[#keys + 1] = {GetBindingText and GetBindingText(key) or key, command, key} end
        end
        table.sort(keys, function(a, b) return a[1] < b[1] end)
        for _, k in ipairs(keys) do add(nil, k[1], bindingName(k[2]), {k[2], k[3]}) end
        summary:SetText(n == 0 and "No key bindings saved."
            or count(n, "key", "keys") .. " bound. Loading unbinds the keys this loadout doesn't use.")
    else
        local names = {}
        for name in pairs(lo.cvars) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do add(nil, L.settingName(name), lo.cvars[name], name) end
        summary:SetText(count(n, "interface setting", "interface settings")
            .. " changed from the defaults (Game and Combat settings).")
    end
    for i = n + 1, #lines do lines[i]:Hide() end
    return n * lineH
end

local DETAIL_PARTS = {renameBox, from, contentScroll, tabLine, status}
local TICKS = {anyClassBox}
local function refreshDetail()
    local lo, isBackup = chosen()
    for _, part in ipairs(DETAIL_PARTS) do part:SetShown(lo ~= nil) end
    for _, b in pairs(tabs) do b:SetShown(lo ~= nil) end
    for _, b in ipairs({loadButton, updateButton, exportButton, deleteButton}) do b:SetShown(lo ~= nil and not isBackup) end
    for _, b in ipairs(TICKS) do b:SetShown(lo ~= nil and not isBackup) end
    restoreButton:SetShown(isBackup == true)
    cloneButton:SetShown(lo ~= nil)
    cloneButton:ClearAllPoints()
    cloneButton:SetPoint("LEFT", isBackup and restoreButton or exportButton, "RIGHT", 8, 0)
    emptyText:SetShown(lo == nil)
    if not lo then return L.ui.decorate and L.ui.decorate(tab, nil, true, 0) end
    if not renameBox:HasFocus() then renameBox:SetText(lo.name) end
    anyClassBox:SetChecked(lo.anyClass == true)
    from:SetText(("%s%s|r · %s %s, %s"):format(classColor(lo.class), lo.className or "?",
        isBackup and "backup of" or "saved from", lo.from or "?", stamp(lo.updated or lo.created)))
    for _, t in ipairs(TABS) do tabs[t[1]]:Set(t[2], tab == t[1]) end
    local height
    if tab == "bars" or tab == "rules" then
        for _, r in ipairs(lines) do r:Hide() end
        if tab == "bars" then height = showBars(lo, not isBackup) else
            for _, row in pairs(barRows) do row:Hide() end
            height = 0 -- LoadoutsRules.lua draws it
        end
    else
        for _, row in pairs(barRows) do row:Hide() end
        height = showLines(lo)
    end
    if L.ui.decorate then height = L.ui.decorate(tab, lo, isBackup, height) end -- the editor's controls
    content:SetHeight(SUMMARY_H + height)
end

-- Refresh ----------------------------------------------------------------------------------------------------------

local function refreshTiles()
    local n = 0
    for _ in pairs(L.list()) do n = n + 1 end
    local waiting = 0
    for _ in pairs(L.pending() or {}) do waiting = waiting + 1 end
    local className, class = UnitClass("player")
    local values = {
        {St.commas(n), n == 1 and "loadout saved" or "loadouts saved"},
        {classColor(class) .. (className or "?") .. "|r", "level " .. (UnitLevel("player") or "?")},
        {St.commas(waiting), waiting == 1 and "spell goes on when learned" or "spells go on when learned"},
    }
    for i, t in ipairs(tiles) do
        t.value:SetText(values[i][1])
        t.sub:SetText(values[i][2])
    end
end

-- a click chooses the row; a right-click also opens its menu: Clone, and Delete for a saved loadout
local function pick(self, button)
    selected = self.backup or self.id
    status:SetText("")
    refresh()
    if button ~= "RightButton" or not ns.IsOn("loadouts") then return end
    local isBackup = self.backup ~= nil
    MenuUtil.CreateContextMenu(self, function(_, root)
        root:CreateButton("Clone", function() cloneButton:GetScript("OnClick")(cloneButton) end)
        if not isBackup then
            root:CreateButton("Delete", function() deleteButton:GetScript("OnClick")(deleteButton) end)
        end
    end)
end
local function Row(i)
    local b = St.ListRow(list, i, LIST_W - 32, ROW_H, pick)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    return b
end

function refresh()
    if not frame:IsShown() then return end
    local shown, backups = shownLoadouts(), L.backups()
    if not chosen() then selected = shown[1] and shown[1].id or backups[1] end
    for i, item in ipairs(shown) do
        local b = rows[i] or Row(i)
        rows[i] = b
        local lo = item.lo
        b.id, b.name = item.id, lo.name
        b.nameText:SetText(classColor(lo.class) .. lo.name .. "|r")
        b.count:SetText(lo.anyClass and "Any class" or lo.className or "")
        b.sub:SetText("from " .. (lo.from or "?") .. (L.hasRules(lo) and " · applies by itself" or ""))
        b.each:SetText(date("%d %b", lo.updated or lo.created))
        b:SetPicked(item.id == selected)
        b:Show()
    end
    for i = #shown + 1, #rows do rows[i]:Hide() end
    listCount:SetText(#shown)
    local y = #shown * ROW_H
    for _, part in ipairs({backupTitle, backupHint, backupLine}) do part:SetShown(#backups > 0) end
    backupTitle:SetPoint("TOPLEFT", 6, -(y + 10))
    backupLine:SetPoint("TOPLEFT", 0, -(y + 28))
    backupLine:SetPoint("TOPRIGHT", 0, -(y + 28))
    for i, lo in ipairs(backups) do
        local b = backupRows[i] or Row(i)
        backupRows[i] = b
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 0, -(y + 30 + (i - 1) * ROW_H))
        b.backup, b.name = lo, lo.name
        b.nameText:SetText(lo.name)
        b.count:SetText("")
        b.sub:SetText(stamp(lo.created))
        b.each:SetText("")
        b:SetPicked(lo == selected)
        b:Show()
    end
    for i = #backups + 1, #backupRows do backupRows[i]:Hide() end
    list:SetHeight(math.max(1, y + (#backups > 0 and 30 + #backups * ROW_H or 0)))
    refreshTiles()
    refreshDetail()
end
frame:SetScript("OnShow", refresh)
L.changed = refresh

-- What the editor (LoadoutsEditor.lua) builds on; a part as wide as the content adds fn(width) to resized
L.ui = {frame = frame, detail = detail, content = content, summary = summary, status = status, lines = lines,
    CONTENT_W = CONTENT_W, SUMMARY_H = SUMMARY_H, LINE_H = LINE_H, Button = Button, Prompt = Prompt, Dialog = Dialog,
    chosen = chosen, bindingName = bindingName, refresh = function() refresh() end, resized = {}}

-- Resizing: the list and the detail stretch on their anchors; this re-lays the tiles and what is as wide as the
-- detail's content (its summary, lines, rules and the macro form; the bars and the ready-made cards keep their size)
St.Resizable(frame, function(w)
    local BW = St.bodySize(w, H)
    local tileW = math.floor((BW - 2 * PAD - (#TILES - 1) * GAP) / #TILES)
    for i, t in ipairs(tiles) do
        t:SetPoint("TOPLEFT", PAD + (i - 1) * (tileW + GAP), -(PAD + TOP_H + GAP))
        -- the last one takes what rounding left, so the row ends where the panes below do
        t:SetSize(i < #TILES and tileW or BW - 2 * PAD - (#TILES - 1) * (tileW + GAP), TILE_H)
    end
    CONTENT_W = BW - 2 * PAD - LIST_W - GAP - 12 - 30
    content:SetWidth(CONTENT_W)
    summary:SetWidth(CONTENT_W)
    for _, r in ipairs(lines) do r:SetWidth(CONTENT_W) end
    for _, fn in ipairs(L.ui.resized) do fn(CONTENT_W) end
    if frame:IsShown() then refresh() end -- the summary may wrap onto another line
end)

function L.toggle()
    if frame:IsShown() then frame:Hide() else frame:Show() end
end
L.frame = frame
ns.OnModuleChange("loadouts", function(on)
    if on then return end
    frame:Hide()
    loadDialog:Hide()
    share:Hide()
    for _, which in ipairs(POPUPS) do StaticPopup_Hide(which) end
end)
