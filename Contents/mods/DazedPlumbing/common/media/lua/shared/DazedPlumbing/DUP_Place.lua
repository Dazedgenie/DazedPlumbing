--[[ Dazed Utilities: Plumbing -- picking tanks up, putting them down, and
     where they may go.

     A tank is a vanilla MOVEABLE (the item's WorldObjectSprite and the
     sprite's tile properties, see tools/pack_tiles.py), so vanilla places
     and lifts it. What vanilla does NOT do is carry the tank's contents:
     the same job Dazed Power's DP_Place does for its parts, done here the same
     way, by wrapping ISMoveableSpriteProps:

       placeMoveableInternal      after vanilla builds the object: copy the
                                  carried state from the item onto it
       pickUpMoveableInternal     after vanilla builds the item: copy the
                                  object's flat state onto it (a 2- or 3-square
                                  tank is ONE item: ForceSingleItem, see G.carry)
       canPlaceMoveableInternal   only ever ADDS refusals: one tank to a
                                  square, and the extra-large only outdoors

     Only the flat (non-table) fields travel, which is all a tank has.
]]

require "Moveables/ISMoveableSpriteProps"
require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Pumps"
require "DazedPlumbing/DUP_Purifiers"
require "DazedPlumbing/DUP_Downspouts"
require "DazedPlumbing/DUP_Sprinklers"
require "DazedPlumbing/DUP_TankFluid"
require "DazedPlumbing/DUP_Mains"
require "DazedPlumbing/DUP_FuelPumps"
require "DazedPlumbing/DUP_Digesters"
require "DazedPlumbing/DUP_DrilledWells"
require "DazedPlumbing/DUP_Smokers"
require "DazedCore/DC_Boot"
DazedCore.Heavy.register("Base.DazedTank")

local P = DazedPlumb.Parts
local M = DazedPlumb.Model
DazedPlumb.Place = DazedPlumb.Place or {}
local G = DazedPlumb.Place

if not ISMoveableSpriteProps then return end

local try = P.try

--- Tell a player why a placement was refused: the core's rate-limited note (the cursor asks every frame).
function G.note(character, key) DazedCore.Note.limited(character, key) end

local function worldHours()
    local gt = getGameTime and getGameTime()
    return gt and gt:getWorldAgeHours() or 0
end

--- Copy an item's carried state onto a freshly placed tank.
function G.seed(obj, item)
    if not obj then return end
    P.scrubCarried(obj)
    local d = P.data(obj)
    local md = item and item.getModData and item:getModData()
    local src = md and md[P.KEY]
    d.condition = (item and item.getCondition and item:getCondition()) or 100
    if type(src) == "table" then
        d.amount = tonumber(src.amount) or 0
    else
        d.amount = 0                                   -- a crafted or found tank is empty
    end
    d.lastHour = worldHours()
    M.normalize(d)
    if DazedPlumb.World and DazedPlumb.World.register then DazedPlumb.World.register(obj) end
end

--- Up to 42.20 placeMoveableInternal is handed (square, item, spriteName);
--  from 42.21 the placer comes first. A square only in the new form; an
--  item in the old. Returns character (nil before 42.21), square, item, name.
local function placeArgs(a1, a2, a3, a4)
    if instanceof(a2, "IsoGridSquare") then return a1, a2, a3, a4 end
    return nil, a1, a2, a3
end

