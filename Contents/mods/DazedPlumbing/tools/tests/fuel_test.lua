-- The fuel pump on a fake engine: model maths, vehicle and can filling, power, placement and the sprite/item counts.
-- Run: lua fuel_test.lua <common/media/lua> [<core lua root>]
local root = arg[1] or "../../common/media/lua"
local core = arg[2] or "../../../DazedCore/common/media/lua"      -- Dazed Utilities: Core, required
package.path = core .. "/shared/?.lua;" .. core .. "/client/?.lua;" .. root .. "/shared/?.lua;" .. root .. "/server/?.lua;" .. root .. "/client/?.lua;" .. package.path
local E = dofile("engine_stub.lua")
local fails, n = 0, 0
local function ok(c, msg) n = n + 1 if not c then fails = fails + 1 E.realPrint("FAIL: " .. msg) end end
local function near(a, b, tol) return math.abs(a - b) < (tol or 1e-4) end
local function slurp(path) local f = assert(io.open(path, "rb")) local s = f:read("*a") f:close() return s end
local media = root .. "/.."

require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Sync"
require "DazedPlumbing/DUP_Net"
require "DazedPlumbing/DUP_Pipes"
require "DazedPlumbing/DUP_Links"
require "DazedPlumbing/DUP_LinkActions"
require "DazedPlumbing/DUP_Pumps"
require "DazedPlumbing/DUP_Purifiers"
require "DazedPlumbing/DUP_Fluids"
require "DazedPlumbing/DUP_FuelPumps"
require "DazedPlumbing/DUP_FuelActions"
require "DazedPlumbing/DUP_PumpActions"
require "DazedPlumbing/DUP_Power"
local P, M, L, K, Fp, F = DazedPlumb.Parts, DazedPlumb.Model, DazedPlumb.Links, DazedPlumb.Pipes, DazedPlumb.FuelPumps, DazedPlumb.Fluids
local W = DazedCore.Power

E.grid(40, 40)
Fluid = { Water = "W", TaintedWater = "TW", Petrol = "P" }
FluidType = { Water = "W", TaintedWater = "TW", Petrol = "P" }

------------------------------------------------------------------ sprites, items and the files agree
ok(Fp.BASE == 236 and Fp.COUNT == 8, "fuel pump sprites are appended at 236..243")
ok(Fp.sprite("hand", "S") == "dazedplumb_01_237" and Fp.sprite("electric", "S") == "dazedplumb_01_241", "south sprites 237 and 241")
ok(Fp.sprite("electric", "N") == "dazedplumb_01_243" and Fp.sprite("hand", "E") == "dazedplumb_01_236", "east and north ends of the block")
local seen = {}
for _, kind in ipairs(Fp.KINDS) do
    for _, f in ipairs(Fp.FACINGS) do
        local info = Fp.spriteInfo(Fp.sprite(kind, f))
        ok(info and info.kind == kind and info.facing == f, "round trip " .. kind .. " " .. f)
        seen[Fp.sprite(kind, f)] = true
    end
end
local count = 0 for _ in pairs(seen) do count = count + 1 end
ok(count == 8, "eight distinct fuel pump sprites")
ok(Fp.spriteInfo("dazedplumb_01_235") == nil and Fp.spriteInfo("dazedplumb_01_244") == nil, "neighbouring tiles are not fuel pumps")
ok(DazedPlumb.Mains.spriteInfo("dazedplumb_01_236") == nil and DazedPlumb.Pumps.spriteInfo("dazedplumb_01_236") == nil, "no overlap with water pumps or the main")

