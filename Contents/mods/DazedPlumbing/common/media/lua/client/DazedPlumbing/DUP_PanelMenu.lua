--[[ Dazed Plumbing -- right-click menu for a wall water panel, and its page in the Dazed guide.
     Bound, it offers Water panel (the main's board, worked through this panel); unbound, it says no main serves the house. ]]

require "DazedPlumbing/DUP_WallPanels"
require "DazedPlumbing/DUP_Board"

local Wp, W = DazedPlumb.WallPanels, DazedPlumb.Mains

local function tip(text)
    local t = ISWorldObjectContextMenu and ISWorldObjectContextMenu.addToolTip and ISWorldObjectContextMenu.addToolTip()
    if t then t.description = text end
    return t
end

--- Walk up to the panel, then open the main's board by its key (it need not be loaded here).
local function onOpen(_, panel, pl, key)
    local sq = panel:getSquare()
    if not sq then return end
    if luautils and luautils.walkAdj then luautils.walkAdj(pl, sq) end
    DUP_Board.open(pl, W.mainAt(key) or key, { via = { x = sq:getX(), y = sq:getY(), z = sq:getZ() } })
end

local function addPanelMenu(playerNum, context, worldobjects, test)
    if test then return end
    local panel
    for _, o in ipairs(DazedPlumb.Parts.objectsAround(worldobjects)) do if Wp.isPanel(o) then panel = o break end end
    if not panel then return end
    local pl = getSpecificPlayer(playerNum)
    if not pl then return end
    local key = Wp.boundTo(panel)
    if key and W.store().mains[key] then
        context:addOption(getText("ContextMenu_DazedPlumb_WaterPanel"), worldobjects, onOpen, panel, pl, key)
    else
        local opt = context:addOption(getText("ContextMenu_DazedPlumb_WaterPanel"), nil, nil)
        opt.notAvailable = true
        opt.toolTip = tip(getText("IGUI_DazedPlumb_PanelUnbound"))
        context:addOption(getText("IGUI_DazedPlumb_PanelUnbound"), nil, nil).notAvailable = true
    end
end

Events.OnFillWorldObjectContextMenu.Add(addPanelMenu)

-- The guide's Plumbing book lives in the core; the panel's page is added to it here (texts in this mod's IG_UI).
local ok = pcall(require, "DazedCore/DC_Guide")
local G = ok and DazedCore and DazedCore.Guide
if G and G.books then
    for _, b in ipairs(G.books) do
        if b.id == "plumbing" and type(b.pages) == "table" then
            local have = false
            for _, p in ipairs(b.pages) do if p == "PlumbPanel" then have = true end end
            if not have then
                local at = #b.pages + 1
                for i, p in ipairs(b.pages) do if p == "PlumbMain" then at = i + 1 end end
                table.insert(b.pages, at, "PlumbPanel")
            end
        end
    end
end
