--[[ Dazed Utilities: Plumbing -- the garden sprinkler.

     A sprinkler is a water SINK on a network, like a tap: pipe it to a water
     tank (or a line already serving one) and every minute it waters the crops
     within RADIUS squares that are thirsty, drawing from the tank.

       how much   each crop is topped up toward the middle of its own good
                  range (waterNeeded .. waterNeededMax), never over it, so a
                  sprinkler cannot drown a field. A crop already in range is left
                  alone; rain usually keeps outdoor beds there by itself.
       cost       LITRES_PER_LEVEL litres per point of a crop's water level
                  (a dry bed from 0 to 70 takes 7 L), at most RATE L/min.
       switch     a player can turn it off (ModData `dazedSprinkler.off`).
       schedule   it waters only from hour `from` to hour `to` (none = always) and,
                  unless `rainSkip` is false, not while it rains (0.14.0).

     Crops live in the game's farming system on the server (SFarmingSystem),
     so watering only happens on the authority; a client's menu just reads.
     SPRITES: dazedplumb_01_204..207 idle, 208..211 spraying (facings E, S, W, N).
]]

require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Links"
require "DazedPlumbing/DUP_Sync"

DazedPlumb.Sprinklers = DazedPlumb.Sprinklers or {}
local Z = DazedPlumb.Sprinklers
local P, L = DazedPlumb.Parts, DazedPlumb.Links
local try = P.try

Z.BASE = 204
Z.COUNT = 8
Z.FACINGS = { "E", "S", "W", "N" }
Z.ITEM = "Base.DazedSprinkler"
Z.ID = "dazed_sprinkler"
Z.KEY = "dazedSprinkler"

Z.RADIUS = 3                    -- squares, round: a 7x7 patch less its corners
Z.RATE = 10                     -- most litres a minute one sprinkler uses
Z.LITRES_PER_LEVEL = 0.1        -- litres per point of a crop's 0..100 water level
Z.DEFAULT_TARGET = 70           -- for a crop that does not say what it needs
Z.SLACK = 5                     -- a crop this close under its target is left alone
Z.RAIN_SKIP_ABOVE = 0.05        -- rain intensity (0..1) above which a "skip when raining" sprinkler waits
-- The schedule choices in the menu: no hours means always; from > to wraps past midnight.
Z.PRESETS = {
    { id = "always" },
    { id = "dawn", from = 5, to = 8 },
    { id = "evening", from = 18, to = 21 },
    { id = "night", from = 22, to = 4 },
}

----------------------------------------------------------- sprites
function Z.sprite(facing, spraying)
    for i, f in ipairs(Z.FACINGS) do
        if f == facing then return P.TILESET .. "_" .. (Z.BASE + (spraying and 4 or 0) + i - 1) end
    end
end

function Z.spriteInfo(name)
    local idx = P.indexOf(name)
    if not idx or idx < Z.BASE or idx >= Z.BASE + Z.COUNT then return nil end
    local n = idx - Z.BASE
    return { facing = Z.FACINGS[n % 4 + 1], spraying = n >= 4 }
end

function Z.describe(obj)
    local spr = obj and try(obj, "getSprite")
    return spr and Z.spriteInfo(try(spr, "getName")) or nil
end
function Z.isSprinkler(obj) return Z.describe(obj) ~= nil end

function Z.state(obj)
    local md = obj and obj.getModData and obj:getModData()
    if not md then return {} end
    md[Z.KEY] = md[Z.KEY] or {}
    return md[Z.KEY]
end
function Z.isOn(obj) return Z.state(obj).off ~= true end

----------------------------------------------------------- the schedule
--- A whole hour 0..23, or nil.
function Z.validHour(h)
    h = tonumber(h)
    if h and h == math.floor(h) and h >= 0 and h <= 23 then return h end
    return nil
end

--- Is `hour` (0..24, fractions allowed) inside the window? The start hour counts and the end hour does not.
-- No window (or from == to) means always, and from > to wraps past midnight.
function Z.inWindow(from, to, hour)
    from, to = Z.validHour(from), Z.validHour(to)
    if not from or not to or from == to then return true end
    hour = (tonumber(hour) or 0) % 24
    if from < to then return hour >= from and hour < to end
    return hour >= from or hour < to
end

