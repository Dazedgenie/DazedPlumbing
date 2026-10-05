--[[ Dazed Utilities: Plumbing -- the right-click menu for a tank.

     One entry, "Tank", with a submenu: a status line (what it holds, its
     condition, a leak warning), then pour-in rows (one per carried container
     that holds what the tank holds), take-out rows (one per carried container
     that can take it) and a patch row.

     Built in OnFillWorldObjectContextMenu; the actions are in DUP_Actions.
]]

require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Fluids"
require "DazedPlumbing/DUP_Gauge"
require "DazedPlumbing/DUP_Actions"
require "DazedPlumbing/DUP_TankFluid"

local P, M, F = DazedPlumb.Parts, DazedPlumb.Model, DazedPlumb.Fluids

---------------------------------------------------------------- helpers

--- Every item in a container and the bags inside it that `pred` takes.
local function collectRecurse(inv, pred, out)
    out = out or {}
    local items = inv and inv.getItems and inv:getItems()
    if not items then return out end
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it then
            if pred(it) then out[#out + 1] = it end
            if it.IsInventoryContainer and it:IsInventoryContainer() and it.getInventory then
                collectRecurse(it:getInventory(), pred, out)
            end
        end
    end
    return out
end

local function f1(v) return string.format("%.1f", v or 0) end

local function tankIn(worldobjects)
    for _, o in ipairs(DazedPlumb.Parts.objectsAround(worldobjects)) do
        if P.isTank(o) then return P.master(o) end
    end
    return nil
end

local function approach(playerObj, tank)
    local sq = tank:getSquare()
    if not sq then return false end
    if luautils and luautils.walkAdj then return luautils.walkAdj(playerObj, sq) end
    return true
end

local function tip(text)
    local t = ISWorldObjectContextMenu and ISWorldObjectContextMenu.addToolTip and ISWorldObjectContextMenu.addToolTip()
    if t then t.description = text end
    return t
end

local function statusLine(d)
    local unit = M.UNIT[d.type]
    local cap = M.capacity(d.size, d.tier, d.type)
    local line = string.format("%s: %s / %s %s (%d%%)  %s %d%%",
        getText(P.typeKey(d.type)), f1(d.amount), f1(cap), unit,
        math.floor(M.fullness(d) * 100 + 0.5), getText("IGUI_DazedPlumb_Condition"),
        math.floor(d.condition + 0.5))
    if M.isLeaking(d) then line = line .. "  " .. getText("IGUI_DazedPlumb_Leaking") end
    if d.catching then line = line .. "  " .. getText("IGUI_DazedPlumb_Catching") end
    if d.type == "water" and (d.amount or 0) > 0 then
        line = line .. "  [" .. getText(M.isTainted(d) and "IGUI_DazedPlumb_Tainted" or "IGUI_DazedPlumb_Clean") .. "]"
    end
    return line
end

local function vesselLabel(item, v, kind)
    -- getName() is the name the inventory shows ("Empty Jerry Can"); the
    -- display name of an empty fluid container can read like its full form.
    local name = (item.getName and item:getName()) or item:getDisplayName() or "?"
    local q = (v.kind == "water" and v.amount > 0.001) and (" " .. getText(v.tainted and "IGUI_DazedPlumb_Tainted" or "IGUI_DazedPlumb_Clean")) or ""
    return string.format("%s (%s %s%s)", name, f1(v.amount), M.UNIT[v.kind] or M.UNIT[kind] or "", q)
end

---------------------------------------------------------------- handlers

local function onFill(worldobjects, tank, playerObj, item, units)
    if not approach(playerObj, tank) then return end
    ISTimedActionQueue.add(DUP_TankFill:new(playerObj, tank, item, units))
end
local function onTake(worldobjects, tank, playerObj, item, units)
    if not approach(playerObj, tank) then return end
    ISTimedActionQueue.add(DUP_TankTake:new(playerObj, tank, item, units))
end
local function onRepair(worldobjects, tank, playerObj, sheet, screws)
    if not (sheet and screws) then return end
    if not approach(playerObj, tank) then return end
    ISTimedActionQueue.add(DUP_TankRepair:new(playerObj, tank, sheet, screws))
end

--- Ask for a name, then set it beside the tank.
local function onRename(_, tank, playerObj, current)
    local box = ISTextBox:new(0, 0, 280, 180, getText("ContextMenu_DazedPlumb_RenamePrompt"), current or "", nil,
        function(_, button)
            if button.internal ~= "OK" then return end
            local name = button.parent.entry:getText()
            if approach(playerObj, tank) then ISTimedActionQueue.add(DUP_TankRename:new(playerObj, tank, name)) end
        end, playerObj:getPlayerNum())
    box:initialise()
    box:addToUIManager()
end

--- The game's Info / Transfer / Empty rows for the tank's container, when the game did not add them itself.
local function addFluidMenu(context, tank, playerNum)
    local fc = tank.getFluidContainer and tank:getFluidContainer()
    if not fc then return end
    local fetch = ISWorldObjectContextMenu.fetchVars
    for _, o in ipairs(fetch and fetch.fluidcontainer or {}) do
        if o == tank or o == fc or (o.getGameEntity and o:getGameEntity() == tank) then return end
    end
    local opt = context:addOption(getText("ContextMenu_Fluid"), nil, nil)
    opt.iconTexture = getTexture("Item_WaterDrop")
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(opt, sub)
    sub:addOption(getText("Fluid_Show_Info"), playerNum, ISWorldObjectContextMenu.onFluidInfo, fc)
    sub:addOption(getText("Fluid_Transfer_Fluids"), playerNum, ISWorldObjectContextMenu.onFluidTransfer, fc)
    if fc.isEmpty and not fc:isEmpty() and (not fc.canPlayerEmpty or fc:canPlayerEmpty()) then
        sub:addOption(getText("Fluid_Empty"), playerNum, ISWorldObjectContextMenu.onFluidEmpty, fc)
    end
end

---------------------------------------------------------------- the menu

local function hasScrewdriver(playerObj)
    local inv = playerObj:getInventory()
    local found = false
    pcall(function()
        found = inv:containsTagEval("base:screwdriver", function(it) return it ~= nil end) == true
    end)
    if not found and inv.containsTypeRecurse then
        found = inv:containsTypeRecurse("Screwdriver") == true
    end
    return found
end

local function addTankMenu(playerNum, context, worldobjects, test)
    if test then return end
    local tank = tankIn(worldobjects)
    if not tank then return end
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end
    pcall(DazedPlumb.TankFluid.reconcile, tank)          -- single player: show what the Fluid menu left in it
    local d = P.data(tank)

    local title = getText("ContextMenu_DazedPlumb_Tank") .. (d.name and (": " .. d.name) or "")
    local top = context:addOption(title, worldobjects, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(top, sub)

    local line = sub:addOption(statusLine(d), nil, nil)
    line.notAvailable = true
    if DazedPlumb.Place and DazedPlumb.Place.mustEmpty and DazedPlumb.Place.mustEmpty(tank) then
        sub:addOption(getText("IGUI_DazedPlumb_EmptyToMove"), nil, nil).notAvailable = true
    end
    sub:addOption(getText("ContextMenu_DazedPlumb_OpenGauge"), worldobjects,
        function(_, t, pl) DazedPlumb.Gauge.open(pl, t) end, tank, playerObj)
    sub:addOption(getText("ContextMenu_DazedPlumb_Rename"), worldobjects, onRename, tank, playerObj, d.name)

    -- the game's Fluid menu sits on the tank's first square only; clicking another square of a long tank gets this copy
    addFluidMenu(context, tank, playerNum)

    local inv = playerObj:getInventory()
    local vessels = collectRecurse(inv, function(it) return F.vessel(it) ~= nil end)

    -- Pour in: containers holding what this tank holds.
    local anyIn = false
    for _, it in ipairs(vessels) do
        local v = F.vessel(it)
        if v and v.kind == d.type and v.amount > 0.001 then
            anyIn = true
            local move = math.min(v.amount, M.room(d))
            local opt = sub:addOption(getText("ContextMenu_DazedPlumb_PourIn") .. ": " .. vesselLabel(it, v),
                                      worldobjects, onFill, tank, playerObj, it, move)
            if M.room(d) <= 0.001 then
                opt.notAvailable = true
                opt.toolTip = tip(getText("Tooltip_DazedPlumb_Full"))
            end
        end
    end
    if not anyIn then
        local opt = sub:addOption(getText("ContextMenu_DazedPlumb_PourInNone"), nil, nil)
        opt.notAvailable = true
        opt.toolTip = tip(getText("Tooltip_DazedPlumb_NoVessel_" .. string.upper(d.type:sub(1, 1)) .. d.type:sub(2)))
    end

    -- Take out: containers with room that can take it.
    local anyOut = false
    for _, it in ipairs(vessels) do
        local v = F.vessel(it)
        local sameQuality = d.type ~= "water" or v.kind ~= "water" or v.amount <= 0.001
            or (v.tainted == true) == M.isTainted(d)
        if v and (v.kind == d.type or (v.kind == "empty" and F.accepts(it, d.type))) and v.capacity - v.amount > 0.001 and sameQuality then
            anyOut = true
            local move = math.min(d.amount or 0, v.capacity - v.amount)
            local opt = sub:addOption(getText("ContextMenu_DazedPlumb_TakeOut") .. ": " .. vesselLabel(it, v, d.type),
                                      worldobjects, onTake, tank, playerObj, it, move)
            if (d.amount or 0) <= 0.001 then
                opt.notAvailable = true
                opt.toolTip = tip(getText("Tooltip_DazedPlumb_Empty"))
            end
        end
    end
    if not anyOut then
        local opt = sub:addOption(getText("ContextMenu_DazedPlumb_TakeOutNone"), nil, nil)
        opt.notAvailable = true
    end

    -- An admin can fill any tank, propane included.
    if DazedPlumb.isAdmin(playerObj) then
        sub:addOption(getText("ContextMenu_DazedPlumb_AdminFill"), worldobjects,
            function(_, t, pl) ISTimedActionQueue.add(DUP_TankAdminFill:new(pl, t)) end, tank, playerObj)
    end

    -- Patch it.
    if (d.condition or 100) < 100 then
        local sheet = inv:getFirstEvalRecurse(function(i) return i ~= nil and i:getFullType() == "Base.SmallSheetMetal" end)
        local screws = inv:getFirstEvalRecurse(function(i) return i ~= nil and i:getFullType() == "Base.Screws" end)
        local opt = sub:addOption(getText("ContextMenu_DazedPlumb_Patch"), worldobjects, onRepair,
                                  tank, playerObj, sheet, screws)
        if not (sheet and screws) then
            opt.notAvailable = true
            opt.toolTip = tip(getText("Tooltip_DazedPlumb_NeedPatchParts"))
        elseif not hasScrewdriver(playerObj) then
            opt.notAvailable = true
            opt.toolTip = tip(getText("Tooltip_DazedPlumb_NeedScrewdriver"))
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(addTankMenu)

-- A long tank keeps its fluid container on its first piece only. When another piece is clicked, the game is
-- handed the first piece too, so its full Fluid menu (drink, fill, pour in, transfer) shows on every square.
local function addMasterToFetch(playerNum, context, worldobjects, test)
    local tank = tankIn(worldobjects)
    if not (tank and tank.getFluidContainer and tank:getFluidContainer()) then return end
    local fetch = ISWorldObjectContextMenu.fetchVars
    if not fetch or not ISWorldObjectContextMenuLogic or not ISWorldObjectContextMenuLogic.fetch then return end
    for _, o in ipairs(fetch.fluidcontainer or {}) do
        if o == tank or o == tank:getFluidContainer() or (o.getGameEntity and o:getGameEntity() == tank) then return end
    end
    pcall(ISWorldObjectContextMenuLogic.fetch, fetch, tank, playerNum, true)
end
if Events.OnPreFillWorldObjectContextMenu then Events.OnPreFillWorldObjectContextMenu.Add(addMasterToFetch) end

-- A dedicated server's refusal notes arrive through the core (DazedCore/DC_NoteClient).
