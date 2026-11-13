-- Mail rules: rules ("herbs go to the alchemist") that a button at the mailbox carries out. A rule is a recipient and
-- conditions that must all hold (item kinds, name rules, qualities), with an amount to keep back; the first rule that
-- matches a bag stack sends it. Rules and the Never send list are account-wide (KureqUtilsDB.mail); a character never
-- mails itself. The window (MailWindow.lua) edits the rules and previews what goes where.
local ADDON, ns = ...
ns.AddModule("mail", "Mail rules", "Mail herbs, ore and other items to your other characters by rules, from a "
    .. "button at the mailbox.")
local fmt, tinsert, tremove = string.format, table.insert, table.remove
local say, trim = ns.say, ns.trim
local M = {}
ns.mail = M

-- a rule: {to = "Name", on = true, kinds = {{class = 7, sub = 9}, {class = 7}}, nameRules = {{kind =, text =}},
-- qualities = {[2] = true}, keep = 0}; never: item IDs or names; neverRules: name rules
ns.defaults.mail = {rules = {}, never = {}, neverRules = {}}

local GetItemInfo = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
local C = C_Container
local QUEST, CONSUMABLE = 12, 0 -- item class IDs
local function perMail() return ATTACHMENTS_MAX_SEND or 12 end

local db
tinsert(ns.onLoad, function(root)
    db = root.mail
    db.rules, db.never, db.neverRules = {unpack(db.rules)}, {unpack(db.never)}, {unpack(db.neverRules)} -- not the defaults'
end)
function M.db() return db end

-- Matching ---------------------------------------------------------------------------------------------------------

-- a "Tooltip has" rule reads the item's bag slot's tooltip, once; unknown: what it counts as when the tooltip can't be
-- read (Never send: true, so nothing it might cover goes; a rule: false)
local function anyName(rules, item, unknown)
    local tip = function()
        if item.tipRead == nil then item.tip, item.tipRead = ns.delete.tooltipText(item.bag, item.slot), true end
        return item.tip
    end
    for _, r in ipairs(rules or {}) do
        local hit = ns.delete.ruleMatches(r, item.name, tip)
        if hit == nil then hit = unknown end
        if hit then return true end
    end
    return false
end

-- what keeps a rule from sending anything, as the window says it; nil when it can send
function M.problem(rule)
    if trim(rule.to) == "" then return "Type who gets it" end
    if #(rule.kinds or {}) == 0 and #(rule.nameRules or {}) == 0 then return "Add an item kind or a name rule" end
end

-- item: {id, name, class, sub, quality, count}. Every condition the rule has must hold; any entry inside one may.
-- Quality alone only narrows: a rule needs a kind or a name rule (never "mail everything").
function M.match(rule, item)
    if rule.on == false then return false end
    local kinds, names = rule.kinds or {}, rule.nameRules or {}
    if #kinds == 0 and #names == 0 then return false end
    if #kinds > 0 then
        local hit = false
        for _, k in ipairs(kinds) do
            if k.class == item.class and (k.sub == nil or k.sub == item.sub) then hit = true; break end
        end
        if not hit then return false end
    end
    if #names > 0 and not anyName(names, item, false) then return false end
    if next(rule.qualities or {}) and not rule.qualities[item.quality or -1] then return false end
    return true
end

-- the recipient as shown and as a key: spaces evened out ("Ku  Req" -> "Ku Req"); names are never split on spaces
local function cleanName(to) return (trim(to):gsub("%s+", " ")) end
local function realmKey(realm) return (realm or ""):gsub("[%s%-']", ""):lower() end
-- to is me ({name =, realm =}): the same whole name, and the same realm when one is typed ("Ku Req-Forever")
function M.isMe(to, me)
    if not me or ns.notes.key(to) ~= ns.notes.key(me.name or "") then return false end
    local realm = trim(to):match("%-(.+)$")
    return not realm or realmKey(realm) == realmKey(me.realm)
end
function M.me()
    return {name = ns.notes.unitName("player") or "", realm = GetRealmName and GetRealmName() or ""}
end