-- the whole taxonomy as the boot check counts it: 256 sprites, 33 items, all present
require "DazedPlumbing/DUP_Boot"
local itemsTxt = slurp(media .. "/scripts/dup_items.txt")
local defined = {}
for name in itemsTxt:gmatch("\n%s+item%s+(%w+)") do defined[name] = true end
local itemCount = 0 for _ in pairs(defined) do itemCount = itemCount + 1 end
ok(itemCount == 33, "33 items in dup_items.txt, found " .. itemCount)
getScriptManager = function() return { getItem = function(_, ft) return defined[ft:match("%.(.+)$")] and {} or nil end } end
getSprite = function(name) local i = tonumber(name:match("_(%d+)$")) return (i and i < 260) and {} or nil end
for _, h in ipairs(Events.OnGameStart.handlers) do h() end
local boot
for _, line in ipairs(E.printed) do if line:find("DazedPlumbing: ready") or line:find("INCOMPLETE") then boot = line end end
ok(boot and boot:find("256/256 tiles, 33/33 items", 1, true), "boot check: " .. tostring(boot))
ok(DazedPlumb.VERSION == "0.17.0", "version constant is 0.17.0")
ok(slurp(media .. "/../../42/mod.info"):find("modversion=0.17.0", 1, true) ~= nil, "mod.info says 0.17.0")
for _, it in ipairs(Fp.allItems()) do ok(defined[it:match("%.(.+)$")], it .. " is defined") end

-- tiles 236..243 name their item; each item points at its south tile; weights stay under the heavy limit
local tilesTxt = slurp(media .. "/dazedplumbing_tiles.tiles.txt")
local function weight(name) return tonumber(itemsTxt:match("item " .. name .. "%s*{.-Weight%s*=%s*([%d%.]+)")) end
for _, kind in ipairs(Fp.KINDS) do
    local w = weight(kind == "hand" and "DazedFuelPumpHand" or "DazedFuelPumpElectric")
    ok(w and w < DazedCore.Heavy.LIMIT and DazedCore.Heavy.count(w) == 1, kind .. " fuel pump is one piece, " .. tostring(w) .. " kg")
    ok(itemsTxt:find("WorldObjectSprite   = " .. Fp.sprite(kind, "S"), 1, true), kind .. " item points at its south tile")
end
ok(tilesTxt:find("Hand Fuel Pump", 1, true) and tilesTxt:find("Electric Fuel Pump", 1, true), "tile definitions name both pumps")
local _, hits = tilesTxt:gsub("Base%.DazedFuelPump%a+", "")
ok(hits == 8, "eight tiles carry a fuel pump item, found " .. hits)
local recipes = slurp(media .. "/scripts/dup_recipes.txt")
ok(recipes:find("craftRecipe MakeDazedFuelPumpHand", 1, true) and recipes:find("craftRecipe MakeDazedFuelPumpElectric", 1, true), "both recipes exist")
ok(recipes:match("MakeDazedFuelPumpElectric.-Base%.DazedFuelPumpHand%] mode:destroy") ~= nil, "the electric build consumes a hand fuel pump")
local hs = tonumber(recipes:match("MakeDazedFuelPumpHand.-MetalWelding:(%d)"))
local es = tonumber(recipes:match("MakeDazedFuelPumpElectric.-Electricity:(%d)"))
ok(hs and es and es > hs, "the hand pump is the easier build")
for _, f in ipairs({ "ItemName", "Recipes", "Tooltip", "ContextMenu", "IG_UI", "Moveables" }) do
    local t = slurp(root .. "/shared/Translate/EN/" .. f .. ".json")
    ok(t:find("Fuel", 1, true) ~= nil, "EN " .. f .. ".json has fuel pump text")
end
ok(slurp(root .. "/shared/Translate/EN/Tooltip.json"):find("Tooltip_DazedFuelPumpElectric", 1, true), "tooltip text for the electric pump")

-- every Lua file this feature touches compiles
for _, f in ipairs({ "shared/DazedPlumbing/DUP_FuelPumps.lua", "shared/DazedPlumbing/DUP_FuelActions.lua", "client/DazedPlumbing/DUP_FuelMenu.lua",
                     "shared/DazedPlumbing/DUP_Power.lua", "shared/DazedPlumbing/DUP_Place.lua", "shared/DazedPlumbing/DUP_Boot.lua" }) do
    ok(loadfile(root .. "/" .. f) ~= nil, f .. " compiles")
end