--- Why the schedule holds a sprinkler back: nil (it may water), "window" or "rain". Pure.
function Z.held(from, to, rainSkip, hour, rain)
    if not Z.inWindow(from, to, hour) then return "window" end
    if rainSkip and (tonumber(rain) or 0) > Z.RAIN_SKIP_ABOVE then return "rain" end
    return nil
end

--- The stored schedule: from, to (both nil = always) and whether it skips rain (default yes).
function Z.schedule(obj)
    local st = Z.state(obj)
    local from, to = Z.validHour(st.from), Z.validHour(st.to)
    if not from or not to or from == to then from, to = nil, nil end
    return from, to, st.rainSkip ~= false
end

--- The game hour now as a fraction (GameTime:getTimeOfDay, else getHour), or 12 when the engine cannot say.
function Z.hourNow()
    local gt = getGameTime and getGameTime()
    local h = gt and try(gt, "getTimeOfDay")
    if type(h) ~= "number" then h = gt and try(gt, "getHour") end
    return type(h) == "number" and h or 12
end

--- Rain intensity now, 0..1 (snow counts as none).
function Z.rainNow()
    local cm = getClimateManager and getClimateManager()
    if not cm then return 0 end
    if try(cm, "getPrecipitationIsSnow") == true then return 0 end
    local r = try(cm, "getRainIntensity")
    if type(r) ~= "number" then r = try(cm, "getPrecipitationIntensity") end
    return type(r) == "number" and r or 0
end

--- Why this sprinkler's schedule holds it back right now: nil, "window" or "rain".
function Z.blocked(obj)
    local from, to, rainSkip = Z.schedule(obj)
    return Z.held(from, to, rainSkip, Z.hourNow(), Z.rainNow())
end

--- Store a watering window (authority): two whole hours, or -1/-1 (or nil) for always. Returns true when stored.
function Z.setWindow(obj, from, to)
    local st = Z.state(obj)
    if (from == nil or from == -1) and (to == nil or to == -1) then
        st.from, st.to = nil, nil
        return true
    end
    from, to = Z.validHour(from), Z.validHour(to)
    if not from or not to then return false end
    if from == to then st.from, st.to = nil, nil else st.from, st.to = from, to end
    return true
end

--- Store the "skip when raining" toggle (authority); on is the default, so only off is kept.
function Z.setRainSkip(obj, on)
    local st = Z.state(obj)
    if on == false then st.rainSkip = false else st.rainSkip = nil end
    return true
end

--- The preset id a window matches ("always", "dawn"...), or nil for a window no preset has.
function Z.presetOf(from, to)
    for _, p in ipairs(Z.PRESETS) do
        if p.from == from and p.to == to then return p.id end
    end
    return nil
end

----------------------------------------------------------- the crops
local worldHours = DazedCore.Util.worldHours

--- The farming system's plant on a square, or nil (server side only).
local function plantAt(x, y, z)
    -- a client (a menu) reads the synced copy; the authority has the real system
    local sys = (SFarmingSystem and SFarmingSystem.instance) or (CFarmingSystem and CFarmingSystem.instance)
    if not (sys and sys.getLuaObjectAt) then return nil end
    local ok, p = pcall(sys.getLuaObjectAt, sys, x, y, z)
    return ok and p or nil
end

--- The water level a crop is topped up to: the middle of its good range.
function Z.target(plant)
    local lo, hi = tonumber(plant.waterNeeded), tonumber(plant.waterNeededMax)
    if lo and hi and hi > lo then return math.min(100, (lo + hi) / 2) end
    if lo then return math.min(100, lo + 10) end
    return Z.DEFAULT_TARGET
end

--- Is this a crop worth watering (seeded and alive, not bare ploughed earth)?
local function growing(plant)
    if not plant or plant.state == "plow" or plant.state == "destroyed" then return false end
    if plant.isAlive then
        local ok, alive = pcall(plant.isAlive, plant)
        if ok and alive == false then return false end
    end
    return tonumber(plant.waterLvl) ~= nil
end

-- The growing crops in a sprinkler's reach, looked up once per sprinkler per game minute (room, put and the
-- menu all ask); how thirsty each is stays a live reading, since one sprinkler's watering changes it for the next.
local cropMemo, cropMemoAt = {}, nil

