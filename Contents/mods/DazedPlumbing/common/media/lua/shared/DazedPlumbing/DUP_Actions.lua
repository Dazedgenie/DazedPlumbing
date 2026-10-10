--[[ Dazed Plumbing -- the timed actions: pour in, take out, patch.

     Each is a vanilla timed action, run on the authority (the server in
     multiplayer) by its complete(), which re-checks EVERYTHING against the
     world as it is then: the tank still there and in reach, the container
     still carried. complete() returns true on every no-op: a false return is
     a Reject, which force-stops the client.

     The container is changed first and the tank second, from what the
     container really did (DUP_Fluids reads it back), so a pour the engine
     refused never creates or destroys fluid.
]]

require "TimedActions/ISBaseTimedAction"
require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Fluids"
require "DazedPlumbing/DUP_TankFluid"

local P = DazedPlumb.Parts
local M = DazedPlumb.Model
local F = DazedPlumb.Fluids

local worldHours = DazedCore.Util.worldHours

--- Is the tank still standing, still a tank, and within two tiles of the actor?
local function stillApplies(action)
    local o = action.object
    if not o or o:getObjectIndex() == -1 then return false end
    if not P.isTank(o) then return false end
    local c = action.character
    for _, sq in ipairs(P.squares(o)) do        -- any square of a long tank will do
        if math.abs(sq:getX() - c:getX()) <= 2 and math.abs(sq:getY() - c:getY()) <= 2
                and sq:getZ() == c:getZ() then
            return true
        end
    end
    return false
end

--- The container an item is in, if it is still in a player's hands/bags.
local function stillCarried(item)
    local cont = item and item.getContainer and item:getContainer()
    if not cont then return nil end
    if item.getWorldItem and item:getWorldItem() then return nil end
    return cont
end

local function tankAction(name, getDuration)
    local A = ISBaseTimedAction:derive(name)
    function A:isValid() return stillApplies(self) end
    function A:waitToStart()
        self.character:faceThisObject(self.object)
        return self.character:shouldBeTurning()
    end
    function A:update() self.character:faceThisObject(self.object) end
    function A:start()
        self:setActionAnim("Loot")
        self.character:SetVariable("LootPosition", "Low")
        self.character:reportEvent("EventLootItem")
        DazedPlumb.Parts.startSound(self)
    end
    function A:stop() DazedPlumb.Parts.stopSound(self) ISBaseTimedAction.stop(self) end
    function A:perform() DazedPlumb.Parts.stopSound(self) ISBaseTimedAction.perform(self) end
    function A:getDuration()
        if self.character:isTimedActionInstant() then return 1 end
        return getDuration(self)
    end
    return A
end

-- Keep the tank's container in step around a pour, so the game's Fluid menu never works from an old figure.
local function fluidSync(obj) pcall(DazedPlumb.TankFluid.reconcile, obj) end

local function pourTime(self) return 40 + math.floor(6 * math.min(60, self.units or 1)) end

----------------------------------------------------- container -> tank
DUP_TankFill = tankAction("DUP_TankFill", pourTime)

function DUP_TankFill:complete()
    if not stillApplies(self) then return true end
    if not stillCarried(self.item) then return true end
    fluidSync(self.object)
    local v = F.vessel(self.item)
    local d = P.data(self.object)
    if not v or v.kind ~= d.type then return true end
    local move = math.min(v.amount, M.room(d))
    if move <= 0.001 then return true end
    local removed = F.drain(self.item, move)
    if removed <= 0 then
        print(string.format("DazedPlumbing: pour in %s: asked %.3f, container gave 0", tostring(d.type), move))
        return true
    end
    local was = d.amount or 0
    if d.type == "water" then M.addWater(d, removed, v.tainted) else M.add(d, removed) end
    local msq = self.object:getSquare()
    print(string.format("DazedPlumbing: pour in %s (%s %s, master at %d,%d): asked %.3f, container gave %.3f, tank %.3f -> %.3f",
        tostring(d.type), tostring(d.size), tostring(d.tier), msq and msq:getX() or -1, msq and msq:getY() or -1,
        move, removed, was, d.amount or 0))
    d.lastHour = worldHours()
    if sendItemStats then sendItemStats(self.item) end
    self.object:transmitModData()
    fluidSync(self.object)
    return true
