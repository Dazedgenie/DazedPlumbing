--[[ Dazed Utilities: Plumbing -- water pumps.

     Two pumps draw water from the ground:

       hand      you work the handle: one stroke puts STROKE litres into the
                 tank it is piped to (or fill a container straight from it).
       electric  runs by itself when the square has mains power (the grid a
                 generator or an Dazed Power controller keeps up), or when it is
                 wired to a powered Dazed Power controller (with Dazed Power), and
                 pushes RATE litres a minute down its pipe. It is billed as an
                 power load while it works (see DUP_Power).
       Both go ONLY on bare natural ground (grass, dirt) in the open.

     THE WELL (the ground under a pump) can run dry. It is a PLACE, not part
     of the pump: lifting a pump and putting it down on the same square finds
     the same water level. Per square, in the world ModData "DazedPlumbWells":
         wells["x,y,z"] = { reserve = litres left, cap = most it holds, hour = when last settled }
     The ground holds BASE_CAP litres, double near open water. It refills
     slowly (RECHARGE_PER_HOUR), three times as fast in the rain, worked out
     lazily from the world clock whenever somebody touches the well, so time
     away is paid for.

     SPRITES: after the pipes, 8 tiles: kind (hand, electric) x facing
     (E, S, W, N): dazedplumb_01_176 + kind*4 + facing.

     A pump is a link "SOURCE" (see DUP_Links): it pushes into a water tank
     through the same pipes and fuel lines the machines draw from.
]]

require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Pipes"
require "DazedPlumbing/DUP_Links"
require "DazedPlumbing/DUP_Sync"

DazedPlumb.Pumps = DazedPlumb.Pumps or {}
local U = DazedPlumb.Pumps
local P, K, L = DazedPlumb.Parts, DazedPlumb.Pipes, DazedPlumb.Links
local try = P.try

U.KINDS = { "hand", "electric" }
U.FACINGS = { "E", "S", "W", "N" }
U.BASE = K.BASE + K.COUNT
U.COUNT = 8
U.ITEM = { hand = "Base.DazedPumpHand", electric = "Base.DazedPumpElectric" }

U.BASE_CAP = 800               -- litres a well holds (double near open water)
U.NEAR_WATER_MULT = 2
U.RECHARGE_PER_HOUR = 30       -- litres back per hour
U.RAIN_MULT = 3
U.MAX_CATCHUP_HOURS = 24 * 14
U.STROKE = 5                   -- litres per stroke of a hand pump
U.ELECTRIC_RATE = 8            -- litres per minute from an electric pump, at full flow
U.PUMP_WATTS = 400             -- what an electric pump draws at full flow while working
U.FLOWS = { 0.25, 0.5, 0.75, 1.0 }   -- the flow settings a player may choose
U.STROKE_BASE = 212           -- a hand pump with its handle pressed down (facings E, S, W, N), shown mid-stroke
U.ID = "dazed_pump"
U.WELLS = "DazedPlumbWells"

----------------------------------------------------------- sprites
local function kindIndex(kind) for i, k in ipairs(U.KINDS) do if k == kind then return i - 1 end end end
local function facingIndex(f) for i, k in ipairs(U.FACINGS) do if k == f then return i - 1 end end end

function U.sprite(kind, facing)
    return P.TILESET .. "_" .. (U.BASE + kindIndex(kind) * 4 + facingIndex(facing))
end

--- The hand pump sprite with its handle up (false) or pressed down (true).
function U.handleSprite(facing, down)
    if not down then return U.sprite("hand", facing) end
    return P.TILESET .. "_" .. (U.STROKE_BASE + facingIndex(facing))
end

--- {kind, facing} for a pump sprite name (`stroke` when the handle is down), or nil.
function U.spriteInfo(name)
    local idx = P.indexOf(name)
    if idx and idx >= U.STROKE_BASE and idx < U.STROKE_BASE + 4 then
        return { kind = "hand", facing = U.FACINGS[idx - U.STROKE_BASE + 1], stroke = true }
    end
    if not idx or idx < U.BASE or idx >= U.BASE + U.COUNT then return nil end
    local n = idx - U.BASE
    return { kind = U.KINDS[math.floor(n / 4) + 1], facing = U.FACINGS[n % 4 + 1] }
end

function U.describe(obj)
    local spr = obj and try(obj, "getSprite")
    return spr and U.spriteInfo(try(spr, "getName")) or nil
end
function U.isPump(obj) return U.describe(obj) ~= nil end

function U.allItems() return { U.ITEM.hand, U.ITEM.electric } end

----------------------------------------------------------- where a pump may go
--- Is this square bare natural ground in the open?
function U.groundOk(square)
    if not square then return false end
    if try(square, "isOutside") ~= true then return false end
    local floor = try(square, "getFloor")
    local spr = floor and try(floor, "getSprite")
    local name = spr and try(spr, "getName")
    return type(name) == "string" and string.find(name, "^blends_natural") ~= nil
end

----------------------------------------------------------- the well
local function wells()
    if not ModData then return { wells = {} } end
    local t = ModData.getOrCreate(U.WELLS)
    t.wells = t.wells or {}
    return t
end

local worldHours = DazedCore.Util.worldHours

