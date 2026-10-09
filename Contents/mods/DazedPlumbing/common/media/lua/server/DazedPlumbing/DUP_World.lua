--[[ Dazed Utilities: Plumbing -- tanks in the live world (authority only).

     Registers every tank that streams in or is placed, then once a minute:

       LEAKS   a tank below its tier's leak condition loses contents. Counted
               from the world clock since the tank was last settled, so hours
               spent unloaded are paid for the moment it loads again; settled
               at most every SETTLE_HOURS so the save is not rewritten every
               minute.
       RAIN    a water tank with open sky over a square collects rain, and one beside a
               building also catches that roof's runoff (shared with the other tanks there). Live only.
       FIRE    a tank holding something that burns (propane, petrol) with
               flames on or beside its square may ignite: the tank is
               destroyed in an explosion and a fire. Live world only.
]]

require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Downspouts"
require "DazedPlumbing/DUP_TankFluid"

DazedPlumb.World = DazedPlumb.World or {}
local W = DazedPlumb.World
local P, M, D = DazedPlumb.Parts, DazedPlumb.Model, DazedPlumb.Downspouts
local try = P.try

W.SETTLE_HOURS = 1 / 6                 -- ten game minutes
W.MAX_CATCHUP_HOURS = 72
W.tanks = W.tanks or setmetatable({}, { __mode = "k" })
W.spouts = W.spouts or setmetatable({}, { __mode = "k" })

local worldHours = DazedCore.Util.worldHours

local alive = P.alive

function W.register(obj)
    if obj then W.tanks[obj] = true end
end

function W.registerSpout(obj)
    if obj then W.spouts[obj] = true end
end

local function roll(p)
    if p <= 0 then return false end
    local r = ZombRand and ZombRand(1000000) / 1000000 or math.random()
    return r < p
end

--- Flames on this square or any of its eight neighbours.
local function fireNear(squares)
    local cell = getCell and getCell()
    if not cell then return false end
    for _, sq in ipairs(squares) do
        for dx = -1, 1 do
            for dy = -1, 1 do
                local n = cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
                if n and try(n, "haveFire") == true then return true end
            end
        end
    end
    return false
end

