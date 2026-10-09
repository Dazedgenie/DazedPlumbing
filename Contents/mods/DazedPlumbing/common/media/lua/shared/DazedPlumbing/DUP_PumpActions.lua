--[[ Dazed Plumbing -- timed actions for the pumps: work the handle
     (into the piped tank) and fill a carried container from the well.
     Run by the authority; complete() re-checks everything. ]]

require "TimedActions/ISBaseTimedAction"
require "DazedPlumbing/DUP_Pumps"
require "DazedPlumbing/DUP_Purifiers"
require "DazedPlumbing/DUP_Fluids"
require "DazedPlumbing/DUP_FuelPumps"
require "DazedPlumbing/DUP_DrilledWells"

local P, M, L, U, F = DazedPlumb.Parts, DazedPlumb.Model, DazedPlumb.Links, DazedPlumb.Pumps, DazedPlumb.Fluids

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

local function pumpAction(name, duration)
    local A = ISBaseTimedAction:derive(name)
    function A:isValid() return self.pump ~= nil and self.pump:getObjectIndex() ~= -1 and U.isPump(self.pump) end
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
        return duration(self)
    end
    return A
end

--- Does this pump give water right now (an electric one needs power)?
local function works(pump)
    local info = U.describe(pump)
    return info ~= nil and (info.kind == "hand" or U.powered(pump))
end

------------------------------------------------------------ the handle
--- Room left in everything on a hand pump's line (0 when it is not piped to a tank).
function U.lineRoom(pump)
    local link = L.linkOf(pump, U.ID)
    if not link or link.source ~= "tank" then return 0 end
    local room = 0
    for _, r in ipairs(L.status(pump, L.adapters[U.ID]).receivers) do room = room + (r.room() or 0) end
    return room
end

DUP_PumpStroke = pumpAction("DUP_PumpStroke", function() return 135 end)  -- slowed by half again from 90

--- Show the handle up or down on this player's screen only; the server's pump keeps its handle up.
local function showHandle(pump, down)
    local info = U.describe(pump)
    if not info or info.kind ~= "hand" or (info.stroke == true) == down then return end
    local name = U.handleSprite(info.facing, down)
    pump:setSprite(name)
    if pump.setSpriteFromName then pcall(pump.setSpriteFromName, pump, name) end
end

-- Working a lever: the character pumps and the handle goes down twice a stroke, water running from the spout.
function DUP_PumpStroke:start()
    self:setActionAnim("UseHandPress")
    DazedPlumb.Parts.startSound(self)
end
function DUP_PumpStroke:update()
    self.character:faceThisObject(self.pump)
    local delta = self.getJobDelta and self:getJobDelta() or 0
    showHandle(self.pump, math.floor(delta * 4) % 2 == 1)
end
function DUP_PumpStroke:stop()
    showHandle(self.pump, false)
    DazedPlumb.Parts.stopSound(self)
    ISBaseTimedAction.stop(self)
end
function DUP_PumpStroke:perform()
    showHandle(self.pump, false)
    DazedPlumb.Parts.stopSound(self)
    ISBaseTimedAction.perform(self)
end
local strokeValid = DUP_PumpStroke.isValid
-- A queue of strokes stops by itself once the tanks are full or the well runs dry.
function DUP_PumpStroke:isValid()
    if not strokeValid(self) then return false end
    -- asked every tick, so the tank and well are only looked at now and then
    self.checks = (self.checks or 0) + 1
    if self.checks % 30 ~= 1 then return self.lastOk ~= false end
    local sq = self.pump:getSquare()
    self.lastOk = sq ~= nil and U.lineRoom(self.pump) > 0.001 and U.well(sq).reserve > 0.5
    return self.lastOk
end
function DUP_PumpStroke:complete()
    local pump = self.pump
    if not near(pump, self.character) or not works(pump) then return true end
    local link = L.linkOf(pump, U.ID)
    if not link or link.source ~= "tank" then return true end
    local a = L.adapters[U.ID]
    local st = L.status(pump, a)
    local room = 0
    for _, r in ipairs(st.receivers) do room = room + r.room() end
    local want = math.min(U.STROKE, room)
    if want <= 0.001 then return true end
    local got = U.draw(pump:getSquare(), want)
    if got > 0 then
        L.pushFrom(pump, a, got, true)                            -- ground water is tainted, shared by room
        if addXp and Perks and Perks.Strength then addXp(self.character, Perks.Strength, 1) end
    end
    return true
end
function DUP_PumpStroke:new(character, pump)
    local o = ISBaseTimedAction.new(self, character)
    o.pump = pump
    o.maxTime = o:getDuration()
    return o
end

------------------------------------------------------------ fill a container
DUP_PumpFill = pumpAction("DUP_PumpFill", function(self) return math.max(90, math.floor((self.units or 5) * 18)) end)
-- Filling a container at a hand pump works the handle the same way; an electric pump just runs.
local function isHand(pump) local i = U.describe(pump) return i ~= nil and i.kind == "hand" end
function DUP_PumpFill:start()
    if isHand(self.pump) then self:setActionAnim("UseHandPress") else self:setActionAnim("Loot") self.character:SetVariable("LootPosition", "Low") end
    DazedPlumb.Parts.startSound(self)
