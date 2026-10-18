--[[ Dazed Plumbing -- the sprinkler's spray turning round, on screen (0.18.0).

     A spraying sprinkler near a local player and on screen walks the spray cycle: SPRAY_FRAMES sprites
     (DUP_Sprinklers: 264 + frame * 4 + facing) of the head and its jet across a half circle in front of it,
     played there and back (0..7, 6..1) at 6 frames a second, like an impact sprinkler's sweep. Purely cosmetic
     and only on this machine, like Dazed Power's machine effects (DP_MachineFx): nothing is sent, nothing is
     written to ModData, and the server keeps the plain spraying sprite clients sync from. Every frame sprite
     reads back as spraying in its facing, so the menus, the network and the watering never notice. When the
     server sets the idle sprite (switched off, nothing to water, out of hours), the cycle stops on its own.

     Cost. Nothing while no sprinkler is loaded. Sprinklers come from MapObjects as chunks stream in, from
     OnObjectAdded, and from a slow sweep round each local player for anything no event announced. Two Dazed
     Core Tick jobs, each present only while it has work:
       DazedPlumbing.sprinklerfx        once a second while any sprinkler is tracked: drops the ones that left,
                                        keeps the spraying ones within RANGE squares and on screen.
       DazedPlumbing.sprinklerfxFrames  every FRAME_MS while one of those is on screen: one sprite swap each.
     Both stand still while single player is paused. A culled sprinkler keeps the frame it shows.

     Sandbox: Animate sprinklers (DazedPlumb.SprinklerAnimation, on). Off puts every plain sprite back. ]]

require "DazedCore/DC_Tick"
require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Sprinklers"

DazedPlumb = DazedPlumb or {}
DazedPlumb.SprinklerFx = DazedPlumb.SprinklerFx or {}
local F = DazedPlumb.SprinklerFx
local P, Z = DazedPlumb.Parts, DazedPlumb.Sprinklers
local try = P.try

F.RANGE = 25                 -- squares from a local player (either axis)
F.FLOORS = 2                 -- and floors above or below
F.SCAN_MS = 1000
F.FRAME_MS = 167             -- one frame (6 a second): a sweep there and back in #CYCLE * FRAME_MS
F.SWEEP_MS = 10000           -- real time between the fallback sweeps
F.SWEEP_RADIUS = 18          -- squares round each local player the sweep reads
F.PRIORITY = 7               -- not 6: DUP_Sprinklers' own loader uses 6, and equal priorities replace in single player
F.SCAN_ID, F.FRAME_ID, F.SWEEP_ID = "DazedPlumbing.sprinklerfx", "DazedPlumbing.sprinklerfxFrames", "DazedPlumbing.sprinklerfxSweep"

F.tracked = F.tracked or {}  -- object -> entry { obj, offset, f, spr }
F.count = F.count or 0       -- entries in tracked (Kahlua has no next)
F.active = F.active or {}    -- entries cycling now (spraying, near, on screen)
F.scanJob, F.frameJob = F.scanJob or false, F.frameJob or false
F.shown = F.shown or false   -- whether any frame may be on show (for the option going off)

local spriteObjs = {}        -- sprite name -> IsoSprite (false: none)

------------------------------------------------------------------ small parts

local function paused()
    local ok, v = pcall(function() return isGamePaused and isGamePaused() end)
    if ok and v then return true end
    ok, v = pcall(function() return getGameSpeed and getGameSpeed() end)
    return ok and v == 0
end
F.paused = paused

--- The sandbox option; on unless switched off.
function F.enabled()
    local sv = SandboxVars and SandboxVars.DazedPlumb
    return not (sv and sv.SprinklerAnimation == false)
end

local function spriteObj(name)
    local s = spriteObjs[name]
    if s == nil then
        s = getSprite and getSprite(name) or false
        spriteObjs[name] = s or false
    end
    return s or nil
end

-- Show a sprite on this machine only (no transmit); false when it already shows it or the sprite is unknown.
local function show(obj, name)
    if not name then return false end
    local cur = try(obj, "getSprite")
    if cur and cur:getName() == name then return false end
    local s = spriteObj(name)
    if not s then return false end
    return (pcall(obj.setSprite, obj, s))
end
F.show = show