local function explode(obj, sq)
    local cell = getCell and getCell()
    if cell and IsoFireManager then
        if IsoFireManager.explode then pcall(IsoFireManager.explode, cell, sq, 100) end
        if IsoFireManager.StartFire then pcall(IsoFireManager.StartFire, cell, sq, true, 100) end
    end
    if addSound then pcall(addSound, obj, sq:getX(), sq:getY(), sq:getZ(), 60, 60) end
    -- The tank is gone: every piece of it.
    local info = P.describe(obj)
    for _, q in ipairs(P.squares(obj)) do
        local objs = try(q, "getObjects")
        local doomed = {}
        if objs then
            for i = 0, objs:size() - 1 do
                local o = objs:get(i)
                local oi = P.describe(o)
                if oi and info and oi.size == info.size and oi.type == info.type
                        and oi.tier == info.tier and oi.facing == info.facing then
                    doomed[#doomed + 1] = o
                end
            end
        end
        for _, o in ipairs(doomed) do
            pcall(function()
                if q.transmitRemoveItemFromSquare then q:transmitRemoveItemFromSquare(o) end
                if q.RemoveTileObject then q:RemoveTileObject(o) end
            end)
        end
    end
end

--- Settle one tank. `live` is false for a load-time catch-up (no fire).
local function settle(obj, now, live, rain)
    if not alive(obj) then return false end
    local sq = try(obj, "getSquare")
    if not sq then return false end
    local d = P.data(obj)
    local gap = now - (d.lastHour or now)
    if gap < 0 or gap > W.MAX_CATCHUP_HOURS then gap = math.min(math.max(gap, 0), W.MAX_CATCHUP_HOURS) end
    local changed = false
    if gap >= W.SETTLE_HOURS then
        local lost = M.leak(d, gap)
        d.lastHour = now
        local leaking = M.isLeaking(d) or nil
        if lost > 0 or leaking ~= d.leaking then changed = true end
        d.leaking = leaking
    elseif d.lastHour == nil then
        d.lastHour = now
    end
    if live and (d.amount or 0) > 0 and M.FLAMMABLE[d.type] and fireNear(P.squares(obj)) then
        if roll(M.fireChance(d, 1)) then
            explode(obj, sq)
            return false
        end
    end
    -- Rain on a water tank: from open sky over it, and runoff from a building beside it
    -- (live minutes only; rain while unloaded is not known).
    if live and d.type == "water" then
        local catching = nil
        if rain and rain.intensity > 0.05 then
            local gain, open = 0, 0
            for _, q in ipairs(P.squares(obj)) do
                if try(q, "isOutside") == true then open = open + 1 end
            end
            if open > 0 then
                gain = M.rainGain(d, open, rain.intensity, 1 / 60)
                if gain > 0 then catching = "sky" end
                local b = W.roofOf(obj)
                local info = b and rain.roofs[b]
                if info then
                    gain = gain + M.runoffGain(d, info.squares, rain.intensity, 1 / 60, info.catchers)
                    catching = "roof"
                end
            end
            if M.addWater(d, gain, false) > 0 then changed = true end
        end
        if catching ~= d.catching then d.catching, changed = catching, true end
    end
    -- the game's Fluid menu, drinking and washing work on the tank's container: take in what they did, then rewrite it
    -- (live minutes only: a chunk still loading is no place to attach a component)
    if live then
        local okF, err = pcall(DazedPlumb.TankFluid.reconcile, obj)
        if not okF then print("DazedPlumbing: tank fluid sync failed: " .. tostring(err)) end
    end
    if changed then obj:transmitModData() end
    return true
end

--- The building whose roof drains to this tank: one standing on a square next to a tank
--  square, with the tank itself outside. Returns the building, or nil.
-- Buildings do not move: each tank's answer is kept for an in-game hour (weak keys, so lifted tanks drop out).
local roofMemo = setmetatable({}, { __mode = "k" })

function W.roofOf(obj)
    local now = worldHours()
    local hit = roofMemo[obj]
    if hit and now - hit.at < 1 then return hit.b or nil end
    local b = W.findRoof(obj)
    roofMemo[obj] = { b = b or false, at = now }
    return b
end

function W.findRoof(obj)
    local cell = getCell and getCell()
    if not cell then return nil end
    for _, q in ipairs(P.squares(obj)) do
        if try(q, "isOutside") == true and not try(q, "getBuilding") then
            for dx = -1, 1 do
                for dy = -1, 1 do
                    local n = cell:getGridSquare(q:getX() + dx, q:getY() + dy, q:getZ())
                    local b = n and try(n, "getBuilding")
                    if b then return b end
                end
            end
        end
    end
    return nil
end

--- Roof squares of a building (its floor plan's width x depth), a rough size.
local function roofSquares(b)
    local def = try(b, "getDef")
    local w, h = def and try(def, "getW"), def and try(def, "getH")
    if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then return math.min(w * h, 400) end
    return 25
end

--- A downspout takes its share of its building's roof into its buffer. Returns false once it is gone.
function W.settleSpout(obj, rain)
    if not alive(obj) then return false end
    if rain.intensity > 0.05 then
        local b = D.building(obj)
        local info = b and rain.roofs[b]
        if info then
            D.fill(obj, M.runoffShare(info.squares, rain.intensity, 1 / 60, info.catchers, M.DOWNSPOUT_MAX_PER_HOUR))
        end
    end
    return true
end

--- How hard it is raining, 0..1.
local function rainNow()
    local cm = getClimateManager and getClimateManager()
    local r = cm and try(cm, "getRainIntensity")
    return type(r) == "number" and r or 0
end

function W.tick()
    if isClient and isClient() then return end            -- only the authority changes tanks
    local now = worldHours()
    local rain = { intensity = rainNow(), roofs = {} }
    if rain.intensity > 0.05 then
        -- tanks beside the same building share its roof
        for obj in pairs(W.tanks) do
            local d = alive(obj) and P.data(obj)
            local b = d and d.type == "water" and W.roofOf(obj)
            if b then
                local r = rain.roofs[b]
                if not r then r = { squares = roofSquares(b), catchers = 0 } rain.roofs[b] = r end
                r.catchers = r.catchers + 1
            end
        end
    end
    if rain.intensity > 0.05 then
        for obj in pairs(W.spouts) do
            if alive(obj) then
                local b = D.building(obj)
                if b then
                    local r = rain.roofs[b]
                    if not r then r = { squares = roofSquares(b), catchers = 0 } rain.roofs[b] = r end
                    r.catchers = r.catchers + 1
                end
            end
        end
    end
    for obj in pairs(W.spouts) do
        local ok, keep = pcall(W.settleSpout, obj, rain)
        if not ok then print("DazedPlumbing: downspout tick failed: " .. tostring(keep)) end
        if not ok or not keep then W.spouts[obj] = nil end
    end
    for obj in pairs(W.tanks) do
        local ok, keep = pcall(settle, obj, now, true, rain)
        if not ok then print("DazedPlumbing: tank tick failed: " .. tostring(keep)) end
        if not ok or not keep then W.tanks[obj] = nil end
    end
end

local function onLoadTank(obj)
    local info = P.describe(obj)
    if info and not info.master then return end     -- only the master piece is ticked
    if isClient and isClient() then return end      -- a client takes what the server sends
    W.register(obj)
    pcall(settle, obj, worldHours(), false)        -- leaks since it was last loaded; no fire
end

local function onLoadSpout(obj)
    if isClient and isClient() then return end
    W.registerSpout(obj)
end

local function registerSprites()
    local PRIORITY = 6
    for n = D.BASE, D.BASE + D.COUNT - 1 do
        local name = P.TILESET .. "_" .. n
        MapObjects.OnLoadWithSprite(name, onLoadSpout, PRIORITY)
        MapObjects.OnNewWithSprite(name, onLoadSpout, PRIORITY)
    end
    for n = 0, P.TILE_COUNT - 1 do
        local name = P.TILESET .. "_" .. n
        MapObjects.OnLoadWithSprite(name, onLoadTank, PRIORITY)
        MapObjects.OnNewWithSprite(name, onLoadTank, PRIORITY)
    end
end

-- Registered at file load AND on game start (OnLoadWithSprite at equal
-- priority replaces, so it is idempotent): the login area's chunks stream in
-- during the loading screen, before OnGameStart.
registerSprites()
Events.OnGameStart.Add(registerSprites)
Events.OnServerStarted.Add(registerSprites)
Events.EveryOneMinute.Add(W.tick)
