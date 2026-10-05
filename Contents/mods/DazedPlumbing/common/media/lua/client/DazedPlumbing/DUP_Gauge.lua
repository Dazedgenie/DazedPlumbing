--[[ Dazed Utilities: Plumbing -- the tank gauge window.

     Opened from a tank's menu ("Open gauge"). It shows, live:
       - a gauge in the fluid's colour, the amount, capacity and percent
       - condition, water quality, leaking or catching rain
       - the trend: litres an hour in or out, from what the window has seen,
         and a graph of the last two in-game hours while it stays open
       - what is piped to it: what feeds it, what draws from it, and the other
         tanks on its lines, each with what it is doing right now

     Read only: it never changes anything. The device lines are looked up
     every couple of seconds, the numbers twice a second.
]]

require "ISUI/ISCollapsableWindow"
require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Pipes"
require "DazedPlumbing/DUP_Links"

DUP_Gauge = ISCollapsableWindow:derive("DUP_Gauge")
DazedPlumb.Gauge = DazedPlumb.Gauge or {}
local G = DazedPlumb.Gauge
local P, M, L, K, N = DazedPlumb.Parts, DazedPlumb.Model, DazedPlumb.Links, DazedPlumb.Pipes, DazedPlumb.Net
local try = P.try

-- Sizes follow the font, since the game scales its UI through font size.
local FH = getTextManager():getFontHeight(UIFont.Small)
local FHM = getTextManager():getFontHeight(UIFont.Medium)
local S = math.max(1, FH / 16)
local function px(v) return math.floor(v * S + 0.5) end
local WIDTH, PAD, ROW = px(380), px(10), FH + 3
local GAUGE_W, GAUGE_H, GRAPH_H = px(46), px(150), px(44)
local HISTORY = 120                         -- samples kept, one per in-game minute

local COL = {
    panel = { 0.14, 0.15, 0.18 }, line = { 0.28, 0.30, 0.34 }, text = { 0.86, 0.88, 0.91 },
    dim = { 0.55, 0.58, 0.63 }, good = { 0.42, 0.78, 0.48 }, warn = { 0.85, 0.65, 0.28 }, bad = { 0.80, 0.35, 0.30 },
}
local FLUID = { water = { 0.30, 0.60, 1.00 }, gas = { 0.88, 0.18, 0.18 }, propane = { 0.92, 0.92, 0.90 } }

local function f1(v) return string.format("%.1f", v or 0) end
local function f0(v) return string.format("%d", math.floor((v or 0) + 0.5)) end
local function worldHours()
    local gt = getGameTime and getGameTime()
    return gt and gt:getWorldAgeHours() or 0
end

----------------------------------------------------------- reading the world
--- A device's name as the player knows it: its tile's moveable name, else the item's.
local function deviceName(obj)
    local cn = P.prop(obj, "CustomName")
    if type(cn) == "string" and cn ~= "" then
        if Translator and Translator.getMoveableDisplayName then
            local ok, t = pcall(Translator.getMoveableDisplayName, cn)
            if ok and type(t) == "string" and t ~= "" then return t end
        end
        return cn
    end
    local spr = try(obj, "getSprite")
    return tostring(spr and try(spr, "getName") or "?")
end

local function at(obj)
    local sq = try(obj, "getSquare")
    return sq and string.format("(%d,%d)", sq:getX(), sq:getY()) or ""
end

