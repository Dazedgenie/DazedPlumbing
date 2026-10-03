--[[ Dazed Utilities: Plumbing -- right-click menu for a fuel pump: the petrol on its line, refuel a parked vehicle and fill a petrol can.
     The pipe rows come from DUP_LinkMenu; the on/off switch of the electric pump comes from DUP_PumpMenu. ]]

require "DazedPlumbing/DUP_FuelPumps"
require "DazedPlumbing/DUP_FuelActions"
require "DazedPlumbing/DUP_PumpActions"
require "DazedPlumbing/DUP_PumpMenu"
require "DazedPlumbing/DUP_Power"

local Fp, F, U = DazedPlumb.FuelPumps, DazedPlumb.Fluids, DazedPlumb.Pumps

local function f0(v) return string.format("%d", math.floor((v or 0) + 0.5)) end

local function collect(inv, pred, out)
    out = out or {}
    local items = inv and inv.getItems and inv:getItems()
    if not items then return out end
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it then
            if pred(it) then out[#out + 1] = it end
            if it.IsInventoryContainer and it:IsInventoryContainer() and it.getInventory then
                collect(it:getInventory(), pred, out)
            end
        end
    end
    return out
end

local function approach(playerObj, pump)
    local sq = pump:getSquare()
    if not sq then return false end
    if luautils and luautils.walkAdj then return luautils.walkAdj(playerObj, sq) end
    return true
end

local function tip(text)
    local t = ISWorldObjectContextMenu and ISWorldObjectContextMenu.addToolTip and ISWorldObjectContextMenu.addToolTip()
    if t then t.description = text end
    return t
end

local AMOUNTS = { 10, 25, 50 }

--- Queue `litres` as chunks of the pump's size; the queue stops early when the tanks run dry or the target is full.
local function queue(action, pump, playerObj, target, litres)
    if not approach(playerObj, pump) then return end
    local chunk = Fp.CHUNK[Fp.kindOf(pump)]
    local left = litres
    while left > Fp.EPS do
        local n = math.min(left, chunk)
        ISTimedActionQueue.add(action:new(playerObj, pump, target, n))
        left = left - n
    end
end

--- The amount submenu: fixed sizes below what is possible, then "until full". `run(litres)` queues the job.
local function amountMenu(sub, opt, worldobjects, can, kind, run)
    local amounts = ISContextMenu:getNew(sub)
    sub:addSubMenu(opt, amounts)
    for _, litres in ipairs(AMOUNTS) do
        if litres < can - 0.5 then
            amounts:addOption(getText("ContextMenu_DazedPlumb_FuelLitres", litres, Fp.chunksFor(kind, litres)), worldobjects,
                function(_, l) run(l) end, litres)
        end
    end
    amounts:addOption(getText("ContextMenu_DazedPlumb_FuelAll", f0(can), Fp.chunksFor(kind, can)), worldobjects,
        function(_, l) run(l) end, can)
end

local function addFuelMenu(playerNum, context, worldobjects, test)
    if test then return end
    local pump
    for _, o in ipairs(DazedPlumb.Parts.objectsAround(worldobjects)) do if Fp.isFuelPump(o) then pump = o break end end
    if not pump then return end
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end
    local kind = Fp.kindOf(pump)

    local top = context:addOption(getText("ContextMenu_DazedPlumb_FuelPump"), worldobjects, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(top, sub)

    -- the petrol on the line
    local line = Fp.line(pump)
    local head
    if line.state == "ok" then
        head = getText("IGUI_DazedPlumb_FuelOnLine", f0(line.litres), #line.tanks)
    elseif line.state == "paused" then
        head = getText("IGUI_DazedPlumb_LinkPaused")
    elseif line.state == "down" then
        head = getText("IGUI_DazedPlumb_LineDown")
    else
        head = getText("IGUI_DazedPlumb_FuelNoTank")
    end
    sub:addOption(head, nil, nil).notAvailable = true
    sub:addOption(getText("IGUI_DazedPlumb_FuelRate", f0(Fp.rate(kind))), nil, nil).notAvailable = true

    -- the electric pump: its wire and its switch
    local ready, why = Fp.ready(pump)
    if kind == "electric" then
        sub:addOption(Fp.wired(pump) and getText("IGUI_DazedPlumb_Powered") or getText("IGUI_DazedPlumb_FuelNoWire"), nil, nil).notAvailable = true
        U.addSwitchMenu(sub, worldobjects, pump, playerObj)
    end
    local blocked = (not ready) and getText(why == "off" and "IGUI_DazedPlumb_Fuel_off" or "IGUI_DazedPlumb_Fuel_nopower") or nil
    local hasFuel = line.state == "ok" and line.litres > Fp.EPS

    -- a parked vehicle in reach
    local anyCar = false
    for _, v in ipairs(Fp.vehiclesNear(pump)) do
        local t = Fp.tankOf(v)
        if t then
            anyCar = true
            local label = getText("ContextMenu_DazedPlumb_FuelRefuel") .. ": " .. Fp.vehicleName(v) .. " (" .. f0(t.amount) .. "/" .. f0(t.capacity) .. " L)"
            local opt = sub:addOption(label, nil, nil)
            local can = math.min(t.room, line.litres)
            if blocked then
                opt.notAvailable = true
                opt.toolTip = tip(blocked)
            elseif not Fp.parked(v) then
                opt.notAvailable = true
                opt.toolTip = tip(getText("IGUI_DazedPlumb_Fuel_running"))
            elseif t.room <= Fp.EPS then
                opt.notAvailable = true
                opt.toolTip = tip(getText("IGUI_DazedPlumb_Fuel_full"))
            elseif not hasFuel then
                opt.notAvailable = true
                opt.toolTip = tip(getText(line.state == "ok" and "IGUI_DazedPlumb_Fuel_empty" or "IGUI_DazedPlumb_Fuel_notank"))
            else
                amountMenu(sub, opt, worldobjects, can, kind, function(l) queue(DUP_FuelVehicle, pump, playerObj, v, l) end)
            end
        end
    end
    if not anyCar then sub:addOption(getText("ContextMenu_DazedPlumb_FuelNoVehicle"), nil, nil).notAvailable = true end

    -- a carried petrol can or other fuel container
    local cans = collect(playerObj:getInventory(), function(it) return Fp.canTake(it) end)
    for _, it in ipairs(cans) do
        local v = F.vessel(it)
        local name = (it.getName and it:getName()) or "?"
        local opt = sub:addOption(getText("ContextMenu_DazedPlumb_FuelFillCan") .. ": " .. name .. " (" .. f0(v.amount) .. "/" .. f0(v.capacity) .. " L)", nil, nil)
        if blocked then
            opt.notAvailable = true
            opt.toolTip = tip(blocked)
        elseif not hasFuel then
            opt.notAvailable = true
            opt.toolTip = tip(getText(line.state == "ok" and "IGUI_DazedPlumb_Fuel_empty" or "IGUI_DazedPlumb_Fuel_notank"))
        else
            amountMenu(sub, opt, worldobjects, math.min(v.capacity - v.amount, line.litres), kind, function(l) queue(DUP_FuelCan, pump, playerObj, it, l) end)
        end
    end
    if #cans == 0 then sub:addOption(getText("ContextMenu_DazedPlumb_FuelFillCanNone"), nil, nil).notAvailable = true end
end

Events.OnFillWorldObjectContextMenu.Add(addFuelMenu)
