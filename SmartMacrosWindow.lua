-- The Macros window's fourth page, Smart macros (SmartMacros.lua, Ping.lua, Alert.lua): one row per smart macro on the
-- left (its icon, name, an On tick and what it uses now), and the chosen one on the right: what it does, its own
-- settings, the text it writes now (read-only), its icon to drag to a bar and Update now. The settings are the same
-- saved ones (account-wide in KureqUtilsDB.smartMacros, KU Ping's in KureqUtilsDB.ping
-- and KureqUtilsDB.alert); every rule of writing the macros stays in SmartMacros.lua and Ping.lua.
local _, ns = ...
local M, L, St, C = ns.macros, ns.loadouts, ns.style, ns.macroCode
local SM, P = M.smart, ns.ping
local Text, Button = St.Text, L.Button
local U = M.ui

local _, myClass = UnitClass("player")
local KINDS = {}
for _, kind in ipairs(SM.KINDS) do
    if kind ~= "pet" or SM.PET_ACTIONS[myClass] then KINDS[#KINDS + 1] = kind end
end
KINDS[#KINDS + 1] = "ping"
local ICONS = setmetatable({ping = "Ability_Hunter_SniperShot", pet = myClass == "WARLOCK" and "Spell_Shadow_SummonImp"
    or SM.ICONS.pet}, {__index = SM.ICONS})
local PING_TEXT = "Targets a mob, or a quest's mobs, and pings it (the account macro " .. P.NAME .. "). Set what "
    .. "below, with /ku ping <name or quest link>, or by Alt-clicking a quest."

local function nameOf(kind) return kind == "ping" and "KU Ping" or SM.NAMES[kind] end
local function isOn(kind)
    if kind == "ping" then return P.on() end
    local s = SM.db()
    return s and s.on[kind] == true or false
end
local function setOn(kind, v)
    if kind == "ping" then return P.setOn(v) end
    SM.change(function(s)
        s.on[kind] = v or nil
        if v then SM.adopt(s.made, kind, SM.NAMES[kind], true) end
    end)
end
local OFF_TEXT = "Not in use" -- the row's grey line while unticked
local function uses(kind, items)
    if kind ~= "ping" then
        local u = SM.uses(kind, items)
        return u == "off" and OFF_TEXT or u
    end
    if not P.on() then return OFF_TEXT end
    local db = P.db()
    return "Targets " .. (db and db.custom or "nothing yet")
end
local function bodyOf(kind, items)
    if kind == "ping" then return P.preview() end
    local s = SM.db()
    if kind == "mount" and s and s.on.mount and s.made.mount then return s.made.mount.body end -- the mount picked last
    return SM.body(kind, items)
end

local chosen = KINDS[1]
local draw
local list, detail = U.addPage("Smart macros", "smart", "Smart macros", function() draw() end)

-- The list: a row per smart macro --------------------------------------------------------------------------------

local rows = {}
for i, kind in ipairs(KINDS) do
    local r = St.ListRow(list.child, i, U.LIST_W - 32, U.ROW_H, function(self)
        if chosen == self.kind then return end
        chosen = self.kind
        detail.status:SetText("")
        draw()
    end)
    r.kind = kind
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(26, 26)
    r.icon:SetPoint("LEFT", 6, 0)
    r.icon:SetTexture(L.iconPath(ICONS[kind]))
    r.nameText:ClearAllPoints()
    r.nameText:SetPoint("TOPLEFT", 40, -4)
    r.nameText:SetPoint("RIGHT", -70, 0)
    r.nameText:SetText(nameOf(kind))
    r.sub:ClearAllPoints()
    r.sub:SetPoint("BOTTOMLEFT", 40, 5)
    r.sub:SetPoint("RIGHT", -40, 0)
    r.on = St.Checkbox(r)
    r.on:SetPoint("RIGHT", -6, 0)
    r.on.Text:SetText("") -- the tick says it all; its tooltip names it
    r.on:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self:GetChecked() and "In use: untick to remove the macro" or "Tick to make this macro", 1, 1, 1)
        GameTooltip:Show()
    end)
    r.on:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.on:SetScript("OnClick", function(self)
        setOn(kind, self:GetChecked() and true or false)
        draw()
    end)
    r.on:SetScript("OnEnter", function(self)
        St.Tooltip(self, nameOf(kind), {"Tick it to have Kureq Utils make and keep this macro: a General macro, shared "
            .. "by all your characters and written for the one you're on. Unticked, the macro it "
            .. "made is deleted (an earlier version stays in History)."})
    end)
    r.on:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
