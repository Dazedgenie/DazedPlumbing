--[[ Dazed Utilities: Plumbing -- the tank physics. Pure Lua: no engine calls.

     A tank is a vessel with a TYPE (what it holds), a SIZE, a TIER (how it
     came to be) and a record of what it holds right now. Everything here
     works on a plain table of the tank's flat ModData -- the same table the
     objects carry -- so it can be tested without the game.

       size   small, large, xl
       type   propane (kg), gas = petrol (litres), water (litres)
       tier   salvaged: found worn; holds a little less, leaks from a higher
                        condition
              crafted:  built properly; full capacity, leaks only when it is
                        badly hurt

     The three fields the model reads and writes on a tank `d`:
       d.amount     what it holds, in the type's unit
       d.condition  0..100, from the item it came from; repaired by hand
       d.size / d.type / d.tier   identity (set by DUP_Parts)
]]

DazedPlumb = DazedPlumb or {}
DazedPlumb.Model = DazedPlumb.Model or {}
local M = DazedPlumb.Model

local min, max = math.min, math.max
local function clamp(v, lo, hi) return min(hi, max(lo, v)) end
M.clamp = clamp

M.SIZES = { "small", "large", "xl" }
M.TYPES = { "propane", "gas", "water" }
M.TIERS = { "salvaged", "crafted" }

