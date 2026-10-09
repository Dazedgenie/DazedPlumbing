--[[ Dazed Plumbing -- right-click menu for the water purifier:
     its buffer, flow and filter, and fitting / removing a cartridge. The pipe
     rows come from DUP_LinkMenu. ]]

require "DazedPlumbing/DUP_Purifiers"
require "DazedPlumbing/DUP_PumpMenu"
require "DazedPlumbing/DUP_Power"
require "DazedPlumbing/DUP_PumpActions"

local Pu = DazedPlumb.Purifiers

local function f0(v) return string.format("%d", math.floor((v or 0) + 0.5)) end

local function approach(playerObj, obj)
    local sq = obj:getSquare()
    if not sq then return false end
    if luautils and luautils.walkAdj then return luautils.walkAdj(playerObj, sq) end
    return true
end

local function filtersIn(inv, out)
    out = out or {}
    local items = inv and inv.getItems and inv:getItems()
    if not items then return out end
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it then
            if it:getFullType() == Pu.FILTER_ITEM then out[#out + 1] = it end
            if it.IsInventoryContainer and it:IsInventoryContainer() and it.getInventory then filtersIn(it:getInventory(), out) end
        end
    end
    return out
end

local function addPurifierMenu(playerNum, context, worldobjects, test)
    if test then return end
    local obj
    for _, o in ipairs(DazedPlumb.Parts.objectsAround(worldobjects)) do if Pu.isPurifier(o) then obj = o break end end
    if not obj then return end
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end
    local st = Pu.state(obj)

    local top = context:addOption(getText("ContextMenu_DazedPlumb_Purifier"), worldobjects, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(top, sub)

    sub:addOption(getText("IGUI_DazedPlumb_Buffer") .. ": " .. f0(st.buf) .. " / " .. Pu.BUF_CAP .. " L", nil, nil).notAvailable = true
    local filt = (st.filter or 0) > 0
    sub:addOption(getText("IGUI_DazedPlumb_Filter") .. ": " .. (filt and (f0(st.filter) .. "%") or getText("IGUI_DazedPlumb_NoFilter")),
        nil, nil).notAvailable = true
    sub:addOption(Pu.powered(obj) and getText("IGUI_DazedPlumb_Powered") or getText("IGUI_DazedPlumb_NoPower"), nil, nil).notAvailable = true
    DazedPlumb.Pumps.addSwitchMenu(sub, worldobjects, obj, playerObj)
    local full = Pu.fullRate(obj)
    DazedPlumb.Pumps.addFlowMenu(sub, worldobjects, obj, playerObj, function(f) return full * f end, Pu.working(obj))

    if filt then
        sub:addOption(getText("ContextMenu_DazedPlumb_FilterRemove"), worldobjects,
            function(_, o, pl) if approach(pl, o) then ISTimedActionQueue.add(DUP_FilterRemove:new(pl, o)) end end, obj, playerObj)
    else
        local found = filtersIn(playerObj:getInventory())
        if #found == 0 then
            sub:addOption(getText("ContextMenu_DazedPlumb_FilterNone"), nil, nil).notAvailable = true
        end
        for _, it in ipairs(found) do
            sub:addOption(getText("ContextMenu_DazedPlumb_FilterInstall") .. " (" .. f0(it:getCondition()) .. "%)", worldobjects,
                function(_, o, pl, item) if approach(pl, o) then ISTimedActionQueue.add(DUP_FilterInstall:new(pl, o, item)) end end,
                obj, playerObj, it)
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(addPurifierMenu)
