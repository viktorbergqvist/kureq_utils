-- Character notes: a 0-5 star rating and a note on any character, shown on their tooltip and added from their
-- right-click menu, /ku note or the notes window (NotesWindow.lua). Account-wide, in KureqUtilsDB.notes.people.
-- Names have a first and a last name in WoW Forever ("Ku Req"), so a note is keyed by the whole name: lowercased,
-- its spaces evened out, the realm dropped. Names are never split on spaces.
local _, ns = ...
ns.AddModule("notes", "Character notes", "A star rating and a note on anyone, shown on their tooltip.")
local tinsert = table.insert
local N = {}
ns.notes = N
ns.defaults.notes = {tooltip = true, blockChat = true, warn = true, share = false}

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- "  Ku   Req-Forever " -> "ku req"
function N.key(name)
    name = ns.trim(name):gsub("%s+", " ")
    return (name:match("^(.-)%-") or name):lower()
end

-- the display name: spaces evened out, no realm
local function clean(name)
    name = ns.trim(name):gsub("%s+", " ")
    return name:match("^(.-)%-") or name
end

-- A player unit's whole name: Forever's UnitName returns the first name and the surname apart, and Blizzard's
-- NameUtil joins them; elsewhere UnitName's second return is the realm. nil for a hidden (secret) name.
function N.unitName(unit)
    local name
    if NameUtil and NameUtil.FormatUnitNameForDisplay then
        name = NameUtil.FormatUnitNameForDisplay(unit)
    else
        name = UnitName(unit)
    end
    if not name or secret(name) or name == "" then return nil end
    return clean(name)
end

function N.people() return ns.db.notes.people end
function N.get(name) return name and ns.db.notes.people[N.key(name)] end

-- the note on name, made if there's none yet
function N.ensure(name)
    local key = N.key(name)
    local entry = ns.db.notes.people[key]
    if not entry then
        entry = {name = clean(name), note = "", updated = time()}
        ns.db.notes.people[key] = entry
    end
    return entry
end

-- a note changed: NotesSync.lua shares what changed, while sharing is on
function N.changed() if N.sync then N.sync.changed() end end
function N.touch(entry)
    entry.updated = time()
    N.changed()
end
function N.remove(name)
    ns.db.notes.people[N.key(name)] = nil
    N.changed()
end
local function empty(entry)
    return not entry.rating and (entry.note or "") == "" and not next(entry.tags or {}) and not entry.block
        and not next(entry.dungeons or {})
end
N.isEmpty = empty
-- notes with no rating, text, category, block or dungeon are dropped, except keep's (the one being written)
function N.prune(keep)
    for key, entry in pairs(ns.db.notes.people) do
        if empty(entry) and entry ~= keep then ns.db.notes.people[key] = nil end
    end
    N.changed()
end

