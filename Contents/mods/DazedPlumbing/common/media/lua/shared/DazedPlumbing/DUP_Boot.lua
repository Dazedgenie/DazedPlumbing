--[[ Dazed Utilities: Plumbing -- start-up check.

     One console line so a player or a bug report can tell at a glance that
     everything arrived: DazedPlumbing: ready -- 72/72 tiles, 18/18 items
]]

require "DazedCore/DC_Boot"
require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Sync"
require "DazedPlumbing/DUP_Net"
require "DazedPlumbing/DUP_Pipes"
require "DazedPlumbing/DUP_Links"
require "DazedPlumbing/DUP_Fixtures"
require "DazedPlumbing/DUP_Pumps"
require "DazedPlumbing/DUP_Rain"
require "DazedPlumbing/DUP_Downspouts"
require "DazedPlumbing/DUP_Sprinklers"
require "DazedPlumbing/DUP_Purifiers"
require "DazedPlumbing/DUP_Power"
require "DazedPlumbing/DUP_Mains"
require "DazedPlumbing/DUP_FuelPumps"
require "DazedPlumbing/DUP_Digesters"

local P = DazedPlumb.Parts
DazedPlumb.VERSION = "0.13.0"
DazedCore.Boot.register("DazedPlumbing", DazedPlumb.VERSION)

local function check()
    local sm = getScriptManager and getScriptManager()
    -- every block of sprites the mod draws, as { first index, how many } (the sheet has gaps)
    local D = DazedPlumb
    local blocks = { { 0, P.TILE_COUNT }, { D.Pipes.BASE, D.Pipes.COUNT }, { D.Pumps.BASE, D.Pumps.COUNT },
        { D.Purifiers.BASE, D.Purifiers.COUNT }, { D.Downspouts.BASE, D.Downspouts.COUNT },
        { D.Pipes.VALVE_BASE, D.Pipes.VALVE_COUNT }, { D.Sprinklers.BASE, D.Sprinklers.COUNT }, { D.Pumps.STROKE_BASE, 4 }, { D.Pipes.PORT_BASE, D.Pipes.PORT_COUNT },
        { D.Mains.BASE, D.Mains.COUNT }, { D.FuelPumps.BASE, D.FuelPumps.COUNT },
        { D.Digesters.BASE, D.Digesters.COUNT } }
    local sprites, total = 0, 0
    for _, b in ipairs(blocks) do
        for n = b[1], b[1] + b[2] - 1 do
            total = total + 1
            if getSprite then
                local ok, spr = pcall(getSprite, P.TILESET .. "_" .. n)
                if ok and spr then sprites = sprites + 1 end
            else
                sprites = sprites + 1             -- not asked: nothing to count
            end
        end
    end
    local want, items, missing = P.allItems(), 0, nil
    for _, it in ipairs(DazedPlumb.Pumps.allItems()) do want[#want + 1] = it end
    for _, it in ipairs(DazedPlumb.Purifiers.allItems()) do want[#want + 1] = it end
    want[#want + 1] = DazedPlumb.Downspouts.ITEM
    want[#want + 1] = DazedPlumb.Sprinklers.ITEM
    want[#want + 1] = DazedPlumb.Pipes.ITEM
    want[#want + 1] = DazedPlumb.Pipes.VALVE_ITEM
    want[#want + 1] = DazedPlumb.Mains.ITEM
    for _, it in ipairs(DazedPlumb.FuelPumps.allItems()) do want[#want + 1] = it end
    for _, it in ipairs(DazedPlumb.Digesters.allItems()) do want[#want + 1] = it end
    for i = 1, #want do
        if sm and sm:getItem(want[i]) then items = items + 1
        elseif not missing then missing = want[i] end
    end
    if not sm then items = #want end
    local ok = sprites == total and items == #want
    print(string.format("DazedPlumbing: %s -- %d/%d tiles, %d/%d items%s",
        ok and "ready" or "INCOMPLETE", sprites, total, items, #want,
        missing and (" (first missing item: " .. missing .. ")") or ""))
end

--- Did the engine assemble the multi-tile tanks' sprite grids? One line, so a
--  bug report shows it: "grids: large 2x1, xl 3x1" (or "none" when it did not).
local function gridCheck()
    if not getSprite then return end
    local parts = {}
    for _, size in ipairs({ "large", "xl" }) do
        local ok, spr = pcall(getSprite, P.sprite(size, "water", "crafted", "S", 1))
        local grid = ok and spr and P.try(spr, "getSpriteGrid")
        local w = grid and P.try(grid, "getWidth")
        local h = grid and P.try(grid, "getHeight")
        parts[#parts + 1] = size .. " " .. ((w and h) and (w .. "x" .. h) or "NO GRID")
    end
    print("DazedPlumbing: sprite grids: " .. table.concat(parts, ", "))
end

Events.OnGameStart.Add(check)
Events.OnGameStart.Add(gridCheck)
