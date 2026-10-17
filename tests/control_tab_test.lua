-- The Plumbing tab of Dazed Control on a fake engine: the view and marks for a small world, and every command
-- as an admin, a moderator and a plain player (the last two must change nothing). Also writes the view for the
-- lead's picture to /home/claude/work/views/plumbing.lua when that folder exists (or CONTROL_VIEWS names another).
-- Run: lua control_tab_test.lua <lua root> [<core root>]
local root = arg[1] or "../Contents/mods/DazedPlumbing/common/media/lua"
local core = arg[2] or "../../DazedCore/Contents/mods/DazedCore/common/media/lua"
package.path = core .. "/shared/?.lua;" .. core .. "/client/?.lua;" .. root .. "/shared/?.lua;" .. root .. "/server/?.lua;" .. root .. "/client/?.lua;" .. package.path
local E = dofile("engine_stub.lua")
local print = E.realPrint
local fails, n = 0, 0
local function ok(c, msg) n = n + 1 if not c then fails = fails + 1 print("FAIL: " .. msg) end end
local function near(a, b, tol) return math.abs(a - b) < (tol or 1e-4) end

isClient = function() return false end
isServer = function() return false end
MapObjects = { OnLoadWithSprite = function() end, OnNewWithSprite = function() end }
local clock = 0
getTimestampMs = function() clock = clock + 1000 return clock end     -- each call a second later: no cache, no rate limit
getGameTime = function()
    return { getWorldAgeHours = function() return E.hours or 100 end, getNightsSurvived = function() return 18 end,
             getHour = function() return 10 end, getMinutes = function() return 42 end }
end

require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Sync"
require "DazedPlumbing/DUP_Net"
require "DazedPlumbing/DUP_Pipes"
require "DazedPlumbing/DUP_Links"
require "DazedPlumbing/DUP_Pumps"
require "DazedPlumbing/DUP_Fixtures"
require "DazedPlumbing/DUP_Mains"
require "DazedPlumbing/DUP_World"
local T = require "DazedPlumbing/DUP_Control"
local C, Net = DazedCore.Control, DazedCore.Net
local P, M, K, N, U, W, X = DazedPlumb.Parts, DazedPlumb.Model, DazedPlumb.Pipes, DazedPlumb.Net, DazedPlumb.Pumps, DazedPlumb.Mains, DazedPlumb.Fixtures

ok(type(T) == "table" and C.tabs.plumbing ~= nil, "the tab is registered")
ok(Net.server[T.MODULE] ~= nil, "the handlers are registered")

-- ------------------------------------------------------------ a small world
E.grid(50, 50)
SandboxVars.WaterShutModifier = 30          -- town water still on (day 4 of 30)

local function pipeEnd(x, y, z, role, id, f)
    local k = N.key(x, y, z)
    local s = N.endString(k, role, id)
    -- a one-square run beside the device, holding its end
    local pk = N.key(x + 1, y, z)
    local rec = K.pipes()[pk] or { f = f or "water", cond = 100, mask = 0, ends = {} }
    N.addEnd(rec, s)
    K.pipes()[pk] = rec
    K.touch(true)
    return s
end

local function tank(x, y, size, typ, tier, d)
    local o = E.object(P.sprite(size, typ, tier, "S", 1), E.square(x, y))
    o.md.dazedplumb = d
    DazedPlumb.World.register(o)
    return o
end

local function well(x, y, reserve, cap)
    ModData.getOrCreate(U.WELLS).wells = ModData.getOrCreate(U.WELLS).wells or {}
    ModData.getOrCreate(U.WELLS).wells[N.key(x, y, 0)] = { reserve = reserve, cap = cap or 800, hour = 100 }
end

