--[[ Dazed Utilities: Plumbing -- right-click menu for the smoker: gas on the line, lit state, what is smoking and Light / Extinguish.
     The pipe rows come from DUP_LinkMenu; meat goes in and out through the smoker's own container in the loot window. ]]

require "DazedPlumbing/DUP_Smokers"
require "DazedPlumbing/DUP_SmokerActions"

local Sm = DazedPlumb.Smokers

local function f1(v) return string.format("%.1f", v or 0) end
local function f2(v) return string.format("%.2f", v or 0) end

local function approach(playerObj, obj)
    local sq = obj:getSquare()
    if not sq then return false end
    if luautils and luautils.walkAdj then return luautils.walkAdj(playerObj, sq) end
    return true
end

local function addSmokerMenu(playerNum, context, worldobjects, test)
    if test then return end
    local obj
    for _, o in ipairs(DazedPlumb.Parts.objectsAround(worldobjects)) do if Sm.isSmoker(o) then obj = o break end end
    if not obj then return end
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end

    local top = context:addOption(getText("ContextMenu_DazedPlumb_Smoker"), worldobjects, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(top, sub)

    -- gas, status and what is smoking (also the top row's tooltip)
    local line = Sm.line(obj)
    local count, left = Sm.progressNow(obj)
    local lines = {
        line.state == "unpiped" and getText("IGUI_DazedPlumb_SmokerNotPiped") or getText("IGUI_DazedPlumb_SmokerGas", f2(line.kg)),
        getText("IGUI_DazedPlumb_SmokerStatus", getText("IGUI_DazedPlumb_Smoker_" .. Sm.status(obj))),
        count > 0 and getText("IGUI_DazedPlumb_SmokerItems", count, f1(left)) or getText("IGUI_DazedPlumb_SmokerEmpty"),
    }
    for _, l in ipairs(lines) do sub:addOption(l, nil, nil).notAvailable = true end
    local tip = ISWorldObjectContextMenu and ISWorldObjectContextMenu.addToolTip and ISWorldObjectContextMenu.addToolTip()
    if tip then
        tip.description = table.concat(lines, " <LINE> ")
        top.toolTip = tip
    end

    local lit = Sm.isLit(obj)
    local opt = sub:addOption(getText(lit and "ContextMenu_DazedPlumb_SmokerExtinguish" or "ContextMenu_DazedPlumb_SmokerLight"), worldobjects,
        function(_, o, pl, on) if approach(pl, o) then ISTimedActionQueue.add(DUP_SmokerLight:new(pl, o, on)) end end,
        obj, playerObj, not lit)
    if not lit and line.kg <= Sm.EPS then
        opt.notAvailable = true
        local t = ISWorldObjectContextMenu and ISWorldObjectContextMenu.addToolTip and ISWorldObjectContextMenu.addToolTip()
        if t then t.description = getText("IGUI_DazedPlumb_Smoker_nogas") opt.toolTip = t end
    end
end

Events.OnFillWorldObjectContextMenu.Add(addSmokerMenu)
