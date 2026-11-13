-- The macro code editor (MacroForm.lua puts it in the macro form): JetBrains Mono on a dark panel, line numbers, the
-- line you're on lit, colours for commands, conditions, units and values (MacroCode.lua), a wavy line under each
-- problem (hover it for why; Tab fixes it), completions as you type (Up and Down choose, Tab puts it in), and a status
-- line: the first problem, else what the macro does right now, and the count out of 255.
-- How: the EditBox takes the typing but draws its text clear; a FontString of the same font and width over it shows
-- the coloured copy. The font is monospaced, so rows and columns are counted, not measured.
local _, ns = ...
local C = ns.macroCode

local FONT_FILE = "Interface\\AddOns\\KureqUtils\\media\\fonts\\JetBrainsMono-Regular.ttf"
local SQUIGGLE = "Interface\\AddOns\\KureqUtils\\media\\squiggle.tga"
-- no extra line spacing: the game's EditBox doesn't take it, so its (clear) rows and the coloured copy would drift
-- apart and clicks, the caret and the lit line land on the wrong row
local SIZE, SPACING, GUTTER, ROWS = 13, 0, 30, 8
-- Set on each region, not through a named font object: UI addons that change "all game text" (EllesmereUI) rewrite
-- every named font object, and a proportional face makes clicks and the caret miss the letters.
local function mono(region)
    if region:SetFont(FONT_FILE, SIZE, "") == false and ChatFontNormal then
        region:SetFontObject(ChatFontNormal) -- the bundled font isn't loaded (a new file needs a game restart)
    end
    region:SetJustifyH("LEFT")
    if region.SetSpacing then region:SetSpacing(SPACING) end
    return region
end
C.mono = mono -- the smart macros' read-only text (SmartMacrosWindow.lua)

