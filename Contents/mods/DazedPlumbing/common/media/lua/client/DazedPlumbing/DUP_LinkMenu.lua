--[[ Dazed Utilities: Plumbing -- the line menu on machines, pumps and taps, and
     the menu on a laid pipe.

     MACHINE (a generator, boiler, pump, purifier or a water fixture): one entry
     with a submenu: where it draws from or pushes to, a "Pipe to: <tank>" row
     for every tank in reach (a run that ends beside a pipe already serving that
     tank joins it), pause / resume, mend a broken square, and disconnect.
     PIPE: its fluid and condition, mend, cut, fit a valve, open or close one.

     The menu only PREVIEWS the route and the cost; the authority lays it
     (DUP_LinkActions). A dedicated-server client may not have every square of a
     long run loaded, so the preview can be shorter than the truth.
]]

require "DazedPlumbing/DUP_Links"
require "DazedPlumbing/DUP_LinkActions"
require "DazedPlumbing/DUP_Menu"

local P, M, L, K, N = DazedPlumb.Parts, DazedPlumb.Model, DazedPlumb.Links, DazedPlumb.Pipes, DazedPlumb.Net

local PIPE_RANGE = 25            -- how far a tank may be and still be offered a pipe
local PLAN_MAX = 8               -- routes worked out per menu, nearest first (each one is a search)

local function f1(v) return string.format("%.1f", v or 0) end

local function tip(text)
    local t = ISWorldObjectContextMenu and ISWorldObjectContextMenu.addToolTip and ISWorldObjectContextMenu.addToolTip()
    if t then t.description = text end
    return t
end

local function approach(playerObj, obj)
    local sq = obj:getSquare()
    if not sq then return false end
    if luautils and luautils.walkAdj then return luautils.walkAdj(playerObj, sq) end
    return true
end

local function toSquare(playerObj, x, y, z)
    local cell = getCell()
    local sq = cell and cell:getGridSquare(x, y, z)
    if not sq then return false end
    if luautils and luautils.walkAdj then return luautils.walkAdj(playerObj, sq) end
    return true
end

local function onPipe(_, machine, playerObj, adapterId, tank)
    if approach(playerObj, machine) then ISTimedActionQueue.add(DUP_PipeSet:new(playerObj, machine, adapterId, tank)) end
end
local function onClear(_, machine, playerObj, adapterId)
    if approach(playerObj, machine) then ISTimedActionQueue.add(DUP_LinkClear:new(playerObj, machine, adapterId)) end
end
local function onSource(_, machine, playerObj, adapterId, source)
    if approach(playerObj, machine) then ISTimedActionQueue.add(DUP_LinkSource:new(playerObj, machine, adapterId, source)) end
end
local function onSquare(action)
    return function(_, playerObj, x, y, z)
        if toSquare(playerObj, x, y, z) then ISTimedActionQueue.add(action:new(playerObj, x, y, z)) end
    end
end
local onRepair, onCut = onSquare(DUP_PipeRepair), onSquare(DUP_PipeCut)
local onValveFit, onValveToggle = onSquare(DUP_ValveFit), onSquare(DUP_ValveToggle)

local function nodeLabel(obj)
    local sq = obj:getSquare()
    return string.format("%s (%d,%d)", getText("ContextMenu_DazedPlumb_Purifier"), sq and sq:getX() or 0, sq and sq:getY() or 0)
end

local function tankLabel(tank, info, d)
    local sq = tank:getSquare()
    if d.name then
        return string.format("%s (%d,%d)  %s/%s %s", d.name, sq and sq:getX() or 0, sq and sq:getY() or 0,
            f1(d.amount), f1(M.capacity(d.size, d.tier, info.type)), M.UNIT[info.type])
    end
    return string.format("%s %s (%d,%d)  %s/%s %s", getText(P.sizeKey(info.size)), getText(P.typeKey(info.type)),
        sq and sq:getX() or 0, sq and sq:getY() or 0, f1(d.amount), f1(M.capacity(d.size, d.tier, info.type)), M.UNIT[info.type])
end

