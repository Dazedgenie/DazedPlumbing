-- A 2- or 3-square tank picked up comes back as ONE item carrying the master's state.
-- Run: lua54 place_test.lua <common/media/lua>
local root = arg[1] or "../../common/media/lua"
local core = arg[2] or "../../../DazedCore/common/media/lua"      -- Dazed Utilities: Core, required
package.path = core .. "/shared/?.lua;" .. core .. "/client/?.lua;" .. root .. "/shared/?.lua;" .. root .. "/server/?.lua;" .. root .. "/client/?.lua;" .. package.path
local E = dofile("engine_stub.lua")
local fails, n = 0, 0
local function ok(c, msg) n = n + 1 if not c then fails = fails + 1 E.realPrint("FAIL: " .. msg) end end

-- vanilla's multi-sprite pick-up, cut down to what matters: with ForceSingleItem the pieces
-- are lifted without items and one item is built from the anchor sprite afterwards
local built = {}
ISMoveableSpriteProps = {}
function ISMoveableSpriteProps:instanceItem(name)
    local it = { md = {}, name = name, cond = 100 }
    function it:getModData() return self.md end
    function it:setCondition(c) self.cond = c end
    built[#built + 1] = it
    return it
end
function ISMoveableSpriteProps:pickUpMoveableInternal(character, square, object, spr, name, createItem)
    if createItem then return self:instanceItem(name) end
    return nil
end
function ISMoveableSpriteProps:pickUpMoveable(character, square, createItem)
    for _, piece in ipairs(self.pieces) do
        self:pickUpMoveableInternal(character, piece:getSquare(), piece, nil, piece.sprite, not self.force)
    end
    if self.force then self:instanceItem(self.pieces[1].sprite) end
end
package.preload["Moveables/ISMoveableSpriteProps"] = function() return true end

require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Place"
local P = DazedPlumb.Parts

E.grid(20, 20)
local function largeTank(x, y)
    local pieces = {}
    for p = 1, 2 do
        local o = E.object(P.sprite("large", "water", "crafted", "S", p), E.square(x + p - 1, y))
        pieces[p] = o
    end
    pieces[1].md.dazedplumb = { amount = 20, condition = 64 }
    pieces[2].md.dazedplumb = { amount = 0, condition = 100 }
    return pieces
end

local props = setmetatable({ pieces = largeTank(3, 3), force = true }, { __index = ISMoveableSpriteProps })
built = {}
props:pickUpMoveable(nil, nil, true)
ok(#built == 1, "one item for a large tank, got " .. #built)
local carried = built[1] and built[1].md[P.KEY]
ok(carried and carried.amount == 20, "the item carries the master's water")
ok(built[1] and built[1].cond == 64, "and its condition")
ok(DazedPlumb.Place.carry == nil, "nothing left waiting for the next item")

-- an item built later (a placement's other pieces) carries nothing
built = {}
ISMoveableSpriteProps.instanceItem({}, "x")
ok(built[1] and built[1].md[P.KEY] == nil, "a later item is clean")

E.realPrint(string.format("place_test: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
