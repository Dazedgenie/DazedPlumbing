-- The Main Water Panel's server side on a fake engine: the square codec, the priority fill, valves, the throttle,
-- shut-off and drain, the minute's figures and day roll-over, use detection, the pause-line switch, and every panel
-- command's checks (range, wall panel, unknown fixture, machine not on the line, rate limit) and mainInfo's shape.
-- Run: lua panel_test.lua <lua root> [<core root>]
local root = arg[1] or "../../common/media/lua"
local core = arg[2] or "../../../DazedCore/common/media/lua"
package.path = core .. "/shared/?.lua;" .. core .. "/client/?.lua;" .. root .. "/shared/?.lua;" .. root .. "/server/?.lua;" .. root .. "/client/?.lua;" .. package.path
local E = dofile("engine_stub.lua")
local print = E.realPrint
local fails, n = 0, 0
local function ok(c, msg) n = n + 1 if not c then fails = fails + 1 print("FAIL: " .. msg) end end
local function near(a, b, tol) return math.abs((a or 0) - (b or 0)) < (tol or 1e-4) end

-- One house, rooms 10..19 x 10..19 on z 0 and one room upstairs (as mains_test).
local function List(t) return { size = function() return #t end, get = function(_, i) return t[i + 1] end } end
local function Rect(x, y, w, h) return { getX = function() return x end, getY = function() return y end, getW = function() return w end, getH = function() return h end } end
local function Room(z, rects, def, name) return { getZ = function() return z end, getRects = function() return List(rects) end, isUserDefined = function() return false end, getBuilding = function() return def end, getName = function() return name end } end
local function Def(x, y, w, h)
    local d = { rooms = {} }
    d.getX = function() return x end d.getY = function() return y end d.getW = function() return w end d.getH = function() return h end
    d.getRooms = function() return List(d.rooms) end
    d.isUserDefined = function() return false end
    d.isBasement = function() return false end
    d.getMaxLevel = function() return 1 end
    return d
end
local house = Def(10, 10, 10, 10)
house.rooms = { Room(0, { Rect(10, 10, 10, 5) }, house, "kitchen"), Room(0, { Rect(10, 15, 10, 5) }, house, "bathroom"), Room(1, { Rect(10, 10, 10, 10) }, house, "bedroom") }
local defs = { house }
local function roomAt(x, y, z)
    for _, d in ipairs(defs) do
        for _, r in ipairs(d.rooms) do
            if r.getZ() == z then
                local rs = r.getRects()
                for i = 0, rs.size() - 1 do
                    local q = rs.get(nil, i)
                    if x >= q.getX() and x < q.getX() + q.getW() and y >= q.getY() and y < q.getY() + q.getH() then return r end
                end
            end
        end
    end
end
getWorld = function()
    return { getMetaGrid = function() return {
        getRoomAt = function(_, x, y, z) return roomAt(x, y, z) end,
        getBuildingsIntersecting = function(_, x, y, w, h, list)
            for _, d in ipairs(defs) do
                if d.getX() < x + w and d.getX() + d.getW() > x and d.getY() < y + h and d.getY() + d.getH() > y then list:add(d) end
            end
        end,
    } end }
end
ArrayList = { new = function() local t = {} return { add = function(_, v) t[#t + 1] = v end, size = function() return #t end, get = function(_, i) return t[i + 1] end } end }
Fluid = { Water = "W", TaintedWater = "TW", Petrol = "P" }
FluidType = Fluid
local clock = 0
getTimestampMs = function() clock = clock + 1000 return clock end

require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Sync"
require "DazedPlumbing/DUP_Net"
require "DazedPlumbing/DUP_Pipes"
require "DazedPlumbing/DUP_Links"
require "DazedPlumbing/DUP_Pumps"
require "DazedPlumbing/DUP_Purifiers"
require "DazedPlumbing/DUP_Fixtures"
require "DazedPlumbing/DUP_LinkActions"
require "DazedPlumbing/DUP_Mains"
require "DazedPlumbing/DUP_MainPanel"
local P, L, K, S, X, W, Pn, U = DazedPlumb.Parts, DazedPlumb.Links, DazedPlumb.Pipes, DazedPlumb.Sync, DazedPlumb.Fixtures,
    DazedPlumb.Mains, DazedPlumb.MainPanel, DazedPlumb.Pumps

E.grid(50, 50)
SandboxVars.WaterShutModifier = 0
SandboxVars.DazedPlumb = { MainReach = 6, MainFlow = 30 }

-- 1. the square codec
ok(W.encodeSquares({ "1,2,0", "-3,4,1", "1,2,0", "bad", 7 }) == "1,2,0;-3,4,1", "codec drops repeats and junk, keeps order")
local l, set = W.decodeSquares("1,2,0;-3,4,1")
ok(#l == 2 and l[1] == "1,2,0" and l[2] == "-3,4,1" and set["-3,4,1"], "codec round-trips")
local l2 = W.decodeSquares("x;;5,5,5;1,2;5,5,5;1,2,3,4")
ok(#l2 == 1 and l2[1] == "5,5,5", "a malformed string decodes to what is sound in it: " .. #l2)
ok(W.encodeSquares({}) == nil and #W.decodeSquares(nil) == 0, "empty is nil, nil is empty")
local many = {}
for i = 1, 100 do many[i] = i .. ",0,0" end
ok(#W.decodeSquares(W.encodeSquares(many)) == W.SQUARES_MAX, "the codec is bounded")

-- the house: three fixtures, a main at 22,15 piped to a 200 L tank at 24,15
local function fixture(x, y, z, cap)
    local f = E.object("fixtures_bathroom_01_0", E.square(x, y, z))
    f.getProperties = function() return { Is = function(_, k) return k == "waterPiped" end, Val = function() return nil end } end
    local fc = { amount = 0, cap = cap or 20, getAmount = function(s) return s.amount end, getCapacity = function(s) return s.cap end,
        addFluid = function(s, _, a) s.amount = s.amount + a end, setCapacity = function(s, c) s.cap = c end,
        Empty = function(s) s.amount = 0 end }
    f.getFluidContainer = function() return fc end
    f.fc = fc
    return f
end
local sink = fixture(12, 12, 0)
local bath = fixture(15, 17, 0, 100)
local upstairs = fixture(14, 14, 1)
local SINK, BATH, UP = "12,12,0", "15,17,0", "14,14,1"
local main = E.object(W.sprite("S"), E.square(22, 15, 0))
local player = E.character(21, 15, 0, 5)
local XYZ = { x = 22, y = 15, z = 0 }
local function args(t) local o = { x = 22, y = 15, z = 0 } for k, v in pairs(t or {}) do o[k] = v end return o end
W.send(player, "mainPick", { x = 22, y = 15, z = 0, sx = 12, sy = 12, sz = 0 })
local e = W.entry(main)
ok(e ~= nil, "connected")
local tank = E.object(P.sprite("small", "water", "crafted", "S", 1), E.square(24, 15, 0))
tank.md.dazedplumb = { amount = 150, condition = 100 }
E.give(player, K.ITEM, 40)
DUP_PipeSet:new(player, main, W.ID, tank):complete()
E.hours = 101
local function minute()
    W.beforeFlow()
    L.tick()
    W.afterFlow()
end
local function total() return sink.fc.amount + bath.fc.amount + upstairs.fc.amount end

-- 2. untouched: the same list and line rate as before the panel
ok(#W.ordered(main) == 3 and W.ordered(main) == W.fixtures(main), "no settings: the fill order is the scan order itself")
ok(W.rateOf(e) == 30 and L.adapters[W.ID].rate(main) == 30, "no settings: the line rate")
minute()
ok(near(total(), 30), "the first minute fills 30 L as before: " .. total())
ok(near(e.lpm, 30) and near(e.today, 30) and e.hist and near(e.hist[101 % 24 + 1], 30), "lpm, today and the hour's bar: " .. tostring(e.lpm))
local day0 = e.histDay

-- 3. priority: the bath to the top, throttled to 10 L: only the bath fills
sink.fc.amount, bath.fc.amount, upstairs.fc.amount = 0, 0, 0
W.send(player, "mainPrio", args({ fx = 15, fy = 17, fz = 0, dir = "top" }))
ok(W.squares(e.prio)[1] == BATH, "the bath leads the fill order: " .. tostring(e.prio))
W.send(player, "mainRate", args({ rate = 10 }))
ok(e.rate == 10 and W.room(main) == 10 and L.adapters[W.ID].rate(main) == 10, "the throttle caps room and rate")
E.hours = 101 + 1 / 60
minute()
ok(near(bath.fc.amount, 10) and sink.fc.amount == 0 and upstairs.fc.amount == 0, "a throttled minute goes to the first in line: " .. bath.fc.amount)
ok(near(e.lpm, 10) and near(e.today, 40), "the figures follow: " .. tostring(e.today))
-- moving down and up again
local order = Pn.order(main, e)
W.send(player, "mainPrio", args({ fx = 15, fy = 17, fz = 0, dir = "down" }))
local o2 = Pn.order(main, e)
ok(o2[2] == BATH and o2[1] == order[2], "down swaps with the next")
W.send(player, "mainPrio", args({ fx = 15, fy = 17, fz = 0, dir = "up" }))
ok(Pn.order(main, e)[1] == BATH, "up swaps back")
W.send(player, "mainPrio", args({ fx = 15, fy = 17, fz = 0, dir = "sideways" }))
ok(Pn.order(main, e)[1] == BATH, "an unknown direction changes nothing")

-- 4. valves: the bath closed, the water goes on to the next
W.send(player, "mainValve", args({ fx = 15, fy = 17, fz = 0, closed = true }))
ok(e.valves == BATH, "the bath's valve is closed")
local bathWas = bath.fc.amount
E.hours = 101 + 2 / 60
minute()
ok(bath.fc.amount == bathWas and near(sink.fc.amount + upstairs.fc.amount, 10), "a closed valve is skipped")
W.send(player, "mainValve", args({ fx = 15, fy = 17, fz = 0, closed = false }))
ok(e.valves == nil, "opened again, nothing stored")

-- 5. the throttle's ends
W.send(player, "mainRate", args({ rate = 999 }))
ok(e.rate == nil and W.rateOf(e) == 30, "the full line rate is the default: nothing stored")
W.send(player, "mainRate", args({ rate = -4 }))
ok(e.rate == 1, "the throttle never goes under 1 L/min")
W.send(player, "mainRate", args({ rate = "lots" }))
ok(e.rate == 1, "a rate that is not a number is ignored")
W.send(player, "mainRate", args({ rate = 30 }))

-- 6. use: a sink that lost 2 L since the last fill was used; a few drops are not
E.hours = 102
minute()                                        -- fills and records the levels
sink.fc.amount = sink.fc.amount - 2
upstairs.fc.amount = upstairs.fc.amount - 0.3
E.hours = 102 + 1 / 60
minute()
ok(e.used and e.used[SINK] == 102 and e.used[UP] ~= 102, "a 2 L drop marks the sink used at hour 102, 0.3 L does not")

-- 7. shut-off: no room, no rate, nothing moves, the line menu shows the pause too
local before = total()
local tankBefore = P.data(tank).amount
W.send(player, "mainShut", args({ shut = true }))
ok(e.shut == true and W.room(main) == 0 and L.adapters[W.ID].rate(main) == 0, "shut: no room and no rate")
ok(L.linkOf(main, W.ID).source == "manual", "shut pauses the line, so the line menu agrees")
sink.fc.amount = 0
E.hours = 102 + 2 / 60
minute()
ok(sink.fc.amount == 0 and near(P.data(tank).amount, tankBefore), "nothing flows while shut")
ok(Pn.info(main, e, "22,15,0").status.paused == true, "the PAUSED lamp is lit")
W.send(player, "mainShut", args({ shut = false }))
ok(e.shut == nil and L.linkOf(main, W.ID).source == "tank", "opened: both switches open")

-- 8. drain once: shut with drain set empties the fixtures one time
E.hours = 102 + 3 / 60
minute()
ok(total() > 0, "water in the house before the drain")
W.send(player, "mainDrain", args({ drain = true }))
ok(e.drain == true and not e.drained, "drain armed; nothing drained while open")
e.used = nil
W.send(player, "mainShut", args({ shut = true }))
ok(total() == 0 and e.drained == true, "shutting off drains every fed fixture at once")
sink.fc.amount = 5                              -- a bucket poured in by hand
E.hours = 102 + 4 / 60
minute()
ok(sink.fc.amount == 5, "the drain happens once per shut-off")
ok(e.used == nil, "the drain itself is not counted as use")
W.send(player, "mainShut", args({ shut = false }))
ok(e.drained == nil, "opening clears the drained mark")
W.send(player, "mainDrain", args({ drain = false }))

-- 9. the old pause-line action is the shut-off
DUP_LinkSource:new(player, main, W.ID, "manual"):complete()
ok(e.shut == true, "Use own water (pause) on the main's line shuts it")
DUP_LinkSource:new(player, main, W.ID, "tank"):complete()
ok(e.shut == nil, "resuming the line opens it")
-- an old save: the line paused, no shut field; the next minute marks it shut
L.linkOf(main, W.ID).source = "manual"
E.hours = 102 + 5 / 60
minute()
ok(e.shut == true, "a line paused before the panel reads as shut")
W.send(player, "mainShut", args({ shut = false }))

-- 10. the day rolls over: today and the chart start again
E.hours = 102 + 6 / 60
minute()
ok(e.histDay == day0 and (e.today or 0) > 0, "still the same day")
P.data(tank).amount = 200
E.hours = 125                                   -- the next morning
sink.fc.amount, bath.fc.amount, upstairs.fc.amount = sink.fc.cap, bath.fc.cap, upstairs.fc.cap
minute()
ok(e.histDay == day0 + 1 and e.today == nil and e.hist == nil and e.lpm == nil, "a new day clears today and the chart")
sink.fc.amount = 10
E.hours = 125 + 1 / 60
minute()
ok(near(e.today, 10) and near(e.hist[125 % 24 + 1], 10), "and counts again from zero: " .. tostring(e.today))

-- figures alone do not resend the mains table every minute: a full house moves nothing and sends nothing
sink.fc.amount, bath.fc.amount, upstairs.fc.amount = sink.fc.cap, bath.fc.cap, upstairs.fc.cap
E.hours = 125 + 2 / 60
minute()
local v0 = S.versionOf(W.TAG)
E.hours = 125 + 3 / 60
minute()
ok(S.versionOf(W.TAG) == v0, "an idle minute does not touch the synced table")
sink.fc.amount = 15
E.hours = 125 + 4 / 60                          -- minute 7504 is not a multiple of 5, but lpm going from nothing to something is sent
minute()
ok(S.versionOf(W.TAG) > v0, "water starting to flow is sent at once")

-- 11. status lamps
local st = W.status(main)
ok(st.piped and not st.dry and not st.tainted and not st.paused and not st.frozen, "a healthy main: piped, wet, clean, open")
ok(W.status(e).piped == true, "W.status takes the entry too")
P.data(tank).dirty = P.data(tank).amount
ok(W.status(main).tainted == true, "a tainted tank lights TAINTED")
P.data(tank).dirty = 0
local keep = P.data(tank).amount
P.data(tank).amount = 0
sink.fc.amount = 0
ok(W.status(main).dry == true and W.status(main).rationed == true, "a dry tank lights DRY and RATIONED")
P.data(tank).amount = keep
DazedClimate = { Plumbing = { enabled = function() return true end } }
P.data(tank).frozen = true
ok(W.status(main).frozen == true, "a frozen feeding tank lights FROZEN")
P.data(tank).frozen = nil
DazedClimate = nil

-- 12. command checks: range, a wall panel, unknown fixtures, machines off the line
local far = E.character(5, 40, 0, 5)
W.send(far, "mainRate", args({ rate = 7 }))
ok(e.rate == nil and far.notes[#far.notes] == "IGUI_DazedPlumb_PanelFar", "a far player is refused")
local panel = E.object("dazed_panel_test", E.square(6, 40, 0))
panel.md.dazedPanelMain = "22,15,0"
W.send(far, "mainRate", args({ rate = 7, via = { x = 6, y = 40, z = 0 } }))
ok(e.rate == 7, "a player beside a wall panel naming the main may work it")
panel.md.dazedPanelMain = "1,1,0"
W.send(far, "mainRate", args({ rate = 8, via = { x = 6, y = 40, z = 0 } }))
ok(e.rate == 7, "a panel naming another main does not count")
panel.md.dazedPanelMain = "22,15,0"
local farther = E.character(5, 46, 0, 5)
W.send(farther, "mainRate", args({ rate = 9, via = { x = 6, y = 40, z = 0 } }))
ok(e.rate == 7, "the panel must be within 2 squares of the player")
W.send(player, "mainRate", args({ rate = 30 }))
W.send(player, "mainValve", args({ fx = 30, fy = 30, fz = 0, closed = true }))
ok(e.valves == nil and player.notes[#player.notes] == "IGUI_DazedPlumb_PanelNoFixture", "an unknown fixture square is refused")
W.send(player, "mainRate", { x = 40, y = 40, z = 0, rate = 5 })
ok(player.notes[#player.notes] == "IGUI_DazedPlumb_MainGone", "no main at that square")
-- an electric pump piped to the tank is on the line; one standing alone is not
local pump = E.object(U.sprite("electric", "S"), E.square(26, 16, 0))
local loner = E.object(U.sprite("electric", "S"), E.square(30, 30, 0))
local hand = E.object(U.sprite("hand", "S"), E.square(26, 13, 0))
player.x, player.y = 25, 15
DUP_PipeSet:new(player, pump, U.ID, tank):complete()
DUP_PipeSet:new(player, hand, U.ID, tank):complete()
player.x, player.y = 21, 15
ok(L.linkOf(pump, U.ID) ~= nil and L.linkOf(hand, U.ID) ~= nil, "pumps piped to the tank")
W.send(player, "mainMachine", args({ mx = 30, my = 30, mz = 0, off = true }))
ok(loner.md.dazedOff == nil and player.notes[#player.notes] == "IGUI_DazedPlumb_PanelNoMachine", "a machine off the main's water is refused")
W.send(player, "mainMachine", args({ mx = 26, my = 16, mz = 0, off = true }))
ok(pump.md.dazedOff == true, "a pump on the line is switched off (DUP_PowerSwitch's field)")
W.send(player, "mainMachine", args({ mx = 26, my = 16, mz = 0, off = false, flow = 0.5 }))
ok(pump.md.dazedOff == nil and pump.md.dazedFlow == 0.5, "on again at half flow (DUP_SetFlow's field)")
W.send(player, "mainMachine", args({ mx = 26, my = 16, mz = 0, flow = 0.33 }))
ok(pump.md.dazedFlow == 0.5, "a flow that is not one of the settings is ignored")
W.send(player, "mainMachine", args({ mx = 26, my = 13, mz = 0, off = true }))
ok(hand.md.dazedOff == nil, "a hand pump has no switch")

-- 13. Core's rate limit: a second switch inside 250 ms is dropped
local frozen = clock
getTimestampMs = function() return frozen + 1000 end
W.send(player, "mainRate", args({ rate = 12 }))
W.send(player, "mainRate", args({ rate = 13 }))
ok(e.rate == 12, "a second command inside the rate limit is dropped: " .. tostring(e.rate))
clock = frozen + 1000
getTimestampMs = function() clock = clock + 1000 return clock end
W.send(player, "mainRate", args({ rate = 30 }))

-- 14. mainInfo's shape, through the core's reply
local got
DazedCore.Net.onClient("DazedPlumb", "mainInfo", function(a) got = a end)
W.send(player, "mainValve", args({ fx = 14, fy = 14, fz = 1, closed = true }))
W.send(player, "mainInfo", args())
ok(type(got) == "table" and got.key == "22,15,0" and got.flow == 30, "mainInfo answers the asking player")
ok(type(got.status) == "table" and got.status.supply ~= nil and got.status.demand ~= nil and got.status.paused == false, "status flags")
ok(got.building and got.building.kind == "building" and got.building.tiles > 0 and got.building.floors == 2, "building kind, tiles and floors")
ok(#got.tanks == 1 and got.tanks[1].feeding == true and got.tanks[1].cap == 200 and got.tanks[1].amount > 0, "the feeding tank with litres and capacity")
local kinds = {}
for _, s in ipairs(got.sources) do kinds[s.kind] = s end
ok(kinds.pump and kinds.pump.canOff and kinds.pump.canFlow and kinds.pump.flow == 0.5 and kinds.pump.watts and kinds.pump.state, "the electric pump's row")
ok(kinds.handpump and not kinds.handpump.canOff and kinds.handpump.state == "manual", "the hand pump's row")
ok(#got.fixtures == 3 and got.fixtureCount == 3, "every fixture listed")
local byKey = {}
for _, f in ipairs(got.fixtures) do byKey[f.x .. "," .. f.y .. "," .. f.z] = f end
ok(byKey[UP].closed == true and byKey[SINK].closed == false, "valve flags")
ok(byKey[BATH].prio == 1 and got.fixtures[1].x == 15, "fixtures come in fill order")
ok(byKey[SINK].room == "kitchen" and byKey[BATH].room == "bathroom" and byKey[UP].room == "bedroom", "room names from the map")
ok(byKey[BATH].cap == 20 and byKey[BATH].kind == "fixture" and byKey[SINK].ownTap == false, "capacity, kind and tap flags: " .. tostring(byKey[BATH].cap) .. " " .. tostring(byKey[BATH].kind) .. " " .. tostring(byKey[SINK].ownTap))
ok(byKey[SINK].used == 125, "the used hour")
ok(got.hist and #got.hist == 24 and got.today ~= nil, "today's figures ride along")
local far2 = E.character(5, 40, 0, 5)
got = nil
W.send(far2, "mainInfo", args())
ok(got == nil, "mainInfo is refused out of range")


-- 15. the board window on a stub UI: opens, reads the entry and the reply, draws, and sends commands for clicks
UIFont = { Small = 1, Medium = 2, Large = 3, Code = 4, CodeSmall = 5, CodeMedium = 6, CodeLarge = 7, NewSmall = 8 }
getTextManager = function() return { getFontHeight = function() return 16 end, MeasureStringX = function(_, _, s) return #s * 7 end } end
getTexture = function() return nil end
getPlayerScreenLeft, getPlayerScreenTop = function() return 0 end, function() return 0 end
local drawn = 0
package.preload["ISUI/ISPanel"] = function()
    ISPanel = { derive = function(self, name) local c = { name = name } c.__index = c setmetatable(c, { __index = self }) return c end,
        new = function(self, x, y, w, h) return setmetatable({ x = x, y = y, width = w, height = h }, self) end,
        initialise = function() end, addToUIManager = function() end, removeFromUIManager = function(self) self.removed = true end,
        update = function() end, onMouseDown = function() end, onMouseUp = function() end,
        drawRect = function() drawn = drawn + 1 end, drawText = function() drawn = drawn + 1 end, drawTextRight = function() drawn = drawn + 1 end,
        drawTextCentre = function() drawn = drawn + 1 end, drawLine = function() drawn = drawn + 1 end, drawTextureScaled = function() end,
        drawTextureAllPoint = function() end, isMouseOver = function() return false end, getAbsoluteX = function() return 0 end, getAbsoluteY = function() return 0 end }
    return ISPanel
end
package.preload["DazedCore/DC_Picker"] = function() DazedCore.Picker = DazedCore.Picker or { open = function(pl, part, spec) DazedCore.Picker.opened = spec end } return DazedCore.Picker end
require "DazedPlumbing/DUP_Board"
player.x, player.y = 21, 15
local win = DUP_Board.open(player, main)
ok(win and DazedPlumb.Board.current == win and win.mx == 22 and win.key == "22,15,0", "the board opens on the main")
ok(DazedPlumb.Board.info["22,15,0"] ~= nil, "opening asks for mainInfo (answered at once in single player)")
win:refresh()
win:prerender()
ok(drawn > 100 and win.snap.connected and #win.snap.fixtures == 3 and win.snap.fixtures[1].x == 15, "it reads and draws the main: " .. drawn)
local hitIds = {}
for _, hh in ipairs(win.model.hits) do hitIds[hh.id] = true end
ok(hitIds["rate:-"] and hitIds["valve:1"] and hitIds.shut, "its face has the controls")
local r0 = e.rate
win:onHit("rate:-")
ok(e.rate == 29, "rate:- sends mainRate one lower: " .. tostring(e.rate))
win:onHit("shut")
ok(not e.shut and win.shutArmedAt ~= nil, "the first click on the wheel only arms it")
win:onHit("shut")
ok(e.shut == true, "the second click within two seconds shuts the main")
win:refresh()
ok(win.snap.shut and win.snap.status.paused, "the board reads PAUSED from the entry")
win:onHit("shut") win:onHit("shut")
ok(not e.shut, "and opens it again")
W.send(player, "mainValve", args({ fx = 14, fy = 14, fz = 1, closed = false }))
win:refresh()
win:onHit("valve:2")
local second = win.snap.fixtures[2]
ok(W.squares(e.valves)[1] == second.x .. "," .. second.y .. "," .. second.z, "valve:2 closes the second row's fixture")
win:refresh()
ok(win.snap.fixtures[2].closed == true, "the row shows closed as soon as the entry has it")
win:onHit("prio:down:1")
win:refresh()
ok(win.snap.fixtures[2].x == 15, "prio:down:1 moves the first fixture down")
win:onHit("connect")
ok(DazedCore.Picker.opened == W.PICKER or W.PICKER == nil, "CONNECT BUILDING opens the picker")
win:onHit("src:off:1")
local srow = win.snap.sources[1]
local sobj = srow and E.square(srow.x, srow.y, srow.z).objs[1]
ok(sobj and (sobj.md.dazedOff == true or srow.canOff ~= true), "a source's toggle switches it")
local ro = DUP_Board.open(player, main, { readOnly = true })
ok(DazedPlumb.Board.current == ro and win.removed, "one board at a time")
ro:refresh() ro:prerender()
local rr = e.rate
ro:onHit("rate:+")
ok(e.rate == rr, "a read-only board sends nothing")
E.square(22, 15, 0):RemoveTileObject(main)
ro:update()
ok(ro.removed and DazedPlumb.Board.current == nil, "the board closes when the main is gone")
E.square(22, 15, 0):AddTileObject(main)

print(string.format("panel_test: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
