--[[ Dazed Utilities: Plumbing -- timed actions for the fuel pump: refuel a parked vehicle and fill a carried can.
     Each action moves one chunk on the authority, whose complete() re-checks everything; the menu queues several.
     Only plain fields (the pump, the vehicle or item, a number) go to the server. ]]

require "TimedActions/ISBaseTimedAction"
require "DazedPlumbing/DUP_FuelPumps"

local Fp, S = DazedPlumb.FuelPumps, DazedPlumb.Sync

local function near(pump, character)
    local sq = pump and pump:getSquare()
    return sq ~= nil and math.abs(sq:getX() - character:getX()) <= 2
       and math.abs(sq:getY() - character:getY()) <= 2 and sq:getZ() == character:getZ()
end

local function stillCarried(item)
    local cont = item and item.getContainer and item:getContainer()
    if not cont then return nil end
    if item.getWorldItem and item:getWorldItem() then return nil end
    return cont
end

-- A short reason for the player, by translation key.
local function refuse(character, why)
    if why and why ~= "far" and why ~= "gone" then S.note(character, "IGUI_DazedPlumb_Fuel_" .. why) end
end

local function fuelAction(name)
    local A = ISBaseTimedAction:derive(name)
    function A:isValid() return self.pump ~= nil and self.pump:getObjectIndex() ~= -1 and Fp.isFuelPump(self.pump) end
    function A:waitToStart()
        self.character:faceThisObject(self.pump)
        return self.character:shouldBeTurning()
    end
    function A:update() self.character:faceThisObject(self.pump) end
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
        return Fp.ticks(Fp.kindOf(self.pump) or "hand", self.litres or Fp.CHUNK.hand)
    end
    return A
end

------------------------------------------------------------ a vehicle
DUP_FuelVehicle = fuelAction("DUP_FuelVehicle")
local vehicleValid = DUP_FuelVehicle.isValid
-- A queue of chunks stops by itself when the tanks run dry, the vehicle is full or it moves off.
function DUP_FuelVehicle:isValid()
    if not vehicleValid(self) then return false end
    self.checks = (self.checks or 0) + 1                 -- asked every tick, so look only now and then
    if self.checks % 30 ~= 1 then return self.lastOk ~= false end
    local t = Fp.tankOf(self.vehicle)
    self.lastOk = t ~= nil and t.room > Fp.EPS and Fp.line(self.pump).litres > Fp.EPS
        and Fp.parked(self.vehicle) and Fp.ready(self.pump) == true
    return self.lastOk
end
function DUP_FuelVehicle:complete()
    if not near(self.pump, self.character) then return true end
    local moved, why = Fp.refuel(self.pump, self.vehicle, self.litres)
    if moved <= 0 then refuse(self.character, why) end
    return true
end
function DUP_FuelVehicle:new(character, pump, vehicle, litres)
    local o = ISBaseTimedAction.new(self, character)
    o.pump, o.vehicle, o.litres = pump, vehicle, litres
    o.maxTime = o:getDuration()
    return o
end

------------------------------------------------------------ a carried can
DUP_FuelCan = fuelAction("DUP_FuelCan")
local canValid = DUP_FuelCan.isValid
function DUP_FuelCan:isValid()
    if not canValid(self) then return false end
    self.checks = (self.checks or 0) + 1
    if self.checks % 30 ~= 1 then return self.lastOk ~= false end
    self.lastOk = stillCarried(self.item) ~= nil and Fp.canTake(self.item)
        and Fp.line(self.pump).litres > Fp.EPS and Fp.ready(self.pump) == true
    return self.lastOk
end
function DUP_FuelCan:complete()
    if not near(self.pump, self.character) then return true end
    if not stillCarried(self.item) then return true end
    local moved, why = Fp.fillCan(self.pump, self.item, self.litres)
    if moved > 0 then
        if sendItemStats then sendItemStats(self.item) end
    else
        refuse(self.character, why)
    end
    return true
end
function DUP_FuelCan:new(character, pump, item, litres)
    local o = ISBaseTimedAction.new(self, character)
    o.pump, o.item, o.litres = pump, item, litres
    o.maxTime = o:getDuration()
    return o
end

-- The game's own refuelling sound for both jobs.
DUP_FuelVehicle.SOUND = "VehicleAddFuelFromGasPump"
DUP_FuelCan.SOUND = "VehicleAddFuelFromGasPump"
