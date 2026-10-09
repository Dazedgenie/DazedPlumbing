-- The biogas digester on a fake engine: model maths, the add-waste logic, gas into a piped propane tank, load catch-up, placement and the file counts.
-- Run: lua digester_test.lua <common/media/lua> [<core lua root>]
local root = arg[1] or "../../common/media/lua"
local core = arg[2] or "../../../DazedCore/common/media/lua"      -- Dazed Core, required
package.path = core .. "/shared/?.lua;" .. core .. "/client/?.lua;" .. root .. "/shared/?.lua;" .. root .. "/server/?.lua;" .. root .. "/client/?.lua;" .. package.path
local E = dofile("engine_stub.lua")
local fails, n = 0, 0
local function ok(c, msg) n = n + 1 if not c then fails = fails + 1 E.realPrint("FAIL: " .. msg) end end
local function near(a, b, tol) return math.abs(a - b) < (tol or 1e-4) end
local function slurp(path) local f = assert(io.open(path, "rb")) local s = f:read("*a") f:close() return s end
local media = root .. "/.."

require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Sync"
require "DazedPlumbing/DUP_Net"
require "DazedPlumbing/DUP_Pipes"
require "DazedPlumbing/DUP_Links"
require "DazedPlumbing/DUP_LinkActions"
require "DazedPlumbing/DUP_Pumps"
require "DazedPlumbing/DUP_FuelPumps"
require "DazedPlumbing/DUP_Digesters"
require "DazedPlumbing/DUP_DigesterActions"
local P, M, L, Dg = DazedPlumb.Parts, DazedPlumb.Model, DazedPlumb.Links, DazedPlumb.Digesters

E.grid(60, 60)
getSpecificPlayer = function() return nil end
instanceof = function(o, cls) return cls == "Food" and type(o) == "table" and o.isFood == true end
local TEMP = 20
getClimateManager = function()
    return { getAirTemperatureForSquare = function() return TEMP end, getTemperature = function() return TEMP end }
end
MapObjects = { loads = {}, news = {},
    OnLoadWithSprite = function(name, f) MapObjects.loads[name] = f end,
    OnNewWithSprite = function(name, f) MapObjects.news[name] = f end }

------------------------------------------------------------------ taxonomy: sprites, items, tiles, recipe, translations
ok(Dg.BASE == 244 and Dg.COUNT == 4, "digester sprites are appended at 244..247, after the fuel pumps' 236-243")
ok(Dg.BASE == DazedPlumb.FuelPumps.BASE + DazedPlumb.FuelPumps.COUNT, "the block starts where the fuel pumps end")
ok(Dg.sprite("E") == "dazedplumb_01_244" and Dg.sprite("S") == "dazedplumb_01_245" and Dg.sprite("N") == "dazedplumb_01_247", "facing sprites")
for i, f in ipairs(Dg.FACINGS) do
    local info = Dg.spriteInfo(Dg.sprite(f))
    ok(info and info.facing == f, "round trip " .. f)
    local o = E.object(Dg.sprite(f), E.square(2, i))
    ok(Dg.isDigester(o) and L.adapterFor(o) == L.adapters[Dg.ID], "a digester is found by its sprite: " .. f)
end
ok(Dg.spriteInfo("dazedplumb_01_243") == nil and Dg.spriteInfo("dazedplumb_01_248") == nil, "neighbouring tiles are not digesters")
ok(DazedPlumb.FuelPumps.spriteInfo("dazedplumb_01_244") == nil and DazedPlumb.Pumps.spriteInfo("dazedplumb_01_245") == nil, "no overlap with the pumps")
ok(not Dg.isDigester(E.object(DazedPlumb.FuelPumps.sprite("hand", "S"), E.square(3, 3))), "a fuel pump is not a digester")

