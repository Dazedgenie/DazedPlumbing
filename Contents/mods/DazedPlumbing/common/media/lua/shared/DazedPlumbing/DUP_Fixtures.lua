--[[ Dazed Utilities: Plumbing -- taps: a sink, bath, shower, toilet or washer piped to a tank is topped up from it
     every minute, into a FluidContainer on the fixture (made if missing) where the game looks once the town water is off.
     While the town supply still runs the fixture has endless water of its own and is left alone. ]]

require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Links"
require "DazedPlumbing/DUP_Fluids"

DazedPlumb.Fixtures = DazedPlumb.Fixtures or {}
local X = DazedPlumb.Fixtures
local P, L, F = DazedPlumb.Parts, DazedPlumb.Links, DazedPlumb.Fluids
local try = P.try

X.ID = "dazed_fixture"
-- A tile's own name for the fixtures that can be fed (the engine's waterPiped flag covers most of them).
X.NAMES = { sink = 20, bath = 100, shower = 60, toilet = 15, ["washing machine"] = 40, ["combo washer dryer"] = 40,
            dishwasher = 20, urinal = 10, ["water dispenser"] = 20, ["water cooler"] = 20, fountain = 50 }
X.DEFAULT_CAP = 20

local once = P.once

local function customName(obj)
    local v = P.prop(obj, "CustomName")
    return type(v) == "string" and string.lower(v) or ""
end

--- Is this object a water fixture? The engine's plumbing flag, or a fixture's own tile name.
function X.isFixture(obj)
    if not obj or P.describe(obj) then return false end
    if P.propIs(obj, "waterPiped") then return true end
    local flag = IsoFlagType and IsoFlagType.waterPiped
    if flag and P.propIs(obj, flag) then return true end
    if X.NAMES[customName(obj)] then return true end
    -- a sink set into a counter: a fixtures tile that holds water of its own
    local spr = try(obj, "getSpriteName")
    if type(spr) == "string" and string.find(string.lower(spr), "fixtures", 1, true)
            and try(obj, "getFluidContainer") ~= nil then
        return true
    end
    return false
end

--- Litres the fixture holds when full: its tile's own figure, else a figure for its kind.
function X.capacity(obj)
    local v = tonumber(P.prop(obj, "waterMaxAmount") or P.prop(obj, "WaterMaxAmount"))
    if v and v > 0 then return v end
    return X.NAMES[customName(obj)] or X.DEFAULT_CAP
end

--- Is the town supply still running? Unknown counts as "no" (the tap is fed).
function X.townWater()
    local mod = SandboxVars and tonumber(SandboxVars.WaterShutModifier)
    local gt = getGameTime and getGameTime()
    local hours = gt and try(gt, "getWorldAgeHours")
    if mod == nil or type(hours) ~= "number" then return false end
    local on = mod >= 0 and (hours / 24) < mod
    once("town", string.format("town water: WaterShutModifier=%s, day %.1f -> %s", tostring(mod), hours / 24, on and "on" or "off"))
    return on
end

--- Does the game give this fixture endless water now (town supply on, and still plumbed in where it was built)?
local function endless(obj)
    if not X.townWater() then return false end
    local md = try(obj, "getModData")
    return not (md and md.canBeWaterPiped == true) and try(obj, "getUsesExternalWaterSource") ~= true
end

--- Plumbed by the game to a rain barrel upstairs that is really there? Then it is the barrel's business.
local function barrelFed(obj)
    return try(obj, "getUsesExternalWaterSource") == true and try(obj, "FindExternalWaterSource") ~= nil
end

--- Litres the fixture can still take.
function X.room(obj)
    if endless(obj) or barrelFed(obj) then return 0 end
    local cap = X.capacity(obj)
    local fc = try(obj, "getFluidContainer")
    if fc then
        cap = math.max(cap, try(fc, "getCapacity") or 0)
        return math.max(0, cap - (try(fc, "getAmount") or 0))
    end
    return cap                                   -- no container yet: put() makes one
end

--- Put water in; returns what went in (read back from the fixture).
function X.put(obj, amount, dirty)
    local want = math.min(amount or 0, X.room(obj))
    if want <= 0.001 then return 0 end
    local fc = F.ensureContainer(obj, math.max(X.capacity(obj), 0))
    if not fc then return 0 end
    -- plumbed by the game to a barrel that is gone: our pipe takes over, or the game would look upstairs for water
    if try(obj, "getUsesExternalWaterSource") == true then
        pcall(obj.setUsesExternalWaterSource, obj, false)
        if IsoObjectChange and obj.sendObjectChange then
            pcall(obj.sendObjectChange, obj, IsoObjectChange.USES_EXTERNAL_WATER_SOURCE, { value = false })
        end
    end
    local before = try(fc, "getAmount") or 0
    local ft = F.fluidType("water", dirty == true)
    local ok = ft ~= nil and pcall(fc.addFluid, fc, ft, want)
    local after = try(fc, "getAmount") or before
    once("fc", "tap: filling the fixture " .. ((ok and after > before) and "worked" or "did NOT raise it"))
    if after > before + 1e-6 then
        F.syncObject(obj)
        return after - before
    end
    return 0
end

L.register({
    id = X.ID, supplies = "water", label = "ContextMenu_DazedPlumb_Tap",
    match = X.isFixture, room = X.room, put = X.put,
})

return X