-- an electric pump on mains power at 3/4 flow, piped to the farm tank
local farmPump = E.object(U.sprite("electric", "S"), E.square(10, 10))
E.square(10, 10).power = true
farmPump.md.dazedFlow = 0.75
well(10, 10, 640)
pipeEnd(10, 10, 0, "source", U.ID)
local farmTank = tank(12, 10, "large", "water", "crafted", { amount = 640, condition = 100, name = "Riverside farm tote" })
pipeEnd(12, 10, 0, "tank", "tank")
-- a hand pump on a dry well
E.object(U.sprite("hand", "E"), E.square(20, 10))
well(20, 10, 0)
-- an electric pump with no power
E.object(U.sprite("electric", "N"), E.square(30, 10))
well(30, 10, 500)
-- a pump far away, its chunk not loaded
well(900, 900, 300)
-- tanks: tainted rain barrel, an empty propane tank, a cracked petrol tank
local schoolTank = tank(22, 14, "small", "water", "salvaged", { amount = 120, dirty = 60, condition = 100, name = "School barrels" })
local propTank = tank(40, 12, "small", "propane", "crafted", { amount = 0, condition = 100 })
tank(42, 20, "small", "gas", "crafted", { amount = 150, condition = 100, cracked = true })
-- a piped tank in an unloaded area
pipeEnd(600, 600, 0, "tank", "tank")
-- stuck: a tank and a pump that were removed (loaded squares, nothing there)
local stuckTank = pipeEnd(25, 25, 0, "tank", "tank")
local stuckPump = pipeEnd(26, 30, 0, "source", U.ID)
local stuckPumpReg = ModData.getOrCreate("DazedPlumbLinks")
stuckPumpReg.links = stuckPumpReg.links or {}
stuckPumpReg.links["26,30,0|" .. U.ID] = { x = 26, y = 30, z = 0, id = U.ID }
-- a water main serving a house with two fixtures, and one in an unloaded area
local function fixture(x, y)
    local f = E.object("fixtures_bathroom_01_0", E.square(x, y, 0))
    f.getProperties = function() return { Is = function(_, k) return k == "waterPiped" end, Val = function() return nil end } end
    local fc = { amount = 0, cap = 20, getAmount = function(s) return s.amount end, getCapacity = function(s) return s.cap end }
    f.getFluidContainer = function() return fc end
    return f
end
fixture(5, 31) fixture(7, 33)
E.object(W.sprite("S"), E.square(3, 30))
pipeEnd(3, 30, 0, "sink", W.ID)
W.store().mains["3,30,0"] = { k = "b", x = 5, y = 31, z = 0, id = "muldraugh-3", rects = "4,30,5,5,0", at = 100 }
W.store().mains["800,800,0"] = { k = "b", x = 800, y = 800, z = 0, id = "farmhouse", rects = "800,800,4,4,0", at = 100 }

-- ------------------------------------------------------------ people
local function person(name, access, x, y)
    return { name = name, access = access, x = x or 1, y = y or 1, z = 0,
             getUsername = function(s) return s.name end, getAccessLevel = function(s) return s.access end,
             getX = function(s) return s.x end, getY = function(s) return s.y end, getZ = function(s) return s.z end,
             getOnlineID = function() return 1 end }
end
local admin, moder, plain = person("Kyle", "admin"), person("Ash", "moderator"), person("Sam", "none")
ok(C.level(admin) == "admin" and C.level(moder) == "mod" and C.level(plain) == nil, "levels as expected")

-- ------------------------------------------------------------ the view
local function find(items, pat)
    for _, it in ipairs(items or {}) do if string.find(it.text or "", pat, 1, true) then return it end end
    return nil
end
local function lamp(view, pat)
    for _, l in ipairs(view.lamps) do if string.find(l[1], pat, 1, true) then return l end end
end