require "DazedPlumbing/DUP_Boot"
local itemsTxt = slurp(media .. "/scripts/dup_items.txt")
local defined = {}
for name in itemsTxt:gmatch("\n%s+item%s+(%w+)") do defined[name] = true end
local itemCount = 0 for _ in pairs(defined) do itemCount = itemCount + 1 end
ok(itemCount == 32 and defined.DazedDigester, "32 items, DazedDigester among them, found " .. itemCount)
getScriptManager = function() return { getItem = function(_, ft) return defined[ft:match("%.(.+)$")] and {} or nil end } end
getSprite = function(name) local i = tonumber(name:match("_(%d+)$")) return (i and i < 256) and {} or nil end
for _, h in ipairs(Events.OnGameStart.handlers) do h() end
local boot
for _, line in ipairs(E.printed) do if line:find("DazedPlumbing: ready") or line:find("INCOMPLETE") then boot = line end end
ok(boot and boot:find("252/252 tiles, 32/32 items", 1, true), "boot check counts the digester: " .. tostring(boot))
ok(DazedPlumb.VERSION == "0.16.1" and slurp(media .. "/../../42/mod.info"):find("modversion=0.16.1", 1, true) ~= nil, "version 0.16.1 in the Lua and in mod.info")

local w = tonumber(itemsTxt:match("item DazedDigester%s*{.-Weight%s*=%s*([%d%.]+)"))
ok(w and w < DazedCore.Heavy.LIMIT and DazedCore.Heavy.count(w) == 1, "the digester is one piece under the heavy limit, " .. tostring(w) .. " kg")
ok(itemsTxt:find("WorldObjectSprite   = " .. Dg.sprite("S"), 1, true), "the item points at its south tile")
local tilesTxt = slurp(media .. "/dazedplumbing_tiles.tiles.txt")
local _, hits = tilesTxt:gsub("Base%.DazedDigester", "")
ok(hits == 4 and tilesTxt:find("Biogas Digester", 1, true), "four tiles carry the digester item, found " .. hits)
ok(slurp(media .. "/textures/Item_DazedDigester.png"):sub(2, 4) == "PNG", "the item icon exists")

local recipes = slurp(media .. "/scripts/dup_recipes.txt")
local _, recipeCount = recipes:gsub("craftRecipe ", "")
ok(recipeCount == 32, "32 recipes, found " .. recipeCount)
local r = recipes:match("craftRecipe MakeDazedDigester(.-)\n    }\n")
ok(r ~= nil, "the digester recipe exists")
r = r or ""
ok(tonumber(r:match("MetalWelding:(%d)")) == 2, "it needs Welding 2")
for _, need in ipairs({ "Base.MetalDrum", "Base.MetalPipe", "Base.DazedValve", "Base.Screws", "Base.BlowTorch", "base:weldingmask" }) do
    ok(r:find(need, 1, true), "the recipe uses " .. need)
end
ok(r:find("Base.DazedDigester", 1, true), "and makes the digester")

local function json(f) return slurp(root .. "/shared/Translate/EN/" .. f .. ".json") end
local keys = {
    ItemName = { "Base.DazedDigester" }, Recipes = { "MakeDazedDigester" }, Moveables = { "Dazed_Plumbing_Biogas_Digester" },
    Tooltip = { "Tooltip_DazedDigester" },
    ContextMenu = { "ContextMenu_DazedPlumb_Digester", "ContextMenu_DazedPlumb_DigesterLine", "ContextMenu_DazedPlumb_DigesterAdd",
                    "ContextMenu_DazedPlumb_DigesterAddNone", "ContextMenu_DazedPlumb_DigesterAddAll", "ContextMenu_DazedPlumb_DigesterAddOne" },
    IG_UI = { "IGUI_DazedPlumb_DigesterWaste", "IGUI_DazedPlumb_DigesterGas", "IGUI_DazedPlumb_DigesterOutput", "IGUI_DazedPlumb_DigesterStatus",
              "IGUI_DazedPlumb_DigesterNotPiped", "IGUI_DazedPlumb_Digester_idle", "IGUI_DazedPlumb_Digester_ok", "IGUI_DazedPlumb_Digester_cold",
              "IGUI_DazedPlumb_Digester_frozen", "IGUI_DazedPlumb_Digester_held", "IGUI_DazedPlumb_Digester_full", "IGUI_DazedPlumb_Digester_bad",
              "IGUI_DazedPlumb_Digester_far" },
}
local keyCount = 0
for file, list in pairs(keys) do
    local text = json(file)
    for _, k in ipairs(list) do
        keyCount = keyCount + 1
        ok(text:find('"' .. k .. '"', 1, true) ~= nil, "EN " .. file .. ".json has " .. k)
    end
