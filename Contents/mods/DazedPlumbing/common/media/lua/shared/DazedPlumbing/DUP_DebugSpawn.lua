--[[ Dazed Plumbing -- every Dazed Plumbing item for Dazed Core's debug spawn ("Dazed debug" in the right-click
     menu, debug mode or staff only): every tank, then the pumps, purifier, downspout, sprinkler, water main,
     fuel pumps, digester, drilled well and smoker, then the pipe, valve and filter cartridge. The same list
     DUP_Boot checks; a module that is not loaded is skipped. ]]

require "DazedCore/DC_Boot"
require "DazedCore/DC_DebugSpawn"     -- by name, so it is there whichever mod's shared files load first
require "DazedPlumbing/DUP_Parts"

local S = DazedCore.DebugSpawn
if not (S and S.register) then return end      -- a Dazed Core older than 1.5.0

S.register("plumbing", "Dazed Plumbing", function()
    local D = DazedPlumb
    local out = {}
    local function one(mod, field) if mod and mod[field] then out[#out + 1] = mod[field] end end
    local function all(mod)
        if mod and mod.allItems then for _, it in ipairs(mod.allItems()) do out[#out + 1] = it end end
    end
    all(D.Parts)
    all(D.Pumps)
    all(D.Purifiers)
    one(D.Downspouts, "ITEM"); one(D.Sprinklers, "ITEM"); one(D.Mains, "ITEM")
    all(D.FuelPumps)
    all(D.Digesters)
    all(D.DrilledWells)
    all(D.Smokers)
    one(D.Pipes, "ITEM"); one(D.Pipes, "VALVE_ITEM")
    return out
end)
