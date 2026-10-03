--[[ Dazed Utilities: Plumbing -- the timed action for the biogas digester: add one item of waste.
     The authority's complete() re-checks everything; the menu queues one action per item.
     Only plain fields (the digester and the item) go to the server. ]]

require "TimedActions/ISBaseTimedAction"
require "DazedPlumbing/DUP_Digesters"

local Dg, S = DazedPlumb.Digesters, DazedPlumb.Sync

local function near(obj, character)
    local sq = obj and obj:getSquare()
    return sq ~= nil and math.abs(sq:getX() - character:getX()) <= 2
       and math.abs(sq:getY() - character:getY()) <= 2 and sq:getZ() == character:getZ()
end

local function stillCarried(item)
    local cont = item and item.getContainer and item:getContainer()
    if not cont then return nil end
    if item.getWorldItem and item:getWorldItem() then return nil end
    return cont
end

DUP_DigesterAdd = ISBaseTimedAction:derive("DUP_DigesterAdd")

function DUP_DigesterAdd:isValid()
    if not (self.digester ~= nil and self.digester:getObjectIndex() ~= -1 and Dg.isDigester(self.digester)) then return false end
    self.checks = (self.checks or 0) + 1                 -- asked every tick, so look at the item only now and then
    if self.checks % 30 ~= 1 then return self.lastOk ~= false end
    local kind, units = Dg.classify(self.item)
    self.lastOk = stillCarried(self.item) ~= nil and kind ~= nil and Dg.room(Dg.state(self.digester).waste) >= units - Dg.EPS
    return self.lastOk
end
function DUP_DigesterAdd:waitToStart()
    self.character:faceThisObject(self.digester)
    return self.character:shouldBeTurning()
end
function DUP_DigesterAdd:update() self.character:faceThisObject(self.digester) end
function DUP_DigesterAdd:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    self.character:reportEvent("EventLootItem")
end
function DUP_DigesterAdd:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 50
end
--- On the authority: feed the item in, or tell the player why not.
function DUP_DigesterAdd:complete()
    if not near(self.digester, self.character) then return true end
    if not stillCarried(self.item) then return true end
    local added, why = Dg.add(self.digester, self.item)
    if added <= 0 and why then S.note(self.character, "IGUI_DazedPlumb_Digester_" .. why) end
    return true
end
function DUP_DigesterAdd:new(character, digester, item)
    local o = ISBaseTimedAction.new(self, character)
    o.digester, o.item = digester, item
    o.maxTime = o:getDuration()
    return o
end
