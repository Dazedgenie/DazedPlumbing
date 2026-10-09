--[[ Dazed Utilities: Plumbing -- the Main Water Panel window: dials, line rate, tower, sources, fixtures, today, shut-off.
     It reads the synced mains entry and the last mainInfo reply, and every switch is a DUP_MainPanel command. ]]

require "ISUI/ISPanel"
require "DazedCore/DC_Picker"
require "DazedPlumbing/DUP_Mains"
require "DazedPlumbing/DUP_MainPanel"
require "DazedPlumbing/DUP_BoardLayout"

local W, P = DazedPlumb.Mains, DazedPlumb.Parts
local Board = DazedPlumb.BoardLayout
local R, CU = DazedCore.Reach, DazedCore.Util

DUP_Board = ISPanel:derive("DUP_Board")
DazedPlumb.Board = DazedPlumb.Board or {}
local Bd = DazedPlumb.Board
Bd.info = Bd.info or {}           -- main key -> { data = the last mainInfo reply, at = ms }

DUP_Board.INFO_EVERY_MS = 10000   -- ask for a fresh mainInfo this often while open
DUP_Board.AFTER_SWITCH_MS = 600   -- and this long after a switch, to show its result
DUP_Board.CONFIRM_MS = 2000       -- the shut-off wheel's second click must come within this

-- The game has no UI scale: Options > Font Size loads a bigger font set, so the face grows by the same ratio.
local S = math.max(1, getTextManager():getFontHeight(UIFont.CodeSmall) / 16)
local function px(v) return math.floor(v * S + 0.5) end
local WIDTH, HEIGHT = math.floor(Board.W * S + 0.5), math.floor(Board.H * S + 0.5)

local FONTS = { Small = UIFont.Small, Medium = UIFont.Medium, Large = UIFont.Large, Code = UIFont.Code,
    CodeSmall = UIFont.CodeSmall, CodeMedium = UIFont.CodeMedium, CodeLarge = UIFont.CodeLarge, NewSmall = UIFont.NewSmall }
local function font(name) return FONTS[name] or UIFont.Small end
local function fontH(name) return getTextManager():getFontHeight(font(name)) end
-- Font -> string -> measured width, bounded; the board measures the same labels on every build.
local measureMemo, measureN = {}, 0
local function measure(name, str)
    str = tostring(str)
    local byFont = measureMemo[name or ""]
    local w = byFont and byFont[str]
    if w then return w end
    local tm = getTextManager()
    local ok, mw = pcall(tm.MeasureStringX, tm, font(name), str)
    if ok and type(mw) == "number" then w = mw else w = #str * math.floor(fontH(name) * 0.6) end
    if measureN >= 4000 then measureMemo, measureN = {}, 0 end
    byFont = measureMemo[name or ""]
    if not byFont then byFont = {} measureMemo[name or ""] = byFont end
    byFont[str] = w
    measureN = measureN + 1
    return w
end

-- Textures by path, missing ones remembered as false; Dazed Power's board art is only there when that mod is on.
local TEXCACHE = {}
local function tex(name)
    local t = TEXCACHE[name]
    if t == nil then
        t = (getTexture and getTexture(name)) or false
        TEXCACHE[name] = t
    end
    return t or nil
end
Board.resolver = function(path) return tex(path) ~= nil end

local function nowMs() return getTimestampMs and getTimestampMs() or 0 end

-- The authority's answer to mainInfo, kept per main (single player gets it at once).
DazedCore.Net.onClient(W.MODULE, "mainInfo", function(args)
    if type(args) ~= "table" or type(args.key) ~= "string" then return end
    Bd.info[args.key] = { data = args, at = nowMs() }
end)

----------------------------------------------------------------- lifecycle
function DUP_Board:createChildren() end

function DUP_Board:onClose() self:close() end

function DUP_Board:close()
    self:removeFromUIManager()
    if Bd.current == self then Bd.current = nil end
end

--- Send one panel command for this main (the authority re-checks it), then ask for the result shortly after.
function DUP_Board:send(cmd, args)
    local a = { x = self.mx, y = self.my, z = self.mz, via = self.via }
    for k, v in pairs(args or {}) do a[k] = v end
    W.send(self.player, cmd, a)
    self.infoDue = nowMs() + DUP_Board.AFTER_SWITCH_MS