end
ok(keyCount == 23, "23 translation keys checked, " .. keyCount)
-- every status and refusal the code can name has a line
local statusSeen = { idle = false, ok = false, cold = false, frozen = false, held = false }
local codeText = slurp(root .. "/shared/DazedPlumbing/DUP_Digesters.lua")
for k in pairs(statusSeen) do ok(codeText:find('"' .. k .. '"', 1, true) ~= nil, "status " .. k .. " is in the code") end
for _, f in ipairs({ "shared/DazedPlumbing/DUP_Digesters.lua", "shared/DazedPlumbing/DUP_DigesterActions.lua", "client/DazedPlumbing/DUP_DigesterMenu.lua",
                     "server/DazedPlumbing/DUP_DigesterWorld.lua", "shared/DazedPlumbing/DUP_Place.lua", "shared/DazedPlumbing/DUP_Boot.lua" }) do
    ok(loadfile(root .. "/" .. f) ~= nil, f .. " compiles")
end
ok(not slurp(media .. "/sandbox-options.txt"):find("Digester", 1, true), "no sandbox option was added")

------------------------------------------------------------------ the model maths
ok(Dg.tempFactor(20) == 1 and Dg.tempFactor(10) == 1 and Dg.tempFactor(nil) == 1, "10 C and above: full speed (unknown counts as warm)")
ok(Dg.tempFactor(9.9) == 0.5 and Dg.tempFactor(0) == 0.5 and Dg.tempFactor(5) == 0.5, "below 10 C: half")
ok(Dg.tempFactor(-0.1) == 0 and Dg.tempFactor(-20) == 0, "below 0 C: stopped")

local d1, g1 = Dg.digest(1, 100000, 1, 2)
ok(near(g1, 0.05, 1e-9) and near(d1, 1, 1e-9), "one unit of waste makes 0.05 kg of propane in all")
local _, g24 = Dg.digest(24, 1, 1, 2)
ok(near(g24, 0.05, 0.002), "24 units make about 0.05 kg in an hour, got " .. g24)
local dDay = Dg.digest(10, 24, 1, 2)
ok(near(dDay, 10 * (1 - math.exp(-1)), 1e-9), "a unit's mean digestion time is 24 h: 63% in the first day")
local rem, gasSum = 10, 0
for _ = 1, 1440 do local d, g = Dg.digest(rem, 1 / 60, 1, 2) rem, gasSum = rem - d, gasSum + g end
local _, gOnce = Dg.digest(10, 24, 1, 2)
ok(near(gasSum, gOnce, 1e-6), "a day in minute steps gives the same gas as one day-long step")
local waste, total, steps = 12, 0, 0
while waste > 0 and steps < 100000 do local d, g = Dg.digest(waste, 1, 1, 2) waste, total, steps = waste - d, total + g, steps + 1 end
ok(near(total, 12 * 0.05, 1e-9) and waste == 0, "digesting to the end gives 0.05 kg per unit exactly, got " .. total)
local _, gc = Dg.digest(10, 1, 0.5, 2)
local _, gw = Dg.digest(10, 1, 1, 2)
ok(near(gc / gw, 0.5, 0.01), "cold halves the gas, ratio " .. gc / gw)
ok(select(2, Dg.digest(40, 100, 0, 2)) == 0, "frozen makes none")
local dCap, gCap = Dg.digest(40, 1000, 1, 0.3)
ok(near(gCap, 0.3) and near(dCap, 6), "the gas buffer caps what a step makes (0.3 kg of room: 6 units)")
ok(select(2, Dg.digest(40, 10, 1, 0)) == 0 and select(1, Dg.digest(40, 10, 1, 0)) == 0, "a full buffer pauses digestion, the waste stays")
ok(near(Dg.rate(24, 1), 0.05) and near(Dg.rate(24, 0.5), 0.025) and Dg.rate(24, 0) == 0, "the hourly rate shown in the menu")
ok(Dg.BUF_CAP == 2 and Dg.SLURRY_CAP * Dg.GAS_PER_UNIT == Dg.BUF_CAP, "a full drum holds exactly a full buffer of gas")
ok(Dg.room(0) == 40 and Dg.room(39.5) == 0.5 and Dg.room(50) == 0, "room for waste")

-- the state, settled by the clock
local function digesterAt(x, y, waste, buf, hour, facing)
    local o = E.object(Dg.sprite(facing or "S"), E.square(x, y))
    o.md.dazedDigester = { waste = waste, buf = buf, hour = hour }
    return o
