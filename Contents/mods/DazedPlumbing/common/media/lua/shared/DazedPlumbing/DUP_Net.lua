--[[ Dazed Utilities: Plumbing -- the pipe NETWORK, as pure data.

     No engine calls live here, so the whole thing runs in the test harness.

     A pipe square is a RECORD in a table keyed "x,y,z":
         { f = "water"|"gas"|"propane", cond = 0..100, mask = 0..15 (N=1 E=2 S=4 W=8),
           outdoor = bool, valve = nil|"open"|"closed", ends = { "x,y,z|role|id", ... } }
     Two neighbouring squares are JOINED when each one's mask has the bit
     pointing at the other and they carry the same fluid. A network is a set of
     joined squares. A closed valve or a broken square (cond 0) stops flow.

     An END ties a device to a square: role is "tank", "node" (takes from
     sources, e.g. a purifier's input), "sink" (a machine that draws) or
     "source" (a pump that gives); id is the adapter id ("tank" for tanks).
     A device that touches a tank with no pipe between uses a VIRTUAL joint
     (a record with virtual = true, keyed "x,y,z~role~id~tx,ty").
]]

DazedPlumb = DazedPlumb or {}
DazedPlumb.Net = DazedPlumb.Net or {}
local N = DazedPlumb.Net

N.EPS = 1e-6
N.DIRS = { { 0, -1, 1, 4 }, { 1, 0, 2, 8 }, { 0, 1, 4, 1 }, { -1, 0, 8, 2 } }   -- dx, dy, bit, opposite

----------------------------------------------------------- keys and masks
function N.key(x, y, z) return x .. "," .. y .. "," .. z end

-- Key string -> its three numbers; a key always parses the same way, and the minute ticks split every pipe key.
local splitMemo, splitMemoN = {}, 0
local SPLIT_MEMO_MAX = 20000

function N.split(key)
    local hit = splitMemo[key]
    if hit then return hit[1], hit[2], hit[3] end
    local x, y, z = string.match(key, "^(%-?%d+),(%-?%d+),(%-?%d+)")
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    -- Only well-formed keys are kept, and the table is bounded so stray strings cannot grow it forever.
    if x and type(key) == "string" then
        if splitMemoN >= SPLIT_MEMO_MAX then splitMemo, splitMemoN = {}, 0 end
        splitMemo[key] = { x, y, z }
        splitMemoN = splitMemoN + 1
    end
    return x, y, z
end

function N.has(mask, bit) return math.floor((mask or 0) / bit) % 2 == 1 end
function N.addBit(mask, bit) mask = mask or 0 return N.has(mask, bit) and mask or mask + bit end
function N.subBit(mask, bit) mask = mask or 0 return N.has(mask, bit) and mask - bit or mask end
function N.count(mask)
    local c = 0
    for _, d in ipairs(N.DIRS) do if N.has(mask, d[3]) then c = c + 1 end end
    return c
end

--- The mask bit that points from (ax, ay) to the adjacent (bx, by), or nil.
function N.bitToward(ax, ay, bx, by)
    for _, d in ipairs(N.DIRS) do
        if ax + d[1] == bx and ay + d[2] == by then return d[3], d[4] end
    end
    return nil
end

function N.isReal(rec) return rec ~= nil and not rec.virtual end
function N.flows(rec) return rec ~= nil and (rec.cond or 100) > 0 and rec.valve ~= "closed" end

----------------------------------------------------------- ends
function N.endString(key, role, id) return key .. "|" .. role .. "|" .. id end

function N.parseEnd(s)
    local k, role, id = string.match(s, "^([^|]+)|([^|]+)|(.+)$")
    if not k then return nil end
    local x, y, z = N.split(k)
    return { key = k, x = x, y = y, z = z, role = role, id = id }
end

local function hasEnd(rec, s)
    for _, e in ipairs(rec.ends or {}) do if e == s then return true end end
    return false
end

function N.addEnd(rec, s)
    rec.ends = rec.ends or {}
    if not hasEnd(rec, s) then rec.ends[#rec.ends + 1] = s end
end

----------------------------------------------------------- joins and components
--- The keys of the real squares joined to `key`. With `structural` a closed
--  valve or a break still joins (used to find where a new pipe may merge).
function N.joined(pipes, key, structural)
    local rec = pipes[key]
    local out = {}
    if not N.isReal(rec) then return out end
    local x, y, z = N.split(key)
    for _, d in ipairs(N.DIRS) do
        if N.has(rec.mask, d[3]) then
            local nk = N.key(x + d[1], y + d[2], z)
            local nr = pipes[nk]
            if N.isReal(nr) and nr.f == rec.f and N.has(nr.mask, d[4]) and (structural or N.flows(nr)) then
                out[#out + 1] = nk
            end
        end
    end
    return out
end

--- The component holding `start`: { keys = {...}, set = {...}, fluid }.
function N.component(pipes, start, structural)
    local rec = pipes[start]
    if not rec then return nil end
    if not structural and not rec.virtual and not N.flows(rec) then return nil end
    local comp = { keys = { start }, set = { [start] = true }, fluid = rec.f }
    local head = 1
    while head <= #comp.keys do
        for _, nk in ipairs(N.joined(pipes, comp.keys[head], structural)) do
            if not comp.set[nk] then comp.set[nk] = true; comp.keys[#comp.keys + 1] = nk end
        end
        head = head + 1
    end
    return comp
end

--- The parsed ends held by a component's squares (each tagged with `via`).
function N.endsOf(pipes, comp)
    local out = {}
    for _, k in ipairs(comp.keys) do
        for _, s in ipairs(pipes[k].ends or {}) do
            local e = N.parseEnd(s)
            if e then e.via = k; out[#out + 1] = e end
        end
    end
    return out
end

--- Every WORKING component, in a stable order, each with its `ends`.
function N.components(pipes)
    local keys = {}
    for k in pairs(pipes) do keys[#keys + 1] = k end
    table.sort(keys)
    local seen, out = {}, {}
    for _, k in ipairs(keys) do
        if not seen[k] then
            local c = N.component(pipes, k, false)
            if c then
                for _, ck in ipairs(c.keys) do seen[ck] = true end
                c.ends = N.endsOf(pipes, c)
                out[#out + 1] = c
            else
                seen[k] = true
            end
        end
    end
    return out
end

--- Index: "x,y,z|role|id" -> list of the square keys holding that end.
function N.index(pipes)
    local idx = {}
    for k, rec in pairs(pipes) do
        for _, s in ipairs(rec.ends or {}) do
            idx[s] = idx[s] or {}
            idx[s][#idx[s] + 1] = k
        end
    end
    return idx
end

----------------------------------------------------------- laying
--- Write the records for a freshly routed path. `from` is the device's square
--  {x,y}; `path` the new squares {x,y}...; `tail` the square the last pipe
--  butts onto {x,y,kind = "dev"|"pipe"}; devEnd / tailEnd the end strings.
--  `outdoor(x, y)` says whether a square is outside. Returns the touched keys
--  (every real square whose record changed).
function N.layPath(pipes, f, z, from, path, tail, devEnd, tailEnd, outdoor)
    local touched, seen = {}, {}
    local function touch(k) if not seen[k] then seen[k] = true; touched[#touched + 1] = k end end
    local chain = { from }
    for _, p in ipairs(path) do chain[#chain + 1] = p end
    chain[#chain + 1] = tail
    for i = 1, #path do
        local at, prev, nxt = chain[i + 1], chain[i], chain[i + 2]
        local mask = 0
        for _, nb in ipairs({ prev, nxt }) do
            local b = N.bitToward(at.x, at.y, nb.x, nb.y)
            if b then mask = N.addBit(mask, b) end
        end
        local k = N.key(at.x, at.y, z)
        pipes[k] = { f = f, cond = 100, mask = mask, outdoor = outdoor and outdoor(at.x, at.y) or false }
        touch(k)
    end
    local function joinTail(lastX, lastY)
        if tail.kind == "pipe" then
            local tk = N.key(tail.x, tail.y, z)
            local tr = pipes[tk]
            local b = N.bitToward(tail.x, tail.y, lastX, lastY)
            if tr and b then tr.mask = N.addBit(tr.mask, b); touch(tk) end
        end
    end
    if #path >= 1 then
        local first, last = pipes[N.key(path[1].x, path[1].y, z)], pipes[N.key(path[#path].x, path[#path].y, z)]
        N.addEnd(first, devEnd)
        if tail.kind == "dev" then N.addEnd(last, tailEnd) else joinTail(path[#path].x, path[#path].y) end
    else
        if tail.kind == "dev" then
            local role, id = string.match(devEnd, "^[^|]+|([^|]+)|(.+)$")
            local vk = N.key(from.x, from.y, z) .. "~" .. role .. "~" .. id .. "~" .. tail.x .. "," .. tail.y
            pipes[vk] = { virtual = true, f = f, cond = 100, mask = 0, ends = { devEnd, tailEnd } }
        else
            local tk = N.key(tail.x, tail.y, z)
            local tr = pipes[tk]
            if tr then
                N.addEnd(tr, devEnd)
                local b = N.bitToward(tail.x, tail.y, from.x, from.y)
                if b then tr.mask = N.addBit(tr.mask, b) end
                touch(tk)
            end
        end
    end
    return touched
end

----------------------------------------------------------- taking pipe away
--- Remove every end equal to `s`; delete virtual joints left with fewer than
--  two ends. Returns the real keys that lost an end.
function N.dropEnd(pipes, s)
    local changed, dead = {}, {}
    for k, rec in pairs(pipes) do
        local ends = rec.ends
        if ends then
            local keep = {}
            for _, e in ipairs(ends) do if e ~= s then keep[#keep + 1] = e end end
            if #keep ~= #ends then
                rec.ends = keep
                if rec.virtual then dead[#dead + 1] = k else changed[#changed + 1] = k end
            end
        end
    end
    for _, k in ipairs(dead) do pipes[k] = nil end
    return changed
end

--- Delete dead-end real squares (one join or fewer, and at most one end),
--  over and over. Returns removed = { {key, rec}... } and touched neighbours.
function N.prune(pipes)
    local removed, touched = {}, {}
    local again = true
    while again do
        again = false
        local keys = {}
        for k, rec in pairs(pipes) do if N.isReal(rec) then keys[#keys + 1] = k end end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local rec = pipes[k]
            if rec and #N.joined(pipes, k, true) + #(rec.ends or {}) <= 1 then
                local nbs = N.joined(pipes, k, true)
                pipes[k] = nil
                removed[#removed + 1] = { key = k, rec = rec }
                for _, nk in ipairs(nbs) do
                    local nr = pipes[nk]
                    local x, y = N.split(k)
                    local nx, ny = N.split(nk)
                    local b = N.bitToward(nx, ny, x, y)
                    if nr and b then nr.mask = N.subBit(nr.mask, b); touched[#touched + 1] = nk end
                end
                again = true
            end
        end
    end
    return removed, touched
end

----------------------------------------------------------- sharing
--- Split `supply` between wants as evenly as their limits allow (each gets at
--  most what it asked for; what one cannot take goes to the others).
function N.share(supply, demands)
    local out, active = {}, {}
    for i = 1, #demands do
        out[i] = 0
        if (demands[i] or 0) > N.EPS then active[#active + 1] = i end
    end
    local remaining = supply or 0
    while #active > 0 and remaining > N.EPS do
        local per = remaining / #active
        local next, used = {}, 0
        for _, i in ipairs(active) do
            local need = demands[i] - out[i]
            if need <= per + N.EPS then out[i] = demands[i]; used = used + need
            else next[#next + 1] = i end
        end
        if #next == #active then
            for _, i in ipairs(active) do out[i] = out[i] + per end
            remaining = 0
        else
            remaining = remaining - used
            active = next
        end
    end
    return out
end

--- Move fluid across one network. Handles are tables of closures:
--    tanks    { amount(), room(), add(n, dirty) -> n, take(n) -> n, tainted() }
--    nodes    { room(), add(n, dirty) -> n }                      (take from sources)
--    sources  { available(), take(n) -> n, dirty = bool }
--    sinks    { room(), put(n, dirty) -> n }
--  `rate` caps what one device moves in a minute.
function N.run(rate, tanks, nodes, sources, sinks)
    local receivers = {}
    for _, t in ipairs(tanks) do receivers[#receivers + 1] = t end
    for _, n in ipairs(nodes) do receivers[#receivers + 1] = n end
    for _, s in ipairs(sources) do
        local give = math.min(s.available() or 0, rate)
        if give > N.EPS then
            local rooms, total = {}, 0
            for i, r in ipairs(receivers) do rooms[i] = r.room(); total = total + rooms[i] end
            give = math.min(give, total)
            if give > N.EPS then
                local gave = s.take(give) or 0
                local alloc = N.share(gave, rooms)
                for i, r in ipairs(receivers) do
                    if alloc[i] > N.EPS then r.add(alloc[i], s.dirty == true) end
                end
            end
        end
    end
    if #sinks == 0 or #tanks == 0 then return end
    local supply = 0
    for _, t in ipairs(tanks) do supply = supply + math.max(0, t.amount()) end
    local demands = {}
    for i, s in ipairs(sinks) do demands[i] = math.min(math.max(0, s.room() or 0), s.rate or rate) end
    local alloc = N.share(supply, demands)
    for i, s in ipairs(sinks) do
        if alloc[i] > N.EPS then
            local order = {}
            for _, t in ipairs(tanks) do order[#order + 1] = t end
            table.sort(order, function(a, b) return a.amount() > b.amount() end)
            local dirty, left = false, alloc[i]
            for _, t in ipairs(order) do
                if left > N.EPS and t.amount() > N.EPS then
                    if t.tainted() then dirty = true end
                    left = left - math.min(left, t.amount())
                end
            end
            local took = s.put(alloc[i], dirty) or 0
            left = took
            for _, t in ipairs(order) do
                if left > N.EPS then
                    local got = t.take(math.min(left, t.amount())) or 0
                    left = left - got
                end
            end
        end
    end
end

--- Tanks on one line even out like connected barrels: the fuller ones (by share of capacity) give to the emptier,
--  at most `rate` a minute in all. Water keeps its taint as it moves. Returns what moved.
function N.balance(rate, tanks)
    if #tanks < 2 then return 0 end
    local amt, cap, A, C = {}, {}, 0, 0
    for i, t in ipairs(tanks) do
        amt[i] = math.max(0, t.amount())
        cap[i] = amt[i] + math.max(0, t.room())
        A, C = A + amt[i], C + cap[i]
    end
    if C <= N.EPS then return 0 end
    local f = A / C
    local give, need, gTotal, nTotal = {}, {}, 0, 0
    for i = 1, #tanks do
        local surplus = amt[i] - f * cap[i]
        give[i] = surplus > 0.05 and surplus or 0
        need[i] = surplus < -0.05 and -surplus or 0
        gTotal, nTotal = gTotal + give[i], nTotal + need[i]
    end
    local move = math.min(rate, gTotal, nTotal)
    if move <= N.EPS then return 0 end
    local moved = 0
    for i, t in ipairs(tanks) do
        if give[i] > 0 then
            local dirty = t.tainted and t.tainted() or false
            local got = t.take(move * give[i] / gTotal) or 0
            for j, r in ipairs(tanks) do
                if need[j] > 0 and got > N.EPS then r.add(got * need[j] / nTotal, dirty) end
            end
            moved = moved + got
        end
    end
    return moved
end

return N
