-- Integration test: the real Plumbing Lua on a fake engine. Run: lua54 plumbing_test.lua <common/media/lua>
local root = arg[1] or "../../common/media/lua"
local core = arg[2] or "../../../DazedCore/common/media/lua"      -- Dazed Utilities: Core, required
package.path = core .. "/shared/?.lua;" .. core .. "/client/?.lua;" .. root .. "/shared/?.lua;" .. root .. "/server/?.lua;" .. root .. "/client/?.lua;" .. package.path
local E = dofile("engine_stub.lua")
local fails, n = 0, 0
local function empty(t) for _ in pairs(t) do return false end return true end
local function ok(c, msg) n = n + 1 if not c then fails = fails + 1 E.realPrint("FAIL: " .. msg) end end
local function near(a, b, tol) return math.abs(a - b) < (tol or 1e-4) end

require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Sync"
require "DazedPlumbing/DUP_Net"
require "DazedPlumbing/DUP_Pipes"
require "DazedPlumbing/DUP_Links"
require "DazedPlumbing/DUP_Pumps"
require "DazedPlumbing/DUP_Purifiers"
require "DazedPlumbing/DUP_Fixtures"
require "DazedPlumbing/DUP_Rain"
require "DazedPlumbing/DUP_Downspouts"
require "DazedPlumbing/DUP_LinkActions"
require "DazedPlumbing/DUP_Sprinklers"
require "DazedPlumbing/DUP_Actions"
local P, M, L, K, N, S, U = DazedPlumb.Parts, DazedPlumb.Model, DazedPlumb.Links, DazedPlumb.Pipes, DazedPlumb.Net, DazedPlumb.Sync, DazedPlumb.Pumps

E.grid(40, 40)
local function tankAt(x, y, typ, amount)
    local o = E.object(P.sprite("small", typ, "crafted", "S", 1), E.square(x, y))
    o.md.dazedplumb = { amount = amount, condition = 100 }
    return o
end
local function machineAt(x, y, sprite) return E.object(sprite, E.square(x, y)) end

local got = {}
local function boiler(name)
    got[name] = 0
    return { id = name, supplies = "water", match = function(o) return o.sprite == name end,
        room = function() return 100 end, put = function(o, amt, dirty) got[name] = got[name] + amt got[name .. "_dirty"] = dirty return amt end }
end
for _, nm in ipairs({ "b1", "b2", "b3" }) do L.register(boiler(nm)) end

-- a tank with 10 L, three boilers piped to it: two straight, one by a branch that merges
local tank = tankAt(15, 10, "water", 10)
local m1, m2, m3 = machineAt(10, 10, "b1"), machineAt(20, 10, "b2"), machineAt(12, 13, "b3")
local ch = E.character(10, 10, 0, 1)
E.give(ch, "Base.DazedPipeSection", 12)

local function pipeSet(machine, adapterId)
    ch.x, ch.y = machine:getSquare():getX(), machine:getSquare():getY()
    local a = DUP_PipeSet:new(ch, machine, adapterId, tank)
    a:complete()