end

function DUP_Board:requestInfo()
    self.infoAt = nowMs()
    self.infoDue = nil
    W.send(self.player, "mainInfo", { x = self.mx, y = self.my, z = self.mz, via = self.via })
end

----------------------------------------------------------------- clicks
function DUP_Board:fixtureRow(i) return self.snap and self.snap.fixtures and self.snap.fixtures[i] end
function DUP_Board:sourceRow(i) return self.snap and self.snap.sources and self.snap.sources[i] end

--- Turn a click on one of the board's regions into its command.
function DUP_Board:onHit(id)
    local s = self.snap
    if id == "close" then return self:onClose() end
    local list, dir = id:match("^(%a+):(%a+)$")
    if (list == "src" or list == "fix") and (dir == "up" or dir == "down") then return self:scrollBy(list, dir == "up" and -1 or 1) end
    if not s then return end
    if id == "connect" then
        if not self.readOnly and W.PICKER then DazedCore.Picker.open(self.player, self.main, W.PICKER) end
        return
    end
    if self.readOnly or not s.connected then return end
    if id == "rate:-" or id == "rate:+" then
        local step = (id == "rate:+") and 1 or -1
        local r = math.max(1, math.min(s.flow, math.floor((s.rate or s.flow) + 0.5) + step))
        if r ~= s.rate then self:send("mainRate", { rate = r }) end
    elseif id == "drain" then
        self:send("mainDrain", { drain = not s.drain })
    elseif id == "shut" then
        local now = nowMs()
        if self.shutArmedAt and now - self.shutArmedAt <= DUP_Board.CONFIRM_MS then
            self.shutArmedAt = nil
            self:send("mainShut", { shut = not s.shut })
        else
            self.shutArmedAt = now
        end
    else
        local what, arg = id:match("^(%a+):(%d+)$")
        local kind, sub, idx = id:match("^(%a+):(%a+):(%d+)$")
        if what == "valve" then
            local f = self:fixtureRow(tonumber(arg))
            if f then self:send("mainValve", { fx = f.x, fy = f.y, fz = f.z, closed = not f.closed }) end
        elseif kind == "prio" and (sub == "up" or sub == "down") then
            local f = self:fixtureRow(tonumber(idx))
            if f then self:send("mainPrio", { fx = f.x, fy = f.y, fz = f.z, dir = sub }) end
        elseif kind == "src" and sub == "off" then
            local r = self:sourceRow(tonumber(idx))
            if r then self:send("mainMachine", { mx = r.x, my = r.y, mz = r.z, off = not r.off }) end
        elseif kind == "src" and sub == "flow" then
            local r = self:sourceRow(tonumber(idx))
            if r and r.flow then
                -- step to the next flow setting, round to the lowest after full
                local flows, nextF = DazedPlumb.Pumps.FLOWS, nil
                for _, f in ipairs(flows) do if not nextF and f > r.flow + 0.001 then nextF = f end end
                self:send("mainMachine", { mx = r.x, my = r.y, mz = r.z, flow = nextF or flows[1] })
            end
        end
    end
end

function DUP_Board:hitAt(x, y)
    local hits = self.model and self.model.hits or {}
    for i = #hits, 1, -1 do
        local h = hits[i]
        if x >= h.x and x < h.x + h.w and y >= h.y and y < h.y + h.h then return h end
    end
    return nil
end

--- Scroll one of the board's lists by `step` rows, within what the last layout said it can.
function DUP_Board:scrollBy(id, step)
    for _, a in ipairs(self.model and self.model.scrolls or {}) do
        if a.id == id then
            self.scroll = self.scroll or {}
            self.scroll[id] = math.max(0, math.min(a.max, a.off + step))
            return true
        end
    end
    return false
end

function DUP_Board:onMouseWheel(del)
    local x, y = self:getMouseX(), self:getMouseY()
    for _, a in ipairs(self.model and self.model.scrolls or {}) do
        if a.max > 0 and x >= a.x and x < a.x + a.w and y >= a.y and y < a.y + a.h then
            return self:scrollBy(a.id, del > 0 and 1 or -1)
        end
    end
    return false
end