--  Nominal capacity by type and size, in the type's unit (crafted; salvaged holds TIER_SPEC.cap of it).
--  Water and petrol: a 55-gallon drum, a 275-gallon basement tank, a 500-gallon one.
--  Propane is kilograms (what Dazed Power's generators burn; a vanilla tank is 9 kg):
--  a 100 lb cylinder, then large and XL tanks kept below their true fill so propane stays scarce.
M.NOMINAL = {
    water   = { small = 200, large = 1000, xl = 2000 },
    gas     = { small = 200, large = 1000, xl = 2000 },
    propane = { small = 45,  large = 200,  xl = 400 },
}

M.TIER_SPEC = {
    salvaged = { cap = 0.80, leakBelow = 60 },
    crafted  = { cap = 1.00, leakBelow = 35 },
}

M.UNIT = { propane = "kg", gas = "L", water = "L" }
M.FLAMMABLE = { propane = true, gas = true, water = false }

--  LEAKS. Below its tier's leakBelow condition a tank loses a share of its
--  capacity every hour, more the worse it is: nothing at the threshold,
--  LEAK_FRAC_PER_HOUR of capacity at condition 0.
M.LEAK_FRAC_PER_HOUR = 0.06

--  FIRE. A tank holding something that burns, with flames on or beside its
--  square, goes up. Chance per minute at a full tank; scaled by how full it
--  is, so a nearly empty one is a small risk and a full one is a bad one.
M.FIRE_PER_MINUTE = 0.10

--- Capacity in the type's unit (type defaults to water).
function M.capacity(size, tier, typ)
    local spec = M.TIER_SPEC[tier or "crafted"] or M.TIER_SPEC.crafted
    local row = M.NOMINAL[typ or "water"] or M.NOMINAL.water
    return (row[size or "small"] or row.small) * spec.cap
end

--- The tank's table `d` with every field defaulted, never below zero and
--  never over capacity (a lowered capacity cannot happen, but a hand-edited
--  save can). Returns d.
function M.normalize(d)
    d.condition = clamp(d.condition or 100, 0, 100)
    d.amount = clamp(d.amount or 0, 0, M.capacity(d.size, d.tier, d.type))
    if d.dirty ~= nil then d.dirty = clamp(d.dirty, 0, d.amount) end
    return d
end

--- How much room is left.
function M.room(d)
    return max(0, M.capacity(d.size, d.tier, d.type) - max(0, d.amount or 0))
end

--- Fill fraction, 0..1.
function M.fullness(d)
    local cap = M.capacity(d.size, d.tier, d.type)
    return (cap > 0) and clamp((d.amount or 0) / cap, 0, 1) or 0
end

--  WATER QUALITY. A water tank also remembers how much of what it holds is
--  TAINTED (d.dirty, litres): ground water is, rain and purified water are not.
--  Taking water out takes the dirty share out in proportion, and the tank
--  counts as tainted while at least TAINT_THRESHOLD of it is dirty, so a
--  little dirt in a lot of clean water is forgiven and a lot is not.
M.TAINT_THRESHOLD = 0.10

--- Fraction of the contents that is tainted, 0..1.
function M.dirtyFraction(d)
    local a = d.amount or 0
    if a <= 0 then return 0 end
    return clamp((d.dirty or 0) / a, 0, 1)
end

--- Is this a water tank that counts as tainted right now?
function M.isTainted(d)
    return d.type == "water" and (d.amount or 0) > 0.0001 and M.dirtyFraction(d) >= M.TAINT_THRESHOLD
end

--- Put in up to `amount`; returns what was accepted.
function M.add(d, amount)
    local take = min(max(0, amount or 0), M.room(d))
    d.amount = (d.amount or 0) + take
    return take
end

--- Put in water, `dirty` saying whether it is tainted. Returns what was accepted.
function M.addWater(d, amount, dirty)
    local took = M.add(d, amount)
    if dirty and took > 0 then d.dirty = (d.dirty or 0) + took end
    return took
end

--- Take out up to `amount`; returns what was given.
function M.take(d, amount)
    local have = max(0, d.amount or 0)
    local give = min(max(0, amount or 0), have)
    if have > 0 and (d.dirty or 0) > 0 then
        d.dirty = d.dirty * (1 - give / have)            -- the dirty share leaves with it
        if have - give <= 0.0001 then d.dirty = 0 end
    end
    d.amount = (d.amount or 0) - give
    return give
end

--  RAIN. A water tank standing in the open (no roof over a square) catches rain:
--  RAIN_PER_SQUARE_HOUR litres per open square per hour at full downpour, scaled
--  by the rain's intensity (0..1). Rainwater is clean.
M.RAIN_PER_SQUARE_HOUR = 10

--- Litres a water tank with `openSquares` uncovered squares catches in `hours` of rain at `intensity`.
function M.rainGain(d, openSquares, intensity, hours)
    if d.type ~= "water" then return 0 end
    return M.RAIN_PER_SQUARE_HOUR * max(0, openSquares or 0) * clamp(intensity or 0, 0, 1) * max(0, hours or 0)
end

--  ROOF RUNOFF. A water tank standing beside a building (outside, a building square
--  touching it) catches what runs off that roof: RUNOFF_PER_ROOF_SQUARE_HOUR litres per
--  roof square per hour at full downpour, split between the tanks beside that building and
--  limited to RUNOFF_MAX_PER_HOUR each (a barrel with no gutter only takes so much).
M.RUNOFF_PER_ROOF_SQUARE_HOUR = 2
M.RUNOFF_MAX_PER_HOUR = 60

--  A DOWNSPOUT on a wall draws from the same roof, up to DOWNSPOUT_MAX_PER_HOUR (one
--  gutter run's worth), and holds DOWNSPOUT_BUFFER litres for the line it feeds.
M.DOWNSPOUT_MAX_PER_HOUR = 80
M.DOWNSPOUT_BUFFER = 20

--- Litres one catcher takes from a roof of `roofSquares` in `hours`: an equal share between
--  `catchers` (tanks and downspouts at that building), limited to `perHourCap` litres an hour.
function M.runoffShare(roofSquares, intensity, hours, catchers, perHourCap)
    if (catchers or 0) < 1 then return 0 end
    local k = clamp(intensity or 0, 0, 1)
    local total = M.RUNOFF_PER_ROOF_SQUARE_HOUR * max(0, roofSquares or 0) * k
    return min(total / catchers, (perHourCap or M.RUNOFF_MAX_PER_HOUR) * k) * max(0, hours or 0)
end

--- Litres one water tank takes from a roof of `roofSquares`, shared by `catchers`.
function M.runoffGain(d, roofSquares, intensity, hours, catchers)
    if d.type ~= "water" then return 0 end
    return M.runoffShare(roofSquares, intensity, hours, catchers, M.RUNOFF_MAX_PER_HOUR)
end

--- Units lost per hour to a leak at the tank's present condition (0 = sound).
function M.leakRate(d)
    local spec = M.TIER_SPEC[d.tier or "crafted"] or M.TIER_SPEC.crafted
    local c = d.condition or 100
    if c >= spec.leakBelow then return 0 end
    return M.capacity(d.size, d.tier, d.type) * M.LEAK_FRAC_PER_HOUR * (spec.leakBelow - c) / spec.leakBelow
end

--- Let `hours` pass. Mutates d.amount; returns the amount lost.
function M.leak(d, hours)
    local rate = M.leakRate(d)
    if rate <= 0 or (d.amount or 0) <= 0 then return 0 end
    return M.take(d, rate * max(0, hours or 0))
end

--- Is it leaking right now?
function M.isLeaking(d)
    return M.leakRate(d) > 0 and (d.amount or 0) > 0
end

--- The chance, over `minutes`, that a tank with flames beside it ignites.
--  Zero for water or an empty tank.
function M.fireChance(d, minutes)
    if not M.FLAMMABLE[d.type or ""] then return 0 end
    local f = M.fullness(d)
    if f <= 0 then return 0 end
    return clamp(M.FIRE_PER_MINUTE * f * max(0, minutes or 0), 0, 1)
end

--  VESSELS the player carries. Propane lives in vanilla drainables
--  (a 20 lb tank, a lantern bottle), read as a 0..1 fill; kilograms when full:
M.PROPANE_VESSELS = {
    ["Base.PropaneTank"] = 9,
    ["Base.Propane_Refill"] = 0.45,
}