-- The sweep: frames 0..last, then back down to 1, so the head goes there and back without stopping twice.
F.CYCLE = {}
for k = 0, Z.SPRAY_FRAMES - 1 do F.CYCLE[#F.CYCLE + 1] = k end
for k = Z.SPRAY_FRAMES - 2, 1, -1 do F.CYCLE[#F.CYCLE + 1] = k end

--- The frame a sprinkler shows at time t (ms), staggered by its offset so neighbours do not sweep in step.
function F.frameAt(t, offset)
    return F.CYCLE[math.floor(t / F.FRAME_MS + (offset or 0)) % #F.CYCLE + 1]
end

local function info(obj)
    local spr = try(obj, "getSprite")
    return spr and Z.spriteInfo(spr:getName()) or nil
end

------------------------------------------------------------------ jobs

local function setFrameJob(on)
    if on == F.frameJob then return end
    F.frameJob = on
    if on then DazedCore.Tick.every(F.FRAME_ID, F.FRAME_MS, function(t) F.frames(t) end)
    else DazedCore.Tick.remove(F.FRAME_ID) end
end

local function forget(obj)
    if not F.tracked[obj] then return end
    F.tracked[obj] = nil
    F.count = F.count - 1
end

-- Put the plain spraying sprite back on one sprinkler showing a frame.
local function restoreOne(obj)
    local i = P.alive(obj) and info(obj)
    if i and i.frame ~= nil then show(obj, Z.sprite(i.facing, true)) end
end

--- Plain sprites back on every tracked sprinkler (the option went off).
function F.restoreAll()
    for obj, e in pairs(F.tracked) do
        restoreOne(obj)
        e.f, e.spr = nil, nil
    end
    F.active = {}
    setFrameJob(false)
end

local playerList = {}
local function localPlayers()
    local n = 0
    for i = 0, (getNumActivePlayers and getNumActivePlayers() or 0) - 1 do
        local p = getSpecificPlayer(i)
        if p and not p:isDead() then n = n + 1 playerList[n] = p end
    end
    for i = n + 1, #playerList do playerList[i] = nil end
    return playerList, n
end

local function nearAny(e, players, np)
    for i = 1, np do
        local p = players[i]
        if math.abs(p:getX() - e.x) <= F.RANGE and math.abs(p:getY() - e.y) <= F.RANGE
                and math.abs(p:getZ() - e.z) <= F.FLOORS then
            return true
        end
    end
    return false
end

local function onScreen(sq)
    local v = try(sq, "IsOnScreen")
    if v == nil then return true end            -- no such call: take it as seen
    return v == true
end

--- The once-a-second pass. Public for the tests.
function F.scan()
    if F.count == 0 then
        DazedCore.Tick.remove(F.SCAN_ID); F.scanJob = false
        setFrameJob(false)
        return
    end
    if not F.enabled() then
        if F.shown then F.restoreAll() end
        F.shown = false
        return
    end
    if paused() then return end
    local players, np = localPlayers()
    local active, na = F.active, 0
    for obj, e in pairs(F.tracked) do
        local i = P.alive(obj) and info(obj)
        if not i then
            forget(obj)
        elseif i.spraying and np > 0 and nearAny(e, players, np) and onScreen(obj:getSquare()) then
            e.facing = i.facing
            na = na + 1
            active[na] = e
        end
    end
    for k = na + 1, #active do active[k] = nil end
    setFrameJob(na > 0)
end

--- One frame step for every active sprinkler. Public for the tests.
function F.frames(t)
    if paused() then return end
    t = t or (getTimestampMs and getTimestampMs() or 0)
    local active, keep = F.active, 0
    for k = 1, #active do
        local e = active[k]
        local obj = e.obj
        local cur = try(obj, "getSprite")
        local live = cur ~= nil
        if live and cur ~= e.spr then
            -- Not the sprite we put there: the server's change (idle) or a new facing; follow it or stop.
            local i = Z.spriteInfo(cur:getName())
            live = i ~= nil and i.spraying
            if live then e.facing = i.facing end
            e.f = nil
        end
        if live then
            local f = F.frameAt(t, e.offset)
            if f ~= e.f then
                e.f = f
                show(obj, Z.frameSprite(e.facing, f))
                F.shown = true
            end
            e.spr = try(obj, "getSprite")
            keep = keep + 1
            active[keep] = e
        end
    end
    for k = keep + 1, #active do active[k] = nil end
    if keep == 0 then setFrameJob(false) end
end

------------------------------------------------------------------ tracking

--- Start following an object if it is a sprinkler.
function F.consider(obj)
    if not obj or F.tracked[obj] or not info(obj) then return end
    local sq = try(obj, "getSquare")
    if not sq then return end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    F.tracked[obj] = { obj = obj, x = x, y = y, z = z, offset = (x * 7 + y * 13) % #F.CYCLE }
    F.count = F.count + 1
    if not F.scanJob then
        F.scanJob = true
        DazedCore.Tick.every(F.SCAN_ID, F.SCAN_MS, function() F.scan() end)
    end
end

--- Read the squares round every local player for sprinklers no event announced. Public for the tests.
function F.sweep()
    local cell = getCell and getCell()
    if not cell then return end
    local players, np = localPlayers()
    local r = F.SWEEP_RADIUS
    for i = 1, np do
        local p = players[i]
        local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
        for x = px - r, px + r do
            for y = py - r, py + r do
                local sq = cell:getGridSquare(x, y, pz)
                local objs = sq and sq:getObjects()
                if objs then
                    for k = 0, objs:size() - 1 do F.consider(objs:get(k)) end
                end
            end
        end
    end
end

function F.onRemoved(obj)
    if obj and F.tracked[obj] then forget(obj) end
end

--- Forget everything (a new game: the old cell is gone).
function F.reset()
    F.tracked, F.count, F.active, F.shown = {}, 0, {}, false
    DazedCore.Tick.remove(F.SCAN_ID); DazedCore.Tick.remove(F.FRAME_ID)
    F.scanJob, F.frameJob = false, false
end

if Events and not F.hooked then
    F.hooked = true
    if MapObjects and MapObjects.OnLoadWithSprite then
        for n = 0, Z.COUNT - 1 do MapObjects.OnLoadWithSprite(P.TILESET .. "_" .. (Z.BASE + n), F.consider, F.PRIORITY) end
    end
    if Events.OnObjectAdded then Events.OnObjectAdded.Add(F.consider) end
    if Events.OnObjectAboutToBeRemoved then Events.OnObjectAboutToBeRemoved.Add(F.onRemoved) end
    if Events.OnGameStart then
        -- No reset here: the login area streams in (and is tracked) before OnGameStart.
        Events.OnGameStart.Add(function() DazedCore.Tick.every(F.SWEEP_ID, F.SWEEP_MS, function() F.sweep() end) end)
    end
end

return F
