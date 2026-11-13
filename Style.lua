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
St.STRIPED = "Interface\\AddOns\\KureqUtils\\media\\Striped.tga"
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

-- The settings page's controls (Core.lua), for the windows. Both clients have these templates (origin/forever and
-- classic_era of the UI source).

-- A choice, as the settings page's: Blizzard's dropdown (WowStyle1DropdownTemplate) showing label(), its menu built by
-- fill(root) as St.MenuButton's. The menu is set up on the first Refresh, not at file load: setting it up reads the
-- radios' selections, and saved variables aren't loaded then. Menus of actions (Insert, Add...) stay St.MenuButton.
function St.Dropdown(parent, width, label, fill)
    local d = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    d:SetWidth(width)
    d:SetSelectionText(function() return label() end)
    local ready
    function d:Refresh()
        if not ready then
            ready = true
            self:SetupMenu(function(_, root) fill(root) end)
        end
        self:GenerateMenu()
    end
    return d
end

-- A tick, as the settings page's (SettingsCheckboxTemplate: the large square box with a gold tick), with its label in
-- box.Text to its right. The template's own hover shows an empty settings tooltip and lights the whole of its parent,
-- so it's left out: set OnEnter for a tooltip.
function St.Checkbox(parent, label, font)
    local box = CreateFrame("CheckButton", nil, parent, "SettingsCheckboxTemplate")
    box:SetScript("OnEnter", nil)
    box:SetScript("OnLeave", nil)
    box.Text = St.Text(box, font or "GameFontHighlight")
    box.Text:SetPoint("LEFT", box, "RIGHT", 4, 0)
    box.Text:SetText(label or "")
    return box
end

-- A text box, as the settings page's: InputBoxTemplate 22 high in the chat font, no focus until clicked.
function St.EditBox(parent, width, letters)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetHeight(22)
    if width then box:SetWidth(width) end
    box:SetFontObject("ChatFontNormal")
    box:SetAutoFocus(false)
    if letters then box:SetMaxLetters(letters) end
    return box
end

-- A breakdown row, width wide, as Road to Sixty's: a white label and a grey value on top, under them a thin dark
-- track with a bar in color for the share. Set(label, value, share 0-1); place it with SetPoint; Resize(width) when
-- its pane changes size.
function St.BarRow(parent, width, color)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(width, 22)
    r.share = 0
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
        self.share = share
        self.bar:SetWidth(math.max(1, width * math.min(1, share)))
    end
    function r:Resize(w)
        width = w
        self:SetWidth(w)
        self.bar:SetWidth(math.max(1, w * math.min(1, self.share)))
    end
    return r
end

-- Label / value pairs, as Road to Sixty's cards: a gold label on the left, its white value right-aligned to the
-- column's edge, n of them in columns of colW from (x, y), 18 apart. Returns {label =, value =} for each, and
-- facts:SetColumnWidth(colW) to place them again when the pane changes size.
function St.Facts(parent, n, x, y, colW, columns)
    local facts = {}
    for i = 1, n do
        facts[i] = {label = St.Text(parent, "GameFontNormalSmall"), value = St.Text(parent, "GameFontHighlightSmall")}
        facts[i].value:SetJustifyH("RIGHT")
    end
    function facts:SetColumnWidth(w)
        for i, f in ipairs(self) do
            local col, row = (i - 1) % columns, math.floor((i - 1) / columns)
            local fx, fy = x + col * (w + 16), y - row * 18
            f.label:ClearAllPoints()
            f.label:SetPoint("TOPLEFT", parent, "TOPLEFT", fx, fy)
            f.value:ClearAllPoints()
            f.value:SetPoint("TOPRIGHT", parent, "TOPLEFT", fx + w, fy)
            f.value:SetWidth(w - 70) -- a long value ends in "..." before it reaches its label
        end
    end
    facts:SetColumnWidth(colW)
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

-- Resizing, which a window opts into once its content is built: Blizzard's resize grip at the bottom right, the
-- design size the smallest, the screen the largest. onResize(w, h) re-lays what anchors can't stretch; it runs now
-- with the design size, at every size change, and once saved variables load with the size saved for the window
-- (account-wide, KureqUtilsDB.windows[name]). A double-click on the grip goes back to the design size.
ns.defaults.windows = {}
local resizable = {}
-- the largest size: the screen, less the page tabs hanging under the window (St.Tab: 32 high, 2 of it on the window)
local TABS_H = 30
local function largest(frame)
    local sw, sh = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
    if sw <= 0 then return math.huge, math.huge end
    return math.max(frame.designW, sw), math.max(frame.designH, sh - (frame.kuTabs and TABS_H or 0))
end
local function bound(frame)
    local mw, mh = largest(frame)
    frame:SetResizeBounds(frame.designW, frame.designH, mw ~= math.huge and mw or nil, mh ~= math.huge and mh or nil)
end
local function fit(frame, w, h)
    local mw, mh = largest(frame)
    w, h = math.min(mw, math.max(frame.designW, w)), math.min(mh, math.max(frame.designH, h))
    frame:SetSize(w, h)
    frame.onResize(w, h)
end
local function restore(frame, db)
    local saved = db.windows[frame:GetName()]
    if type(saved) ~= "table" or type(saved.w) ~= "number" or type(saved.h) ~= "number" then return false end
    fit(frame, saved.w, saved.h)
    return true
end
function St.Resizable(frame, onResize)
    local name = frame:GetName()
    frame.designW, frame.designH, frame.onResize = frame:GetWidth(), frame:GetHeight(), onResize
    frame:SetResizable(true)
    bound(frame)
    frame:SetScript("OnSizeChanged", function(self, w, h) self.onResize(w, h) end)
    local grip = CreateFrame("Button", nil, frame, "PanelResizeButtonTemplate")
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetFrameLevel(frame:GetFrameLevel() + 10) -- over the panes
    grip:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        local w, h = math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5)
        local design = w == frame.designW and h == frame.designH
        if ns.db then ns.db.windows[name] = not design and {w = w, h = h} or nil end
        frame.onResize(w, h)
    end)
    grip:SetScript("OnDoubleClick", function()
        if ns.db then ns.db.windows[name] = nil end
        fit(frame, frame.designW, frame.designH)
    end)
    frame.resizeGrip = grip
    resizable[#resizable + 1] = frame
    onResize(frame.designW, frame.designH)
    if ns.db then restore(frame, ns.db) end -- made after saved variables loaded
end
ns.onLoad[#ns.onLoad + 1] = function(db)
    for _, frame in ipairs(resizable) do restore(frame, db) end
end
-- a new screen size or UI scale: new bounds, and every window (open or at its saved size) fitted to them. The saved
-- size itself is kept, so a larger screen later gets it back.
local screenWatch = CreateFrame("Frame")
screenWatch:RegisterEvent("DISPLAY_SIZE_CHANGED")
screenWatch:RegisterEvent("UI_SCALE_CHANGED")
screenWatch:SetScript("OnEvent", function()
    for _, frame in ipairs(resizable) do
        bound(frame)
        if not (ns.db and restore(frame, ns.db)) then fit(frame, frame:GetWidth(), frame:GetHeight()) end
    end
end)
