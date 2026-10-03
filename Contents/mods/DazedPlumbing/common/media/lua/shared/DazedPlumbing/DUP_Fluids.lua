--[[ Dazed Utilities: Plumbing -- reading and changing what a carried
     container holds.

     Three kinds of vessel, three ways the game stores their contents:

       propane   vanilla DRAINABLES (Base.PropaneTank 9 kg, Base.Propane_Refill
                 0.45 kg): a 0..1 fill through getCurrentUsesFloat /
                 setCurrentUsesFloat (the way Dazed Power reads car batteries).
       water     B42 FLUID CONTAINERS: item:getFluidContainer(), litres.
       gas       petrol is a fluid in B42 as well; where a build still has the
                 petrol can as a drainable, its "uses" are read as litres.

     Taking things OUT of a tank into a container needs to ADD a fluid to a
     fluid container, which is the one call here that has not been proven
     in play (Dazed Power only ever drains water). So every engine call is
     pcall'd, a result is checked by reading the container back, and the
     first time each path is used the console says which one worked, so a
     failure is a one-line report rather than a mystery.

     All functions answer for ONE item; none touches a tank.
]]

require "DazedPlumbing/DUP_Model"

DazedPlumb.Fluids = DazedPlumb.Fluids or {}
local F = DazedPlumb.Fluids
local M = DazedPlumb.Model

local function try(obj, method, ...)
    if obj == nil or type(obj[method]) ~= "function" then return nil end
    local ok, v = pcall(obj[method], obj, ...)
    if ok then return v end
    return nil
end

local said = {}
local function once(key, text)
    if said[key] then return end
    said[key] = true
    print("DazedPlumbing: " .. text)
end

--- What a fluid container holds, as one of our types ("water", "gas") or nil.
local function fluidKind(fc, item)
    local primary = try(fc, "getPrimaryFluid")
    local name = primary and (try(primary, "getFluidTypeString") or try(primary, "toString"))
    name = name and string.lower(tostring(name)) or nil
    if name then
        if string.find(name, "water", 1, true) then return "water" end
        if string.find(name, "petrol", 1, true) or string.find(name, "gasoline", 1, true)
                or string.find(name, "fuel", 1, true) then
            return "gas"
        end
        return nil
    end
    -- An EMPTY container names no fluid; what it was made for is its type.
    local ft = item and try(item, "getFullType")
    if ft and string.find(ft, "Petrol", 1, true) then return "gas" end
    return nil
end

--- Does this fluid container hold TAINTED water?
function F.isTaintedFluid(fc)
    local primary = try(fc, "getPrimaryFluid")
    local name = primary and (try(primary, "getFluidTypeString") or try(primary, "toString"))
    return name ~= nil and string.find(string.lower(tostring(name)), "tainted", 1, true) ~= nil
end

--- Describe a carried item as a vessel: kind ("propane"|"water"|"gas"), the
--  amount it holds now, and its capacity, in our units. nil if it is not
--  one. `how` says which API reads it ("drain", "fluid", "uses").
function F.vessel(item)
    if not item then return nil end
    local ft = try(item, "getFullType")
    local kg = ft and M.PROPANE_VESSELS[ft]
    if kg then
        local fill = try(item, "getCurrentUsesFloat")
        if type(fill) ~= "number" then return nil end
        return { kind = "propane", amount = math.max(0, math.min(1, fill)) * kg, capacity = kg, how = "drain" }
    end
    local fc = try(item, "getFluidContainer")
    if fc then
        local amount, capacity = try(fc, "getAmount"), try(fc, "getCapacity")
        if type(amount) ~= "number" or type(capacity) ~= "number" then return nil end
        local kind = fluidKind(fc, item)
        if kind == nil and amount <= 0 and try(item, "isWaterSource") then kind = "water" end
        if kind then
            return { kind = kind, amount = amount, capacity = capacity, how = "fluid",
                     tainted = (kind == "water" and amount > 0 and F.isTaintedFluid(fc)) or nil }
        end
        -- Empty and unnamed: it can take water or petrol; the caller decides.
        if amount <= 0 then return { kind = "empty", amount = 0, capacity = capacity, how = "fluid" } end
        return nil
    end
    if ft and string.find(ft, "PetrolCan", 1, true) then
        local cur, max = try(item, "getCurrentUses"), try(item, "getMaxUses")
        if type(cur) == "number" and type(max) == "number" and max > 0 then
            return { kind = "gas", amount = cur, capacity = max, how = "uses" }
        end
    end
    return nil
end

--- The engine's Fluid object for "water" / "gas", or nil.
local function fluidObject(kind, tainted)
    local name = (kind == "water") and (tainted and "TaintedWater" or "Water") or "Petrol"
    local candidates = {
        function() return Fluid and Fluid[name] end,
        function() return Fluid and Fluid.Get and Fluid.Get(name) end,
        function() return FluidType and FluidType[name] end,
    }
    for _, get in ipairs(candidates) do
        local ok, f = pcall(get)
        if ok and f then return f end
    end
    return nil
end

F.fluidObject = fluidObject

