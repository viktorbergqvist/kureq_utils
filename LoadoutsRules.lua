-- The loadouts window's "Apply automatically" tab (LoadoutsWindow.lua shows it, Loadouts.lua keeps and runs the
-- rules): a saved loadout's rules, each a block of two lines. The first: On, what sets it off (a menu), the level or
-- spell it waits for, Ask first and Remove. The second: which classes (a menu of ticks, none = any) and which names
-- (only these, or all but these, comma separated). Each change saves at once to the loadout; Revert changes puts it
-- back. Backups have no rules.
local _, ns = ...
local L, St = ns.loadouts, ns.style
local U = L.ui
local Text, Button = St.Text, U.Button
local frame, detail, content, summary = U.frame, U.detail, U.content, U.summary
local W, TOP = U.CONTENT_W, U.SUMMARY_H -- W follows the window's size (U.resized below)
local BLOCK_H = 70 -- two lines of ticks, dropdowns and boxes (29 high), 32 apart
local CLASSES = {"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"}
local function className(class) return LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class end

local addButton = Button(detail, "Add rule", 100)
addButton:SetPoint("TOPRIGHT", -12, -59)
addButton:Hide()
frame.addRuleButton = addButton

local blocks = {}
frame.ruleBlocks = blocks
U.resized[#U.resized + 1] = function(w)
    W = w
    for _, b in ipairs(blocks) do
        b:SetWidth(w)
        b.namesBox:SetWidth(w - 280)
    end
end
local function rule(b) return b.lo and b.lo.rules and b.lo.rules[b.i] end
local function set(b, fields)
    if rule(b) then L.setRule(b.lo, b.i, fields) end
end

local function Tick(parent, label, x, onClick)
    local box = St.Checkbox(parent)
    box:SetPoint("TOPLEFT", x, 1)
    box.Text:SetText(label)
    box.Text:SetFontObject("GameFontHighlightSmall")
    box:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    return box
end
local function Box(parent, w, prompt, onText)
    local box = St.EditBox(parent)
    box:SetWidth(w)
    box.prompt = U.Prompt(box, prompt)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnTextChanged", function(self, userInput) if userInput then onText(self:GetText() or "") end end)
    return box
end

local function Block(n)
    local b = CreateFrame("Frame", nil, content)
    b:SetSize(W, BLOCK_H)
    b:SetPoint("TOPLEFT", 0, -(TOP + (n - 1) * BLOCK_H))
    b.on = Tick(b, "On", 0, function(on)
        set(b, {off = not on})
        U.refresh()
    end)
    b.trigger = St.Dropdown(b, 130, function()
        local r = rule(b)
        for _, t in ipairs(L.TRIGGERS) do
            if r and r.trigger == t[1] then return t[2] end
        end
        return ""
    end, function(root)
        for _, t in ipairs(L.TRIGGERS) do
            root:CreateRadio(t[2], function() local r = rule(b); return r and r.trigger == t[1] end, function()
                set(b, {trigger = t[1]})
                U.refresh()
            end, t[1])
        end
    end)
    b.trigger:SetPoint("TOPLEFT", 52, 0)
    b.levelBox = Box(b, 40, "Level", function(text) set(b, {level = tonumber(text) or false}) end)
    b.levelBox:SetNumeric(true)
    b.levelBox:SetMaxLetters(3)
    b.levelBox:SetPoint("TOPLEFT", 194, -1)
    b.spellBox = Box(b, 130, "Spell name", function(text) set(b, {spell = text ~= "" and text or false}) end)
    b.spellBox:SetMaxLetters(100)
    b.spellBox:SetPoint("TOPLEFT", 194, -1)
    b.ask = Tick(b, "Ask first", 336, function(on)
        set(b, {ask = on})
        U.refresh()
    end)
    b.remove = Button(b, "Remove", 70)
    b.remove:SetPoint("TOPRIGHT", 0, 0)
    b.remove:SetScript("OnClick", function()
        if rule(b) then L.removeRule(b.lo, b.i) end
        U.refresh()
    end)
    b.classes = St.Dropdown(b, 150, function()
        local r, names = rule(b), {}
        for _, class in ipairs(CLASSES) do
            if r and r.classes and r.classes[class] then names[#names + 1] = className(class) end
        end
        return #names == 0 and "Any class" or table.concat(names, ", ")
    end, function(root)
        for _, class in ipairs(CLASSES) do
            root:CreateCheckbox(className(class), function()
                local r = rule(b)
                return r and r.classes and r.classes[class] == true
            end, function()
                local r = rule(b)
                if not r then return end
                local classes = {}
                for c in pairs(r.classes or {}) do classes[c] = true end
                classes[class] = not classes[class] or nil
                set(b, {classes = next(classes) and classes or false})
                b.classes:Refresh()
                U.refresh()
            end, class)
        end
    end)
    b.classes:SetPoint("TOPLEFT", 0, -32)
    b.mode = St.Dropdown(b, 110, function()
        local r = rule(b)
        return r and r.except and "All but these" or "Only these"
    end, function(root)
        for _, m in ipairs({{false, "Only these"}, {true, "All but these"}}) do
            root:CreateRadio(m[2], function() local r = rule(b); return r and (r.except == true) == m[1] end,
                function()
                    set(b, {except = m[1]})
                    U.refresh()
                end, m[1])
        end
    end)
    b.mode:SetPoint("TOPLEFT", 156, -32)
    b.namesBox = Box(b, W - 280, "Names, comma separated (empty: anyone)", function(text)
        set(b, {names = text ~= "" and text or false})
    end)
    b.namesBox:SetMaxLetters(500)
    b.namesBox:SetPoint("TOPLEFT", 278, -29)
    b.line = St.Line(b)
    b.line:SetPoint("BOTTOMLEFT", 0, 4)
    b.line:SetPoint("BOTTOMRIGHT", 0, 4)
    return b
end

local function fill(box, text)
    if not box:HasFocus() then
        box:SetText(text or "")
        box.prompt:SetShown((text or "") == "")
    end
end

local shownLo
local function showRules(tab, lo, isBackup, height)
    local on = tab == "rules" and lo ~= nil
    addButton:SetShown(on and not isBackup)
    if lo ~= shownLo then -- a box left focused writes to the loadout it was opened on, not the next
        for _, b in ipairs(blocks) do
            for _, box in ipairs({b.levelBox, b.spellBox, b.namesBox}) do box:ClearFocus() end
        end
        shownLo = lo
    end
    local rules = on and not isBackup and lo.rules or {}
    for i, r in ipairs(rules) do
        local b = blocks[i] or Block(i)
        blocks[i] = b
        b.lo, b.i = lo, i
        b.on:SetChecked(not r.off)
        b.trigger:Refresh()
        b.levelBox:SetShown(r.trigger == "level")
        b.spellBox:SetShown(r.trigger == "spell")
        fill(b.levelBox, r.level and tostring(r.level))
        fill(b.spellBox, r.spell)
        b.ask:SetChecked(r.ask == true)
        b.classes:Refresh()
        b.mode:Refresh()
        fill(b.namesBox, r.names)
        b:Show()
    end
    for i = #rules + 1, #blocks do blocks[i]:Hide() end
    if not on then return height end
    if isBackup then
        summary:SetText("Backups don't load by themselves.")
    elseif #rules == 0 then
        summary:SetText("Apply automatically: no rules yet. Click Add rule to load this loadout by itself: on a new "
            .. "character, every login, at a level or when you learn a spell.")
    else
        summary:SetText(("Apply automatically: %s. Each waits out combat and keeps a backup first; a new character "
            .. "with XP, or one Kureq Utils knew before, is asked."):format(#rules == 1 and "1 rule" or #rules .. " rules"))
    end
    return #rules * BLOCK_H
end

addButton:SetScript("OnClick", function()
    local lo, isBackup = U.chosen()
    if not lo or isBackup then return end
    local i, why = L.addRule(lo)
    if not i then U.status:SetText(why) end
    U.refresh()
end)

local decorate = U.decorate
function U.decorate(tab, lo, isBackup, height)
    return showRules(tab, lo, isBackup, decorate(tab, lo, isBackup, height))
end
