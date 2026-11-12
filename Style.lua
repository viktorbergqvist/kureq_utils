-- Kureq Utils' window look, shared by the kill stats and the character notes: the character sheet's background in
-- a Blizzard window, dark panes with the tooltip border, gold plaques and text tabs, and two-line list rows, as in
-- Road to Sixty.
local _, ns = ...
local St = {}
ns.style = St

St.GOLD = {1, 0.82, 0}
local GOLD = St.GOLD

function St.commas(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end

-- The user's Striped bar texture, tinted: every bar and chart column uses it
St.STRIPED = "Interface\\AddOns\\KureqUtils\\Media\\Striped.tga"
function St.Striped(texture, color, vertical)
    texture:SetTexture(St.STRIPED)
    -- a column turns it a quarter, so its length runs up the bar: corners UL, LL, UR, LR
    if vertical then texture:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1) end
    texture:SetVertexColor(color[1], color[2], color[3], 1)
end

-- A pane: the Professions Guide's dark marble ground (Blizzard's inset frame) inside the thin grey tooltip border;
-- the inset's own bevelled border is hidden, its corners look odd on small panes (user decision)
function St.Pane(parent)
    local pane = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
    if type(pane.NineSlice) == "table" then pane.NineSlice:Hide() end
    if type(pane.Bg) == "table" then
        pane.Bg:ClearAllPoints()
        pane.Bg:SetPoint("TOPLEFT", 3, -3)
        pane.Bg:SetPoint("BOTTOMRIGHT", -3, 3)
        pane.Bg:SetVertexColor(0.45, 0.45, 0.45) -- darkened so the clouds don't fight the text (user decision)
    end
    local edge = CreateFrame("Frame", nil, pane, "BackdropTemplate")
    edge:SetAllPoints()
    edge:SetBackdrop({edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12})
    edge:SetBackdropBorderColor(0.6, 0.6, 0.6)
    return pane
end

function St.Text(parent, font, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", font)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

function St.Line(parent, a)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    t:SetColorTexture(1, 1, 1, a or 0.15)
    return t
end

-- A page tab hanging under the window, as on Forever's own windows (Blizzard's PanelTabButtonTemplate): dark, the
-- chosen one lit gold. Tabs line up left to right in the order they're made.
function St.Tab(window, text, onClick)
    window.tabPadding, window.minTabWidth = window.tabPadding or 20, window.minTabWidth or 90
    local b = CreateFrame("Button", nil, window, "PanelTabButtonTemplate")
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    window.kuTabs = window.kuTabs or {}
    local prev = window.kuTabs[#window.kuTabs]
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 3, 0) else b:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 11, 2) end
    window.kuTabs[#window.kuTabs + 1] = b
    if PanelTemplates_TabResize and type(b.Text) == "table" then
        PanelTemplates_TabResize(b, window.tabPadding, nil, window.minTabWidth)
    end
    function b:SetOn(on)
        self.on = on
        if type(self.LeftActive) ~= "table" then return end -- test stubs have no template parts
        if on then PanelTemplates_SelectTab(self) else PanelTemplates_DeselectTab(self) end
    end
    return b
end

-- A text tab: gold and underlined when chosen, grey otherwise. Its text starts 12 in, so a tab row placed at a pane's
-- left edge lines up with a title at 12.
function St.TextTab(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b.label = St.Text(b, "GameFontNormal")
    b.label:SetPoint("CENTER", 0, 1)
    b.underline = b:CreateTexture(nil, "OVERLAY")
    b.underline:SetPoint("BOTTOMLEFT", 12, 0)
    b.underline:SetPoint("BOTTOMRIGHT", -12, 0)
    b.underline:SetHeight(2)
    b.underline:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self) if self.cut then St.Tooltip(self, self.text, {}) end end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- maxW (optional) caps the tab's width: a longer text ends in "..." and shows whole on hover
    function b:Set(text, on, maxW)
        self.label:SetWidth(0) -- back to the text's own width, to measure it
        self.label:SetText(text)
        self.text = text
        local w = math.ceil(self.label:GetStringWidth()) + 24
        self.cut = maxW ~= nil and w > maxW
        if self.cut then
            w = maxW
            self.label:SetWidth(maxW - 24)
        end
        self:SetSize(w, 24)
        if on then self.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) else self.label:SetTextColor(0.6, 0.6, 0.6) end
        self.underline:SetShown(on)
    end
    return b
end

function St.Tooltip(owner, title, lines)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title, 1, 1, 1)
    for _, l in ipairs(lines) do GameTooltip:AddLine(l, nil, nil, nil, true) end
    GameTooltip:Show()
end

-- A list row, the i-th in parent: a title and a value on top, a grey line and a grey value under them, lit gold
-- (SetPicked) when it's the chosen one
function St.ListRow(parent, i, width, height, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetPoint("TOPLEFT", 0, -(i - 1) * height)
    b:SetSize(width, height)
    b.pick = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.pick:SetAllPoints()
    b.pick:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.12)
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetPoint("TOPLEFT")
    b.bar:SetPoint("BOTTOMLEFT")
    b.bar:SetWidth(2)
    b.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    b.nameText = St.Text(b, "GameFontHighlight")
    b.nameText:SetPoint("TOPLEFT", 10, -4)
    b.nameText:SetPoint("RIGHT", -70, 0)
    b.count = St.Text(b, "GameFontHighlight")
    b.count:SetPoint("TOPRIGHT", -8, -4)
    b.count:SetJustifyH("RIGHT")
    b.sub = St.Text(b, "GameFontDisableSmall")
    b.sub:SetPoint("BOTTOMLEFT", 10, 5)
    b.sub:SetPoint("RIGHT", -90, 0)
    b.each = St.Text(b, "GameFontDisableSmall")
    b.each:SetPoint("BOTTOMRIGHT", -8, 5)
    b.each:SetJustifyH("RIGHT")
    b:SetScript("OnClick", onClick)
    function b:SetPicked(on)
        self.pick:SetShown(on)
        self.bar:SetShown(on)
    end
    return b