end

function DUP_TankFill:new(character, object, item, units)
    local o = ISBaseTimedAction.new(self, character)
    o.object, o.item, o.units = object, item, units
    o.maxTime = o:getDuration()
    return o
end

----------------------------------------------------- tank -> container
DUP_TankTake = tankAction("DUP_TankTake", pourTime)

function DUP_TankTake:complete()
    if not stillApplies(self) then return true end
    if not stillCarried(self.item) then return true end
    fluidSync(self.object)
    local v = F.vessel(self.item)
    local d = P.data(self.object)
    if not v or (v.kind ~= d.type and v.kind ~= "empty") then return true end
    local move = math.min(M.available(d), v.capacity - v.amount)   -- nothing comes out of a frozen tank
    if move <= 0.001 then return true end
    local before = d.amount
    local tainted = (d.type == "water") and M.isTainted(d) or nil     -- read BEFORE the water leaves
    local added = F.fill(self.item, d.type, move, tainted)
    print(string.format("DazedPlumbing: take out %s: asked %.3f, container took %.3f (tank %.3f -> %.3f)",
        tostring(d.type), move, added, before or 0, (before or 0) - added))
    if added <= 0 then return true end
    M.take(d, added)
    d.lastHour = worldHours()
    if sendItemStats then sendItemStats(self.item) end
    self.object:transmitModData()
    fluidSync(self.object)
    return true
end

function DUP_TankTake:new(character, object, item, units)
    local o = ISBaseTimedAction.new(self, character)
    o.object, o.item, o.units = object, item, units
    o.maxTime = o:getDuration()
    return o
end

----------------------------------------------------- patching
--  A patch: a small sheet of metal and screws, a screwdriver in hand. Puts
--  REPAIR_STEP points of condition back, up to 100.
DUP_REPAIR_STEP = 30
DUP_TankRepair = tankAction("DUP_TankRepair", function() return 240 end)

function DUP_TankRepair:isValid()
    return stillApplies(self) and (P.data(self.object).condition or 100) < 100
        and self.sheet ~= nil and self.screws ~= nil
end