end
function DUP_PumpFill:update()
    self.character:faceThisObject(self.pump)
    if isHand(self.pump) then
        local delta = self.getJobDelta and self:getJobDelta() or 0
        showHandle(self.pump, math.floor(delta * math.max(2, (self.units or 5) / 2.5)) % 2 == 1)
    end
end
function DUP_PumpFill:stop() showHandle(self.pump, false) DazedPlumb.Parts.stopSound(self) ISBaseTimedAction.stop(self) end
function DUP_PumpFill:perform() showHandle(self.pump, false) DazedPlumb.Parts.stopSound(self) ISBaseTimedAction.perform(self) end

function DUP_PumpFill:complete()
    local pump = self.pump
    if not near(pump, self.character) or not works(pump) then return true end
    if not stillCarried(self.item) then return true end
    local v = F.vessel(self.item)
    if not v or (v.kind ~= "water" and v.kind ~= "empty") then return true end
    local want = math.min(v.capacity - v.amount, U.well(pump:getSquare()).reserve)
    if want <= 0.001 then return true end
    local added = F.fill(self.item, "water", want, true)    -- ground water is tainted
    if added > 0 then
        U.draw(pump:getSquare(), added)             -- the well pays for what really went in
        if sendItemStats then sendItemStats(self.item) end
    end
    return true
end
function DUP_PumpFill:new(character, pump, item, units)
    local o = ISBaseTimedAction.new(self, character)
    o.pump, o.item, o.units = pump, item, units
    o.maxTime = o:getDuration()
    return o
end

