--[[ Dazed Plumbing -- timed actions for pipes: lay a run, take a
     machine off its line, pause it, cut, mend, fit a valve, turn a valve.
     The AUTHORITY runs complete() and re-checks the world; the menu only
     previews. Pipe sections and valves are items, taken from the pack here. ]]

require "TimedActions/ISBaseTimedAction"
require "DazedPlumbing/DUP_Links"

local P, L, K, N, S = DazedPlumb.Parts, DazedPlumb.Links, DazedPlumb.Pipes, DazedPlumb.Net, DazedPlumb.Sync

local function near(obj, character)
    local sq = obj and obj:getSquare()
    return sq ~= nil and math.abs(sq:getX() - character:getX()) <= 2
       and math.abs(sq:getY() - character:getY()) <= 2 and sq:getZ() == character:getZ()
end

----------------------------------------------------------- items and skill
--- Every carried item of a full type, in bags too.
local function itemsOf(inv, fullType, out)
    out = out or {}
    local items = inv and inv.getItems and inv:getItems()
    if not items then return out end
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it then
            if it:getFullType() == fullType then out[#out + 1] = it end
            if it.IsInventoryContainer and it:IsInventoryContainer() and it.getInventory then
                itemsOf(it:getInventory(), fullType, out)
            end
        end
    end
    return out
end
L.itemsOf = itemsOf

--- Take `n` of a type from the pack; true only if all n were there.
local function consume(character, fullType, n)
    if n <= 0 then return true end
    local found = itemsOf(character:getInventory(), fullType)
    if #found < n then return false end
    for i = 1, n do
        local it = found[i]
        local cont = it:getContainer()
        if cont then
            cont:Remove(it)
            if sendRemoveItemFromContainer then sendRemoveItemFromContainer(cont, it) end
        end
    end
    return true
end

local function give(character, fullType, n)
    local inv = character:getInventory()
    for _ = 1, n do
        local it = instanceItem and instanceItem(fullType)
        if it then
            inv:AddItem(it)
            if sendAddItemToContainer then sendAddItemToContainer(inv, it) end
        end
    end
end

local function weldLevel(character)
    local ok, lvl = pcall(function() return character:getPerkLevel(Perks.MetalWelding) end)
    return (ok and type(lvl) == "number") and lvl or 0
end
L.weldLevel = weldLevel

--- Is a pipe wrench needed for pipe work? Sandbox option, on unless a server turns it off.
function L.wrenchNeeded()
    local pre = DazedCore and DazedCore.Preset and DazedCore.Preset.override("DazedPlumb", "NeedWrench")
    if pre ~= nil then return pre == true end
    local sv = SandboxVars and SandboxVars.DazedPlumb
    return not (sv and sv.NeedWrench == false)
end

--- Does the character carry a pipe wrench that is not broken (or is none needed)?
function L.hasWrench(character)
    if not L.wrenchNeeded() then return true end
    local inv = character and character.getInventory and character:getInventory()
    if not inv then return false end
    local function sound(it) return it ~= nil and not (it.isBroken and it:isBroken()) end
    local ok, w = pcall(inv.getFirstTypeEvalRecurse, inv, "PipeWrench", sound)
    if ok and w then return true end
    if ItemTag and ItemTag.PIPE_WRENCH then
        ok, w = pcall(inv.getFirstTagEvalRecurse, inv, ItemTag.PIPE_WRENCH, sound)
        if ok and w then return true end
    end
    return false
end

--- Does the character have the skill and the wrench? Tells them if not.
local function skilled(character)
    if weldLevel(character) < K.WELD_LEVEL then
        S.note(character, "IGUI_DazedPlumb_NeedWelding")
        return false
    end
    if not L.hasWrench(character) then
        S.note(character, "IGUI_DazedPlumb_NeedWrench")
        return false
    end
    return true
end

----------------------------------------------------------- the actions
local function lineAction(name)
    local A = ISBaseTimedAction:derive(name)
    function A:isValid() return self.machine ~= nil and self.machine:getObjectIndex() ~= -1 end
    function A:waitToStart()
        self.character:faceThisObject(self.machine)
        return self.character:shouldBeTurning()
    end
    function A:update() self.character:faceThisObject(self.machine) end
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
        return 60
    end
    return A
end

--- Lay a run from a machine to a tank or node and join it to any line already
--  serving that target. The router, the skill check and the cost are all here.
DUP_PipeSet = lineAction("DUP_PipeSet")
function DUP_PipeSet:complete()
    local a = self.adapter and L.adapters[self.adapter]
    if not a or not near(self.machine, self.character) then return true end
    local fluid = L.kindOf(a)
    local T = self.tank and L.wrapTarget(self.tank, fluid)
    if not T or (T.isNode and a.noNodes) then return true end
    if not skilled(self.character) then return true end
    local msq = self.machine:getSquare()
    local role, id = "tank", "tank"
    if T.isNode then role, id = "node", T.node.id end
    local plan = K.plan(msq, fluid, T.squares(), role, id)
    if not plan then S.note(self.character, "IGUI_DazedPlumb_NoRoute") return true end
    local cost = K.cost(plan)
    if #L.itemsOf(self.character:getInventory(), K.ITEM) < cost then
        S.note(self.character, "IGUI_DazedPlumb_NeedSections")
        return true
    end
    consume(self.character, K.ITEM, cost)
    local devEnd = L.endFor(self.machine, a)
    local tailEnd = N.endString(N.key(plan.tail.x, plan.tail.y, plan.z), role, id)
    L.attach(self.machine, a)
    K.lay(plan, devEnd, tailEnd)
    return true
end
function DUP_PipeSet:new(character, machine, adapterId, tank)
    local o = ISBaseTimedAction.new(self, character)
    o.machine, o.adapter, o.tank = machine, adapterId, tank
    o.maxTime = o:getDuration()
    return o
end

--- Pipe one tank to another of the same type; on one line their levels even out (see N.balance).
DUP_TankLink = lineAction("DUP_TankLink")
function DUP_TankLink:complete()
    local a, b = self.machine and P.master(self.machine), self.tank and P.master(self.tank)
    local ia, ib = a and P.describe(a), b and P.describe(b)
    if not (ia and ib) or a == b or ia.type ~= ib.type or not near(a, self.character) then return true end
    if not skilled(self.character) then return true end
    local plan = K.plan(a:getSquare(), ia.type, P.squares(b), "tank", "tank")
    if not plan then S.note(self.character, "IGUI_DazedPlumb_NoRoute") return true end
    local cost = K.cost(plan)
    if #L.itemsOf(self.character:getInventory(), K.ITEM) < cost then
        S.note(self.character, "IGUI_DazedPlumb_NeedSections")
        return true
    end
    consume(self.character, K.ITEM, cost)
    local sq = a:getSquare()
    local devEnd = N.endString(N.key(sq:getX(), sq:getY(), sq:getZ()), "tank", "tank")
    local tailEnd = N.endString(N.key(plan.tail.x, plan.tail.y, plan.z), "tank", "tank")
    K.lay(plan, devEnd, tailEnd)
    return true
end
function DUP_TankLink:new(character, fromTank, toTank)
    local o = ISBaseTimedAction.new(self, character)
    o.machine, o.tank = fromTank, toTank
    o.maxTime = o:getDuration()
    return o
end

--- Take a machine off its line; the dead-end pipe comes up and some of it comes back.
DUP_LinkClear = lineAction("DUP_LinkClear")
function DUP_LinkClear:complete()
    local a = self.adapter and L.adapters[self.adapter]
    if not a or not near(self.machine, self.character) then return true end
    local sound = L.clear(self.machine, a)
    give(self.character, K.ITEM, math.floor(sound * K.REFUND))
    return true
end
function DUP_LinkClear:new(character, machine, adapterId)
    local o = ISBaseTimedAction.new(self, character)
    o.machine, o.adapter = machine, adapterId
    o.maxTime = o:getDuration()
    return o
end

DUP_LinkSource = lineAction("DUP_LinkSource")
function DUP_LinkSource:complete()
    local a = self.adapter and L.adapters[self.adapter]
    if not a or not near(self.machine, self.character) then return true end
    if self.source == "tank" or self.source == "manual" then L.setSource(self.machine, a, self.source) end
    return true
end
function DUP_LinkSource:new(character, machine, adapterId, source)
    local o = ISBaseTimedAction.new(self, character)
    o.machine, o.adapter, o.source = machine, adapterId, source
    o.maxTime = o:getDuration()
    return o
end

----------------------------------------------------------- one square of pipe
-- (self.x, self.y, self.z) name the square; the character must be beside it.
local function pipeAction(name, fn)
    local A = lineAction(name)
    function A:isValid() return self.x ~= nil and self.character:getSquare() ~= nil end
    function A:waitToStart() return false end
    function A:update() end
    function A:complete()
        if math.abs(self.x - self.character:getX()) <= 3 and math.abs(self.y - self.character:getY()) <= 3
                and self.z == self.character:getZ() then
            fn(self)
        end
        return true
    end
    function A:new(character, x, y, z)
        local o = ISBaseTimedAction.new(self, character)
        o.x, o.y, o.z = x, y, z
        o.maxTime = o:getDuration()
        return o
    end
    return A
end

DUP_PipeCut = pipeAction("DUP_PipeCut", function(a)
    if not L.hasWrench(a.character) then S.note(a.character, "IGUI_DazedPlumb_NeedWrench") return end
    K.breakAt(a.x, a.y, a.z)
end)

DUP_PipeRepair = pipeAction("DUP_PipeRepair", function(a)
    local r = K.record(a.x, a.y, a.z)
    if not r or (r.cond or 100) >= 100 then return end
    if not skilled(a.character) then return end
    if not consume(a.character, K.ITEM, 1) then S.note(a.character, "IGUI_DazedPlumb_NeedSections") return end
    K.repairAt(a.x, a.y, a.z)
end)

DUP_ValveFit = pipeAction("DUP_ValveFit", function(a)
    if not K.canValve(a.x, a.y, a.z) then return end
    if weldLevel(a.character) < 2 then S.note(a.character, "IGUI_DazedPlumb_NeedWeldingValve") return end
    if not L.hasWrench(a.character) then S.note(a.character, "IGUI_DazedPlumb_NeedWrench") return end
    if not consume(a.character, K.VALVE_ITEM, 1) then S.note(a.character, "IGUI_DazedPlumb_NeedValve") return end
    K.setValve(a.x, a.y, a.z, "open")
end)

DUP_ValveToggle = pipeAction("DUP_ValveToggle", function(a)
    local r = K.record(a.x, a.y, a.z)
    if not r or not r.valve then return end
    K.setValve(a.x, a.y, a.z, r.valve == "open" and "closed" or "open")
end)

-- The game's own sounds for each job.
for _, A in ipairs({ DUP_PipeSet, DUP_TankLink, DUP_LinkClear, DUP_PipeCut, DUP_PipeRepair, DUP_ValveFit, DUP_ValveToggle }) do
    A.SOUND = "RepairWithWrench"
end