--- Set what a vessel holds to `amount` (our units). Returns what it holds
--  afterwards, read back, or nil if nothing could be done.
--  `kind` is the type being poured in (needed to fill an empty container).
function F.setAmount(item, kind, amount, tainted)
    local v = F.vessel(item)
    if not v then return nil end
    amount = math.max(0, math.min(v.capacity, amount))
    if v.how == "drain" then
        if not item.setCurrentUsesFloat then return nil end
        item:setCurrentUsesFloat(amount / v.capacity)
    elseif v.how == "uses" then
        if not item.setCurrentUses then return nil end
        item:setCurrentUses(math.floor(amount + 0.5))
    else
        local fc = try(item, "getFluidContainer")
        if not fc then return nil end
        if amount > v.amount then
            -- RAISING a fluid container: adjustAmount may only lower or clamp,
            -- so add the fluid (the container's own fluid when it has one).
            local fluid = try(fc, "getPrimaryFluid")
            if v.amount <= 0 or v.kind == "empty" or fluid == nil then fluid = fluidObject(kind, tainted) end
            local ok = fluid ~= nil and pcall(fc.addFluid, fc, fluid, amount - v.amount)
            local mid = F.vessel(item)
            local rose = mid and mid.amount > v.amount + 1e-6
            once("add" .. kind .. (v.amount > 0 and "P" or "E"), "raising a " .. (v.amount > 0 and "part-full" or "empty")
                .. " container with " .. kind .. ": addFluid "
                .. ((ok and rose) and "worked" or ("did NOT raise it (call " .. tostring(ok) .. ", fluid " .. tostring(fluid) .. ")")))
            if not rose then pcall(fc.adjustAmount, fc, amount) end   -- last resort: set it
        else
            pcall(fc.adjustAmount, fc, amount)
        end
    end
    local after = F.vessel(item)
    return after and after.amount or nil
end

--- Remove `amount` from a vessel; returns the amount actually removed.
function F.drain(item, amount)
    local v = F.vessel(item)
    if not v or v.amount <= 0 then return 0 end
    local want = math.min(amount, v.amount)
    local after = F.setAmount(item, v.kind, v.amount - want)
    if after == nil then return 0 end
    return math.max(0, v.amount - after)
end

--- May this EMPTY container be filled with `kind`? Water goes in anything
--  that accepts it except fuel cans; petrol only into things that look like a
--  fuel can (petrol can, jerry can, fuel drum...). Where the engine can say
--  whether it accepts the fluid (canAddFluid) that must agree too.
local FUEL_HINTS = { "petrol", "gasoline", "jerry", "fuel", "gas", "drum", "canister" }
function F.accepts(item, kind)
    local ft = string.lower(try(item, "getFullType") or "")
    local looksFuel = false
    for _, h in ipairs(FUEL_HINTS) do
        if string.find(ft, h, 1, true) then looksFuel = true break end
    end
    if kind == "gas" and not looksFuel then return false end
    if kind == "water" and (string.find(ft, "petrol", 1, true) or string.find(ft, "fuel", 1, true)) then return false end
    local fc = try(item, "getFluidContainer")
    local fluid = fluidObject(kind)
    if fc and fluid then
        local ok, can = pcall(fc.canAddFluid, fc, fluid)
        if ok and can == false then return false end
    end
    return true
end

--- Add `amount` of `kind` to a vessel; returns the amount actually added.
function F.fill(item, kind, amount, tainted)
    local v = F.vessel(item)
    if not v then return 0 end
    if v.kind ~= kind and v.kind ~= "empty" then return 0 end
    if v.kind == "empty" and not F.accepts(item, kind) then return 0 end
    -- clean and tainted water do not share a bottle
    if kind == "water" and v.kind == "water" and v.amount > 0 and (v.tainted == true) ~= (tainted == true) then return 0 end
    local want = math.min(amount, v.capacity - v.amount)
    if want <= 0 then return 0 end
    local after = F.setAmount(item, kind, v.amount + want, tainted)
    if after == nil then return 0 end
    return math.max(0, after - v.amount)
end

------------------------------------------------------------ world objects
-- Build 42 world objects (a rain barrel, a sink) keep water in a FluidContainer COMPONENT.
-- A tank or a piped fixture is given one, so the game's own fluid menu, drinking and washing see its water.

--- The FluidType enum value for a kind ("water" / "gas"), or nil.
function F.fluidType(kind, tainted)
    local name = (kind == "water") and (tainted and "TaintedWater" or "Water") or "Petrol"
    local ok, t = pcall(function() return FluidType[name] end)
    return ok and t or nil
end

--- The object's FluidContainer, made if missing and raised to `capacity`. Returns it and whether it was just made.
function F.ensureContainer(obj, capacity)
    local fc = try(obj, "getFluidContainer")
    local made = false
    if not fc then
        local ok, c = pcall(function() return ComponentType.FluidContainer:CreateComponent() end)
        if not (ok and c) then ok, c = pcall(function() return FluidContainer.CreateContainer() end) end
        if not (ok and c) then once("fcmake", "could not make a fluid container") return nil, false end
        if capacity then pcall(c.setCapacity, c, capacity) end
        if not pcall(GameEntityFactory.AddComponent, obj, true, c) then once("fcadd", "could not attach a fluid container") return nil, false end
        fc = try(obj, "getFluidContainer") or c
        made = true
        once("fcok", "fluid container attached to a world object")
    end
    local cap = try(fc, "getCapacity") or 0
    if capacity and math.abs(cap - capacity) > 0.01 then pcall(fc.setCapacity, fc, capacity) end
    return fc, made
end

--- Litres of `kind` in a world container, and how many of them are tainted.
function F.containerAmounts(fc, kind)
    local function amt(name)
        local ok, v = pcall(function() return fc:getSpecificFluidAmount(Fluid[name]) end)
        return ok and type(v) == "number" and v or 0
    end
    if kind == "water" then
        local tainted = amt("TaintedWater")
        return amt("Water") + tainted, tainted
    end
    return amt("Petrol"), 0
end

--- Send a world object's container to the clients (a server only; single player has nothing to send).
function F.syncObject(obj)
    if isServer and isServer() and obj and obj.sync then pcall(obj.sync, obj) end
end

