-- Death recaps (Stats.lua keeps each death's last hits, d.hits, from the game's death recap): a panel with the damage
-- of those hits, split by school (one bar and its totals), how long they took, and each attacker with a bar and the
-- icon and damage of each spell; on the Deaths page it also lists the hits. A small window shows it when you die
-- (the "Show a recap when you die" setting). The game keeps only the last 5 hits, so it's the last seconds.
local _, ns = ...
local S, St = ns.stats, ns.style
local Pane, Text, Line = St.Pane, St.Text, St.Line

-- Blizzard's spell schools (a bit each; a mix shows as its first), in the colors of the screenshot's kind
local SCHOOLS = {
    {1, "Physical", {0.85, 0.35, 0.2}}, {2, "Holy", {1, 0.9, 0.5}}, {4, "Fire", {1, 0.5, 0}},
    {8, "Nature", {0.3, 0.85, 0.3}}, {16, "Frost", {0.4, 0.75, 1}}, {32, "Shadow", {0.6, 0.4, 1}},
    {64, "Arcane", {1, 0.5, 1}},
}
local WORLD = {0, "World", {0.7, 0.7, 0.7}} -- falling, drowning, lava
local MELEE_ICON, UNKNOWN_ICON = "Interface\\Icons\\INV_Sword_04", 134400
local function schoolOf(hit)
    if hit.kind == "world" then return WORLD end
    local mask = hit.school or 1
    for _, sch in ipairs(SCHOOLS) do
        if bit and bit.band and bit.band(mask, sch[1]) ~= 0 or mask == sch[1] then return sch end
    end
    return SCHOOLS[1]
end
local function hex(c) return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end
-- what a hit took off you: its damage less overkill, absorbed, resisted and blocked, as Blizzard's recap shows it
local function taken(hit)
    local n = hit.amount or 0
    for _, k in ipairs({"overkill", "absorbed", "resisted", "blocked"}) do
        if (hit[k] or 0) > 0 then n = n - hit[k] end
    end
    return math.max(0, n)
end
local function spellIcon(hit)
    if not hit.spell then return hit.kind == "world" and UNKNOWN_ICON or MELEE_ICON end
    local icon = hit.spellId and (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(hit.spellId)
        or GetSpellTexture and GetSpellTexture(hit.spellId))
    return icon or UNKNOWN_ICON
end
S.recapTaken, S.recapSchool = taken, schoolOf

