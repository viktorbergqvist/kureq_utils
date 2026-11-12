-- A zoomable Blizzard map for Kureq Utils' windows (ns.style.MapView): a map's art and its explored overlays, with
-- marks on it. The wheel zooms at the cursor (1x to 8x), dragging moves it, a right-click zooms back out (or, when
-- it's out already, calls onBack). A click that isn't a drag calls onClick(x, y) with the map position (0-1). The art
-- and marks sit on a canvas zoom times the view's size, in a scroll frame that clips it; marks keep their size.
local _, ns = ...
local St = ns.style

local MAX_ZOOM = 8
local DOT_ATLAS = "WhiteCircle-RaidBlips"

-- marks: {x, y (0-1 on the map), size, color = {r, g, b, a}, label = text on it, tip = {title, lines}, onClick}.
-- Marks with a tip or onClick are buttons (zone bubbles); the rest are plain dots.
function St.MapView(parent, w, h)
    local m = {w = w, h = h, zoom = 1, panX = 0, panY = 0, marks = {}}
    local view = CreateFrame("ScrollFrame", nil, parent)
    view:SetSize(w, h)
    view:EnableMouse(true)
    view:EnableMouseWheel(true)
    m.view = view
    local canvas = CreateFrame("Frame", nil, view)
    canvas:SetSize(w, h)
    view:SetScrollChild(canvas)
    m.canvas = canvas
    local note = view:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    note:SetPoint("CENTER")
    note:SetWidth(w - 30)
    m.note = note
    local tiles, overlays, dots, buttons = {}, {}, {}, {}

    local function drawArt(map, CW, CH)
        for _, t in ipairs(tiles) do t:Hide() end
        for _, t in ipairs(overlays) do t:Hide() end
        local layer = map and C_Map.GetMapArtLayers and (C_Map.GetMapArtLayers(map) or {})[1]
        local files = layer and C_Map.GetMapArtLayerTextures(map, 1)
        if not files then return false end
        -- the art: its tiles row by row, scaled to the canvas, edge tiles cut to the layer's size
        local cols = math.ceil(layer.layerWidth / layer.tileWidth)
        local sx, sy = CW / layer.layerWidth, CH / layer.layerHeight
        for i, file in ipairs(files) do
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            local tw = math.min(layer.tileWidth, layer.layerWidth - col * layer.tileWidth)
            local th = math.min(layer.tileHeight, layer.layerHeight - row * layer.tileHeight)
            local t = tiles[i] or canvas:CreateTexture(nil, "ARTWORK")
            tiles[i] = t
            if tw > 0 and th > 0 then
                t:SetTexture(file)
                t:SetTexCoord(0, tw / layer.tileWidth, 0, th / layer.tileHeight)
                t:SetSize(tw * sx, th * sy)
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", col * layer.tileWidth * sx, -row * layer.tileHeight * sy)
                t:Show()
            end
        end
        -- the explored parts over the art, as the world map draws them (MapExplorationDataProvider): each overlay
        -- is tiles of the layer's tile size at an offset in the art's pixels; the last row and column are cut from
        -- a power-of-two file. Overlays only shown when hovering (isShownByMouseOver) are left out.
        local explored = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures(map) or {}
        local o = 0
        for _, info in ipairs(explored) do
            if not info.isShownByMouseOver then
                local wide = math.ceil(info.textureWidth / layer.tileWidth)
                local tall = math.ceil(info.textureHeight / layer.tileHeight)
                for j = 1, tall do
                    local ph = j < tall and layer.tileHeight or (info.textureHeight % layer.tileHeight)
                    if ph == 0 then ph = layer.tileHeight end
                    local fh = layer.tileHeight
                    if j == tall then fh = 16; while fh < ph do fh = fh * 2 end end
                    for k = 1, wide do
                        local pw = k < wide and layer.tileWidth or (info.textureWidth % layer.tileWidth)
                        if pw == 0 then pw = layer.tileWidth end
                        local fw = layer.tileWidth
                        if k == wide then fw = 16; while fw < pw do fw = fw * 2 end end
                        o = o + 1
                        local t = overlays[o] or canvas:CreateTexture(nil, "ARTWORK", nil, 1)
                        overlays[o] = t
                        t:SetTexture(info.fileDataIDs[(j - 1) * wide + k])
                        t:SetTexCoord(0, pw / fw, 0, ph / fh)
                        t:SetSize(pw * sx, ph * sy)
                        t:ClearAllPoints()
                        t:SetPoint("TOPLEFT", (info.offsetX + layer.tileWidth * (k - 1)) * sx,
                            -(info.offsetY + layer.tileHeight * (j - 1)) * sy)
                        t:Show()
                    end
                end
            end
        end
        return true
    end

    local function Bubble()
        local b = CreateFrame("Button", nil, canvas)
        b.dot = b:CreateTexture(nil, "ARTWORK")
        b.dot:SetAllPoints()
        if not b.dot:SetAtlas(DOT_ATLAS) then b.dot:SetColorTexture(1, 1, 1, 1) end
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.label:SetPoint("CENTER")
        b:SetScript("OnEnter", function(self)
            if self.tip then St.Tooltip(self, self.tip[1], self.tip[2] or {}) end
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
        return b
    end

    -- draws map (a uiMapID) with marks; text shows when there's no art
    function m:Draw(map, marks, text)
        self.map, self.marks = map, marks or {}
        local CW, CH = self.w * self.zoom, self.h * self.zoom
        canvas:SetSize(CW, CH)
        view:SetHorizontalScroll(self.panX)
        view:SetVerticalScroll(self.panY)
        for _, d in ipairs(dots) do d:Hide() end
        for _, b in ipairs(buttons) do b:Hide() end
        local drawn = drawArt(map, CW, CH)
        note:SetShown(not drawn)
        note:SetText(text or "No map for this zone")
        if not drawn then return end
        local nd, nb = 0, 0
        for _, mark in ipairs(self.marks) do
            local size, c = mark.size or 7, mark.color or {1, 0.3, 0.2, 0.95}
            local region
            if mark.tip or mark.onClick then
                nb = nb + 1
                region = buttons[nb] or Bubble()
                buttons[nb] = region
                region:SetFrameLevel(canvas:GetFrameLevel() + 2 + nb)
                region.dot:SetVertexColor(c[1], c[2], c[3], c[4] or 0.9)
                region.label:SetText(mark.label or "")
                region.tip, region.onClick = mark.tip, mark.onClick
            else
                nd = nd + 1
                region = dots[nd]
                if not region then
                    region = canvas:CreateTexture(nil, "OVERLAY")
                    if not region:SetAtlas(DOT_ATLAS) then region:SetColorTexture(1, 1, 1, 1) end
                    dots[nd] = region
                end
                region:SetVertexColor(c[1], c[2], c[3], c[4] or 0.95)
            end
            region:SetSize(size, size)
            region:ClearAllPoints()
            region:SetPoint("CENTER", canvas, "TOPLEFT", mark.x * CW, -mark.y * CH)
            region:Show()
        end
    end
    function m:Redraw() self:Draw(self.map, self.marks, note:GetText()) end
    function m:Reset() self.zoom, self.panX, self.panY = 1, 0, 0 end

    -- the cursor over the view, in the view's pixels from its top left
    local function cursor()
        local x, y = GetCursorPosition()
        local scale = view:GetEffectiveScale()
        return x / scale - view:GetLeft(), view:GetTop() - y / scale
    end
    local function clamp()
        m.panX = math.max(0, math.min(m.panX, m.w * (m.zoom - 1)))
        m.panY = math.max(0, math.min(m.panY, m.h * (m.zoom - 1)))
    end
    view:SetScript("OnMouseWheel", function(_, delta)
        local cx, cy = cursor()
        local new = math.max(1, math.min(MAX_ZOOM, m.zoom * (delta > 0 and 1.25 or 0.8)))
        m.panX = (m.panX + cx) / m.zoom * new - cx -- keep the point under the cursor where it is
        m.panY = (m.panY + cy) / m.zoom * new - cy
        m.zoom = new
        clamp()
        m:Redraw()
    end)
    view:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local cx, cy = cursor()
        self.drag = {cx, cy, m.panX, m.panY, moved = false}
        self:SetScript("OnUpdate", function()
            local x, y = cursor()
            if math.abs(x - self.drag[1]) + math.abs(y - self.drag[2]) > 4 then self.drag.moved = true end
            m.panX, m.panY = self.drag[3] - (x - self.drag[1]), self.drag[4] - (y - self.drag[2])
            clamp()
            view:SetHorizontalScroll(m.panX)
            view:SetVerticalScroll(m.panY)
        end)
    end)
    view:SetScript("OnMouseUp", function(self, button)
        local drag = self.drag
        self.drag = nil
        self:SetScript("OnUpdate", nil)
        if button == "RightButton" then
            if m.zoom > 1 or not m.onBack then
                m:Reset()
                m:Redraw()
            else
                m.onBack()
            end
        elseif drag and not drag.moved and m.onClick then
            local cx, cy = cursor()
            m.onClick((m.panX + cx) / (m.w * m.zoom), (m.panY + cy) / (m.h * m.zoom))
        end
    end)
    view:SetScript("OnHide", function(self) self.drag = nil; self:SetScript("OnUpdate", nil) end)
    return m
end
