--[[ Dazed Plumbing -- right-click menu for a garden sprinkler: the crops in reach, its state, the switch and the schedule.
     The pipe rows come from DUP_LinkMenu. ]]

require "DazedPlumbing/DUP_Sprinklers"
require "DazedPlumbing/DUP_PumpActions"

local Z = DazedPlumb.Sprinklers

local function approach(playerObj, obj)
    local sq = obj:getSquare()
    if not sq then return false end
    if luautils and luautils.walkAdj then return luautils.walkAdj(playerObj, sq) end
    return true
end

local function hh(h) return string.format("%02d:00", h) end

--- The schedule as one line of text: its window (or "always") and whether it skips rain.
local function scheduleText(from, to, rainSkip)
    local window = from and getText("IGUI_DazedPlumb_SprinklerWindow", hh(from), hh(to)) or getText("IGUI_DazedPlumb_SprinklerAlways")
    return window, getText(rainSkip and "IGUI_DazedPlumb_SprinklerRainSkipOn" or "IGUI_DazedPlumb_SprinklerRainSkipOff")
end

local function queueSchedule(_, obj, playerObj, field, from, to, skip)
    if approach(playerObj, obj) then ISTimedActionQueue.add(DUP_SprinklerSchedule:new(playerObj, obj, field, from, to, skip)) end
end

--- The "Schedule" submenu: the hour presets (the current one greyed) and the rain toggle.
local function addScheduleMenu(sub, worldobjects, obj, playerObj, from, to, rainSkip)
    local sched = ISContextMenu:getNew(sub)
    sub:addSubMenu(sub:addOption(getText("ContextMenu_DazedPlumb_SprinklerSchedule"), nil, nil), sched)
    local current = Z.presetOf(from, to)
    for _, p in ipairs(Z.PRESETS) do
        local label = getText("ContextMenu_DazedPlumb_SprinklerPreset_" .. p.id)
        if p.from then label = label .. " (" .. hh(p.from) .. " - " .. hh(p.to) .. ")" end
        local opt = sched:addOption(label, worldobjects, queueSchedule, obj, playerObj, "window", p.from or -1, p.to or -1, rainSkip)
        if p.id == current then opt.notAvailable = true end
    end
    sched:addOption(getText(rainSkip and "ContextMenu_DazedPlumb_SprinklerRainSkipOff" or "ContextMenu_DazedPlumb_SprinklerRainSkipOn"),
        worldobjects, queueSchedule, obj, playerObj, "rain", -1, -1, not rainSkip)
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
    local held = on and Z.blocked(obj)
    local state = not on and "IGUI_DazedPlumb_SprinklerOff"
        or (held == "window" and "IGUI_DazedPlumb_SprinklerOutsideWindow")
        or (held == "rain" and "IGUI_DazedPlumb_SprinklerRaining")
        or (Z.describe(obj).spraying and "IGUI_DazedPlumb_SprinklerSpraying" or "IGUI_DazedPlumb_SprinklerWaiting")
    sub:addOption(getText(state), nil, nil).notAvailable = true

    -- the schedule: a line in the submenu and the top row's tooltip
    local from, to, rainSkip = Z.schedule(obj)
    local window, rain = scheduleText(from, to, rainSkip)
    sub:addOption(window .. ", " .. rain, nil, nil).notAvailable = true
    local tip = ISWorldObjectContextMenu and ISWorldObjectContextMenu.addToolTip and ISWorldObjectContextMenu.addToolTip()
    if tip then
        tip.description = getText(state) .. " <LINE> " .. window .. " <LINE> " .. rain
        top.toolTip = tip
    end

    sub:addOption(getText(on and "ContextMenu_DazedPlumb_SprinklerTurnOff" or "ContextMenu_DazedPlumb_SprinklerTurnOn"),
        worldobjects, function(_, o, pl, want)
            if approach(pl, o) then ISTimedActionQueue.add(DUP_SprinklerToggle:new(pl, o, want)) end
        end, obj, playerObj, not on)
    addScheduleMenu(sub, worldobjects, obj, playerObj, from, to, rainSkip)
end

Events.OnFillWorldObjectContextMenu.Add(addSprinklerMenu)