local origPlace = ISMoveableSpriteProps.placeMoveableInternal
function ISMoveableSpriteProps:placeMoveableInternal(...)
    local _, square, item, spriteName = placeArgs(...)
    local info = P.spriteInfo(spriteName)
    local obj = origPlace(self, ...)           -- the original gets exactly what it was handed
    -- A purifier carries only its filter's remaining life (the buffer is lost in the lift).
    if obj and square and DazedPlumb.Purifiers and DazedPlumb.Purifiers.spriteInfo(spriteName) then
        local md = item and item.getModData and item:getModData()
        local obj_md = obj:getModData()
        obj_md.dazedPurifier = { buf = 0, filter = tonumber(md and md.dazedPurifierFilter) }
        if obj_md.modData then obj_md.modData = nil end     -- vanilla's nested copy of the item's data
    end
    -- A downspout starts empty (vanilla copies the item's data onto it) and joins the rain tick.
    if obj and square and DazedPlumb.Downspouts.spriteInfo(spriteName) then
        obj:getModData()[DazedPlumb.Downspouts.KEY] = { water = 0 }
        if obj:getModData().modData then obj:getModData().modData = nil end
        if DazedPlumb.World and DazedPlumb.World.registerSpout then DazedPlumb.World.registerSpout(obj) end
    end
    -- A water main starts unconnected (vanilla copies the item's data onto it; none of it is wanted).
    if obj and square and DazedPlumb.Mains.spriteInfo(spriteName) then
        local md = obj:getModData()
        if md.modData then md.modData = nil end
    end
    -- A fuel pump starts switched on and idle (vanilla copies the item's data onto it; none of it is wanted).
    if obj and square and DazedPlumb.FuelPumps.spriteInfo(spriteName) then
        local md = obj:getModData()
        if md.modData then md.modData = nil end
    end
    -- A digester starts empty and joins the live tick (vanilla copies the item's data onto it; none of it is wanted).
    if obj and square and DazedPlumb.Digesters.spriteInfo(spriteName) then
        local md = obj:getModData()
        if md.modData then md.modData = nil end
        md[DazedPlumb.Digesters.KEY] = nil
        DazedPlumb.Digesters.state(obj)
        DazedPlumb.Digesters.register(obj)
    end
    -- A drilled well starts switched on and unpiped (vanilla copies the item's data onto it; none of it is wanted).
    if obj and square and DazedPlumb.DrilledWells.spriteInfo(spriteName) then
        local md = obj:getModData()
        if md.modData then md.modData = nil end
    end
    -- A smoker starts unlit and joins the live tick (vanilla copies the item's data onto it and builds its container from the tile).
    if obj and square and DazedPlumb.Smokers.spriteInfo(spriteName) then
        local md = obj:getModData()
        if md.modData then md.modData = nil end
        md[DazedPlumb.Smokers.KEY] = nil
        DazedPlumb.Smokers.state(obj)
        DazedPlumb.Smokers.register(obj)
    end
    -- A sprinkler starts switched on and idle (vanilla copies the item's data onto it).
    local spr = DazedPlumb.Sprinklers
    if obj and square and spr.spriteInfo(spriteName) then
        local md = obj:getModData()
        md[spr.KEY] = {}
        if md.modData then md.modData = nil end
        spr.setSpraying(obj, false)
    end
    if info and obj and square then
        -- Only the master piece carries state; the others just lose vanilla's copy.
        if info.master then G.seed(obj, item) else P.scrubCarried(obj) end
    end
    return obj
end

local origCanPlace = ISMoveableSpriteProps.canPlaceMoveableInternal
if origCanPlace then
    function ISMoveableSpriteProps:canPlaceMoveableInternal(character, square, item, forceTypeObject, ...)
        local allowed = origCanPlace(self, character, square, item, forceTypeObject, ...)
        if not allowed then return allowed end
        -- A water pump: bare natural ground in the open, one to a square.
        local pump = self.spriteName and DazedPlumb.Pumps and DazedPlumb.Pumps.spriteInfo(self.spriteName)
        if pump and square then
            if not DazedPlumb.Pumps.groundOk(square) then
                G.note(character, "IGUI_DazedPlumb_PumpGround")
                return false
            end
            local objs = square.getObjects and square:getObjects()
            if objs then
                for i = 0, objs:size() - 1 do
                    if DazedPlumb.Pumps.isPump(objs:get(i)) then return false end
                end
            end
            return allowed
        end
        -- A drilled well: bare natural ground in the open (the water pump's rule), one to a square.
        if self.spriteName and DazedPlumb.DrilledWells.spriteInfo(self.spriteName) and square then
            if not DazedPlumb.Pumps.groundOk(square) then
                G.note(character, "IGUI_DazedPlumb_WellGround")
                return false
            end
            local objs = square.getObjects and square:getObjects()
            if objs then
                for i = 0, objs:size() - 1 do
                    if DazedPlumb.DrilledWells.isWell(objs:get(i)) then return false end
                end
            end
            return allowed
        end
        -- A water main: outdoors, one to a square.
        if self.spriteName and DazedPlumb.Mains.spriteInfo(self.spriteName) and square then
            if square.isOutside and not square:isOutside() then
                G.note(character, "IGUI_DazedPlumb_MainOutdoors")
                return false
            end
            local objs = square.getObjects and square:getObjects()
            if objs then
                for i = 0, objs:size() - 1 do
                    if DazedPlumb.Mains.isMain(objs:get(i)) then return false end
                end
            end
            return allowed
        end
        -- A fuel pump: one to a square.
        if self.spriteName and DazedPlumb.FuelPumps.spriteInfo(self.spriteName) and square then
            local objs = square.getObjects and square:getObjects()
            if objs then
                for i = 0, objs:size() - 1 do
                    if DazedPlumb.FuelPumps.isFuelPump(objs:get(i)) then return false end
                end
            end
            return allowed
        end
        -- A digester: one to a square.
        if self.spriteName and DazedPlumb.Digesters.spriteInfo(self.spriteName) and square then
            local objs = square.getObjects and square:getObjects()
            if objs then
                for i = 0, objs:size() - 1 do
                    if DazedPlumb.Digesters.isDigester(objs:get(i)) then return false end
                end
            end
            return allowed
        end
        -- A smoker: one to a square.
        if self.spriteName and DazedPlumb.Smokers.spriteInfo(self.spriteName) and square then
            local objs = square.getObjects and square:getObjects()
            if objs then
                for i = 0, objs:size() - 1 do
                    if DazedPlumb.Smokers.isSmoker(objs:get(i)) then return false end
                end
            end
            return allowed
        end
        -- A sprinkler: one to a square.
        if self.spriteName and DazedPlumb.Sprinklers.spriteInfo(self.spriteName) and square then
            local objs = square.getObjects and square:getObjects()
            if objs then
                for i = 0, objs:size() - 1 do
                    if DazedPlumb.Sprinklers.isSprinkler(objs:get(i)) then return false end
                end
            end
            return allowed
        end
        -- A downspout: an outdoor square with a building wall on the side it faces.
        local spout = self.spriteName and DazedPlumb.Downspouts.spriteInfo(self.spriteName)
        if spout and square then
            if not DazedPlumb.Downspouts.buildingFor(square, spout.facing) then
                G.note(character, "IGUI_DazedPlumb_DownspoutWall")
                return false
            end
            local objs = square.getObjects and square:getObjects()
            if objs then
                for i = 0, objs:size() - 1 do
                    if DazedPlumb.Downspouts.isDownspout(objs:get(i)) then return false end
                end
            end
            return allowed
        end
        local info = self.spriteName and P.spriteInfo(self.spriteName)
        if not info or not square then return allowed end
        -- The extra-large tank stands in the open: nothing over it.
        if info.size == "xl" and square.isOutside and not square:isOutside() then
            G.note(character, "IGUI_DazedPlumb_XLOutdoors")
            return false
        end
        -- One tank to a square: the menu and the world tick each look up
        -- "the" tank on a square.
        local objs = square.getObjects and square:getObjects()
        if objs then
            for i = 0, objs:size() - 1 do
                if P.isTank(objs:get(i)) then return false end
            end
        end
        return allowed
    end
end

-- A large or XL tank comes back as ONE item (tile property ForceSingleItem). Vanilla builds
-- that item with instanceItem after lifting every piece, so the master's state waits in G.carry.
G.carry = nil

local function applyCarry(item, carry)
    if not (item and item.getModData and carry) then return end
    item:getModData()[P.KEY] = carry.copy
    if item.setCondition and carry.cond then item:setCondition(math.floor(carry.cond)) end
end

local origInstance = ISMoveableSpriteProps.instanceItem
if origInstance then
    function ISMoveableSpriteProps:instanceItem(...)
        local item = origInstance(self, ...)
        if item and G.carry then
            applyCarry(item, G.carry)
            G.carry = nil
        end
        return item
    end
end

--- Is this tank heavy enough to come apart into parts, and not yet empty?
function G.mustEmpty(object)
    local info = P.describe(object)
    local item = info and P.itemFor(info.size, info.type, info.tier)
    local script = item and getScriptManager and getScriptManager():getItem(item)
    local w = script and script:getActualWeight() or 0
    return DazedCore.Heavy.count(w) > 1 and (P.data(object).amount or 0) > 0.05
end

-- A tank's FluidContainer only mirrors its contents, which travel with the item, so it never stops a lift or a turn.
local origCanPick = ISMoveableSpriteProps.canPickUpMoveableInternal
if origCanPick then
    function ISMoveableSpriteProps:canPickUpMoveableInternal(character, square, object, ...)
        -- a tank that comes apart into parts must be emptied first
        if object and P.describe(object) and G.mustEmpty(object) then return false end
        if object and P.describe(object) then object = nil end
        return origCanPick(self, character, square, object, ...)
    end
end
local origCanRotate = ISMoveableSpriteProps.canRotateMoveableInternal
if origCanRotate then
    function ISMoveableSpriteProps:canRotateMoveableInternal(square, object, ...)
        if object and P.describe(object) then object = nil end
        return origCanRotate(self, square, object, ...)
    end
end

local origPickOuter = ISMoveableSpriteProps.pickUpMoveable
if origPickOuter then
    function ISMoveableSpriteProps:pickUpMoveable(...)
        G.carry = nil
        -- take in what the game's Fluid menu did to the tank before vanilla empties its container for the move
        local square = select(2, ...)
        local found = square and self.findOnSquare and self:findOnSquare(square, self.spriteName)
        if found and P.describe(found) and DazedPlumb.TankFluid then pcall(DazedPlumb.TankFluid.reconcile, found) end
        local ok, a, b = pcall(origPickOuter, self, ...)
        G.carry = nil                                   -- never let it reach the next item built
        if not ok then error(a, 0) end
        return a, b
    end
end

local origPick = ISMoveableSpriteProps.pickUpMoveableInternal
function ISMoveableSpriteProps:pickUpMoveableInternal(character, square, object, ...)
    local info = object and P.describe(object)
    -- Read the state off the MASTER before vanilla takes the pieces apart.
    local carry
    if info and info.master ~= false then
        local d = P.data(object)
        local copy = {}
        for k, v in pairs(d) do
            if type(v) ~= "table" and type(v) ~= "userdata" then copy[k] = v end
        end
        carry = { copy = copy, cond = d.condition }
        G.carry = carry
    end
    local filterLeft
    if object and DazedPlumb.Purifiers and DazedPlumb.Purifiers.isPurifier(object) then
        filterLeft = DazedPlumb.Purifiers.state(object).filter
    end
    local item = origPick(self, character, square, object, ...)
    if filterLeft and item and item.getModData then item:getModData().dazedPurifierFilter = filterLeft end
    if carry and item then
        applyCarry(item, carry)
        G.carry = nil
    end
    return item
end
