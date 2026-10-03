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

----------------------------------------------------------- sprites
function Z.sprite(facing, spraying)
    for i, f in ipairs(Z.FACINGS) do
        if f == facing then return P.TILESET .. "_" .. (Z.BASE + (spraying and 4 or 0) + i - 1) end
    end
end

function Z.spriteInfo(name)
    local idx = type(name) == "string" and string.match(name, "^" .. P.TILESET .. "_(%d+)$")
    idx = idx and tonumber(idx)
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

----------------------------------------------------------- the crops
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

--- Every thirsty crop in reach as { plant, want = water level points short }.
function Z.thirsty(obj)
    local sq = obj and try(obj, "getSquare")
    if not sq then return {} end
    local cx, cy, cz = sq:getX(), sq:getY(), sq:getZ()
    local out, r = {}, Z.RADIUS
    for dx = -r, r do
        for dy = -r, r do
            if dx * dx + dy * dy <= r * r + 0.5 then
                local plant = plantAt(cx + dx, cy + dy, cz)
                if growing(plant) then
                    local short = Z.target(plant) - plant.waterLvl
                    if short > Z.SLACK then out[#out + 1] = { plant = plant, want = short } end
                end
            end
        end
    end
    return out
end

----------------------------------------------------------- the sink
--- Litres it would use this minute.
local function worldHours()
    local gt = getGameTime and getGameTime()
    return gt and gt:getWorldAgeHours() or 0
end

function Z.room(obj)
    -- the network asks every minute: a sprinkler that has not been fed for a while stops spraying
    local info = Z.describe(obj)
    if info and info.spraying and DazedPlumb.Sync and DazedPlumb.Sync.authority()
            and worldHours() - (Z.state(obj).fedAt or 0) > 2 / 60 then
        Z.setSpraying(obj, false)
    end
    if not Z.isOn(obj) then return 0 end
    local need = 0
    for _, t in ipairs(Z.thirsty(obj)) do need = need + t.want * Z.LITRES_PER_LEVEL end
    return math.min(Z.RATE, need)
end

--- Water the thirsty crops with `amount` litres, driest first; returns what was used.
--- Crops in reach and how many of them are thirsty, for the menu.
function Z.survey(obj)
    local sq = obj and try(obj, "getSquare")
    if not sq then return 0, 0 end
    local cx, cy, cz = sq:getX(), sq:getY(), sq:getZ()
    local crops, r = 0, Z.RADIUS
    for dx = -r, r do
        for dy = -r, r do
            if dx * dx + dy * dy <= r * r + 0.5 and growing(plantAt(cx + dx, cy + dy, cz)) then crops = crops + 1 end
        end
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