end
list.child:SetHeight(#KINDS * U.ROW_H)

-- The detail: what it does, its settings, its text, drag and Update now --------------------------------------------

local title = Text(detail, "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 12, -12)
title:SetPoint("RIGHT", -12, 0)
local what = Text(detail, "GameFontHighlightSmall")
what:SetPoint("TOPLEFT", 12, -36)
what:SetPoint("RIGHT", -12, 0)
what:SetWordWrap(true)

-- bottom up: the status line (12), the drag icon and Update now, the macro's text
local TEXT_H, TEXT_Y = 110, 76
local textPane = St.Pane(detail)
textPane:SetPoint("BOTTOMLEFT", 12, TEXT_Y)
textPane:SetPoint("BOTTOMRIGHT", -12, TEXT_Y)
textPane:SetHeight(TEXT_H)
local textLabel = Text(detail, "GameFontNormalSmall")
textLabel:SetPoint("BOTTOMLEFT", textPane, "TOPLEFT", 0, 4)
textLabel:SetText("The macro's text now")
local macroText = textPane:CreateFontString(nil, "OVERLAY")
C.mono(macroText)
macroText:SetPoint("TOPLEFT", 10, -10)
macroText:SetPoint("BOTTOMRIGHT", -10, 10)
macroText:SetJustifyH("LEFT")
macroText:SetJustifyV("TOP")
macroText:SetWordWrap(true)

local drag = CreateFrame("Button", nil, detail)
drag:SetSize(36, 36)
drag:SetPoint("BOTTOMLEFT", 12, 32)
drag.texture = drag:CreateTexture(nil, "ARTWORK")
drag.texture:SetAllPoints()
local dragHl = drag:CreateTexture(nil, "HIGHLIGHT")
dragHl:SetAllPoints()
dragHl:SetColorTexture(1, 1, 1, 0.15)
drag:RegisterForDrag("LeftButton")
-- kind's macro on the cursor (the detail's icon, or dragging its row)
local function pickup(kind)
    local m = SM.find(kind == "ping" and P.NAME or SM.NAMES[kind], true)
    if not (isOn(kind) and m) then
        return detail.status:SetText(("Tick %s first: Kureq Utils makes the macro once it's on."):format(nameOf(kind)))
    end
    local ok, why = M.pickup(m)
    if not ok and why then detail.status:SetText(why) end
end
drag:SetScript("OnDragStart", function() pickup(chosen) end)
drag:SetScript("OnClick", function() pickup(chosen) end)
for _, r in ipairs(rows) do
    r:RegisterForDrag("LeftButton")
    r:SetScript("OnDragStart", function(self) pickup(self.kind) end)
end
drag:SetScript("OnEnter", function(self)
    St.Tooltip(self, "Drag to bar", {"Drag it to an action bar, or click it and then click a slot."})
end)
drag:SetScript("OnLeave", function() GameTooltip:Hide() end)
local dragLabel = Text(detail, "GameFontNormalSmall")
dragLabel:SetPoint("LEFT", drag, "RIGHT", 8, 0)
dragLabel:SetText("Drag to bar")
local updateButton = Button(detail, "Update now", 110)
updateButton:SetPoint("LEFT", dragLabel, "RIGHT", 16, 0)
updateButton:SetScript("OnEnter", function(self)
    St.Tooltip(self, "Update now", {"Rewrites the macro now. It also updates by itself as your bags, level and "
        .. "spells change."})
end)
updateButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
updateButton:SetScript("OnClick", function()
    if not isOn(chosen) then
        return detail.status:SetText(("Tick %s first."):format(nameOf(chosen)))
    end
    local why = InCombatLockdown() and "In combat: it updates once combat ends."
        or MacroFrame and MacroFrame:IsShown() and "Close Blizzard's macro window: it updates then."
        or not SM.ready and "Your macros are still loading: it updates in a moment."
    local kind = chosen
    SM.problems[kind] = nil
    if kind == "ping" then P.update() else SM.update() end
    -- up to date only when it was written: else why not (no slot, a name taken or twice, let go, no target)
    detail.status:SetText(why or SM.problems[kind] or ("%s is up to date."):format(nameOf(kind)))
    draw()
end)

-- The settings: one frame per macro in a scroll pane between the text on top and the macro's text below
local scroll = CreateFrame("ScrollFrame", nil, detail, "ScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 6, -68)
scroll:SetPoint("BOTTOMRIGHT", -26, TEXT_Y + TEXT_H + 22)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(1, 1)
scroll:SetScrollChild(content)
scroll:HookScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)
local noSettings = Text(content, "GameFontDisable")
noSettings:SetPoint("TOPLEFT", 6, -4)
noSettings:SetText("Nothing to set for this one.")

local settings = {} -- kind -> its frame: controls by label, refreshers, y (where the next row goes)
local function Settings(kind)
    local f = CreateFrame("Frame", nil, content)
    f:SetPoint("TOPLEFT")
    f:SetPoint("TOPRIGHT")
    f.y, f.refreshers, f.controls = 0, {}, {}
    settings[kind] = f
    return f
end
local function tip(widget, label, text)
    widget:SetScript("OnEnter", function(self) St.Tooltip(self, label, {text}) end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
local LABEL_X, CONTROL_X = 6, 150 -- a row's gold label, and the control after it
local function Tick(f, label, text, get, set)
    local box = St.Checkbox(f)
    box:SetPoint("TOPLEFT", LABEL_X, f.y)
    box.Text:SetText(label)
    box.Text:SetFontObject("GameFontHighlight")
    box:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        draw()
    end)
    tip(box, label, text)
    f.refreshers[#f.refreshers + 1] = function() box:SetChecked(get() and true or false) end
    f.controls[label], f.y = box, f.y - 32
    return box
end
local function RowLabel(f, label, dy)
    local l = Text(f, "GameFontNormalSmall")
    l:SetPoint("TOPLEFT", LABEL_X + 4, f.y - (dy or 5))
    l:SetText(label)
    return l
end
-- choices: {value, text}; get() the current value, set(value)
local function Choice(f, label, text, choices, get, set)
    RowLabel(f, label)
    local function current()
        local v = get()
        for _, c in ipairs(choices) do if c[1] == v then return c[2] end end
        return choices[1][2]
    end
    local b = St.Dropdown(f, 220, current, function(root)
        for _, c in ipairs(choices) do
            root:CreateRadio(c[2], function() return get() == c[1] end, function()
                set(c[1])
                draw()
            end, c[1])
        end
    end)
    b:SetPoint("TOPLEFT", CONTROL_X, f.y)
    tip(b, label, text)
    f.refreshers[#f.refreshers + 1] = function() b:Refresh() end
    f.controls[label], f.y = b, f.y - 32
    return b
end
-- Enter saves (set returns nil and why to refuse); Escape or clicking away puts the saved value back
local function Box(f, label, text, prompt, get, set)
    RowLabel(f, label)
    local box = St.EditBox(f)
    box:SetPoint("TOPLEFT", CONTROL_X + 6, f.y - 1)
    box:SetWidth(220)
    box:SetMaxLetters(255)
    local hint = L.Prompt(box, prompt)
    local function reset(self)
        self:SetText(get() or "")
        self:SetCursorPosition(0)
        hint:SetShown((self:GetText() or "") == "")
    end
    box:SetScript("OnEnterPressed", function(self)
        local ok, why = set(self:GetText() or "")
        self:ClearFocus()
        reset(self)
        detail.status:SetText(ok == nil and why or "")
        draw()
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); reset(self) end)
    box:HookScript("OnEditFocusLost", reset)
    tip(box, label, text .. "\n\nPress Enter to save.")
    f.refreshers[#f.refreshers + 1] = function() if not box:HasFocus() then reset(box) end end
    f.controls[label], f.y = box, f.y - 32
    return box
end

local function smartSetting(key) return function() local s = SM.db(); return s and s[key] end end
local function setSmart(key) return function(v) SM.change(function(s) s[key] = v end) end end

Tick(Settings("potion"), "Healthstone first", "KU Potion uses a Healthstone before any potion.",
    smartSetting("healthstone"), setSmart("healthstone"))
for _, kind in ipairs({"drink", "food"}) do
    Tick(Settings(kind), "Conjured first", ("%s uses conjured %s (a mage's) before any other, even a stronger one.")
        :format(SM.NAMES[kind], kind == "drink" and "water" or "food"),
        function() local s = SM.db(); return s and s.conjured[kind] end,
        function(v) SM.change(function(s) s.conjured[kind] = v end) end)
end
local mountSettings = Settings("mount")
Tick(mountSettings, "Favourites only", "KU Mount rides only the mounts you marked as favourites in the mount "
    .. "journal (the fastest of them). While you have no favourites it rides any.", smartSetting("favourites"),
    function(v) SM.change(function(s) s.favourites = v or nil end) end)
Tick(mountSettings, "Travel form", "Where you can't mount (indoors, in combat, swimming) or with no mount: your "
    .. "class's form (Ghost Wolf; Travel, Cat or Aquatic Form; Aspect of the Cheetah).",
    function() local s = SM.db(); return s and not s.noForm end,
    function(v) SM.change(function(s) s.noForm = not v or nil end) end)
Tick(mountSettings, "Form instead of a mount", "Always your travel form, never a mount (say, a druid's Travel "
    .. "Form before a fast mount).", smartSetting("formFirst"),
    function(v) SM.change(function(s) s.formFirst = v or nil end) end)

if SM.PET_ACTIONS[myClass] then
    local f = Settings("pet")
    local choices = {{"", "Nothing"}}
    for _, a in ipairs(SM.PET_ACTIONS[myClass]) do choices[#choices + 1] = {a[1], SM.actionLabel(a)} end
    for _, row in ipairs(SM.ROWS) do
        Choice(f, row[2], "What KU Pet does when you press it with this key held. Spells you don't know yet are left "
            .. "out until you learn them.", choices,
            function() return SM.petRows()[row[1]] or "" end,
            function(v) SM.change(function() SM.petRows()[row[1]] = v end) end)
    end
end

do -- KU Ping, with Nearby alert
    local f = Settings("ping")
    local function pingSetting(key) return function() local db = P.db(); return db and db[key] end end
    local function setPing(key) return function(v) P.set(key, v) end end
    Box(f, "Custom target", "The mob " .. P.NAME .. " targets. For a quest's mobs, type /ku in chat and shift-click "
        .. "the quest, or Alt-click it in the quest log.", "A mob's name", pingSetting("custom"),
        function(text) P.setCustom(text); return true end)
    local commands = {}
    for _, c in ipairs(P.TARGET_COMMANDS) do commands[#commands + 1] = {c[1], c[2]} end
    Choice(f, "Targeting command", "How each mob line targets.", commands, pingSetting("targetCmd"), setPing("targetCmd"))
    local marks = {{0, "None"}}
    for i = #P.MARKERS, 1, -1 do
        marks[#marks + 1] = {i, ("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:14|t %s"):format(i, P.MARKERS[i])}
    end
    Choice(f, "Raid marker", "Also put this marker on the target (not on corpses). A marker that's already on stays on.",
        marks, pingSetting("marker"), setPing("marker"))
    Box(f, "Action line", "What the macro does after targeting. Default: " .. ns.defaults.ping.action .. ". Must start "
        .. "with /. Empty puts the default back.", "/ping [@target,nodead]", pingSetting("action"), P.setAction)
    Tick(f, "Clear dead targets", "Clear the target when the targeting lines pick a corpse (adds /cleartarget [dead]).",
        pingSetting("lastTarget"), setPing("lastTarget"))
    Tick(f, "Alt-click quests", "Alt-click a quest in the quest log, or in Questie's tracker, to make " .. P.NAME
        .. " target its mobs.", pingSetting("questClick"), setPing("questClick"))
    Tick(f, "Companion addons' macros", "Let companion addons (Kureq RestedXp) keep their own ping macros, built with "
        .. "these settings.", P.companionsOn, P.setCompanions)

    f.y = f.y - 10
    local header = Text(f, "GameFontNormal")
    header:SetPoint("TOPLEFT", LABEL_X + 4, f.y)
    header:SetText("Nearby alert")
    local about = Text(f, "GameFontDisableSmall")
    about:SetPoint("TOPLEFT", LABEL_X + 4, f.y - 18)
    about:SetPoint("RIGHT", -12, 0)
    about:SetWordWrap(true)
    about:SetText("A sound and an on-screen message when KU Ping's mobs (or a companion addon's) show up nearby. It uses "
        .. "enemy nameplates, so turn those on (V).")
    f.y = f.y - 48
    local A = ns.alert
    Tick(f, "Alert when nearby", "Show a message when one of the watched mobs appears. Off by default.",
        function() return A.get("on") end, function(v) A.set("on", v) end)
    Tick(f, "Play a sound", "Play the raid warning sound with the message.",
        function() return A.get("sound") end, function(v) A.set("sound", v) end)
    local test = Button(f, "Test alert", 100)
    test:SetPoint("TOPLEFT", LABEL_X + 4, f.y - 2)
    test:SetScript("OnClick", function() A.test() end)
    f.controls["Test alert"], f.y = test, f.y - 30
    RowLabel(f, "Watching", 2)
    local watching = Text(f, "GameFontHighlightSmall")
    watching:SetPoint("TOPLEFT", CONTROL_X, f.y - 2)
    watching:SetPoint("RIGHT", -12, 0)
    watching:SetWordWrap(true)
    f.refreshers[#f.refreshers + 1] = function() watching:SetText(A.watching()) end
    f.controls.Watching, f.y = watching, f.y - 40
end

-- Drawing ----------------------------------------------------------------------------------------------------------

function draw()
    local items = SM.bagItems()
    local n = 0
    for _, r in ipairs(rows) do
        local on = isOn(r.kind)
        if on then n = n + 1 end
        r.on:SetChecked(on)
        r.sub:SetText(uses(r.kind, items))
        r:SetPicked(r.kind == chosen)
        r:Show()
    end
    list.count:SetText(("%d in use"):format(n))
    title:SetText(nameOf(chosen))
    what:SetText(chosen == "ping" and PING_TEXT or SM.TEXT[chosen])
    for kind, f in pairs(settings) do
        f:SetShown(kind == chosen)
        if kind == chosen then for _, fn in ipairs(f.refreshers) do fn() end end
    end
    local f = settings[chosen]
    noSettings:SetShown(f == nil)
    if f then f:SetHeight(math.max(1, -f.y)) end -- never 0 high: the game draws nothing anchored in such a frame
    content:SetHeight(f and -f.y + 8 or 30)
    local lines = {}
    for _, line in ipairs(C.parse(bodyOf(chosen, items)).lines) do lines[#lines + 1] = C.highlight(line) end
    macroText:SetText(table.concat(lines, "\n"))
    textLabel:SetText(isOn(chosen) and "The macro's text now" or "The text it writes once ticked")
    drag.texture:SetTexture(L.iconPath(ICONS[chosen]))
end

-- what the tests drive
U.smart = {rows = rows, settings = settings, title = title, what = what, macroText = macroText, drag = drag,
    updateButton = updateButton, status = detail.status, noSettings = noSettings, list = list, detail = detail,
    pick = function(kind) chosen = kind; draw() end}