-- The board drags by its body, so a press counts as a click only when the mouse hardly moved (4 px).
function DUP_Board:onMouseDown(x, y)
    self.pressAt = { getMouseX(), getMouseY() }
    return ISPanel.onMouseDown(self, x, y)
end

function DUP_Board:onMouseUp(x, y)
    local press = self.pressAt
    self.pressAt = nil
    ISPanel.onMouseUp(self, x, y)
    if press and math.abs(getMouseX() - press[1]) + math.abs(getMouseY() - press[2]) <= 4 then
        local h = self:hitAt(x, y)
        if h then self:onHit(h.id) end
    end
    return true
end

----------------------------------------------------------------- reading
--- Is the main still standing, and is the player still where the panel can be worked from?
function DUP_Board:stillThere()
    if not self.main or self.main:getObjectIndex() == -1 then return false end
    if self.via then return true end
    local pl = self.player
    if not pl then return false end
    local dx, dy = pl:getX() - self.mx, pl:getY() - self.my
    local far = W.reach() + 6
    return dx * dx + dy * dy <= far * far
end

function DUP_Board:update()
    ISPanel.update(self)
    if not self:stillThere() then
        self:close()
        return
    end
    self.tick = (self.tick or 0) + 1
    local now = nowMs()
    if (self.infoDue and now >= self.infoDue) or now - (self.infoAt or 0) >= DUP_Board.INFO_EVERY_MS then self:requestInfo() end
    if self.shutArmedAt and now - self.shutArmedAt > DUP_Board.CONFIRM_MS then self.shutArmedAt = nil end
    if self.tick % 6 == 0 or not self.snap then self:refresh() end
end

