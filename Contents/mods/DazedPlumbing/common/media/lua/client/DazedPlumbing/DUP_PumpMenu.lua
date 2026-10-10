--[[ Dazed Plumbing -- right-click menu for a water pump: the
     well's level, "Pump" (hand pump into its piped tank) and "Fill a
     container". The pipe / link rows come from DUP_LinkMenu. ]]

require "DazedPlumbing/DUP_Pumps"
require "DazedPlumbing/DUP_PumpActions"
require "DazedPlumbing/DUP_Power"
require "DazedPlumbing/DUP_Fluids"

local P, M, L, U, F = DazedPlumb.Parts, DazedPlumb.Model, DazedPlumb.Links, DazedPlumb.Pumps, DazedPlumb.Fluids

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

-- The percent sign rides in the argument: a bare % in a translation string breaks the game's formatter.
local function pct(f) return string.format("%d", math.floor(f * 100 + 0.5)) .. "%" end
local function rate(v) return (v >= 10 or v == math.floor(v)) and string.format("%d", math.floor(v + 0.5)) or string.format("%.1f", v) end

--- The on/off line and switch for an electric pump or a purifier.
function U.addSwitchMenu(sub, worldobjects, obj, playerObj)
    local off = U.isOff(obj)
    sub:addOption(getText(off and "IGUI_DazedPlumb_SwitchedOff" or "IGUI_DazedPlumb_SwitchedOn"), nil, nil).notAvailable = true
    sub:addOption(getText(off and "ContextMenu_DazedPlumb_TurnOn" or "ContextMenu_DazedPlumb_TurnOff"), worldobjects,
        function(_, o, pl, on) if approach(pl, o) then ISTimedActionQueue.add(DUP_PowerSwitch:new(pl, o, on)) end end,
        obj, playerObj, off)
end

--- The flow line and the "Set flow" choices for an electric pump or a purifier.
--  `rateAt(f)` is its litres a minute at flow share f; `running` whether water is moving now.
function U.addFlowMenu(sub, worldobjects, obj, playerObj, rateAt, running)
    local now = U.flow(obj)
    local line = getText("IGUI_DazedPlumb_FlowNow", rate(rateAt(now)), pct(now))
        .. "  " .. getText(running and "IGUI_DazedPlumb_Running" or "IGUI_DazedPlumb_Idle")
    sub:addOption(line, nil, nil).notAvailable = true
    local top = sub:addOption(getText("ContextMenu_DazedPlumb_SetFlow"), nil, nil)
    local choices = ISContextMenu:getNew(sub)
    sub:addSubMenu(top, choices)
    for _, f in ipairs(U.FLOWS) do
        local opt = choices:addOption(getText("ContextMenu_DazedPlumb_FlowChoice", pct(f), rate(rateAt(f))), worldobjects,
            function(_, o, pl, flow) if approach(pl, o) then ISTimedActionQueue.add(DUP_SetFlow:new(pl, o, flow)) end end,
            obj, playerObj, f)
        if math.abs(f - now) < 0.001 then opt.notAvailable = true end
    end
end

-- How much the handle can be asked for at once, in litres (plus "until full").
local PUMP_AMOUNTS = { 5, 25, 50, 100, 250 }

--- Queue `n` strokes; the queue stops early when the tanks fill or the well runs dry.
local function onStrokes(_, pump, playerObj, n)
    if not approach(playerObj, pump) then return end
    for _ = 1, n do ISTimedActionQueue.add(DUP_PumpStroke:new(playerObj, pump)) end
end

local function addPumpMenu(playerNum, context, worldobjects, test)
    if test then return end
    local pump
    for _, o in ipairs(DazedPlumb.Parts.objectsAround(worldobjects)) do if U.isPump(o) then pump = o break end end
    if not pump then return end
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end
    local info = U.describe(pump)
    local sq = pump:getSquare()
    local w = sq and U.well(sq) or { reserve = 0, cap = 0 }

    local top = context:addOption(getText("ContextMenu_DazedPlumb_Pump"), worldobjects, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(top, sub)

    local text = getText("IGUI_DazedPlumb_Aquifer") .. ": " .. f0(w.reserve) .. " / " .. f0(w.cap) .. " L"
    if w.reserve <= 0.5 then text = text .. "  " .. getText("IGUI_DazedPlumb_Dry") end
    sub:addOption(text, nil, nil).notAvailable = true
    local powered = (info.kind == "hand") or U.powered(pump)
    if info.kind == "electric" then
        sub:addOption(powered and getText("IGUI_DazedPlumb_Powered") or getText("IGUI_DazedPlumb_NoPower"), nil, nil).notAvailable = true
        U.addSwitchMenu(sub, worldobjects, pump, playerObj)
        U.addFlowMenu(sub, worldobjects, pump, playerObj, function(f) return U.ELECTRIC_RATE * f end,
            U.working ~= nil and U.working(pump))
    end

    -- the handle: needs a linked tank with room
    if info.kind == "hand" then
        -- the room in every tank (or purifier) on the pump's line, as the stroke itself counts it
        local link = L.linkOf(pump, U.ID)
        local st = link and link.source == "tank" and L.status(pump, L.adapters[U.ID]) or nil
        local room, n = 0, 0
        for _, r in ipairs(st and st.receivers or {}) do room = room + (r.room() or 0) n = n + 1 end
        if n == 0 then
            local opt = sub:addOption(getText("ContextMenu_DazedPlumb_PumpHandle"), nil, nil)
            opt.notAvailable = true
            opt.toolTip = ISWorldObjectContextMenu.addToolTip()
            opt.toolTip.description = getText("IGUI_DazedPlumb_PumpNoTank")
        else
            local can = math.min(room, w.reserve)
            local hopt = sub:addOption(getText("ContextMenu_DazedPlumb_PumpHandle"), nil, nil)
            if can < 0.5 then
                hopt.notAvailable = true
            else
                local amounts = ISContextMenu:getNew(sub)
                sub:addSubMenu(hopt, amounts)
                local function strokesFor(litres) return math.max(1, math.ceil(litres / U.STROKE - 0.001)) end
                for _, litres in ipairs(PUMP_AMOUNTS) do
                    if litres < can then
                        amounts:addOption(getText("ContextMenu_DazedPlumb_PumpLitres", litres, strokesFor(litres)), worldobjects,
                            onStrokes, pump, playerObj, strokesFor(litres))
                    end
                end
                amounts:addOption(getText("ContextMenu_DazedPlumb_PumpAll", f0(can), strokesFor(can)), worldobjects,
                    onStrokes, pump, playerObj, strokesFor(can))
            end
            sub:addOption(getText("IGUI_DazedPlumb_PumpRoom", string.format("%d", math.floor(room))), nil, nil).notAvailable = true
        end
    end

    -- fill a carried container straight from the well
    local vessels = collect(playerObj:getInventory(), function(it) return F.vessel(it) ~= nil end)
    local any = false
    for _, it in ipairs(vessels) do
        local v = F.vessel(it)
        if v and ((v.kind == "water" and (v.amount <= 0.001 or v.tainted)) or (v.kind == "empty" and F.accepts(it, "water")))
                and v.capacity - v.amount > 0.001 then
            any = true
            local name = (it.getName and it:getName()) or "?"
            local units = math.min(v.capacity - v.amount, w.reserve)
            local opt = sub:addOption(getText("ContextMenu_DazedPlumb_PumpFill") .. ": " .. name .. " (" .. f0(v.amount) .. " L)",
                worldobjects, function(_, p, pl, item, u) if approach(pl, p) then ISTimedActionQueue.add(DUP_PumpFill:new(pl, p, item, u)) end end,
                pump, playerObj, it, units)
            if not powered or w.reserve <= 0.5 then opt.notAvailable = true end
        end
    end
    if not any then sub:addOption(getText("ContextMenu_DazedPlumb_PumpFillNone"), nil, nil).notAvailable = true end
end

Events.OnFillWorldObjectContextMenu.Add(addPumpMenu)