--- Every network this tank's squares are an end of, resolved, without repeats.
local function linesOf(tank, fluid)
    local T = L.wrapTarget(tank, fluid)
    local out, seen = {}, {}
    for _, q in ipairs(T and T.squares() or {}) do
        local endStr = N.endString(N.key(q:getX(), q:getY(), q:getZ()), "tank", "tank")
        for _, comp in ipairs(K.componentsOf(endStr)) do
            local first = comp.keys and comp.keys[1]
            if first and not seen[first] then
                seen[first] = true
                out[#out + 1] = L.resolve(comp, fluid)
            end
        end
    end
    return out
end

--- The rows of the "piped to" card: { text, state, col }.
function G.connections(tank, d)
    local feeds, draws, tanks, seen = {}, {}, {}, {}
    local unit = M.UNIT[d.type] or "L"
    for _, r in ipairs(linesOf(tank, d.type)) do
        for _, s in ipairs(r.sources) do
            local k = "o" .. tostring(s.obj)
            if not seen[k] then
                seen[k] = true
                local ok, give = pcall(s.adapter.available, s.obj)
                give = ok and tonumber(give) or 0
                feeds[#feeds + 1] = { text = deviceName(s.obj) .. " " .. at(s.obj),
                    state = give > 0.001 and getText("IGUI_DazedPlumb_GaugeGives", f1(give), unit) or getText("IGUI_DazedPlumb_Idle"),
                    col = give > 0.001 and "good" or "dim" }
            end
        end
        for _, n in ipairs(r.nodes) do
            local k = "n" .. tostring(n.obj)
            if not seen[k] then
                seen[k] = true
                feeds[#feeds + 1] = { text = deviceName(n.obj) .. " " .. at(n.obj), state = "", col = "dim" }
            end
        end
        for _, s in ipairs(r.sinks) do
            local k = "s" .. tostring(s.obj)
            if not seen[k] then
                seen[k] = true
                local ok, want = pcall(s.adapter.room, s.obj)
                want = ok and tonumber(want) or 0
                draws[#draws + 1] = { text = deviceName(s.obj) .. " " .. at(s.obj),
                    state = want > 0.001 and getText("IGUI_DazedPlumb_GaugeWants", f1(want), unit) or getText("IGUI_DazedPlumb_GaugeSatisfied"),
                    col = want > 0.001 and "warn" or "dim" }
            end
        end
        for _, t in ipairs(r.tanks) do
            local k = "t" .. tostring(t.obj)
            if t.obj ~= tank and not seen[k] then
                seen[k] = true
                local od = P.data(t.obj)
                tanks[#tanks + 1] = { text = getText(P.sizeKey(od.size)) .. " " .. at(t.obj),
                    state = f0(od.amount) .. " / " .. f0(M.capacity(od.size, od.tier, od.type)) .. " " .. unit, col = "dim" }
            end
        end
    end
    return feeds, draws, tanks
end

--- Litres (or kg) an hour in (+) or out (-), from the samples the window has, or nil.
function G.trend(hist)
    local n = #hist
    if n < 3 then return nil end
    local last = hist[n]
    local first = hist[math.max(1, n - 30)]
    local dt = last.h - first.h
    if dt <= 0 then return nil end
    return (last.a - first.a) / dt
end

----------------------------------------------------------- the window
function DUP_Gauge:new(x, y, tank)
    local o = ISCollapsableWindow.new(self, x, y, WIDTH, px(300))
    o.tank = P.master(tank)
    o.hist = {}
    o.tick = 0
    o:setResizable(false)
    local d = P.data(o.tank)
    o.title = (d.name and (d.name .. " - ") or "") .. getText(P.sizeKey(d.size)) .. " " .. getText(P.typeKey(d.type)) .. " " .. at(o.tank)
    return o
end

function DUP_Gauge:close()
    self:removeFromUIManager()
    if G.current == self then G.current = nil end
end

function DUP_Gauge:update()
    ISCollapsableWindow.update(self)
    if not self.tank or self.tank:getObjectIndex() == -1 then self:close() return end
    self.tick = self.tick + 1
    if self.tick % 30 == 1 then self:refresh(self.tick % 120 == 1) end
end

--- Read the tank (and, now and then, its lines) and size the window to fit.
function DUP_Gauge:refresh(lines)
    local d = P.data(self.tank)
    self.d = d
    local now = worldHours()
    local last = self.hist[#self.hist]
    if not last or now - last.h >= 1 / 60 - 1e-6 then
        self.hist[#self.hist + 1] = { h = now, a = d.amount or 0 }
        while #self.hist > HISTORY do table.remove(self.hist, 1) end
    else
        last.a = d.amount or 0
    end
    if lines or not self.feeds then
        self.feeds, self.draws, self.others = G.connections(self.tank, d)
    end
    local rows = #self.feeds + #self.draws + #self.others
    local heads = 3
    local h = self:titleBarHeight() + PAD + GAUGE_H + PAD + GRAPH_H + PAD
        + px(8) + (rows + heads) * ROW + PAD
    self:setHeight(h)
end

local function c(name) local k = COL[name] or COL.text return k[1], k[2], k[3] end

function DUP_Gauge:txt(s, x, y, col, font)
    local k = COL[col or "text"] or COL.text
    self:drawText(s, x, y, k[1], k[2], k[3], 1, font or UIFont.Small)
end
function DUP_Gauge:txtR(s, x, y, col, font)
    local k = COL[col or "text"] or COL.text
    self:drawTextRight(s, x, y, k[1], k[2], k[3], 1, font or UIFont.Small)
end

function DUP_Gauge:prerender()
    local w = self:getWidth()
    self:drawRect(0, 0, w, self:getHeight(), 0.92, 0.09, 0.10, 0.12)
    ISCollapsableWindow.prerender(self)
    local d = self.d
    if not d then return end
    local unit = M.UNIT[d.type] or "L"
    local cap = M.capacity(d.size, d.tier, d.type)
    local full = M.fullness(d)
    local fl = FLUID[d.type] or FLUID.water
    local top = self:titleBarHeight() + PAD

    -- the gauge: a column filled in the fluid's colour, marks at each quarter
    local gx = PAD
    self:drawRect(gx, top, GAUGE_W, GAUGE_H, 0.9, c("panel"))
    local fillH = math.floor(GAUGE_H * full + 0.5)
    if fillH > 0 then self:drawRect(gx + 2, top + GAUGE_H - fillH, GAUGE_W - 4, fillH, 0.9, fl[1], fl[2], fl[3]) end
    for q = 1, 3 do self:drawRect(gx, top + GAUGE_H * q / 4, px(8), 1, 0.8, c("line")) end
    self:drawRectBorder(gx, top, GAUGE_W, GAUGE_H, 0.8, c("line"))

    -- the numbers beside it
    local x = gx + GAUGE_W + PAD
    self:txt(f1(d.amount) .. " / " .. f0(cap) .. " " .. unit, x, top, "text", UIFont.Medium)
    self:txt(f0(full * 100) .. "%", x, top + FHM, "dim")
    local y = top + FHM + ROW + px(4)
    local cond = d.condition or 100
    self:txt(getText("IGUI_DazedPlumb_Condition"), x, y, "dim")
    self:txtR(f0(cond) .. "%", w - PAD, y, cond < 35 and "bad" or (cond < 60 and "warn" or "text"))
    y = y + ROW
    if d.type == "water" then
        local dirty = M.dirtyFraction(d)
        self:txt(getText("IGUI_DazedPlumb_GaugeQuality"), x, y, "dim")
        self:txtR(getText(M.isTainted(d) and "IGUI_DazedPlumb_Tainted" or "IGUI_DazedPlumb_Clean")
            .. " (" .. f0(dirty * 100) .. "% " .. getText("IGUI_DazedPlumb_GaugeDirty") .. ")", w - PAD, y,
            M.isTainted(d) and "bad" or "good")
        y = y + ROW
    end
    if M.isLeaking(d) then
        self:txt(getText("IGUI_DazedPlumb_Leaking"), x, y, "bad")
        self:txtR(f1(M.leakRate(d)) .. " " .. unit .. "/h", w - PAD, y, "bad")
        y = y + ROW
    end
    if d.catching then
        self:txt(getText("IGUI_DazedPlumb_Catching"), x, y, "good")
        y = y + ROW
    end
    if M.isFrozen(d) then
        self:txt(getText("IGUI_DazedPlumb_Frozen"), x, y, "bad")
        y = y + ROW
    end
    if d.cracked then
        self:txt(getText("IGUI_DazedPlumb_Cracked"), x, y, "bad")
        y = y + ROW
    end
    local tr = G.trend(self.hist)
    self:txt(getText("IGUI_DazedPlumb_GaugeTrend"), x, y, "dim")
    if tr == nil then
        self:txtR(getText("IGUI_DazedPlumb_GaugeWatching"), w - PAD, y, "dim")
    elseif math.abs(tr) < 0.05 then
        self:txtR(getText("IGUI_DazedPlumb_GaugeSteady"), w - PAD, y, "text")
    else
        local s = (tr > 0 and "+" or "") .. f1(tr) .. " " .. unit .. "/h"
        if tr < 0 and (d.amount or 0) > 0 then
            s = s .. "  " .. getText("IGUI_DazedPlumb_GaugeEmptyIn", f1((d.amount or 0) / -tr))
        elseif tr > 0 and cap - (d.amount or 0) > 0 then
            s = s .. "  " .. getText("IGUI_DazedPlumb_GaugeFullIn", f1((cap - (d.amount or 0)) / tr))
        end
        self:txtR(s, w - PAD, y, tr > 0 and "good" or "warn")
    end

    -- the graph: the level over the samples this window has taken
    local gy = top + GAUGE_H + PAD
    local gw = w - PAD * 2
    self:drawRect(PAD, gy, gw, GRAPH_H, 0.9, c("panel"))
    self:drawRectBorder(PAD, gy, gw, GRAPH_H, 0.6, c("line"))
    local n = #self.hist
    if n >= 2 and cap > 0 then
        local bw = gw / HISTORY
        for i = 1, n do
            local v = math.max(0, math.min(1, self.hist[i].a / cap))
            local bh = math.floor((GRAPH_H - 4) * v + 0.5)
            local bx = PAD + gw - (n - i + 1) * bw
            if bh > 0 then self:drawRect(bx, gy + GRAPH_H - 2 - bh, math.max(1, bw), bh, 0.75, fl[1], fl[2], fl[3]) end
        end
    else
        self:txt(getText("IGUI_DazedPlumb_GaugeGraphHint"), PAD + px(6), gy + (GRAPH_H - FH) / 2, "dim")
    end

    -- what it is piped to
    y = gy + GRAPH_H + PAD
    local function section(head, rows, none)
        self:txt(head, PAD, y, "dim")
        if #rows == 0 then self:txtR(none, w - PAD, y, "dim") end
        y = y + ROW
        for _, r in ipairs(rows) do
            self:txt("  " .. r.text, PAD, y, "text")
            self:txtR(r.state, w - PAD, y, r.col)
            y = y + ROW
        end
    end
    section(getText("IGUI_DazedPlumb_GaugeFeeds"), self.feeds or {}, getText("IGUI_DazedPlumb_GaugeNone"))
    section(getText("IGUI_DazedPlumb_GaugeDraws"), self.draws or {}, getText("IGUI_DazedPlumb_GaugeNone"))
    section(getText("IGUI_DazedPlumb_GaugeOthers"), self.others or {}, getText("IGUI_DazedPlumb_GaugeNone"))
end

function DUP_Gauge:render()
    ISCollapsableWindow.render(self)
end

--- Open the gauge for a tank (one window at a time).
function G.open(playerObj, tank)
    if G.current then G.current:close() end
    local x = getPlayerScreenLeft(0) + 120
    local y = getPlayerScreenTop(0) + 90
    local win = DUP_Gauge:new(x, y, tank)
    win:initialise()
    win:addToUIManager()
    win:refresh(true)
    G.current = win
    return win
end

return DUP_Gauge
