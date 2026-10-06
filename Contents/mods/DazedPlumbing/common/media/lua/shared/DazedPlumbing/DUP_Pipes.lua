--[[ Dazed Utilities: Plumbing -- pipes in the world.

     The data model (records, joins, networks) is DUP_Net; this file puts it
     on the map. A pipe is a plain world object that never blocks movement:
     OVERHEAD indoors, ON THE GROUND outdoors, decided per square. Its sprite
     shows which neighbours it joins (a 4-bit mask: N=1 E=2 S=4 W=8, 16 shapes,
     times 2 for overhead/ground = 32 sprites, dazedplumb_01_144..175):
         index = 144 + (outdoor and 16 or 0) + mask
     The fluid is shown by a TINT on the object (water blue, petrol red,
     propane white). A VALVE is its own small untinted object on the square
     (a brass ball valve, dazedplumb_01_196..203): its red lever runs along the
     pipe when open and across it when closed.

     Pipes form NETWORKS: a new pipe that ends next to a pipe of the same fluid
     (or at the tank that pipe serves) joins it, so one line serves several
     machines. Only the authority changes pipes; clients read the synced table.

     DAMAGE (authority, once a minute): an OUTDOOR pipe loses condition while a
     zombie or a vehicle is on its square; at 0 it breaks (object gone, record
     kept so it can be mended). A player can also cut, mend and fit valves.
]]

require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Net"
require "DazedPlumbing/DUP_Sync"

DazedPlumb.Pipes = DazedPlumb.Pipes or {}
local K = DazedPlumb.Pipes
local P, N, S = DazedPlumb.Parts, DazedPlumb.Net, DazedPlumb.Sync
local try = P.try

K.BASE = P.TILE_COUNT              -- first pipe sprite (after the tanks)
K.COUNT = 32
K.VALVE_BASE = 196                 -- valve sprites: +4 overhead, +2 north-south, +1 closed
K.VALVE_COUNT = 8
K.PORT_BASE = 216                  -- a pipe's last stretch on a device's square: + belly*8 + overhead*4 + side (N, E, S, W)
K.PORT_COUNT = 16
K.MAX_LEN = 40                     -- longest new run, in squares
K.SEARCH = 30                      -- how far from the device the router may wander
K.ROUTE_BUDGET = 2500              -- most squares one route search may look at before giving up
K.ZOMBIE_DAMAGE = 4                -- condition lost per minute per zombie on the square
K.VEHICLE_DAMAGE = 25              -- ... per vehicle
K.KEY = "DazedPlumbNet"
K.ITEM = "Base.DazedPipeSection"   -- one per square laid or mended
K.VALVE_ITEM = "Base.DazedValve"
K.REFUND = 0.5                     -- share of sections handed back when a pipe is lifted
K.WELD_LEVEL = 1                   -- Welding level needed to lay, mend or fit pipe
-- Match the tank barrels: water blue, propane white, petrol red.
K.COLORS = { water = { 0.30, 0.60, 1.00 }, gas = { 0.88, 0.18, 0.18 }, propane = { 0.96, 0.96, 0.96 } }

