--[[ Dazed Utilities: Plumbing -- right-click menu for a garden sprinkler: the crops
     in reach, whether it is on, and the switch. The pipe rows come from DUP_LinkMenu. ]]

require "DazedPlumbing/DUP_Sprinklers"
require "DazedPlumbing/DUP_PumpActions"

local Z = DazedPlumb.Sprinklers

local function approach(playerObj, obj)
    local sq = obj:getSquare()
    if not sq then return false end
    if luautils and luautils.walkAdj then return luautils.walkAdj(playerObj, sq) end
    return true
end

local function addSprinklerMenu(playerNum, context, worldobjects, test)
    if test then return end
    local obj
    for _, o in ipairs(DazedPlumb.Parts.objectsAround(worldobjects)) do if Z.isSprinkler(o) then obj = o break end end
    if not obj then return end
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end

    local top = context:addOption(getText("ContextMenu_DazedPlumb_Sprinkler"), worldobjects, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(top, sub)

    local crops, thirsty = Z.survey(obj)
    sub:addOption(getText("IGUI_DazedPlumb_SprinklerCrops", crops, thirsty, Z.RADIUS), nil, nil).notAvailable = true
    local on = Z.isOn(obj)
    local state = not on and "IGUI_DazedPlumb_SprinklerOff"
        or (Z.describe(obj).spraying and "IGUI_DazedPlumb_SprinklerSpraying" or "IGUI_DazedPlumb_SprinklerWaiting")
    sub:addOption(getText(state), nil, nil).notAvailable = true
    sub:addOption(getText(on and "ContextMenu_DazedPlumb_SprinklerTurnOff" or "ContextMenu_DazedPlumb_SprinklerTurnOn"),
        worldobjects, function(_, o, pl, want)
            if approach(pl, o) then ISTimedActionQueue.add(DUP_SprinklerToggle:new(pl, o, want)) end
        end, obj, playerObj, not on)
end

Events.OnFillWorldObjectContextMenu.Add(addSprinklerMenu)