-- The fixture rows in the order the entry's prio string gives now, with the valve flags it gives now, so a switch
-- shows as soon as the entry syncs, before the next mainInfo.
local function orderFixtures(rows, e)
    local prio = W.squares(e and e.prio)
    local _, closed = W.squares(e and e.valves)
    local byKey, plain, own = {}, {}, {}
    for _, r in ipairs(rows or {}) do
        local copy = {}
        for k, v in pairs(r) do copy[k] = v end
        local key = copy.x .. "," .. copy.y .. "," .. copy.z
        copy.closed = closed[key] == true
        if copy.ownTap then own[#own + 1] = copy
        else
            byKey[key] = byKey[key] or {}
            byKey[key][#byKey[key] + 1] = copy
            plain[#plain + 1] = { key = key, row = copy }
        end
    end
    local out, used = {}, {}
    for _, k in ipairs(prio) do
        if byKey[k] and not used[k] then
            used[k] = true
            for _, r in ipairs(byKey[k]) do out[#out + 1] = r end
        end
    end
    for _, p in ipairs(plain) do if not used[p.key] then out[#out + 1] = p.row end end
    for i, r in ipairs(out) do r.prio = i end
    for _, r in ipairs(own) do r.prio = nil out[#out + 1] = r end
    return out
end

--- Pull everything the face shows into one snapshot, once per beat, never mid-draw.
function DUP_Board:refresh()
    local e = W.store().mains[self.key]
    local rec = Bd.info[self.key]
    local info = rec and rec.data or nil
    local flow = (info and tonumber(info.flow)) or W.flow()
    local snap = { connected = e ~= nil, waiting = e ~= nil and info == nil, flow = flow }
    if e then
        snap.rate = math.max(1, math.min(flow, tonumber(e.rate) or flow))
        snap.shut, snap.drain, snap.drained = e.shut == true, e.drain == true, e.drained == true
        snap.day = e.at and (math.floor(e.at / 24) + 1) or nil
        if info and info.building then
            snap.building = info.building
        else
            local fp = W.footprint(e)
            local _, _, _, _, z0, z1 = R.fpBounds(fp)
            snap.building = { kind = e.k == "s" and "structure" or "building", tiles = fp and R.fpCount(fp) or 0, floors = z0 and (z1 - z0 + 1) or 0 }
        end
    end
    local st = {}
    for k, v in pairs(info and info.status or {}) do st[k] = v end
    st.paused = snap.shut == true
    st.supply = tonumber(st.supply) or (e and e.lpm) or 0
    st.demand = tonumber(st.demand) or 0
    snap.status = st
    snap.tanks = info and info.tanks or {}
    snap.sources = info and info.sources or {}
    snap.fixtures = orderFixtures(info and info.fixtures, e)
    snap.fixtureCount = info and info.fixtureCount or #snap.fixtures
    if info and (info.today ~= nil or info.hist ~= nil) then snap.today, snap.hist = info.today, info.hist
    elseif e then snap.today, snap.hist = e.today, e.hist end
    local gt = getGameTime and getGameTime()
    local tod = gt and P.try(gt, "getTimeOfDay")
    snap.hour = type(tod) == "number" and tod or (info and info.hour) or 0
    snap.nowHour = math.floor(CU.worldHours())
    self.snap = snap
end

----------------------------------------------------------------- the face
local NEEDLES = { "supply", "demand" }
local NEEDLE_EPS = 0.001

--- The needles ease toward their readings.
function DUP_Board:dials(s)
    local full = Board.dialFull(s.flow)
    local n = self.needles or { supply = 0, demand = 0 }
    self.needles = n
    local st = s.status or {}
    n.supply = n.supply + ((tonumber(st.supply) or 0) / full - n.supply) * 0.15
    n.demand = n.demand + ((tonumber(st.demand) or 0) / full - n.demand) * 0.15
end

function DUP_Board:prerender()
    local s = self.snap
    if not s then return end
    self.blink = math.floor((self.tick or 0) / 18) % 2 == 0
    self:dials(s)
    local srcScroll, fixScroll = self.scroll and self.scroll.src, self.scroll and self.scroll.fix
    local armed = self.shutArmedAt ~= nil
    -- Rebuilt only when something it shows changed; between builds only the needles move.
    local b = self.built
    if not (self.model and b and b.s == s and b.blink == self.blink and b.srcScroll == srcScroll
            and b.fixScroll == fixScroll and b.armed == armed) then
        self.model = Board.build(s, {
            S = S, fontH = fontH, measure = measure, getText = getText, txt = CU.txt,
            needles = self.needles, readOnly = self.readOnly, blink = self.blink, shutArmed = armed,
            srcScroll = srcScroll, fixScroll = fixScroll,
        })
        b = b or {}
        b.s, b.blink, b.srcScroll, b.fixScroll, b.armed = s, self.blink, srcScroll, fixScroll, armed
        b.supply, b.demand = self.needles.supply, self.needles.demand
        self.built = b
    else
        for _, k in ipairs(NEEDLES) do
            local no = self.model.needleOps and self.model.needleOps[k]
            local f = s.connected and self.needles[k] or 0
            local was = s.connected and b[k] or 0
            if no and math.abs(f - was) > NEEDLE_EPS then
                if no.op.k == "quad" then
                    no.op.pts = Board.needleQuad(no.x, no.y, no.d, f, S)
                else
                    no.op.x, no.op.y, no.op.x2, no.op.y2 = Board.needleLine(no.x, no.y, no.d, f, S)
                end
                b[k] = self.needles[k]
            end
        end
    end
    self:drawOps(self.model.ops)
end

local RAD = 8
--- A rounded card from Dazed Power's corner textures; square corners when they are missing.
function DUP_Board:card(x, y, w, h, f, b, a)
    local r = math.min(RAD * S, w / 2, h / 2)
    self:drawRect(x + r, y, w - 2 * r, h, a, f[1], f[2], f[3])
    self:drawRect(x, y + r, r, h - 2 * r, a, f[1], f[2], f[3])
    self:drawRect(x + w - r, y + r, r, h - 2 * r, a, f[1], f[2], f[3])
    for _, c in ipairs({ { "tl", x, y }, { "tr", x + w - r, y }, { "bl", x, y + h - r }, { "br", x + w - r, y + h - r } }) do
        local t = tex(Board.TEX .. "cardfill_" .. c[1] .. ".png")
        if t then self:drawTextureScaled(t, c[2], c[3], r, r, a, f[1], f[2], f[3])
        else self:drawRect(c[2], c[3], r, r, a, f[1], f[2], f[3]) end
        if b then
            local tl = tex(Board.TEX .. "cardline_" .. c[1] .. ".png")
            if tl then self:drawTextureScaled(tl, c[2], c[3], r, r, a, b[1], b[2], b[3]) end
        end
    end
    if b then
        local inset = tex(Board.TEX .. "cardline_tl.png") and r or 0
        self:drawRect(x + inset, y, w - 2 * inset, 1, a, b[1], b[2], b[3])
        self:drawRect(x + inset, y + h - 1, w - 2 * inset, 1, a, b[1], b[2], b[3])
        self:drawRect(x, y + inset, 1, h - 2 * inset, a, b[1], b[2], b[3])
        self:drawRect(x + w - 1, y + inset, 1, h - 2 * inset, a, b[1], b[2], b[3])
    end
end

function DUP_Board:drawOps(ops)
    for _, op in ipairs(ops) do
        local c = op.c
        if op.k == "rect" then
            self:drawRect(op.x, op.y, op.w, op.h, op.a, c[1], c[2], c[3])
        elseif op.k == "card" then
            self:card(op.x, op.y, op.w, op.h, c, op.line, op.a)
        elseif op.k == "tex" then
            local t = tex(op.name)
            if t then
                if c then self:drawTextureScaled(t, op.x, op.y, op.w, op.h, op.a, c[1], c[2], c[3])
                else self:drawTextureScaled(t, op.x, op.y, op.w, op.h, op.a, 1, 1, 1) end
            end
        elseif op.k == "quad" then
            local t = tex(op.name)
            local q = op.pts
            -- the four-corner call takes screen coordinates, so add where the window is
            local ax, ay = self:getAbsoluteX(), self:getAbsoluteY()
            if t then self:drawTextureAllPoint(t, ax + q[1], ay + q[2], ax + q[3], ay + q[4], ax + q[5], ay + q[6], ax + q[7], ay + q[8], 1, 1, 1, op.a) end
        elseif op.k == "line" then
            self:drawLine(nil, op.x, op.y, op.x2, op.y2, op.th, op.a, c[1], c[2], c[3])
        elseif op.k == "text" then
            local f = font(op.font)
            if op.align == "right" then self:drawTextRight(op.str, op.x, op.y, c[1], c[2], c[3], op.a, f)
            elseif op.align == "center" then self:drawTextCentre(op.str, op.x, op.y, c[1], c[2], c[3], op.a, f)
            else self:drawText(op.str, op.x, op.y, c[1], c[2], c[3], op.a, f) end
        end
    end
    -- a faint wash over whatever the mouse would click
    local h = self:isMouseOver() and self:hitAt(self:getMouseX(), self:getMouseY())
    if h and h.id ~= "close" then self:drawRect(h.x, h.y, h.w, h.h, 0.08, 1, 1, 1) end
end

----------------------------------------------------------------- opening
function DUP_Board:new(x, y, player, main, opts)
    local o = ISPanel.new(self, x, y, WIDTH, HEIGHT)
    local sq = main:getSquare()
    o.player, o.main = player, main
    -- the main's square (not x/y: those are the panel's own position on screen)
    o.mx, o.my, o.mz = sq:getX(), sq:getY(), sq:getZ()
    o.key = DazedPlumb.Net.key(o.mx, o.my, o.mz)
    opts = type(opts) == "table" and opts or {}
    o.readOnly = opts.readOnly == true
    -- opened from a wall panel (phase 3): its square, which the authority checks names this main
    o.via = type(opts.via) == "table" and { x = opts.via.x, y = opts.via.y, z = opts.via.z } or nil
    o.moveWithMouse = true
    o.background = false
    o.tick = 0
    return o
end

--- Open the panel for a water main; one at a time, so a second open replaces the first.
function DUP_Board.open(player, main, opts)
    if not (player and main and main:getSquare()) then return nil end
    if Bd.current then Bd.current:close() end
    local x = getPlayerScreenLeft(0) + px(60)
    local y = getPlayerScreenTop(0) + px(60)
    if getCore and getCore() then
        local ok, sw, sh = pcall(function() return getCore():getScreenWidth(), getCore():getScreenHeight() end)
        if ok and sw and sh then
            x = math.max(0, math.min(x, sw - WIDTH))
            y = math.max(0, math.min(y, sh - HEIGHT))
        end
    end
    local win = DUP_Board:new(x, y, player, main, opts)
    win:initialise()
    win:addToUIManager()
    win:requestInfo()
    win:refresh()
    Bd.current = win
    return win
end

return DUP_Board
