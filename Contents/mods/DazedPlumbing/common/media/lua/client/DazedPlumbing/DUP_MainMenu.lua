--[[ Dazed Plumbing -- right-click menu for a water main: Water panel (once a building is connected),
     what it serves, the line rate, Connect a building... (the core's Building Picker) and Disconnect.
     The pipe rows come from DUP_LinkMenu. ]]

require "DazedPlumbing/DUP_Mains"
require "DazedPlumbing/DUP_Board"
require "DazedCore/DC_Picker"

local W = DazedPlumb.Mains
local B, R, U, K = DazedCore.Buildings, DazedCore.Reach, DazedCore.Util, DazedCore.Picker

local function f0(v) return string.format("%d", math.floor((v or 0) + 0.5)) end

--- The main's registry key from the picker state.
local function keyOf(st) return st.x .. "," .. st.y .. "," .. st.z end

--- What the picker needs to know about a water main (see DC_Picker's header).
W.PICKER = {
    single = true,
    title = "IGUI_DazedPlumb_MainPickTitle", help = "IGUI_DazedPlumb_MainPickHelp",
    clearTip = "Tooltip_DazedPlumb_MainClear",
    range = function() return W.reach(), W.BAND end,
    textVersion = function() return DazedPlumb.Sync.version end,
    served = function(st)
        local e = W.store().mains[keyOf(st)]
        if not e then return {} end
        return { { k = e.k, x = e.x, y = e.y, z = e.z, id = e.id, rects = R.decodeRects(e.rects) } }
    end,
    status = function(st, t)
        if W.servedBy(t.id, keyOf(st)) then return "taken" end
        return nil
    end,
    pick = function(st, sx, sy, sz)
        W.send(st.player, "mainPick", { x = st.x, y = st.y, z = st.z, sx = sx, sy = sy, sz = sz })
    end,
    clear = function(st) W.send(st.player, "mainClear", { x = st.x, y = st.y, z = st.z }) end,
}

local function describe(e)
    local fp = W.footprint(e)
    local _, _, _, _, z0, z1 = R.fpBounds(fp)
    local floors = z0 and (z1 - z0 + 1) or 0
    local kind = (e.k == "b") and "IGUI_DazedCore_PickBuilding" or "IGUI_DazedCore_PickStructure"
    return U.txt(kind, U.count("IGUI_DazedCore_TileCount", R.fpCount(fp)), U.count("IGUI_DazedCore_FloorCount", floors))
end

local function addMainMenu(playerNum, context, worldobjects, test)
    if test then return end
    local obj
    for _, o in ipairs(DazedPlumb.Parts.objectsAround(worldobjects)) do if W.isMain(o) then obj = o break end end
    if not obj then return end
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end

    local top = context:addOption(getText("ContextMenu_DazedPlumb_WaterMain"), worldobjects, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(top, sub)

    local e = W.entry(obj)
    if e then
        -- connected: the panel comes first; unconnected, Connect a building... stays the first thing to do
        sub:addOption(getText("ContextMenu_DazedPlumb_WaterPanel"), worldobjects,
            function(_, o, pl) DUP_Board.open(pl, o) end, obj, playerObj)
        sub:addOption(U.txt("IGUI_DazedPlumb_MainServes", describe(e)), nil, nil).notAvailable = true
        local list, total = W.fixtures(obj)
        sub:addOption(U.txt("IGUI_DazedPlumb_MainFixtures", #list, total), nil, nil).notAvailable = true
    else
        sub:addOption(getText("IGUI_DazedPlumb_MainNone"), nil, nil).notAvailable = true
    end
    sub:addOption(U.txt("IGUI_DazedPlumb_MainFlow", f0(W.flow())), nil, nil).notAvailable = true
    sub:addOption(getText("ContextMenu_DazedPlumb_MainConnect"), worldobjects,
        function(_, o, pl) K.open(pl, o, W.PICKER) end, obj, playerObj)
    if e then
        sub:addOption(getText("ContextMenu_DazedPlumb_MainDisconnect"), worldobjects,
            function(_, o, pl) W.send(pl, "mainClear", { x = o:getSquare():getX(), y = o:getSquare():getY(), z = o:getSquare():getZ() }) end,
            obj, playerObj)
    end
end

Events.OnFillWorldObjectContextMenu.Add(addMainMenu)
