--[[ Dazed Utilities: Plumbing -- the fuel pump: refuel a parked vehicle or fill a can from a piped petrol tank.
     Two builds exist: a hand pump you crank and an electric one that works only when wired to a Dazed Power controller.

     A fuel pump is a link SINK for "gas" that never takes fuel into itself (room is always 0); it only
     stands on the line, so the player's action can draw from the petrol tanks piped to it.
     SPRITES: after the water main, 8 tiles: kind (hand, electric) x facing (E, S, W, N): BASE + kind*4 + facing.
]]

require "DazedCore/DC_Boot"
require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Links"
require "DazedPlumbing/DUP_Pumps"
require "DazedPlumbing/DUP_Mains"
require "DazedPlumbing/DUP_Fluids"

DazedPlumb.FuelPumps = DazedPlumb.FuelPumps or {}
local Fp = DazedPlumb.FuelPumps
local P, L, U, F = DazedPlumb.Parts, DazedPlumb.Links, DazedPlumb.Pumps, DazedPlumb.Fluids
local try = P.try

Fp.KINDS = { "hand", "electric" }
Fp.FACINGS = { "E", "S", "W", "N" }
Fp.BASE = DazedPlumb.Mains.BASE + DazedPlumb.Mains.COUNT     -- first fuel pump sprite (appended after the water main)
Fp.COUNT = 8
Fp.ITEM = { hand = "Base.DazedFuelPumpHand", electric = "Base.DazedFuelPumpElectric" }
Fp.ID = "dazed_fuelpump"

Fp.RATE = { hand = 2, electric = 10 }      -- litres a minute
Fp.CHUNK = { hand = 2, electric = 10 }     -- litres one timed action moves (a minute of pumping)
Fp.WATTS = 200                             -- electric pump load while it is moving fuel
Fp.REACH = 2                               -- squares from the pump a vehicle may stand
Fp.TICKS_PER_MINUTE = 90                   -- action ticks that stand for one minute of pumping
Fp.EPS = 0.001

----------------------------------------------------------- sprites
local function kindIndex(kind) for i, k in ipairs(Fp.KINDS) do if k == kind then return i - 1 end end end
local function facingIndex(f) for i, k in ipairs(Fp.FACINGS) do if k == f then return i - 1 end end end

function Fp.sprite(kind, facing)
    local k, f = kindIndex(kind), facingIndex(facing)
    if not (k and f) then return nil end
    return P.TILESET .. "_" .. (Fp.BASE + k * 4 + f)
end

--- {kind, facing} for a fuel pump sprite name, or nil.
function Fp.spriteInfo(name)
    local idx = type(name) == "string" and string.match(name, "^" .. P.TILESET .. "_(%d+)$")
    idx = idx and tonumber(idx)
    if not idx or idx < Fp.BASE or idx >= Fp.BASE + Fp.COUNT then return nil end
    local n = idx - Fp.BASE
    return { kind = Fp.KINDS[math.floor(n / 4) + 1], facing = Fp.FACINGS[n % 4 + 1] }
end

function Fp.describe(obj)
    local spr = obj and try(obj, "getSprite")
    return spr and Fp.spriteInfo(try(spr, "getName")) or nil
end
function Fp.isFuelPump(obj) return Fp.describe(obj) ~= nil end
function Fp.kindOf(obj) local i = Fp.describe(obj) return i and i.kind or nil end
function Fp.allItems() return { Fp.ITEM.hand, Fp.ITEM.electric } end

----------------------------------------------------------- the model (pure)
function Fp.rate(kind) return Fp.RATE[kind] or 0 end

--- Litres one action moves: what was asked, capped by the chunk, the fuel in the tanks and the room in the target.
function Fp.litres(kind, want, tankLitres, room)
    local chunk = Fp.CHUNK[kind] or 0
    local n = math.min(want or chunk, chunk, tankLitres or 0, room or 0)
    return n > Fp.EPS and n or 0
end

--- Minutes of pumping for a number of litres.
function Fp.minutes(kind, litres)
    local r = Fp.rate(kind)
    return r > 0 and litres / r or 0
end

--- Action length in ticks for a number of litres.
function Fp.ticks(kind, litres)
    return math.max(10, math.ceil(Fp.minutes(kind, litres) * Fp.TICKS_PER_MINUTE))
