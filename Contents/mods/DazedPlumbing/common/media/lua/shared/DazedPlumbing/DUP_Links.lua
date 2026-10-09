--[[ Dazed Utilities: Plumbing -- machines and tanks on the pipe networks.

     WHAT A MACHINE IS is an ADAPTER, a small table anyone can register (this
     mod registers pumps, the purifier and water fixtures; Dazed Power
     registers its propane and petrol generators and steam boilers):

       A SINK draws from a network:   supplies, room, put   (+ engage, release, rate)
           supplies  "propane" | "gas" | "water"
           room(obj)             how much it can take right now (tank units)
           put(obj, amt, dirty)  take it (dirty = tainted water); returns what it took
           engage(obj, link)     each minute while fed: link = { tx, ty, tz, source }
                                 names the tank it should draw from
           release(obj)          the line was cut, paused or lost
           rate(obj)             its own most-per-minute, instead of the fluid's (a water main)
       A SOURCE gives to a network:   produces, available, take  (a pump)
           available(obj)        how much it can give now; take(obj, amt) gives it up
           tainted = true        what it gives is tainted water (or a function(obj) -> boolean)
       both:  id, match(obj), label (menu title key)

     A NODE is a placed device a source can pipe into instead of a tank (the
     water purifier): { id, kind, match, room, add, squares }.

     HOW THEY JOIN is DUP_Net: a device holds an END on a pipe square. Every
     minute the authority walks each working network and moves fluid:
         sources -> tanks/nodes (shared by room)   tanks -> sinks (shared evenly)
     A machine's own ModData keeps a small LINK record only for its source
     switch and the tank it is currently pointed at:
         md.dazedplumbLinks[adapterId] = { source = "tank"|"manual", tx, ty, tz }
]]

require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Net"
require "DazedPlumbing/DUP_Pipes"

DazedPlumb.Links = DazedPlumb.Links or {}
local L = DazedPlumb.Links
local P, M, K, N = DazedPlumb.Parts, DazedPlumb.Model, DazedPlumb.Pipes, DazedPlumb.Net
local try = P.try

L.RATE = { propane = 1.0, gas = 2.0, water = 20.0 }   -- most one device moves per minute
L.KEY = "dazedplumbLinks"

L.adapters, L.order = {}, {}