------------------------------------------------------------ purifier filter
-- Fit a cartridge (consumed; its remaining life becomes the filter's) or take
-- the fitted one out (comes back as an item with its remaining condition).
local Pu = DazedPlumb.Purifiers

local function purifierAction(name)
    local A = ISBaseTimedAction:derive(name)
    function A:isValid() return self.pump ~= nil and self.pump:getObjectIndex() ~= -1 and Pu.isPurifier(self.pump) end
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
        return 80
    end
    return A
end

DUP_FilterInstall = purifierAction("DUP_FilterInstall")
function DUP_FilterInstall:complete()
    if not near(self.pump, self.character) then return true end
    local cont = stillCarried(self.item)
    if not cont or self.item:getFullType() ~= Pu.FILTER_ITEM then return true end
    local st = Pu.state(self.pump)
    if (st.filter or 0) > 0 then return true end             -- one at a time: take the old one out first
    local life = self.item:getCondition() or 100
    if life <= 0 then return true end
    cont:Remove(self.item)
    if sendRemoveItemFromContainer then sendRemoveItemFromContainer(cont, self.item) end
    st.filter = life
    self.pump:transmitModData()
    return true
end
function DUP_FilterInstall:new(character, pump, item)
    local o = ISBaseTimedAction.new(self, character)
    o.pump, o.item = pump, item
    o.maxTime = o:getDuration()
    return o
end

DUP_FilterRemove = purifierAction("DUP_FilterRemove")
function DUP_FilterRemove:complete()
    if not near(self.pump, self.character) then return true end
    local st = Pu.state(self.pump)
    if (st.filter or 0) <= 0 then return true end
    local it = instanceItem and instanceItem(Pu.FILTER_ITEM)
    if not it then return true end
    it:setCondition(math.max(1, math.floor(st.filter)))
    local inv = self.character:getInventory()
    inv:AddItem(it)
    if sendAddItemToContainer then sendAddItemToContainer(inv, it) end
    st.filter = nil
    self.pump:transmitModData()
    return true
end
function DUP_FilterRemove:new(character, pump)
    local o = ISBaseTimedAction.new(self, character)
    o.pump = pump
    o.maxTime = o:getDuration()
    return o
end

------------------------------------------------------------ the flow setting (electric pump, purifier)
DUP_SetFlow = ISBaseTimedAction:derive("DUP_SetFlow")
function DUP_SetFlow:isValid()
    local o = self.obj
    return o ~= nil and o:getObjectIndex() ~= -1 and (Pu.isPurifier(o) or U.isPump(o))
end
function DUP_SetFlow:waitToStart()
    self.character:faceThisObject(self.obj)
    return self.character:shouldBeTurning()
end
function DUP_SetFlow:update() self.character:faceThisObject(self.obj) end
function DUP_SetFlow:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    DazedPlumb.Parts.startSound(self)
end
function DUP_SetFlow:stop() DazedPlumb.Parts.stopSound(self) ISBaseTimedAction.stop(self) end
function DUP_SetFlow:perform() DazedPlumb.Parts.stopSound(self) ISBaseTimedAction.perform(self) end
function DUP_SetFlow:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 30
end
--- On the authority: store the setting the player picked (one of U.FLOWS).
function DUP_SetFlow:complete()
    if not near(self.obj, self.character) then return true end
    local ok = false
    for _, f in ipairs(U.FLOWS) do if f == self.flow then ok = true end end
    if not ok then return true end
    self.obj:getModData().dazedFlow = self.flow
    self.obj:transmitModData()
    return true
end
function DUP_SetFlow:new(character, obj, flow)
    local o = ISBaseTimedAction.new(self, character)
    o.obj, o.flow = obj, flow
    o.maxTime = o:getDuration()
    return o
end

------------------------------------------------------------ the power switch (electric pump, purifier)
DUP_PowerSwitch = ISBaseTimedAction:derive("DUP_PowerSwitch")
function DUP_PowerSwitch:isValid()
    local o = self.obj
    return o ~= nil and o:getObjectIndex() ~= -1 and (Pu.isPurifier(o) or U.isPump(o) or DazedPlumb.FuelPumps.isFuelPump(o) or DazedPlumb.DrilledWells.isWell(o))
end
function DUP_PowerSwitch:waitToStart()
    self.character:faceThisObject(self.obj)
    return self.character:shouldBeTurning()
end
function DUP_PowerSwitch:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
end
function DUP_PowerSwitch:perform()
    if self.character.playSound then self.character:playSound("KnobSwitch") end
    ISBaseTimedAction.perform(self)
end
function DUP_PowerSwitch:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 20
end
--- On the authority: flip the switch the player chose.
function DUP_PowerSwitch:complete()
    if not near(self.obj, self.character) then return true end
    self.obj:getModData().dazedOff = (not self.on) or nil
    self.obj:transmitModData()
    return true
end
function DUP_PowerSwitch:new(character, obj, on)
    local o = ISBaseTimedAction.new(self, character)
    o.obj, o.on = obj, on
    o.maxTime = o:getDuration()
    return o
end

------------------------------------------------------------ the sprinkler switch
require "DazedPlumbing/DUP_Sprinklers"
local Zs = DazedPlumb.Sprinklers
DUP_SprinklerToggle = ISBaseTimedAction:derive("DUP_SprinklerToggle")
function DUP_SprinklerToggle:isValid()
    return self.obj ~= nil and self.obj:getObjectIndex() ~= -1 and Zs.isSprinkler(self.obj)
end
function DUP_SprinklerToggle:waitToStart()
    self.character:faceThisObject(self.obj)
    return self.character:shouldBeTurning()
end
function DUP_SprinklerToggle:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
end
function DUP_SprinklerToggle:stop() DazedPlumb.Parts.stopSound(self) ISBaseTimedAction.stop(self) end
function DUP_SprinklerToggle:perform() DazedPlumb.Parts.stopSound(self) ISBaseTimedAction.perform(self) end
function DUP_SprinklerToggle:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 30
end
--- On the authority: switch it on or off; switched off it stops spraying at once.
function DUP_SprinklerToggle:complete()
    if not near(self.obj, self.character) then return true end
    Zs.state(self.obj).off = not self.on or nil
    if not self.on then Zs.setSpraying(self.obj, false) end
    self.obj:transmitModData()
    return true
end
function DUP_SprinklerToggle:new(character, obj, on)
    local o = ISBaseTimedAction.new(self, character)
    o.obj, o.on = obj, on
    o.maxTime = o:getDuration()
    return o
end

------------------------------------------------------------ the sprinkler schedule
-- One action for both settings: `field` is "window" (from, to: hours, or -1/-1 for always) or "rain" (skip: boolean).
DUP_SprinklerSchedule = ISBaseTimedAction:derive("DUP_SprinklerSchedule")
DUP_SprinklerSchedule.isValid = DUP_SprinklerToggle.isValid
DUP_SprinklerSchedule.waitToStart = DUP_SprinklerToggle.waitToStart
DUP_SprinklerSchedule.start = DUP_SprinklerToggle.start
DUP_SprinklerSchedule.stop = DUP_SprinklerToggle.stop
DUP_SprinklerSchedule.perform = DUP_SprinklerToggle.perform
function DUP_SprinklerSchedule:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 20
end
--- On the authority: re-check the values and store them; a held-back sprinkler stops spraying at once.
function DUP_SprinklerSchedule:complete()
    if not near(self.obj, self.character) then return true end
    local stored = false
    if self.field == "window" then
        stored = Zs.setWindow(self.obj, tonumber(self.from), tonumber(self.to))
    elseif self.field == "rain" and type(self.skip) == "boolean" then
        stored = Zs.setRainSkip(self.obj, self.skip)
    end
    if not stored then return true end
    if Zs.blocked(self.obj) then Zs.setSpraying(self.obj, false) end
    self.obj:transmitModData()
    return true
end
function DUP_SprinklerSchedule:new(character, obj, field, from, to, skip)
    local o = ISBaseTimedAction.new(self, character)
    o.obj, o.field, o.from, o.to, o.skip = obj, field, from, to, skip
    o.maxTime = o:getDuration()
    return o
end

-- The game's own sounds for each job.
DUP_PumpStroke.SOUND = "GetWaterFromTap"
DUP_PumpFill.SOUND = "GetWaterFromTap"
DUP_FilterInstall.SOUND = "RepairWithWrench"
DUP_FilterRemove.SOUND = "RepairWithWrench"
DUP_SetFlow.SOUND = "RepairWithWrench"
