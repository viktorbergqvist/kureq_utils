-- Kureq Utils core: saved settings, the settings pages and their widgets, /ku, and the KureqUtils
-- API that companion addons use. The utilities themselves are in Ping.lua and Delete.lua.
local ADDON, ns = ...
local fmt, tinsert = string.format, table.insert

ns.defaults, ns.onLoad, ns.commands = {}, {}, {}

function ns.say(msg, ...) print("|cff33ff99Kureq Utils|r: " .. fmt(msg, ...)) end
function ns.trim(s) return (s or ""):match("^%s*(.-)%s*$") end

-- Settings widgets ---------------------------------------------------------------------------

local function addTooltip(frame, title, text)
    if not text then return end
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(text, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Pages follow Blizzard's own settings pages: a large title over a divider, then one row per
-- setting with its name on the left and the control in a column that starts left of the middle.
local LABEL_X, CONTROL_X, ROW = 37, -80, 32 -- CONTROL_X is relative to the page's horizontal center

-- Content stacks downwards from the label column; panel.y is the next free row, measured from the top of
-- panel.base (the page, or a full-width frame under the last item list, which grows). wide: stretch the
-- widget to the page's right margin (for wrapping text).
local function place(panel, widget, height, x, wide)
    widget:SetPoint("TOPLEFT", panel.base, "TOPLEFT", x or LABEL_X, panel.y)
    if wide then widget:SetPoint("TOPRIGHT", panel.base, "TOPRIGHT", -LABEL_X, panel.y) end
    panel.y = panel.y - height
end
ns.place = place

-- A setting row: returns the vertical center to anchor the control at, and moves panel.y down.
local function settingRow(panel, label)
    local y = panel.y - ROW / 2
    local text = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("LEFT", panel.base, "TOPLEFT", LABEL_X, y)
    text:SetPoint("RIGHT", panel.base, "TOP", CONTROL_X - 12, y)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    text:SetText(label)
    panel.y = panel.y - ROW
    return y
end

-- Blizzard's settings canvas is a fixed ~600px high and doesn't scroll, so a page taller than it (grown item lists)
-- would spill past the window. The canvas frame registered with Blizzard holds a scroll frame; the page (panel,
-- where every widget goes) is its scroll child, as tall as its content. The scroll bar only shows when needed.
local pages = 0
local function newPanel(title, subtitle)
    pages = pages + 1
    local canvas = CreateFrame("Frame")
    local scroll = CreateFrame("ScrollFrame", "KureqUtilsPage" .. pages, canvas, "UIPanelScrollFrameTemplate")
    scroll:SetAllPoints()
    scroll:EnableMouseWheel(true)
    scroll.scrollBarHideable = true -- read on scroll range changes; the template's OnLoad already ran, so hide it now
    scroll.ScrollBar:Hide()
    scroll.ScrollBar:ClearAllPoints() -- in the page's empty right margin, so layout matches a page without a bar
    scroll.ScrollBar:SetPoint("TOPRIGHT", -10, -70)
    scroll.ScrollBar:SetPoint("BOTTOMRIGHT", -10, 16)
    local panel = CreateFrame("Frame", nil, scroll)
    panel:SetSize(1, 1)
    scroll:SetScrollChild(panel)
    scroll:HookScript("OnSizeChanged", function(_, width) panel:SetWidth(width) end)
    canvas.name, canvas.page = title, panel
    panel.name, panel.refreshers, panel.base, panel.canvas = title, {}, panel, canvas
    local header = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    header:SetPoint("TOPLEFT", 7, -16)
    header:SetText(title)
    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    divider:SetPoint("TOPLEFT", 0, -50)
    divider:SetPoint("TOPRIGHT", 0, -50)
    panel.y = -64
    if subtitle then
        local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetJustifyH("LEFT")
        text:SetText(subtitle)
        place(panel, text, 44, nil, true)
    end
    -- Blizzard's settings window calls OnRefresh whenever it displays a page; OnShow alone misses the
    -- first display after a reload (the page frame is already shown), which showed blank values.
    canvas.OnRefresh = function() ns.refresh(panel) end
    canvas:SetScript("OnShow", function() ns.refresh(panel) end)
    return panel
end

-- how far below the page top a base frame starts: each item list's base hangs under its holder
local function depth(base)
    return base.above and depth(base.above) - base.top + base.holder:GetHeight() or 0
end

function ns.refresh(panel)
    for _, refresh in ipairs(panel.refreshers) do refresh() end
    panel:SetHeight(depth(panel.base) - panel.y + 16) -- the scroll range: content height plus a bottom margin
end

-- A section heading inside a page, like Blizzard's.
function ns.Header(panel, text)
    panel.y = panel.y - 10
    local header = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    header:SetText(text)
    place(panel, header, 32, 7)
    return header
end

-- A line of plain text in the label column.
function ns.Label(panel, text, font)
    local label = panel:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    label:SetJustifyH("LEFT")
    label:SetText(text)
    place(panel, label, 22, nil, true)
    return label
end

function ns.Checkbox(panel, label, tooltip, get, set)
    local top = panel.y
    local y = settingRow(panel, label)
    -- SettingsCheckboxTemplate's hover background fills the checkbox's parent (in Blizzard's list, the setting's
    -- row). Parented to the page it lit up the whole screen, so each checkbox gets a row frame like Blizzard's.
    local row = CreateFrame("Frame", nil, panel)
    row:SetPoint("TOPLEFT", panel.base, "TOPLEFT", LABEL_X, top)
    row:SetPoint("TOPRIGHT", panel.base, "TOPRIGHT", -LABEL_X, top)
    row:SetHeight(ROW)
    local box = CreateFrame("CheckButton", nil, row, "SettingsCheckboxTemplate")
    box:SetPoint("LEFT", panel.base, "TOP", CONTROL_X, y)
    box:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    tinsert(panel.refreshers, function() box:SetChecked(get() and true or false) end)
    addTooltip(box, label, tooltip)
    return box
end

-- Enter saves; Escape or clicking away puts the saved value back.
function ns.EditBox(panel, label, tooltip, get, set)
    local y = settingRow(panel, label)
    local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    box:SetPoint("LEFT", panel.base, "TOP", CONTROL_X + 6, y) -- the template's border sits 5px left of the box
    box:SetPoint("RIGHT", panel.base, "TOPRIGHT", -LABEL_X, y)
    box:SetHeight(22)
    box:SetFontObject("ChatFontNormal")
    box:SetAutoFocus(false)
    box:SetMaxLetters(255)
    -- An EditBox can fail to draw text set just as it becomes visible (it showed blank after a
    -- reload); moving the cursor forces a redraw, and the box's own OnShow sets it again once visible.
    local function reset(self)
        self:SetText(get() or "")
        self:SetCursorPosition(0)
    end
    box:SetScript("OnEnterPressed", function(self) set(self:GetText()); self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", reset)
    box:HookScript("OnShow", function(self) if not self:HasFocus() then reset(self) end end)
    tinsert(panel.refreshers, function() reset(box) end)
    addTooltip(box, label, (tooltip and tooltip .. "\n\n" or "") .. "Press Enter to save.")
    return box
end

-- options: list of {value, text, icon}; Blizzard's modern dropdown with one radio entry each.
function ns.Dropdown(panel, label, tooltip, options, get, set)
    local y = settingRow(panel, label)
    local menu = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
    menu:SetPoint("LEFT", panel.base, "TOP", CONTROL_X, y)
    menu:SetWidth(220)
    local entries = {}
    for _, o in ipairs(options) do
        tinsert(entries, {o.icon and fmt("|T%s:14|t %s", o.icon, o.text) or o.text, o.value})
    end
    MenuUtil.CreateRadioMenu(menu, function(value) return get() == value end, function(value) set(value) end,
        unpack(entries))
    tinsert(panel.refreshers, function() menu:GenerateMenu() end) -- shows the saved choice
    addTooltip(menu, label, tooltip)
    return menu
end

-- A button in the control column, with an optional row name.
function ns.Button(panel, label, width, onClick, rowLabel)
    local y = settingRow(panel, rowLabel or "")
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetPoint("LEFT", panel.base, "TOP", CONTROL_X, y)
    button:SetSize(width, 22)
    button:SetText(label)
    button:SetScript("OnClick", onClick)
    return button
end

-- A full-width frame from the row at top down, whose height its owner sets; what's placed after it hangs from its
-- bottom, so the page below moves as it grows.
local function growingRow(panel, top)
    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", panel.base, "TOPLEFT", 0, top)
    holder:SetPoint("TOPRIGHT", panel.base, "TOPRIGHT", 0, top)
    holder:SetHeight(ROW)
    local base = CreateFrame("Frame", nil, panel)
    base:SetPoint("TOPLEFT", holder, "BOTTOMLEFT")
    base:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT")
    base:SetHeight(1)
    base.above, base.top, base.holder = panel.base, top, holder
    panel.base, panel.y = base, 0
    return holder
end

-- A row of item icons in the control column, ending in an empty slot and wrapping onto more rows; the page
-- below it moves down as it grows. Drop a bag item on it (or click it holding one) to add it: the item only
-- goes back to its bag. Right-click an icon to remove it. get() returns the list, item IDs or names not found
-- yet (shown as a question mark); add(itemID) and remove(index) change it, then the page refreshes.
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or _G.GetItemInfoInstant
local ICON, PER_ROW = 28, 10 -- shortcut: a fixed 10 per row fits Blizzard's settings window; measure the column if it gets narrower
local UNKNOWN, EMPTY = "Interface\\Icons\\INV_Misc_QuestionMark", "Interface\\Buttons\\UI-EmptySlot-Disabled"
function ns.ItemList(panel, label, tooltip, get, add, remove)
    local top = panel.y
    settingRow(panel, label)
    local holder = growingRow(panel, top)

    local function drop()
        local kind, id = GetCursorInfo()
        if kind ~= "item" then return false end
        ClearCursor() -- never move or delete the item: it returns to its bag
        add(id)
        ns.refresh(panel)
        return true
    end
    local function onEnter(self)
        local e = self.entry
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if type(e) == "number" then
            GameTooltip:SetHyperlink("item:" .. e)
        elseif e then
            GameTooltip:SetText(e, 1, 1, 1)
            GameTooltip:AddLine("Item not found yet; it still matches by name.", nil, nil, nil, true)
        else
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:AddLine("Drop an item from your bags here.", nil, nil, nil, true)
        end
        if e then GameTooltip:AddLine("Right-click to remove.", 0.5, 0.5, 0.5) end
        GameTooltip:Show()
    end
    local buttons = {}
    local function slot(i)
        if buttons[i] then return buttons[i] end
        local b = CreateFrame("Button", nil, holder)
        b:SetSize(ICON, ICON)
        b:SetPoint("TOPLEFT", holder, "TOP", CONTROL_X + (i - 1) % PER_ROW * ROW,
            -math.floor((i - 1) / PER_ROW) * ROW - (ROW - ICON) / 2)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnReceiveDrag", drop)
        b:SetScript("OnClick", function(self, mouse)
            if not drop() and mouse == "RightButton" and self.entry then
                remove(self.index)
                ns.refresh(panel)
                GameTooltip:Hide()
            end
        end)
        b:SetScript("OnEnter", onEnter)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        buttons[i] = b
        return b
    end
    tinsert(panel.refreshers, function()
        local list = get() or {}
        local n = #list + 1
        for i = 1, math.max(n, #buttons) do
            local b, e = i <= n and slot(i) or buttons[i], list[i]
            b.entry, b.index = e, i
            b.icon:SetTexture(type(e) == "number" and select(5, GetItemInfoInstant(e)) or e and UNKNOWN or EMPTY)
            b:SetShown(i <= n)
        end
        holder:SetHeight(math.ceil(n / PER_ROW) * ROW)
    end)
    return holder
end

-- Rules typed as text: a row with a kind choice, a text box and Add (Enter adds too), then one row per rule reading
-- '<kind>: "<text>"' with a Remove button; the page below moves down as rules are added. kinds: list of {value, text};
-- get() returns the rules, {kind =, text =}; add(kind, text) gets the text exactly as typed (spaces at its ends
-- matter; only blank text is ignored) and skips duplicates; remove(index); note(rule), optional, returns grey text
-- shown after a rule, never cut off: a long rule's text is, and hovering the row shows all of it.
function ns.RuleList(panel, label, tooltip, kinds, get, add, remove, note)
    local y = settingRow(panel, label)
    local names, entries, kind = {}, {}, kinds[1][1]
    for _, k in ipairs(kinds) do names[k[1]] = k[2]; tinsert(entries, {k[2], k[1]}) end
    local menu = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
    menu:SetPoint("LEFT", panel.base, "TOP", CONTROL_X, y)
    menu:SetWidth(120)
    MenuUtil.CreateRadioMenu(menu, function(v) return v == kind end, function(v) kind = v end, unpack(entries))
    local addButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addButton:SetPoint("RIGHT", panel.base, "TOPRIGHT", -LABEL_X, y)
    addButton:SetSize(80, 22)
    addButton:SetText("Add")
    local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    box:SetPoint("LEFT", menu, "RIGHT", 14, 0) -- the template's border sits 5px left of the box
    box:SetPoint("RIGHT", addButton, "LEFT", -8, 0)
    box:SetHeight(22)
    box:SetFontObject("ChatFontNormal")
    box:SetAutoFocus(false)
    box:SetMaxLetters(100)
    local function submit()
        local text = box:GetText() or ""
        box:SetText("")
        box:ClearFocus()
        if ns.trim(text) ~= "" then add(kind, text) end
        ns.refresh(panel)
    end
    box:SetScript("OnEnterPressed", submit)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    addButton:SetScript("OnClick", submit)
    for _, f in ipairs({menu, box, addButton}) do addTooltip(f, label, tooltip) end

    local holder = growingRow(panel, panel.y)
    holder:SetHeight(0)
    holder.ruleMenu, holder.ruleBox, holder.addButton, holder.rows = menu, box, addButton, {}
    local rows = holder.rows
    local function row(i)
        if rows[i] then return rows[i] end
        local r = CreateFrame("Frame", nil, holder)
        r:SetPoint("TOPLEFT", holder, "TOP", CONTROL_X, -(i - 1) * ROW)
        r:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -LABEL_X, -(i - 1) * ROW)
        r:SetHeight(ROW)
        r.remove = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.remove:SetPoint("RIGHT")
        r.remove:SetSize(80, 22)
        r.remove:SetText("Remove")
        r.remove:SetScript("OnClick", function() remove(r.index); ns.refresh(panel) end)
        r.note = r:CreateFontString(nil, "ARTWORK", "GameFontDisable") -- one anchor: as wide as its text
        r.note:SetPoint("RIGHT", r.remove, "LEFT", -8, 0)
        r.label = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        r.label:SetPoint("LEFT")
        r.label:SetPoint("RIGHT", r.note, "LEFT", -4, 0)
        r.label:SetJustifyH("LEFT")
        r.label:SetWordWrap(false)
        r:EnableMouse(true)
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.full, 1, 1, 1)
            if self.extra then GameTooltip:AddLine(self.extra, 0.5, 0.5, 0.5) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = r
        return r
    end
    tinsert(panel.refreshers, function()
        menu:GenerateMenu()
        local list = get() or {}
        for i = 1, math.max(#list, #rows) do
            local rule, r = list[i], list[i] and row(i) or rows[i]
            if rule then
                -- quoted, so spaces at the ends show; "||" draws a "|"
                r.index, r.extra = i, note and note(rule)
                r.full = fmt('%s: "%s"', names[rule.kind] or rule.kind, (rule.text:gsub("|", "||")))
                r.label:SetText(r.full)
                r.note:SetText(r.extra or "")
            end
            r:SetShown(rule ~= nil)
        end
        holder:SetHeight(#list * ROW)
    end)
    return holder
end

-- Pages: "Kureq Utils" with one sub-page per utility ------------------------------------------

local root = newPanel("Kureq Utils", "Small utilities, one page each below.")
-- Modules add their checkbox as they register, the separate addons after Kureq Utils has loaded, so the
-- checkboxes go in a row that grows, with the commands below it.
ns.Header(root, "Modules")
local moduleRows = growingRow(root, root.y)
ns.Header(root, "Commands")
ns.Label(root, "/ku - opens these settings")

local rootCategory
if Settings and Settings.RegisterCanvasLayoutCategory then
    rootCategory = Settings.RegisterCanvasLayoutCategory(root.canvas, root.name)
    Settings.RegisterAddOnCategory(rootCategory)
end

-- Modules: each utility can be turned off per character from the root page. Off is saved as
-- KureqUtilsCharDB.modules[key] = false; until the saved variables load, everything is on.
local modules, moduleListeners, covers = {}, {}, {}

function ns.IsOn(key) return not (ns.charDB and ns.charDB.modules[key] == false) end

-- fn(on) runs when the user turns the module on or off
function ns.OnModuleChange(key, fn)
    moduleListeners[key] = moduleListeners[key] or {}
    tinsert(moduleListeners[key], fn)
end

local function updateCovers()
    for _, cover in ipairs(covers) do cover:SetShown(not ns.IsOn(cover.key)) end
end

function ns.SetModule(key, on)
    if not ns.charDB or ns.IsOn(key) == on then return end
    if on then ns.charDB.modules[key] = nil else ns.charDB.modules[key] = false end
    updateCovers()
    for _, fn in ipairs(moduleListeners[key] or {}) do fn(on) end
end

-- the order of the calls is the order on the page
function ns.AddModule(key, name, description)
    if modules[key] then return end
    modules[key] = {name = name}
    tinsert(modules, key)
    local base, y = root.base, root.y
    root.base, root.y = moduleRows, -(#modules - 1) * ROW
    ns.Checkbox(root, name, description, function() return ns.IsOn(key) end, function(on) ns.SetModule(key, on) end)
    root.base, root.y = base, y
    moduleRows:SetHeight(#modules * ROW)
end

-- key: the module the page belongs to; while it's off a cover dims the page and takes its clicks
function ns.AddSettingsPage(title, subtitle, key)
    local page = newPanel(title, subtitle)
    if key then
        local cover = CreateFrame("Frame", nil, page)
        cover:SetPoint("TOPLEFT", 0, -52) -- under the title's divider
        cover:SetPoint("BOTTOMRIGHT")
        cover:EnableMouse(true)
        local dim = cover:CreateTexture(nil, "BACKGROUND")
        dim:SetAllPoints()
        dim:SetColorTexture(0, 0, 0, 0.6)
        local band = cover:CreateTexture(nil, "BORDER") -- darker behind the banner, so the page's text doesn't show through it
        band:SetPoint("TOPLEFT")
        band:SetPoint("TOPRIGHT")
        band:SetHeight(32)
        band:SetColorTexture(0, 0, 0, 0.9)
        cover.banner = cover:CreateFontString(nil, "ARTWORK", "GameFontDisable")
        cover.banner:SetPoint("LEFT", cover, "TOPLEFT", LABEL_X, -16)
        cover.banner:SetText("Turned off on the Kureq Utils page.")
        cover.key = key
        -- above every control made after it, also after the settings window reparents the page
        tinsert(page.refreshers, function() cover:SetFrameLevel(page:GetFrameLevel() + 100) end)
        tinsert(covers, cover)
        cover:SetShown(not ns.IsOn(key))
        page.cover = cover
    end
    local sub = rootCategory and Settings.RegisterCanvasLayoutSubcategory(rootCategory, page.canvas, title)
    return page, sub
end

-- What combat blocks (macros, action bars, opening the settings) waits for it to end: Defer(key, fn) runs fn now out
-- of combat; in combat it keeps fn under key (a later Defer with the same key replaces it) and runs each kept fn once
-- when combat ends, in the order first deferred. The only PLAYER_REGEN_ENABLED registration (tools/guardrails.py).
local deferred, deferredKeys = {}, {}
local combatQueue = CreateFrame("Frame")
combatQueue:RegisterEvent("PLAYER_REGEN_ENABLED")
combatQueue:SetScript("OnEvent", function()
    local fns, keys = deferred, deferredKeys
    deferred, deferredKeys = {}, {}
    for _, key in ipairs(keys) do xpcall(fns[key], geterrorhandler()) end -- one error doesn't stop the rest
end)
ns.CombatQueue = {}
function ns.CombatQueue.Defer(key, fn)
    if not InCombatLockdown() then return fn() end
    if not deferred[key] then tinsert(deferredKeys, key) end
    deferred[key] = fn
end

-- WoW Forever blocks an addon opening the settings in combat ("Interface action failed because of an AddOn"), so
-- then they open when combat ends.
function ns.OpenSettings(category)
    category = category or rootCategory
    if not (category and Settings and Settings.OpenToCategory) then return end
    if InCombatLockdown() then ns.say("the settings open when combat ends.") end
    ns.CombatQueue.Defer("settings", function() Settings.OpenToCategory(category:GetID()) end)
end

-- /ku <command> ... ; each utility registers its commands (and a help line) in ns.commands.
-- key: the module it belongs to; while that's off the command only says so
function ns.whenOn(key, fn)
    return function(...)
        if ns.IsOn(key) then return fn(...) end
        ns.say("%s is off; turn it on in /ku.", modules[key].name)
    end
end

function ns.AddCommand(name, usage, fn, key)
    ns.commands[name] = key and ns.whenOn(key, fn) or fn
    ns.Label(root, usage)
end

SLASH_KUREQUTILS1 = "/ku"
SlashCmdList.KUREQUTILS = function(msg)
    if not ns.db then return end
    local cmd, rest = ns.trim(msg):match("^(%S*)%s*(.-)$")
    local fn = ns.commands[cmd:lower()]
    if fn then return fn(rest) end
    -- a bare link (/ku <shift-clicked quest>) goes to the utility that takes links
    if ns.linkHandler and msg:find("|H") then return ns.linkHandler(ns.trim(msg)) end
    ns.OpenSettings()
    if cmd ~= "" then ns.say("unknown command %s; the settings page lists them.", cmd) end
end

-- Minimap button, built like LibDBIcon's at a fixed spot on the edge; EllesmereUIMinimap gathers named minimap
-- buttons into its flyout. LibDBIcon's two layouts: the minimap art changed when the addon compartment came in.
do
    local modern = AddonCompartmentFrame ~= nil
    local button = CreateFrame("Button", "KureqUtilsMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    if modern then
        background:SetSize(24, 24)
        background:SetPoint("CENTER")
        icon:SetSize(18, 18)
        icon:SetPoint("CENTER")
    else
        background:SetSize(20, 20)
        background:SetPoint("TOPLEFT", 7, -5)
        icon:SetSize(17, 17)
        icon:SetPoint("TOPLEFT", 7, -6)
    end
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(modern and 50 or 53, modern and 50 or 53)
    border:SetPoint("TOPLEFT")
    local angle, radius = math.rad(200), Minimap:GetWidth() / 2 + 5
    button:SetPoint("CENTER", Minimap, "CENTER", radius * math.cos(angle), radius * math.sin(angle))
    -- left-click: the settings; right-click: a menu of the windows (each utility that has one, when loaded)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(self, mouse)
        if mouse ~= "RightButton" then return ns.OpenSettings() end
        -- Owned by the screen, not the button: a menu closes when its owner hides, and EllesmereUIMinimap's flyout
        -- (which holds the button) hides on a press outside it, so a click on a lower entry never landed.
        MenuUtil.CreateContextMenu(nil, function(_, root)
            root:CreateTitle("Kureq Utils")
            if ns.stats and ns.IsOn("stats") then root:CreateButton("Kill stats", function() ns.stats.toggle() end) end
            if ns.notes and ns.IsOn("notes") then root:CreateButton("Character notes", function() ns.notes.toggle() end) end
            if ns.loadouts and ns.IsOn("loadouts") then
                root:CreateButton("Loadouts", function() ns.loadouts.toggle() end)
            end
            root:CreateDivider()
            root:CreateButton("Settings", function() ns.OpenSettings() end)
        end)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Kureq Utils", 1, 1, 1)
        GameTooltip:AddLine("Click to open the settings.")
        GameTooltip:AddLine("Right-click for kill stats, notes and loadouts.")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    KureqUtilsDB = type(KureqUtilsDB) == "table" and KureqUtilsDB or {}
    ns.db = KureqUtilsDB
    ns.db.mark = nil -- the auto marks' settings; that utility was removed
    KureqUtilsCharDB = type(KureqUtilsCharDB) == "table" and KureqUtilsCharDB or {}
    if type(KureqUtilsCharDB.modules) ~= "table" then KureqUtilsCharDB.modules = {} end
    ns.charDB = KureqUtilsCharDB
    updateCovers()
    for section, defaults in pairs(ns.defaults) do
        local t = type(ns.db[section]) == "table" and ns.db[section] or {}
        for k, v in pairs(defaults) do if t[k] == nil then t[k] = v end end
        ns.db[section] = t
    end
    for _, fn in ipairs(ns.onLoad) do fn(ns.db) end
end)

-- API for companion addons ---------------------------------------------------------------------
KureqUtils = {
    -- macro text for these names (lowest priority first), with the ping macro settings
    Build = function(names) return ns.build(names) end,
    -- create the macro if needed and set its text; call out of combat
    WriteMacro = function(name, text) return ns.writeMacro(name, text) end,
    -- fn() runs after a ping macro setting changes, so companions can rebuild their macros
    OnChange = function(fn) tinsert(ns.listeners, fn) end,
    -- KureqPingCustom targets these names (lowest priority first), shown as label, until another target is set
    SetCustomTargets = function(label, names) return ns.setCustomNames(label, names) end,
    -- the nearby alert watches these mob names under this source name (replacing its last list)
    SetWatchList = function(source, names) ns.setWatch(source, names) end,
    -- the lowercased mob or item a quest objective text names ("Boar Tusk: 1/5" -> "boar tusk")
    ObjectiveName = function(text) return ns.objectiveName(text) end,
    -- a settings sub-page under Kureq Utils (key: its module's); returns the panel and its category
    AddSettingsPage = ns.AddSettingsPage,
    OpenSettings = ns.OpenSettings,
    -- CombatQueue.Defer(key, fn): fn now out of combat, else once when combat ends (the last fn per key)
    CombatQueue = ns.CombatQueue,
    Checkbox = ns.Checkbox,
    Header = ns.Header,
    Label = ns.Label,
}