end
E.hours = 1000
local s1 = digesterAt(10, 1, 40, 0, 1000 - 24)
Dg.settle(s1, 1000, 20)
ok(near(s1.md.dazedDigester.buf, 40 * (1 - math.exp(-1)) * 0.05, 1e-9) and s1.md.dazedDigester.hour == 1000, "a day away settles a day of gas")
local s2 = digesterAt(10, 2, 40, 0, 1000 - 500)
Dg.settle(s2, 1000, 20)
local capped = select(2, Dg.digest(40, 48, 1, 2))
ok(near(s2.md.dazedDigester.buf, capped, 1e-9) and capped < 2, "an absence of 500 h is capped at 48 h of gas, " .. capped)
local s3 = digesterAt(10, 3, 40, 0, 1000 - 48)
Dg.settle(s3, 1000, 20)
ok(near(s3.md.dazedDigester.buf, s2.md.dazedDigester.buf, 1e-9), "48 h and 500 h away give the same")
local s4 = digesterAt(10, 4, 40, 0, 1000 - 10)
Dg.settle(s4, 1000, -5)
ok(s4.md.dazedDigester.buf == 0 and s4.md.dazedDigester.waste == 40, "a frozen digester away makes nothing and keeps its waste")
local s5 = digesterAt(10, 5, 40, 0, 1000 - 1)
Dg.settle(s5, 1000, 4)
local s6 = digesterAt(10, 6, 40, 0, 1000 - 1)
Dg.settle(s6, 1000, 15)
ok(near(s5.md.dazedDigester.buf / s6.md.dazedDigester.buf, 0.5, 0.03), "a cold spell halves it")
local s7 = digesterAt(10, 7, 40, 1.99, 1000 - 48)
Dg.settle(s7, 1000, 20)
ok(near(s7.md.dazedDigester.buf, 2) and s7.md.dazedDigester.waste > 30, "the buffer never passes 2 kg and the rest of the waste stays")
local s8 = digesterAt(10, 8, 40, 0, nil)
ok(Dg.settle(s8, 1000, 20) == false and s8.md.dazedDigester.hour == 1000 and s8.md.dazedDigester.buf == 0, "a digester with no clock yet only starts it")
local s9 = digesterAt(10, 9, 40, 0, 1010)
Dg.settle(s9, 1000, 20)
ok(s9.md.dazedDigester.buf == 0 and s9.md.dazedDigester.hour == 1000, "a clock that went backwards makes no gas")
local sTemp = digesterAt(10, 10, 5, 0, 1000)
TEMP = 20 ok(Dg.status(sTemp) == "ok", "status: digesting")
TEMP = 5 ok(Dg.status(sTemp) == "cold", "status: cold")
TEMP = -2 ok(Dg.status(sTemp) == "frozen", "status: frozen")
TEMP = 20
sTemp.md.dazedDigester.buf = 2 ok(Dg.status(sTemp) == "held", "status: buffer full")
sTemp.md.dazedDigester.waste = 0 ok(Dg.status(sTemp) == "idle", "status: no waste")

------------------------------------------------------------------ adding waste
local ch = E.character(20, 20, 0, 1)
local function food(fullType, opts)
    local it = E.item(fullType)
    it.isFood = true
    for k, v in pairs(opts or {}) do it[k] = v end
    ch.inv:AddItem(it)
    return it
end
local function carried(it) for _, v in ipairs(ch.inv.items) do if v == it then return true end end return false end
local removedSent = 0
sendRemoveItemFromContainer = function() removedSent = removedSent + 1 end
local dig = digesterAt(20, 21, 0, 0, 1000)
dig.md.dazedDigester.hour = E.hours