end

--- Chunks (actions) needed to move `litres`.
function Fp.chunksFor(kind, litres)
    local c = Fp.CHUNK[kind] or 1
    return math.max(1, math.ceil(litres / c - Fp.EPS))
end

----------------------------------------------------------- power
function Fp.isOff(obj) return U.isOff(obj) end

--- Is an electric pump wired to a powered Dazed Power controller? The square's own power does not count.
function Fp.wired(obj) return DazedPlumb.wiredPower(obj) end

--- Can this pump run now? Returns true, or false and a reason: "off", "nopower".
function Fp.ready(obj)
    local kind = Fp.kindOf(obj)
    if not kind then return false, "gone" end
    if kind == "hand" then return true end
    if Fp.isOff(obj) then return false, "off" end
    if not Fp.wired(obj) then return false, "nopower" end
    return true
end

local function nowMinutes()
    local gt = getGameTime and getGameTime()
    local h = gt and try(gt, "getWorldAgeHours")
    return (tonumber(h) or 0) * 60
end

--- Note that an electric pump just moved `litres`: it counts as working (and billed) for that long.
function Fp.markBusy(obj, litres)
    local md = obj and obj.getModData and obj:getModData()
    if not md or Fp.kindOf(obj) ~= "electric" then return end
    md.dazedFuelBusy = nowMinutes() + math.max(1, Fp.minutes("electric", litres))
end

--- Is this electric pump moving fuel right now? (No side effects.)
function Fp.working(obj)
    if Fp.kindOf(obj) ~= "electric" or not Fp.ready(obj) then return false end
    local md = obj:getModData()
    return md ~= nil and (tonumber(md.dazedFuelBusy) or 0) > nowMinutes()
end

----------------------------------------------------------- the piped tanks
--- What the pump is piped to: { state = "ok"|"unpiped"|"down"|"paused", tanks = {handles}, litres }.
function Fp.line(pump)
    local a = L.adapters[Fp.ID]
    local out = { state = "unpiped", tanks = {}, litres = 0 }
    if not a then return out end
    local st = L.status(pump, a)
    if not st.connected then return out end
    if not st.working then out.state = "down" return out end
    local link = L.linkOf(pump, Fp.ID)
    if link and link.source ~= "tank" then out.state = "paused" return out end
    out.state, out.tanks = "ok", st.tanks
    for _, t in ipairs(st.tanks) do out.litres = out.litres + math.max(0, t.amount()) end
    return out
end

