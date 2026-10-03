--[[ Dazed Utilities: Plumbing -- a water or petrol tank wears a FluidContainer that mirrors what it holds,
     so the game's own Fluid menu (info, transfer, empty), drinking and washing all work on it.
     The tank's ModData stays the record: on the authority, what the game took or added since the last look is
     applied to it, then the container is rewritten to match. ]]

require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Model"
require "DazedPlumbing/DUP_Fluids"

DazedPlumb.TankFluid = DazedPlumb.TankFluid or {}
local T = DazedPlumb.TankFluid
local P, M, F = DazedPlumb.Parts, DazedPlumb.Model, DazedPlumb.Fluids

T.KINDS = { water = true, gas = true }          -- propane is not a fluid the game knows
local EPS = 0.001

--- Apply what the game did to the container since we last wrote it.
local function adopt(d, fc)
    local amt, tainted = F.containerAmounts(fc, d.type)
    local delta = amt - (d.fcAmt or amt)
    if math.abs(delta) <= EPS then return false end
    if delta < 0 then
        M.take(d, -delta)
    elseif d.type == "water" then
        local dirtyIn = math.max(0, math.min(delta, tainted - (d.fcDirty or 0)))
        M.addWater(d, delta - dirtyIn, false)
        M.addWater(d, dirtyIn, true)
    else
        d.amount = M.clamp((d.amount or 0) + delta, 0, M.capacity(d.size, d.tier, d.type))
    end
    return true
end

--- Rewrite the container from the record, all clean or all tainted (the game mixes the two into tainted anyway).
local function publish(obj, d, fc)
    local amt, tainted = F.containerAmounts(fc, d.type)
    local bad = M.isTainted(d)
    local wantTainted = bad and (d.amount or 0) or 0
    local other = (P.try(fc, "getAmount") or 0) - amt                 -- anything poured in that a tank does not hold
    if math.abs(amt - (d.amount or 0)) > EPS or math.abs(tainted - wantTainted) > EPS or other > EPS then
        pcall(fc.Empty, fc)
        local ft = F.fluidType(d.type, bad)
        if ft and (d.amount or 0) > EPS then pcall(fc.addFluid, fc, ft, d.amount) end
        F.syncObject(obj)
        amt, tainted = F.containerAmounts(fc, d.type)
    end
    d.fcAmt, d.fcDirty = amt, tainted
end

--- Bring a tank and its container into step (authority only). Returns true when the tank's contents changed.
function T.reconcile(obj)
    if not (DazedPlumb.Sync and DazedPlumb.Sync.authority()) then return false end
    local master = P.master(obj)
    local d = P.data(master)
    if not T.KINDS[d.type] then return false end
    local fc, made = F.ensureContainer(master, M.capacity(d.size, d.tier, d.type))
    if not fc then return false end
    if made then d.fcAmt, d.fcDirty = nil, nil end                 -- a new container is empty, not emptied by a player
    local changed = adopt(d, fc)
    if changed then M.normalize(d) end
    publish(master, d, fc)
    if changed and master.transmitModData then master:transmitModData() end
    return changed
end

return T