function DUP_TankRepair:complete()
    if not stillApplies(self) then return true end
    local d = P.data(self.object)
    if (d.condition or 100) >= 100 then return true end
    local conts = {}
    for _, it in ipairs({ self.sheet, self.screws }) do
        local cont = stillCarried(it)
        if not cont then return true end
        conts[#conts + 1] = { cont = cont, item = it }
    end
    for _, c in ipairs(conts) do
        c.cont:Remove(c.item)
        if sendRemoveItemFromContainer then sendRemoveItemFromContainer(c.cont, c.item) end
    end
    d.condition = math.min(100, (d.condition or 0) + DUP_REPAIR_STEP)
    self.object:transmitModData()
    if addXp and Perks and Perks.MetalWelding then addXp(self.character, Perks.MetalWelding, 5) end
    return true
end

function DUP_TankRepair:new(character, object, sheet, screws)
    local o = ISBaseTimedAction.new(self, character)
    o.object, o.sheet, o.screws = object, sheet, screws
    o.maxTime = o:getDuration()
    return o
end

----------------------------------------------------- welding a crack
--  A tank that cracked when it froze full is welded shut: a blowtorch (WELD_TORCH_USES uses), a welding mask
--  and Welding WELD_LEVEL. It stops the crack's leak; wear from low condition is patched as before.
DUP_WELD_LEVEL = 2
DUP_WELD_TORCH_USES = 2
DUP_TankWeld = tankAction("DUP_TankWeld", function() return 300 end)

--- Uses left in a blowtorch, or 0.
function DazedPlumb.torchUses(torch)
    local P_ = DazedPlumb.Parts
    local n = P_.try(torch, "getCurrentUses")
    if type(n) == "number" then return n end
    local delta = P_.try(torch, "getCurrentUsesFloat") or P_.try(torch, "getUsedDelta")
    local per = P_.try(torch, "getUseDelta")
    if type(delta) == "number" and type(per) == "number" and per > 0 then return math.floor(delta / per + 0.0001) end
    return 0
end

--- Has this character the skill and a welding mask for a crack weld? Asked again on the server.
function DazedPlumb.canWeldCrack(character)
    local level = 0
    pcall(function() level = character:getPerkLevel(Perks.MetalWelding) end)
    if level < DUP_WELD_LEVEL then return false end
    local inv = character:getInventory()
    local mask = false
    pcall(function() mask = inv:containsTagEval("base:weldingmask", function(it) return it ~= nil end) == true end)
    if not mask and inv.containsTypeRecurse then mask = inv:containsTypeRecurse("WeldingMask") == true end
    return mask
end

function DUP_TankWeld:isValid()
    return stillApplies(self) and P.data(self.object).cracked == true and self.torch ~= nil
        and DazedPlumb.torchUses(self.torch) >= DUP_WELD_TORCH_USES and DazedPlumb.canWeldCrack(self.character)
end

function DUP_TankWeld:start()
    self:setActionAnim("BlowTorch")
    self.character:reportEvent("EventLootItem")
    DazedPlumb.Parts.startSound(self)
end

function DUP_TankWeld:complete()
    if not stillApplies(self) or not stillCarried(self.torch) then return true end
    local d = P.data(self.object)
    if not d.cracked or not DazedPlumb.canWeldCrack(self.character) then return true end
    for _ = 1, DUP_WELD_TORCH_USES do
        for _, m in ipairs({ "UseAndSync", "Use" }) do
            if type(self.torch[m]) == "function" and pcall(self.torch[m], self.torch) then break end
        end
    end
    d.cracked = nil
    self.object:transmitModData()
    if addXp and Perks and Perks.MetalWelding then addXp(self.character, Perks.MetalWelding, 10) end
    return true
end

function DUP_TankWeld:new(character, object, torch)
    local o = ISBaseTimedAction.new(self, character)
    o.object, o.torch = object, torch
    o.maxTime = o:getDuration()
    return o
end

----------------------------------------------------- naming, and an admin fill
--- Is this character an admin (or is it single player in debug mode)? Asked on whichever side runs the check.
function DazedPlumb.isAdmin(character)
    if isClient and isClient() or isServer and isServer() then
        local ok, level = pcall(function() return character:getAccessLevel() end)
        return ok and type(level) == "string" and level ~= "" and string.lower(level) ~= "none"
    end
    return (getDebug and getDebug()) or (isAdmin and isAdmin()) or false
end

DUP_TankRename = tankAction("DUP_TankRename", function() return 1 end)
function DUP_TankRename:start() end
--- On the authority: store the name (trimmed, at most 32 letters; empty clears it).
function DUP_TankRename:complete()
    if not stillApplies(self) then return true end
    local name = tostring(self.name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    P.data(self.object).name = (name ~= "") and string.sub(name, 1, 32) or nil
    P.master(self.object):transmitModData()
    return true
end
function DUP_TankRename:new(character, object, name)
    local o = ISBaseTimedAction.new(self, character)
    o.object, o.name = object, name
    o.maxTime = o:getDuration()
    return o
end

DUP_TankAdminFill = tankAction("DUP_TankAdminFill", function() return 1 end)
function DUP_TankAdminFill:start() end
--- On the authority, for an admin only: fill the tank (clean water for a water tank).
function DUP_TankAdminFill:complete()
    if not stillApplies(self) or not DazedPlumb.isAdmin(self.character) then return true end
    fluidSync(self.object)
    local d = P.data(self.object)
    d.amount = M.capacity(d.size, d.tier, d.type)
    d.dirty = nil
    self.object:transmitModData()
    fluidSync(self.object)
    return true
end
function DUP_TankAdminFill:new(character, object)
    local o = ISBaseTimedAction.new(self, character)
    o.object = object
    o.maxTime = o:getDuration()
    return o
end

-- The game's own sounds: pouring water, and a wrench for the patch.
local function waterSound(a)
    local d = a.object and DazedPlumb.Parts.data(a.object)
    return d and d.type == "water" and "GetWaterFromTap" or nil
end
DUP_TankFill.SOUND = waterSound
DUP_TankTake.SOUND = waterSound
DUP_TankRepair.SOUND = "RepairWithWrench"
DUP_TankWeld.SOUND = "BlowTorch"