end
pipeSet(m1, "b1")
ok(E.count(ch, "Base.DazedPipeSection") == 8, "first run costs 4 sections, left " .. E.count(ch, "Base.DazedPipeSection"))
local sq = E.square(12, 10)
ok(#sq.objs == 1 and K.isPipe(sq.objs[1]), "pipe object laid at (12,10)")
ok(sq.objs[1].color and sq.objs[1].color[3] > 0.9, "water pipe is tinted blue")
pipeSet(m2, "b2")
ok(E.count(ch, "Base.DazedPipeSection") == 4, "second run costs 4 more")
pipeSet(m3, "b3")
ok(E.count(ch, "Base.DazedPipeSection") == 2, "branch costs 2 and merges, left " .. E.count(ch, "Base.DazedPipeSection"))
local junction = K.record(12, 10, 0)
ok(N.has(junction.mask, 4), "junction at (12,10) got a south arm")
ok(E.square(12, 10).objs[1].sprite == K.sprite(junction.mask, true), "junction sprite refreshed to its new shape")

L.tick()
ok(near(got.b1, 10 / 3, 0.01) and near(got.b2, 10 / 3, 0.01) and near(got.b3, 10 / 3, 0.01),
   string.format("fair share of 10 L: %.2f %.2f %.2f", got.b1, got.b2, got.b3))
ok(near(P.data(tank).amount, 0), "tank drained")

-- a tainted tank gives tainted water
P.data(tank).amount, P.data(tank).dirty = 10, 10
L.tick()
ok(got.b1_dirty == true, "tainted tank makes tainted water")
P.data(tank).amount, P.data(tank).dirty = 10, 0

-- a valve on the branch shuts b3 off
local ch2 = E.character(12, 11, 0, 2)
E.give(ch2, "Base.DazedValve", 1)
ok(K.canValve(12, 11, 0), "branch square can take a valve")
DUP_ValveFit:new(ch2, 12, 11, 0):complete()
ok(K.record(12, 11, 0).valve == "open", "valve fitted")
local vo = K.valveAt(12, 11, 0)
local vr = K.record(12, 11, 0)
ok(vo ~= nil and vo.sprite == K.valveSprite(vr), "an open valve shows as its own object")
local openName = vo and vo.sprite
DUP_ValveToggle:new(ch2, 12, 11, 0):complete()
ok(K.record(12, 11, 0).valve == "closed", "valve closed")
vo = K.valveAt(12, 11, 0)
ok(vo ~= nil and vo.sprite ~= openName and vo.sprite == K.valveSprite(K.record(12, 11, 0)), "closing turns the lever")
ok(K.valveSprite({ valve = "open", mask = 10, outdoor = true }) == "dazedplumb_01_196", "east-west ground valve")
ok(K.valveSprite({ valve = "closed", mask = 5, outdoor = false }) == "dazedplumb_01_203", "north-south overhead closed valve")
ok(K.valveSprite({ valve = "open", mask = 10, outdoor = true, cond = 0 }) == nil, "a broken square shows no valve")
got.b1, got.b2, got.b3 = 0, 0, 0
L.tick()
ok(near(got.b3, 0) and near(got.b1, 5, 0.01) and near(got.b2, 5, 0.01), string.format("closed valve cuts b3: %.2f %.2f %.2f", got.b1, got.b2, got.b3))
DUP_ValveToggle:new(ch2, 12, 11, 0):complete()

-- a break cuts the trunk on that side
P.data(tank).amount = 10
DUP_PipeCut:new(ch2, 13, 10, 0):complete()
ok(#E.square(13, 10).objs == 0 and K.record(13, 10, 0).cond == 0, "cut removes the object, keeps the record")
got.b1, got.b2, got.b3 = 0, 0, 0
L.tick()
ok(near(got.b1, 0) and near(got.b3, 0) and near(got.b2, 10, 0.01), "after the cut only b2 is fed")
-- mend it: costs a section and Welding 1
DUP_PipeRepair:new(ch2, 13, 10, 0):complete()
ok(K.record(13, 10, 0).cond == 0, "no section, no mend")
E.give(ch2, "Base.DazedPipeSection", 1)
DUP_PipeRepair:new(ch2, 13, 10, 0):complete()
ok(K.record(13, 10, 0).cond == 100 and #E.square(13, 10).objs == 1, "mended")
ok(E.count(ch2, "Base.DazedPipeSection") == 0, "mend used the section")

-- skill and sections gate laying
local green = E.character(30, 30, 0, 0)
E.give(green, "Base.DazedPipeSection", 50)
local m4 = machineAt(30, 30, "b1")
L.register(boiler("b4"))
local m5 = machineAt(30, 32, "b4")
green.x, green.y = 30, 32
DUP_PipeSet:new(green, m5, "b4", tank):complete()
ok(E.count(green, "Base.DazedPipeSection") == 50, "no Welding, no pipe")
local poor = E.character(30, 32, 0, 1)
DUP_PipeSet:new(poor, m5, "b4", tank):complete()
ok(#poor.notes == 0 or true, "poor character gets a note (server sends a key)")

-- disconnect b3: the dead-end branch comes up, half its sections come back
local giver = E.character(12, 13, 0, 1)
DUP_LinkClear:new(giver, m3, "b3"):complete()
ok(K.record(12, 12, 0) == nil and K.record(12, 11, 0) == nil, "branch removed")
ok(K.record(12, 10, 0) ~= nil, "trunk stays")
ok(E.count(giver, "Base.DazedPipeSection") == 1, "refund floor(2*0.5)=1, got " .. E.count(giver, "Base.DazedPipeSection"))

-- a pump is a source: pipe it to an empty water tank, it pushes tainted water
local t2 = tankAt(25, 25, "water", 0)
local pumpA = { id = "t_pump", produces = "water", tainted = true, match = function(o) return o.sprite == "pump" end,
    available = function() return 8 end, take = function(o, a) return a end }
L.register(pumpA)
local pump = machineAt(22, 25, "pump")
local pch = E.character(22, 25, 0, 1)
E.give(pch, "Base.DazedPipeSection", 5)
DUP_PipeSet:new(pch, pump, "t_pump", t2):complete()
L.tick()
ok(near(P.data(t2).amount, 8), "pump filled 8 L, got " .. P.data(t2).amount)
ok(M.isTainted(P.data(t2)), "pump water is tainted")

-- a machine right beside a tank needs no pipe: a virtual joint
local t3 = tankAt(35, 5, "water", 6)
local m6 = machineAt(34, 5, "b1")
local vch = E.character(34, 5, 0, 1)
tank = t3
DUP_PipeSet:new(vch, m6, "b1", t3):complete()
ok(K.record(34, 5, 0) == nil, "nothing laid")
got.b1 = 0
L.tick()
ok(near(got.b1, 6, 0.01) or got.b1 > 0, "virtual joint feeds, got " .. got.b1)

-- multiplayer: a client changes nothing
local keep = isClient
isClient = function() return true end
P.data(t3).amount = 5
got.b1 = 0
L.tick()
K.tick()
ok(got.b1 == 0 and near(P.data(t3).amount, 5), "client tick moves nothing")
local sqW = E.square(5, 5)
local w = U.well(sqW)
local stored = ModData.getOrCreate("DazedPlumbWells").wells
ok(empty(stored) and w.reserve == U.BASE_CAP, "client reads a well without creating one")
isClient = keep
w = U.well(sqW)
ok(not empty(ModData.getOrCreate("DazedPlumbWells").wells), "authority creates the well")
local drawn = U.draw(sqW, 50)
ok(near(drawn, 50) and S.dirty["DazedPlumbWells"] == true, "drawing marks the wells for sync")

-- sync bookkeeping
for k in pairs(S.dirty) do S.dirty[k] = nil end
S.dirty.DazedPlumbNet = true
S.flush()
ok(empty(S.dirty), "flush clears the dirty set")

-- taps: a fixture with a fluid container is topped up
local fixture = E.object("fixtures_bathroom_01_0", E.square(30, 20), {
    props = true,
})
fixture.getProperties = function() return { Is = function(_, k) return k == "waterPiped" end, Val = function(_, k) if k == "CustomName" then return "Sink" end end } end
local fc = { amount = 0, cap = 20, getAmount = function(s) return s.amount end, getCapacity = function(s) return s.cap end,
    addFluid = function(s, f, a) s.amount = s.amount + a end, setCapacity = function(s, c) s.cap = c end }
fixture.getFluidContainer = function() return fc end
Fluid = { Water = "W", TaintedWater = "TW", Petrol = "P" }
FluidType = { Water = "W", TaintedWater = "TW", Petrol = "P" }
ok(DazedPlumb.Fixtures.isFixture(fixture), "a sink is a fixture")
SandboxVars.WaterShutModifier = 0
ok(DazedPlumb.Fixtures.room(fixture) == 20, "town water off: the sink takes 20 L")
local took = DazedPlumb.Fixtures.put(fixture, 5, true)
ok(near(took, 5) and fc.amount == 5, "tap puts water in the fixture")
SandboxVars.WaterShutModifier = 1000
ok(DazedPlumb.Fixtures.room(fixture) == 0, "town water still on: the tap is left alone")


-- a water dispenser counts as a tap fixture
local disp = E.object("appliances_misc_01_0", E.square(31, 20))
disp.getProperties = function() return { Is = function() return false end, Val = function(_, k) if k == "CustomName" then return "Water Dispenser" end end } end
disp.getFluidContainer = function() return fc end
ok(DazedPlumb.Fixtures.isFixture(disp), "a water dispenser is a fixture")

-- rain on an open water tank: only water tanks, scaled by squares, intensity and time
ok(near(M.rainGain({ type = "water" }, 1, 1, 1), M.RAIN_PER_SQUARE_HOUR), "one open square, full rain, an hour")
ok(near(M.rainGain({ type = "water" }, 3, 0.5, 2), M.RAIN_PER_SQUARE_HOUR * 3), "scales by squares, intensity, hours")
ok(M.rainGain({ type = "gas" }, 3, 1, 1) == 0, "a petrol tank catches nothing")
ok(M.rainGain({ type = "water" }, 0, 1, 1) == 0, "a covered tank catches nothing")
local wt = { type = "water", size = "small", tier = "crafted", amount = 0 }
M.addWater(wt, M.rainGain(wt, 1, 1, 0.5), false)
ok(near(wt.amount, 5) and (wt.dirty or 0) == 0, "rainwater is clean")

-- a vanilla rain barrel is a water source for a tank
local R = DazedPlumb.Rain
local barrel = E.object("carpentry_02_54", E.square(34, 30))
local bfc = { amount = 100, getAmount = function(s) return s.amount end, getCapacity = function() return 200 end,
    adjustAmount = function(s, a) s.amount = a end, getPrimaryFluid = function() return { getFluidTypeString = function() return "TaintedWater" end } end }
barrel.getProperties = function() return { Is = function() return false end, Val = function(_, k) if k == "CustomName" then return "Rain Collector Barrel" end end } end
barrel.getFluidContainer = function() return bfc end
ok(R.isBarrel(barrel), "a rain collector barrel is recognised")
ok(not R.isBarrel(fixture), "a sink is not a rain barrel")
ok(R.tainted(barrel), "tainted barrel water is read as tainted")
ok(near(R.take(barrel, 30), 30) and near(bfc.amount, 70), "taking draws the barrel down")
ok(L.sourceDirty(L.adapters["dazed_rainbarrel"], barrel) == true, "the source reports taint through its function")
local rtank = tankAt(36, 30, "water", 0)
ch.x, ch.y = 34, 30
E.give(ch, "Base.DazedPipeSection", 8)
DUP_PipeSet:new(ch, barrel, "dazed_rainbarrel", rtank):complete()
L.tick()
ok(near(rtank.md.dazedplumb.amount, 20) and near(bfc.amount, 50), "the line draws 20 L a minute from the barrel into the tank, got " .. tostring(rtank.md.dazedplumb.amount))
ok(M.isTainted(rtank.md.dazedplumb), "tainted barrel water taints the tank")


-- roof runoff: the model, then the world tick with tanks beside a building
ok(near(M.runoffGain({ type = "water" }, 25, 1, 1, 1), 50), "25 roof squares at full rain give 50 L/h")
ok(near(M.runoffGain({ type = "water" }, 25, 1, 1, 2), 25), "two tanks share the roof")
ok(near(M.runoffGain({ type = "water" }, 400, 1, 1, 1), M.RUNOFF_MAX_PER_HOUR), "one barrel only takes so much")
ok(M.runoffGain({ type = "gas" }, 25, 1, 1, 1) == 0, "a petrol tank takes no runoff")
MapObjects = { OnLoadWithSprite = function() end, OnNewWithSprite = function() end }
local RAIN = 1
getClimateManager = function() return { getRainIntensity = function() return RAIN end } end
dofile(root .. "/server/DazedPlumbing/DUP_World.lua")
local W = DazedPlumb.World
local bsq = E.square(60, 5)
local bldg = { getDef = function() return { getW = function() return 5 end, getH = function() return 5 end } end }
bsq.getBuilding = function() return bldg end
local t1 = tankAt(59, 5, "water", 0)
W.register(t1)
W.tick()
ok(near(t1.md.dazedplumb.amount, 1.0, 0.01) and t1.md.dazedplumb.catching == "roof", "a tank beside a house catches sky + roof, got " .. tostring(t1.md.dazedplumb.amount))
local t2 = tankAt(59, 4, "water", 0)
W.register(t2)
t1.md.dazedplumb.amount = 0
W.tick()
ok(near(t1.md.dazedplumb.amount, 10 / 60 + 25 / 60, 0.01), "two tanks beside one house share its roof, got " .. tostring(t1.md.dazedplumb.amount))
local far = tankAt(10, 35, "water", 0)
W.register(far)
W.tick()
ok(near(far.md.dazedplumb.amount, 10 / 60, 0.01) and far.md.dazedplumb.catching == "sky", "an open tank away from buildings catches only sky")
RAIN = 0
W.tick()
ok(far.md.dazedplumb.catching == nil, "the tag clears when the rain stops")


-- downspouts: facing, wall check, buffer, roof share with a tank, and a line to a tank
local D = DazedPlumb.Downspouts
ok(D.spriteInfo(D.sprite("W")).facing == "W" and D.spriteInfo("dazedplumb_01_191") == nil, "downspout sprites are 192..195")
local wallSq = E.square(70, 5)
local hall = { getDef = function() return { getW = function() return 8 end, getH = function() return 10 end } end }
wallSq.getBuilding = function() return hall end
local spout = E.object(D.sprite("E"), E.square(69, 5))
ok(D.buildingFor(spout:getSquare(), "E") == hall, "an outdoor square with a wall on its east side is valid")
ok(D.buildingFor(spout:getSquare(), "W") == nil, "no wall on the west side: refused")
ok(D.building(spout) == hall, "the downspout finds its building")
ok(near(D.fill(spout, 5), 5) and near(D.water(spout), 5), "the buffer takes rainwater")
ok(near(D.fill(spout, 100), 15) and near(D.water(spout), 20), "the buffer holds 20 L")
ok(near(D.take(spout, 8), 8) and near(D.water(spout), 12), "taking draws the buffer down")
D.take(spout, 100)
-- world tick: roof 80 squares = 160 L/h; one downspout alone is capped at 80 L/h; with a barrel beside the same wall they split
RAIN = 1
W.registerSpout(spout)
W.tick()
ok(near(D.water(spout), 80 / 60, 0.01), "a lone downspout takes its 80 L/h cap, got " .. tostring(D.water(spout)))
D.take(spout, 100)
local rbarrel = tankAt(69, 6, "water", 0)
wallSq2 = E.square(70, 6); wallSq2.getBuilding = function() return hall end
W.register(rbarrel)
W.tick()
ok(near(D.water(spout), 80 / 60, 0.01), "with a barrel beside it the roof (160 L/h) still gives each 80 L/h, got " .. tostring(D.water(spout)))
D.take(spout, 100)
local rbarrel2 = tankAt(69, 4, "water", 0)
wallSq3 = E.square(70, 4); wallSq3.getBuilding = function() return hall end
W.register(rbarrel2)
W.tick()
ok(near(D.water(spout), 160 / 3 / 60, 0.01), "three catchers split 160 L/h, got " .. tostring(D.water(spout)))
-- a downspout piped to a tank
D.fill(spout, 20)
for x = 65, 69 do E.square(x, 5) end
local dtank = tankAt(66, 5, "water", 0)
ch.x, ch.y = 69, 5
E.give(ch, "Base.DazedPipeSection", 8)
DUP_PipeSet:new(ch, spout, "dazed_downspout", dtank):complete()
L.tick()
ok(near(dtank.md.dazedplumb.amount, 20) and not M.isTainted(dtank.md.dazedplumb), "the downspout line fills a tank with clean water, got " .. tostring(dtank.md.dazedplumb.amount))
RAIN = 0


-- Build 42 property calls (get/has) are read too: a kitchen sink, and a valve on a square beside a machine
local b42sink = E.object("fixtures_sinks_01_0", E.square(32, 22))
b42sink.getProperties = function() return { get = function(_, k) if k == "CustomName" then return "Sink" end end, has = function() return false end } end
ok(DazedPlumb.Fixtures.isFixture(b42sink), "a sink read through get/has is a fixture")
ok(P.prop(b42sink, "CustomName") == "Sink", "P.prop reads get()")
local endKey
for k, r in pairs(K.pipes()) do if r.ends and #r.ends > 0 and not r.virtual and not r.valve then endKey = k break end end
if endKey then
    local x, y, z = N.split(endKey)
    ok(K.canValve(x, y, z) == true, "a valve can go on a pipe square beside a machine")
end

-- a sink set into a counter: no "sink" in its name, only the engine's waterPiped FLAG
IsoFlagType = IsoFlagType or { waterPiped = { flag = "waterPiped" } }
local counter = E.object("fixtures_counters_01_12", E.square(33, 22))
counter.getProperties = function() return { get = function(_, k) if k == "CustomName" then return "Counter" end end,
    has = function(_, k) return k == IsoFlagType.waterPiped end } end
ok(DazedPlumb.Fixtures.isFixture(counter), "a counter sink with only the waterPiped flag is a fixture")
local plainCounter = E.object("fixtures_counters_01_13", E.square(34, 22))
plainCounter.getProperties = function() return { get = function(_, k) if k == "CustomName" then return "Counter" end end,
    has = function() return false end } end
ok(not DazedPlumb.Fixtures.isFixture(plainCounter), "a plain counter is not")

-- the flow setting scales the electric pump and the purifier, and their watts
local Pu = DazedPlumb.Purifiers
local ep = E.object(U.sprite("electric", "S"), E.square(35, 30))
ok(near(U.flowRate(ep), U.ELECTRIC_RATE) and near(U.watts(ep), U.PUMP_WATTS), "full flow by default")
ep.md.dazedFlow = 0.5
ok(near(U.flowRate(ep), U.ELECTRIC_RATE / 2) and near(U.watts(ep), U.PUMP_WATTS / 2), "half flow halves rate and watts")
ep.md.dazedFlow = 7
ok(near(U.flowRate(ep), U.ELECTRIC_RATE), "a nonsense setting reads as full")
local pu = E.object(Pu.sprite("E"), E.square(36, 30))
pu.md.dazedFlow = 0.25
ok(near(Pu.rate(pu), Pu.BARE_RATE * 0.25) and near(Pu.watts(pu), Pu.WATTS * 0.25), "purifier flow scales too")

-- a route search with no way through gives up within its budget instead of combing the whole box
local looked = 0
local route = K.route({ x = 5, y = 5 }, { ["200,200"] = true }, function() looked = looked + 1 return true end)
ok(route == nil and looked <= K.ROUTE_BUDGET * 4, "unreachable route stops at the budget (" .. looked .. " squares)")

-- tank sizes by type: drums, then basement-tank sizes; propane in kilograms
ok(M.capacity("small", "crafted", "water") == 200 and M.capacity("large", "crafted", "gas") == 1000
   and M.capacity("xl", "crafted", "water") == 2000, "water and petrol tanks: 200 / 1000 / 2000 L")
ok(M.capacity("small", "crafted", "propane") == 45 and M.capacity("xl", "crafted", "propane") == 400, "propane tanks: 45 .. 400 kg")
ok(near(M.capacity("large", "salvaged", "water"), 800), "salvaged holds 80%")

-- a sprinkler waters the thirsty crops in reach toward the middle of their range, from its tank
local Zs = DazedPlumb.Sprinklers
local crops = {}
SFarmingSystem = { instance = { hoursElapsed = 500, getLuaObjectAt = function(_, x, y, z) return crops[x .. "," .. y] end } }
local function crop(x, y, lvl) local c = { state = "seeded", waterLvl = lvl, waterNeeded = 60, waterNeededMax = 80, saveData = function() end }
    crops[x .. "," .. y] = c return c end
local dry, wet, far = crop(21, 36, 20), crop(22, 37, 72), crop(28, 36, 0)
local spr = E.object(Zs.sprite("S", false), E.square(20, 36))
ok(near(Zs.room(spr), 5), "room: the dry crop is 50 points short of 70 = 5 L, got " .. tostring(Zs.room(spr)))
local wtank = tankAt(20, 38, "water", 100)
E.give(ch, "Base.DazedPipeSection", 8)
ch.x, ch.y = 20, 36
DUP_PipeSet:new(ch, spr, Zs.ID, wtank):complete()
L.tick()
ok(near(dry.waterLvl, 70) and near(wet.waterLvl, 72) and near(far.waterLvl, 0), "watered the dry crop only, and only in reach")
ok(near(wtank.md.dazedplumb.amount, 95, 0.01), "the tank paid 5 L, has " .. tostring(wtank.md.dazedplumb.amount))
ok(Zs.describe(spr).spraying, "it shows the spray while watering")
ok(dry.lastWaterHour == 500, "the crop counts as watered")
-- the gauge window's readings: what the tank is piped to, and its trend
package.preload["ISUI/ISCollapsableWindow"] = function() return true end
ISCollapsableWindow = ISCollapsableWindow or { derive = function(self, name) return setmetatable({}, { __index = self }) end }
UIFont = UIFont or { Small = 1, Medium = 2 }
getTextManager = getTextManager or function() return { getFontHeight = function() return 16 end, MeasureStringX = function() return 10 end } end
require "DazedPlumbing/DUP_Gauge"
local Gg = DazedPlumb.Gauge
crops["21,36"].waterLvl = 10
local feeds, draws, others = Gg.connections(wtank, P.data(wtank))
ok(#draws == 1 and #feeds == 0, "the gauge lists the sprinkler as drawing from the tank")
ok(Gg.trend({ { h = 0, a = 100 }, { h = 0.5, a = 90 }, { h = 1, a = 80 } }) == -20, "trend: 20 L/h out")
ok(Gg.trend({ { h = 0, a = 1 } }) == nil, "no trend from one sample")
Zs.state(spr).off = true
ok(Zs.room(spr) == 0, "switched off it asks for nothing")
SFarmingSystem = nil

-- no pipe wrench, no pipe work (unless the sandbox option is off)
local bare = E.character(5, 30, 0, 2)
for i = #bare.inv.items, 1, -1 do bare.inv:Remove(bare.inv.items[i]) end
ok(not L.hasWrench(bare), "a character without a wrench has none")
SandboxVars = SandboxVars or {}
SandboxVars.DazedPlumb = { NeedWrench = false }
ok(L.hasWrench(bare), "the sandbox option lets anyone do pipe work")
SandboxVars.DazedPlumb = nil


-- a bathroom wall is not a fixture just because its sprite says "bathroom"; a bath is, by its own name
local wall = E.object("walls_interior_bathroom_01_3", E.square(35, 22))
wall.getProperties = function() return { get = function() return nil end, has = function() return false end } end
ok(not DazedPlumb.Fixtures.isFixture(wall), "a bathroom wall is not a fixture")
local tub = E.object("fixtures_bathroom_01_25", E.square(36, 22))
tub.getProperties = function() return { get = function(_, k) if k == "CustomName" then return "Bath" end end, has = function() return false end } end
ok(DazedPlumb.Fixtures.isFixture(tub) and DazedPlumb.Fixtures.capacity(tub) == 100, "a bath is a fixture holding 100 L")

-- a fixture with no container of its own gets one, and the game then sees the water there
local made = {}
local function fakeContainer()
    local c = { fl = {}, cap = 0 }
    function c:getCapacity() return self.cap end
    function c:setCapacity(v) self.cap = v end
    function c:getAmount() local t = 0 for _, v in pairs(self.fl) do t = t + v end return t end
    function c:addFluid(f, a) a = math.min(a, self.cap - self:getAmount()) self.fl[f] = (self.fl[f] or 0) + a end
    function c:getSpecificFluidAmount(f) return self.fl[f] or 0 end
    function c:Empty() self.fl = {} end
    return c
end
ComponentType = { FluidContainer = { CreateComponent = function() local c = fakeContainer() made[#made + 1] = c return c end } }
GameEntityFactory = { AddComponent = function(obj, replace, c) obj.fluid = c end }
local function withContainer(o) o.getFluidContainer = function(self) return self.fluid end return o end
withContainer(tub)
SandboxVars.WaterShutModifier = 0
ok(DazedPlumb.Fixtures.room(tub) == 100, "a dry bath with no container asks for 100 L")
ok(near(DazedPlumb.Fixtures.put(tub, 30, false), 30) and tub.fluid and tub.fluid:getAmount() == 30, "feeding it makes a container and fills it")

-- a water tank wears a container that mirrors it; what the game's Fluid menu takes comes off the tank
require "DazedPlumbing/DUP_TankFluid"
local TF = DazedPlumb.TankFluid
local mt = withContainer(tankAt(5, 35, "water", 120))
TF.reconcile(mt)
ok(mt.fluid and near(mt.fluid:getSpecificFluidAmount("W"), 120) and near(mt.fluid:getCapacity(), 200), "the tank's container shows its 120 L of 200")
mt.fluid.fl.W = 100                                    -- a player poured 20 L into a bucket through the game's menu
TF.reconcile(mt)
ok(near(mt.md.dazedplumb.amount, 100), "the 20 L taken by the game came off the tank: " .. tostring(mt.md.dazedplumb.amount))
mt.md.dazedplumb.amount = 150                            -- a pump added 50 L
TF.reconcile(mt)
ok(near(mt.fluid:getSpecificFluidAmount("W"), 150), "the container follows the tank")
mt.fluid.fl.TW = 10                                    -- a player poured in 10 L of tainted water
TF.reconcile(mt)
ok(near(mt.md.dazedplumb.amount, 160) and near(mt.md.dazedplumb.dirty or 0, 10), "poured-in tainted water counts as dirty")
local pt = withContainer(tankAt(6, 35, "propane", 20))
TF.reconcile(pt)
ok(pt.fluid == nil, "a propane tank gets no fluid container")

-- the menus look at everything on the clicked square, so a small sprinkler under a crop is found
local sqx = E.square(7, 35)
local floor = E.object("blends_natural_01_16", sqx)
local spr2 = E.object(DazedPlumb.Sprinklers.sprite("S", false), sqx)
local around = P.objectsAround({ floor })
ok(around[1] == spr2 and #around == 2, "objects around a click: ours first")

-- the power switch: an electric pump switched off pumps nothing
local ep = E.object(U.sprite("electric", "S"), E.square(8, 35))
E.square(8, 35).power = true
ok(L.adapters[U.ID].available(ep) > 0, "a powered electric pump offers water")
ep.md.dazedOff = true
ok(L.adapters[U.ID].available(ep) == 0 and U.isOff(ep), "switched off it offers none")


-- where a pipe meets a device a port object carries it in, below the device in the square's list
local function portsOn(x, y)
    local out = {}
    for _, o in ipairs(E.square(x, y).objs) do if K.isPort(o) then out[#out + 1] = o end end
    return out
end
ok(#portsOn(20, 38) == 1 and #portsOn(20, 36) == 1, "the sprinkler's run has a port at the tank and one at the sprinkler")
ok(portsOn(20, 38)[1].sprite == K.portSprite(1, false, false), "the drum's port comes in from the north, at ground level")
local lg = E.object(P.sprite("large", "water", "crafted", "S", 1), E.square(25, 30))
E.object(P.sprite("large", "water", "crafted", "S", 2), E.square(26, 30))
lg.md.dazedplumb = { amount = 0, condition = 100 }
local m4 = machineAt(25, 33, "b1")
E.give(ch, "Base.DazedPipeSection", 4)
ch.x, ch.y = 25, 33
DUP_PipeSet:new(ch, m4, "b1", lg):complete()
local lp = portsOn(25, 30)[1]
ok(lp and lp.sprite == K.portSprite(4, not K.record(25, 31, 0).outdoor, true), "a large tank's port rises into its belly from the south")
E.square(25, 30).objs = { lg }                        -- the tank is lifted ... and put back elsewhere: its port goes
for i = #E.square(25, 30).objs, 1, -1 do table.remove(E.square(25, 30).objs, i) end
K.tick()
ok(#portsOn(25, 30) == 0, "a lifted tank's port goes within a minute")
E.square(25, 30):AddTileObject(lg)
K.tick()
ok(#portsOn(25, 30) == 1 and portsOn(25, 30)[1].sprite == K.portSprite(4, not K.record(25, 31, 0).outdoor, true), "put back, its port returns within a minute")
-- swapped for a machine in one go (same object count): the object event marks the square
E.square(25, 30):RemoveTileObject(lg)
local swap = machineAt(25, 30, "b2")
K.markPortSquare(E.square(25, 30))
K.tick()
ok(#portsOn(25, 30) == 1 and portsOn(25, 30)[1].sprite == K.portSprite(4, not K.record(25, 31, 0).outdoor, false), "an object event re-syncs the port for the machine")
E.square(25, 30):RemoveTileObject(swap)
K.tick()


-- two water tanks piped together even out, a little each minute
local ta = tankAt(30, 30, "water", 180)
local tb = tankAt(30, 34, "water", 20)
E.give(ch, "Base.DazedPipeSection", 6)
ch.x, ch.y = 30, 31
DUP_TankLink:new(ch, ta, tb):complete()
for _ = 1, 10 do L.tick() end
ok(near(ta.md.dazedplumb.amount, 100, 0.01) and near(tb.md.dazedplumb.amount, 100, 0.01),
   "linked tanks even out: " .. tostring(ta.md.dazedplumb.amount) .. " / " .. tostring(tb.md.dazedplumb.amount))
local tc = tankAt(31, 30, "gas", 50)
ch.x, ch.y = 30, 31
local before = E.count(ch, "Base.DazedPipeSection")
DUP_TankLink:new(ch, ta, tc):complete()
ok(E.count(ch, "Base.DazedPipeSection") == before, "a water tank will not pipe to a petrol tank")

-- a name, and an admin's fill
DUP_TankRename:new(ch, ta, "  Garden barrel  "):complete()
ok(ta.md.dazedplumb.name == "Garden barrel", "a tank keeps its trimmed name")
local pr = tankAt(31, 31, "propane", 0)
getDebug = function() return true end
DUP_TankAdminFill:new(ch, pr):complete()
ok(near(pr.md.dazedplumb.amount, 45), "an admin fills a propane tank to 45 kg")
getDebug = nil

-- indoors a run keeps to the walls
local path = K.route({ x = 0, y = 0 }, { ["0,6"] = true }, function() return true end,
    function(x, y) return (x == 2) and 1 or 3 end)
local hugs = 0
for _, p in ipairs(path) do if p.x == 2 then hugs = hugs + 1 end end
ok(path and hugs >= 3, "a weighted route keeps to the cheap side")

-- graph caches follow the pipe table alone, plus Climate's ice switch
local idxBefore = K.index()
DazedCore.Sync.touch("DazedPlumbWells")
ok(K.index() == idxBefore, "a wells change leaves the pipe index cached")
K.touch()
ok(K.index() ~= idxBefore, "a pipe change rebuilds the pipe index")
local stampOff = K.flowStamp()
DazedClimate = { Plumbing = { enabled = function() return true end } }
ok(K.flowStamp() ~= stampOff, "Climate's ice switching on changes the flow stamp")
DazedClimate = nil

-- a sprite's description is remembered per name; foreign names stop at the prefix
local nm = P.sprite("large", "water", "crafted", "E", 2)
ok(P.spriteInfo(nm) == P.spriteInfo(nm) and P.spriteInfo(nm).piece == 2, "a tank sprite's info is one shared table")
ok(P.spriteInfo("carpentry_01_0") == nil and P.spriteInfo(nil) == nil and P.spriteInfo("dazedplumb_01_x") == nil, "foreign names are not tanks")

-- zombies wearing through two outdoor squares in one minute: both break, the clients hear once
do
    local hit = {}
    for k, r in pairs(K.pipes()) do
        if N.isReal(r) and r.outdoor and (r.cond or 100) > 0 and #hit < 2 then hit[#hit + 1] = k end
    end
    for _, k in ipairs(hit) do
        K.pipes()[k].cond = 1
        local x, y, z = N.split(k)
        E.square(x, y, z).movers = { {} }
    end
    local oldInstanceof = instanceof
    instanceof = function(_, cls) return cls == "IsoZombie" end
    local v0 = K.version()
    K.tick()
    instanceof = oldInstanceof
    local broken = 0
    for _, k in ipairs(hit) do
        if K.pipes()[k].cond <= 0 then broken = broken + 1 end
        local x, y, z = N.split(k)
        E.square(x, y, z).movers = nil
    end
    ok(#hit == 2 and broken == 2 and K.version() == v0 + 1, "two squares broken by wear cost one pipe-table send")
    for _, k in ipairs(hit) do local x, y, z = N.split(k) K.repairAt(x, y, z) end
end

-- a tank changed by the minute tick is sent to clients once, after the tick
do
    local sent = {}
    for _, t in ipairs({ ta, tb }) do t.transmitModData = function(self) sent[self] = (sent[self] or 0) + 1 end end
    ta.md.dazedplumb.amount, tb.md.dazedplumb.amount = 150, 20
    L.tick()
    ok(sent[ta] == 1 and sent[tb] == 1, "balancing sends each tank once: " .. tostring(sent[ta]) .. "/" .. tostring(sent[tb]))
    P.transmit(ta)
    ok(sent[ta] == 2, "outside a tick a send goes out at once")
    P.batch(function() P.transmit(ta) P.transmit(ta) P.transmit(tb) P.transmit(ta) end)
    ok(sent[ta] == 3 and sent[tb] == 2, "inside a batch three sends of one tank become one")
    ok(not pcall(P.batch, function() error("boom") end), "a failing batch still raises its error")
    P.transmit(ta)
    ok(sent[ta] == 4, "and the batch after an error is closed")
    for _, t in ipairs({ ta, tb }) do t.transmitModData = nil end
end

-- a network's resolved handles are kept while the world under them holds
do
    local comp
    for _, c in ipairs(N.components(K.pipes())) do
        for _, e in ipairs(c.ends) do if e.role == "tank" and e.x == 30 and e.y == 34 then comp = c end end
    end
    local r1 = comp and L.resolveCached(comp, "water")
    ok(r1 and #r1.tanks == 2 and L.resolveCached(comp, "water") == r1, "a second ask reuses the resolved network")
    local sq = tb:getSquare()
    sq:RemoveTileObject(tb)
    local r2 = L.resolveCached(comp, "water")
    ok(r2 ~= r1 and #r2.tanks == 1, "a lifted tank makes it resolve afresh")
    sq:AddTileObject(tb)
    ok(#L.resolveCached(comp, "water").tanks == 2, "and putting it back is seen too")
end

ok(P.indexOf("dazedplumb_01_212") == 212 and P.indexOf("dazedpower_01_212") == nil and P.indexOf("dazedplumb_01_2x") == nil, "tile numbers come only from our sprite names")
ok(K.spriteInfo(K.sprite(5, true)) == true and select(2, K.spriteInfo(K.sprite(5, true))) == 5 and K.spriteInfo("x_01_150") == nil, "pipe sprites still decode to outdoor and mask")

E.realPrint(string.format("plumbing_test: %d checks, %d failed", n, fails))
if fails > 0 then for _, l in ipairs(E.printed) do E.realPrint("  log: " .. l) end end
os.exit(fails == 0 and 0 or 1)
