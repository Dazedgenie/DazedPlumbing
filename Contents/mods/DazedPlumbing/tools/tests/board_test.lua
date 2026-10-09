-- The Main Water Panel's face (DUP_BoardLayout) on a sample snapshot: its click regions, what greys out, scrolling,
-- scaling, the needles, and the drawn stand-ins when Dazed Power's textures are missing.
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
check(count(mt, "tex") > 10 and count(mt, "quad") == 2, "with textures: tex ops and two needle quads")
check(B.tex("wheel.png") == B.TEX .. "wheel.png", "Board.tex gives the full path")
local nq, same = B.needleQuad(206, 46, 170, 0.25, 1), true
for i = 1, 8 do if nq[i] ~= mt.needleOps.demand.op.pts[i] then same = false end end
check(same, "the quad needle matches needleQuad")
check(#mt.ops < #m.ops, "textures replace drawn stand-ins")
B.resolver = nil

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
