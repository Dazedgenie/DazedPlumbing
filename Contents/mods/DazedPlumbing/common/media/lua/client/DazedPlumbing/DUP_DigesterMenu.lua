--[[ Dazed Plumbing -- right-click menu for the biogas digester: waste, gas buffer and status, and "Add waste".
     The pipe rows come from DUP_LinkMenu. ]]

require "DazedPlumbing/DUP_Digesters"
require "DazedPlumbing/DUP_DigesterActions"

local Dg = DazedPlumb.Digesters

local function f1(v) return string.format("%.1f", v or 0) end
local function f2(v) return string.format("%.2f", v or 0) end

local function collect(inv, out)
    out = out or {}
    local items = inv and inv.getItems and inv:getItems()
    if not items then return out end
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it then
            local kind, units = Dg.classify(it)
            if kind then out[#out + 1] = { item = it, units = units } end
            if it.IsInventoryContainer and it:IsInventoryContainer() and it.getInventory then collect(it:getInventory(), out) end
        end
    end
    return out
end

local function approach(playerObj, obj)
    local sq = obj:getSquare()
    if not sq then return false end
    if luautils and luautils.walkAdj then return luautils.walkAdj(playerObj, sq) end
    return true
end

--- Queue the first `count` entries of `found` (the server re-checks each one).
local function queue(_, digester, playerObj, found, count)
    if not approach(playerObj, digester) then return end
    for i = 1, count do ISTimedActionQueue.add(DUP_DigesterAdd:new(playerObj, digester, found[i].item)) end
end

local function addDigesterMenu(playerNum, context, worldobjects, test)
    if test then return end
    local obj
    for _, o in ipairs(DazedPlumb.Parts.objectsAround(worldobjects)) do if Dg.isDigester(o) then obj = o break end end
    if not obj then return end
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end
    local st = Dg.state(obj)

    local top = context:addOption(getText("ContextMenu_DazedPlumb_Digester"), worldobjects, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(top, sub)

    -- the three lines: waste, gas buffer, status (also the tooltip of the top row)
    local status, factor = Dg.status(obj)
    local lines = {
        getText("IGUI_DazedPlumb_DigesterWaste", f1(st.waste), Dg.SLURRY_CAP),
        getText("IGUI_DazedPlumb_DigesterGas", f2(st.buf), f2(Dg.BUF_CAP)),
        getText("IGUI_DazedPlumb_DigesterStatus", getText("IGUI_DazedPlumb_Digester_" .. status)),
    }
    for _, line in ipairs(lines) do sub:addOption(line, nil, nil).notAvailable = true end
    if status == "ok" or status == "cold" then
        sub:addOption(getText("IGUI_DazedPlumb_DigesterOutput", f2(Dg.rate(st.waste, factor))), nil, nil).notAvailable = true
    end
    if Dg.line(obj).state == "unpiped" then
        sub:addOption(getText("IGUI_DazedPlumb_DigesterNotPiped"), nil, nil).notAvailable = true
    end
    local tip = ISWorldObjectContextMenu and ISWorldObjectContextMenu.addToolTip and ISWorldObjectContextMenu.addToolTip()
    if tip then
        tip.description = table.concat(lines, " <LINE> ")
        top.toolTip = tip
    end

    -- add waste: the carried items that fit
    local found = collect(playerObj:getInventory())
    local room, count, units = Dg.room(st.waste), 0, 0
    for _, e in ipairs(found) do
        if units + e.units > room + Dg.EPS then break end
        units, count = units + e.units, count + 1
    end
    if #found == 0 then
        sub:addOption(getText("ContextMenu_DazedPlumb_DigesterAddNone"), nil, nil).notAvailable = true
    elseif count == 0 then
        local opt = sub:addOption(getText("ContextMenu_DazedPlumb_DigesterAdd"), nil, nil)
        opt.notAvailable = true
        local t = ISWorldObjectContextMenu and ISWorldObjectContextMenu.addToolTip and ISWorldObjectContextMenu.addToolTip()
        if t then t.description = getText("IGUI_DazedPlumb_Digester_full") opt.toolTip = t end
    else
        local add = ISContextMenu:getNew(sub)
        sub:addSubMenu(sub:addOption(getText("ContextMenu_DazedPlumb_DigesterAdd"), nil, nil), add)
        add:addOption(getText("ContextMenu_DazedPlumb_DigesterAddAll", count, f1(units)), worldobjects, queue, obj, playerObj, found, count)
        for i = 1, math.min(#found, 8) do
            local e = found[i]
            if e.units <= room + Dg.EPS then
                local name = (e.item.getName and e.item:getName()) or "?"
                add:addOption(getText("ContextMenu_DazedPlumb_DigesterAddOne", name, f1(e.units)), worldobjects,
                    function(_, d, pl, entry) queue(nil, d, pl, { entry }, 1) end, obj, playerObj, e)
            end
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(addDigesterMenu)
