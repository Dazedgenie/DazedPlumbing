-- Pure tests for DUP_Net: joins, valves, pruning, sharing and flow. Run: lua54 net_test.lua <DazedPlumbing/common/media/lua>
local root = arg[1] or "../../common/media/lua"
local core = arg[2] or "../../../DazedCore/common/media/lua"      -- Dazed Utilities: Core, required
dofile(root .. "/shared/DazedPlumbing/DUP_Net.lua")
local N = DazedPlumb.Net
local fails, n = 0, 0
local function empty(t) for _ in pairs(t) do return false end return true end
local function ok(c, msg) n = n + 1 if not c then fails = fails + 1 print("FAIL: " .. msg) end end
local function near(a, b) return math.abs(a - b) < 1e-6 end

-- share: even split, caps, leftovers move on
local a = N.share(10, { 2, 100, 100 })
ok(near(a[1], 2) and near(a[2], 4) and near(a[3], 4), "share leftovers")
a = N.share(3, { 5, 5 }) ok(near(a[1], 1.5) and near(a[2], 1.5), "share even")
a = N.share(100, { 1, 2 }) ok(near(a[1], 1) and near(a[2], 2), "share plenty")
a = N.share(0, { 1 }) ok(near(a[1], 0), "share none")

-- lay a path machine(0,0) -> pipes (1,0),(2,0) -> tank(3,0)
local pipes = {}
local devEnd, tankEnd = N.endString("0,0,0", "sink", "gen"), N.endString("3,0,0", "tank", "tank")
local t = N.layPath(pipes, "water", 0, { x = 0, y = 0 }, { { x = 1, y = 0 }, { x = 2, y = 0 } }, { x = 3, y = 0, kind = "dev" }, devEnd, tankEnd)
ok(#t == 2, "touched two")
ok(pipes["1,0,0"].mask == 10, "mask W+E = 10, got " .. tostring(pipes["1,0,0"].mask))
local comps = N.components(pipes)
ok(#comps == 1 and #comps[1].ends == 2, "one network with two ends")

-- branch: second machine at (2,2) -> pipe (2,1) joins existing pipe (2,0)
local t2 = N.layPath(pipes, "water", 0, { x = 2, y = 2 }, { { x = 2, y = 1 } }, { x = 2, y = 0, kind = "pipe" }, N.endString("2,2,0", "sink", "boil"), nil)
ok(pipes["2,0,0"].mask == 8 + 2 + 4, "junction mask got S bit, got " .. tostring(pipes["2,0,0"].mask))
comps = N.components(pipes)
ok(#comps == 1 and #comps[1].ends == 3, "merged into one network with three ends")

-- another fluid next door does not join
N.layPath(pipes, "gas", 0, { x = 5, y = 5 }, { { x = 1, y = 1 } }, { x = 1, y = 0, kind = "pipe" }, N.endString("5,5,0", "sink", "g"), nil)
-- gas tail is a water pipe: bit added to the water record, but fluids differ so no join
local c = N.component(pipes, "1,0,0", false)
ok(#c.keys == 3, "gas square did not join the water network (" .. #c.keys .. ")")

-- valve closes a branch
pipes["2,1,0"].valve = "closed"
comps = N.components(pipes)
local found = 0
for _, cc in ipairs(comps) do if cc.set["2,0,0"] then for _, e in ipairs(cc.ends) do found = found + 1 end end end
ok(found == 2, "closed valve cuts the boiler off (ends=" .. found .. ")")
pipes["2,1,0"].valve = "open"

-- break cuts the line, structural component still sees it
pipes["1,0,0"].cond = 0
c = N.component(pipes, "2,0,0", false)
ok(not c.set["1,0,0"], "break stops flow")
c = N.component(pipes, "2,0,0", true)
ok(c.set["1,0,0"], "structural still joined")
pipes["1,0,0"].cond = 100

-- disconnect the boiler: its stub is pruned, trunk stays
N.dropEnd(pipes, N.endString("2,2,0", "sink", "boil"))
local removed = N.prune(pipes)
local hit = false
for _, r in ipairs(removed) do if r.key == "2,1,0" then hit = true end end
ok(hit, "boiler stub pruned")
ok(pipes["2,0,0"] ~= nil, "trunk survives")
ok(not N.has(pipes["2,0,0"].mask, 4), "junction bit removed")
-- disconnect the generator: whole trunk goes
N.dropEnd(pipes, devEnd)
removed = N.prune(pipes)
local left = 0
for k, r in pairs(pipes) do if N.isReal(r) and r.f == "water" then left = left + 1 end end
ok(left == 0, "trunk fully pruned, left " .. left)

-- virtual joint: machine beside tank
local p2 = {}
N.layPath(p2, "gas", 0, { x = 0, y = 0 }, {}, { x = 1, y = 0, kind = "dev" }, N.endString("0,0,0", "sink", "g"), N.endString("1,0,0", "tank", "tank"))
comps = N.components(p2)
ok(#comps == 1 and #comps[1].ends == 2, "virtual joint is a network")
N.dropEnd(p2, N.endString("0,0,0", "sink", "g"))
ok(empty(p2), "virtual joint dies with its device")

-- run: two tanks, two sinks, one source; fair share
local function tank(amount, cap, dirty)
    local o = { amount = amount, cap = cap }
    o.handle = { amount = function() return o.amount end, room = function() return o.cap - o.amount end,
        add = function(x) o.amount = o.amount + x return x end, take = function(x) o.amount = o.amount - x return x end,
        tainted = function() return dirty == true end }
    return o
end
local function sink(room) local o = { got = 0, r = room } o.handle = { room = function() return o.r - o.got end, put = function(x, d) o.got = o.got + x o.dirty = d return x end } return o end
local T1, T2 = tank(5, 100), tank(5, 100)
local S1, S2 = sink(50), sink(50)
N.run(20, { T1.handle, T2.handle }, {}, {}, { S1.handle, S2.handle })
ok(near(S1.got, 5) and near(S2.got, 5), "sinks share 10 L evenly")
ok(near(T1.amount + T2.amount, 0), "tanks drained")
-- dirty flag follows the tank
local T3 = tank(10, 100, true)
local S3 = sink(4)
N.run(20, { T3.handle }, {}, {}, { S3.handle })
ok(S3.dirty == true and near(T3.amount, 6), "tainted tank gives tainted water")
-- a source fills tanks by room
local T4, T5 = tank(0, 3), tank(0, 100)
local src = { available = function() return 20 end, take = function(x) return x end, dirty = true }
N.run(20, { T4.handle, T5.handle }, {}, { src }, {})
ok(near(T4.amount, 3) and near(T5.amount, 17), "source split by room")
-- pruning from the squares that lost an end matches pruning the whole table
local function layout()
    local q = {}
    local e1, e2 = N.endString("0,0,0", "sink", "a"), N.endString("6,0,0", "tank", "tank")
    N.layPath(q, "water", 0, { x = 0, y = 0 }, { { x = 1, y = 0 }, { x = 2, y = 0 }, { x = 3, y = 0 }, { x = 4, y = 0 }, { x = 5, y = 0 } }, { x = 6, y = 0, kind = "dev" }, e1, e2)
    N.layPath(q, "water", 0, { x = 3, y = 3 }, { { x = 3, y = 2 }, { x = 3, y = 1 } }, { x = 3, y = 0, kind = "pipe" }, N.endString("3,3,0", "sink", "b"), nil)
    return q, e1
end
local full, e1 = layout()
local seeded = layout()
N.prune(full, N.dropEnd(full, e1))
local holders = N.index(seeded)[e1]
N.prune(seeded, N.dropEnd(seeded, e1, holders))
local same = true
for k, r in pairs(full) do if not seeded[k] or seeded[k].mask ~= r.mask then same = false end end
for k in pairs(seeded) do if not full[k] then same = false end end
ok(same and full["1,0,0"] == nil and full["3,0,0"] ~= nil, "seeded prune leaves the same pipes and arms as a full prune")
for i = 1, 40000 do N.split(i .. ",2,3") end
local sx, sy, sz = N.split("7,-8,9")
ok(sx == 7 and sy == -8 and sz == 9 and select(1, N.split("1,2,3")) == 1, "the split memo keeps working past its size")

print(string.format("net_test: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