local rotten = food("Base.Apple", { isRotten = function() return true end })
local fresh = food("Base.Apple", { isRotten = function() return false end })
local old = food("Base.Steak", { isRotten = function() return false end, getAge = function() return 12 end, getOffAgeMax = function() return 10 end })
local young = food("Base.Steak", { getAge = function() return 3 end, getOffAgeMax = function() return 10 end })
local nails = E.item("Base.Nails") ch.inv:AddItem(nails)
local never = food("Base.Salt", { getAge = function() return 900 end, getOffAgeMax = function() return 1e9 end })
ok(select(1, Dg.classify(rotten)) == "food" and select(2, Dg.classify(rotten)) == 1, "rotten food is one unit")
ok(Dg.classify(fresh) == nil and Dg.classify(young) == nil and Dg.classify(nails) == nil and Dg.classify(never) == nil, "fresh food, a plain item and food that never spoils are not waste")
ok(Dg.classify(old) == "food", "food past its off-age counts as rotten even without isRotten")
local added, why = Dg.add(dig, rotten)
ok(added == 1 and dig.md.dazedDigester.waste == 1 and not carried(rotten), "adding rotten food: +1 unit and the item is gone")
ok(removedSent == 1, "the removal was sent to clients")
added, why = Dg.add(dig, fresh)
ok(added == 0 and why == "bad" and carried(fresh) and dig.md.dazedDigester.waste == 1, "fresh food is refused and kept")
local manure = E.item("Base.Dung_Cow") ch.inv:AddItem(manure)
local chicken = E.item("Base.Dung_Chicken") ch.inv:AddItem(chicken)
ok(select(1, Dg.classify(manure)) == "dung" and select(2, Dg.classify(manure)) == 2 and Dg.classify(chicken) == "dung", "manure items are two units, any animal")
added = Dg.add(dig, manure)
ok(added == 2 and dig.md.dazedDigester.waste == 3 and not carried(manure), "manure: +2 units")
local uses = 4
local bag = E.item("Base.CompostBag") ch.inv:AddItem(bag)
bag.getCurrentUses = function() return uses end
bag.Use = function() uses = uses - 1 end
added = Dg.add(dig, bag)
ok(added == 2 and uses == 3 and carried(bag) and dig.md.dazedDigester.waste == 5, "a compost bag gives 2 units a use and stays until empty")
uses = 0
ok(Dg.classify(bag) == nil and select(2, Dg.add(dig, bag)) == "bad", "an empty compost bag is not waste")
uses = 2
local bag2 = E.item("Base.CompostBag") ch.inv:AddItem(bag2)
bag2.getCurrentUses = function() return 2 end
bag2.Use = function() error("boom") end
ok(Dg.add(dig, bag2) == 0 and dig.md.dazedDigester.waste == 5, "an engine call that throws adds nothing and does not crash")
local weird = food("Base.Apple", { isRotten = function() error("boom") end })
ok(Dg.classify(weird) == nil, "a throwing isRotten is guarded: not waste")
local hurt = E.item("Base.Dung_Pig") ch.inv:AddItem(hurt)
hurt.getContainer = function() return nil end
ok(Dg.add(dig, hurt) == 0 and dig.md.dazedDigester.waste == 5, "an item that is in no container is not consumed")

-- the drum fills up
dig.md.dazedDigester.waste = 39
local last = food("Base.Bread", { isRotten = function() return true end })
local dung2 = E.item("Base.Dung_Sheep") ch.inv:AddItem(dung2)
local a1, w1 = Dg.add(dig, dung2)
ok(a1 == 0 and w1 == "full" and carried(dung2), "2 units do not fit in 1 unit of room")
ok(Dg.add(dig, last) == 1 and dig.md.dazedDigester.waste == 40, "1 unit fills it to exactly 40")
local more = food("Base.Bread", { isRotten = function() return true end })
local a2, w2 = Dg.add(dig, more)
ok(a2 == 0 and w2 == "full" and carried(more) and dig.md.dazedDigester.waste == 40, "a full drum refuses more")

