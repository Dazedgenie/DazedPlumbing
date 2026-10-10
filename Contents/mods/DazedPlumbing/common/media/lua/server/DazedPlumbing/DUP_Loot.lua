--[[ Dazed Plumbing -- where worn tanks turn up.

     The SALVAGED tanks (never the crafted ones) are added to procedural loot
     lists for garages, metalwork, farms and fuel storage, lightly: small
     ones now and then, large ones rarely, the extra-large almost never (it
     weighs as much as a person).

     Each list is looked up by name and skipped if this game version has no
     such list, and the result is printed once so a renamed list is a
     one-line report.
]]

require "Items/ProceduralDistributions"
require "DazedPlumbing/DUP_Parts"

DazedPlumb = DazedPlumb or {}
local H = DazedPlumb
local P = DazedPlumb.Parts

-- { list name, size weights = { small, large, xl }, types }
H.LOOT = {
    { "GarageMetalwork",       { 0.6, 0.25, 0.05 }, { "propane", "gas", "water" } },
    { "GarageTools",           { 0.4, 0.15, 0.00 }, { "propane", "gas", "water" } },
    { "GasStorageMechanics",   { 0.8, 0.40, 0.08 }, { "gas", "propane" } },
    { "CrateMechanics",        { 0.4, 0.15, 0.00 }, { "gas", "propane" } },
    { "ToolStoreMetalwork",    { 0.6, 0.25, 0.05 }, { "propane", "gas", "water" } },
    { "FarmingTools",          { 0.5, 0.25, 0.05 }, { "water", "gas" } },
    { "CrateFarming",          { 0.4, 0.20, 0.00 }, { "water", "gas" } },
    { "BarnTools",             { 0.5, 0.25, 0.05 }, { "water", "gas" } },
    { "CampingStoreGear",      { 0.5, 0.10, 0.00 }, { "propane", "water" } },
}

-- { list name, weight } for a found water main: plumbing and hardware stock, lightly.
H.MAIN_LOOT = {
    { "ToolStoreMetalwork", 0.3 }, { "GarageMetalwork", 0.15 }, { "CrateMetalwork", 0.2 },
    { "PlumbingSupplies", 0.5 }, { "StoreShelfMechanics", 0.1 },
}

function H.addMainLoot()
    if H.mainLootDone then return end
    H.mainLootDone = true
    local lists = ProceduralDistributions and ProceduralDistributions.list
    if not lists then return end
    local added, skipped = {}, {}
    for _, row in ipairs(H.MAIN_LOOT) do
        local list = lists[row[1]]
        if list and type(list.items) == "table" then
            table.insert(list.items, "Base.DazedWaterMain")
            table.insert(list.items, row[2])
            added[#added + 1] = row[1]
        else
            skipped[#skipped + 1] = row[1]
        end
    end
    print(string.format("DazedPlumbing: water main loot in %d lists (%s)%s", #added, table.concat(added, ", "),
        #skipped > 0 and ("; no such list: " .. table.concat(skipped, ", ")) or ""))
end

function H.addTankLoot()
    if H.tankLootDone then return end
    H.tankLootDone = true
    local lists = ProceduralDistributions and ProceduralDistributions.list
    if not lists then return end
    local added, skipped = {}, {}
    for _, row in ipairs(H.LOOT) do
        local name, weights, types = row[1], row[2], row[3]
        local list = lists[name]
        if list and type(list.items) == "table" then
            for si, size in ipairs({ "small", "large", "xl" }) do
                local w = weights[si]
                if w and w > 0 then
                    for _, typ in ipairs(types) do
                        table.insert(list.items, P.itemFor(size, typ, "salvaged"))
                        table.insert(list.items, w)
                    end
                end
            end
            added[#added + 1] = name
        else
            skipped[#skipped + 1] = name
        end
    end
    print(string.format("DazedPlumbing: tank loot in %d lists (%s)%s", #added, table.concat(added, ", "),
        #skipped > 0 and ("; no such list: " .. table.concat(skipped, ", ")) or ""))
end

if Events and Events.OnPreDistributionMerge then
    Events.OnPreDistributionMerge.Add(H.addTankLoot)
    Events.OnPreDistributionMerge.Add(H.addMainLoot)
else
    H.addTankLoot()
    H.addMainLoot()
end
