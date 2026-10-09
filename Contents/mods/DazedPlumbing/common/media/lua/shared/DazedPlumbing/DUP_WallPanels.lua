--[[ Dazed Utilities: Plumbing -- the wall water panel: a cabinet hung on a wall inside a house that opens the main's board.
     The authority binds it to the main whose footprint holds its square, as ModData `dazedPanelMain` = "x,y,z" of that main.

     Placement: an indoor square of a building, with a wall on the side the sprite faces (like the downspout, it faces
     the wall it is fixed to), one panel to a square. A panel in a house no main serves stays unbound until one does.
     DazedPlumbPanels (world ModData, authority only, never synced) = { panels = { ["x,y,z"] = true } }.
     SPRITES: dazedplumb_01_256..259 = facings E, S, W, N. ]]

require "DazedCore/DC_Boot"
require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Sync"
require "DazedPlumbing/DUP_Mains"

DazedPlumb.WallPanels = DazedPlumb.WallPanels or {}
local Wp = DazedPlumb.WallPanels
local P, S, W = DazedPlumb.Parts, DazedPlumb.Sync, DazedPlumb.Mains
local B, R, U = DazedCore.Buildings, DazedCore.Reach, DazedCore.Util
local try = P.try

Wp.BASE = 256
Wp.COUNT = 4
Wp.FACINGS = { "E", "S", "W", "N" }
Wp.ITEM = "Base.DazedWaterPanel"
Wp.TAG = "DazedPlumbPanels"
Wp.MD = "dazedPanelMain"
Wp.STEP = { E = { 1, 0 }, S = { 0, 1 }, W = { -1, 0 }, N = { 0, -1 } }

----------------------------------------------------------- sprites
function Wp.sprite(facing)
    for i, f in ipairs(Wp.FACINGS) do
        if f == facing then return P.TILESET .. "_" .. (Wp.BASE + i - 1) end
    end
end

function Wp.spriteInfo(name)
    local idx = P.indexOf(name)
    if not idx or idx < Wp.BASE or idx >= Wp.BASE + Wp.COUNT then return nil end
    return { facing = Wp.FACINGS[idx - Wp.BASE + 1] }
end

function Wp.describe(obj)
    local spr = obj and try(obj, "getSprite")
    return spr and Wp.spriteInfo(try(spr, "getName")) or nil
end
function Wp.isPanel(obj) return Wp.describe(obj) ~= nil end

function Wp.allItems() return { Wp.ITEM } end

--- The main a panel is bound to ("x,y,z"), or nil.
function Wp.boundTo(obj)
    local md = obj and try(obj, "getModData")
    local k = md and md[Wp.MD]
    return type(k) == "string" and k or nil
end

----------------------------------------------------------- where it may hang
--- Is there a wall on the `facing` side of the square? North and west walls belong to the square itself,
--  south and east ones to the neighbour's north and west edges.
function Wp.wallOn(square, facing)
    if not square then return false end
    local function wall(sq, north)
        if not sq then return false end
        if try(sq, "getWall", north) ~= nil then return true end
        local p = try(sq, "getProperties")
        local flag = IsoFlagType and (north and IsoFlagType.collideN or IsoFlagType.collideW)
        return flag ~= nil and p ~= nil and (try(p, "has", flag) == true or try(p, "Is", flag) == true)
    end
    if facing == "N" then return wall(square, true) end
    if facing == "W" then return wall(square, false) end
    local step = Wp.STEP[facing]
    if not step then return false end
    local nb = U.squareAt(square:getX() + step[1], square:getY() + step[2], square:getZ())
    return wall(nb, facing == "S")
end

--- The main whose connected footprint holds x, y, z, as its key, or nil.
function Wp.mainFor(x, y, z)
    for key, e in pairs(W.store().mains) do
        local fp = W.footprint(e)
        if fp and R.fpHas(fp, x, y, z) then return key end
    end
    return nil
end

--- May a panel facing `facing` hang on this square? true, or false and a note key.
function Wp.canPlace(square, facing)
    if not square then return false end
    if try(square, "isOutside") == true then return false, "IGUI_DazedPlumb_PanelIndoors" end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    if not Wp.mainFor(x, y, z) and not B.targetAt(x, y, z) then return false, "IGUI_DazedPlumb_PanelIndoors" end
    if not Wp.wallOn(square, facing) then return false, "IGUI_DazedPlumb_PanelWall" end
    local objs = square:getObjects()
    for i = 0, objs:size() - 1 do
        if Wp.isPanel(objs:get(i)) then return false end
    end
    return true
end

----------------------------------------------------------- binding (authority)
local function store()
    if not ModData then return { panels = {} } end
    local t = ModData.getOrCreate(Wp.TAG)
    t.panels = t.panels or {}
    return t
end
Wp.store = store

local function keyOf(obj)
    local sq = try(obj, "getSquare")
    return sq and DazedPlumb.Net.key(sq:getX(), sq:getY(), sq:getZ()) or nil, sq
end

--- Point a panel at the main that serves its square (or at none); sends its ModData when that changed.
function Wp.bind(obj)
    if not S.authority() then return nil end
    local _, sq = keyOf(obj)
    if not sq then return nil end
    local want = Wp.mainFor(sq:getX(), sq:getY(), sq:getZ())
    local md = obj:getModData()
    if md[Wp.MD] ~= want then
        md[Wp.MD] = want
        if obj.transmitModData then obj:transmitModData() end
    end
    return want
end

--- Remember a panel and bind it (on placement, and when its square loads).
function Wp.register(obj)
    if not S.authority() then return end
    local key = keyOf(obj)
    if not key then return end
    store().panels[key] = true
    Wp.bind(obj)
end

--- The panel at a key: obj, or nil and "gone" / "unloaded".
function Wp.panelAt(key)
    local x, y, z = DazedPlumb.Net.split(key)
    local sq = x and U.squareAt(x, y, z)
    if not sq then return nil, "unloaded" end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if Wp.isPanel(o) then return o end
    end
    return nil, "gone"
end

--- Once a minute: a bound panel is checked against the mains table (a lookup), an unbound one looks for a main.
function Wp.tick()
    if not S.authority() then return end
    local drop = {}
    for key in pairs(store().panels) do
        local obj, why = Wp.panelAt(key)
        if obj then
            local bound = Wp.boundTo(obj)
            local e = bound and W.store().mains[bound]
            local x, y, z = DazedPlumb.Net.split(key)
            local fp = e and W.footprint(e)
            if not (fp and R.fpHas(fp, x, y, z)) then Wp.bind(obj) end
        elseif why == "gone" then
            drop[#drop + 1] = key
        end
    end
    for _, k in ipairs(drop) do store().panels[k] = nil end
end

--- Bind every loaded panel again at once (a main was connected or disconnected).
function Wp.bindAll()
    if not S.authority() then return end
    for key in pairs(store().panels) do
        local obj = Wp.panelAt(key)
        if obj then Wp.bind(obj) end
    end
end

-- A panel that loads from the save is remembered and bound again on the authority.
local function onLoad(obj)
    if S.authority() then pcall(Wp.register, obj) end
end
if MapObjects and MapObjects.OnLoadWithSprite then
    for n = 0, Wp.COUNT - 1 do MapObjects.OnLoadWithSprite(P.TILESET .. "_" .. (Wp.BASE + n), onLoad, 6) end
end

return Wp
