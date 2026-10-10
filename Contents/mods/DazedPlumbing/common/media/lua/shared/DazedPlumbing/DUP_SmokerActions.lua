--[[ Dazed Plumbing -- the timed action that lights or puts out a smoker.
     The authority's complete() re-checks the gas; only plain fields (the smoker and on/off) go to the server. ]]

require "TimedActions/ISBaseTimedAction"
require "DazedPlumbing/DUP_Smokers"

local Sm, S = DazedPlumb.Smokers, DazedPlumb.Sync

local function near(obj, character)
    local sq = obj and obj:getSquare()
    return sq ~= nil and math.abs(sq:getX() - character:getX()) <= 2
       and math.abs(sq:getY() - character:getY()) <= 2 and sq:getZ() == character:getZ()
end

DUP_SmokerLight = ISBaseTimedAction:derive("DUP_SmokerLight")

function DUP_SmokerLight:isValid()
    return self.obj ~= nil and self.obj:getObjectIndex() ~= -1 and Sm.isSmoker(self.obj)
end
function DUP_SmokerLight:waitToStart()
    self.character:faceThisObject(self.obj)
    return self.character:shouldBeTurning()
end
function DUP_SmokerLight:update() self.character:faceThisObject(self.obj) end
function DUP_SmokerLight:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
end
function DUP_SmokerLight:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 40
end
--- On the authority: light it (only with gas on the line) or put it out, telling the player why not.
function DUP_SmokerLight:complete()
    if not near(self.obj, self.character) then return true end
    local ok, why = Sm.setLit(self.obj, self.on == true)
    if not ok and why then S.note(self.character, "IGUI_DazedPlumb_Smoker_" .. why) end
    return true
end
function DUP_SmokerLight:new(character, obj, on)
    local o = ISBaseTimedAction.new(self, character)
    o.obj, o.on = obj, on
    o.maxTime = o:getDuration()
    return o
end
