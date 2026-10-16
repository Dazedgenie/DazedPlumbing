-- The Main Water Panel's face (DUP_BoardLayout) on a sample snapshot: its click regions, what greys out, scrolling,
-- scaling, the needles, the texture lookup order and the drawn stand-ins when the board textures are missing.
-- Run: lua board_test.lua <lua root>
local root = arg[1] or "../../common/media/lua"
package.path = root .. "/shared/?.lua;" .. package.path
next = nil                                      -- the game's Lua has no next()
local fails, n = 0, 0
local function check(c, msg) n = n + 1 if not c then fails = fails + 1 print("FAIL: " .. msg) end end

require "DazedPlumbing/DUP_BoardLayout"
local B = DazedPlumb.BoardLayout

local function opts(extra)
    local o = { S = 1, fontH = function() return 16 end, measure = function(_, s) return #s * 3 end,
        getText = function(k) return (k:gsub("^IGUI_DazedPlumb_", "")) end, txt = function(k) return (k:gsub("^IGUI_DazedPlumb_", "")) end, needles = { supply = 0.5, demand = 0.25 } }
    for k, v in pairs(extra or {}) do o[k] = v end
    return o
end
local function fixtures(count)
    local out = {}
    for i = 1, count do
        out[i] = { kind = (i % 2 == 0) and "bath" or "sink", room = "kitchen", amount = i, cap = 20, closed = i == 2, prio = i, used = 100 }
    end
    return out