-- items (bag order) -> {{to =, key =, items = {item + rule}, mails = {{items}, ...}}, ...}, recipients in the order
-- first reached. Never send and the always-kept items (bound, quest, locked, unmailable) go nowhere.
function M.plan(items, rules, never, neverRules, me)
    local neverSet, left = {}, {}
    for _, e in ipairs(never) do neverSet[type(e) == "string" and e:lower() or e] = true end
    for _, it in ipairs(items) do left[it.id] = (left[it.id] or 0) + it.count end -- what stays on the sender
    local out, byKey = {}, {}
    for _, it in ipairs(items) do
        local kept = it.bound or it.quest or it.locked or it.unmailable or it.class == QUEST
            or neverSet[it.id] or neverSet[it.name:lower()] or anyName(neverRules, it, true)
        for _, rule in ipairs(kept and {} or rules) do
            if not M.problem(rule) and not M.isMe(rule.to, me) and M.match(rule, it) then
                -- first match wins, also when keeping back holds this stack
                if left[it.id] - it.count >= (tonumber(rule.keep) or 0) then
                    left[it.id] = left[it.id] - it.count
                    local to = cleanName(rule.to)
                    local key = to:lower()
                    local r = byKey[key]
                    if not r then
                        r = {to = to, key = key, items = {}, mails = {}}
                        byKey[key] = r
                        out[#out + 1] = r
                    end
                    local copy = {rule = rule}
                    for k, v in pairs(it) do copy[k] = v end
                    r.items[#r.items + 1] = copy
                end
                break
            end
        end
    end
    for _, r in ipairs(out) do
        for i, it in ipairs(r.items) do
            local n = math.floor((i - 1) / perMail()) + 1
            r.mails[n] = r.mails[n] or {}
            tinsert(r.mails[n], it)
        end
    end
    return out
end

-- Bags -------------------------------------------------------------------------------------------------------------

-- Conjured items can't be mailed; their tooltip says so. shortcut: only consumables are checked (Classic's conjured
-- food, water, gems and healthstones all are); check every class if another kind turns up.
local function conjured(bag, slot)
    local data = ITEM_CONJURED and C_TooltipInfo and C_TooltipInfo.GetBagItem and C_TooltipInfo.GetBagItem(bag, slot)
    for _, line in ipairs(data and data.lines or {}) do
        if line.leftText == ITEM_CONJURED then return true end
    end
    return false
end

-- one bag slot as an item, nil when empty or its data hasn't arrived yet
function M.readSlot(bag, slot)
    local info = C.GetContainerItemInfo(bag, slot)
    if not (info and info.itemID) then return nil end
    local name, link, quality, _, _, _, _, _, _, icon, _, class, sub = GetItemInfo(info.itemID)
    if not name then return nil end
    local q = C.GetContainerItemQuestInfo and C.GetContainerItemQuestInfo(bag, slot)
    return {bag = bag, slot = slot, id = info.itemID, name = name, class = class, sub = sub,
        quality = info.quality or quality, count = info.stackCount or 1, locked = info.isLocked, bound = info.isBound,
        quest = class == QUEST or (q and (q.isQuestItem or q.questID ~= nil)) or false,
        unmailable = class == CONSUMABLE and conjured(bag, slot), icon = info.iconFileID or icon,
        link = info.hyperlink or link}
end

function M.scanBags()
    local items = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0) do -- the reagent bag (5) too
        for slot = 1, C.GetContainerNumSlots(bag) or 0 do
            local it = M.readSlot(bag, slot)
            if it then items[#items + 1] = it end
        end
    end
    return items
end

-- what the rules would send now, from fresh bag data
function M.current()
    if not db then return {} end
    return M.plan(M.scanBags(), db.rules, db.never, db.neverRules, M.me())
end

-- Item kinds, as the game names them -------------------------------------------------------------------------------

local GetItemSubClassInfo = C_Item and C_Item.GetItemSubClassInfo or _G.GetItemSubClassInfo
local GetItemClassInfo = C_Item and C_Item.GetItemClassInfo or _G.GetItemClassInfo
function M.subclassName(class, sub)
    local name = GetItemSubClassInfo and GetItemSubClassInfo(class, sub)
    return name ~= "" and name or nil
end
function M.className(class)
    local name = GetItemClassInfo and GetItemClassInfo(class)
    return name ~= "" and name or nil
end
function M.kindName(k)
    if k.sub == nil then return fmt("%s (any)", M.className(k.class) or ("Class " .. k.class)) end
    return M.subclassName(k.class, k.sub) or fmt("Kind %d/%d", k.class, k.sub)
end

M.QUALITIES = {{0, "|cff9d9d9dPoor|r"}, {1, "|cffffffffCommon|r"}, {2, "|cff1eff00Uncommon|r"}, {3, "|cff0070ddRare|r"},
    {4, "|cffa335eeEpic|r"}}

-- The templates fill in the conditions; the player types the recipient. Trade Goods (class 7) subclasses: 5 Cloth,
-- 6 Leather, 7 Metal & Stone, 9 Herb (Classic's IDs; the Debug check "mail: trade goods subclasses" names them in
-- game). Enchanting mats go by name, as Classic files them under Trade Goods without a subclass of their own.
M.TEMPLATES = {
    {name = "Herbs", kinds = {{class = 7, sub = 9}}},
    {name = "Ore and stone", kinds = {{class = 7, sub = 7}}},
    {name = "Cloth", kinds = {{class = 7, sub = 5}}},
    {name = "Leather", kinds = {{class = 7, sub = 6}}},
    {name = "Enchanting mats", kinds = {{class = 7}},
        nameRules = {{kind = "ends", text = "Dust"}, {kind = "ends", text = "Essence"}, {kind = "ends", text = "Shard"}}},
}

local function copyList(list)
    local out = {}
    for i, e in ipairs(list or {}) do
        out[i] = {}
        for k, v in pairs(e) do out[i][k] = v end
    end
    return out
end
-- a new rule at the end of the list, from a template (an index into M.TEMPLATES) or empty
function M.newRule(template)
    local t = M.TEMPLATES[template] or {}
    local rule = {to = "", on = true, kinds = copyList(t.kinds), nameRules = copyList(t.nameRules), qualities = {}, keep = 0}
    tinsert(db.rules, rule)
    return rule
end

-- "Herb, Metal & Stone · ends with "Dust" · Uncommon · keep 20" for the rule list
local KIND_WORDS = {starts = "starts with", ends = "ends with", contains = "contains", pattern = "pattern"}
function M.summary(rule)
    local parts, kinds, names, quals = {}, {}, {}, {}
    for _, k in ipairs(rule.kinds or {}) do kinds[#kinds + 1] = M.kindName(k) end
    for _, r in ipairs(rule.nameRules or {}) do names[#names + 1] = fmt('%s "%s"', KIND_WORDS[r.kind] or r.kind, r.text) end
    for _, q in ipairs(M.QUALITIES) do if (rule.qualities or {})[q[1]] then quals[#quals + 1] = q[2] end end
    if #kinds > 0 then parts[#parts + 1] = table.concat(kinds, ", ") end
    if #names > 0 then parts[#parts + 1] = table.concat(names, " or ") end
    if #quals > 0 then parts[#parts + 1] = table.concat(quals, ", ") end
    if (tonumber(rule.keep) or 0) > 0 then parts[#parts + 1] = "keep " .. rule.keep end
    return #parts > 0 and table.concat(parts, " · ") or "No conditions yet"
end

-- "5 Cloth, 6 Leather, ..." for the subclasses the templates use (a Debug check: are they Classic's IDs here?)
local function templateSubclasses()
    local names = {}
    for _, sub in ipairs({5, 6, 7, 9, 12}) do names[#names + 1] = sub .. " " .. tostring(M.subclassName(7, sub)) end
    return table.concat(names, ", ")
end

-- Sending at the mailbox -------------------------------------------------------------------------------------------
-- One mail per step: the button's click sends the first, and each next one starts on MAIL_SEND_SUCCESS. If the game
-- blocks or ignores a send no click started, the button sends one mail per click ("Send next mail (k of n)"). Each
-- stack is read again before it is attached; one that moved or changed stays. MAIL_FAILED, the mailbox closing, no
-- answer in 10 seconds, short postage or the module turned off stops the run; what was sent stays sent.

local GetCoinTextureString = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString or _G.GetCoinTextureString
local TIMEOUT, NEXT_DELAY = 10, 0.5
M.POSTAGE = 30 -- copper per attached item, for the preview; GetSendMailPrice is checked before each send

function M.money(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return fmt("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end
local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end
M.plural = plural

local run -- {mails = {{to =, items =}}, i =, perClick =, clicked =, out = the mail sent, wait = its timer, sent, order, notes}
local mailOpen = false
local sendButton

local function debugCheck(name, value)
    if ns.debug then ns.debug.run({{name, function() return value end}}) end
end

local function attachedCount()
    local n = 0
    for i = 1, perMail() do if HasSendMailItem(i) then n = n + 1 end end
    return n
end
local function clearSendTab()
    for i = 1, perMail() do if HasSendMailItem(i) then ClickSendMailItemButton(i, true) end end
end

function M.count(plan)
    local n = 0
    for _, r in ipairs(plan) do n = n + #r.items end
    return n
end

function M.refreshButton()
    if not sendButton then return end
    local shown = mailOpen and ns.IsOn("mail")
    sendButton:SetShown(shown)
    if not shown then return end
    local text, enabled
    if run and run.perClick then
        text, enabled = fmt("Send next mail (%d of %d)", run.i, #run.mails), not run.wait
    elseif run then
        text, enabled = fmt("Sending mail %d of %d", run.i, #run.mails), false
    else
        local n = M.count(M.current())
        text, enabled = n > 0 and fmt("Send by rules (%s)", plural(n, "item", "items")) or "Nothing to send", n > 0
    end
    sendButton:SetText(text)
    sendButton:SetWidth(math.max(120, (sendButton:GetTextWidth() or 0) + 28)) -- as wide as its text, no wider
    sendButton:SetEnabled(enabled)
end
local function changed()
    M.refreshButton()
    if M.changed then M.changed() end -- the window's refresh
end
M.notify = changed -- after every change to the rules or Never send: the mailbox button and the window followM.isOpen = function() return mailOpen end

-- the chat summary: per recipient what went, then what stayed and why
local function finish(why)
    local r = run
    run = nil
    if mailOpen then clearSendTab() end -- the send tab is left empty
    for _, key in ipairs(r.order) do
        local s = r.sent[key]
        say("Sent %s to %s (%s)", plural(s.items, "item", "items"), s.to, plural(s.mails, "mail", "mails"))
    end
    for _, line in ipairs(r.notes) do say(line) end
    if why then say("Stopped sending: %s.", why)
    elseif #r.order == 0 then say("Nothing was sent.") end
    changed()
end

local send
local function advance()
    run.i = run.i + 1
    if run.i > #run.mails then return finish() end
    if run.perClick then return changed() end
    local step = run
    C_Timer.After(NEXT_DELAY, function() if run == step and not run.perClick then send(false) end end)
end

local function toPerClick(result)
    debugCheck("mail: chained send", result)
    run.perClick, run.wait = true, nil
    say("The game wants a click for each mail: click Send next mail at the mailbox.")
    changed()
end

-- fills the send tab with mail run.i and sends it; clicked: a click started this
function send(clicked)
    local mail = run.mails[run.i]
    if GetCursorInfo() then return finish("put down what's on the cursor first") end
    clearSendTab()
    -- the rules again on fresh bag data: a stack goes only if it's unchanged and still sent to this recipient now
    -- (Never send, rule edits and keep-back totals as they are now). This mail's own stacks may still read locked
    -- from a retry's attachments just taken off, so they count as free here; picking one up checks it.
    local queued, fresh = {}, {}
    for _, it in ipairs(mail.items) do queued[it.bag .. ":" .. it.slot] = true end
    local items = M.scanBags()
    for _, it in ipairs(items) do if queued[it.bag .. ":" .. it.slot] then it.locked = false end end
    for _, r in ipairs(M.plan(items, db.rules, db.never, db.neverRules, M.me())) do
        if r.key == mail.to:lower() then
            for _, it in ipairs(r.items) do fresh[it.bag .. ":" .. it.slot] = it end
        end
    end
    local attached = {}
    for _, it in ipairs(mail.items) do
        local now = fresh[it.bag .. ":" .. it.slot]
        if not (now and now.id == it.id and now.count == it.count) then
            tinsert(run.notes, fmt("%s x%d stayed: it changed in your bags or the rules no longer send it.", it.name,
                it.count))
        else
            C.PickupContainerItem(it.bag, it.slot)
            local kind, id = GetCursorInfo()
            if kind == "item" and id == it.id then ClickSendMailItemButton(#attached + 1) end
            if GetCursorInfo() or not HasSendMailItem(#attached + 1) then
                ClearCursor()
                tinsert(run.notes, fmt("%s x%d stayed: the game wouldn't attach it.", it.name, it.count))
            else
                attached[#attached + 1] = it
            end
        end
    end
    if #attached == 0 then return advance() end
    local price = GetSendMailPrice()
    if price > GetMoney() then
        return finish(fmt("not enough money for the postage to %s (%s)", mail.to, M.money(price)))
    end
    local subject = #attached > 1 and fmt("%s and %d more", attached[1].name, #attached - 1) or attached[1].name
    if SendMailNameEditBox then SendMailNameEditBox:SetText(mail.to) end
    if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText(subject) end
    local token = {}
    run.out, run.wait, run.clicked, run.error, run.confirming, mail.attached = mail, token, clicked, nil, nil, attached
    changed()
    SendMail(mail.to, subject, "")
    if run and run.wait == token then -- a block (ADDON_ACTION_BLOCKED) during the call clears it
        C_Timer.After(TIMEOUT, function()
            if not (run and run.wait == token) then return end
            if run.confirming then
                return finish(fmt("the game's confirm box wasn't answered in %d seconds", TIMEOUT))
            end
            if run.clicked then return finish(fmt("no answer from the mailbox for %d seconds", TIMEOUT)) end
            -- per-click from here; the mail stays outstanding until a late answer settles it or a click drops it
            toPerClick("no answer")
        end)
    end
end

local function start()
    if run or not (mailOpen and ns.IsOn("mail")) then return end
    if GetCursorInfo() then return say("Put down what's on the cursor first; nothing sent.") end
    local mails = {}
    for _, r in ipairs(M.current()) do
        for _, m in ipairs(r.mails) do mails[#mails + 1] = {to = r.to, items = m} end
    end
    if #mails == 0 then return changed() end
    if MailFrameTab_OnClick then MailFrameTab_OnClick(nil, 2) end -- the send tab: attaching needs it showing
    local typed = attachedCount() > 0
    for _, box in ipairs({SendMailNameEditBox, SendMailSubjectEditBox, SendMailBodyEditBox}) do
        typed = typed or (box:GetText() or "") ~= ""
        box:SetText("")
    end
    if SetSendMailMoney then SetSendMailMoney(0) end -- never money or C.O.D. left from the player's own mail
    if SetSendMailCOD then SetSendMailCOD(0) end
    run = {mails = mails, i = 1, sent = {}, order = {}, notes = {}}
    if typed then say("Cleared the send tab to send by rules.") end
    send(true)
end

local function onClick()
    if not ns.IsOn("mail") then return end
    if run and run.perClick and not run.wait then return send(true) end
    start()
end

local function makeButtons()
    if sendButton or not MailFrame then return end
    sendButton = CreateFrame("Button", "KureqUtilsMailSendButton", MailFrame, "UIPanelButtonTemplate")
    sendButton:SetHeight(22)
    -- in the row of the mail tabs, its right edge at the frame's, so it never hangs past the frame
    sendButton:SetPoint("RIGHT", MailFrame, "RIGHT", -4, 0)
    sendButton:SetPoint("TOP", MailFrameTab2 or MailFrame, "TOP", 0, -6)
    sendButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    sendButton:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            if M.showPreview then M.showPreview() end
        else
            onClick()
        end
    end)
    sendButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Mail rules", 1, 1, 1)
        GameTooltip:AddLine("Click to send what your rules match. Right-click to see what goes to whom.", nil, nil, nil,
            true)
        GameTooltip:Show()
    end)
    sendButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local events = CreateFrame("Frame")
for _, e in ipairs({"MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_FAILED", "BAG_UPDATE_DELAYED",
    "UI_ERROR_MESSAGE", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
    "SECURE_TRANSFER_CONFIRM_SEND_MAIL", "SECURE_TRANSFER_CANCEL"}) do
    events:RegisterEvent(e)
end
events:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "MAIL_SHOW" then
        mailOpen = true
        makeButtons()
        debugCheck("mail: trade goods subclasses", templateSubclasses())
        return M.refreshButton()
    elseif event == "MAIL_CLOSED" then
        mailOpen = false
        if run then finish("the mailbox closed") end
        return M.refreshButton()
    elseif event == "BAG_UPDATE_DELAYED" then
        if not run then changed() end
        return
    end
    if not (run and run.out) then return end
    if event == "MAIL_SEND_SUCCESS" then
        local mail, r = run.out, run
        if not run.clicked and not run.perClick then debugCheck("mail: chained send", "works") end
        run.out, run.wait = nil, nil
        local key = mail.to:lower()
        if not r.sent[key] then r.sent[key] = {to = mail.to, items = 0, mails = 0}; tinsert(r.order, key) end
        r.sent[key].items, r.sent[key].mails = r.sent[key].items + #mail.attached, r.sent[key].mails + 1
        advance()
    elseif event == "MAIL_FAILED" then
        finish(fmt("the mail to %s didn't go: %s", run.out.to, run.error or "the game refused it"))
    elseif event == "SECURE_TRANSFER_CONFIRM_SEND_MAIL" then
        run.confirming = true -- Blizzard asks the player (a stranger): wait for the answer, never a retry
    elseif event == "SECURE_TRANSFER_CANCEL" then
        if run.confirming then finish("you said no to the game's confirm box") end
    elseif event == "UI_ERROR_MESSAGE" then
        run.error = type(a2) == "string" and a2 or type(a1) == "string" and a1 or run.error
    elseif a1 == ADDON and type(a2) == "string" and a2:find("SendMail") and run.wait then -- blocked or forbidden
        if run.clicked then return finish("the game blocked sending") end
        run.out = nil
        toPerClick("blocked")
    end
end)

ns.OnModuleChange("mail", function(on)
    if not on and run then finish("Mail rules was turned off") end
    M.refreshButton()
end)

-- Settings page and command ----------------------------------------------------------------------------------------

ns.AddCommand("mail", "/ku mail - open or close the mail rules window", function() M.toggle() end, "mail")

local panel = ns.AddSettingsPage("Mail rules",
    "Rules that mail bag items to your other characters, such as herbs to your alchemist. At a mailbox, a button "
        .. "beside the Send Mail tab sends everything the rules match.", "mail")
ns.Button(panel, "Open mail rules", 140, function() M.toggle() end, "Rules")
ns.Header(panel, "Never send")
local NEVER_MAX = 40
ns.ItemList(panel, "Never send", "Never mailed, whatever the rules say.",
    function() return db and db.never end,
    function(id)
        for _, e in ipairs(db.never) do if e == id then return end end
        if #db.never >= NEVER_MAX then
            return say("The Never send list is full (%d items); right-click one to remove it.", NEVER_MAX)
        end
        tinsert(db.never, id)
        changed()
    end,
    function(i) tremove(db.never, i); changed() end)
ns.RuleList(panel, "Name rules", "Items whose name matches a rule are never mailed. " .. ns.delete.KIND_HELP,
    ns.delete.KINDS,
    function() return db and db.neverRules end,
    function(kind, text)
        for _, r in ipairs(db.neverRules) do if r.kind == kind and r.text == text then return end end
        tinsert(db.neverRules, {kind = kind, text = text})
        changed()
    end,
    function(i) tremove(db.neverRules, i); changed() end,
    function(r) return r.kind == "pattern" and not ns.delete.validPattern(r.text) and "(invalid pattern)" or nil end)
ns.Label(panel, "Soulbound, quest and conjured items are never mailed either.", "GameFontDisable")