end

-- A choice button, as in Road to Sixty: a red button showing the current choice (label()), that opens a menu of the
-- choices built by fill(root) (root:CreateRadio, root:CreateButton for a submenu). Picking one closes the menu; the
-- radio's setter changes the choice and the window's refresh calls Refresh to show it.
function St.MenuButton(parent, width, label, fill)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    local text = b:GetFontString()
    if text then -- long choices end in "..." rather than run past the button
        text:SetWidth(width - 16)
        text:SetWordWrap(false)
    end
    b:SetScript("OnClick", function(self) MenuUtil.CreateContextMenu(self, function(_, root) fill(root) end) end)
    function b:Refresh() self:SetText(label()) end
    return b
end

-- A breakdown row, width wide, as Road to Sixty's: a white label and a grey value on top, under them a thin dark
-- track with a bar in color for the share. Set(label, value, share 0-1); place it with SetPoint.
function St.BarRow(parent, width, color)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(width, 22)
    r.value = St.Text(r, "GameFontDisableSmall")
    r.value:SetPoint("TOPRIGHT", 0, -2)
    r.value:SetJustifyH("RIGHT")
    r.label = St.Text(r, "GameFontHighlightSmall")
    r.label:SetPoint("TOPLEFT", 0, -2)
    r.label:SetPoint("RIGHT", r.value, "LEFT", -8, 0) -- a long label ends in "..." before the value
    r.track = r:CreateTexture(nil, "BACKGROUND")
    r.track:SetPoint("BOTTOMLEFT", 0, 4)
    r.track:SetPoint("BOTTOMRIGHT", 0, 4)
    r.track:SetHeight(5)
    r.track:SetColorTexture(0, 0, 0, 0.7)
    r.bar = r:CreateTexture(nil, "ARTWORK")
    r.bar:SetPoint("BOTTOMLEFT", 0, 4)
    r.bar:SetHeight(5) -- fills the track, so the stripes show
    St.Striped(r.bar, color)
    function r:Set(label, value, share)
        self.label:SetText(label)
        self.value:SetText(value)
        self.bar:SetWidth(math.max(1, width * math.min(1, share)))
    end
    return r
end

-- Label / value pairs, as Road to Sixty's cards: a gold label on the left, its white value right-aligned to the
-- column's edge, n of them in columns of colW from (x, y), 18 apart. Returns {label =, value =} for each.
function St.Facts(parent, n, x, y, colW, columns)
    local facts = {}
    for i = 1, n do
        local col, row = (i - 1) % columns, math.floor((i - 1) / columns)
        local fx, fy = x + col * (colW + 16), y - row * 18
        local label = St.Text(parent, "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", parent, "TOPLEFT", fx, fy)
        local value = St.Text(parent, "GameFontHighlightSmall")
        value:SetPoint("TOPRIGHT", parent, "TOPLEFT", fx + colW, fy)
        value:SetJustifyH("RIGHT")
        value:SetWidth(colW - 70) -- a long value ends in "..." before it reaches its label
        facts[i] = {label = label, value = value}
    end
    return facts
end

-- A Blizzard window (ButtonFrameTemplate) as Road to Sixty's: no portrait, inset or button bar, the title bar kept
-- dark, and the content (the body, the frame to build in) on the character sheet's background inside one grey
-- tooltip border, 10 in from the window's own. Movable, closed by Escape. St.bodySize(w, h) is the body's size.
function St.bodySize(w, h) return w - 40, h - 55 end
function St.Window(name, title, w, h)
    local frame = CreateFrame("Frame", name, UIParent, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(frame)
    ButtonFrameTemplate_HideButtonBar(frame)
    frame:SetTitle(title)
    frame:SetSize(w, h)
    frame:SetPoint("CENTER")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame.CloseButton:SetScript("OnClick", function() frame:Hide() end)
    frame:Hide()
    table.insert(UISpecialFrames, name) -- Escape closes it
    frame.Inset:Hide()
    if frame.Bg then -- the background starts under the title bar, so the bar stays dark; Era's border starts elsewhere
        local interface = select(4, GetBuildInfo())
        local left = (interface < 16000 or interface >= 17000) and select(4, frame.Bg:GetPoint(1)) or 6
        frame.Bg:SetPoint("TOPLEFT", left, -21)
        if frame.TopTileStreaks then frame.TopTileStreaks:SetPoint("TOPLEFT", left, -21) end
    end
    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", 20, -35) -- the window's border (6, 21 under the title), a gap of 10, the view border's 4
    body:SetPoint("BOTTOMRIGHT", -20, 20)
    -- no ground or border of its own: the window's background shows through, the panes have borders (user decision)
    return frame, body
end