--- Register (or replace, by id) a machine adapter (a sink, a source, or both ways round).
function L.register(a)
    if not (a and a.id and a.match) then return false end
    local sink = a.supplies and a.room and a.put
    local source = a.produces and a.available and a.take
    if not (sink or source) then return false end
    if not L.adapters[a.id] then L.order[#L.order + 1] = a.id end
    L.adapters[a.id] = a
    L.forgetAdapters()
    return true
end

-- What adapter a sprite gets is the same for every object wearing it, so the answer is kept by
-- sprite name (false = none). Objects with no sprite name are always asked afresh.
local byName = {}
function L.forgetAdapters() byName = {} end

function L.kindOf(a) return a and (a.supplies or a.produces) end
function L.roleOf(a) return a.supplies and "sink" or "source" end

--- The adapter for an object, or nil.
local function scan(obj)
    for _, id in ipairs(L.order) do
        local a = L.adapters[id]
        local ok, yes = pcall(a.match, obj)
        if ok and yes then return a end
    end
    return nil
end

function L.adapterFor(obj)
    local spr = obj and obj.getSprite and obj:getSprite()
    local name = spr and spr:getName()
    if type(name) ~= "string" then return scan(obj) end
    local hit = byName[name]
    if hit == nil then
        hit = scan(obj) or false
        byName[name] = hit
    end
    return hit or nil
end

----------------------------------------------------------- nodes
L.nodes, L.nodeOrder = {}, {}

function L.registerNode(n)
    if not (n and n.id and n.kind and n.match and n.room and n.add) then return false end
    if not L.nodes[n.id] then L.nodeOrder[#L.nodeOrder + 1] = n.id end
    L.nodes[n.id] = n
    return true
end

function L.nodeOf(obj)
    for _, id in ipairs(L.nodeOrder) do
        local n = L.nodes[id]
        local ok, yes = pcall(n.match, obj)
        if ok and yes then return n end
    end
    return nil
end

-- a pipe may not share a square with a machine, a pump or a node
K.addBlocker(function(o) return L.adapterFor(o) ~= nil or L.nodeOf(o) ~= nil end)

----------------------------------------------------------- the stored links
local function registry()
    if not ModData then return { links = {} } end
    local t = ModData.getOrCreate("DazedPlumbLinks")
    t.links = t.links or {}
    return t
end

local function squareOf(obj) return try(obj, "getSquare") end

function L.devKey(obj)
    local sq = squareOf(obj)
    return sq and N.key(sq:getX(), sq:getY(), sq:getZ()) or nil
end

--- The end string that ties a machine to a network under an adapter.
function L.endFor(machine, adapter)
    local k = L.devKey(machine)
    return k and N.endString(k, L.roleOf(adapter), adapter.id) or nil
end

--- The link record a machine keeps for an adapter, or nil.
function L.linkOf(machine, id)
    local md = machine and machine.getModData and machine:getModData()
    local all = md and md[L.KEY]
    return all and all[id] or nil
end

--- Note that a machine is on a line (authority): its link record and registry entry.
function L.attach(machine, adapter)
    local sq = squareOf(machine)
    if not sq then return false end
    local md = machine:getModData()
    md[L.KEY] = md[L.KEY] or {}
    md[L.KEY][adapter.id] = md[L.KEY][adapter.id] or { source = "tank" }
    registry().links[N.key(sq:getX(), sq:getY(), sq:getZ()) .. "|" .. adapter.id] =
        { x = sq:getX(), y = sq:getY(), z = sq:getZ(), id = adapter.id }
    if machine.transmitModData then machine:transmitModData() end
    return true
end

--- Cut a machine off its lines (authority). Returns the sections handed back.
function L.clear(machine, adapter)
    local sq = squareOf(machine)
    local endStr = L.endFor(machine, adapter)
    local sound = endStr and K.disconnect(endStr) or 0
    local md = machine and machine:getModData()
    if md and md[L.KEY] then md[L.KEY][adapter.id] = nil end
    if sq then registry().links[N.key(sq:getX(), sq:getY(), sq:getZ()) .. "|" .. adapter.id] = nil end
    if adapter.release then pcall(adapter.release, machine) end
    if machine and machine.transmitModData then machine:transmitModData() end
    return sound
end

--- Switch a line between feeding ("tank") and paused ("manual").
function L.setSource(machine, adapter, source)
    local link = L.linkOf(machine, adapter.id)
    if not link then return false end
    link.source = source
    if source ~= "tank" and adapter.release then pcall(adapter.release, machine) end
    if machine.transmitModData then machine:transmitModData() end
    return true
end

----------------------------------------------------------- finding things
local function squareAt(x, y, z)
    local cell = getCell and getCell()
    return cell and cell:getGridSquare(x, y, z) or nil
end

--- The machine at a square for an adapter: obj, or nil + why ("unloaded"|"gone").
function L.machineAt(x, y, z, adapter)
    local sq = squareAt(x, y, z)
    if not sq then return nil, "unloaded" end
    local objs = try(sq, "getObjects")
    if objs then
        for i = 0, objs:size() - 1 do
            local o = objs:get(i)
            local ok, yes = pcall(adapter.match, o)
            if ok and yes then return o end
        end
    end
    return nil, "gone"
end

--- The tank (master piece) of a given kind at a square, or nil + why.
function L.tankAt(x, y, z, supplies)
    local sq = squareAt(x, y, z)
    if not sq then return nil, "unloaded" end
    local objs = try(sq, "getObjects")
    if objs then
        for i = 0, objs:size() - 1 do
            local o = objs:get(i)
            local info = P.describe(o)
            if info and info.type == supplies then return P.master(o) end
        end
    end
    return nil, "gone"
end

--- A uniform handle on whatever a line ends at -- a tank or a node:
--      { obj, key, room(), add(amt, dirty), squares(), isNode, [amount(), take(amt), tainted()] }
function L.wrapTarget(obj, kind)
    if not obj then return nil end
    local info = P.describe(obj)
    if info and info.type == kind then
        local master = P.master(obj)
        return {
            obj = master, key = L.devKey(master),
            room = function() return M.room(P.data(master)) end,
            amount = function() return M.available(P.data(master)) end,
            tainted = function() return M.isTainted(P.data(master)) end,
            add = function(amt, dirty)
                local d = P.data(master)
                local took = (kind == "water") and M.addWater(d, amt, dirty) or M.add(d, amt)
                if took > 0 then P.transmit(master) end
                return took
            end,
            take = function(amt)
                local got = M.take(P.data(master), amt)
                if got > 0 then P.transmit(master) end
                return got
            end,
            squares = function() return P.squares(master) end,
        }
    end
    local n = L.nodeOf(obj)
    if n and n.kind == kind then
        return {
            obj = obj, isNode = true, node = n,
            room = function() return n.room(obj) end,
            add = function(amt, dirty) return n.add(obj, amt, dirty) end,
            squares = function()
                if n.squares then return n.squares(obj) end
                local sq = squareOf(obj)
                return sq and { sq } or {}
            end,
        }
    end
    return nil
end

--- The target at a square: a tank of `kind`, or a node of that kind.
function L.targetAt(x, y, z, kind)
    local sq = squareAt(x, y, z)
    if not sq then return nil, "unloaded" end
    local objs = try(sq, "getObjects")
    if objs then
        for i = 0, objs:size() - 1 do
            local t = L.wrapTarget(objs:get(i), kind)
            if t then return t end
        end
    end
    return nil, "gone"
end

--- Every tank of `supplies` within `range` of a machine (master objects), nearest first,
--  and with `withNodes` the nodes of that kind too.
function L.tanksNear(machine, supplies, range, withNodes)
    range = range or 25
    local sq = squareOf(machine)
    local out, seen = {}, {}
    if not sq then return out end
    local cx, cy, cz = sq:getX(), sq:getY(), sq:getZ()
    local prefix = P.TILESET .. "_"
    for dx = -range, range do
        for dy = -range, range do
            local s = squareAt(cx + dx, cy + dy, cz)
            local objs = s and try(s, "getObjects")
            if objs then
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    -- only this mod's sprites can be tanks or nodes: one cheap name test first
                    local spr = o.getSprite and o:getSprite()
                    local name = spr and spr:getName()
                    local ours = type(name) == "string" and string.sub(name, 1, #prefix) == prefix
                    local info = ours and P.spriteInfo(name)
                    if info and info.type == supplies then
                        local m = P.master(o)
                        if not seen[m] then
                            seen[m] = true
                            out[#out + 1] = { tank = m, dist = math.max(math.abs(dx), math.abs(dy)) }
                        end
                    elseif ours and withNodes and not seen[o] then
                        local nd = L.nodeOf(o)
                        if nd and nd.kind == supplies and o ~= machine then
                            seen[o] = true
                            out[#out + 1] = { tank = o, node = true, dist = math.max(math.abs(dx), math.abs(dy)) }
                        end
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end

----------------------------------------------------------- reading a network
--- Resolve a network's ends into live handles.
--  Returns { tanks, nodes, sinks, sources } (each a list), skipping ends whose
--  square is not loaded or whose device is gone.
function L.resolve(comp, fluid)
    local out = { tanks = {}, nodes = {}, sinks = {}, sources = {} }
    local seen = {}
    for _, e in ipairs(comp.ends or {}) do
        if e.role == "tank" then
            local tank = L.tankAt(e.x, e.y, e.z, fluid)
            if tank and not seen[tank] then
                seen[tank] = true
                out.tanks[#out.tanks + 1] = L.wrapTarget(tank, fluid)
            end
        elseif e.role == "node" then
            local n = L.nodes[e.id]
            local sq = squareAt(e.x, e.y, e.z)
            local objs = sq and try(sq, "getObjects")
            if n and objs then
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    local ok, yes = pcall(n.match, o)
                    if ok and yes and not seen[o] then
                        seen[o] = true
                        out.nodes[#out.nodes + 1] = L.wrapTarget(o, fluid)
                    end
                end
            end
        else
            local a = L.adapters[e.id]
            if a and L.kindOf(a) == fluid then
                local m = L.machineAt(e.x, e.y, e.z, a)
                if m then
                    seen[m] = seen[m] or {}
                    if not seen[m][e.role] then
                        seen[m][e.role] = true
                        local list = (e.role == "sink") and out.sinks or out.sources
                        list[#list + 1] = { obj = m, adapter = a, key = e.key }
                    end
                end
            end
        end
    end
    return out
end

--- What a machine is joined to right now, for a menu or a check:
--  { connected = has an end, working = in a working network, tanks = {handles},
--    receivers = {handles} }.
function L.status(machine, adapter)
    local endStr = L.endFor(machine, adapter)
    local st = { connected = false, working = false, tanks = {}, receivers = {} }
    if not endStr then return st end
    st.connected = (K.index()[endStr] ~= nil)
    local fluid = L.kindOf(adapter)
    for _, comp in ipairs(K.componentsOf(endStr)) do
        st.working = true
        local r = L.resolve(comp, fluid)
        for _, t in ipairs(r.tanks) do st.tanks[#st.tanks + 1] = t st.receivers[#st.receivers + 1] = t end
        for _, n in ipairs(r.nodes) do st.receivers[#st.receivers + 1] = n end
    end
    return st
end

--- Push `amount` from a source machine into its network (a hand pump's stroke).
--  Shared by room among the tanks and nodes there. Returns what went in.
function L.pushFrom(machine, adapter, amount, dirty)
    local st = L.status(machine, adapter)
    if #st.receivers == 0 then return 0 end
    local rooms = {}
    for i, r in ipairs(st.receivers) do rooms[i] = r.room() end
    local alloc = N.share(amount, rooms)
    local total = 0
    for i, r in ipairs(st.receivers) do
        if alloc[i] > N.EPS then total = total + (r.add(alloc[i], dirty) or 0) end
    end
    return total
end

----------------------------------------------------------- the tick
local function fullest(tanks)
    local best
    for _, t in ipairs(tanks) do
        if not best or t.amount() > best.amount() + N.EPS then best = t end
    end
    return best
end

--- Lines that meet at the same tank share it: their machines draw from it
--  together, fairly. Returns lists of resolved networks, one per such group.
-- The networks only change when the pipes do (or Climate's ice switches), so the
-- per-minute tick reuses them instead of walking every pipe again.
local netCache = { v = -1 }
local function components(pipes)
    local stamp = K.flowStamp()
    if netCache.v ~= stamp or netCache.pipes ~= pipes then
        netCache = { v = stamp, pipes = pipes, list = N.components(pipes) }
    end
    return netCache.list
end

local function groups(pipes)
    local comps, parent = {}, {}
    for i, comp in ipairs(components(pipes)) do
        comps[i] = { comp = comp, r = L.resolve(comp, comp.fluid) }
        parent[i] = i
    end
    local function find(i) while parent[i] ~= i do parent[i] = parent[parent[i]] i = parent[i] end return i end
    local owner = {}
    for i, c in ipairs(comps) do
        for _, t in ipairs(c.r.tanks) do
            local k = c.comp.fluid .. "|" .. tostring(t.key)
            if owner[k] then parent[find(i)] = find(owner[k]) else owner[k] = i end
        end
    end
    local byRoot, order = {}, {}
    for i, c in ipairs(comps) do
        local root = find(i)
        if not byRoot[root] then
            byRoot[root] = { fluid = c.comp.fluid, tanks = {}, nodes = {}, sinks = {}, sources = {}, seen = {} }
            order[#order + 1] = byRoot[root]
        end
        local g = byRoot[root]
        local function add(list, items, keyOf)
            for _, it in ipairs(items) do
                local k = keyOf(it)
                if not g.seen[k] then g.seen[k] = true list[#list + 1] = it end
            end
        end
        add(g.tanks, c.r.tanks, function(t) return "t" .. tostring(t.key) end)
        add(g.nodes, c.r.nodes, function(t) return "n" .. tostring(t.obj) end)
        add(g.sinks, c.r.sinks, function(d) return "s" .. d.key .. "|" .. d.adapter.id end)
        add(g.sources, c.r.sources, function(d) return "o" .. d.key .. "|" .. d.adapter.id end)
    end
    return order
end

--- Does this source give tainted water? `tainted` may be true, or a function of the machine.
function L.sourceDirty(adapter, obj)
    local t = adapter.tainted
    if type(t) == "function" then
        local ok, v = pcall(t, obj)
        return ok and v == true
    end
    return t == true
end

--- Move what every working network moves this minute (authority only).
-- Tanks and buffers changed during the minute are sent to clients once, at its end.
function L.tick()
    if not DazedPlumb.Sync.authority() then return end
    P.batch(L.tickNow)
end

function L.tickNow()
    local pipes = K.pipes()
    local served = {}
    for _, r in ipairs(groups(pipes)) do
        local fluid = r.fluid
        local sinks, sources = {}, {}
        local pointAt = fullest(r.tanks)
        for _, s in ipairs(r.sinks) do
            local link = L.linkOf(s.obj, s.adapter.id)
            if not link and L.attach(s.obj, s.adapter) then link = L.linkOf(s.obj, s.adapter.id) end
            local id = s.key .. "|" .. s.adapter.id
            if link and link.source == "tank" and pointAt then
                local tsq = squareOf(pointAt.obj)
                if tsq and (link.tx ~= tsq:getX() or link.ty ~= tsq:getY() or link.tz ~= tsq:getZ()) then
                    link.tx, link.ty, link.tz = tsq:getX(), tsq:getY(), tsq:getZ()
                end
                served[id] = true
                if s.adapter.engage then pcall(s.adapter.engage, s.obj, link) end
                sinks[#sinks + 1] = {
                    room = function() return s.adapter.room(s.obj) end,
                    put = function(amt, dirty) return s.adapter.put(s.obj, amt, dirty) end,
                    rate = s.adapter.rate and s.adapter.rate(s.obj) or nil,
                }
            end
        end
        for _, s in ipairs(r.sources) do
            local link = L.linkOf(s.obj, s.adapter.id)
            if not link and L.attach(s.obj, s.adapter) then link = L.linkOf(s.obj, s.adapter.id) end
            if link and link.source == "tank" then
                served[s.key .. "|" .. s.adapter.id] = true
                sources[#sources + 1] = {
                    available = function() return s.adapter.available(s.obj) end,
                    take = function(amt) return s.adapter.take(s.obj, amt) end,
                    dirty = L.sourceDirty(s.adapter, s.obj),
                }
            end
        end
        local ok, err = pcall(N.run, L.RATE[fluid] or 1, r.tanks, r.nodes, sources, sinks)
        if not ok then print("DazedPlumbing: network failed: " .. tostring(err)) end
        -- tanks piped together even out
        if #r.tanks >= 2 then
            local okB, errB = pcall(N.balance, L.RATE[fluid] or 1, r.tanks)
            if not okB then print("DazedPlumbing: tank balancing failed: " .. tostring(errB)) end
        end
    end
    -- machines that were on a line and are not served now: let them go
    local reg, drop = registry(), {}
    for key, entry in pairs(reg.links) do
        local adapter = L.adapters[entry.id]
        if adapter and not served[N.key(entry.x, entry.y, entry.z) .. "|" .. entry.id] then
            local m, why = L.machineAt(entry.x, entry.y, entry.z, adapter)
            if m then
                local link = L.linkOf(m, adapter.id)
                if link and link.tx then
                    link.tx, link.ty, link.tz = nil, nil, nil
                    if adapter.release then pcall(adapter.release, m) end
                    if m.transmitModData then m:transmitModData() end
                end
            elseif why == "gone" then
                drop[#drop + 1] = key
            end
        end
    end
    for _, k in ipairs(drop) do reg.links[k] = nil end
end

return L