------------------------------------------------------------------ the model maths
ok(Fp.rate("electric") == 10 and Fp.rate("hand") < Fp.rate("electric") / 3, "electric ~10 L/min, hand much slower")
ok(Fp.WATTS == 200, "electric pump is a 200 W load")
ok(near(Fp.litres("hand", 10, 100, 50), Fp.CHUNK.hand), "a hand action moves one chunk")
ok(near(Fp.litres("electric", 25, 100, 50), Fp.CHUNK.electric), "an electric action moves one chunk (10 L)")
ok(near(Fp.litres("electric", 4, 100, 50), 4), "a smaller request is honoured")
ok(near(Fp.litres("electric", 10, 3, 50), 3), "limited by what the tank holds")
ok(near(Fp.litres("electric", 10, 100, 0.5), 0.5), "limited by the room in the target")
ok(Fp.litres("electric", 10, 0, 50) == 0 and Fp.litres("electric", 10, 100, 0) == 0, "an empty tank or a full target moves nothing")
ok(near(Fp.minutes("electric", 10), 1) and near(Fp.minutes("hand", 2), 1), "a chunk is a minute of pumping")
ok(Fp.ticks("hand", Fp.CHUNK.hand) == Fp.ticks("electric", Fp.CHUNK.electric), "both chunks take the same time")
ok(Fp.ticks("hand", 10) == 5 * Fp.ticks("electric", 10), "10 L by hand takes five times as long as by motor")
ok(Fp.chunksFor("electric", 60) == 6 and Fp.chunksFor("hand", 60) == 30 and Fp.chunksFor("electric", 0.2) == 1, "chunks needed for a car")

------------------------------------------------------------------ a pump piped to a petrol tank
local function tankAt(x, y, typ, amount)
    local o = E.object(P.sprite("small", typ, "crafted", "S", 1), E.square(x, y))
    o.md.dazedplumb = { amount = amount, condition = 100 }
    return o
end
local function pumpAt(x, y, kind, extra)
    local o = E.object(Fp.sprite(kind, "S"), E.square(x, y), extra)
    return o
end
local function pipe(pump, tank)
    local ch = E.character(pump:getSquare():getX(), pump:getSquare():getY(), 0, 1)
    E.give(ch, "Base.DazedPipeSection", 12)
    DUP_PipeSet:new(ch, pump, Fp.ID, tank):complete()
    return ch
end

local adapter = L.adapters[Fp.ID]
ok(adapter and adapter.supplies == "gas" and adapter.room() == 0, "the pump is a gas sink that holds nothing")
ok(L.adapterFor(pumpAt(5, 5, "hand")) == adapter, "a fuel pump is found by its sprite")

