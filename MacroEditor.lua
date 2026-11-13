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
local mono
local function monoFont()
    if not mono then
        mono = CreateFont("KureqUtilsMonoFont")
        if mono:SetFont(FONT_FILE, SIZE, "") == false and ChatFontNormal then
            mono:CopyFontObject(ChatFontNormal) -- the bundled font isn't loaded (a new file needs a game restart)
        end
        mono:SetJustifyH("LEFT")
        mono:SetSpacing(SPACING)
    end
    return mono
end
C.monoFont = monoFont -- the smart macros' read-only text (SmartMacrosWindow.lua)

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

local function dark(frame, r, g, b, a)
    local t = frame:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(r, g, b, a)
    return t
end

-- An editor w by h in parent (place it with SetPoint), and its status line in status (a frame the caller places, 16
-- high). code.edit is the EditBox; code.onEdited() runs after each change you type; code.note is added to the
-- unknown-spell problem; code.problems the problems now. code:Refresh() redraws after the text is set.
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
    edit:SetFontObject(monoFont())
    edit:SetTextColor(1, 1, 1, 0) -- the overlay shows the text
    edit:SetCountInvisibleLetters(true)
    -- The panel places the caret on a click (CaretAt below): in game the box's own click handling put it at the end
    -- whatever line was clicked, so the box takes keys only. shortcut: no drag-to-select with the mouse; select with
    -- Shift and the arrow keys.
    edit:EnableMouse(false)
    code.edit = edit
    local shown = page:CreateFontString(nil, "ARTWORK")
    shown:SetFontObject(monoFont())
    shown:SetPoint("TOPLEFT", edit, "TOPLEFT")
    shown:SetWidth(textW)
    shown:SetJustifyH("LEFT")
    shown:SetJustifyV("TOP")
    shown:SetWordWrap(true)
    code.shown = shown
    local caret = page:CreateTexture(nil, "OVERLAY")
    caret:SetColorTexture(1, 1, 1, 0.9)
    caret:SetWidth(1)
    caret:Hide()
    local probe = page:CreateFontString(nil, "ARTWORK")
    probe:SetFontObject(monoFont())
    probe:SetText("0000000000")
    local charW = math.max(1, (probe:GetStringWidth() or 0) / 10)
    if charW <= 1 then charW = SIZE * 0.6 end
    probe:SetWordWrap(true)
    local lineH = math.max(((probe.GetLineHeight and probe:GetLineHeight()) or SIZE) + SPACING,
        probe:GetStringHeight() or 0) -- one row, as the game draws it
    probe:SetText("")
    probe:Hide()
    local cols = math.max(1, math.floor(textW / charW))
    code.cols, code.charW, code.lineH = cols, charW, lineH

    local numbers, marks = {}, {}
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
    code.status:SetPoint("RIGHT", code.length, "LEFT", -8, 0)
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

    function code:Refresh()
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
            probe:SetWidth(textW)
            probe:SetText(line.text ~= "" and line.text or " ")
            local tall = math.max(lineH, probe:GetStringHeight() or lineH)
            local rows = C.wrap(line.text, cols)
            local step = tall / #rows
            for _, r in ipairs(rows) do
                layout[#layout + 1] = {from = line.from + r[1] - 1, to = line.from + r[2] - 1, y = y, h = step, line = i}
                y = y + step
            end
        end
        for i = #parsed.lines + 1, #numbers do numbers[i]:Hide() end
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
                    m:SetPoint("TOPLEFT", edit, "TOPLEFT", (a - r.from) * charW, -(r.y + SIZE + 1))
                    m:SetSize(math.max(charW, (b - a + 1) * charW), 4)
                    if p.severity == "error" then m.texture:SetVertexColor(1, 0.3, 0.3) else m.texture:SetVertexColor(1, 0.8, 0.2) end
                    m:Show()
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
        b.label:SetFontObject(monoFont())
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
                b.label:SetText(item.label)
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
    function code:Complete()
        local text = edit:GetText() or ""
        local got = C.complete(text, edit:GetCursorPosition() or #text, {spells = C.spells()})
        if not got or #got.items == 0 then return closeChoices() end
        -- one choice that is just what you typed: nothing to offer
        if #got.items == 1 and got.items[1].insert == text:sub(got.from, got.to) then return closeChoices() end
        choices.items, choices.from, choices.to, choices.pick, choices.top = got.items, got.from, got.to, 1, 0
        drawChoices()
        pop:ClearAllPoints()
        pop:SetPoint("TOPLEFT", edit, "TOPLEFT", math.min(caretX, math.max(0, textW - pop:GetWidth())), caretY - lineH)
        pop:Show()
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
        -- keep the caret in view
        local top, view = scroll:GetVerticalScroll(), scroll:GetHeight() or h
        if -caretY < top then scroll:SetVerticalScroll(-caretY)
        elseif -caretY + lineH > top + view then scroll:SetVerticalScroll(-caretY + lineH - view) end
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
            probe:SetText(text:sub(row.from, k))
            local wide = probe:GetStringWidth() or 0
            probe:SetText(text:sub(k, k))
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
    page:EnableMouse(true)
    page:SetScript("OnMouseDown", clickToCaret)
    return code
end