--- The first broken or worn square of the lines a device is on, or nil.
local function worstSquare(endStr)
    local pipes, worst = K.pipes(), nil
    for _, k in ipairs(K.index()[endStr] or {}) do
        local c = N.component(pipes, k, true)
        for _, ck in ipairs(c and c.keys or {}) do
            local r = pipes[ck]
            if r and (r.cond or 100) < 100 then
                if not worst or (r.cond or 0) < worst.cond then worst = { key = ck, cond = r.cond or 0 } end
            end
        end
    end
    return worst
end

local function addLineMenu(playerNum, context, worldobjects, test)
    if test then return end
    local machine, adapter
    for _, o in ipairs(DazedPlumb.Parts.objectsAround(worldobjects)) do
        local a = L.adapterFor(o)
        if a then machine, adapter = o, a break end
    end
    if not machine then return end
    local playerObj = getSpecificPlayer(playerNum)
    local msq = machine:getSquare()
    if not (playerObj and msq) then return end
    local fluid = L.kindOf(adapter)

    local top = context:addOption(getText(adapter.label or "ContextMenu_DazedPlumb_FuelLine"), worldobjects, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(top, sub)

    local st = L.status(machine, adapter)
    local link = L.linkOf(machine, adapter.id)
    local head
    if not st.connected then
        head = getText("IGUI_DazedPlumb_NotLinked")
    elseif not st.working then
        head = getText("IGUI_DazedPlumb_LineDown")
    elseif adapter.supplies then
        local t = st.tanks[1]
        head = getText("IGUI_DazedPlumb_Piped") .. " (" .. #st.tanks .. " " .. getText("IGUI_DazedPlumb_Tanks") .. ")"
        if link and link.tx and t then
            local d = P.data(t.obj)
            head = getText("IGUI_DazedPlumb_DrawingFrom") .. ": " .. getText(P.typeKey(fluid)) .. " (" .. link.tx .. "," .. link.ty .. ")  "
                .. f1(d.amount) .. " " .. M.UNIT[fluid]
        end
    else
        head = getText("IGUI_DazedPlumb_Piped") .. " (" .. #st.receivers .. " " .. getText("IGUI_DazedPlumb_Tanks") .. ")"
    end
    if link and link.source ~= "tank" then head = head .. "  [" .. getText("IGUI_DazedPlumb_LinkPaused") .. "]" end
    sub:addOption(head, nil, nil).notAvailable = true

    -- every tank (or purifier, for a pump) in reach: a run to it, joining any line already there
    local withNodes = adapter.produces ~= nil and not adapter.noNodes
    local have = #L.itemsOf(playerObj:getInventory(), K.ITEM)
    local skilled = L.weldLevel(playerObj) >= K.WELD_LEVEL
    local wrench = L.hasWrench(playerObj)
    local connectedTo = {}
    for _, t in ipairs(st.receivers) do connectedTo[t.obj] = true end
    local offered, planned = 0, 0
    for _, n in ipairs(L.tanksNear(machine, fluid, PIPE_RANGE, withNodes)) do
        if not connectedTo[n.tank] and planned < PLAN_MAX then
            planned = planned + 1
            local T = L.wrapTarget(n.tank, fluid)
            local role, id = "tank", "tank"
            if T and T.isNode then role, id = "node", T.node.id end
            -- a run is never shorter than the gap, so a tank past the longest run is not searched for
            local plan = T and n.dist <= K.MAX_LEN + 1 and K.plan(msq, fluid, T.squares(), role, id)
            local text = n.node and nodeLabel(n.tank) or tankLabel(n.tank, P.describe(n.tank), P.data(n.tank))
            local label = getText("ContextMenu_DazedPlumb_PipeTo") .. ": " .. text
            if plan then
                local cost = K.cost(plan)
                label = label .. "  [" .. cost .. " " .. getText("IGUI_DazedPlumb_Squares")
                if plan.tail.kind == "pipe" then label = label .. ", " .. getText("IGUI_DazedPlumb_JoinsLine") end
                label = label .. "]"
                local opt = sub:addOption(label, worldobjects, onPipe, machine, playerObj, adapter.id, n.tank)
                if not skilled then
                    opt.notAvailable = true
                    opt.toolTip = tip(getText("IGUI_DazedPlumb_NeedWelding"))
                elseif not wrench then
                    opt.notAvailable = true
                    opt.toolTip = tip(getText("IGUI_DazedPlumb_NeedWrench"))
                elseif have < cost then
                    opt.notAvailable = true
                    opt.toolTip = tip(getText("IGUI_DazedPlumb_NeedSectionsN", cost, have))
                end
            else
                local o = sub:addOption(label .. "  [" .. getText("IGUI_DazedPlumb_NoRoute") .. "]", nil, nil)
                o.notAvailable = true
            end
            offered = offered + 1
        end
    end
    if offered == 0 and not st.connected then
        sub:addOption(getText("ContextMenu_DazedPlumb_LinkNone"), nil, nil).notAvailable = true
    end

    -- mend the worst square of this device's lines
    local endStr = L.endFor(machine, adapter)
    local worst = endStr and worstSquare(endStr)
    if worst then
        local x, y, z = N.split(worst.key)
        local txt = worst.cond <= 0 and getText("IGUI_DazedPlumb_PipeBroken") or getText("IGUI_DazedPlumb_PipeWorn")
        local opt = sub:addOption(getText("ContextMenu_DazedPlumb_PipeRepair") .. " (" .. x .. "," .. y .. ")  " .. txt,
                                  worldobjects, onRepair, playerObj, x, y, z)
        if not skilled then
            opt.notAvailable = true
            opt.toolTip = tip(getText("IGUI_DazedPlumb_NeedWelding"))
        elseif not wrench then
            opt.notAvailable = true
            opt.toolTip = tip(getText("IGUI_DazedPlumb_NeedWrench"))
        elseif have < 1 then
            opt.notAvailable = true
            opt.toolTip = tip(getText("IGUI_DazedPlumb_NeedSectionsN", 1, have))
        end
    end

    if link or st.connected then
        if link and link.source == "tank" then
            sub:addOption(getText("ContextMenu_DazedPlumb_UseOwn"), worldobjects, onSource, machine, playerObj, adapter.id, "manual")
        elseif link then
            sub:addOption(getText("ContextMenu_DazedPlumb_UseTank"), worldobjects, onSource, machine, playerObj, adapter.id, "tank")
        end
        sub:addOption(getText("ContextMenu_DazedPlumb_Unlink"), worldobjects, onClear, machine, playerObj, adapter.id)
    end
end

-- Right-clicking a laid pipe: what it carries, its condition, mend, cut and valve.
local function addPipeMenu(playerNum, context, worldobjects, test)
    if test then return end
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end
    for _, o in ipairs(DazedPlumb.Parts.objectsAround(worldobjects)) do
        if K.isPipe(o) then
            local sq = o:getSquare()
            local r = sq and K.record(sq:getX(), sq:getY(), sq:getZ())
            if sq and r then
                local x, y, z = sq:getX(), sq:getY(), sq:getZ()
                local top = context:addOption(getText("ContextMenu_DazedPlumb_Pipe") .. " (" .. getText(P.typeKey(r.f)) .. ")", worldobjects, nil)
                local sub = ISContextMenu:getNew(context)
                context:addSubMenu(top, sub)
                local tanks, users, makers = 0, 0, 0
                local c = N.component(K.pipes(), N.key(x, y, z), true)
                for _, e in ipairs(c and N.endsOf(K.pipes(), c) or {}) do
                    if e.role == "tank" then tanks = tanks + 1
                    elseif e.role == "sink" then users = users + 1
                    elseif e.role == "source" then makers = makers + 1 end
                end
                sub:addOption(getText("IGUI_DazedPlumb_LineSummary", tanks, users, makers), nil, nil).notAvailable = true
                sub:addOption(getText("IGUI_DazedPlumb_Condition") .. ": " .. string.format("%d", r.cond or 0)
                    .. (r.valve and ("   " .. getText("IGUI_DazedPlumb_Valve") .. ": " .. getText(r.valve == "open" and "IGUI_DazedPlumb_Open" or "IGUI_DazedPlumb_Shut")) or ""),
                    nil, nil).notAvailable = true

                local have = #L.itemsOf(playerObj:getInventory(), K.ITEM)
                local skilled = L.weldLevel(playerObj) >= K.WELD_LEVEL
                local wrench = L.hasWrench(playerObj)
                local noWrench = getText("IGUI_DazedPlumb_NeedWrench")
                if (r.cond or 100) < 100 then
                    local opt = sub:addOption(getText("ContextMenu_DazedPlumb_PipeRepairHere"), worldobjects, onRepair, playerObj, x, y, z)
                    if not skilled then opt.notAvailable = true opt.toolTip = tip(getText("IGUI_DazedPlumb_NeedWelding"))
                    elseif not wrench then opt.notAvailable = true opt.toolTip = tip(noWrench)
                    elseif have < 1 then opt.notAvailable = true opt.toolTip = tip(getText("IGUI_DazedPlumb_NeedSectionsN", 1, have)) end
                end
                if r.valve then
                    sub:addOption(getText(r.valve == "open" and "ContextMenu_DazedPlumb_ValveClose" or "ContextMenu_DazedPlumb_ValveOpen"),
                        worldobjects, onValveToggle, playerObj, x, y, z)
                else
                    -- always offered, greyed with the reason when it cannot be fitted yet
                    local can, why = K.canValve(x, y, z)
                    local valves = #L.itemsOf(playerObj:getInventory(), K.VALVE_ITEM)
                    local opt = sub:addOption(getText("ContextMenu_DazedPlumb_ValveFit"), worldobjects, onValveFit, playerObj, x, y, z)
                    if not can then opt.notAvailable = true opt.toolTip = tip(getText(why or "IGUI_DazedPlumb_ValveBroken"))
                    elseif L.weldLevel(playerObj) < 2 then opt.notAvailable = true opt.toolTip = tip(getText("IGUI_DazedPlumb_NeedWeldingValve"))
                    elseif not wrench then opt.notAvailable = true opt.toolTip = tip(noWrench)
                    elseif valves < 1 then opt.notAvailable = true opt.toolTip = tip(getText("IGUI_DazedPlumb_NeedValve")) end
                end
                local cut = sub:addOption(getText("ContextMenu_DazedPlumb_PipeCut"), worldobjects, onCut, playerObj, x, y, z)
                if not wrench then cut.notAvailable = true cut.toolTip = tip(noWrench) end
            end
            return
        end
    end
end

-- Right-clicking a tank: pipe it to another tank of the same type, so the two even out.
local function addTankLinkMenu(playerNum, context, worldobjects, test)
    if test then return end
    local tank
    for _, o in ipairs(DazedPlumb.Parts.objectsAround(worldobjects)) do
        if P.isTank(o) then tank = P.master(o) break end
    end
    local info = tank and P.describe(tank)
    local playerObj = getSpecificPlayer(playerNum)
    if not (info and playerObj and tank:getSquare()) then return end
    local fluid = info.type
    -- tanks already sharing a line with this one
    local linked = {}
    local key = L.devKey(tank)
    for _, comp in ipairs(N.components(K.pipes())) do
        if comp.fluid == fluid then
            local r = L.resolve(comp, fluid)
            local mine = false
            for _, t in ipairs(r.tanks) do if t.key == key then mine = true end end
            if mine then for _, t in ipairs(r.tanks) do linked[t.obj] = true end end
        end
    end
    local rows = {}
    for _, n in ipairs(L.tanksNear(tank, fluid, PIPE_RANGE, false)) do
        if n.tank ~= tank and not linked[n.tank] and #rows < PLAN_MAX then rows[#rows + 1] = n end
    end
    if #rows == 0 then return end
    local top = context:addOption(getText("ContextMenu_DazedPlumb_LinkTanks"), worldobjects, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(top, sub)
    local have = #L.itemsOf(playerObj:getInventory(), K.ITEM)
    local skilled = L.weldLevel(playerObj) >= K.WELD_LEVEL
    local wrench = L.hasWrench(playerObj)
    for _, n in ipairs(rows) do
        local label = getText("ContextMenu_DazedPlumb_PipeTo") .. ": " .. tankLabel(n.tank, P.describe(n.tank), P.data(n.tank))
        local plan = n.dist <= K.MAX_LEN + 1 and K.plan(tank:getSquare(), fluid, P.squares(n.tank), "tank", "tank")
        if plan then
            local cost = K.cost(plan)
            local opt = sub:addOption(label .. "  [" .. cost .. " " .. getText("IGUI_DazedPlumb_Squares") .. "]", worldobjects,
                function(_, a, pl, b) if approach(pl, a) then ISTimedActionQueue.add(DUP_TankLink:new(pl, a, b)) end end,
                tank, playerObj, n.tank)
            if not skilled then opt.notAvailable = true opt.toolTip = tip(getText("IGUI_DazedPlumb_NeedWelding"))
            elseif not wrench then opt.notAvailable = true opt.toolTip = tip(getText("IGUI_DazedPlumb_NeedWrench"))
            elseif have < cost then opt.notAvailable = true opt.toolTip = tip(getText("IGUI_DazedPlumb_NeedSectionsN", cost, have)) end
        else
            sub:addOption(label .. "  [" .. getText("IGUI_DazedPlumb_NoRoute") .. "]", nil, nil).notAvailable = true
        end
    end
    sub:addOption(getText("IGUI_DazedPlumb_LinkTanksNote"), nil, nil).notAvailable = true
end

-- Debug mode: why a square would or would not take a pipe.
local function addDebugSquare(playerNum, context, worldobjects, test)
    if test or not (getDebug and getDebug()) then return end
    local o = worldobjects and worldobjects[1]
    local sq = o and o.getSquare and o:getSquare()
    if not sq then return end
    local clear, why = K.squareClear(sq)
    context:addDebugOption("[Plumbing] pipe here: " .. (clear and "clear" or ("blocked by " .. tostring(why))), nil, nil)
    -- What the square holds and what the network says it should, for chasing pipes that will not draw.
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local rec = K.record(x, y, z)
    if rec then
        context:addDebugOption(string.format("[Plumbing] record: mask %d (drawn %d), %s, cond %d, %d end(s)",
            rec.mask or 0, K.displayMask(N.key(x, y, z), rec), rec.outdoor and "outdoor" or "overhead",
            rec.cond or 100, #(rec.ends or {})), nil, nil)
    end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local ob = objs:get(i)
        local spr = ob:getSprite()
        local name = spr and spr:getName() or "(no sprite)"
        if string.find(tostring(name), P.TILESET, 1, true) then
            context:addDebugOption("[Plumbing] object " .. i .. ": " .. tostring(name)
                .. (K.isPipe(ob) and " (pipe)" or K.isPort(ob) and " (port)" or K.isValve(ob) and " (valve)" or ""), nil, nil)
        end
    end
    -- On a device square: what stands there and which ports the pipes beside it ask for.
    local dev = not rec and K.deviceOn(sq)
    if dev then
        local a = L.adapterFor(dev)
        context:addDebugOption("[Plumbing] device: " .. tostring(dev:getSprite() and dev:getSprite():getName())
            .. (a and (" (line: " .. a.id .. ")") or ""), nil, nil)
        local want = K.wantedPorts(x, y, z)
        context:addDebugOption("[Plumbing] ports wanted: " .. (#want > 0 and table.concat(want, ", ") or "none"), nil, nil)
    end
    if dev then
        context:addDebugOption("[Plumbing] redraw ports here", nil, function() K.syncPorts(x, y, z) end)
    end
    if rec then
        context:addDebugOption("[Plumbing] redraw this pipe", nil, function() K.redraw(N.key(x, y, z)) end)
    end
    context:addDebugOption("[Plumbing] redraw every pipe", nil, function() K.redrawAll() end)
end

Events.OnFillWorldObjectContextMenu.Add(addLineMenu)
Events.OnFillWorldObjectContextMenu.Add(addDebugSquare)
Events.OnFillWorldObjectContextMenu.Add(addTankLinkMenu)
Events.OnFillWorldObjectContextMenu.Add(addPipeMenu)
