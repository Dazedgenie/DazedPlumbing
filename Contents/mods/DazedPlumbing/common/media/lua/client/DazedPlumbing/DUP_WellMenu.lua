--[[ Dazed Plumbing -- right-click menu for the drilled well: power, status, output and the on/off switch.
     The pipe rows ("Well line -> Pipe to: <tank>") come from DUP_LinkMenu. ]]

require "DazedPlumbing/DUP_DrilledWells"
require "DazedPlumbing/DUP_PumpActions"
require "DazedPlumbing/DUP_PumpMenu"

local Dw, U = DazedPlumb.DrilledWells, DazedPlumb.Pumps

local function addWellMenu(playerNum, context, worldobjects, test)
    if test then return end
    local obj
    for _, o in ipairs(DazedPlumb.Parts.objectsAround(worldobjects)) do if Dw.isWell(o) then obj = o break end end
    if not obj then return end
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end

    local top = context:addOption(getText("ContextMenu_DazedPlumb_Well"), worldobjects, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(top, sub)

    -- power, status and output (also the top row's tooltip)
    local status = Dw.status(obj)
    local lines = {
        getText(DazedPlumb.wiredPower(obj) and "IGUI_DazedPlumb_WellWired" or "IGUI_DazedPlumb_WellNotWired"),
        getText("IGUI_DazedPlumb_WellStatus", getText("IGUI_DazedPlumb_Well_" .. status)),
        getText("IGUI_DazedPlumb_WellOutput", Dw.RATE, Dw.WATTS),
    }
    for _, line in ipairs(lines) do sub:addOption(line, nil, nil).notAvailable = true end
    local tip = ISWorldObjectContextMenu and ISWorldObjectContextMenu.addToolTip and ISWorldObjectContextMenu.addToolTip()
    if tip then
        tip.description = table.concat(lines, " <LINE> ")
        top.toolTip = tip
    end
    if U.addSwitchMenu then U.addSwitchMenu(sub, worldobjects, obj, playerObj) end
end

Events.OnFillWorldObjectContextMenu.Add(addWellMenu)