-- The panel, w wide; withHits adds the list of hits under it
function S.RecapPanel(parent, w, withHits)
    local p = {}
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, withHits and 360 or 250)
    p.frame = f
    p.total = Text(f, "GameFontHighlightLarge")
    p.total:SetPoint("TOPLEFT", 0, 0)
    p.totalNote = Text(f, "GameFontDisableSmall")
    p.totalNote:SetPoint("LEFT", p.total, "RIGHT", 8, 0)
    p.span = Text(f, "GameFontHighlight")
    p.span:SetPoint("TOPRIGHT", 0, -2)
    p.span:SetJustifyH("RIGHT")
    p.empty = Text(f, "GameFontDisable")
    p.empty:SetPoint("TOPLEFT", 0, -30)
    p.empty:SetWidth(w)
    p.empty:SetWordWrap(true)
    -- the school split: one bar, its parts in the schools' colors, and the shares under it
    p.track = f:CreateTexture(nil, "ARTWORK")
    p.track:SetPoint("TOPLEFT", 0, -28)
    p.track:SetSize(w, 14)
    p.track:SetColorTexture(1, 1, 1, 0.05)
    p.parts = {}
    for i = 1, #SCHOOLS + 1 do p.parts[i] = f:CreateTexture(nil, "ARTWORK", nil, 1) end
    p.shares = Text(f, "GameFontHighlightSmall")
    p.shares:SetPoint("TOPLEFT", p.track, "BOTTOMLEFT", 0, -4)
    p.shares:SetWidth(w)
    -- per school: a square, its name and its damage
    p.schools = {}
    for i = 1, 4 do
        local c = {}
        c.square = f:CreateTexture(nil, "ARTWORK")
        c.square:SetPoint("TOPLEFT", (i - 1) * (w / 4), -66)
        c.square:SetSize(10, 10)
        c.name = Text(f, "GameFontNormalSmall")
        c.name:SetPoint("LEFT", c.square, "RIGHT", 6, 0)
        c.value = Text(f, "GameFontHighlight")
        c.value:SetPoint("TOPLEFT", c.square, "BOTTOMLEFT", 0, -3)
        p.schools[i] = c
    end
    local line = Line(f)
    line:SetPoint("TOPLEFT", 0, -98)
    line:SetWidth(w)
    p.line = line
    -- per attacker: name and total, a bar, and the icon and damage of each of their spells
    p.attackers = {}
    for i = 1, 3 do
        local y = -106 - (i - 1) * 50
        local a = {}
        a.name = Text(f, "GameFontHighlight")
        a.name:SetPoint("TOPLEFT", 0, y)
        a.name:SetWidth(150)
        a.total = Text(f, "GameFontHighlight")
        a.total:SetPoint("TOPRIGHT", 0, y)
        a.total:SetJustifyH("RIGHT")
        a.track = f:CreateTexture(nil, "ARTWORK")
        a.track:SetPoint("TOPLEFT", 160, y - 2)
        a.track:SetSize(w - 160 - 50, 10)
        a.track:SetColorTexture(1, 1, 1, 0.05)
        a.parts = {}
        for k = 1, #SCHOOLS + 1 do a.parts[k] = f:CreateTexture(nil, "ARTWORK", nil, 1) end
        a.icons = {}
        for k = 1, 6 do
            local b = CreateFrame("Button", nil, f)
            b:SetSize(20, 20)
            b:SetPoint("TOPLEFT", 160 + (k - 1) * 46, y - 16)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetAllPoints()
            b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            b.value = Text(f, "GameFontHighlightSmall")
            b.value:SetPoint("LEFT", b, "RIGHT", 4, 0)
            b:SetScript("OnEnter", function(self) if self.tip then St.Tooltip(self, self.tip[1], self.tip[2]) end end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            a.icons[k] = b
        end
        p.attackers[i] = a
    end
    -- the hits, newest last
    p.hits = {}
    if withHits then
        p.hitsTitle = Text(f, "GameFontNormal")
        p.hitsTitle:SetPoint("TOPLEFT", 0, -258)
        p.hitsTitle:SetText("Hits")
        for i = 1, 5 do
            local r = {}
            local y = -276 - (i - 1) * 16
            r.time = Text(f, "GameFontDisableSmall")
            r.time:SetPoint("TOPLEFT", 0, y)
            r.time:SetWidth(44)
            r.what = Text(f, "GameFontHighlightSmall")
            r.what:SetPoint("TOPLEFT", 48, y)
            r.what:SetWidth(w - 48 - 150)
            r.amount = Text(f, "GameFontHighlightSmall")
            r.amount:SetPoint("TOPRIGHT", -70, y)
            r.amount:SetJustifyH("RIGHT")
            r.hp = Text(f, "GameFontDisableSmall")
            r.hp:SetPoint("TOPRIGHT", 0, y)
            r.hp:SetJustifyH("RIGHT")
            p.hits[i] = r
        end
    end

    -- stacked parts in a track, each the share of its school
    local function stack(parts, track, width, bySchool, total)
        local x = 0
        for i, part in ipairs(parts) do
            local s = bySchool[i]
            part:SetShown(s ~= nil and total > 0)
            if s and total > 0 then
                local pw = math.max(1, width * s.n / total)
                part:ClearAllPoints()
                part:SetPoint("TOPLEFT", track, "TOPLEFT", x, 0)
                part:SetSize(pw, track:GetHeight())
                part:SetColorTexture(s.school[3][1], s.school[3][2], s.school[3][3], 0.9)
                x = x + pw
            end
        end
    end
    local function schoolTotals(hits)
        local by, list = {}, {}
        for _, hit in ipairs(hits) do
            local sch = schoolOf(hit)
            if not by[sch] then by[sch] = {school = sch, n = 0}; list[#list + 1] = by[sch] end
            by[sch].n = by[sch].n + taken(hit)
        end
        table.sort(list, function(a, b) return a.n > b.n end)
        return list
    end

    function p:Show(d)
        local hits = d and d.hits or {}
        local has = #hits > 0
        for _, r in ipairs({self.total, self.totalNote, self.span, self.track, self.shares, self.line}) do r:SetShown(has) end
        for _, part in ipairs(self.parts) do part:SetShown(false) end
        self.empty:SetShown(not has)
        self.empty:SetText(d and "The game gave no recap for this death." or "")
        local total, first, last = 0, nil, nil
        for _, hit in ipairs(hits) do
            total = total + taken(hit)
            if hit.t then first, last = math.min(first or hit.t, hit.t), math.max(last or hit.t, hit.t) end
        end
        self.total:SetText(St.commas(total))
        self.totalNote:SetText(("damage in your last %d %s"):format(#hits, #hits == 1 and "hit" or "hits"))
        self.span:SetText(first and ("over %.1fs"):format(last - first) or "")
        local bySchool = schoolTotals(hits)
        stack(self.parts, self.track, w, bySchool, total)
        local shares = {}
        for _, s in ipairs(bySchool) do
            shares[#shares + 1] = ("%s%s %d%%|r"):format(hex(s.school[3]), s.school[2], total > 0 and 100 * s.n / total + 0.5 or 0)
        end
        self.shares:SetText(table.concat(shares, "  /  "))
        for i, c in ipairs(self.schools) do
            local s = bySchool[i]
            for _, r in pairs(c) do r:SetShown(s ~= nil) end
            if s then
                c.square:SetColorTexture(s.school[3][1], s.school[3][2], s.school[3][3], 1)
                c.name:SetText(s.school[2]:upper())
                c.value:SetText(hex(s.school[3]) .. St.commas(s.n) .. "|r")
            end
        end
        -- attackers, most damage first; their spells, most damage first
        local by, list = {}, {}
        for _, hit in ipairs(hits) do
            local who = hit.source or "Unknown"
            if not by[who] then by[who] = {name = who, kind = hit.kind, n = 0, hits = {}, spells = {}}; list[#list + 1] = by[who] end
            local a = by[who]
            a.n = a.n + taken(hit)
            a.hits[#a.hits + 1] = hit
            local key = hit.spell or "Melee"
            if not a.spells[key] then a.spells[key] = {name = key, hit = hit, n = 0, count = 0}; a.spells[#a.spells + 1] = a.spells[key] end
            a.spells[key].n, a.spells[key].count = a.spells[key].n + taken(hit), a.spells[key].count + 1
        end
        table.sort(list, function(a, b) return a.n > b.n end)
        for i, row in ipairs(self.attackers) do
            local a = list[i]
            for _, r in ipairs({row.name, row.total, row.track}) do r:SetShown(a ~= nil) end
            for _, part in ipairs(row.parts) do part:SetShown(false) end
            for _, b in ipairs(row.icons) do b:Hide(); b.value:Hide() end
            if a then
                row.name:SetText(a.kind == "player" and ("|cffff6060" .. a.name .. "|r") or a.name)
                row.total:SetText(St.commas(a.n))
                stack(row.parts, row.track, w - 210, schoolTotals(a.hits), total)
                table.sort(a.spells, function(x, y) return x.n > y.n end)
                for k, b in ipairs(row.icons) do
                    local sp = a.spells[k]
                    if sp then
                        b.icon:SetTexture(spellIcon(sp.hit))
                        b.value:SetText(hex(schoolOf(sp.hit)[3]) .. St.commas(sp.n) .. "|r")
                        b.tip = {sp.name, {("%s damage, %d %s"):format(St.commas(sp.n), sp.count, sp.count == 1 and "hit" or "hits"),
                            schoolOf(sp.hit)[2]}}
                        b:Show()
                        b.value:Show()
                    end
                end
            end
        end
        if withHits then
            self.hitsTitle:SetShown(has)
            local newestFirst = hits -- the recap lists the killing blow first; time runs back from it
            for i, r in ipairs(self.hits) do
                local hit = newestFirst[#newestFirst - i + 1] -- oldest at the top
                for _, part in pairs(r) do part:SetShown(hit ~= nil) end
                if hit then
                    r.time:SetText(hit.t and last and ("%.1fs"):format(hit.t - last) or "")
                    r.what:SetText(("%s · %s"):format(hit.spell or (hit.kind == "world" and "" or "Melee"), hit.source or "Unknown"))
                    r.amount:SetText(hex(schoolOf(hit)[3]) .. St.commas(taken(hit)) .. "|r"
                        .. ((hit.overkill or 0) > 0 and (" (" .. St.commas(hit.overkill) .. " overkill)") or ""))
                    r.hp:SetText(hit.hp and d.maxHp and d.maxHp > 0 and ("%d%% hp"):format(100 * hit.hp / d.maxHp + 0.5)
                        or hit.hp and (St.commas(hit.hp) .. " hp") or "")
                end
            end
        end
    end
    return p
end

-- The popup when you die: the recap, its title the killing blow, and a button to the death on the Deaths page
local POPUP_W, POPUP_H = 590, 357 -- the content as large as before the Road to Sixty frame's 10 px gap
local popup, popupBody = St.Window("KureqDeathRecapFrame", "Death Recap", POPUP_W, POPUP_H)
popup:ClearAllPoints()
popup:SetPoint("TOP", UIParent, "TOP", 0, -120)
local popupTitle = Text(popupBody, "GameFontNormalLarge")
popupTitle:SetPoint("TOPLEFT", 14, -12)
popupTitle:SetPoint("RIGHT", -14, 0)
local popupSub = Text(popupBody, "GameFontDisableSmall")
popupSub:SetPoint("TOPLEFT", popupTitle, "BOTTOMLEFT", 0, -4)
local popupPane = Pane(popupBody)
popupPane:SetPoint("TOPLEFT", 8, -50)
popupPane:SetPoint("BOTTOMRIGHT", -8, 40)
local popupRecap = S.RecapPanel(popupPane, St.bodySize(POPUP_W, POPUP_H) - 16 - 24, false)
popupRecap.frame:SetPoint("TOPLEFT", 12, -12)
local openDeaths = CreateFrame("Button", nil, popupBody, "UIPanelButtonTemplate")
openDeaths:SetPoint("BOTTOMRIGHT", -10, 10)
openDeaths:SetSize(150, 22)
openDeaths:SetText("Open the Deaths page")
openDeaths:SetScript("OnClick", function()
    popup:Hide()
    if S.openDeaths then S.openDeaths(popup.death) end
end)
S.recapPopup = popup
ns.OnModuleChange("stats", function(on) if not on then popup:Hide() end end)

function S.showRecap(d)
    if not ns.IsOn("stats") then return end -- turned off while the recap was still being waited for
    popup.death = d
    if not d.killer then popupTitle:SetText("Died")
    elseif d.kind == "world" then popupTitle:SetText("Died: " .. d.killer)
    else popupTitle:SetText("Killed by " .. (d.kind == "player" and ("|cffff6060" .. d.killer .. "|r") or d.killer)
        .. (d.spell and (" (" .. d.spell .. ")") or "")) end
    local where = d.map and C_Map.GetMapInfo and C_Map.GetMapInfo(d.map)
    popupSub:SetText(date("%H:%M", d.t) .. (where and (" · " .. where.name) or "") .. " · level " .. (d.level or "?"))
    popupRecap:Show(d)
    popup:Show()
end
