-- A tiny stand-in for the game engine: a grid of squares holding objects, ModData, events and
-- just enough of the item and timed-action API for Plumbing's own Lua to run. Not the real engine.
local E = {}
next = nil           -- the game's Lua (Kahlua) has no next(); make a use fail here too
select = select

local function list(t)
    return { size = function() return #t end, get = function(_, i) return t[i + 1] end, add = function(_, v) t[#t + 1] = v end }
end

E.squares = {}
E.printed = {}
local realPrint = print
print = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end E.printed[#E.printed + 1] = table.concat(t, " ") end
E.realPrint = realPrint

local Square = {}
Square.__index = Square
function Square:getX() return self.x end
function Square:getY() return self.y end
function Square:getZ() return self.z end
function Square:getObjects() return list(self.objs) end
function Square:isSolid() return false end
function Square:isSolidTrans() return false end
function Square:isBlockedTo(o) return self.walls and self.walls[o.x .. "," .. o.y] or false end
function Square:isOutside() return self.outside ~= false end
function Square:AddTileObject(o) self.objs[#self.objs + 1] = o; o.square = self end
function Square:RemoveTileObject(o) for i, v in ipairs(self.objs) do if v == o then table.remove(self.objs, i) o.square = nil return end end end
function Square:transmitRemoveItemFromSquare(o) end
function Square:getMovingObjects() return list(self.movers or {}) end
function Square:getVehicleContainer() return nil end
function Square:haveElectricity() return self.power == true end

function E.square(x, y, z)
    z = z or 0
    local k = x .. "," .. y .. "," .. z
    if not E.squares[k] then E.squares[k] = setmetatable({ x = x, y = y, z = z, objs = {} }, Square) end
    return E.squares[k]
end
function E.grid(w, h)
    for x = 0, w do for y = 0, h do E.square(x, y, 0) end end
end

local Obj = {}
Obj.__index = Obj
function Obj:getSprite() local n = self.sprite return { getName = function() return n end } end
function Obj:getSpriteName() return self.sprite end
function Obj:setSprite(n) self.sprite = n end
function Obj:setCustomColor(r, g, b, a) self.color = { r, g, b } end
function Obj:getModData() return self.md end
function Obj:getSquare() return self.square end
function Obj:getObjectIndex() return self.square and 0 or -1 end
function Obj:transmitModData() end
function Obj:transmitCompleteItemToClients() end
function Obj:transmitUpdatedSpriteToClients() end
function Obj:getProperties() return { Is = function() return false end, Val = function() return nil end } end

function E.object(sprite, sq, extra)
    local o = setmetatable({ sprite = sprite, md = {} }, Obj)
    for k, v in pairs(extra or {}) do o[k] = v end
    if sq then sq:AddTileObject(o) end
    return o
end

IsoObject = { new = function(_, sq, name) return setmetatable({ sprite = name, md = {} }, Obj) end }
getCell = function() return { getGridSquare = function(_, x, y, z) return E.squares[x .. "," .. y .. "," .. z] end } end

ModData = { _t = {}, getOrCreate = function(k) ModData._t[k] = ModData._t[k] or {} return ModData._t[k] end,
            transmit = function() end, request = function() end, add = function(k, t) ModData._t[k] = t end }
Events = setmetatable({}, { __index = function(t, k) local ev = { handlers = {} } ev.Add = function(f) ev.handlers[#ev.handlers + 1] = f end t[k] = ev return ev end })
getGameTime = function() return { getWorldAgeHours = function() return E.hours or 100 end } end
getSandboxOptions = nil
SandboxVars = { WaterShutModifier = 0 }
instanceof = function() return false end
Perks = { MetalWelding = "MetalWelding" }
getText = function(k, ...) return k end
ColorInfo = nil

-- items and characters
function E.item(fullType, container)
    return { fullType = fullType, container = container, getFullType = function(s) return s.fullType end,
             getContainer = function(s) return s.container end }
end
function E.character(x, y, z, welding)
    local items = {}
    local inv = {
        items = items,
        getItems = function() return list(items) end,
        AddItem = function(self, it) it.container = self items[#items + 1] = it end,
        Remove = function(self, it) for i, v in ipairs(items) do if v == it then table.remove(items, i) return end end end,
        getFirstTypeEvalRecurse = function(self, typ, pred)
            for _, v in ipairs(items) do
                if v.fullType and v.fullType:match("%.(.+)$") == typ and (not pred or pred(v)) then return v end
            end
            return nil
        end,
    }
    local ch = { inv = inv, x = x, y = y, z = z or 0, welding = welding or 0, notes = {} }
    function ch:getInventory() return inv end
    function ch:getX() return self.x end
    function ch:getY() return self.y end
    function ch:getZ() return self.z end
    function ch:getPerkLevel() return self.welding end
    function ch:faceThisObject() end
    function ch:setHaloNote(t) self.notes[#self.notes + 1] = t end
    function ch:isTimedActionInstant() return true end
    inv:AddItem(E.item("Base.PipeWrench"))                -- everyone carries a pipe wrench unless a test takes it
    return ch
end
function E.give(ch, fullType, n)
    for _ = 1, n do ch.inv:AddItem(E.item(fullType)) end
end
function E.count(ch, fullType)
    local c = 0
    for _, it in ipairs(ch.inv.items) do if it.fullType == fullType then c = c + 1 end end
    return c
end
instanceItem = function(ft) return E.item(ft) end

package.preload["Moveables/ISMoveableSpriteProps"] = package.preload["Moveables/ISMoveableSpriteProps"] or function() return true end
package.preload["TimedActions/ISBaseTimedAction"] = function()
    ISBaseTimedAction = { derive = function(self, name) local c = { name = name } c.__index = c setmetatable(c, { __index = self }) return c end,
        new = function(self, ch) return setmetatable({ character = ch }, self) end }
    return ISBaseTimedAction
end

return E
