-- The wall water panel on a fake engine: where it may hang (through the placement hooks), binding to the main that
-- serves its house, unbinding when the main goes, working the main through the panel (via), the board opened by key
-- with the main out of range (waiting), Climate's frozen pipes on the status, and the guide page.
-- Run: lua wallpanel_test.lua <lua root> [<core root>]
local root = arg[1] or "../../common/media/lua"
local core = arg[2] or "../../../DazedCore/common/media/lua"
package.path = core .. "/shared/?.lua;" .. core .. "/client/?.lua;" .. root .. "/shared/?.lua;" .. root .. "/server/?.lua;" .. root .. "/client/?.lua;" .. package.path
local E = dofile("engine_stub.lua")
local print = E.realPrint
local fails, n = 0, 0
local function ok(c, msg) n = n + 1 if not c then fails = fails + 1 print("FAIL: " .. msg) end end

-- one house (10..19 x 10..19, two floors) and a shed at 40,10, as mains_test
local function List(t) return { size = function() return #t end, get = function(_, i) return t[i + 1] end } end
local function Rect(x, y, w, h) return { getX = function() return x end, getY = function() return y end, getW = function() return w end, getH = function() return h end } end
local function Room(z, rects, def) return { getZ = function() return z end, getRects = function() return List(rects) end, isUserDefined = function() return false end, getBuilding = function() return def end, getName = function() return "kitchen" end } end
local function Def(x, y, w, h)
    local d = { rooms = {} }
    d.getX = function() return x end d.getY = function() return y end d.getW = function() return w end d.getH = function() return h end
    d.getRooms = function() return List(d.rooms) end
    d.isUserDefined = function() return false end
    d.isBasement = function() return false end
    d.getMaxLevel = function() return 1 end
    return d
end
local house = Def(10, 10, 10, 10)
house.rooms = { Room(0, { Rect(10, 10, 10, 10) }, house), Room(1, { Rect(10, 10, 10, 10) }, house) }
local shed = Def(40, 10, 4, 4)
shed.rooms = { Room(0, { Rect(40, 10, 4, 4) }, shed) }
local defs = { house, shed }
local function roomAt(x, y, z)
    for _, d in ipairs(defs) do
        for _, r in ipairs(d.rooms) do
            local q = r.getRects().get(nil, 0)
            if r.getZ() == z and x >= q.getX() and x < q.getX() + q.getW() and y >= q.getY() and y < q.getY() + q.getH() then return r end
        end
    end
end
getWorld = function()
    return { getMetaGrid = function() return {
        getRoomAt = function(_, x, y, z) return roomAt(x, y, z) end,
        getBuildingsIntersecting = function(_, x, y, w, h, list)
            for _, d in ipairs(defs) do
                if d.getX() < x + w and d.getX() + d.getW() > x and d.getY() < y + h and d.getY() + d.getH() > y then list:add(d) end
            end
        end,
    } end }
end
ArrayList = { new = function() local t = {} return { add = function(_, v) t[#t + 1] = v end, size = function() return #t end, get = function(_, i) return t[i + 1] end } end }
Fluid = { Water = "W", TaintedWater = "TW" }
FluidType = Fluid
local clock = 0
getTimestampMs = function() clock = clock + 1000 return clock end

-- vanilla's placement, cut down: canPlace says yes, place builds the object on the square
ISMoveableSpriteProps = {}
function ISMoveableSpriteProps:canPlaceMoveableInternal() return true end
function ISMoveableSpriteProps:placeMoveableInternal(square, item, spriteName) return E.object(spriteName, square) end
package.preload["Moveables/ISMoveableSpriteProps"] = function() return true end

require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Sync"
require "DazedPlumbing/DUP_Pipes"
require "DazedPlumbing/DUP_Links"
require "DazedPlumbing/DUP_Fixtures"
require "DazedPlumbing/DUP_LinkActions"
require "DazedPlumbing/DUP_Mains"
require "DazedPlumbing/DUP_MainPanel"
require "DazedPlumbing/DUP_WallPanels"
require "DazedPlumbing/DUP_Place"
local P, L, K, W, Wp, Pn = DazedPlumb.Parts, DazedPlumb.Links, DazedPlumb.Pipes, DazedPlumb.Mains, DazedPlumb.WallPanels, DazedPlumb.MainPanel

E.grid(50, 50)
SandboxVars.WaterShutModifier = 0
SandboxVars.DazedPlumb = { MainReach = 6, MainFlow = 30 }
-- indoor squares, and walls: the house's north wall on row 10, its west wall on column 10, and a wall south of 12,14
for x = 10, 19 do for y = 10, 19 do E.square(x, y, 0).outside = false end end
for x = 40, 43 do for y = 10, 13 do E.square(x, y, 0).outside = false end end
local walls = { ["12,10,0N"] = true, ["10,12,0W"] = true, ["12,15,0N"] = true, ["40,10,0N"] = true }
for _, sq in pairs(E.squares) do
    sq.getWall = function(self, north) return walls[self.x .. "," .. self.y .. "," .. self.z .. (north and "N" or "W")] and {} or nil end
end

ok(Wp.sprite("N") == "dazedplumb_01_259" and Wp.spriteInfo("dazedplumb_01_256").facing == "E" and Wp.spriteInfo("dazedplumb_01_255") == nil, "sprites 256-259")
ok(Wp.ITEM == "Base.DazedWaterPanel" and Wp.allItems()[1] == Wp.ITEM, "the item")

-- 1. where it may hang
local player = E.character(12, 11, 0, 5)
local props = setmetatable({ spriteName = Wp.sprite("N") }, { __index = ISMoveableSpriteProps })
ok(props:canPlaceMoveableInternal(player, E.square(12, 10, 0), nil) == true, "on the house's north wall, facing it")
ok(props:canPlaceMoveableInternal(player, E.square(13, 10, 0), nil) == false and player.notes[#player.notes] == "IGUI_DazedPlumb_PanelWall", "no wall on that side: refused")
ok(props:canPlaceMoveableInternal(player, E.square(30, 30, 0), nil) == false, "outdoors: refused")
E.square(30, 31, 0).outside = false
ok(Wp.canPlace(E.square(30, 31, 0), "N") == false, "a roofed square in no building: refused")
local west = setmetatable({ spriteName = Wp.sprite("W") }, { __index = ISMoveableSpriteProps })
ok(west:canPlaceMoveableInternal(player, E.square(10, 12, 0), nil) == true, "on the west wall, facing west")
local south = setmetatable({ spriteName = Wp.sprite("S") }, { __index = ISMoveableSpriteProps })
ok(south:canPlaceMoveableInternal(player, E.square(12, 14, 0), nil) == true, "a south wall belongs to the square below's north edge")
ok(Wp.canPlace(E.square(40, 10, 0), "N") == true, "a house no main serves takes a panel too")

-- 2. placed in a house no main serves: unbound
local panel = props:placeMoveableInternal(E.square(12, 10, 0), { getModData = function() return {} end }, Wp.sprite("N"))
ok(Wp.isPanel(panel) and Wp.boundTo(panel) == nil and Wp.store().panels["12,10,0"], "placed unbound, and remembered")
ok(props:canPlaceMoveableInternal(player, E.square(12, 10, 0), nil) == false, "one panel to a square")

-- 3. a main connects the house: the panel binds at once
local main = E.object(W.sprite("S"), E.square(22, 15, 0))
local mp = E.character(21, 15, 0, 5)
W.send(mp, "mainPick", { x = 22, y = 15, z = 0, sx = 12, sy = 12, sz = 0 })
ok(W.entry(main) ~= nil and Wp.boundTo(panel) == "22,15,0", "connecting the house binds its panel: " .. tostring(Wp.boundTo(panel)))
-- a panel placed now binds on placement
local panel2 = west:placeMoveableInternal(E.square(10, 12, 0), nil, Wp.sprite("W"))
ok(Wp.boundTo(panel2) == "22,15,0", "a panel placed in a served house binds on placement")
-- the shed's panel stays unbound through the tick
local shedPanel = props:placeMoveableInternal(E.square(40, 10, 0), nil, Wp.sprite("N"))
Wp.tick()
ok(Wp.boundTo(shedPanel) == nil, "the shed's panel stays unbound")

-- 4. the main is disconnected: panels show unbound; reconnected: bound again by the tick even without the hook
W.send(mp, "mainClear", { x = 22, y = 15, z = 0 })
ok(Wp.boundTo(panel) == nil and Wp.boundTo(panel2) == nil, "a disconnected main unbinds its panels")
W.send(mp, "mainPick", { x = 22, y = 15, z = 0, sx = 12, sy = 12, sz = 0 })
panel:getModData().dazedPanelMain = nil
Wp.tick()
ok(Wp.boundTo(panel) == "22,15,0", "an unbound panel binds on the next tick")
-- a stale binding (a main that no longer exists) is cleared by the tick
panel:getModData().dazedPanelMain = "1,1,0"
Wp.tick()
ok(Wp.boundTo(panel) == "22,15,0", "a binding to a missing main is corrected")
-- a lifted panel is forgotten; nothing on the main changes
local before = W.entry(main)
E.square(40, 10, 0):RemoveTileObject(shedPanel)
Wp.tick()
ok(Wp.store().panels["40,10,0"] == nil and W.entry(main) == before, "a lifted panel is forgotten and the main keeps its entry")

-- 5. working the main through the panel: far from the main, beside the panel
local e = W.entry(main)
local inside = E.character(12, 12, 0, 5)
W.send(inside, "mainRate", { x = 22, y = 15, z = 0, rate = 15 })
ok(e.rate == nil and inside.notes[#inside.notes] == "IGUI_DazedPlumb_PanelFar", "without the panel, the house is out of reach of the main")
W.send(inside, "mainRate", { x = 22, y = 15, z = 0, rate = 15, via = { x = 12, y = 10, z = 0 } })
ok(e.rate == 15, "through the bound panel the rate changes")
W.send(inside, "mainRate", { x = 22, y = 15, z = 0, rate = 16, via = { x = 40, y = 10, z = 0 } })
ok(e.rate == 15, "a square with no panel there does not count")
local gotInfo
DazedCore.Net.onClient("DazedPlumb", "mainInfo", function(a) gotInfo = a end)
W.send(inside, "mainInfo", { x = 22, y = 15, z = 0, via = { x = 12, y = 10, z = 0 } })
ok(gotInfo and gotInfo.key == "22,15,0" and not gotInfo.waiting and gotInfo.building.floors == 2, "mainInfo through the panel, live")

-- 6. the main's square unloaded on the authority: the panel still works the entry, mainInfo says waiting
local mainSq = E.squares["22,15,0"]
E.squares["22,15,0"] = nil
gotInfo = nil
W.send(inside, "mainInfo", { x = 22, y = 15, z = 0, via = { x = 12, y = 10, z = 0 } })
ok(gotInfo and gotInfo.waiting == true and gotInfo.flow == 30 and gotInfo.rate == 15 and #gotInfo.fixtures == 0, "out of range: waiting, with the entry's figures")
W.send(inside, "mainShut", { x = 22, y = 15, z = 0, shut = true, via = { x = 12, y = 10, z = 0 } })
ok(e.shut == true, "the shut-off works from the entry alone")
W.send(inside, "mainValve", { x = 22, y = 15, z = 0, fx = 14, fy = 14, fz = 0, closed = true, via = { x = 12, y = 10, z = 0 } })
ok(e.valves == "14,14,0", "a valve inside the footprint can be set while the main is away")
W.send(inside, "mainValve", { x = 22, y = 15, z = 0, fx = 30, fy = 30, fz = 0, closed = true, via = { x = 12, y = 10, z = 0 } })
ok(e.valves == "14,14,0", "but not one outside it")
W.send(inside, "mainMachine", { x = 22, y = 15, z = 0, mx = 1, my = 1, mz = 0, off = true, via = { x = 12, y = 10, z = 0 } })
ok(inside.notes[#inside.notes] == "IGUI_DazedPlumb_PanelOutOfRange", "machines need the main loaded")
local nearMain = E.character(21, 15, 0, 5)
W.send(nearMain, "mainRate", { x = 22, y = 15, z = 0, rate = 9 })
ok(e.rate == 15, "without a panel, an unloaded main is refused")

-- 7. the board opened at the panel by key, with the main out of range
UIFont = { Small = 1, Medium = 2, Large = 3, Code = 4, CodeSmall = 5, CodeMedium = 6, CodeLarge = 7, NewSmall = 8 }
getTextManager = function() return { getFontHeight = function() return 16 end, MeasureStringX = function(_, _, s) return #s * 7 end } end
getTexture = function() return nil end
getPlayerScreenLeft, getPlayerScreenTop = function() return 0 end, function() return 0 end
package.preload["ISUI/ISPanel"] = function()
    ISPanel = { derive = function(self, name) local c = { name = name } c.__index = c setmetatable(c, { __index = self }) return c end,
        new = function(self, x, y, w, h) return setmetatable({ x = x, y = y, width = w, height = h }, self) end,
        initialise = function() end, addToUIManager = function() end, removeFromUIManager = function(self) self.removed = true end,
        update = function() end, onMouseDown = function() end, onMouseUp = function() end,
        drawRect = function() end, drawText = function() end, drawTextRight = function() end, drawTextCentre = function() end,
        drawLine = function() end, drawTextureScaled = function() end, drawTextureAllPoint = function() end,
        isMouseOver = function() return false end, getAbsoluteX = function() return 0 end, getAbsoluteY = function() return 0 end }
    return ISPanel
end
package.preload["DazedCore/DC_Picker"] = function() DazedCore.Picker = DazedCore.Picker or { open = function() DazedCore.Picker.opened = true end } return DazedCore.Picker end
DazedCore.Guide = { books = { { id = "plumbing", pages = { "PlumbStart", "PlumbMain", "PlumbFuel" } } } }
package.preload["DazedCore/DC_Guide"] = function() return DazedCore.Guide end
getSpecificPlayer = function() return inside end
require "DazedPlumbing/DUP_Board"
require "DazedPlumbing/DUP_PanelMenu"
local pages = DazedCore.Guide.books[1].pages
ok(pages[3] == "PlumbPanel" and #pages == 4, "the guide's Plumbing book gains the panel page after the main's")
local win = DUP_Board.open(inside, "22,15,0", { via = { x = 12, y = 10, z = 0 } })
ok(win and win.main == nil and win.mx == 22 and win.key == "22,15,0", "the board opens by key with no main object")
win:refresh() win:prerender()
ok(win.snap.connected and win.snap.outOfRange == true, "it shows the main out of range")
local outText = false
for _, op in ipairs(win.model.ops) do if op.k == "text" and op.str:find("IGUI_DazedPlumb_BoardOutOfRange", 1, true) then outText = true end end
ok(outText, "with the out-of-range line")
local hits = {}
for _, h in ipairs(win.model.hits) do hits[h.id] = true end
ok(hits.connect == nil and hits.shut, "no CONNECT BUILDING at a wall panel; the shut-off still works")
win:onHit("shut") win:onHit("shut")
ok(e.shut == nil, "the wheel opens the main through the panel")
-- the area loads: the board picks the main up
E.squares["22,15,0"] = mainSq
win:requestInfo()
win:refresh()
ok(win.main == main and win.snap.outOfRange == false, "once the main loads, live figures again")
-- the panel lifted: the board closes
E.square(12, 10, 0):RemoveTileObject(panel)
win:update()
ok(win.removed, "lifting the panel closes its board")

-- 8. the menu: bound panels open the board, unbound ones say so
local added = {}
local ctx = { addOption = function(_, t, wo, fn) local o = { text = t, fn = fn } added[#added + 1] = o return o end }
DazedPlumb.Parts.objectsAround = function(wo) return wo end
for _, h in ipairs(Events.OnFillWorldObjectContextMenu.handlers) do h(0, ctx, { panel2 }, false) end
local opened
for _, o in ipairs(added) do if o.text == "ContextMenu_DazedPlumb_WaterPanel" and o.fn then opened = o end end
ok(opened ~= nil, "a bound panel offers Water panel")
added = {}
local loose = props:placeMoveableInternal(E.square(40, 10, 0), nil, Wp.sprite("N"))
for _, h in ipairs(Events.OnFillWorldObjectContextMenu.handlers) do h(0, ctx, { loose }, false) end
local says = false
for _, o in ipairs(added) do if o.text == "IGUI_DazedPlumb_PanelUnbound" then says = true end end
ok(says, "an unbound panel says no main serves the building")

-- 9. Climate: a frozen square on the main's line lights FROZEN and the PAUSED lamp
local tank = E.object(P.sprite("small", "water", "crafted", "S", 1), E.square(25, 15, 0))
tank.md.dazedplumb = { amount = 100, condition = 100 }
E.give(mp, K.ITEM, 20)
DUP_PipeSet:new(mp, main, W.ID, tank):complete()
ok(W.status(main).frozen == false, "not frozen without Climate")
local first = K.index()[L.endFor(main, L.adapters[W.ID])][1]
K.pipes()[first].frozen = true
ok(W.status(main).frozen == false, "a frozen mark does nothing while Climate's ice is off")
DazedClimate = { Plumbing = { enabled = function() return true end } }
local st = W.status(main)
ok(st.frozen == true, "with Climate's ice on, a frozen square on the main's line is FROZEN")
local B = DazedPlumb.BoardLayout
local lamps = B.lamps({ connected = true, status = st })
ok(lamps[5].lit == true, "and the PAUSED lamp is lit")
K.pipes()[first].frozen = nil
DazedClimate = nil

print(string.format("wallpanel_test: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