-- Guild notes, the notes guildmates shared (NotesSync.lua): KureqUtilsDB.notes.guilds[guild key][player key]
-- [author key] = {player, author (their names), at (the author's time), rating, note, cats = {{name, {r, g, b}}, ...},
-- relay = true when passed along by someone else, deleted = true for a dated deletion}. Your own notes stay in people
-- (entry.private keeps one from being shared); what of them you shared is in notes.shared[guild key][player key], with
-- the characters of yours it went out under (authors). notes.chars: your characters (key -> name); their notes are
-- yours, never guild notes. notes.cleared[guild key]: when you cleared guild notes (older ones aren't taken again).
-- Deletions (and notes made Private) are kept for good as dated markers, so they win over old copies passed along;
-- they count toward NotesSync.lua's guild caps like notes.
-- The guild key is the guild's name and your realm; nil without a guild.
function N.guildKey()
    local name = IsInGuild and IsInGuild() and GetGuildInfo("player")
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not name or secret(name) or name == "" or not realm or realm == "" then return nil end
    return name .. "-" .. realm
end
-- your characters, key -> name, this one added
function N.myChars()
    local chars = ns.db.notes.chars
    local name = N.unitName("player")
    if name and not chars[N.key(name)] then chars[N.key(name)] = name end
    return chars
end
-- one of your guild's tables in notes (section "guilds" or "shared"), nil without a guild (made when create)
function N.perGuild(section, create)
    local gkey = ns.db and N.guildKey()
    if not gkey then return nil end
    local t = ns.db.notes[section]
    if create and not t[gkey] then t[gkey] = {} end
    return t[gkey]
end
-- your guild's notes, player key -> author key -> note; nil without a guild (made when create)
function N.guildStore(create) return N.perGuild("guilds", create) end
-- the guild's notes on name (deletions and your own characters' left out), newest first
function N.guildNotes(name)
    local store = name and ns.db and N.guildStore()
    local list = {}
    if not store then return list end
    local chars = N.myChars()
    for akey, g in pairs(store[N.key(name)] or {}) do
        if not g.deleted and not chars[akey] then list[#list + 1] = g end
    end
    table.sort(list, function(a, b)
        if a.at ~= b.at then return a.at > b.at end
        return a.author < b.author
    end)
    return list
end
-- the guild's notes on name, newest first, and their average rating (nil when none is rated)
function N.guildRating(name)
    local list = N.guildNotes(name)
    local sum, rated = 0, 0
    for _, g in ipairs(list) do
        if g.rating then sum, rated = sum + g.rating, rated + 1 end
    end
    return list, rated > 0 and sum / rated or nil
end
-- removes every guild note (yours are in people and stay); notes from before now aren't taken again
N.AHEAD = 300 -- seconds a guildmate's clock may run ahead of yours; a note stamped later than that isn't taken
function N.clearGuild()
    local notes = ns.db.notes
    local cutoff = time() + N.AHEAD -- past every note taken so far, however far ahead its author's clock ran
    for gkey in pairs(notes.guilds) do notes.cleared[gkey] = cutoff end
    local gkey = N.guildKey()
    if gkey then notes.cleared[gkey] = cutoff end
    wipe(notes.guilds)
    if N.sync then N.sync.cleared() end
end
-- Stars: the raid target star, gold for the rating, dark for the rest
N.COLORS = {[0] = {0.75, 0.1, 0.1}, {1, 0.3, 0.25}, {1, 0.55, 0.2}, {1, 0.82, 0.2}, {0.6, 0.9, 0.3}, {0.3, 0.85, 0.35}} -- 0 dark red, 1 red to 5 green
N.STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
function N.stars(rating, size) -- "" with no rating, so 0 stars (all dark) stands apart
    if not rating then return "" end
    size = size or 12
    local on = "|T" .. N.STAR .. (":%d:%d|t"):format(size, size)
    local off = "|T" .. N.STAR .. (":%d:%d:0:0:64:64:0:64:0:64:70:70:70|t"):format(size, size)
    return (on):rep(rating or 0) .. (off):rep(5 - (rating or 0))
end
N.WORDS = {[0] = "Never again", "Avoid", "Not great", "Okay", "Good", "Great"}
-- small stars and the rating's word ("<stars> Avoid"), nil with no rating
function N.ratingText(entry)
    return entry.rating and N.stars(entry.rating, 10) .. " " .. N.WORDS[entry.rating] or nil
end
function N.firstLine(entry) return (entry.note or ""):match("^[^\n]*") end
function N.colored(entry)
    local c = entry.rating and N.COLORS[entry.rating]
    if not c then return entry.name end
    return ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, entry.name)
end

-- Categories: named and colored, set on characters (entry.tags[id] = true); several per character. Kept by id
-- in KureqUtilsDB.notes.categories, so renaming or recoloring one keeps who's in it.
local STARTER = {{"Ninja looter", {1, 0.25, 0.2}}, {"Toxic", {0.75, 0.4, 1}}, {"Steals tags", {1, 0.6, 0.15}}}
local function hex(c) return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end
function N.categoryList() -- {id, name, color}, A-Z
    local list = {}
    for id, c in pairs(ns.db.notes.categories) do list[#list + 1] = {id = id, name = c.name, color = c.color} end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return list
end
function N.categoryText(id)
    local c = ns.db.notes.categories[id]
    return c and hex(c.color) .. c.name .. "|r"
end
function N.addCategory(name, color)
    local notes = ns.db.notes
    local id = notes.nextCategory
    notes.nextCategory = id + 1
    notes.categories[id] = {name = name, color = color}
    return id
end
function N.deleteCategory(id)
    ns.db.notes.categories[id] = nil
    for _, entry in pairs(ns.db.notes.people) do
        if entry.tags then entry.tags[id] = nil end
    end
    N.changed()
end
function N.inCategory(id) -- how many characters are in it
    local n = 0
    for _, entry in pairs(ns.db.notes.people) do
        if entry.tags and entry.tags[id] then n = n + 1 end
    end
    return n
end
-- an entry's categories, colored, A-Z, joined by commas; "" when it has none
function N.tagsText(entry)
    local parts = {}
    for _, c in ipairs(N.categoryList()) do
        if entry.tags and entry.tags[c.id] then parts[#parts + 1] = hex(c.color) .. c.name .. "|r" end
    end
    return table.concat(parts, ", ")
end

-- a guild note's categories in its author's names and colors, joined by commas; "" when it has none
function N.guildTagsText(g)
    local parts = {}
    for _, c in ipairs(g.cats or {}) do parts[#parts + 1] = hex(c[2]) .. c[1] .. "|r" end
    return table.concat(parts, ", ")
end
function N.round(v) return v and math.floor(v + 0.5) end
-- "Guild: 2 notes, 3.5 stars" (no stars part when none is rated)
function N.guildText(count, avg)
    local text = ("Guild: %d %s"):format(count, count == 1 and "note" or "notes")
    return avg and text .. (", %.1f stars"):format(avg) or text
end
-- a guild note's first line with its author ("Half Dan: Ninja looted"), its rating's word when it has no text
function N.guildLine(g)
    local line = N.firstLine(g)
    if line == "" then line = g.rating and N.WORDS[g.rating] or N.guildTagsText(g) end
    return g.author .. ": " .. line
end

-- Tooltips: a player's stars, categories and note, then the guild's notes on them
local function onTooltipUnit(tip)
    if not (ns.db and ns.db.notes.tooltip and ns.IsOn("notes")) then return end
    local _, unit = tip:GetUnit()
    if not unit or secret(unit) or not UnitIsPlayer(unit) then return end
    local name = N.unitName(unit)
    local entry = N.get(name)
    local guild, avg = N.guildRating(name)
    if not entry and #guild == 0 then return end
    if not entry then
        tip:AddLine(N.guildText(#guild, avg), 1, 0.82, 0)
        tip:AddLine(N.guildLine(guild[1]), 0.8, 0.8, 0.8, true)
        return tip:Show()
    end
    if entry.rating then
        tip:AddDoubleLine("Note", N.stars(entry.rating, 14), 1, 0.82, 0)
    else
        tip:AddLine("Note", 1, 0.82, 0)
    end
    local tags = N.tagsText(entry)
    if tags ~= "" then tip:AddLine(tags, 1, 1, 1, true) end
    if (entry.note or "") ~= "" then tip:AddLine(entry.note, 1, 1, 1, true) end
    local blocks = {}
    for _, b in ipairs(N.BLOCKS) do
        if N.blocked(entry.name, b[1]) then blocks[#blocks + 1] = b[2]:lower() end
    end
    if #blocks > 0 then tip:AddLine("Blocks: " .. table.concat(blocks, ", "), 0.6, 0.6, 0.6) end
    if #guild > 0 then
        tip:AddLine(N.guildText(#guild, avg), 1, 0.82, 0)
        tip:AddLine(N.guildLine(guild[1]), 0.8, 0.8, 0.8, true)
    end
    tip:Show() -- resize to the added lines
end
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tip)
        if tip == GameTooltip then onTooltipUnit(tip) end
    end)
else
    GameTooltip:HookScript("OnTooltipSetUnit", onTooltipUnit)
end

-- The Looking For Group window (Blizzard_GroupFinder_VanillaStyle, loaded on demand; Forever has no applicant list):
-- a rated leader's stars before their name in the list, and on a group's tooltip each noted member's stars and rating
-- word after their row, the note's first line under it. Blizzard's functions are hooked, never replaced (taint).
local function lfgEntry(name)
    local entry = name and not secret(name) and name ~= "" and N.get(name)
    if entry and (entry.rating or N.firstLine(entry) ~= "") then return entry end
end
local function lfgGuild(name) -- the guild's notes on name and their average, when there are any
    if not name or secret(name) or name == "" then return nil end
    local list, avg = N.guildRating(name)
    if #list > 0 then return list, avg end
end
-- the list's name with your stars in front, else the guild's average marked as the guild's; nil when there's nothing
function N.lfgName(name)
    local entry = lfgEntry(name)
    if entry and entry.rating then return N.stars(entry.rating, 12) .. " " .. name end
    local _, avg = lfgGuild(name)
    if avg then return N.stars(N.round(avg), 12) .. " " .. name .. " |cff999999(guild)|r" end
end
-- a tooltip row's rating text ("" with none) and the note's first line: yours, else the guild's; nil without either
function N.lfgLines(name)
    local entry = lfgEntry(name)
    if entry then return N.ratingText(entry) or "", N.firstLine(entry) end
    local list, avg = lfgGuild(name)
    if list then
        return (avg and N.stars(N.round(avg), 10) .. " " or "") .. N.guildText(#list, avg), N.guildLine(list[1])
    end
end
local ROW = 14 -- a tooltip member row's height (LFGBrowseSearchEntryTooltipGroupMember)
local function onLFGRow(row)
    if not (ns.db and ns.IsOn("notes") and row:IsShown()) then return end
    local text = N.lfgName(row.Name:GetText())
    if not text then return end
    row.Name:SetWidth(0)
    row.Name:SetText(text)
    local max = row.NameMaxWidth or 0 -- Blizzard's cap, less the icons shown after the name
    if row.DiscordIcon and row.DiscordIcon:IsShown() then max = max - row.DiscordIcon:GetWidth() - 4 end
    if row.NewPlayerFriendlyIcon and row.NewPlayerFriendlyIcon:IsShown() then
        max = max - row.NewPlayerFriendlyIcon:GetWidth() - 1
    end
    if max > 0 and row.Name:GetWidth() > max then row.Name:SetWidth(max) end
end
local function onLFGTooltip(tip)
    local rows = {tip.Leader}
    for f in tip.memberPool:EnumerateActive() do rows[#rows + 1] = f end
    local added, width = 0, 0 -- Blizzard summed the row heights we set last time: take that back first
    for _, f in ipairs(rows) do
        added = added - (f:GetHeight() - ROW)
        f:SetHeight(ROW)
        if f.kuRating then f.kuRating:Hide(); f.kuLine:Hide() end
    end
    if ns.db and ns.IsOn("notes") then
        local indent = tip.LeaderIcon:IsShown() and tip.LeaderIcon:GetWidth() or 0
        for _, f in ipairs(rows) do
            local rating, line
            if f:IsShown() then rating, line = N.lfgLines(f.Name:GetText()) end
            if rating then
                if not f.kuRating then
                    f.kuRating = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                    f.kuLine = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
                    f.kuLine:SetPoint("TOPLEFT", f.Name, "BOTTOMLEFT", 0, 0)
                    f.kuLine:SetJustifyH("LEFT")
                    f.kuLine:SetWordWrap(false)
                end
                local roles = 0
                for _, icon in ipairs(f.Roles or {}) do if icon:IsShown() then roles = roles + icon:GetWidth() + 4 end end
                f.kuRating:ClearAllPoints()
                f.kuRating:SetPoint("LEFT", f.Level, "RIGHT", roles + 8, 0)
                f.kuRating:SetText(rating)
                f.kuRating:Show()
                local right = f.Name:GetWidth() + 4 + f.Level:GetWidth() + roles + 8 + f.kuRating:GetStringWidth()
                if line ~= "" then
                    f.kuLine:SetWidth(0)
                    f.kuLine:SetText(line)
                    if f.kuLine:GetStringWidth() > 260 then f.kuLine:SetWidth(260) end
                    f.kuLine:Show()
                    f:SetHeight(ROW * 2)
                    added = added + ROW
                    right = math.max(right, math.min(f.kuLine:GetStringWidth(), 260))
                end
                width = math.max(width, indent + right + 22)
            end
        end
    end
    if added ~= 0 then tip:SetHeight(tip:GetHeight() + added) end
    if width > tip:GetWidth() then tip:SetWidth(width) end
end
local function hookLFG()
    if LFGBrowseSearchEntry_Update then hooksecurefunc("LFGBrowseSearchEntry_Update", onLFGRow) end
    if LFGBrowseSearchEntryTooltip_UpdateAndShow then
        hooksecurefunc("LFGBrowseSearchEntryTooltip_UpdateAndShow", onLFGTooltip)
    end
end
if EventUtil and EventUtil.ContinueOnAddOnLoaded then
    EventUtil.ContinueOnAddOnLoaded("Blizzard_GroupFinder_VanillaStyle", hookLFG)
end

-- The name a unit menu is for: its unit's, when that's another player, or the name it was opened with (chat
-- names, the friends and guild lists).
function N.contextName(context)
    if not context then return nil end
    local unit = context.unit
    if unit then
        if secret(unit) or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return nil end
        return N.unitName(unit)
    end
    local name = context.name
    if not name or secret(name) or name == "" then return nil end
    if name == UnitName("player") then return nil end
    return clean(name)
end

-- "Add note" / "Edit note" in the right-click menu of every kind of player Blizzard has one for: unit frames, chat
-- names (FRIEND), channel rosters, friends, guild and community lists, scoreboards. contextName leaves out NPCs.
if Menu and Menu.ModifyMenu then
    for _, which in ipairs({"PLAYER", "PARTY", "RAID_PLAYER", "RAID", "TARGET", "FOCUS", "FRIEND", "FRIEND_OFFLINE",
        "CHAT_ROSTER", "GUILD", "GUILD_OFFLINE", "ENEMY_PLAYER", "COMMUNITIES_GUILD_MEMBER", "COMMUNITIES_WOW_MEMBER",
        "COMMUNITIES_MEMBER", "RECENT_ALLY", "RECENT_ALLY_OFFLINE", "PVP_SCOREBOARD", "WORLD_STATE_SCORE", "ARENAENEMY",
        "TEAM"}) do
        Menu.ModifyMenu("MENU_UNIT_" .. which, function(_, root, context)
            local name = ns.db and ns.IsOn("notes") and N.contextName(context)
            if not name then return end
            root:CreateDivider()
            root:CreateTitle("Kureq Utils")
            root:CreateButton(N.get(name) and "Edit note" or "Add note", function() N.open(name) end)
            local block = root:CreateButton("Block")
            for _, b in ipairs(N.BLOCKS) do
                block:CreateCheckbox(b[2], function() return N.blocked(name, b[1]) end,
                    function() N.setBlocked(name, b[1]) end)
            end
        end)
    end
end

-- Blocking, per kind (entry.block = {group = true, ...}, only the kinds on): a blocked person's group invites, guild
-- invites, trade requests and duels are declined and the trades they open closed, with a line in chat. Blizzard's
-- UIParent registers these events before any addon, so its popup is up and gets hidden.
N.BLOCKS = {{"group", "Group invites"}, {"guild", "Guild invites"}, {"trade", "Trades"}, {"duel", "Duels"}}
function N.blocked(name, kind)
    if not name or secret(name) then return false end
    local entry = N.get(name)
    return entry ~= nil and type(entry.block) == "table" and entry.block[kind] == true
end
-- turns name's block of kind on or off (on = nil flips it); the note is made if there's none yet
function N.setBlocked(name, kind, on)
    local entry = N.ensure(name)
    local block = type(entry.block) == "table" and entry.block or {}
    if on == nil then on = not block[kind] end
    block[kind] = on or nil
    entry.block = next(block) and block or nil
    N.touch(entry)
    if N.frame and N.frame:IsShown() then N.open() end -- redraw the window
end

-- The player's own trade attempt ({name, at}): a trade window with that person within a few seconds is theirs, not
-- one to close. announced: a trade request already declined, so its window isn't announced again.
local tradingWith, announced
local function opening(unit)
    local name = ns.db and ns.IsOn("notes") and unit and not secret(unit) and N.unitName(unit)
    tradingWith = name and {name = name, at = GetTime()} or nil
end
hooksecurefunc("InitiateTrade", opening)
if C_Item and C_Item.DropItemOnUnit then hooksecurefunc(C_Item, "DropItemOnUnit", opening) end -- an item dropped on them

local REQUESTS = { -- event -> what's declined, how, and Blizzard's popup for it
    PARTY_INVITE_REQUEST = {"group invite", "DeclineGroup", "PARTY_INVITE", "group"},
    GUILD_INVITE_REQUEST = {"guild invite", "DeclineGuild", "GUILD_INVITE", "guild"},
    DUEL_REQUESTED = {"duel", "CancelDuel", "DUEL_REQUESTED", "duel"},
    TRADE_REQUEST = {"trade", "CancelTrade", "TRADE", "trade"}, -- Classic's "wants to trade" popup
}
local blocker = CreateFrame("Frame")
for event in pairs(REQUESTS) do pcall(blocker.RegisterEvent, blocker, event) end
blocker:RegisterEvent("TRADE_SHOW")
blocker:RegisterEvent("TRADE_CLOSED")
blocker:RegisterEvent("TRADE_REQUEST_CANCEL")
blocker:RegisterEvent("UI_ERROR_MESSAGE")
blocker:RegisterEvent("UI_INFO_MESSAGE")
ns.OnModuleChange("notes", function() tradingWith, announced = nil, nil end)
blocker:SetScript("OnEvent", function(_, event, name)
    -- any error or info message during the attempt counts as its failure: errs toward closing a blocked person's trade
    if event == "UI_ERROR_MESSAGE" or event == "UI_INFO_MESSAGE" then
        tradingWith = nil
        return
    end
    if event == "TRADE_CLOSED" or event == "TRADE_REQUEST_CANCEL" then tradingWith, announced = nil, nil end
    if event == "TRADE_CLOSED" or event == "TRADE_REQUEST_CANCEL" or not (ns.db and ns.IsOn("notes")) then return end
    local kind
    if event == "TRADE_SHOW" then
        name = N.unitName("NPC") -- the trader
        local own = name and tradingWith and N.key(name) == N.key(tradingWith.name) and GetTime() - tradingWith.at < 3
        tradingWith = nil
        if own or not N.blocked(name, "trade") then return end
        CloseTrade()
        if announced == N.key(name) then return end
        kind = "trade"
    else
        local r = REQUESTS[event]
        if not N.blocked(name, r[4]) then return end
        _G[r[2]]()
        StaticPopup_Hide(r[3])
        if event == "GUILD_INVITE_REQUEST" and GuildInviteFrame and StaticPopupSpecial_Hide then
            StaticPopupSpecial_Hide(GuildInviteFrame) -- the guild invite's own frame, where the client uses it
        end
        kind = r[1]
        if event == "TRADE_REQUEST" then announced = N.key(name) end
    end
    if ns.db.notes.blockChat then ns.say("Declined %s's %s (blocked in your notes).", N.get(name).name, kind) end
end)

-- Dungeons played together: entry.dungeons[name] = {runs = n, last = time()}, nil when there are none. Entering a
-- 5-player dungeon in a group gives everyone in it the run, and so does joining while you're inside. One run per visit,
-- and a player seen in that dungeon less than an hour ago gets no new run (corpse runs, zoning out and back).
-- The Classic dungeons by instance ID (GetInstanceInfo's 8th return), so automatic and hand-added names match.
N.DUNGEONS = {{389, "Ragefire Chasm"}, {43, "Wailing Caverns"}, {36, "The Deadmines"}, {33, "Shadowfang Keep"},
    {48, "Blackfathom Deeps"}, {34, "The Stockade"}, {90, "Gnomeregan"}, {47, "Razorfen Kraul"},
    {189, "Scarlet Monastery"}, {129, "Razorfen Downs"}, {70, "Uldaman"}, {209, "Zul'Farrak"}, {349, "Maraudon"},
    {109, "The Temple of Atal'Hakkar"}, {230, "Blackrock Depths"}, {229, "Blackrock Spire"}, {429, "Dire Maul"},
    {329, "Stratholme"}, {289, "Scholomance"}}
local DUNGEON_NAMES = {}
for _, d in ipairs(N.DUNGEONS) do DUNGEON_NAMES[d[1]] = d[2] end
local VISIT_GAP = 3600 -- out of a dungeon for longer than this, the next visit is a new run

-- one more run of dungeon on entry, last now
function N.addDungeon(entry, dungeon)
    entry.dungeons = entry.dungeons or {}
    local d = entry.dungeons[dungeon] or {runs = 0}
    d.runs, d.last = d.runs + 1, time()
    entry.dungeons[dungeon] = d
end
function N.removeDungeon(entry, dungeon)
    if not entry.dungeons then return end
    entry.dungeons[dungeon] = nil
    if not next(entry.dungeons) then entry.dungeons = nil end
end
-- entry's dungeons, {name, runs, last}, newest first
function N.dungeonList(entry)
    local list = {}
    for name, d in pairs(entry.dungeons or {}) do list[#list + 1] = {name = name, runs = d.runs, last = d.last} end
    table.sort(list, function(a, b)
        if a.last ~= b.last then return a.last > b.last end
        return a.name < b.name
    end)
    return list
end

-- the 5-player dungeon you're in, or nil
local function currentDungeon()
    local name, kind, _, _, _, _, _, id = GetInstanceInfo()
    if kind ~= "party" then return nil end
    return DUNGEON_NAMES[id] or (name and not secret(name) and name ~= "" and name) or nil
end

-- The visit (KureqUtilsCharDB.notesVisit, so a /reload keeps it): {dungeon, at = when you were last seen inside it,
-- counted = {[key] = true} who has its run, with = {[key] = true} who is in the group now}. A player's last is stamped
-- when they leave the group or the visit ends, whichever comes first. The visit ends when a check finds you outside its
-- dungeon, or at the first check after login when it was last seen over an hour ago. It's kept up while notes is off
-- (only where you are, nothing recorded), so turning notes off and on inside is still the same visit.
local function stamp(key, dungeon, t)
    local e = N.people()[key]
    local d = e and e.dungeons and e.dungeons[dungeon]
    if d then d.last = t or time() end
end
-- the group's other players, key -> name (hidden names left out)
local function members()
    local found, raid = {}, IsInRaid()
    if not IsInGroup() then return found end
    for i = 1, raid and 40 or 4 do
        local unit = (raid and "raid" or "party") .. i
        local name = UnitExists(unit) and not UnitIsUnit(unit, "player") and N.unitName(unit)
        if name then found[N.key(name)] = name end
    end
    return found
end
local firstCheck = true -- between logout and this file's first check nothing watched where you were
local function checkDungeon()
    if not (ns.db and ns.charDB) then return end
    local dungeon = currentDungeon()
    local visit = ns.charDB.notesVisit
    if visit and (visit.dungeon ~= dungeon or (firstCheck and time() - (visit.at or 0) > VISIT_GAP)) then
        for key in pairs(visit.with) do stamp(key, visit.dungeon, visit.at) end
        visit = nil
    end
    firstCheck = false
    if visit then visit.at = time() end
    ns.charDB.notesVisit = visit
    if not ns.IsOn("notes") then return end
    local changed = false
    if dungeon then
        visit = visit or {dungeon = dungeon, at = time(), counted = {}, with = {}}
        local now = members()
        for key in pairs(visit.with) do
            if not now[key] then
                stamp(key, dungeon)
                visit.with[key] = nil
            end
        end
        for key, name in pairs(now) do
            if not visit.counted[key] then
                visit.counted[key] = true
                local entry = N.ensure(name)
                local d = entry.dungeons and entry.dungeons[dungeon]
                if d and time() - (d.last or 0) <= VISIT_GAP then d.last = time() else N.addDungeon(entry, dungeon) end
                changed = true
            end
            visit.with[key] = true
        end
    end
    ns.charDB.notesVisit = visit
    if changed and N.frame and N.frame:IsShown() then N.open() end -- redraw the window
end
local dungeonWatch = CreateFrame("Frame")
for _, event in ipairs({"PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "PLAYER_LEAVING_WORLD"}) do
    dungeonWatch:RegisterEvent(event)
end
dungeonWatch:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_LEAVING_WORLD" then return checkDungeon() end
    -- a loading screen, logout or /reload: you were inside until now
    local visit = ns.charDB and ns.charDB.notesVisit
    if visit and currentDungeon() == visit.dungeon then visit.at = time() end
end)
ns.OnModuleChange("notes", function(on) if on then checkDungeon() end end)

-- Group warning: a chat line and the raid-warning sound when a player rated 2 stars or less, or blocked in any way,
-- joins your group (once per player until you leave the group) or whispers you (once per player per 10 minutes).
function N.lowRated(entry)
    return type(entry) == "table" and ((entry.rating ~= nil and entry.rating <= 2) or (type(entry.block) == "table" and next(entry.block) ~= nil))
end
-- "<name> joined your group: <stars> <categories> — <first line>"
function N.warnText(entry, what)
    local parts = {}
    if entry.rating then parts[#parts + 1] = N.stars(entry.rating) end
    local tags = N.tagsText(entry)
    if tags ~= "" then parts[#parts + 1] = tags end
    if #parts == 0 then parts[1] = "blocked" end
    local line = N.firstLine(entry)
    return ("%s %s: %s%s"):format(N.colored(entry), what, table.concat(parts, " "), line ~= "" and " — " .. line or "")
end
-- the guild's rating as a warning, when you have no rating (nor block) of your own on name and the guild's average is
-- 2 or less: "<name> joined your group: guild rating <stars> 1.5 from 3 notes — Half Dan: Ninja looted"; else nil
function N.guildWarnText(name, what)
    local entry = N.get(name)
    if entry and (entry.rating or N.lowRated(entry)) then return nil end
    local list, avg = N.guildRating(name)
    if not avg or avg > 2 then return nil end
    local c = N.COLORS[N.round(avg)]
    return ("|cff%02x%02x%02x%s|r %s: guild rating %s %.1f from %d %s — %s"):format(c[1] * 255, c[2] * 255, c[3] * 255,
        list[1].player, what, N.stars(N.round(avg)), avg, #list, #list == 1 and "note" or "notes", N.guildLine(list[1]))
end
local function warn(entry, what)
    if type(entry) == "string" then -- the guild's warning text
        ns.say("%s", entry)
        if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
        return
    end
    ns.say("%s", N.warnText(entry, what))
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
end
local warned, whispered = {}, {} -- key -> true this group; key -> GetTime() of the last whisper warning
local warner = CreateFrame("Frame")
warner:RegisterEvent("GROUP_ROSTER_UPDATE")
warner:RegisterEvent("CHAT_MSG_WHISPER")
warner:SetScript("OnEvent", function(_, event, _, sender)
    if event == "GROUP_ROSTER_UPDATE" and not IsInGroup() then wipe(warned) end
    if not (ns.db and ns.db.notes.warn and ns.IsOn("notes")) then return end
    if event == "CHAT_MSG_WHISPER" then
        if not sender or secret(sender) then return end
        local entry = N.get(sender)
        local text = not N.lowRated(entry) and N.guildWarnText(sender, "whispered you")
        if not (text or N.lowRated(entry)) then return end
        local key = N.key(sender)
        if whispered[key] and GetTime() - whispered[key] < 600 then return end
        whispered[key] = GetTime()
        return warn(text or entry, "whispered you")
    end
    for key, name in pairs(members()) do
        local entry = N.get(name)
        local text = not warned[key] and not N.lowRated(entry) and N.guildWarnText(name, "joined your group")
        if not warned[key] and (text or N.lowRated(entry)) then
            warned[key] = true
            warn(text or entry, "joined your group")
        end
    end
end)
-- turned on: catch up on who's in the group now (warned keeps anyone already warned from a second line)
ns.OnModuleChange("notes", function(on) if on then warner:GetScript("OnEvent")(warner, "GROUP_ROSTER_UPDATE") end end)

-- /ku note [name]: your target's note (or name's), in the notes window
ns.AddCommand("note", "/ku note [name] - your target's note, or that character's, in the notes window", function(rest)
    local name = ns.trim(rest)
    if name == "" then name = UnitIsPlayer("target") and not UnitIsUnit("target", "player") and N.unitName("target") end
    N.open(name or nil)
end, "notes")
ns.AddCommand("notes", "/ku notes - opens or closes the notes window", function() N.toggle() end, "notes")

tinsert(ns.onLoad, function(root)
    root.notes.people = type(root.notes.people) == "table" and root.notes.people or {}
    for _, entry in pairs(root.notes.people) do -- one switch for everything, before blocking went per kind
        if entry.block == true then entry.block = {group = true, guild = true, trade = true, duel = true} end
    end
    -- guild notes (2026-11): none yet for anyone upgrading; anything malformed starts empty
    root.notes.mine, root.notes.barriers = nil, nil -- pre-release shapes
    for _, section in ipairs({"guilds", "shared", "cleared", "chars"}) do
        if type(root.notes[section]) ~= "table" then root.notes[section] = {} end
    end
    for _, section in ipairs({"guilds", "shared"}) do
        for gkey, t in pairs(root.notes[section]) do
            if type(t) ~= "table" then root.notes[section][gkey] = nil end
        end
    end
    if type(root.notes.categories) ~= "table" then -- the first time: a few to start with
        root.notes.categories, root.notes.nextCategory = {}, 1
        for _, c in ipairs(STARTER) do N.addCategory(c[1], c[2]) end
    end
end)

local panel, category = ns.AddSettingsPage("Character notes",
    "A rating (0 to 5 stars) and a note on any character: right-click a player and choose Add note, or /ku note.", "notes")
N.category = category
ns.Checkbox(panel, "Show notes on tooltips", "A noted player's stars and note on their tooltip.",
    function() return ns.db.notes.tooltip end, function(v) ns.db.notes.tooltip = v end)
ns.Checkbox(panel, "Chat line for blocked requests", "A chat line each time a blocked person's group invite, guild invite, trade or duel is declined.",
    function() return ns.db.notes.blockChat end, function(v) ns.db.notes.blockChat = v end)
ns.Checkbox(panel, "Warn about low-rated players", "A chat line and the raid warning sound when a player you rated 2 stars or less, or blocked, joins your group or whispers you; for a player you haven't rated, when the guild's notes average 2 stars or less.",
    function() return ns.db.notes.warn end, function(v) ns.db.notes.warn = v end)
ns.Checkbox(panel, "Share guild notes", "Shares your notes with everyone in your guild who has Kureq Utils, and shows theirs. Tick Private on a note to keep it to yourself.",
    function() return ns.db.notes.share end, function(v)
        ns.db.notes.share = v
        if N.sync then N.sync.start() end
    end)
StaticPopupDialogs.KUREQUTILS_CLEAR_GUILD_NOTES = {
    text = "Remove every guild note you didn't write? Your own notes stay.", button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function()
        if not (ns.db and ns.IsOn("notes")) then return end
        N.clearGuild()
        if N.frame and N.frame:IsShown() then N.open() end -- redraw the window
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
ns.Button(panel, "Clear guild notes", 160, function() StaticPopup_Show("KUREQUTILS_CLEAR_GUILD_NOTES") end, "Guild notes")
ns.OnModuleChange("notes", function(on) if not on then StaticPopup_Hide("KUREQUTILS_CLEAR_GUILD_NOTES") end end)
ns.Button(panel, "Open notes", 160, function() N.open() end, "Notes window")