local gas = tankAt(15, 10, "gas", 100)
local water = tankAt(15, 14, "water", 100)
local hand = pumpAt(10, 10, "hand")
ok(Fp.line(hand).state == "unpiped", "a new pump is not piped")
local chH = pipe(hand, gas)
local line = Fp.line(hand)
ok(line.state == "ok" and #line.tanks == 1 and near(line.litres, 100), "piped to the petrol tank: 100 L on the line")
ok(L.adapterFor(water) == nil and Fp.line(pumpAt(10, 14, "hand")).litres == 0, "a water tank is not a fuel source")

-- a vehicle stub
local function vehicle(squares, amount, cap, extra)
    local part = { amount = amount, cap = cap }
    function part:getContainerContentAmount() return self.amount end
    function part:getContainerCapacity() return self.cap end
    function part:setContainerContentAmount(a) self.amount = math.min(a, self.cap) end
    local v = { part = part, sent = 0, running = false, speed = 0 }
    function v:getPartById(id) if id == "GasTank" and not self.noTank then return self.part end end
    function v:isEngineRunning() return self.running end
    function v:getCurrentSpeedKmHour() return self.speed end
    function v:transmitPartModData() self.sent = self.sent + 1 end
    for k, val in pairs(extra or {}) do v[k] = val end
    for _, sq in ipairs(squares) do sq.getVehicleContainer = function() return v end end
    return v
end

local car = vehicle({ E.square(11, 11), E.square(12, 11) }, 20, 65)
ok(#Fp.vehiclesNear(hand) == 1 and Fp.vehiclesNear(hand)[1] == car, "a car two squares away is in reach once, not twice")
ok(Fp.inReach(hand, car), "the car is in reach")
local t = Fp.tankOf(car)
ok(t and t.amount == 20 and t.capacity == 65 and t.room == 45, "the car's GasTank reads 20 of 65 L")

-- hand pump: one action moves a hand chunk
local moved, why = Fp.refuel(hand, car, 10)
ok(near(moved, Fp.CHUNK.hand) and near(car.part.amount, 20 + Fp.CHUNK.hand), "hand pump put " .. tostring(moved) .. " L into the car")
ok(near(P.data(gas).amount, 100 - Fp.CHUNK.hand), "and took the same from the petrol tank")
ok(car.sent >= 1, "the vehicle's part was transmitted")

-- the timed action does the same on the authority
local before = car.part.amount
local act = DUP_FuelVehicle:new(chH, hand, car, 2)
ok(act:isValid() and act.maxTime == 1, "the refuel action is valid (instant in the stub)")
act:complete()
ok(near(car.part.amount, before + 2) and near(P.data(gas).amount, 100 - 4), "complete() moved 2 L from tank to car")

-- far away or running: refused
local farCar = vehicle({ E.square(20, 20) }, 10, 60)
local m2, w2 = Fp.refuel(hand, farCar, 10)
ok(m2 == 0 and w2 == "far", "a vehicle out of reach is refused")
car.running = true
local m3, w3 = Fp.refuel(hand, car, 10)
ok(m3 == 0 and w3 == "running", "a running engine is refused")
car.running = false
car.speed = 5
ok(select(2, Fp.refuel(hand, car, 10)) == "running", "a rolling vehicle is refused")
car.speed = 0
local noTank = vehicle({ E.square(9, 9) }, 0, 0, { noTank = true })
ok(select(2, Fp.refuel(hand, noTank, 10)) == "novehicle", "a vehicle without a GasTank is refused")

-- limited by the vehicle's capacity
local nearlyFull = vehicle({ E.square(8, 10) }, 64.5, 65)
local m4 = Fp.refuel(hand, nearlyFull, 10)
ok(near(m4, 0.5) and near(nearlyFull.part.amount, 65), "stops at the tank's capacity")
ok(select(2, Fp.refuel(hand, nearlyFull, 10)) == "full", "a full vehicle is refused")

-- limited by the petrol in the tank
local small = tankAt(15, 20, "gas", 3)
local hand2 = pumpAt(10, 20, "hand")
pipe(hand2, small)
local bigCar = vehicle({ E.square(10, 21) }, 0, 100)
local el1 = 0
for _ = 1, 5 do el1 = el1 + Fp.refuel(hand2, bigCar, 10) end
ok(near(el1, 3) and near(bigCar.part.amount, 3) and near(P.data(small).amount, 0), "a 3 L tank gives 3 L and no more")
ok(select(2, Fp.refuel(hand2, bigCar, 10)) == "empty", "an empty tank is reported")
ok(Fp.line(hand2).litres == 0, "the line shows 0 L")

------------------------------------------------------------------ the electric pump
W.registerProvider({ id = "test_wire", isPowered = function(o) if o.wire == nil then return nil end return o.wire == true end })
local gas2 = tankAt(25, 10, "gas", 200)
local elec = pumpAt(20, 10, "electric")
elec:getSquare().power = true                              -- the grid is on; it must not count
local chE = pipe(elec, gas2)
local car2 = vehicle({ E.square(21, 11) }, 0, 65)
local me, we = Fp.refuel(elec, car2, 10)
ok(me == 0 and we == "nopower" and near(P.data(gas2).amount, 200), "unwired, an electric pump refuses even on a powered square")
elec.wire = false
ok(select(2, Fp.refuel(elec, car2, 10)) == "nopower", "wired to an unpowered controller it still refuses")
elec.wire = true
me = Fp.refuel(elec, car2, 25)
ok(near(me, Fp.CHUNK.electric) and near(car2.part.amount, 10) and near(P.data(gas2).amount, 190), "wired and powered it moves 10 L in one action")
ok(near(me, 5 * Fp.CHUNK.hand), "that is five hand chunks")
elec:getModData().dazedOff = true
ok(select(2, Fp.refuel(elec, car2, 10)) == "off", "switched off it refuses")
elec:getModData().dazedOff = nil
-- the switch action
DUP_PowerSwitch:new(chE, elec, false):complete()
ok(elec:getModData().dazedOff == true, "the power switch works on a fuel pump")
DUP_PowerSwitch:new(chE, elec, true):complete()
ok(elec:getModData().dazedOff == nil, "and switches it back on")

-- billed as a Dazed Power load only while it moves fuel
local load = W.loadOf(elec)
ok(load and load.kind == "fuelpump" and load.items[1] == "Base.DazedFuelPumpElectric", "the electric pump is a registered load")
ok(W.loadOf(hand) == nil, "the hand pump is not a load")
ok(near(W.rated(elec), 200), "rated 200 W")
E.hours = 100
local el = pumpAt(30, 30, "electric", { wire = true })
ok(near(W.draw(el), 0), "idle, it draws nothing")
Fp.markBusy(elec, 10)
ok(Fp.working(elec) and near(W.draw(elec), 200), "just after pumping it draws 200 W")
E.hours = 100 + 2 / 60
ok(not Fp.working(elec) and near(W.draw(elec), 0), "two minutes later it is idle again")
elec.wire = false
Fp.markBusy(elec, 10)
ok(not Fp.working(elec), "an unwired pump never counts as working")
elec.wire = true

-- cancelling the queue: the action stops being valid when the tank runs dry or the car is full
local act2 = DUP_FuelVehicle:new(chE, elec, car2, 10)
ok(act2:isValid(), "valid with fuel and room")
car2.part.amount = 65
act2.checks = 0
ok(not act2:isValid(), "invalid once the car is full")

------------------------------------------------------------------ cans
local function fluidCan(fullType, amount, cap, fluidName)
    local it = E.item(fullType, chH.inv)
    local fc = { amount = amount, cap = cap, fluid = fluidName }
    function fc:getAmount() return self.amount end
    function fc:getCapacity() return self.cap end
    function fc:getPrimaryFluid() if self.amount > 0 and self.fluid then local nm = self.fluid return { getFluidTypeString = function() return nm end } end end
    function fc:addFluid(f, a) self.amount = math.min(self.cap, self.amount + a) if f == "P" then self.fluid = "Petrol" elseif f == "W" then self.fluid = "Water" end end
    function fc:adjustAmount(a) self.amount = a end
    function fc:canAddFluid(f) return f == "P" end
    it.getFluidContainer = function() return fc end
    it.fc = fc
    return it
end
local can = fluidCan("Base.PetrolCan", 2, 10, "Petrol")
chH.inv:AddItem(can)
ok(Fp.canTake(can), "a part-full petrol can takes petrol")
local c1 = Fp.fillCan(hand, can, 10)
ok(near(c1, Fp.CHUNK.hand) and near(can.fc.amount, 2 + Fp.CHUNK.hand), "hand pump added 2 L to the can")
ok(near(P.data(gas).amount, 95.5 - Fp.CHUNK.hand), "and took it from the tank")
local act3 = DUP_FuelCan:new(chH, hand, can, 2)
act3:complete()
ok(near(can.fc.amount, 6), "the can action fills a can")
local c2 = Fp.fillCan(elec, can, 25)
ok(near(c2, 4) and near(can.fc.amount, 10), "an electric chunk stops at the can's capacity")
ok(not Fp.canTake(can) and select(2, Fp.fillCan(elec, can, 5)) == "full", "a full can takes nothing")
local empty = fluidCan("Base.EmptyPetrolCan", 0, 8)
chH.inv:AddItem(empty)
ok(Fp.canTake(empty), "an empty petrol can takes petrol")
ok(near(Fp.fillCan(elec, empty, 25), 8) and empty.fc.fluid == "Petrol", "and is filled with petrol, up to its 8 L")
local bottle = fluidCan("Base.WaterBottle", 0, 1)
bottle.fc.canAddFluid = function() return true end
ok(not Fp.canTake(bottle), "a water bottle is not offered petrol")
local waterCan = fluidCan("Base.Bucket", 3, 10, "Water")
ok(not Fp.canTake(waterCan), "a can of water is not offered petrol")
-- an older petrol can that counts "uses"
local drain = E.item("Base.PetrolCan", chH.inv)
drain.uses = 1
drain.getCurrentUses = function(s) return s.uses end
drain.getMaxUses = function() return 8 end
drain.setCurrentUses = function(s, u) s.uses = u end
ok(Fp.canTake(drain), "a drainable petrol can counts")
ok(near(Fp.fillCan(hand, drain, 10), 2) and drain.uses == 3, "a drainable can gains whole uses")
-- a can nobody carries any more
local dropped = fluidCan("Base.PetrolCan", 0, 8, "Petrol")
dropped.container = nil
DUP_FuelCan:new(chH, hand, dropped, 2):complete()
ok(dropped.fc.amount == 0, "a can that is no longer carried is left alone")

------------------------------------------------------------------ the tank gauge sees the line, two tanks share it
local gasB = tankAt(15, 30, "gas", 50)
local pumpB = pumpAt(10, 30, "hand")
pipe(pumpB, gasB)
local gasC = tankAt(15, 33, "gas", 150)
local chB = E.character(10, 30, 0, 1)
E.give(chB, "Base.DazedPipeSection", 12)
DUP_PipeSet:new(chB, pumpB, Fp.ID, gasC):complete()
local lineB = Fp.line(pumpB)
ok(#lineB.tanks == 2 and near(lineB.litres, 200), "two petrol tanks on one line add up to 200 L")
local boy = vehicle({ E.square(10, 31) }, 0, 100)
Fp.refuel(pumpB, boy, 2)
ok(near(P.data(gasC).amount, 148) and near(P.data(gasB).amount, 50), "fuel is drawn from the fullest tank first")
L.setSource(pumpB, L.adapters[Fp.ID], "manual")
ok(Fp.line(pumpB).state == "paused" and select(2, Fp.refuel(pumpB, boy, 2)) == "notank", "a paused line gives nothing")

------------------------------------------------------------------ placement
ISMoveableSpriteProps = {}
function ISMoveableSpriteProps:placeMoveableInternal(square, item, name)
    local o = E.object(name, square)
    o.md.modData = { copied = true }
    return o
end
function ISMoveableSpriteProps:canPlaceMoveableInternal() return true end
function ISMoveableSpriteProps:instanceItem() return {} end
function ISMoveableSpriteProps:pickUpMoveableInternal() return nil end
function ISMoveableSpriteProps:pickUpMoveable() return nil end
package.loaded["DazedPlumbing/DUP_Place"] = nil
require "DazedPlumbing/DUP_Place"
local spot = E.square(35, 5)
local props = setmetatable({ spriteName = Fp.sprite("hand", "S") }, { __index = ISMoveableSpriteProps })
local placed = props:placeMoveableInternal(spot, { getModData = function() return {} end }, Fp.sprite("hand", "S"))
ok(placed and placed.md.modData == nil, "a placed fuel pump drops vanilla's copied item data")
ok(props:canPlaceMoveableInternal(E.character(35, 5), E.square(35, 6), nil) == true, "an empty square takes a fuel pump")
ok(props:canPlaceMoveableInternal(E.character(35, 5), spot, nil) == false, "a second fuel pump on one square is refused")
local propsE = setmetatable({ spriteName = Fp.sprite("electric", "W") }, { __index = ISMoveableSpriteProps })
ok(propsE:canPlaceMoveableInternal(E.character(35, 5), spot, nil) == false, "of either kind")

E.realPrint(string.format("fuel_test: %d checks, %d failed", n, fails))
if fails > 0 then for _, l in ipairs(E.printed) do E.realPrint("  log: " .. l) end end
os.exit(fails == 0 and 0 or 1)