K.blockers = {}                    -- predicates: objects a pipe must not share a square with
function K.addBlocker(fn) K.blockers[#K.blockers + 1] = fn end

----------------------------------------------------------- sprites
function K.sprite(mask, outdoor)
    return P.TILESET .. "_" .. (K.BASE + (outdoor and 16 or 0) + (mask or 0))
end

--- Is this one of our pipe sprites?  Returns outdoor?, mask or nil.
function K.spriteInfo(name)
    local idx = type(name) == "string" and string.match(name, "^" .. P.TILESET .. "_(%d+)$")
    idx = idx and tonumber(idx)
    if not idx or idx < K.BASE or idx >= K.BASE + K.COUNT then return nil end
    local n = idx - K.BASE
    return n >= 16, n % 16
end

function K.isPipe(obj)
    local spr = try(obj, "getSprite")
    local name = spr and try(spr, "getName")
    return K.spriteInfo(name) ~= nil
end

--- The colour a record is drawn in. The valve object shows the valve; a closed one also dims its square a little.
function K.colorOf(rec)
    local c = K.COLORS[rec and rec.f or ""] or { 1, 1, 1 }
    if rec and rec.valve == "closed" then return { c[1] * 0.6, c[2] * 0.6, c[3] * 0.6 } end
    return c
end

----------------------------------------------------------- valve objects
local function has(mask, bit) return math.floor((mask or 0) / bit) % 2 == 1 end

--- The valve sprite a record should show, or nil. It lies along the straight-through
--  pair of a run if there is one, else along the first arm's axis.
function K.valveSprite(rec)
    if not (rec and rec.valve) or rec.virtual or (rec.cond or 100) <= 0 then return nil end
    local m = rec.mask or 0
    local ns
    if has(m, 2) and has(m, 8) then ns = false
    elseif has(m, 1) and has(m, 4) then ns = true
    else ns = has(m, 1) or has(m, 4) end
    local idx = K.VALVE_BASE + (rec.outdoor and 0 or 4) + (ns and 2 or 0) + (rec.valve == "closed" and 1 or 0)
    return P.TILESET .. "_" .. idx
end

function K.isValve(obj)
    local spr = try(obj, "getSprite")
    local name = spr and try(spr, "getName")
    local idx = type(name) == "string" and string.match(name, "^" .. P.TILESET .. "_(%d+)$")
    idx = idx and tonumber(idx)
    return idx ~= nil and idx >= K.VALVE_BASE and idx < K.VALVE_BASE + K.VALVE_COUNT
end

function K.tint(obj, rec)
    local c = K.colorOf(rec)
    if not pcall(obj.setCustomColor, obj, c[1], c[2], c[3], 1.0) then
        if ColorInfo and ColorInfo.new then pcall(obj.setCustomColor, obj, ColorInfo.new(c[1], c[2], c[3], 1.0)) end
    end
end

----------------------------------------------------------- the records
local function store()
    if not ModData then return { pipes = {} } end
    local t = ModData.getOrCreate(K.KEY)
    t.pipes = t.pipes or {}
    return t
end

function K.pipes() return store().pipes end
function K.touch(now) S.touch(K.KEY, now) end
function K.record(x, y, z) return store().pipes[N.key(x, y, z)] end

--- Cached index of ends, rebuilt when a synced table changed.
local cache = { v = -1 }
function K.index()
    if cache.v ~= S.version then
        cache.idx = N.index(store().pipes)
        cache.v = S.version
    end
    return cache.idx
end

--- The working components holding an end string (a device's tie to the network).
-- Answers per end string, kept until the pipes change (menus and the gauge ask often).
local ofCache = { v = -1, map = {} }

function K.componentsOf(endStr)
    if ofCache.v ~= S.version or ofCache.pipes ~= store().pipes then
        ofCache = { v = S.version, pipes = store().pipes, map = {} }
    end
    local hit = ofCache.map[endStr]
    if hit then return hit end
    local out = K.componentsOfUncached(endStr)
    ofCache.map[endStr] = out
    return out
end

function K.componentsOfUncached(endStr)
    local pipes, out = store().pipes, {}
    local keys = K.index()[endStr]
    local seen = {}
    for _, k in ipairs(keys or {}) do
        if not seen[k] then
            local c = N.component(pipes, k, false)
            if c then
                for _, ck in ipairs(c.keys) do seen[ck] = true end
                c.ends = N.endsOf(pipes, c)
                out[#out + 1] = c
            end
            seen[k] = true
        end
    end
    return out
end

----------------------------------------------------------- routing
--- Cheapest route over free squares from next to `from` to a square next to any of the `targets`
--  (a set keyed "x,y"). `free(x, y, px, py)` says whether a pipe may lie on (x,y) coming from (px,py);
--  `cost(x, y)` (optional, 1..3) lets a run prefer some squares. Returns the new squares {x,y}...
--  (EMPTY when `from` already touches a target) or nil.
function K.route(from, targets, free, cost)
    local function adjacentToTarget(x, y)
        for _, d in ipairs(N.DIRS) do
            if targets[(x + d[1]) .. "," .. (y + d[2])] then return true end
        end
        return false
    end
    if adjacentToTarget(from.x, from.y) then return {} end
    local start = from.x .. "," .. from.y
    -- Dijkstra over small whole costs: one bucket per total cost
    local came, best, buckets = { [start] = false }, { [start] = 0 }, { [0] = { { x = from.x, y = from.y, len = 0 } } }
    local looked, at, last = 0, 0, 0
    while at <= last and looked <= K.ROUTE_BUDGET do
        local bucket = buckets[at]
        local i = 1
        while bucket and i <= #bucket and looked <= K.ROUTE_BUDGET do
            local cur = bucket[i]
            i = i + 1
            local ck = cur.x .. "," .. cur.y
            if best[ck] == at then
                looked = looked + 1
                if ck ~= start and adjacentToTarget(cur.x, cur.y) then
                    local path, k = {}, ck
                    while k and k ~= start do
                        local x, y = string.match(k, "(%-?%d+),(%-?%d+)")
                        table.insert(path, 1, { x = tonumber(x), y = tonumber(y) })
                        k = came[k]
                    end
                    return path
                end
                if cur.len < K.MAX_LEN then
                    for _, d in ipairs(N.DIRS) do
                        local nx, ny = cur.x + d[1], cur.y + d[2]
                        local key = nx .. "," .. ny
                        if not targets[key] and math.abs(nx - from.x) <= K.SEARCH and math.abs(ny - from.y) <= K.SEARCH then
                            local step = cost and cost(nx, ny) or 1
                            local nd = at + step
                            if (best[key] == nil or nd < best[key]) and free(nx, ny, cur.x, cur.y) then
                                best[key], came[key] = nd, ck
                                buckets[nd] = buckets[nd] or {}
                                table.insert(buckets[nd], { x = nx, y = ny, len = cur.len + 1 })
                                if nd > last then last = nd end
                            end
                        end
                    end
                end
            end
        end
        at = at + 1
    end
    return nil
end

----------------------------------------------------------- the world
local function cellSquare(x, y, z)
    local cell = getCell and getCell()
    return cell and cell:getGridSquare(x, y, z) or nil
end

--- May a pipe lie on (x,y,z), coming from (px,py)? Standing floor, nothing
--  solid, no other pipe, no device, and no wall or closed door between.
--- Does anything standing on the square keep a pipe off it? (Asked once per square per memo window.)
-- Ground cover and crops never keep a pipe off a square: an outdoor pipe lies between the rows.
local function groundCover(o)
    local name = try(o, "getSpriteName")
    if type(name) ~= "string" or string.find(name, "trees", 1, true) then return false end
    return string.find(name, "^vegetation_") ~= nil or string.find(name, "^blends_") ~= nil or string.find(name, "^floors_") ~= nil
end

--- Does anything standing on the square keep a pipe off it? Returns clear and, when not, what blocked it.
local function squareClear(sq)
    if try(sq, "isSolid") == true then return false, "solid" end
    local objs = try(sq, "getObjects")
    local solidTrans = try(sq, "isSolidTrans") == true
    local transFromOther = false
    if objs then
        for i = 0, objs:size() - 1 do
            local o = objs:get(i)
            if not groundCover(o) then
                if P.describe(o) then return false, "tank" end
                if K.isPipe(o) then return false, "pipe" end
                for _, f in ipairs(K.blockers) do
                    local ok, yes = pcall(f, o)
                    if ok and yes then return false, "device " .. tostring(try(o, "getSpriteName")) end
                end
                if solidTrans and (P.propIs(o, "solidtrans") or (IsoFlagType and P.propIs(o, IsoFlagType.solidtrans))) then
                    transFromOther = true
                end
            end
        end
    end
    -- a square only "solid-trans" because of a crop or a bush is still clear
    if solidTrans and transFromOther then return false, "solidtrans" end
    return true
end
K.squareClear = squareClear

-- One menu plans a route to every tank in reach, and each search asks the same squares again,
-- so a square's answer is kept for a moment (the blocker checks are the slow part).
local memo, memoAt = {}, -1
local MEMO_MS = 400

function K.freeSquare(x, y, z, px, py)
    local sq = cellSquare(x, y, z)
    if not sq then return false end
    local key = N.key(x, y, z)
    if store().pipes[key] then return false end
    local now = getTimestampMs and getTimestampMs() or 0
    if now - memoAt > MEMO_MS or now < memoAt then memo, memoAt = {}, now end
    local clear = memo[key]
    if clear == nil then
        clear = squareClear(sq)
        memo[key] = clear
    end
    if not clear then return false end
    local from = px and cellSquare(px, py, z)
    if from and try(from, "isBlockedTo", sq) == true then return false end
    return true
end

--- What a square costs a run: indoors a pipe keeps to the walls (1 beside one, 3 out in the room); outdoors all cost 1.
local wallMemo, wallAt = {}, -1
function K.stepCost(x, y, z)
    local now = getTimestampMs and getTimestampMs() or 0
    if now - wallAt > MEMO_MS or now < wallAt then wallMemo, wallAt = {}, now end
    local key = N.key(x, y, z)
    local c = wallMemo[key]
    if c == nil then
        c = 1
        local sq = cellSquare(x, y, z)
        if sq and try(sq, "isOutside") ~= true then
            c = 3
            for _, d in ipairs(N.DIRS) do
                local nb = cellSquare(x + d[1], y + d[2], z)
                if not nb or try(sq, "isBlockedTo", nb) == true or try(nb, "isSolid") == true then c = 1 break end
            end
        end
        wallMemo[key] = c
    end
    return c
end

--- Forget the memo (after laying or lifting something).
function K.forgetSquares() memo, memoAt = {}, -1 end

--- Work out a run from a device to a target (a tank or a node) of `fluid`.
--  `devSq` is the device's square; `squares` the target's squares; `role`/`id`
--  how the target is held ("tank"/"tank", "node"/<node id>). The run ends at
--  the target or at any pipe already serving it, so lines merge. Returns a
--  plan { path, z, from, tail } or nil.
function K.plan(devSq, fluid, squares, role, id)
    if not devSq then return nil end
    local z = devSq:getZ()
    local pipes, idx = store().pipes, K.index()
    local devTargets, pipeTargets = {}, {}
    for _, q in ipairs(squares or {}) do
        if q:getZ() == z then
            devTargets[q:getX() .. "," .. q:getY()] = true
            for _, pk in ipairs(idx[N.endString(N.key(q:getX(), q:getY(), z), role, id)] or {}) do
                local c = N.component(pipes, pk, true)
                if c then
                    for _, ck in ipairs(c.keys) do
                        local x, y, cz = N.split(ck)
                        if cz == z and pipes[ck].f == fluid then pipeTargets[x .. "," .. y] = true end
                    end
                end
            end
        end
    end
    local anyTarget = false
    for _ in pairs(devTargets) do anyTarget = true break end      -- Kahlua has no next()
    if not anyTarget then return nil end
    local all = {}
    for k in pairs(devTargets) do all[k] = true end
    for k in pairs(pipeTargets) do all[k] = true end
    local from = { x = devSq:getX(), y = devSq:getY() }
    local own = from.x .. "," .. from.y
    local path = K.route(from, all, function(x, y, px, py)
        if (x .. "," .. y) == own then return false end
        return K.freeSquare(x, y, z, px, py)
    end, function(x, y) return K.stepCost(x, y, z) end)
    if not path then return nil end
    local last = path[#path] or from
    local tail
    for _, d in ipairs(N.DIRS) do
        local tx, ty = last.x + d[1], last.y + d[2]
        if devTargets[tx .. "," .. ty] then tail = { x = tx, y = ty, kind = "dev" } break end
    end
    if not tail then
        for _, d in ipairs(N.DIRS) do
            local tx, ty = last.x + d[1], last.y + d[2]
            if pipeTargets[tx .. "," .. ty] then tail = { x = tx, y = ty, kind = "pipe" } break end
        end
    end
    if not tail then return nil end
    return { path = path, z = z, from = from, tail = tail, fluid = fluid }
end

--- The pipe object standing on a square, or nil.
function K.objectAt(x, y, z)
    local sq = cellSquare(x, y, z)
    local objs = sq and try(sq, "getObjects")
    if objs then
        for i = 0, objs:size() - 1 do
            local o = objs:get(i)
            if K.isPipe(o) then return o, sq end
        end
    end
    return nil, sq
end

--- The valve object standing on a square, or nil.
function K.valveAt(x, y, z)
    local sq = cellSquare(x, y, z)
    local objs = sq and try(sq, "getObjects")
    if objs then
        for i = 0, objs:size() - 1 do
            local o = objs:get(i)
            if K.isValve(o) then return o, sq end
        end
    end
    return nil, sq
end

local function transmitNew(obj)
    if obj.transmitCompleteItemToClients then pcall(obj.transmitCompleteItemToClients, obj) end
end

local function lift(o, sq)
    if o and sq then
        pcall(function()
            if sq.transmitRemoveItemFromSquare then sq:transmitRemoveItemFromSquare(o) end
            if sq.RemoveTileObject then sq:RemoveTileObject(o) end
        end)
    end
end

local function removeObject(x, y, z)
    lift(K.objectAt(x, y, z))
    lift(K.valveAt(x, y, z))
    if K.syncPortsAround then K.syncPortsAround(x, y, z) end
end

--- The joins a pipe square is drawn with: its own, plus an arm toward each device it serves next door
--  (a run laid before a device was moved beside it, or one that ends at a downspout, still reaches it).
function K.displayMask(key, rec)
    local m = rec.mask or 0
    local x, y, z = N.split(key)
    for _, e in ipairs(rec.ends or {}) do
        local ex, ey, ez = N.split(e)
        if ex and ez == z then
            local b = N.bitToward(x, y, ex, ey)
            if b then m = N.addBit(m, b) end
        end
    end
    return m
end

----------------------------------------------------------- ports
-- Where a pipe meets a device, a PORT object on the device's square carries it in: under a large tank and up
-- into its belly, or to a machine's foot; an overhead pipe drops to the ground first.
local SIDES = { [1] = 0, [2] = 1, [4] = 2, [8] = 3 }

function K.portSprite(side, overhead, belly)
    return P.TILESET .. "_" .. (K.PORT_BASE + (belly and 8 or 0) + (overhead and 4 or 0) + SIDES[side])
end

function K.isPort(obj)
    local spr = try(obj, "getSprite")
    local idx = string.match(try(spr, "getName") or "", P.namePattern())
    idx = tonumber(idx)
    return idx ~= nil and idx >= K.PORT_BASE and idx < K.PORT_BASE + K.PORT_COUNT
end

--- The device standing on a square (a tank, machine or tap) and its place in the square's list, or nil.
local function deviceOn(sq)
    local L = DazedPlumb.Links
    local objs = try(sq, "getObjects")
    if not objs then return nil end
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if not K.isPort(o) and (P.describe(o) or (L and (L.adapterFor(o) or L.nodeOf(o)))) then return o, i end
    end
    return nil
end

K.deviceOn = deviceOn

--- The port sprites a device square should carry, as a list (for the debug menu).
function K.wantedPorts(x, y, z)
    local pipes, out = store().pipes, {}
    local sq = cellSquare(x, y, z)
    if not sq or N.isReal(pipes[N.key(x, y, z)]) then return out end
    local dev = deviceOn(sq)
    if not dev then return out end
    local info = P.describe(dev)
    local belly = info ~= nil and info.size ~= "small"
    for _, d in ipairs(N.DIRS) do
        local r = pipes[N.key(x + d[1], y + d[2], z)]
        if N.isReal(r) and (r.cond or 100) > 0 and N.has(K.displayMask(N.key(x + d[1], y + d[2], z), r), d[4]) then
            out[#out + 1] = K.portSprite(d[3], not r.outdoor, belly)
        end
    end
    return out
end

--- Make a device square's port objects agree with the pipes that point into it (authority).
function K.syncPorts(x, y, z)
    if not S.authority() then return end
    local sq = cellSquare(x, y, z)
    if not sq then return end
    local pipes = store().pipes
    local want, wanted = {}, false
    local dev, at = nil, nil
    if not N.isReal(pipes[N.key(x, y, z)]) then dev, at = deviceOn(sq) end
    if dev then
        local info = P.describe(dev)
        local belly = info ~= nil and info.size ~= "small"
        for _, d in ipairs(N.DIRS) do
            local r = pipes[N.key(x + d[1], y + d[2], z)]
            if N.isReal(r) and (r.cond or 100) > 0 and N.has(K.displayMask(N.key(x + d[1], y + d[2], z), r), d[4]) then
                want[K.portSprite(d[3], not r.outdoor, belly)] = r
                wanted = true
            end
        end
    end
    local have, objs = {}, try(sq, "getObjects")
    if objs then for i = 0, objs:size() - 1 do if K.isPort(objs:get(i)) then have[#have + 1] = objs:get(i) end end end
    for _, o in ipairs(have) do
        local name = try(try(o, "getSprite"), "getName")
        if want[name] then K.tint(o, want[name]) want[name] = nil else lift(o, sq) end
    end
    if not wanted then return end
    for name, r in pairs(want) do
        local obj = IsoObject.new(getCell(), sq, name)
        -- below the device in the square's list, so the device is drawn over the part that runs under it
        if at and not pcall(sq.AddTileObject, sq, obj, at) then sq:AddTileObject(obj) elseif not at then sq:AddTileObject(obj) end
        obj:getModData().dazedPort = true
        K.tint(obj, r)
        transmitNew(obj)
    end
end

--- The ports on the four squares around a pipe square.
function K.syncPortsAround(x, y, z)
    for _, d in ipairs(N.DIRS) do K.syncPorts(x + d[1], y + d[2], z) end
end

--- Make a square's valve object agree with its record (authority).
function K.syncValve(x, y, z, rec)
    local want = K.valveSprite(rec)
    local obj, sq = K.valveAt(x, y, z)
    if not sq then return end
    if not want then lift(obj, sq) return end
    -- Same as pipes: a valve that turns or changes state is replaced, not re-sprited.
    local cur = obj and try(obj, "getSprite")
    if obj and (not cur or try(cur, "getName") ~= want) then
        lift(obj, sq)
        obj = nil
    end
    if not obj then
        obj = IsoObject.new(getCell(), sq, want)
        sq:AddTileObject(obj)
        obj:getModData().dazedValve = true
        transmitNew(obj)
    end
end

--- Make a square's object agree with its record (create, re-shape or re-tint).
function K.syncObject(key)
    local rec = store().pipes[key]
    local x, y, z = N.split(key)
    if not rec or rec.virtual then return false end
    if (rec.cond or 100) <= 0 then removeObject(x, y, z) return true end
    local obj, sq = K.objectAt(x, y, z)
    local name = K.sprite(K.displayMask(key, rec), rec.outdoor)
    if not sq then return false end
    -- A pipe that changes shape is swapped for a fresh object: re-spriting one in place left it invisible in game.
    local spr = obj and try(obj, "getSprite")
    if obj and (not spr or try(spr, "getName") ~= name) then
        lift(obj, sq)
        lift(K.valveAt(x, y, z))                       -- its valve comes back on top of the new pipe
        obj = nil
    end
    if not obj then
        local cell = getCell and getCell()
        obj = IsoObject.new(cell, sq, name)
        sq:AddTileObject(obj)
        local md = obj:getModData()
        md.dazedPipe = true
        K.tint(obj, rec)
        transmitNew(obj)
        K.syncValve(x, y, z, rec)
        K.syncPortsAround(x, y, z)
        return true
    end
    K.tint(obj, rec)
    K.syncValve(x, y, z, rec)
    K.syncPortsAround(x, y, z)
    return true
end

--- Throw away a square's pipe and valve objects and draw them fresh from the record (debug repair).
function K.redraw(key)
    local x, y, z = N.split(key)
    lift(K.objectAt(x, y, z))
    lift(K.valveAt(x, y, z))
    return K.syncObject(key)
end

--- Redraw every loaded pipe square. Returns how many were redrawn.
function K.redrawAll()
    local n = 0
    for key, rec in pairs(store().pipes) do
        if N.isReal(rec) and K.redraw(key) then n = n + 1 end
    end
    print("DazedPlumbing: redrew " .. n .. " pipe squares")
    return n
end

--- Lay a planned run (authority). devEnd / tailEnd are end strings. Returns true.
function K.lay(plan, devEnd, tailEnd)
    K.forgetSquares()                                   -- the world is about to change under the memo
    local touched = N.layPath(store().pipes, plan.fluid, plan.z, plan.from, plan.path, plan.tail, devEnd, tailEnd,
        function(x, y)
            local sq = cellSquare(x, y, plan.z)
            return sq ~= nil and try(sq, "isOutside") == true
        end)
    for _, k in ipairs(touched) do K.syncObject(k) end
    K.touch(true)
    return true
end

--- Take one device end away and every dead-end square it leaves (authority).
--  Returns the number of undamaged squares removed (the caller refunds them).
function K.disconnect(endStr)
    local pipes = store().pipes
    local changed = N.dropEnd(pipes, endStr)
    local removed, touched = N.prune(pipes)
    local sound = 0
    for _, r in ipairs(removed) do
        local x, y, z = N.split(r.key)
        removeObject(x, y, z)
        if (r.rec.cond or 100) > 0 then sound = sound + 1 end
    end
    for _, k in ipairs(touched) do K.syncObject(k) end
    for _, k in ipairs(changed) do if pipes[k] then K.syncObject(k) end end
    K.touch(true)
    return sound
end

--- Break one square (damage or a deliberate cut): object gone, record kept at 0.
function K.breakAt(x, y, z)
    local r = K.record(x, y, z)
    if not r or r.virtual then return false end
    r.cond = 0
    removeObject(x, y, z)
    K.touch(true)
    return true
end

--- Mend a broken or damaged square.
function K.repairAt(x, y, z)
    local r = K.record(x, y, z)
    if not r or r.virtual then return false end
    r.cond = 100
    K.syncObject(N.key(x, y, z))
    K.touch(true)
    return true
end

--- May a valve be fitted here? A plain run of pipe: two joins, no device end.
function K.canValve(x, y, z)
    local r = K.record(x, y, z)
    if not N.isReal(r) or r.valve then return false end
    if (r.cond or 100) <= 0 then return false, "IGUI_DazedPlumb_ValveBroken" end
    return true
end

function K.setValve(x, y, z, state)
    local r = K.record(x, y, z)
    if not N.isReal(r) then return false end
    r.valve = state
    K.syncObject(N.key(x, y, z))
    K.touch(true)
    return true
end

--- Sound sections in a run, for a cost preview.
function K.cost(plan) return plan and #plan.path or 0 end

--- Wear from what stands on outdoor pipes. Once a minute, authority only.
local wearTicks = 0
function K.tick()
    if not S.authority() then return end
    local pipes, worn = store().pipes, false
    for key, r in pairs(pipes) do
        if N.isReal(r) and r.outdoor and (r.cond or 100) > 0 then
            local x, y, z = N.split(key)
            local sq = cellSquare(x, y, z)
            if sq then
                local hit = 0
                local movers = try(sq, "getMovingObjects")
                if movers then
                    for i = 0, movers:size() - 1 do
                        if instanceof and instanceof(movers:get(i), "IsoZombie") then hit = hit + K.ZOMBIE_DAMAGE end
                    end
                end
                if try(sq, "getVehicleContainer") then hit = hit + K.VEHICLE_DAMAGE end
                if hit > 0 then
                    r.cond = r.cond - hit
                    worn = true
                    if r.cond <= 0 then K.breakAt(x, y, z) end
                end
            end
        end
    end
    -- a device placed beside a pipe end, or lifted from it: its port follows within a minute
    for key, r in pairs(pipes) do
        if N.isReal(r) and (r.cond or 100) > 0 then
            local x, y, z = N.split(key)
            for _, d in ipairs(N.DIRS) do
                if N.has(K.displayMask(key, r), d[3]) and not N.isReal(pipes[N.key(x + d[1], y + d[2], z)]) and cellSquare(x + d[1], y + d[2], z) then
                    K.syncPorts(x + d[1], y + d[2], z)
                end
            end
        end
    end
    if worn then
        wearTicks = wearTicks + 1
        if wearTicks >= 5 then wearTicks = 0 K.touch() end     -- condition reaches clients now and then
    end
end

--- Tint the ports a pipe square feeds (the tint is not always saved with the object).
function K.retintPortsAround(x, y, z, rec)
    local m = K.displayMask(N.key(x, y, z), rec)
    for _, d in ipairs(N.DIRS) do
        if N.has(m, d[3]) then
            local sq = cellSquare(x + d[1], y + d[2], z)
            local objs = sq and try(sq, "getObjects")
            if objs then
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    if K.isPort(o) then K.tint(o, rec) end
                end
            end
        end
    end
end

--- Give the pipes their colour when a chunk loads (the tint is not always saved).
--  The authority also adds a valve object that a save from before 0.9.5 lacks.
local function onLoad(obj)
    local sq = try(obj, "getSquare")
    if not sq then return end
    local rec = K.record(sq:getX(), sq:getY(), sq:getZ())
    if not rec then return end
    K.tint(obj, rec)
    -- a save from before the arm toward a served device was drawn gets it now
    local want = K.sprite(K.displayMask(N.key(sq:getX(), sq:getY(), sq:getZ()), rec), rec.outdoor)
    if S.authority() and try(try(obj, "getSprite"), "getName") ~= want then
        obj:setSprite(want)
        if obj.setSpriteFromName then pcall(obj.setSpriteFromName, obj, want) end
    end
    K.retintPortsAround(sq:getX(), sq:getY(), sq:getZ(), rec)
    if rec.valve and S.authority() and not K.valveAt(sq:getX(), sq:getY(), sq:getZ()) then
        K.syncValve(sq:getX(), sq:getY(), sq:getZ(), rec)
    end
end

--- A client re-tints the loaded pipes when a new copy of the network arrives (a valve shuts, a line is laid).
local function redress(key)
    if key ~= K.KEY or S.authority() then return end
    for k, rec in pairs(store().pipes) do
        local x, y, z = N.split(k)
        local obj = K.objectAt(x, y, z)
        if obj then K.tint(obj, rec) end
        if N.isReal(rec) then K.retintPortsAround(x, y, z, rec) end
    end
end
if Events and Events.OnReceiveGlobalModData then Events.OnReceiveGlobalModData.Add(redress) end
if MapObjects and MapObjects.OnLoadWithSprite then
    for n = 0, K.COUNT - 1 do
        local name = P.TILESET .. "_" .. (K.BASE + n)
        MapObjects.OnLoadWithSprite(name, onLoad, 6)
    end
end

return K