--- Is open water within a dozen squares? Looks for water floor tiles.
function U.waterNear(square)
    local cell = getCell and getCell()
    if not (cell and square) then return false end
    local flag = IsoFlagType and IsoFlagType.water
    if not flag then return false end
    for dx = -12, 12, 2 do
        for dy = -12, 12, 2 do
            local s = cell:getGridSquare(square:getX() + dx, square:getY() + dy, 0)
            local props = s and try(s, "getProperties")
            if props and (try(props, "has", flag) == true or try(props, "Is", flag) == true) then return true end
        end
    end
    return false
end

local function raining()
    local cm = getClimateManager and getClimateManager()
    local r = cm and try(cm, "getRainIntensity")
    return type(r) == "number" and r > 0.05
end

--- Let `hours` pass on a well. Pure: returns the new reserve.
function U.recharged(reserve, cap, hours, rain)
    local per = U.RECHARGE_PER_HOUR * (rain and U.RAIN_MULT or 1)
    return math.min(cap, math.max(0, reserve) + per * math.max(0, math.min(hours or 0, U.MAX_CATCHUP_HOURS)))
end

--- The well under a square, created full on first use and brought up to date.
--  A client only READS it (nothing is stored); the authority owns the level.
function U.well(square)
    local key = square:getX() .. "," .. square:getY() .. "," .. square:getZ()
    local st = wells().wells
    local now = worldHours()
    local w = st[key]
    if not DazedPlumb.Sync.authority() then
        if not w then
            local cap = U.BASE_CAP
            return { reserve = cap, cap = cap, hour = now }
        end
        return { reserve = U.recharged(w.reserve, w.cap, now - (w.hour or now), raining()), cap = w.cap, hour = now }
    end
    if not w then
        local cap = U.BASE_CAP * (U.waterNear(square) and U.NEAR_WATER_MULT or 1)
        w = { reserve = cap, cap = cap, hour = now }
        st[key] = w
    else
        w.reserve = U.recharged(w.reserve, w.cap, now - (w.hour or now), raining())
        w.hour = now
    end
    return w
end

--- Draw up to `amount` litres; returns what came out.
function U.draw(square, amount)
    local w = U.well(square)
    local got = math.min(math.max(0, amount or 0), w.reserve)
    w.reserve = w.reserve - got
    if got > 0 then DazedPlumb.Sync.touch(U.WELLS) end
    return got
end

----------------------------------------------------------- power
--- Does a power mod feed this machine by wire? Asked through the core's registry; an older
--  add-on's single hook (DazedPlumb.externalPower) still counts.
function DazedPlumb.wiredPower(obj)
    if not obj then return false end
    local W = DazedCore and DazedCore.Power
    if W and W.wired(obj) then return true end
    local hook = DazedPlumb.externalPower
    if not hook then return false end
    local ok, on = pcall(hook, obj)
    return ok and on == true
end

function U.powered(obj)
    if DazedPlumb.wiredPower(obj) then return true end
    local sq = obj and try(obj, "getSquare")
    return sq ~= nil and try(sq, "haveElectricity") == true
end

----------------------------------------------------------- the switch
--- Has a player switched this electric pump or purifier off (ModData `dazedOff`)? Off, it moves no water and draws no power.
function U.isOff(obj)
    local md = obj and obj.getModData and obj:getModData()
    return md ~= nil and md.dazedOff == true
end

----------------------------------------------------------- flow setting
--- The share of full flow a machine is set to (ModData `dazedFlow`, default full).
function U.flow(obj)
    local md = obj and obj.getModData and obj:getModData()
    local f = md and tonumber(md.dazedFlow)
    if f and f > 0 and f <= 1 then return f end
    return 1
end
function U.flowRate(obj) return U.ELECTRIC_RATE * U.flow(obj) end
function U.watts(obj) return U.PUMP_WATTS * U.flow(obj) end

----------------------------------------------------------- the link adapter
-- A pump is a SOURCE of water for a tank. A hand pump offers nothing on the
-- tick (a person works it); an electric one offers its rate while powered.
function U.register()
    return L.register({
        id = U.ID, produces = "water", tainted = true, label = "ContextMenu_DazedPlumb_PumpLine",
        match = function(o) return U.isPump(o) end,
        available = function(o)
            local info = U.describe(o)
            if not info or info.kind ~= "electric" or U.isOff(o) or not U.powered(o) then return 0 end
            local sq = try(o, "getSquare")
            return sq and math.min(U.flowRate(o), U.well(sq).reserve) or 0
        end,
        take = function(o, amount)
            local sq = try(o, "getSquare")
            return sq and U.draw(sq, amount) or 0
        end,
    })
end
U.register()

-- A pump saved mid-stroke (single player) comes back with its handle up.
local function onLoadStroke(obj)
    local info = U.describe(obj)
    if info and info.stroke then
        local name = U.handleSprite(info.facing, false)
        obj:setSprite(name)
        if obj.setSpriteFromName then pcall(obj.setSpriteFromName, obj, name) end
    end
end
if MapObjects and MapObjects.OnLoadWithSprite then
    for n = 0, 3 do MapObjects.OnLoadWithSprite(P.TILESET .. "_" .. (U.STROKE_BASE + n), onLoadStroke, 6) end
end

return U