-- the timed action, run on the authority
dig.md.dazedDigester.waste = 0
local item1 = food("Base.Apple", { isRotten = function() return true end })
local act = DUP_DigesterAdd:new(ch, dig, item1)
local allowed = { character = true, digester = true, item = true, maxTime = true }
local plain = true
for k in pairs(act) do if not allowed[k] then plain = false end end
ok(plain and act.digester == dig and act.item == item1, "the action carries only the character, the digester and the item")
ok(act:isValid() and act.maxTime == 1, "the add action is valid (instant in the stub)")
act:complete()
ok(dig.md.dazedDigester.waste == 1 and not carried(item1), "complete() adds the waste on the authority")
local item2 = food("Base.Apple", { isRotten = function() return true end })
local far = E.character(40, 40, 0, 1)
DUP_DigesterAdd:new(far, dig, item2):complete()
ok(dig.md.dazedDigester.waste == 1 and carried(item2), "a player too far away adds nothing")
item2.container = nil
DUP_DigesterAdd:new(ch, dig, item2):complete()
ok(dig.md.dazedDigester.waste == 1, "an item nobody carries any more adds nothing")
local item3 = food("Base.Apple", { isRotten = function() return false end })
DUP_DigesterAdd:new(ch, dig, item3):complete()
ok(dig.md.dazedDigester.waste == 1 and carried(item3) and #ch.notes >= 1, "a fresh apple is refused with a note")
local item4 = food("Base.Apple", { isRotten = function() return true end })
local act4 = DUP_DigesterAdd:new(ch, dig, item4)
dig.md.dazedDigester.waste = 40
act4.checks = 0
ok(not act4:isValid(), "the action stops being valid once the drum is full")
dig.md.dazedDigester.waste = 0
act4.checks = 0
item4.isRotten = function() return false end
ok(not act4:isValid(), "or once the item is no longer rotten")
local gone = digesterAt(22, 22, 0, 0, 1000)
local actGone = DUP_DigesterAdd:new(ch, gone, item4)
gone.square = nil
ok(not actGone:isValid(), "or once the digester is gone")

------------------------------------------------------------------ gas into a piped propane tank
local function tankAt(x, y, typ, amount)
    local o = E.object(P.sprite("small", typ, "crafted", "S", 1), E.square(x, y))
    o.md.dazedplumb = { amount = amount, condition = 100 }
    return o
end
local function pipe(machine, tank)
    local c = E.character(machine:getSquare():getX(), machine:getSquare():getY(), 0, 1)
    E.give(c, "Base.DazedPipeSection", 12)
    DUP_PipeSet:new(c, machine, Dg.ID, tank):complete()
    return c
end
local adapter = L.adapters[Dg.ID]
ok(adapter and adapter.produces == "propane" and not adapter.supplies, "the digester is a propane SOURCE")

E.hours = 2000
local gas = tankAt(35, 30, "propane", 0)
local dg = digesterAt(30, 30, 40, 0, 2000)
ok(Dg.line(dg).state == "unpiped", "a new digester is not piped")
pipe(dg, gas)
local line = Dg.line(dg)
ok(line.state == "ok" and near(line.room, 45), "piped to a 45 kg propane tank: it has 45 kg of room")
E.hours = 2001
L.tick()
local made1 = 40 * (1 - math.exp(-1 / 24)) * 0.05
ok(near(P.data(gas).amount, made1, 1e-6) and near(dg.md.dazedDigester.buf, 0, 1e-9), "an hour of digestion put " .. made1 .. " kg in the tank, got " .. P.data(gas).amount)
ok(near(dg.md.dazedDigester.waste, 40 - 40 * (1 - math.exp(-1 / 24)), 1e-6), "and used up the matching slurry")

-- the clock-driven minute tick, as the tank sees it
local tank0 = P.data(gas).amount
for i = 1, 60 do E.hours = 2001 + i / 60 L.tick() end
local expect = (40 * math.exp(-1 / 24)) * (1 - math.exp(-1 / 24)) * 0.05
ok(near(P.data(gas).amount - tank0, expect, 1e-5), "sixty minute ticks make the same as an hour: " .. (P.data(gas).amount - tank0))

-- cold and frozen
local gas2 = tankAt(45, 30, "propane", 0)
local dgc = digesterAt(40, 30, 40, 0, 2100)
pipe(dgc, gas2)
E.hours, TEMP = 2101, 5
L.tick()
local half = P.data(gas2).amount
local gas3 = tankAt(45, 36, "propane", 0)
local dgw = digesterAt(40, 36, 40, 0, 2100)
pipe(dgw, gas3)
TEMP = 20
L.tick()
ok(near(half / P.data(gas3).amount, 0.5, 0.02), "at 5 C the digester makes half of what it makes at 20 C")
TEMP = -3
local before = P.data(gas2).amount
E.hours = 2110
L.tick()
ok(near(P.data(gas2).amount, before, 1e-9), "below 0 C it makes nothing")
TEMP = 20

-- a full tank stops the flow; the gas waits in the buffer, capped, and digestion pauses
local full = tankAt(35, 40, "propane", 45)
local dgf = digesterAt(30, 40, 40, 0, 3000)
pipe(dgf, full)
E.hours = 3048
L.tick()
ok(near(P.data(full).amount, 45), "a full tank takes nothing")
ok(near(dgf.md.dazedDigester.buf, capped, 1e-9), "the gas is held in the buffer: " .. dgf.md.dazedDigester.buf .. " kg")
dgf.md.dazedDigester.buf, dgf.md.dazedDigester.waste = 2, 10
E.hours = 3060
L.tick()
ok(near(dgf.md.dazedDigester.buf, 2) and near(dgf.md.dazedDigester.waste, 10), "a full buffer on a full tank: no more gas, the waste stays")
ok(Dg.status(dgf) == "held", "and the status says so")
P.data(full).amount = 0
E.hours = 3060 + 1 / 60
L.tick()
ok(near(P.data(full).amount, 1, 1e-6) and near(dgf.md.dazedDigester.buf, 1, 0.01), "room in the tank: the buffer drains at 1 kg a minute")
E.hours = 3060 + 2 / 60
L.tick()
ok(P.data(full).amount > 1.9 and dgf.md.dazedDigester.buf < 0.1, "and is empty a minute later")

-- a paused line gives nothing
local gas4 = tankAt(35, 46, "propane", 0)
local dgp = digesterAt(30, 46, 40, 0, 3100)
pipe(dgp, gas4)
L.setSource(dgp, adapter, "manual")
E.hours = 3101
L.tick()
Dg.register(dgp)
Dg.tick()
ok(near(P.data(gas4).amount, 0) and dgp.md.dazedDigester.buf > 0, "a paused line keeps the gas in the buffer")
ok(Dg.line(dgp).state == "paused", "and says paused")

-- a petrol or water tank takes no digester gas
local wtank = tankAt(35, 52, "water", 0)
local dgw2 = digesterAt(30, 52, 40, 0, 3200)
local chw = E.character(30, 52, 0, 1)
E.give(chw, "Base.DazedPipeSection", 12)
DUP_PipeSet:new(chw, dgw2, Dg.ID, wtank):complete()
ok(Dg.line(dgw2).state == "unpiped", "a water tank is not a place for gas")

-- loose in the world (not piped): the live tick fills the buffer
local solo = digesterAt(50, 50, 40, 0, 4000)
Dg.register(solo)
E.hours = 4001
Dg.tick()
ok(solo.md.dazedDigester.buf > 0.08 and solo.md.dazedDigester.buf < 0.09, "an unpiped digester stores its gas: " .. solo.md.dazedDigester.buf)
-- a client changes nothing
local keepClient = isClient
isClient = function() return true end
E.hours = 4010
Dg.tick()
ok(solo.md.dazedDigester.hour == 4001, "a client does not settle or tick a digester")
-- the gauge on a client asks the adapter what the digester can give: it previews, and writes nothing
local seen = digesterAt(51, 50, 40, 0.5, 4000)
local sends = 0
seen.transmitModData = function() sends = sends + 1 end
isClient = function() return true end
E.hours = 4024
local offered = L.adapters[Dg.ID].available(seen)
local wantBuf = math.min(Dg.BUF_CAP, 0.5 + select(2, Dg.digest(40, 24, 1, Dg.BUF_CAP - 0.5)))
ok(near(offered, wantBuf, 1e-9), "a client's available() previews a day of gas: " .. offered)
local sd = seen.md.dazedDigester
ok(sd.hour == 4000 and sd.waste == 40 and sd.buf == 0.5 and sends == 0, "and leaves the state alone and sends nothing")
Dg.refresh(seen)
Dg.publish(seen)
ok(sd.hour == 4000 and sends == 0 and Dg.live[seen] == nil, "refresh and publish do nothing on a client")
local noState = E.object(Dg.sprite("S"), E.square(52, 50))
ok(Dg.preview(noState).buf == 0 and noState.md.dazedDigester == nil, "a preview of a digester with no state is empty and creates none")
isClient = keepClient
ok(near(L.adapters[Dg.ID].available(seen), wantBuf, 1e-9) and sd.hour == 4024 and sends == 1, "the authority settles to the same figure and sends it once")
ok(Dg.live[seen] == true, "a published digester is on the live list, so the tick can forget it")
seen.square = nil
Dg.tick()
ok(Dg.live[seen] == nil, "and it leaves once lifted")
-- the smoker follows the same rule: a client never settles or publishes one
require "DazedPlumbing/DUP_Smokers"
local Sm = DazedPlumb.Smokers
local smk = E.object(Sm.sprite("S"), E.square(53, 50))
smk.md.dazedSmoker = { lit = true, hour = 4000, prog = {} }
local smkSends = 0
smk.transmitModData = function() smkSends = smkSends + 1 end
isClient = function() return true end
Sm.refresh(smk)
Sm.publish(smk, true)
ok(smk.md.dazedSmoker.hour == 4000 and smk.md.dazedSmoker.lit == true and smkSends == 0 and Sm.live[smk] == nil,
    "a client's smoker refresh and publish change and send nothing")
isClient = keepClient
Sm.publish(smk, true)
ok(smkSends == 1 and Sm.live[smk] == true, "the authority's publish sends and puts the smoker on the live list")
smk.square = nil
Sm.tick()
ok(Sm.live[smk] == nil, "a lifted smoker leaves the live list")
isClient = keepClient
-- a lifted digester drops out of the tick
solo.square = nil
Dg.tick()
ok(next == nil and Dg.live[solo] == nil, "a lifted digester leaves the live list")

------------------------------------------------------------------ the load and tick hooks
dofile(root .. "/server/DazedPlumbing/DUP_DigesterWorld.lua")
local registered = 0
for name in pairs(MapObjects.loads) do if Dg.spriteInfo(name) and MapObjects.news[name] then registered = registered + 1 end end
ok(registered == 4, "all four sprites hook both load and new, " .. registered)
local loaded = digesterAt(55, 55, 20, 0, 5000 - 500)
E.hours = 5000
MapObjects.loads[Dg.sprite("S")](loaded)
local want = select(2, Dg.digest(20, 48, 1, 2))
ok(near(loaded.md.dazedDigester.buf, want, 1e-9), "a digester that loads after 500 h away catches up 48 h: " .. loaded.md.dazedDigester.buf)
ok(Dg.live[loaded] == true, "and joins the live list")
local before2 = loaded.md.dazedDigester.buf
E.hours = 5001
for _, h in ipairs(Events.EveryOneMinute.handlers) do h() end
ok(loaded.md.dazedDigester.buf > before2, "the minute event ticks it")
isClient = function() return true end
local clientObj = digesterAt(56, 55, 20, 0, 4000)
MapObjects.loads[Dg.sprite("S")](clientObj)
isClient = keepClient
ok(clientObj.md.dazedDigester.buf == 0 and Dg.live[clientObj] == nil, "a client's load hook does nothing")

------------------------------------------------------------------ placement
ISMoveableSpriteProps = {}
function ISMoveableSpriteProps:placeMoveableInternal(square, item, name)
    local o = E.object(name, square)
    o.md.modData = { copied = true }
    return o
end
function ISMoveableSpriteProps:canPlaceMoveableInternal() return true end
function ISMoveableSpriteProps:instanceItem() return {} end
function ISMoveableSpriteProps:pickUpMoveableInternal() return nil end
function ISMoveableSpriteProps:pickUpMoveable() return nil end
require "DazedPlumbing/DUP_Place"
local spot = E.square(35, 5)
local props = setmetatable({ spriteName = Dg.sprite("S") }, { __index = ISMoveableSpriteProps })
local placed = props:placeMoveableInternal(spot, { getModData = function() return {} end }, Dg.sprite("S"))
local st = placed.md.dazedDigester
ok(placed.md.modData == nil and st and st.waste == 0 and st.buf == 0, "a placed digester starts empty and drops vanilla's copied item data")
ok(Dg.live[placed] == true, "and joins the live list")
ok(props:canPlaceMoveableInternal(E.character(35, 5), E.square(35, 6), nil) == true, "an empty square takes a digester")
ok(props:canPlaceMoveableInternal(E.character(35, 5), spot, nil) == false, "a second digester on one square is refused")
local propsW = setmetatable({ spriteName = Dg.sprite("W") }, { __index = ISMoveableSpriteProps })
ok(propsW:canPlaceMoveableInternal(E.character(35, 5), spot, nil) == false, "in any facing")

E.realPrint(string.format("digester_test: %d checks, %d failed", n, fails))
if fails > 0 then for _, l in ipairs(E.printed) do E.realPrint("  log: " .. l) end end
os.exit(fails == 0 and 0 or 1)
