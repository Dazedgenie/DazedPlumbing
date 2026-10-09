--[[ Dazed Utilities: Plumbing -- the downspout.

     A downspout is bolted to the outside of a building's wall. While it rains it takes its
     share of that building's whole roof (see DUP_Model: RUNOFF and DOWNSPOUT) into a small
     buffer, and it is a link SOURCE: pipe it to a water tank, or stand it right beside one.
     Rainwater is clean.

     Its sprite faces the WALL it is fixed to: facing E means the wall is on its east side.
     It may only go on an outdoor square with a building square against that side.
     SPRITES: dazedplumb_01_192..195 = facings E, S, W, N.
     State: the object's ModData table `dazedDownspout` = { water = litres waiting }.
]]

require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Links"

DazedPlumb.Downspouts = DazedPlumb.Downspouts or {}
local D = DazedPlumb.Downspouts
local P, L, M = DazedPlumb.Parts, DazedPlumb.Links, DazedPlumb.Model
local try = P.try

D.BASE = 192
D.COUNT = 4
D.FACINGS = { "E", "S", "W", "N" }
D.STEP = { E = { 1, 0 }, S = { 0, 1 }, W = { -1, 0 }, N = { 0, -1 } }
D.ITEM = "Base.DazedDownspout"
D.ID = "dazed_downspout"
D.KEY = "dazedDownspout"

function D.sprite(facing)
    for i, f in ipairs(D.FACINGS) do
        if f == facing then return P.TILESET .. "_" .. (D.BASE + i - 1) end
    end
end

function D.spriteInfo(name)
    local idx = P.indexOf(name)
    if not idx or idx < D.BASE or idx >= D.BASE + D.COUNT then return nil end
    return { facing = D.FACINGS[idx - D.BASE + 1] }
end

function D.describe(obj)
    local spr = obj and try(obj, "getSprite")
    return spr and D.spriteInfo(try(spr, "getName")) or nil
end
function D.isDownspout(obj) return D.describe(obj) ~= nil end

--- The square on the wall side of a square for a facing, or nil.
function D.wallSquare(square, facing)
    local step = D.STEP[facing]
    local cell = getCell and getCell()
    if not (square and step and cell) then return nil end
    return cell:getGridSquare(square:getX() + step[1], square:getY() + step[2], square:getZ())
end

--- The building a downspout drains, or nil: the one on the wall side of an outdoor square.
function D.buildingFor(square, facing)
    if not square or try(square, "isOutside") ~= true then return nil end
    local wall = D.wallSquare(square, facing)
    return wall and try(wall, "getBuilding") or nil
end

function D.building(obj)
    local info = D.describe(obj)
    local sq = obj and try(obj, "getSquare")
    return info and sq and D.buildingFor(sq, info.facing) or nil
end

----------------------------------------------------------- the buffer
function D.state(obj)
    local md = obj and obj.getModData and obj:getModData()
    if not md then return { water = 0 } end
    md[D.KEY] = md[D.KEY] or { water = 0 }
    return md[D.KEY]
end

function D.water(obj) return math.max(0, D.state(obj).water or 0) end

--- Add rainwater (authority); returns what the buffer took.
function D.fill(obj, litres)
    local st = D.state(obj)
    local took = math.min(math.max(0, litres or 0), M.DOWNSPOUT_BUFFER - (st.water or 0))
    if took > 0 then
        st.water = (st.water or 0) + took
        P.transmit(obj)
    end
    return math.max(0, took)
end

function D.take(obj, amount)
    local st = D.state(obj)
    local give = math.min(math.max(0, amount or 0), st.water or 0)
    if give > 0 then
        st.water = st.water - give
        P.transmit(obj)
    end
    return give
end

L.register({
    id = D.ID, produces = "water", tainted = false, label = "ContextMenu_DazedPlumb_DownspoutLine",
    match = D.isDownspout,
    available = function(o) return math.min(L.RATE.water, D.water(o)) end,
    take = D.take,
})

return D
