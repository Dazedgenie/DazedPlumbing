--[[ Dazed Utilities: Plumbing -- the Main Water Panel's face as draw operations plus click regions, so it tests headlessly.
     DUP_Board draws the ops (Dazed Power's kinds: rect, card, tex, quad, line, text); Board.tex finds Dazed Power's
     board art by path, and answers nil without it so the face falls back to drawn rectangles and lines.

     THE SNAPSHOT (what build() reads; DUP_Board makes it from the synced main entry and the last mainInfo reply):
       connected   bool                      waiting   bool, no mainInfo reply yet
       building    { kind = "building"|"structure", tiles, floors }      day   the day it was connected (1 = first)
       flow        the line rate (L/min)     rate      the house throttle (L/min)
       shut, drain, drained                  bools from the entry
       status      { supply, demand, rationed, dry, tainted, paused, frozen, piped }
       tanks       { { name, size, amount, cap, tainted, leaking, frozen, feeding } }
       sources     { { kind, label, state, detail, lpm, off, flow, canOff, canFlow, powered, watts } }
       fixtures    { { kind, room, amount, cap, closed, prio, used, ownTap, townWater, tainted } }   in fill order
       today       litres today              hist      24 hourly litres          hour   hour of the day (0-24)
       nowHour     the world hour, for "used N h ago"
       outOfRange  bool, the main's square is not loaded on the server: only the entry's figures ]]

DazedPlumb = DazedPlumb or {}
local Board = {}
DazedPlumb.BoardLayout = Board

-- The face in base pixels; build() scales everything by S, the ratio of the loaded fonts to the base set.
Board.W, Board.H = 760, 560
Board.TEX = "media/ui/DazedPower/Board/"
Board.DIAL_MIN = 40               -- the dials read 0-40 L/min, or up to the line rate when that is higher
Board.SRC_ROWS, Board.FIX_ROWS = 8, 6

local C = {
    frame = { 0.204, 0.251, 0.290 }, bar = { 0.176, 0.220, 0.255 }, barText = { 0.910, 0.925, 0.925 },
    board = { 0.886, 0.890, 0.855 }, card = { 0.851, 0.859, 0.824 }, line = { 0.600, 0.620, 0.600 },
    ink = { 0.133, 0.153, 0.165 }, muted = { 0.420, 0.447, 0.455 }, red = { 0.733, 0.169, 0.133 },
    green = { 0.290, 0.560, 0.255 }, amber = { 0.800, 0.540, 0.120 }, dark = { 0.157, 0.169, 0.176 },
    cream = { 0.929, 0.925, 0.886 }, paper = { 0.965, 0.961, 0.929 }, grid = { 0.769, 0.827, 0.851 },
    water = { 0.255, 0.537, 0.851 }, taint = { 0.494, 0.533, 0.247 }, ice = { 0.765, 0.882, 0.957 },
    segOff = { 0.200, 0.196, 0.188 }, segOn = { 0.475, 0.773, 0.420 }, segLow = { 0.886, 0.643, 0.235 },
    white = { 1, 1, 1 }, lampOff = { 0.247, 0.255, 0.255 }, steel = { 0.553, 0.588, 0.612 },
}
Board.COLORS = C

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
Board.clamp = clamp

--- The texture at Board.TEX .. name when the window says it can be loaded, else nil (the face then draws a stand-in).
--  The window sets Board.resolver(path) -> bool; with none (tests, no Dazed Power) every texture is missing.
function Board.tex(name)
    local path = Board.TEX .. name
    local r = Board.resolver
    if r and r(path) then return path end
    return nil
end

--- The dial's full scale for a line rate.
function Board.dialFull(flow)
    local f = tonumber(flow) or 0
    if f <= Board.DIAL_MIN then return Board.DIAL_MIN end
    return math.ceil(f / 10) * 10
end

--- Litres as a short string: whole litres from 10 up, one decimal below.
function Board.fmtL(v)
    v = tonumber(v) or 0
    if v >= 10 or v == math.floor(v) then return string.format("%d", math.floor(v + 0.5)) end
    return string.format("%.1f", v)
end

--- The needle of a dial at x, y (diameter d) pointing at fraction f, as a turned quad's eight corners times S.
--  The same geometry as Dazed Power's board, so its needle.png fits.
function Board.needleQuad(x, y, d, f, S)
    S = S or 1
    local cx, cy = x + d / 2, y + d / 2
    local ro = d / 2 - 11
    local a = math.rad(225 - 270 * clamp(f or 0, -0.02, 1.02))
    local k = (ro - 4) / 80
    local dx, dy = math.cos(a), -math.sin(a)
    local px, py = -dy, dx
    local q = {}
    for _, uv in ipairs({ { -14, -8 }, { 82, -8 }, { 82, 8 }, { -14, 8 } }) do
        q[#q + 1] = (cx + (uv[1] * dx + uv[2] * px) * k) * S
        q[#q + 1] = (cy + (uv[1] * dy + uv[2] * py) * k) * S
    end
    return q
end

--- The drawn stand-in needle: a line from the hub to the tip, x1, y1, x2, y2 times S.
function Board.needleLine(x, y, d, f, S)
    S = S or 1
    local cx, cy = x + d / 2, y + d / 2
    local a = math.rad(225 - 270 * clamp(f or 0, -0.02, 1.02))
    local r = d / 2 - 18
    return cx * S, cy * S, (cx + r * math.cos(a)) * S, (cy - r * math.sin(a)) * S
end

--- The five lamps under the sources list.
function Board.lamps(s)
    local st = s.status or {}
    local live = s.connected and st.piped and not st.dry and not st.paused
    return {
        { lab = "IGUI_DazedPlumb_BoardLampSupply", lit = live == true, col = "green" },
        { lab = "IGUI_DazedPlumb_BoardLampTainted", lit = st.tainted == true, col = "red" },
        { lab = "IGUI_DazedPlumb_BoardLampDry", lit = st.dry == true, col = "red", blink = true },
        { lab = "IGUI_DazedPlumb_BoardLampRationed", lit = st.rationed == true, col = "amber" },
        { lab = "IGUI_DazedPlumb_BoardLampPaused", lit = (st.paused or s.shut or st.frozen) == true, col = "amber" },
    }
end

--- A fixture's kind as a translation key ("washing machine" -> ..._washing_machine).
function Board.kindKey(kind)
    return "IGUI_DazedPlumb_FixtureKind_" .. string.gsub(tostring(kind or "fixture"), "[^%w]", "_")
end

--- Build the face for a snapshot `s`.
--  `o`: S, fontH(name), measure(name, str), getText(key), txt(key, ...), needles { supply, demand } (0..1, eased by the
--  window), readOnly, noConnect (no CONNECT BUILDING: opened at a wall panel), blink, shutArmed, srcScroll, fixScroll.
--  @return { w, h, ops, hits, scrolls, needleOps } in screen pixels; needleOps { supply, demand } each
--  { op, x, y, d } in base pixels, for Board.needleQuad (a "quad" op) or Board.needleLine (a "line" op).
function Board.build(s, o)
    o = o or {}
    local S = o.S or 1
    local ops, hits, scrolls, needleOps = {}, {}, {}, {}
    local function fh(f) return o.fontH(f) / S end
    local function mw(f, str) return o.measure(f, tostring(str)) / S end
    local T, TX = o.getText, o.txt
    local live = s.connected == true and not o.readOnly

    local function rect(x, y, w, h, c, a) ops[#ops + 1] = { k = "rect", x = x, y = y, w = w, h = h, c = c, a = a or 1 } end
    local function card(x, y, w, h, fill, line, a) ops[#ops + 1] = { k = "card", x = x, y = y, w = w, h = h, c = fill, line = line, a = a or 1 } end
    local function line(x1, y1, x2, y2, th, c, a) ops[#ops + 1] = { k = "line", x = x1, y = y1, x2 = x2, y2 = y2, th = th, c = c, a = a or 1 } end
    local function text(str, x, y, c, font, align, a)
        ops[#ops + 1] = { k = "text", str = tostring(str), x = x, y = y, c = c, font = font or "Small", align = align or "left", a = a or 1 }
    end
    -- A texture op when Board.tex finds it; returns false so the caller draws its stand-in.
    local function tex(name, x, y, w, h, a, tint)
        local path = Board.tex(name)
        if not path then return false end
        ops[#ops + 1] = { k = "tex", name = path, x = x, y = y, w = w, h = h, a = a or 1, c = tint }
        return true
    end
    local function hit(x, y, w, h, id) hits[#hits + 1] = { x = x, y = y, w = w, h = h, id = id } end
    local function fit(str, font, w)
        str = tostring(str)
        if mw(font, str) <= w then return str end
        while #str > 1 and mw(font, str .. "..") > w do
            local n = #str
            while n > 1 and string.byte(str, n) >= 128 and string.byte(str, n) < 192 do n = n - 1 end
            str = string.sub(str, 1, n - 1)
        end
        return str .. ".."
    end
    local function wrap(str, font, w)
        local out, cur = {}, ""
        for word in string.gmatch(tostring(str or ""), "%S+") do
            local try = cur == "" and word or (cur .. " " .. word)
            if mw(font, try) > w and cur ~= "" then out[#out + 1] = cur cur = word else cur = try end
        end
        if cur ~= "" then out[#out + 1] = cur end
        return out
    end
    local function tr(key, fallback)
        local v = T(key)
        if type(v) ~= "string" or string.find(v, "IGUI_", 1, true) then return fallback or key end
        return v
    end
    -- A filled disc from thin strips, for the drawn stand-ins.
    local function disc(cx, cy, r, c, a)
        local step = r > 20 and 3 or 2
        local yy = -r
        while yy < r do
            local mid = yy + step / 2
            local half = math.sqrt(math.max(0, r * r - mid * mid))
            rect(cx - half, cy + yy, 2 * half, step, c, a)
            yy = yy + step
        end
    end
    local function ring(cx, cy, r, th, c, a)
        local n = 32
        for i = 0, n - 1 do
            local a1, a2 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
            line(cx + r * math.cos(a1), cy + r * math.sin(a1), cx + r * math.cos(a2), cy + r * math.sin(a2), th, c, a)
        end
    end
    local LAMP = { green = C.green, red = C.red, amber = C.amber }
    local function lamp(col, lit, x, y, size)
        if tex(lit and ("lamp_" .. col .. ".png") or "lamp_off.png", x, y, size, size) then return end
        disc(x + size / 2, y + size / 2, size / 2, C.dark)
        disc(x + size / 2, y + size / 2, size / 2 - 2, lit and LAMP[col] or C.lampOff)
    end
    local function wheel(x, y, w, h)
        if tex("wheel.png", x, y, w, h) then return end
        rect(x, y, w, h, C.dark)
        rect(x + 2, y + 2, w - 4, h / 2 - 2, C.segOff)
    end
    local function toggle(up, x, y, w, h, a)
        if tex(up and "toggle_up.png" or "toggle_down.png", x, y, w, h, a) then return end
        rect(x, y, w, h, C.dark, a)
        rect(x + 3, up and (y + 3) or (y + h / 2), w - 6, h / 2 - 3, up and C.segOn or C.red, a)
    end
    local function triangle(x, y, w, h, up, c, a)
        local n = math.max(3, math.floor(h / 2))
        for i = 0, n - 1 do
            local f = (i + 1) / n
            local ww = w * f
            local yy = up and (y + i * h / n) or (y + h - (i + 1) * h / n)
            rect(x + (w - ww) / 2, yy, ww, h / n, c, a)
        end
    end

    local W, H = Board.W, Board.H
    local st = s.status or {}
    local flow = tonumber(s.flow) or 30
    local rate = clamp(tonumber(s.rate) or flow, 0, flow)

    -- Frame, board and the title bar: the panel's name, the building it serves, the close X.
    rect(0, 0, W, H, C.frame)
    rect(6, 6, W - 12, H - 12, C.board)
    rect(6, 6, W - 12, 34, C.bar)
    local title = T("IGUI_DazedPlumb_BoardTitle")
    text(title, 18, 23 - fh("Medium") / 2, C.barText, "Medium")
    text("X", W - 24, 23 - fh("Small") / 2, C.barText, "Small", "center")
    hit(W - 36, 6, 30, 34, "close")
    local bline
    if s.connected and s.building then
        bline = TX("IGUI_DazedPlumb_BoardBuilding", tr("IGUI_DazedPlumb_BoardKind_" .. tostring(s.building.kind), string.upper(tostring(s.building.kind))),
            tostring(s.building.floors or 0), tostring(s.building.tiles or 0), tostring(s.day or 1))
    else
        bline = T("IGUI_DazedPlumb_BoardNotConnected")
    end
    local left = 18 + mw("Medium", title) + 16
    text(fit(bline, "NewSmall", math.max(20, W - 44 - left)), W - 44, 23 - fh("NewSmall") / 2, C.barText, "NewSmall", "right", 0.85)

    -- The two dials: what reached the house last minute, and what the house wants, in L/min.
    local full = Board.dialFull(flow)
    local function gauge(id, x, y, d, f, titleKey, red)
        local cx, cy = x + d / 2, y + d / 2
        local ro = d / 2 - 11
        if not tex("gauge_face.png", x, y, d, d) then
            disc(cx, cy, d / 2, C.dark)
            disc(cx, cy, d / 2 - 5, C.paper)
        end
        local function at(fr, r)
            local a = math.rad(225 - 270 * fr)
            return cx + r * math.cos(a), cy - r * math.sin(a)
        end
        if red and red < 1 then
            for i = 0, 15 do
                local x1, y1 = at(red + (1 - red) * i / 16, ro - 3)
                local x2, y2 = at(red + (1 - red) * (i + 1) / 16, ro - 3)
                line(x1, y1, x2, y2, 5, C.red, 0.9)
            end
        end
        for i = 0, 20 do
            local major = i % 5 == 0
            local x1, y1 = at(i / 20, ro)
            local x2, y2 = at(i / 20, ro - (major and 12 or 6))
            line(x1, y1, x2, y2, major and 2.5 or 1.2, C.ink)
            if major then
                local tx, ty = at(i / 20, ro - 24)
                text(string.format("%d", math.floor(full * i / 20 + 0.5)), tx, ty - fh("Small") / 2, C.ink, "Small", "center")
            end
        end
        text(T("IGUI_DazedPlumb_BoardLpm"), cx, cy + d * 0.2, C.muted, "Small", "center")
        text(T(titleKey), cx, y + d + 2, C.ink, "Medium", "center")
        if Board.tex("needle.png") then
            ops[#ops + 1] = { k = "quad", name = Board.TEX .. "needle.png", pts = Board.needleQuad(x, y, d, f, 1), a = 1 }
        else
            local x1, y1, x2, y2 = Board.needleLine(x, y, d, f, 1)
            ops[#ops + 1] = { k = "line", x = x1, y = y1, x2 = x2, y2 = y2, th = 3, c = C.red, a = 1 }
        end
        needleOps[id] = { op = ops[#ops], x = x, y = y, d = d }
        if not tex("hub.png", cx - 10, cy - 10, 20, 20) then disc(cx, cy, 8, C.dark) end
    end
    local needles = o.needles or {}
    gauge("supply", 20, 46, 170, s.connected and needles.supply or 0, "IGUI_DazedPlumb_BoardSupply", rate / full)
    gauge("demand", 206, 46, 170, s.connected and needles.demand or 0, "IGUI_DazedPlumb_BoardDemand")

    -- LINE RATE: a knob and its reading on number wheels; the left half of the strip steps down, the right half up.
    local function lineRate()
        local y = 240
        text(T("IGUI_DazedPlumb_BoardLineRate"), 22, y + 22 - fh("Medium") / 2, C.ink, "Medium")
        local kx, ky, kd = 150, y + 4, 36
        disc(kx + kd / 2, ky + kd / 2, kd / 2, C.dark)
        disc(kx + kd / 2, ky + kd / 2, kd / 2 - 4, C.steel)
        local a = math.rad(225 - 270 * (flow > 0 and rate / flow or 0))
        line(kx + kd / 2, ky + kd / 2, kx + kd / 2 + (kd / 2 - 5) * math.cos(a), ky + kd / 2 - (kd / 2 - 5) * math.sin(a), 3, C.cream)
        local str = string.format(flow >= 100 and "%03d" or "%02d", math.floor(rate + 0.5))
        local ww, gap = 22, 4
        local wx = 210
        for i = 1, #str do
            wheel(wx + (i - 1) * (ww + gap), y + 6, ww, 32)
            text(str:sub(i, i), wx + (i - 1) * (ww + gap) + ww / 2, y + 22 - fh("CodeLarge") / 2, C.white, "CodeLarge", "center")
        end
        text(T("IGUI_DazedPlumb_BoardLpm"), wx + #str * (ww + gap) + 2, y + 22 - fh("Small") / 2, C.ink, "Small")
        text("-", 136, y + 22 - fh("Large") / 2, C.ink, "Large", "center", (live and rate > 1) and 1 or 0.35)
        text("+", 368, y + 22 - fh("Large") / 2, C.ink, "Large", "center", (live and rate < flow) and 1 or 0.35)
        if live then
            hit(126, y, 132, 44, "rate:-")
            hit(258, y, 122, 44, "rate:+")
        end
    end
    lineRate()

    -- The water tower: every tank on the line together, in one column.
    local function tower()
        local bx, by = 396, 52
        local amt, cap, frozen, tainted = 0, 0, false, st.tainted == true
        for _, t in ipairs(type(s.tanks) == "table" and s.tanks or {}) do
            amt, cap = amt + (tonumber(t.amount) or 0), cap + (tonumber(t.cap) or 0)
            if t.frozen then frozen = true end
        end
        local frac = cap > 0 and clamp(amt / cap, 0, 1) or 0
        card(bx, by, 60, 170, C.dark, C.dark)
        local ix, iy, iw, ih = bx + 9, by + 19, 42, 140
        rect(ix, iy, iw, ih, C.segOff)
        local col = frozen and C.ice or (tainted and C.taint or C.water)
        local fhh = ih * frac
        if fhh > 0.5 then rect(ix, iy + ih - fhh, iw, fhh, col) end
        for i = 1, 3 do rect(ix, iy + ih * i / 4, 8, 1.5, C.cream, 0.8) end
        rect(bx + 22, by + 4, 16, 10, C.steel)
        text(cap > 0 and string.format("%d%%", math.floor(frac * 100 + 0.5)) or "--", bx + 30, by + 176, C.ink, "Medium", "center")
        text(Board.fmtL(amt) .. " / " .. Board.fmtL(cap) .. " L", bx + 30, by + 176 + fh("Medium"), C.muted, "Small", "center")
        if frozen then text(T("IGUI_DazedPlumb_Frozen"), bx + 30, by + 176 + fh("Medium") + fh("Small"), C.water, "NewSmall", "center") end
    end
    tower()

    -- SOURCES ON LINE: what feeds the tanks, each with its state, its flow (click to step it) and its switch.
    local function sources()
        local x, y, w = 470, 50, 276
        local rows = type(s.sources) == "table" and s.sources or {}
        text(T("IGUI_DazedPlumb_BoardSources"), x, y, C.ink, "Medium")
        local ry, pitch = y + 24, 19
        if s.outOfRange then
            for li, l in ipairs(wrap(T("IGUI_DazedPlumb_BoardOutOfRange"), "Small", w)) do
                if li <= 3 then text(l, x, ry + (li - 1) * fh("Small"), C.muted, "Small") end
            end
        elseif s.waiting then text(T("IGUI_DazedPlumb_BoardWaiting"), x, ry, C.muted, "Small")
        elseif #rows == 0 then text(T("IGUI_DazedPlumb_BoardSourcesNone"), x, ry, C.muted, "Small") end
        local fitN = Board.SRC_ROWS
        local maxOff = math.max(0, #rows - fitN)
        local off = math.max(0, math.min(maxOff, math.floor(tonumber(o.srcScroll) or 0)))
        for i = off + 1, math.min(#rows, off + fitN) do
            local r = rows[i]
            local yy = ry + (i - off - 1) * pitch
            local on = (tonumber(r.lpm) or 0) > 0.001 or r.state == "running" or r.state == "pumping"
            lamp("green", on, x, yy + pitch / 2 - 6, 12)
            local name = tr("IGUI_DazedPlumb_SourceKind_" .. tostring(r.kind), tostring(r.kind))
            text(fit(name, "Small", 100), x + 16, yy + pitch / 2 - fh("Small") / 2, r.off and C.muted or C.ink, "Small")
            local state = tr("IGUI_DazedPlumb_PanelState_" .. tostring(r.state), tostring(r.state or ""))
            if r.powered and r.watts and on then state = string.format("%d W", math.floor(r.watts + 0.5)) end
            text(fit(state, "NewSmall", 64), x + 120, yy + pitch / 2 - fh("NewSmall") / 2, C.muted, "NewSmall")
            local fl = Board.fmtL(r.lpm)
            if r.canFlow and r.flow then fl = fl .. " " .. string.format("%d%%", math.floor(r.flow * 100 + 0.5)) end
            text(fit(fl, "Code", 50), x + 236 - 4, yy + pitch / 2 - fh("Code") / 2, C.ink, "Code", "right")
            if live and r.canFlow then hit(x + 182, yy, 52, pitch, "src:flow:" .. i) end
            if r.canOff then
                toggle(not r.off, x + 240, yy + 1, 22, pitch - 2, live and 1 or 0.35)
                if live then hit(x + 238, yy, 26, pitch, "src:off:" .. i) end
            end
        end
        if maxOff > 0 then
            local tx, th = x + w - 4, fitN * pitch
            local thumb = math.max(12, th * fitN / #rows)
            rect(tx, ry, 4, th, C.line, 0.6)
            rect(tx, ry + (th - thumb) * off / maxOff, 4, thumb, C.muted, 0.9)
            hit(tx - 4, ry, 12, th / 2, "src:up")
            hit(tx - 4, ry + th / 2, 12, th / 2, "src:down")
        end
        scrolls[#scrolls + 1] = { id = "src", x = x, y = y, w = w, h = fitN * pitch + 24, max = maxOff, off = off }
        -- the lamps, each with its name under it
        local lamps = Board.lamps(s)
        local pitchL = w / #lamps
        local ly = 230
        for i, L in ipairs(lamps) do
            local cx = x + (i - 0.5) * pitchL
            lamp(L.col, L.lit and (not L.blink or o.blink ~= false), cx - 8, ly, 16)
            text(fit(T(L.lab), "NewSmall", pitchL - 2), cx, ly + 17, L.lit and C.ink or C.muted, "NewSmall", "center")
        end
    end
    sources()

    -- FIXTURES: one row each, in fill order: room, kind, level, litres, valve and the order arrows.
    local function fixtures()
        local x, y, w, h = 14, 284, 368, 264
        card(x, y, w, h, C.card, C.line)
        local rows = type(s.fixtures) == "table" and s.fixtures or {}
        text(T("IGUI_DazedPlumb_BoardFixtures"), x + 12, y + 8, C.ink, "Medium")
        local count = tonumber(s.fixtureCount) or #rows
        text(tostring(count), x + 12 + mw("Medium", T("IGUI_DazedPlumb_BoardFixtures")) + 8, y + 9, C.muted, "Code")
        local ry, pitch = y + 34, 36
        local fitN = Board.FIX_ROWS
        local maxOff = math.max(0, #rows - fitN)
        local off = math.max(0, math.min(maxOff, math.floor(tonumber(o.fixScroll) or 0)))
        if not s.connected then
            text(T("IGUI_DazedPlumb_BoardNotConnected"), x + 12, ry, C.muted, "Small")
        elseif s.outOfRange then
            text(fit(T("IGUI_DazedPlumb_BoardOutOfRange"), "Small", w - 24), x + 12, ry, C.muted, "Small")
        elseif s.waiting then
            text(T("IGUI_DazedPlumb_BoardWaiting"), x + 12, ry, C.muted, "Small")
        elseif #rows == 0 then
            text(T("IGUI_DazedPlumb_BoardFixturesNone"), x + 12, ry, C.muted, "Small")
        end
        if maxOff > 0 then
            triangle(x + w - 46, y + 10, 14, 10, true, C.ink, off > 0 and 1 or 0.3)
            triangle(x + w - 26, y + 10, 14, 10, false, C.ink, off < maxOff and 1 or 0.3)
            hit(x + w - 50, y + 4, 22, 22, "fix:up")
            hit(x + w - 30, y + 4, 22, 22, "fix:down")
        end
        local ordered = 0
        for _, r in ipairs(rows) do if not r.ownTap then ordered = ordered + 1 end end
        for i = off + 1, math.min(#rows, off + fitN) do
            local r = rows[i]
            local yy = ry + (i - off - 1) * pitch
            local own = r.ownTap == true
            card(x + 10, yy + 5, 62, 22, C.board, C.line)
            local tag = r.room and string.upper(tostring(r.room)) or "--"
            text(fit(tag, "NewSmall", 58), x + 41, yy + 16 - fh("NewSmall") / 2, C.ink, "NewSmall", "center")
            local kind = tr(Board.kindKey(r.kind), tostring(r.kind))
            text(fit(kind, "Small", 86), x + 78, yy + 3, r.closed and C.muted or C.ink, "Small")
            local note
            if own then note = T("IGUI_DazedPlumb_BoardOwnTap")
            elseif r.townWater then note = T("IGUI_DazedPlumb_BoardTown")
            elseif r.closed then note = T("IGUI_DazedPlumb_BoardValveShut")
            elseif r.used and s.nowHour then
                note = TX("IGUI_DazedPlumb_BoardUsedAgo", tostring(math.max(0, math.floor(s.nowHour - r.used))))
            end
            if note then text(fit(note, "NewSmall", 86), x + 78, yy + 3 + fh("Small"), C.muted, "NewSmall") end
            local cap = math.max(0.001, tonumber(r.cap) or 0)
            local frac = clamp((tonumber(r.amount) or 0) / cap, 0, 1)
            local bx, by, bw, bh = x + 168, yy + 11, 80, 10
            rect(bx, by, bw, bh, C.dark)
            if frac > 0 then rect(bx + 1, by + 1, (bw - 2) * frac, bh - 2, r.tainted and C.taint or C.water) end
            text(Board.fmtL(r.amount) .. "/" .. Board.fmtL(r.cap), x + 308, yy + 16 - fh("Code") / 2, C.ink, "Code", "right")
            if not own then
                toggle(not r.closed, x + 314, yy + 4, 18, 24, live and 1 or 0.35)
                if live then hit(x + 312, yy + 2, 22, 30, "valve:" .. i) end
                local first, last = (r.prio or i) <= 1, (r.prio or i) >= ordered
                triangle(x + 340, yy + 4, 14, 10, true, C.ink, (live and not first) and 1 or 0.3)
                triangle(x + 340, yy + 18, 14, 10, false, C.ink, (live and not last) and 1 or 0.3)
                if live and not first then hit(x + 336, yy + 1, 22, 15, "prio:up:" .. i) end
                if live and not last then hit(x + 336, yy + 16, 22, 15, "prio:down:" .. i) end
            end
        end
        scrolls[#scrolls + 1] = { id = "fix", x = x, y = y, w = w, h = h, max = maxOff, off = off }
    end
    fixtures()

    -- TODAY: litres on number wheels and the day's 24 hourly bars, midnight to midnight.
    local function today()
        local x, y, w = 394, 284, 182
        text(T("IGUI_DazedPlumb_BoardToday"), x, y + 2, C.ink, "Medium")
        local v = math.floor((tonumber(s.today) or 0) + 0.5)
        local str = string.format("%05d", math.min(99999, v))
        local ww, gap = 20, 3
        local wx = x
        for i = 1, #str do
            wheel(wx + (i - 1) * (ww + gap), y + 26, ww, 28)
            text(str:sub(i, i), wx + (i - 1) * (ww + gap) + ww / 2, y + 40 - fh("CodeMedium") / 2, C.white, "CodeMedium", "center")
        end
        text("L", wx + #str * (ww + gap) + 4, y + 40 - fh("Medium") / 2, C.ink, "Medium")
        local px, py, pw, ph = x, y + 62, w, 70
        rect(px, py, pw, ph, C.paper)
        for i = 1, 3 do rect(px + pw * i / 4, py, 1, ph, C.grid) end
        local hist = type(s.hist) == "table" and s.hist or {}
        local peak = 1
        for i = 1, 24 do peak = math.max(peak, tonumber(hist[i]) or 0) end
        local bw = pw / 24
        local now = math.floor(tonumber(s.hour) or 0)
        for i = 1, 24 do
            local hv = tonumber(hist[i]) or 0
            if hv > 0 then
                local bh = (ph - 6) * clamp(hv / peak, 0, 1)
                rect(px + (i - 1) * bw + 1, py + ph - 2 - bh, bw - 2, bh, (i - 1 == now) and C.amber or C.water)
            end
        end
        rect(px + pw * clamp((tonumber(s.hour) or 0) / 24, 0, 1), py, 1.5, ph, C.red, 0.8)
        for i = 0, 4 do
            text(string.format("%02d", i * 6), px + pw * i / 4, py + ph + 2, C.muted, "NewSmall", i == 0 and "left" or (i == 4 and "right" or "center"))
        end
    end
    today()

    -- CONNECT BUILDING and DRAIN FIXTURES ON SHUT-OFF.
    local function buttons()
        local x, y, w = 394, 440, 182
        local can = not o.readOnly and not o.noConnect
        local a = can and 1 or 0.35
        card(x, y, w, 28, C.dark, C.dark, a)
        text(fit(T("IGUI_DazedPlumb_BoardConnect"), "Small", w - 12), x + w / 2, y + 14 - fh("Small") / 2, C.cream, "Small", "center", a)
        if can then hit(x, y, w, 28, "connect") end
        local cy = y + 38
        local da = live and 1 or 0.35
        rect(x + 2, cy + 2, 16, 16, C.dark, da)
        rect(x + 4, cy + 4, 12, 12, C.paper, da)
        if s.drain then rect(x + 6, cy + 6, 8, 8, C.ink, da) end
        text(fit(T("IGUI_DazedPlumb_BoardDrain"), "NewSmall", w - 26), x + 24, cy + 10 - fh("NewSmall") / 2, C.ink, "NewSmall", "left", da)
        if live then hit(x, cy, w, 20, "drain") end
    end
    buttons()

    -- TANKS ON LINE: up to three, with their litres and what is wrong with them.
    local function tanks()
        local x, y, w, h = 588, 284, 158, 88
        card(x, y, w, h, C.card, C.line)
        text(T("IGUI_DazedPlumb_BoardTanks"), x + 8, y + 5, C.ink, "NewSmall")
        local rows = type(s.tanks) == "table" and s.tanks or {}
        local ty = y + 5 + fh("NewSmall") + 2
        if #rows == 0 then text(T("IGUI_DazedPlumb_BoardTankNone"), x + 8, ty, C.muted, "NewSmall") end
        for i = 1, math.min(3, #rows) do
            local t = rows[i]
            local name = t.name or tr("IGUI_DazedPlumb_BoardTankSize_" .. tostring(t.size), T("IGUI_DazedPlumb_BoardTank"))
            local flags = (t.frozen and "F" or "") .. (t.tainted and "T" or "") .. (t.leaking and "L" or "")
            lamp(t.feeding and "green" or "amber", t.feeding == true, x + 8, ty + 3, 10)
            text(fit(name, "NewSmall", 64), x + 22, ty, C.ink, "NewSmall")
            text(Board.fmtL(t.amount) .. "/" .. Board.fmtL(t.cap) .. (flags ~= "" and (" " .. flags) or ""), x + w - 8, ty, flags ~= "" and C.red or C.muted, "NewSmall", "right")
            ty = ty + fh("NewSmall") + 3
        end
        if #rows > 3 then text("+" .. (#rows - 3), x + w - 8, y + 5, C.muted, "NewSmall", "right") end
    end
    tanks()

    -- MAIN SHUT-OFF: a big wheel; it reads OPEN or PAUSED, and a second click within two seconds turns it.
    local function shutoff()
        local x, y, w, h = 588, 380, 158, 168
        local shut = (st.paused or s.shut) == true
        local paused = shut or st.frozen == true
        local a = live and 1 or 0.45
        card(x, y, w, h, C.dark, C.dark)
        text(fit(T("IGUI_DazedPlumb_BoardShutOff"), "NewSmall", w - 12), x + w / 2, y + 6, C.cream, "NewSmall", "center", a)
        local cx, cy, r = x + w / 2, y + 74, 46
        ring(cx, cy, r, 7, shut and C.red or (paused and C.ice or C.segOn), a)
        local turn = shut and math.rad(36) or 0
        for i = 0, 4 do
            local ang = turn + 2 * math.pi * i / 5
            line(cx, cy, cx + (r - 3) * math.cos(ang), cy + (r - 3) * math.sin(ang), 4, C.steel, a)
        end
        disc(cx, cy, 10, C.steel, a)
        disc(cx, cy, 5, C.dark, a)
        local label = paused and T("IGUI_DazedPlumb_BoardPaused") or T("IGUI_DazedPlumb_BoardOpen")
        text(label, cx, y + 128, paused and C.segLow or C.segOn, "Medium", "center", a)
        if o.shutArmed then
            text(fit(T("IGUI_DazedPlumb_BoardConfirm"), "NewSmall", w - 8), cx, y + 128 + fh("Medium"), C.cream, "NewSmall", "center", o.blink ~= false and 1 or 0.4)
        elseif st.frozen then
            text(fit(T("IGUI_DazedPlumb_BoardReasonFrozen"), "NewSmall", w - 8), cx, y + 128 + fh("Medium"), C.ice, "NewSmall", "center")
        elseif s.drain and not paused then
            text(fit(T("IGUI_DazedPlumb_BoardDrainArmed"), "NewSmall", w - 8), cx, y + 128 + fh("Medium"), C.cream, "NewSmall", "center", 0.7)
        end
        if live then hit(x, y + 18, w, h - 18, "shut") end
    end
    shutoff()

    -- Scale to the loaded font set.
    if S ~= 1 then
        for _, op in ipairs(ops) do
            for _, f in ipairs({ "x", "y", "w", "h", "x2", "y2", "th" }) do if op[f] then op[f] = op[f] * S end end
            if op.pts then for i = 1, #op.pts do op.pts[i] = op.pts[i] * S end end
        end
        for _, h0 in ipairs(hits) do h0.x, h0.y, h0.w, h0.h = h0.x * S, h0.y * S, h0.w * S, h0.h * S end
        for _, h0 in ipairs(scrolls) do h0.x, h0.y, h0.w, h0.h = h0.x * S, h0.y * S, h0.w * S, h0.h * S end
    end
    return { w = W * S, h = H * S, ops = ops, hits = hits, scrolls = scrolls, needleOps = needleOps }
end

return Board