end
local function snap(extra)
    local s = { connected = true, building = { kind = "building", tiles = 120, floors = 2 }, day = 3, flow = 30, rate = 20,
        shut = false, drain = false, nowHour = 103, hour = 7.5, today = 245, hist = {},
        status = { supply = 12, demand = 20, rationed = true, dry = false, tainted = false, paused = false, frozen = false, piped = true },
        tanks = { { name = "Tower", amount = 120, cap = 200, feeding = true } },
        sources = { { kind = "pump", state = "running", lpm = 8, canOff = true, canFlow = true, flow = 1, off = false },
                    { kind = "handpump", state = "manual", lpm = 0 } },
        fixtures = fixtures(3) }
    for i = 1, 24 do s.hist[i] = (i <= 8) and i * 3 or 0 end
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
end
local function ids(m) local out = {} for _, h in ipairs(m.hits) do out[h.id] = h end return out end
local function count(m, kind) local c = 0 for _, op in ipairs(m.ops) do if op.k == kind then c = c + 1 end end return c end
-- A label counts when shown whole or cut short with ".." (the stub measures 3 px a character, the key without its prefix).
local function texts(m, str)
    str = str:gsub("^IGUI_DazedPlumb_", "")
    local c = 0
    for _, op in ipairs(m.ops) do
        if op.k == "text" then
            local cut = op.str:match("^(.-)%.%.$")
            if op.str == str or (cut and #cut > 3 and str:sub(1, #cut) == cut) then c = c + 1 end
        end
    end
    return c
end

-- without Dazed Power: no texture ops at all, everything drawn
B.resolver = nil
check(B.tex("lamp_green.png") == nil, "Board.tex answers nil with no resolver")
local m = B.build(snap(), opts())
local h = ids(m)
check(m.w == B.W and m.h == B.H and B.W == 760 and B.H == 560, "the face has its base size")
check(count(m, "tex") == 0 and count(m, "quad") == 0, "no textures: no tex or quad ops (stand-ins drawn)")
check(#m.ops > 200 and count(m, "rect") > 100, "a full face of drawn ops: " .. #m.ops)
check(h.close and h["rate:-"] and h["rate:+"] and h.connect and h.drain and h.shut, "the panel's controls")
check(h["src:off:1"] and h["src:flow:1"] and h["src:off:2"] == nil, "the pump switches and steps; the hand pump does not")
check(h["valve:1"] and h["valve:3"] and h["prio:down:1"] and h["prio:up:1"] == nil and h["prio:up:3"] and h["prio:down:3"] == nil,
    "valves on every row; the first cannot go up, the last cannot go down")
check(h["fix:up"] == nil and h["fix:down"] == nil, "three fixtures do not scroll")
check(m.needleOps.supply and m.needleOps.supply.op.k == "line" and m.needleOps.demand.op.k == "line", "drawn needles are lines")
local x1, y1, x2, y2 = B.needleLine(20, 46, 170, 0.5, 1)
local nop = m.needleOps.supply.op
check(nop.x == x1 and nop.y == y1 and nop.x2 == x2 and nop.y2 == y2, "a needle moved alone lands where a fresh build puts it")
check(h["rate:-"].x + h["rate:-"].w == h["rate:+"].x, "the rate strip splits into a left and a right half")
check(texts(m, "IGUI_DazedPlumb_BoardTitle") == 1 and texts(m, "IGUI_DazedPlumb_BoardLampRationed") == 1, "title and lamp labels")
check(texts(m, "IGUI_DazedPlumb_BoardOpen") == 1 and texts(m, "IGUI_DazedPlumb_BoardPaused") == 0, "the shut-off reads OPEN")

-- with Dazed Power's textures
B.resolver = function() return true end
local mt = B.build(snap(), opts())
check(count(mt, "tex") > 10 and count(mt, "quad") == 3, "with textures: tex ops, two needle quads and the knob quad")
check(B.tex("wheel.png") == B.TEX .. "wheel.png" and B.TEX == "media/ui/DazedPlumbing/Board/", "Board.tex gives the full path, Plumbing's first")
local nq, same = B.needleQuad(206, 46, 170, 0.25, 1), true
for i = 1, 8 do if nq[i] ~= mt.needleOps.demand.op.pts[i] then same = false end end
check(same, "the quad needle matches needleQuad")
check(#mt.ops < #m.ops, "textures replace drawn stand-ins")
B.resolver = nil

-- the lookup order: Plumbing's folder, then Dazed Power's, then nil (a stub getTexture knows only the listed files)
local PLUMB, POWER = "media/ui/DazedPlumbing/Board/", "media/ui/DazedPower/Board/"
local function stubTextures(files)
    local known = {}
    for _, f in ipairs(files) do known[f] = true end
    getTexture = function(path) return known[path] and { path = path } or nil end
    B.resolver = function(path) return getTexture(path) ~= nil end
end
local function texNamed(m, path) for _, op in ipairs(m.ops) do if (op.k == "tex" or op.k == "quad") and op.name == path then return op end end end
check(B.TEX_DIRS[1] == PLUMB and B.TEX_DIRS[2] == POWER and #B.TEX_DIRS == 2, "two folders, Plumbing's first")
stubTextures({ PLUMB .. "tank_column.png", PLUMB .. "knob.png", PLUMB .. "wheel_open.png", PLUMB .. "wheel_turned.png" })
check(B.tex("knob.png") == PLUMB .. "knob.png" and B.tex("tank_column.png") == PLUMB .. "tank_column.png", "Plumbing's own parts are found")
check(B.tex("gauge_face.png") == nil and B.tex("needle.png") == nil and B.tex("lamp_green.png") == nil, "no Dazed Power: its parts answer nil")
local pm = B.build(snap(), opts())
check(texNamed(pm, PLUMB .. "tank_column.png") and texNamed(pm, PLUMB .. "wheel_open.png") and texNamed(pm, PLUMB .. "wheel_turned.png") == nil,
    "only Plumbing's art: the tank column and the open wheel are textures")
local kop = texNamed(pm, PLUMB .. "knob.png")
check(kop and kop.k == "quad" and count(pm, "quad") == 1, "the knob is the only quad (the needles fall back to lines)")
check(pm.needleOps.supply.op.k == "line" and pm.needleOps.demand.op.k == "line", "no needle.png: drawn needles")
local tc = texNamed(pm, PLUMB .. "tank_column.png")
check(tc.w == B.TANK_W and tc.h == B.TANK_H and tc.w == 60 and tc.h == 170, "the tank column is drawn at 60x170")
local win, fill = B.TANK_WINDOW
for _, op in ipairs(pm.ops) do if op.k == "rect" and op.c == B.COLORS.water and op.w == win.w then fill = op end end
check(fill and fill.x == tc.x + win.x and math.abs(fill.y + fill.h - (tc.y + win.y + win.h)) < 1e-6 and math.abs(fill.h - win.h * 0.6) < 1e-6,
    "the water fills the glass window from its bottom (120 of 200 L = 60%)")
local ang = math.rad(225 - 270 * (20 / 30))
local kq, ksame = B.knobQuad(150, 244, 36, ang, 1), true
for i = 1, 8 do if math.abs(kq[i] - kop.pts[i]) > 1e-9 then ksame = false end end
check(ksame, "the knob quad turns with the line rate")
local q0 = B.knobQuad(0, 0, 36, 0, 1)
check(q0[1] == 0 and q0[2] == 0 and q0[3] == 36 and q0[4] == 0 and q0[5] == 36 and q0[6] == 36 and q0[7] == 0 and q0[8] == 36,
    "an unturned knob quad is its square, top left first")
local q90 = B.knobQuad(0, 0, 36, math.pi / 2, 1)
check(math.abs(q90[1] - 0) < 1e-9 and math.abs(q90[2] - 36) < 1e-9 and math.abs(q90[3]) < 1e-9 and math.abs(q90[4]) < 1e-9,
    "a quarter turn anticlockwise puts the texture's top left at the bottom left")
local q2 = B.knobQuad(0, 0, 36, 0, 2)
check(q2[5] == 72 and q2[6] == 72, "the knob quad scales by S")
local ps = B.build(snap({ shut = true, status = { paused = true, piped = true } }), opts())
check(texNamed(ps, PLUMB .. "wheel_turned.png") and texNamed(ps, PLUMB .. "wheel_open.png") == nil, "shut: the turned wheel")
local pz = B.build(snap({ status = { frozen = true, piped = true } }), opts())
check(texNamed(pz, PLUMB .. "wheel_open.png") and texNamed(pz, PLUMB .. "wheel_turned.png") == nil, "frozen but not shut: the open wheel")
local wop = texNamed(pm, PLUMB .. "wheel_open.png")
check(wop.w == 92 and wop.h == 92 and wop.x == 588 + 79 - 46 and wop.y == 380 + 74 - 46, "the wheel is 92 px on the shut-off card's centre")
local p2 = B.build(snap(), opts({ S = 2 }))
local k2 = texNamed(p2, PLUMB .. "knob.png")
check(k2 and math.abs(k2.pts[5] - 2 * kop.pts[5]) < 1e-9, "the knob quad scales with the font set")
-- Dazed Power alone: its parts, the Plumbing parts drawn
stubTextures({ POWER .. "gauge_face.png", POWER .. "needle.png", POWER .. "lamp_green.png", POWER .. "wheel.png" })
check(B.tex("gauge_face.png") == POWER .. "gauge_face.png" and B.tex("knob.png") == nil and B.tex("tank_column.png") == nil,
    "Dazed Power only: its parts from its folder, Plumbing's answer nil")
local wm = B.build(snap(), opts())
check(texNamed(wm, POWER .. "gauge_face.png") and wm.needleOps.supply.op.k == "quad" and wm.needleOps.supply.op.name == POWER .. "needle.png",
    "Dazed Power's gauge face and needle")
check(count(wm, "quad") == 2 and texNamed(wm, PLUMB .. "tank_column.png") == nil, "no knob quad; the tank column is drawn")
-- both: Plumbing's copy wins
stubTextures({ PLUMB .. "wheel.png", POWER .. "wheel.png", POWER .. "hub.png" })
check(B.tex("wheel.png") == PLUMB .. "wheel.png" and B.tex("hub.png") == POWER .. "hub.png", "a part in both folders comes from Plumbing's")
stubTextures({})
check(B.tex("wheel.png") == nil, "neither folder: nil")
getTexture, B.resolver = nil, nil

-- seven fixtures scroll six at a time
local big = B.build(snap({ fixtures = fixtures(7) }), opts())
local bh = ids(big)
local area
for _, a in ipairs(big.scrolls) do if a.id == "fix" then area = a end end
check(area and area.max == 1 and area.off == 0 and bh["fix:down"] and bh["fix:up"], "more than six fixtures: scroll arrows")
check(bh["valve:6"] and bh["valve:7"] == nil, "six rows shown")
local scrolled = ids(B.build(snap({ fixtures = fixtures(7) }), opts({ fixScroll = 9 })))
check(scrolled["valve:7"] and scrolled["valve:1"] == nil, "scrolled to the end")
local srcs = {}
for i = 1, 11 do srcs[i] = { kind = "pump", state = "idle", lpm = 0, canOff = true } end
local sm = B.build(snap({ sources = srcs }), opts())
local sa
for _, a in ipairs(sm.scrolls) do if a.id == "src" then sa = a end end
check(sa and sa.max == 3 and ids(sm)["src:down"] and ids(sm)["src:off:9"] == nil, "a long sources list scrolls")

-- read only, shut, armed, not connected, own taps
local ro = ids(B.build(snap(), opts({ readOnly = true })))
check(ro.close and ro["rate:+"] == nil and ro["valve:1"] == nil and ro.shut == nil and ro.connect == nil and ro["src:off:1"] == nil,
    "a read-only board switches nothing")
local sh = B.build(snap({ shut = true, status = { paused = true, piped = true } }), opts({ shutArmed = true }))
check(texts(sh, "IGUI_DazedPlumb_BoardPaused") >= 1 and texts(sh, "IGUI_DazedPlumb_BoardConfirm") == 1, "shut reads PAUSED; armed asks for a second click")
local nc = ids(B.build(snap({ connected = false, fixtures = {}, sources = {}, tanks = {} }), opts()))
check(nc.connect and nc.close and nc["rate:+"] == nil and nc.shut == nil, "not connected: only Connect and close")
local own = fixtures(2)
own[2].ownTap, own[2].prio = true, nil
local oh = ids(B.build(snap({ fixtures = own }), opts()))
check(oh["valve:1"] and oh["valve:2"] == nil and oh["prio:down:1"] == nil, "a fixture with its own tap has no valve or arrows")
local wait = B.build(snap({ waiting = true, fixtures = {}, sources = {} }), opts())
check(texts(wait, "IGUI_DazedPlumb_BoardWaiting") == 2, "waiting for the first reply says so")

-- a wall panel's board: no CONNECT BUILDING; out of range says so; frozen shows its reason; watts when running
local nc2 = ids(B.build(snap(), opts({ noConnect = true })))
check(nc2.connect == nil and nc2.shut, "noConnect drops CONNECT BUILDING only")
local oor = B.build(snap({ outOfRange = true, fixtures = {}, sources = {} }), opts())
check(texts(oor, "IGUI_DazedPlumb_BoardOutOfRange") >= 1, "out of range is spelled out")
local fz = B.build(snap({ status = { frozen = true, piped = true } }), opts())
check(texts(fz, "IGUI_DazedPlumb_BoardReasonFrozen") == 1 and texts(fz, "IGUI_DazedPlumb_BoardPaused") >= 1, "frozen: PAUSED with the reason")
local wt = B.build(snap({ sources = { { kind = "pump", state = "running", lpm = 8, powered = true, watts = 400, canOff = true } } }), opts())
check(texts(wt, "400 W") == 1, "a running powered pump shows its watts")
local np = B.build(snap({ sources = { { kind = "pump", state = "nopower", lpm = 0, powered = false, watts = 400, canOff = true } } }), opts())
check(texts(np, "IGUI_DazedPlumb_PanelState_nopower") == 1, "an unpowered pump says no power")

-- scaling, dial range, formats
local s2 = B.build(snap(), opts({ S = 2 }))
check(s2.w == 2 * B.W and ids(s2).shut.w == 2 * h.shut.w, "the face scales with the font set")
check(B.dialFull(30) == 40 and B.dialFull(55) == 60 and B.dialFull(nil) == 40, "the dials read 0-40, or the line rate rounded up")
check(B.fmtL(7.26) == "7.3" and B.fmtL(12.6) == "13" and B.fmtL(3) == "3", "litres format")
check(B.kindKey("washing machine") == "IGUI_DazedPlumb_FixtureKind_washing_machine", "kind keys")
local lamps = B.lamps(snap({ status = { piped = true, dry = true, tainted = true } }))
check(not lamps[1].lit and lamps[2].lit and lamps[3].lit, "a dry tainted line: SUPPLY dark, TAINTED and DRY lit")

print(string.format("board_test: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