-- The rows a line of cols characters a row wraps into, as the game wraps: at the last space that fits (the space
-- stays on the row), else in the middle of a word. {first, last} byte offsets in the line.
-- shortcut: counts bytes, so a row with letters like é is a little off; measure the row if that shows.
function C.wrap(s, cols)
    local rows, p = {}, 1
    if s == "" then return {{1, 0}} end
    while p <= #s do
        if #s - p + 1 <= cols then
            rows[#rows + 1] = {p, #s}
            break
        end
        local cut
        for k = p + cols, p + 1, -1 do
            if s:sub(k, k) == " " then cut = k break end
        end
        cut = cut or p + cols - 1
        rows[#rows + 1] = {p, cut}
        p = cut + 1
    end
    return rows
end

-- Wrap lines (the tick by the status line): account-wide, read when drawn (saved variables load after this file),
-- shared by every editor; off, each line keeps one row and the editor scrolls sideways.
C.editors = {}
function C.wrapOn()
    local db = KureqUtilsDB and KureqUtilsDB.macros
    return not (db and db.wrap == false)
end
function C.setWrap(on)
    if KureqUtilsDB and KureqUtilsDB.macros then KureqUtilsDB.macros.wrap = on and true or false end
    for _, e in ipairs(C.editors) do e:Refresh() end
end

local function dark(frame, r, g, b, a)
    local t = frame:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(r, g, b, a)
    return t
end

-- An editor w by h in parent (place it with SetPoint), and its status line in status (a frame the caller places, 16
-- high). code.edit is the EditBox; code.onEdited() runs after each change you type; code.note is added to the
-- unknown-spell problem; code.problems the problems now. code:Refresh() redraws after the text is set.
-- code:SetEditorSize(w, h) resizes it.
function C.Editor(parent, w, h, status)
    local code = CreateFrame("Frame", nil, parent)
    code:SetSize(w, h)
    dark(code, 0.055, 0.06, 0.075, 0.96)
    local edge = CreateFrame("Frame", nil, code, "BackdropTemplate")
    edge:SetAllPoints()
    if edge.SetBackdrop then
        edge:SetBackdrop({edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        edge:SetBackdropBorderColor(1, 1, 1, 0.12)
    end
    local scroll = CreateFrame("ScrollFrame", nil, code, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -6)
    scroll:SetPoint("BOTTOMRIGHT", -22, 6)
    local textW = w - GUTTER - 30
    local page = CreateFrame("Frame", nil, scroll)
    page:SetSize(w - 22, h - 12)
    scroll:SetScrollChild(page)
    code.scroll = scroll
    local rule = page:CreateTexture(nil, "BORDER")
    rule:SetPoint("TOPLEFT", GUTTER, 0)
    rule:SetPoint("BOTTOMLEFT", GUTTER, 0)
    rule:SetWidth(1)
    rule:SetColorTexture(1, 1, 1, 0.08)
    local lit = page:CreateTexture(nil, "BACKGROUND", nil, 1) -- the line you're on
    lit:SetColorTexture(1, 1, 1, 0.05)
    lit:Hide()

    local edit = CreateFrame("EditBox", nil, page)
    edit:SetPoint("TOPLEFT", GUTTER + 6, 0)
    edit:SetWidth(textW)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    mono(edit)
    edit:SetTextColor(1, 1, 1, 0) -- the overlay shows the text
    edit:SetCountInvisibleLetters(true)
    -- The panel places the caret on a click (CaretAt below): in game the box's own click handling put it at the end
    -- whatever line was clicked, so the box takes keys only. shortcut: no drag-to-select with the mouse; select with
    -- Shift and the arrow keys.
    edit:EnableMouse(false)
    code.edit = edit
    local shown = page:CreateFontString(nil, "ARTWORK")
    mono(shown)
    shown:SetPoint("TOPLEFT", edit, "TOPLEFT")
    shown:SetWidth(textW)
    shown:SetJustifyH("LEFT")
    shown:SetJustifyV("TOP")
    shown:SetWordWrap(true)
    -- break inside a word longer than a row ([@mouseover,help][@target,help]...), as the EditBox does; without it
    -- the game cuts the line off with "..." (in the middle of a colour code)
    if shown.SetNonSpaceWrap then shown:SetNonSpaceWrap(true) end
    code.shown = shown
    local caret = page:CreateTexture(nil, "OVERLAY")
    caret:SetColorTexture(1, 1, 1, 0.9)
    caret:SetWidth(1)
    caret:Hide()
    local probe = page:CreateFontString(nil, "ARTWORK")
    mono(probe)
    probe:SetText("0000000000")
    local charW = math.max(1, (probe:GetStringWidth() or 0) / 10)
    if charW <= 1 then charW = SIZE * 0.6 end
    probe:SetWordWrap(true)
    if probe.SetNonSpaceWrap then probe:SetNonSpaceWrap(true) end -- measures rows as shown breaks them
    local lineH = math.max(((probe.GetLineHeight and probe:GetLineHeight()) or SIZE) + SPACING,
        probe:GetStringHeight() or 0) -- one row, as the game draws it
    probe:SetText("")
    -- measure text as shown draws it: C.highlight escapes "|", so a |c code in a /run line shows as letters
    local function measure(t) probe:SetText((t:gsub("|", "||"))) return probe end
    probe:Hide()
    local cols = math.max(1, math.floor(textW / charW))
    code.cols, code.charW, code.lineH = cols, charW, lineH

    local numbers, marks = {}, {}
    code.marks = marks -- the wavy lines, for tests
    code.marks = marks
    local layout = {} -- the rows: {from, to (bytes in the text), y, line}

    local tip -- the problem the tooltip is open for
    local function showTip(owner, p)
        tip = p
        GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
        GameTooltip:AddLine(p.text, 1, 1, 1, true)
        if p.fix then GameTooltip:AddLine("Tab: fix it" .. (p.fix.text ~= "" and (" (" .. p.fix.text .. ")") or ""), 0.2, 1, 0.5, true) end
        GameTooltip:Show()
    end
    local function hideTip()
        if tip then GameTooltip:Hide() end
        tip = nil
    end

    -- Status line: problems or what fires now on the left, the count on the right
    -- a (?) beside the count: hover it for the editing keys
    local help = CreateFrame("Button", nil, status)
    help:SetSize(16, 16)
    help:SetPoint("RIGHT", -2, 0)
    help:SetNormalTexture("Interface\\FriendsFrame\\InformationIcon")
    help:SetHighlightTexture("Interface\\FriendsFrame\\InformationIcon", "ADD")
    help:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Editing keys", 1, 1, 1)
        for _, k in ipairs(C.KEYS) do GameTooltip:AddDoubleLine(k[1], k[2], 1, 0.82, 0, 1, 1, 1) end
        GameTooltip:Show()
    end)
    help:SetScript("OnLeave", function() GameTooltip:Hide() end)
    code.help = help
    code.length = status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    code.length:SetPoint("RIGHT", help, "LEFT", -6, 0)
    code.length:SetJustifyH("RIGHT")
    code.status = status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    code.status:SetPoint("LEFT", 4, 0)
    -- the tick's art keeps its atlas size (30 high), so it's scaled down to sit on the 16-high line
    local wrapBox = ns.style.Checkbox(status, "Wrap lines")
    wrapBox:SetScale(0.75)
    wrapBox:SetPoint("RIGHT", code.length, "LEFT", -((wrapBox.Text:GetStringWidth() or 60) + 14), 0)
    wrapBox:SetScript("OnClick", function(self) C.setWrap(self:GetChecked()) end)
    code.wrapBox = wrapBox
    code.status:SetPoint("RIGHT", wrapBox, "LEFT", -8, 0)
    code.status:SetJustifyH("LEFT")
    code.status:SetWordWrap(false)

    local function mark(n)
        if marks[n] then return marks[n] end
        local m = CreateFrame("Frame", nil, page)
        m:SetFrameLevel(edit:GetFrameLevel() + 2)
        m.texture = m:CreateTexture(nil, "OVERLAY")
        m.texture:SetAllPoints()
        m.texture:SetTexture(SQUIGGLE, "REPEAT", "CLAMP")
        if m.texture.SetHorizTile then m.texture:SetHorizTile(true) end
        -- hover shows why, clicks go through to the text
        if m.SetMouseClickEnabled and m.SetMouseMotionEnabled then
            m:SetMouseClickEnabled(false)
            m:SetMouseMotionEnabled(true)
            m:SetScript("OnEnter", function(self) if self.problem then showTip(self, self.problem) end end)
            m:SetScript("OnLeave", hideTip)
        else
            m:EnableMouse(false)
        end
        marks[n] = m
        return m
    end

    local function rowAt(pos) -- the row the byte after pos (the caret) is on
        for i, r in ipairs(layout) do
            local nextRow = layout[i + 1]
            if pos + 1 >= r.from and (not nextRow or pos + 1 < nextRow.from) then return i, r end
        end
        return #layout, layout[#layout]
    end

    local wrap, hs = true, 0 -- hs: how far it's scrolled sideways (wrap off)
    local placeChoices -- the suggestions follow the text when it scrolls sideways
    local function viewW()
        local vw = scroll:GetWidth()
        return (vw and vw > 0) and vw or w - 22
    end
    local function sideways(to)
        hs = math.max(0, to)
        scroll:SetHorizontalScroll(hs)
        if placeChoices then placeChoices() end
    end
    function code:Refresh()
        wrap = C.wrapOn()
        wrapBox:SetChecked(wrap)
        local widest = 0
        local text = edit:GetText() or ""
        local problems, parsed = C.check(text, {spells = C.spells(), note = code.note})
        code.problems, code.parsed = problems, parsed
        -- the coloured copy, and the rows it takes
        local parts = {}
        layout = {}
        local y = 0
        for i, line in ipairs(parsed.lines) do
            parts[#parts + 1] = C.highlight(line)
            local n = numbers[i] or page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            numbers[i] = n
            n:SetPoint("TOPRIGHT", page, "TOPLEFT", GUTTER - 6, -y - 2)
            n:SetText(i)
            n:Show()
            -- how tall the line really is, as the game wraps it in this font (the count of columns is only a guess
            -- when the font isn't monospaced, e.g. before a restart has loaded it); its rows share that height
            probe:SetWidth(wrap and textW or 0) -- 0: no width, the line's full length
            measure(line.text ~= "" and line.text or " ")
            local tall = wrap and math.max(lineH, probe:GetStringHeight() or lineH) or lineH
            widest = math.max(widest, probe:GetStringWidth() or 0)
            local rows = C.wrap(line.text, wrap and cols or math.huge)
            local step = tall / #rows
            for _, r in ipairs(rows) do
                layout[#layout + 1] = {from = line.from + r[1] - 1, to = line.from + r[2] - 1, y = y, h = step, line = i}
                y = y + step
            end
        end
        code.layout = layout -- for tests
        for i = #parsed.lines + 1, #numbers do numbers[i]:Hide() end
        -- wrap off: the text is as wide as its longest line (plus room for the caret), so nothing wraps. shown keeps
        -- its wrapping on: off, the game may cut a line with "..." instead of drawing it past the width.
        local contentW = wrap and textW or math.max(textW, widest + 2 * charW)
        edit:SetWidth(contentW)
        shown:SetWidth(contentW)
        page:SetWidth(contentW + GUTTER + 8)
        if wrap and hs ~= 0 then sideways(0) end
        shown:SetText(table.concat(parts, "\n"))
        page:SetHeight(math.max(h - 12, y + lineH))
        edit:SetHeight(math.max(h - 12, y + lineH))
        -- a wavy line under each problem, a piece per row it covers
        local used = 0
        for _, p in ipairs(problems) do
            for _, r in ipairs(layout) do
                local a, b = math.max(p.from, r.from), math.min(p.to, math.max(r.to, r.from))
                if a <= b then
                    used = used + 1
                    local m = mark(used)
                    m.problem = p
                    m:ClearAllPoints()
                    m:SetPoint("TOPLEFT", edit, "TOPLEFT", (a - r.from) * charW, -(r.y + r.h - 3)) -- the row's bottom, not the next row's top
                    m:SetSize(math.max(charW, (b - a + 1) * charW), 4)
                    if p.severity == "error" then m.texture:SetVertexColor(1, 0.3, 0.3) else m.texture:SetVertexColor(1, 0.8, 0.2) end
                    m.texture:Show()
                    m:Show()
                end
            end
        end
        -- a marker's number (/tm 8): hover it for the marker's icon and name, through the same (unseen) frames
        for _, line in ipairs(parsed.lines) do
            for _, k in ipairs(C.markersIn(line)) do
                for _, r in ipairs(layout) do
                    if k.from >= r.from and k.from <= math.max(r.to, r.from) then
                        used = used + 1
                        local m = mark(used)
                        m.problem = {text = ("|T%s:16|t %s: %s %s"):format(k.marker.icon, k.marker.name, k.what:lower(),
                            text:sub(k.from, k.to))}
                        m:ClearAllPoints()
                        m:SetPoint("TOPLEFT", edit, "TOPLEFT", (k.from - r.from) * charW, -r.y)
                        m:SetSize((k.to - k.from + 1) * charW, r.h)
                        m.texture:Hide()
                        m:Show()
                        break
                    end
                end
            end
        end
        for i = used + 1, #marks do marks[i]:Hide() end
        -- the status line
        local n = #text
        code.length:SetText(("%s%d / %d|r"):format(n > C.LIMIT and "|cffff4040" or "|cffffffff", n, C.LIMIT))
        local first = problems[1]
        if first then
            local color = first.severity == "error" and "|cffff4040" or "|cffffd100"
            local fixable
            for _, p in ipairs(problems) do if p.fix then fixable = true end end
            code.status:SetText(("%s%d %s|r  %s%s"):format(color, #problems, #problems == 1 and "problem" or "problems",
                first.text, fixable and "  |cff999999Tab to fix|r" or ""))
        else
            local now = C.now(parsed, problems)
            code.status:SetText("|cff33ff99No problems|r" .. (now and ("  |cff999999Now:|r " .. now:gsub("|", "||")) or ""))
        end
    end

    -- Completions ------------------------------------------------------------------------------------------------

    local pop = CreateFrame("Frame", nil, code, "BackdropTemplate")
    pop:SetFrameStrata("DIALOG")
    pop:SetSize(math.min(w - 8, 360), ROWS * 20 + 8)
    if pop.SetBackdrop then
        pop:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        pop:SetBackdropColor(0.08, 0.085, 0.1, 0.98)
        pop:SetBackdropBorderColor(1, 1, 1, 0.2)
    end
    pop:Hide()
    code.popup = pop
    local choices = {items = {}, pick = 1, top = 0}
    code.choices = choices
    pop.rows = {}
    local insertChoice
    for i = 1, ROWS do
        local b = CreateFrame("Button", nil, pop)
        b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 20)
        b:SetSize(pop:GetWidth() - 8, 20)
        b.lit = dark(b, 1, 0.82, 0, 0.15)
        b.label = b:CreateFontString(nil, "OVERLAY")
        mono(b.label)
        b.label:SetPoint("LEFT", 6, 0)
        b.label:SetWidth(150)
        b.label:SetJustifyH("LEFT")
        b.label:SetWordWrap(false)
        b.tag = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.tag:SetPoint("RIGHT", -6, 0)
        b.detail = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        b.detail:SetPoint("LEFT", 162, 0)
        b.detail:SetPoint("RIGHT", b.tag, "LEFT", -6, 0)
        b.detail:SetJustifyH("LEFT")
        b.detail:SetWordWrap(false)
        b:SetScript("OnClick", function(self) insertChoice(choices.items[choices.top + self.n]) end)
        b.n = i
        pop.rows[i] = b
    end
    local function drawChoices()
        for i, b in ipairs(pop.rows) do
            local item = choices.items[choices.top + i]
            b:SetShown(item ~= nil)
            if item then
                b.label:SetText(item.icon and ("|T%s:0|t %s"):format(item.icon, item.label) or item.label)
                b.detail:SetText(item.detail or "")
                b.tag:SetText(item.live == "yes" and "|cff33ff99yes|r" or item.live == "no" and "|cff999999no|r" or "")
                b.lit:SetShown(choices.top + i == choices.pick)
            end
        end
        pop:SetHeight(math.min(ROWS, #choices.items) * 20 + 8)
    end
    local function closeChoices() pop:Hide() end
    code.closeChoices = closeChoices
    local caretX, caretY = 0, 0
    local follow -- keeps the caret in view (below)
    function code:Complete()
        local text = edit:GetText() or ""
        local got = C.complete(text, edit:GetCursorPosition() or #text, {spells = C.spells()})
        if not got or #got.items == 0 then return closeChoices() end
        -- one choice that is just what you typed: nothing to offer
        if #got.items == 1 and got.items[1].insert == text:sub(got.from, got.to) then return closeChoices() end
        choices.items, choices.from, choices.to, choices.pick, choices.top = got.items, got.from, got.to, 1, 0
        drawChoices()
        placeChoices()
        pop:Show()
    end
    function placeChoices()
        pop:ClearAllPoints()
        local lo = wrap and 0 or math.max(0, hs - GUTTER - 6) -- the text's left edge in view
        pop:SetPoint("TOPLEFT", edit, "TOPLEFT", math.max(lo, math.min(caretX, lo + textW - pop:GetWidth())), caretY - lineH)
    end
    function insertChoice(item)
        if not item then return end
        local text = edit:GetText() or ""
        local new, at = C.applyFix(text, {from = choices.from, to = choices.to, text = item.insert})
        edit:SetText(new)
        edit:SetCursorPosition(at)
        closeChoices()
        code:Refresh()
        if code.onEdited then code.onEdited() end
    end
    code.insertChoice = insertChoice
    local function move(by)
        local n = #choices.items
        choices.pick = (choices.pick - 1 + by) % n + 1
        if choices.pick <= choices.top then choices.top = choices.pick - 1 end
        if choices.pick > choices.top + ROWS then choices.top = choices.pick - ROWS end
        drawChoices()
    end
    code.moveChoice = move

    -- The fix Tab makes: the problem the caret is in, else the first one with a fix
    function code:FixAt(pos)
        local any
        for _, p in ipairs(code.problems or {}) do
            if p.fix and pos + 1 >= p.from and pos <= p.to then return p end
            any = any or p.fix and p
        end
        return any
    end

    -- Keys and the caret -------------------------------------------------------------------------------------------

    -- Undo and redo (Ctrl+Z, Ctrl+Shift+Z or Ctrl+Y), and shell editing keys (C.editKey): Ctrl+A/E line start and
    -- end, Ctrl+W delete a word back, Ctrl+U/K delete to the line's start/end, Ctrl+B/F a letter, Alt+B/F or
    -- Ctrl+Left/Right a word, Alt+D delete a word forward.
    local history, before, ours = C.History(100), {text = "", pos = 0}, false
    code.history = history
    local function put(text, pos) -- a change the editor makes itself
        ours = true
        edit:SetText(text)
        ours = false
        edit:SetCursorPosition(pos)
        before = {text = text, pos = pos}
        code:Refresh()
        if code.onEdited then code.onEdited() end
    end
    function code:Key(key, ctrl, shift, alt)
        local text, pos = edit:GetText() or "", edit:GetCursorPosition() or 0
        key = key and key:upper()
        -- While suggestions are open: Up and Down choose (the box moves its caret too, so it's put back), Left closes
        -- them. Read on key down, before the box has moved the caret.
        if pop:IsShown() and not (ctrl or alt) then
            if key == "UP" or key == "DOWN" then
                move(key == "UP" and -1 or 1)
                C_Timer.After(0, function() edit:SetCursorPosition(pos) end)
                return true
            elseif key == "LEFT" then
                closeChoices()
                return true
            end
        end
        if ctrl and (key == "Z" and not shift) then
            local t, p = history:Undo(text, pos)
            if t then put(t, p) end
            return true
        end
        if ctrl and ((key == "Z" and shift) or key == "Y") then
            local t, p = history:Redo(text, pos)
            if t then put(t, p) end
            return true
        end
        if ctrl and shift and key == "A" then -- select everything (the box's own Ctrl+A does it; plain Ctrl+A is line start)
            if edit.HighlightText then edit:HighlightText() end
            return true
        end
        local t, p = C.editKey(key, text, pos, ctrl, alt)
        if not t then return false end
        -- the box's own Ctrl+A selects everything after this runs: undo that on the next frame
        if edit.HighlightText then C_Timer.After(0, function() edit:HighlightText(p, p) edit:SetCursorPosition(p) end) end
        if t ~= text then history:Break(); history:Record(text, pos); history:Break(); put(t, p)
        else edit:SetCursorPosition(p) end
        return true
    end
    edit:SetScript("OnKeyDown", function(_, key)
        code:Key(key, IsControlKeyDown(), IsShiftKeyDown(), IsAltKeyDown())
    end)

    edit:SetScript("OnTextChanged", function(self, user)
        if user then
            history:Record(before.text, before.pos, GetTime())
        elseif not ours and self:GetText() ~= code.typed and self:GetText() ~= before.text then
            history:Reset() -- another macro loaded: its own history starts here (not the game's repeat of a typed change)
        end
        if not ours then before = {text = self:GetText() or "", pos = self:GetCursorPosition() or 0} end
        code:Refresh()
        -- Suggestions open on the next frame, once the caret has moved past what was typed. Only a real replacement
        -- of the text closes them: the game can send a second, not-typed change for the same text (seen in game:
        -- the list flashed and closed).
        if user then
            local typed = self:GetText()
            code.typed = typed
            C_Timer.After(0, function() if edit:HasFocus() and edit:GetText() == typed then code:Complete() end end)
        elseif self:GetText() ~= code.typed then
            closeChoices()
        end
        if user and code.onEdited then code.onEdited() end
    end)
    edit:SetScript("OnTabPressed", function(self)
        if pop:IsShown() then return insertChoice(choices.items[choices.pick]) end
        local p = code:FixAt(self:GetCursorPosition() or 0)
        if not p then return end
        local new, at = C.applyFix(self:GetText() or "", p.fix)
        self:SetText(new)
        self:SetCursorPosition(at)
        code:Refresh()
        if code.onEdited then code.onEdited() end
    end)
    -- Up and Down choose while the list is open: the box moves its caret too, so it's put back after
    edit:SetScript("OnEscapePressed", function(self)
        if pop:IsShown() then return closeChoices() end
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", function()
        closeChoices()
        caret:Hide()
        lit:Hide()
        hideTip()
    end)
    -- keep the caret in view
    function follow()
        local top, view = scroll:GetVerticalScroll(), scroll:GetHeight() or h
        if -caretY < top then scroll:SetVerticalScroll(-caretY)
        elseif -caretY + lineH > top + view then scroll:SetVerticalScroll(-caretY + lineH - view) end
        -- and sideways (wrap off). shortcut: the line numbers scroll away with the text; pin them if that bothers.
        if not wrap then
            if caretX < hs then sideways(caretX)
            elseif GUTTER + 6 + caretX + 2 * charW > hs + viewW() then sideways(GUTTER + 6 + caretX + 2 * charW - viewW()) end
        end
    end
    edit:SetScript("OnCursorChanged", function(self, x, y, _, ch)
        if (self:GetText() or "") == before.text then before.pos = self:GetCursorPosition() or before.pos end
        if history.typing and before.pos ~= history.lastPos then history.lastPos = before.pos end
        caretX, caretY = x or 0, y or 0
        caret:ClearAllPoints()
        caret:SetPoint("TOPLEFT", self, "TOPLEFT", caretX, caretY)
        caret:SetHeight(ch and ch > 0 and ch or lineH)
        caret:SetShown(self:HasFocus())
        lit:ClearAllPoints()
        lit:SetPoint("TOPLEFT", page, "TOPLEFT", GUTTER + 1, caretY)
        lit:SetPoint("RIGHT", page, "RIGHT")
        lit:SetHeight(lineH)
        lit:SetShown(self:HasFocus())
        local pos = self:GetCursorPosition() or 0
        local _, r = rowAt(pos)
        for i, n in ipairs(numbers) do
            if r and i == r.line then n:SetTextColor(1, 1, 1) else n:SetTextColor(0.45, 0.45, 0.45) end
        end
        follow()
        -- in a problem: say why
        local here
        for _, p in ipairs(code.problems or {}) do
            if pos + 1 >= p.from and pos <= p.to then here = p break end
        end
        if here then showTip(self, here) elseif tip then hideTip() end
    end)
    -- A click anywhere on the panel puts the caret where you clicked, worked out from the rows above: the box's own
    -- click handling doesn't get the click everywhere (seen in game: only the last line took the caret).
    function code:CaretAt(cx, cy) -- cx, cy: from the text's top left, in the editor's units
        local row = layout[#layout]
        for _, r in ipairs(layout) do
            if cy < r.y + (r.h or lineH) then row = r break end
        end
        if not row then return 0 end
        local text = edit:GetText() or ""
        local at = row.from - 1 -- the caret before the row's first letter
        for k = row.from, math.max(row.to, row.from - 1) do
            local wide = measure(text:sub(row.from, k)):GetStringWidth() or 0
            measure(text:sub(k, k))
            if wide - (probe:GetStringWidth() or 0) / 2 > cx then break end
            at = k
        end
        return at
    end
    local function clickToCaret()
        edit:SetFocus()
        local x, y = GetCursorPosition()
        local scale, left, top = edit:GetEffectiveScale(), edit:GetLeft(), edit:GetTop()
        if not (x and scale and left and top) then return end
        local at = code:CaretAt(x / scale - left, top - y / scale)
        if edit.HighlightText then edit:HighlightText(at, at) end -- a click clears a selection
        edit:SetCursorPosition(at)
    end
    code:EnableMouse(true)
    code:SetScript("OnMouseDown", clickToCaret)
    -- Shift + mouse wheel scrolls sideways (wrap off); otherwise the template's own scrolling
    local wheel = scroll:GetScript("OnMouseWheel")
    scroll:SetScript("OnMouseWheel", function(self, delta)
        if not wrap and IsShiftKeyDown() then
            local range = self:GetHorizontalScrollRange() or math.huge
            sideways(math.min(range, hs - delta * 6 * charW))
        elseif wheel then
            wheel(self, delta)
        end
    end)
    -- A new size (the window was resized): the rows wrap at the new width. The status line follows its own frame.
    function code:SetEditorSize(nw, nh)
        w, h = nw, nh
        code:SetSize(w, h)
        page:SetSize(w - 22, h - 12)
        textW = w - GUTTER - 30
        cols = math.max(1, math.floor(textW / charW))
        code.cols = cols
        pop:SetWidth(math.min(w - 8, 360))
        for _, b in ipairs(pop.rows) do b:SetWidth(pop:GetWidth() - 8) end
        code:Refresh()
        -- the view changed, not the caret (wrap off, its place stays): scroll no further than the text, then follow it
        if not wrap then sideways(math.min(hs, math.max(0, page:GetWidth() - viewW()))) end
        follow()
        if pop:IsShown() then placeChoices() end
    end
    C.editors[#C.editors + 1] = code
    page:EnableMouse(true)
    page:SetScript("OnMouseDown", clickToCaret)
    return code
end