--- Take `litres` out of the tanks, fullest first; returns what came out.
function Fp.draw(tanks, litres)
    local order = {}
    for _, t in ipairs(tanks) do order[#order + 1] = t end
    table.sort(order, function(a, b) return a.amount() > b.amount() end)
    local left, took = litres, 0
    for _, t in ipairs(order) do
        if left > Fp.EPS then
            local got = t.take(math.min(left, t.amount())) or 0
            left, took = left - got, took + got
        end
    end
    return took
end

----------------------------------------------------------- vehicles
--- Every vehicle on a square within `reach` of the pump (the engine's own square lookup).
function Fp.vehiclesNear(pump, reach)
    reach = reach or Fp.REACH
    local sq = pump and try(pump, "getSquare")
    local cell = getCell and getCell()
    local out, seen = {}, {}
    if not (sq and cell) then return out end
    for dx = -reach, reach do
        for dy = -reach, reach do
            local s = cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
            local v = s and try(s, "getVehicleContainer")
            if v and not seen[v] then seen[v] = true out[#out + 1] = v end
        end
    end
    return out
end

function Fp.inReach(pump, vehicle)
    for _, v in ipairs(Fp.vehiclesNear(pump)) do if v == vehicle then return true end end
    return false
end

--- A parked vehicle has its engine off and is not rolling.
function Fp.parked(vehicle)
    if try(vehicle, "isEngineRunning") == true then return false end
    return math.abs(tonumber(try(vehicle, "getCurrentSpeedKmHour")) or 0) < 1
end

--- The vehicle's petrol tank: { part, amount, capacity, room } in litres, or nil.
function Fp.tankOf(vehicle)
    local part = vehicle and try(vehicle, "getPartById", "GasTank")
    if not part then return nil end
    local cap, cur = try(part, "getContainerCapacity"), try(part, "getContainerContentAmount")
    if type(cap) ~= "number" or type(cur) ~= "number" or cap <= 0 then return nil end
    return { part = part, amount = cur, capacity = cap, room = math.max(0, cap - cur) }
end

local said = {}
local function once(key, text)
    if said[key] then return end
    said[key] = true
    print("DazedPlumbing: " .. text)
end

--- Set the tank's contents and tell the clients; returns what it holds afterwards, read back.
function Fp.setVehicleFuel(vehicle, part, amount)
    local ok = pcall(part.setContainerContentAmount, part, amount)
    local after = try(part, "getContainerContentAmount")
    local sent = type(vehicle.transmitPartModData) == "function" and pcall(vehicle.transmitPartModData, vehicle, part)
    if type(vehicle.updatePartStats) == "function" then pcall(vehicle.updatePartStats, vehicle) end
    once("vehfuel", "vehicle tank set " .. (ok and "ok" or "FAILED") .. ", read back " .. tostring(after)
        .. ", transmitPartModData " .. (sent and "called" or "not available"))
    return type(after) == "number" and after or nil
end

--- A readable name for a vehicle (its translated script name when there is one).
function Fp.vehicleName(vehicle)
    local script = try(vehicle, "getScript")
    local name = script and try(script, "getName")
    if type(name) ~= "string" then return "?" end
    local key = "IGUI_VehicleName" .. name
    local text = getText and getText(key)
    return (text and text ~= key) and text or name
end

--- Pump up to `want` litres into a vehicle. Returns litres moved, or 0 and a reason key suffix.
function Fp.refuel(pump, vehicle, want)
    local ok, why = Fp.ready(pump)
    if not ok then return 0, why end
    if not Fp.inReach(pump, vehicle) then return 0, "far" end
    if not Fp.parked(vehicle) then return 0, "running" end
    local line = Fp.line(pump)
    if #line.tanks == 0 then return 0, "notank" end
    if line.litres <= Fp.EPS then return 0, "empty" end
    local t = Fp.tankOf(vehicle)
    if not t then return 0, "novehicle" end
    local kind = Fp.kindOf(pump)
    local n = Fp.litres(kind, want, line.litres, t.room)
    if n <= 0 then return 0, "full" end
    local after = Fp.setVehicleFuel(vehicle, t.part, t.amount + n)
    local added = after and math.max(0, after - t.amount) or 0
    if added > Fp.EPS then
        Fp.draw(line.tanks, added)
        Fp.markBusy(pump, added)
    end
    return added
end

----------------------------------------------------------- cans
--- May this carried item take petrol (a petrol can, or an empty fuel container) with room left?
function Fp.canTake(item)
    local v = F.vessel(item)
    if not v or v.capacity - v.amount <= Fp.EPS then return false end
    return v.kind == "gas" or (v.kind == "empty" and F.accepts(item, "gas"))
end

--- Pump up to `want` litres into a carried can. Returns litres moved, or 0 and a reason.
function Fp.fillCan(pump, item, want)
    local ok, why = Fp.ready(pump)
    if not ok then return 0, why end
    local line = Fp.line(pump)
    if #line.tanks == 0 then return 0, "notank" end
    if line.litres <= Fp.EPS then return 0, "empty" end
    local v = F.vessel(item)
    if not (v and Fp.canTake(item)) then return 0, "full" end
    local n = Fp.litres(Fp.kindOf(pump), want, line.litres, v.capacity - v.amount)
    if n <= 0 then return 0, "full" end
    local added = F.fill(item, "gas", n)
    if added > Fp.EPS then
        Fp.draw(line.tanks, added)
        Fp.markBusy(pump, added)
    end
    return added
end

----------------------------------------------------------- the link adapter
-- A SINK of petrol that holds nothing: it only puts the pump on the line next to its tanks.
function Fp.register()
    return L.register({
        id = Fp.ID, supplies = "gas", label = "ContextMenu_DazedPlumb_FuelPumpLine",
        match = function(o) return Fp.isFuelPump(o) end,
        room = function() return 0 end,
        put = function() return 0 end,
    })
end
Fp.register()

return Fp
