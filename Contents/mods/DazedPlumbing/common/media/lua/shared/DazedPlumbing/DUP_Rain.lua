--[[ Dazed Utilities: Plumbing -- vanilla rain collector barrels as water sources.

     A rain barrel the game already collects rain in can be piped to a water tank: the tank
     draws the barrel down (up to 20 L a minute) through the same pipes a pump uses. The water
     is tainted if the barrel says it is.

     Not proven in game: how a barrel holds its water. A FluidContainer (Build 42) and the older
     water amount are both tried, and the console says once which one took.
]]

require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Links"
require "DazedPlumbing/DUP_Fluids"

DazedPlumb.Rain = DazedPlumb.Rain or {}
local R = DazedPlumb.Rain
local P, L, F = DazedPlumb.Parts, DazedPlumb.Links, DazedPlumb.Fluids
local try = P.try

R.ID = "dazed_rainbarrel"

local once = P.once

--- Is this a vanilla rain collector barrel? Looks at the tile's own name.
function R.isBarrel(obj)
    if not obj or P.describe(obj) then return false end
    local text = ""
    for _, key in ipairs({ "CustomName", "GroupName" }) do
        local v = P.prop(obj, key)
        if type(v) == "string" then text = text .. " " .. string.lower(v) end
    end
    local spr = try(obj, "getSpriteName")
    if type(spr) == "string" then text = text .. " " .. string.lower(spr) end
    if not string.find(text, "rain", 1, true) then return false end
    if not (string.find(text, "barrel", 1, true) or string.find(text, "collect", 1, true)) then return false end
    return try(obj, "getFluidAmount") ~= nil or try(obj, "getFluidContainer") ~= nil or try(obj, "getWaterAmount") ~= nil
end

--- Litres in the barrel now.
function R.amount(obj)
    local direct = try(obj, "getFluidAmount")                       -- Build 42 objects answer this themselves
    if type(direct) == "number" then return direct end
    local fc = try(obj, "getFluidContainer")
    local a = fc and try(fc, "getAmount")
    if type(a) == "number" then return a end
    local w = try(obj, "getWaterAmount")
    return type(w) == "number" and w or 0
end

--- Is the barrel's water tainted?
function R.tainted(obj)
    local t = try(obj, "isTaintedWater")
    if t ~= nil then return t == true end
    local fc = try(obj, "getFluidContainer")
    if fc then return F.isTaintedFluid(fc) end
    return false
end

--- Draw up to `amount` litres; returns what came out (read back from the barrel).
function R.take(obj, amount)
    local have = R.amount(obj)
    local want = math.min(math.max(0, amount or 0), have)
    if want <= 0.001 then return 0 end
    if obj.useFluid then                                            -- the call vanilla's own barrel actions use
        pcall(obj.useFluid, obj, want)
        local after = R.amount(obj)
        once("rainuse", "rain barrel: useFluid " .. (after < have - 1e-6 and "worked" or "did NOT lower it"))
        if after < have - 1e-6 then
            if obj.transmitModData then pcall(obj.transmitModData, obj) end
            return have - after
        end
    end
    local fc = try(obj, "getFluidContainer")
    if fc then
        pcall(fc.adjustAmount, fc, have - want)
        local after = R.amount(obj)
        once("rainfc", "rain barrel: adjustAmount " .. (after < have - 1e-6 and "worked" or "did NOT lower it"))
        if after < have - 1e-6 then
            if obj.sendObjectChange then pcall(obj.sendObjectChange, obj, "containers") end
            return have - after
        end
    end
    if obj.setWaterAmount then
        pcall(obj.setWaterAmount, obj, have - want)
        local after = try(obj, "getWaterAmount") or have
        once("rainlegacy", "rain barrel: setWaterAmount " .. (after < have - 1e-6 and "worked" or "did NOT lower it"))
        if obj.transmitModData then pcall(obj.transmitModData, obj) end
        return math.max(0, have - after)
    end
    return 0
end

L.register({
    id = R.ID, produces = "water", tainted = R.tainted, label = "ContextMenu_DazedPlumb_RainLine",
    match = R.isBarrel,
    available = function(o) return math.min(L.RATE.water, R.amount(o)) end,
    take = R.take,
})

return R
