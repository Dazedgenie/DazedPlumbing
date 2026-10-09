-- The water main on a fake engine: connecting a house through the core's building resolver, reach and
-- one-main-per-house rules, feeding every fixture in the footprint up to the line rate through a real pipe
-- network, taps keeping their own fixtures, and housekeeping. Run: lua mains_test.lua <lua root> [<core root>]
local root = arg[1] or "../../common/media/lua"
local core = arg[2] or "../../../DazedCore/common/media/lua"
package.path = core .. "/shared/?.lua;" .. core .. "/client/?.lua;" .. root .. "/shared/?.lua;" .. root .. "/server/?.lua;" .. root .. "/client/?.lua;" .. package.path
local E = dofile("engine_stub.lua")
local print = E.realPrint
local fails, n = 0, 0
local function ok(c, msg) n = n + 1 if not c then fails = fails + 1 print("FAIL: " .. msg) end end
local function near(a, b, tol) return math.abs(a - b) < (tol or 1e-4) end

-- A metagrid with one house: rooms 10..19 x 10..19 on z 0 (two rooms), one room upstairs; and a shed at 40,10.
local function List(t) return { size = function() return #t end, get = function(_, i) return t[i + 1] end } end
local function Rect(x, y, w, h) return { getX = function() return x end, getY = function() return y end, getW = function() return w end, getH = function() return h end } end
local function Room(z, rects, def) return { getZ = function() return z end, getRects = function() return List(rects) end, isUserDefined = function() return false end, getBuilding = function() return def end } end
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
house.rooms = { Room(0, { Rect(10, 10, 10, 5) }, house), Room(0, { Rect(10, 15, 10, 5) }, house), Room(1, { Rect(10, 10, 10, 10) }, house) }
local shed = Def(40, 10, 4, 4)
shed.rooms = { Room(0, { Rect(40, 10, 4, 4) }, shed) }
local defs = { house, shed }
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
getTimestampMs = function() clock = clock + 1000 return clock end   -- each command a second after the last

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
local P, L, K, S, X, W = DazedPlumb.Parts, DazedPlumb.Links, DazedPlumb.Pipes, DazedPlumb.Sync, DazedPlumb.Fixtures, DazedPlumb.Mains

E.grid(50, 50)
SandboxVars.WaterShutModifier = 0            -- the town water is off
SandboxVars.DazedPlumb = { MainReach = 6, MainFlow = 30 }

local function fixture(x, y, z, cap)
    local f = E.object("fixtures_bathroom_01_0", E.square(x, y, z))
    f.getProperties = function() return { Is = function(_, k) return k == "waterPiped" end, Val = function() return nil end } end
    local fc = { amount = 0, cap = cap or 20, getAmount = function(s) return s.amount end, getCapacity = function(s) return s.cap end,
        addFluid = function(s, _, a) s.amount = s.amount + a end, setCapacity = function(s, c) s.cap = c end }
    f.getFluidContainer = function() return fc end
    f.fc = fc
    return f
end
local sink = fixture(12, 12, 0)                -- ground floor
local bath = fixture(15, 17, 0, 100)
local upstairs = fixture(14, 14, 1)
local shedSink = fixture(41, 11, 0)
local outside = fixture(30, 30, 0)             -- in the open: not the house's

-- the main at 22,15 (3 squares east of the house's east wall shell at x=20), piped to a tank at 24,15
local main = E.object(W.sprite("S"), E.square(22, 15, 0))
ok(W.isMain(main) and W.spriteInfo(W.sprite("N")).facing == "N", "the main's sprite is known")
ok(L.adapterFor(main) and L.adapterFor(main).id == W.ID, "the main is a link sink")
ok(W.reach() == 6 and W.flow() == 30, "sandbox values read")
ok(W.room(main) == 0, "unconnected: takes nothing")

local player = E.character(21, 15, 0, 5)
-- connect by a click inside the house, through the command path single player uses
W.send(player, "mainPick", { x = 22, y = 15, z = 0, sx = 12, sy = 12, sz = 0 })
local e = W.entry(main)
ok(e and e.k == "b" and e.id ~= nil, "a click in the house connects it: " .. tostring(player.notes[#player.notes]))
ok(player.notes[#player.notes] == "IGUI_DazedPlumb_MainConnected", "player told")
local list, total = W.fixtures(main)
ok(#list == 3 and total == 3, "three fixtures in the footprint, on both floors: " .. #list .. "/" .. total)
ok(near(W.room(main), 30), "room is the line rate when the house wants more (20+100+20)")

-- too far: a second main at 30,15 is 10 squares from the house
local far = E.object(W.sprite("S"), E.square(30, 15, 0))
local p2 = E.character(29, 15, 0, 5)
W.send(p2, "mainPick", { x = 30, y = 15, z = 0, sx = 12, sy = 12, sz = 0 })
ok(W.entry(far) == nil and p2.notes[#p2.notes] == "IGUI_DazedPlumb_MainFar", "a main out of reach is refused")
-- taken: a second main in reach cannot take the same house
local second = E.object(W.sprite("S"), E.square(21, 18, 0))
W.send(player, "mainPick", { x = 21, y = 18, z = 0, sx = 12, sy = 12, sz = 0 })
ok(W.entry(second) == nil and player.notes[#player.notes] == "IGUI_DazedPlumb_MainTaken", "a house takes one main")
ok(W.servedBy(e.id) == "22,15,0", "servedBy names the first main")
-- a player far from the main cannot work it
local p3 = E.character(5, 40, 0, 5)
W.send(p3, "mainClear", { x = 22, y = 15, z = 0 })
ok(W.entry(main) ~= nil and p3.notes[#p3.notes] == "IGUI_DazedPlumb_MainGone", "a far player is refused")

-- feed it: a water tank at 24,15 with 100 L, piped to the main
local tank = E.object(P.sprite("small", "water", "crafted", "S", 1), E.square(24, 15, 0))
tank.md.dazedplumb = { amount = 100, condition = 100 }
E.give(player, K.ITEM, 20)
DUP_PipeSet:new(player, main, W.ID, tank):complete()
ok(L.linkOf(main, W.ID) ~= nil, "pipe laid from the main to the tank")
E.hours = 101
L.tick()
local got = sink.fc.amount + bath.fc.amount + upstairs.fc.amount
ok(near(got, 30), "one minute moves the line rate into the house: " .. got)
ok(near(P.data(tank).amount, 70), "the tank paid for it: " .. P.data(tank).amount)
ok(shedSink.fc.amount == 0 and outside.fc.amount == 0, "the shed and the open sink get nothing")
ok(upstairs.fc.amount > 0, "upstairs is served too")

-- a tapped fixture inside the house keeps its tap: the main leaves it alone
local tapped = fixture(18, 18, 0)
L.attach(tapped, L.adapters[X.ID])
local tl = L.linkOf(tapped, X.ID)
tl.source, tl.tx, tl.ty, tl.tz = "tank", 24, 15, 0
E.hours = 101 + 1 / 60
local l1, t1 = W.fixtures(main)
ok(#l1 == 3 and t1 == 3, "a fixture added since the last look waits for the next one: " .. #l1 .. "/" .. t1)
E.hours = 101 + 10 / 60
local l2, t2 = W.fixtures(main)
ok(#l2 == 3 and t2 == 4, "the tapped sink is counted but not fed by the main: " .. #l2 .. "/" .. t2)
-- a fixture lifted between looks drops out at once
E.square(15, 17, 0):RemoveTileObject(bath)
E.hours = 101 + 11 / 60
local l3, t3 = W.fixtures(main)
ok(#l3 == 2 and t3 == 3, "a lifted bath leaves the list the next minute: " .. #l3 .. "/" .. t3)
E.square(15, 17, 0):AddTileObject(bath)

-- clicking the house again disconnects; clicking the shed from the main switches to it (it is 18 away: refused)
W.send(player, "mainPick", { x = 22, y = 15, z = 0, sx = 12, sy = 12, sz = 0 })
ok(W.entry(main) == nil and player.notes[#player.notes] == "IGUI_DazedPlumb_MainDisconnected", "second click disconnects")
W.send(player, "mainPick", { x = 22, y = 15, z = 0, sx = 41, sy = 11, sz = 0 })
ok(W.entry(main) == nil and player.notes[#player.notes] == "IGUI_DazedPlumb_MainFar", "the shed is out of this main's reach")
W.send(player, "mainPick", { x = 22, y = 15, z = 0, sx = 12, sy = 12, sz = 0 })
ok(W.entry(main) ~= nil, "reconnected")

-- a double click: the second pick inside half a second is dropped instead of toggling the house off again
local frozenClock = clock
getTimestampMs = function() return frozenClock + 1000 end
W.send(player, "mainPick", { x = 22, y = 15, z = 0, sx = 12, sy = 12, sz = 0 })
local afterFirst = W.entry(main) ~= nil
W.send(player, "mainPick", { x = 22, y = 15, z = 0, sx = 12, sy = 12, sz = 0 })
ok(afterFirst == (W.entry(main) ~= nil), "a second pick inside half a second is ignored")
clock = frozenClock + 1000
getTimestampMs = function() clock = clock + 1000 return clock end
if not afterFirst then W.send(player, "mainPick", { x = 22, y = 15, z = 0, sx = 12, sy = 12, sz = 0 }) end

-- lifting the main: its square is loaded and empty, so housekeeping forgets it
E.square(22, 15, 0):RemoveTileObject(main)
W.housekeep()
ok(W.store().mains["22,15,0"] == nil, "a lifted main is forgotten")
ok(W.store().mains["21,18,0"] == nil, "nothing else stored")

print(string.format("mains_test: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