local function cropsInReach(obj, sq)
    local minute = math.floor(worldHours() * 60)
    if cropMemoAt ~= minute then cropMemo, cropMemoAt = {}, minute end
    local hit = cropMemo[obj]
    if hit then return hit end
    local cx, cy, cz = sq:getX(), sq:getY(), sq:getZ()
    local out, r = {}, Z.RADIUS
    for dx = -r, r do
        for dy = -r, r do
            if dx * dx + dy * dy <= r * r + 0.5 then
                local plant = plantAt(cx + dx, cy + dy, cz)
                if growing(plant) then out[#out + 1] = plant end
            end
        end
    end
    cropMemo[obj] = out
    return out
end

--- Every thirsty crop in reach as { plant, want = water level points short }.
function Z.thirsty(obj)
    local sq = obj and try(obj, "getSquare")
    if not sq then return {} end
    local out = {}
    for _, plant in ipairs(cropsInReach(obj, sq)) do
        if growing(plant) then
            local short = Z.target(plant) - plant.waterLvl
            if short > Z.SLACK then out[#out + 1] = { plant = plant, want = short } end
        end
    end
    return out
end

----------------------------------------------------------- the sink
--- Litres it would use this minute.

function Z.room(obj)
    -- the network asks every minute: a sprinkler that has not been fed for a while stops spraying
    local info = Z.describe(obj)
    if info and info.spraying and DazedPlumb.Sync and DazedPlumb.Sync.authority()
            and worldHours() - (Z.state(obj).fedAt or 0) > 2 / 60 then
        Z.setSpraying(obj, false)
    end
    if not Z.isOn(obj) or Z.blocked(obj) then return 0 end
    local need = 0
    for _, t in ipairs(Z.thirsty(obj)) do need = need + t.want * Z.LITRES_PER_LEVEL end
    return math.min(Z.RATE, need)
end

--- Water the thirsty crops with `amount` litres, driest first; returns what was used.
--- Crops in reach and how many of them are thirsty, for the menu.
function Z.survey(obj)
    local sq = obj and try(obj, "getSquare")
    if not sq then return 0, 0 end
    local crops = 0
    for _, plant in ipairs(cropsInReach(obj, sq)) do
        if growing(plant) then crops = crops + 1 end
    end
    return crops, #Z.thirsty(obj)
end

function Z.put(obj, amount)
    local list = Z.thirsty(obj)
    table.sort(list, function(a, b) return a.want > b.want end)
    local left, hours = math.max(0, amount or 0), SFarmingSystem and SFarmingSystem.instance and SFarmingSystem.instance.hoursElapsed
    for _, t in ipairs(list) do
        if left <= 1e-6 then break end
        local litres = math.min(left, t.want * Z.LITRES_PER_LEVEL)
        local p = t.plant
        p.waterLvl = math.min(100, p.waterLvl + litres / Z.LITRES_PER_LEVEL)
        if hours then p.lastWaterHour = hours end
        if p.saveData then pcall(p.saveData, p) end
        left = left - litres
    end
    local used = math.max(0, (amount or 0) - left)
    if used > 0 then Z.state(obj).fedAt = worldHours() end
    Z.setSpraying(obj, used > 0)
    return used
end

--- Show the spray while it waters (authority; only when the look changes).
function Z.setSpraying(obj, on)
    local info = Z.describe(obj)
    if not info or info.spraying == on then return end
    local name = Z.sprite(info.facing, on)
    obj:setSprite(name)
    if obj.setSpriteFromName then pcall(obj.setSpriteFromName, obj, name) end
    if obj.transmitUpdatedSpriteToClients and isServer and isServer() then obj:transmitUpdatedSpriteToClients() end
end

-- A sprinkler saved mid-spray comes back idle; the next minute's watering turns it on again.
local function onLoad(obj)
    local info = Z.describe(obj)
    if info and info.spraying and DazedPlumb.Sync and DazedPlumb.Sync.authority() then Z.setSpraying(obj, false) end
end
if MapObjects and MapObjects.OnLoadWithSprite then
    for n = 4, 7 do MapObjects.OnLoadWithSprite(P.TILESET .. "_" .. (Z.BASE + n), onLoad, 6) end
end

L.register({
    id = Z.ID, supplies = "water", label = "ContextMenu_DazedPlumb_SprinklerLine",
    match = Z.isSprinkler, room = Z.room, put = Z.put,
})

return Z