local v = C.tabs.plumbing.view(admin)
ok(#v.lamps == 4 and #v.cards == 3, "four lamps, three cards")
ok(lamp(v, "Town water on")[2] == "green", "town water lamp on")
ok(lamp(v, "Wells: 4") and lamp(v, "Wells: 4")[2] == "amber", "four wells, one dry: amber")
ok(lamp(v, "Tanks loaded: 4") ~= nil, "four loaded tanks counted: " .. tostring(v.lamps[3][1]))
ok(lamp(v, "Stuck links: 2") and lamp(v, "Stuck links: 2")[2] == "red", "two stuck links: red")

local pumps, tanks, links = v.cards[1].items, v.cards[2].items, v.cards[3].items
local fp = find(pumps, "Electric pump at 10, 10")
ok(fp and fp.tone == "green" and string.find(fp.sub, "6 L/min", 1, true) and string.find(fp.sub, "640 / 800", 1, true), "farm pump on, 6 L/min, well 640/800: " .. tostring(fp and fp.sub))
ok(fp and fp.buttons[1].label == "Off" and fp.buttons[1].args.on == false, "farm pump offers Off")
local hp = find(pumps, "Hand pump at 20, 10")
ok(hp and hp.tone == "red" and find({ { text = hp.buttons[1].label } }, "Refill"), "dry hand pump is red with Refill")
local np = find(pumps, "Electric pump at 30, 10")
ok(np and np.tone == "amber" and string.find(np.sub, "no power", 1, true), "unpowered pump amber")
local far = find(pumps, "Pump at 900, 900")
ok(far and far.tone == "muted" and string.find(far.sub, "unloaded", 1, true) and #(far.buttons or {}) == 1, "unloaded pump: shown, only Refill")
ok(pumps[1].tone == "red", "problems first")

local ft = find(tanks, "Riverside farm tote")
ok(ft and string.find(ft.sub, "640 / 1000 L clean", 1, true) and ft.tone == "green", "farm tank 640/1000 clean: " .. tostring(ft and ft.sub))
local st = find(tanks, "School barrels")
ok(st and string.find(st.sub, "tainted", 1, true) and st.tone == "amber", "school tank tainted")
ok(st and #st.buttons == 2 and st.buttons[2].danger == true, "Fill and Empty (danger)")
local pt = find(tanks, "Propane tank")
ok(pt and pt.tone == "muted" and #pt.buttons == 1 and pt.buttons[1].label == "Fill", "empty propane tank: Fill only")
ok(find(tanks, "Petrol tank") and find(tanks, "Petrol tank").tone == "red", "cracked tank red")
local ut = find(tanks, "tank at 600, 600")
ok(ut and ut.tone == "muted" and ut.buttons == nil, "piped unloaded tank listed, no buttons")
ok(#v.cards[2].lines == 1, "tanks card says unloaded unpiped tanks cannot be listed")

local sl = find(links, "Pipe end at 25, 25")
ok(sl and sl.tone == "red" and sl.buttons[1].command == "clearLink", "stuck tank end with Clear link")
ok(find(links, "Pipe end at 26, 30") ~= nil, "stuck pump end listed")
local mn = find(links, "Water main at 3, 30")
ok(mn and mn.tone == "green" and string.find(mn.sub, "2 fixtures", 1, true), "main feeds two fixtures: " .. tostring(mn and mn.sub))
local um = find(links, "Water main at 800, 800")
ok(um and um.tone == "muted", "unloaded main muted")
ok(find(links, "Pipe end at 600, 600") == nil, "an unloaded end is never stuck")

local marks = C.tabs.plumbing.marks(admin)
ok(#marks >= 10, "marks for pumps, tanks, mains and stuck links: " .. #marks)
local redMarks = 0
for _, m in ipairs(marks) do if m.tone == "red" and string.find(m.label, "Stuck", 1, true) then redMarks = redMarks + 1 end end
ok(redMarks == 2, "two red stuck marks")

-- a long list is capped
for i = 1, 20 do well(100 + i, 900, 800) end
local v2 = C.tabs.plumbing.view(admin)
ok(#v2.cards[1].items == T.CAP + 1 and string.find(v2.cards[1].items[T.CAP + 1].text, "more", 1, true), "pumps capped with an 'and N more' row")
for i = 1, 20 do ModData.getOrCreate(U.WELLS).wells[N.key(100 + i, 900, 0)] = nil end

-- ------------------------------------------------------------ the picture data (through Core's own marking)
local sent
Net.onClient(C.MODULE, "ctlView", function(args) sent = args end)
C.sendView(admin, "plumbing")
ok(sent and sent.tab == "plumbing" and sent.view.clock == "D19 10:42", "Core sends the view")
local allNeed = true
for _, card in ipairs(sent.view.cards) do
    for _, it in ipairs(card.items or {}) do
        for _, b in ipairs(it.buttons or {}) do if b.need ~= "admin" or b.module ~= T.MODULE then allNeed = false end end
    end
end
ok(allNeed, "every button marked need = admin")

local function ser(v, ind)
    ind = ind or ""
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) ~= "table" then return tostring(v) end
    local parts, nxt = {}, ind .. "  "
    for i = 1, #v do parts[#parts + 1] = nxt .. ser(v[i], nxt) end
    local keys = {}
    for k in pairs(v) do if type(k) ~= "number" or k < 1 or k > #v or k ~= math.floor(k) then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        local ks = (type(k) == "string" and string.match(k, "^[%a_][%w_]*$")) and k or ("[" .. ser(k) .. "]")
        parts[#parts + 1] = nxt .. ks .. " = " .. ser(v[k], nxt)
    end
    if #parts == 0 then return "{}" end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. ind .. "}"
end
local out = os.getenv("CONTROL_VIEWS") or "/home/claude/work/views"
local fh = io.open(out .. "/plumbing.lua", "w")
if fh then
    fh:write("return " .. ser({ tab = "plumbing", target = nil, view = sent.view }) .. "\n")
    fh:close()
    print("wrote " .. out .. "/plumbing.lua")
end

-- ------------------------------------------------------------ commands
local function run(who, cmd, args)
    local h = Net.server[T.MODULE][cmd]
    h.fn(who, args)
end
local function snapshot()
    local d1, d2 = P.data(farmTank), P.data(schoolTank)
    local w = ModData.getOrCreate(U.WELLS).wells
    return table.concat({ tostring(farmPump.md.dazedOff), d1.amount, tostring(d1.dirty), d2.amount, tostring(d2.dirty),
        P.data(propTank).amount, w["20,10,0"].reserve, tostring(K.index()[stuckTank] ~= nil), tostring(K.index()[stuckPump] ~= nil),
        tostring(stuckPumpReg.links["26,30,0|" .. U.ID] ~= nil) }, "|")
end
local before = snapshot()
local cmds = {
    { "pumpSwitch", { x = 10, y = 10, z = 0, on = false } },
    { "wellRefill", { x = 20, y = 10, z = 0 } },
    { "tankFill", { x = 22, y = 14, z = 0 } },
    { "tankEmpty", { x = 12, y = 10, z = 0 } },
    { "clearLink", { x = 25, y = 25, z = 0, role = "tank", id = "tank" } },
    { "clearLink", { x = 26, y = 30, z = 0, role = "source", id = U.ID } },
}
for _, who in ipairs({ moder, plain }) do
    for _, c in ipairs(cmds) do run(who, c[1], c[2]) end
    ok(snapshot() == before, (C.level(who) or "a plain player") .. " changes nothing")
end
-- the same refusal through Core's button path
Net.server[C.MODULE].ctlAct.fn(moder, { tab = "plumbing", module = T.MODULE, command = "tankEmpty", args = { x = 12, y = 10, z = 0 } })
ok(snapshot() == before, "a moderator's button press is refused by Core too")

-- bad arguments change nothing
run(admin, "pumpSwitch", { x = 10.5, y = 10, z = 0, on = false })
run(admin, "pumpSwitch", { x = 10, y = 10, z = 0, on = "no" })
run(admin, "pumpSwitch", { x = 20, y = 10, z = 0, on = false })          -- a hand pump has no switch
run(admin, "tankFill", { x = 5, y = 5, z = 0 })                           -- no tank there
run(admin, "tankFill", { x = "22", y = 14, z = 0 })
run(admin, "wellRefill", { x = 55, y = 55, z = 0 })                       -- no well there
run(admin, "clearLink", { x = 12, y = 10, z = 0, role = "tank", id = "tank" })  -- the tank is there: not stuck
run(admin, "clearLink", { x = 600, y = 600, z = 0, role = "tank", id = "tank" }) -- unloaded: never touched
run(admin, "clearLink", { x = 25, y = 25, z = 0, role = "bogus", id = "tank" })
run(admin, "clearLink", { x = 25, y = 25, z = 0, role = "tank", id = "a|b" })
run(admin, "clearLink", { x = 25, y = 25, z = 0, role = "tank", id = {} })
ok(snapshot() == before, "bad or refused arguments change nothing")
ok(K.index()["600,600,0|tank|tank"] ~= nil, "the unloaded end is kept")

-- as admin
run(admin, "pumpSwitch", { x = 10, y = 10, z = 0, on = false })
ok(farmPump.md.dazedOff == true and U.isOff(farmPump), "admin switches the pump off")
local v3 = C.tabs.plumbing.view(admin)
local fp3 = find(v3.cards[1].items, "Electric pump at 10, 10")
ok(fp3 and fp3.tone == "amber" and fp3.buttons[1].label == "On", "off pump shows On")
run(admin, "pumpSwitch", { x = 10, y = 10, z = 0, on = true })
ok(farmPump.md.dazedOff == nil and not U.isOff(farmPump), "and on again")

run(admin, "wellRefill", { x = 20, y = 10, z = 0 })
ok(ModData.getOrCreate(U.WELLS).wells["20,10,0"].reserve == 800, "admin refills the dry well")

run(admin, "tankFill", { x = 22, y = 14, z = 0 })
local sd = P.data(schoolTank)
ok(near(sd.amount, M.capacity("small", "salvaged", "water")) and not M.isTainted(sd), "admin fills the school tank clean: " .. sd.amount)
run(admin, "tankEmpty", { x = 12, y = 10, z = 0 })
ok(P.data(farmTank).amount == 0, "admin empties the farm tank")
run(admin, "tankFill", { x = 40, y = 12, z = 0 })
ok(near(P.data(propTank).amount, 45), "propane tank filled in kg")

run(admin, "clearLink", { x = 25, y = 25, z = 0, role = "tank", id = "tank" })
ok(K.index()[stuckTank] == nil and K.pipes()["26,25,0"] == nil, "admin clears the stuck tank end and its dead pipe")
run(admin, "clearLink", { x = 26, y = 30, z = 0, role = "source", id = U.ID })
ok(K.index()[stuckPump] == nil and stuckPumpReg.links["26,30,0|" .. U.ID] == nil, "stuck pump end and registry entry cleared")
ok(K.index()["12,10,0|tank|tank"] ~= nil and K.index()["600,600,0|tank|tank"] ~= nil, "other ends untouched")
local v4 = C.tabs.plumbing.view(admin)
ok(v4.lamps[4][1] == "Stuck links: 0" and v4.lamps[4][2] == "green", "no stuck links left")

-- through Core's button path as admin
Net.server[C.MODULE].ctlAct.fn(admin, { tab = "plumbing", module = T.MODULE, command = "tankEmpty", args = { x = 22, y = 14, z = 0 } })
ok(P.data(schoolTank).amount == 0, "admin's button press runs through Core")

for _, l in ipairs(E.printed) do if string.find(l, "failed", 1, true) then fails = fails + 1 print("FAIL: console: " .. l) end end
print(string.format("control_tab_test: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
