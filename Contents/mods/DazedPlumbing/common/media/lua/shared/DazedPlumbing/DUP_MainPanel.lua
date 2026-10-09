--[[ Dazed Utilities: Plumbing -- the Main Water Panel's commands (authority).

     The board (client DUP_Board) never writes ModData: every switch is a DazedCore.Net command run here, re-checked,
     applied to the DazedPlumbMains entry (or the machine's own ModData) and synced. A player works the panel standing
     within the main's reach (plus two) of the main, or within 2 squares of a wall panel that names this main
     (`args.via` = its square; the panel object's ModData `dazedPanelMain` = "x,y,z" of the main, phase 3).

       mainValve   { fx, fy, fz, closed }        close or open one fixture square
       mainPrio    { fx, fy, fz, dir }           move a fixture "up", "down" or to the "top" of the fill order
       mainRate    { rate }                      the house throttle, L/min, 1..MainFlow
       mainShut    { shut }                      the main shut-off (the same switch as the line menu's pause)
       mainDrain   { drain }                     empty the fixtures when the main is shut off
       mainMachine { mx, my, mz, off, flow }     switch or set the flow of a pump, purifier or well on the main's water
       mainInfo    { }                           answered with DazedCore.Net.reply(..., "mainInfo", info)
     Every command also carries x, y, z (the main's square) and may carry via. ]]

require "DazedCore/DC_Boot"
require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Model"
require "DazedPlumbing/DUP_Links"
require "DazedPlumbing/DUP_Fixtures"
require "DazedPlumbing/DUP_Pumps"
require "DazedPlumbing/DUP_Purifiers"
require "DazedPlumbing/DUP_Downspouts"
require "DazedPlumbing/DUP_Rain"
require "DazedPlumbing/DUP_DrilledWells"
require "DazedPlumbing/DUP_Mains"

DazedPlumb.MainPanel = DazedPlumb.MainPanel or {}
local Pn = DazedPlumb.MainPanel
local W, P, L, X, S, M = DazedPlumb.Mains, DazedPlumb.Parts, DazedPlumb.Links, DazedPlumb.Fixtures, DazedPlumb.Sync, DazedPlumb.Model
local U, Pu, D, Rn, Dw = DazedPlumb.Pumps, DazedPlumb.Purifiers, DazedPlumb.Downspouts, DazedPlumb.Rain, DazedPlumb.DrilledWells
local K, NK = DazedPlumb.Pipes, DazedPlumb.Net
local B, R, CU, CN, Note = DazedCore.Buildings, DazedCore.Reach, DazedCore.Util, DazedCore.Net, DazedCore.Note
local try = P.try

Pn.EVERY_MS = 250                 -- one player's switches, at most this often each
Pn.INFO_EVERY_MS = 500            -- one player's mainInfo requests
Pn.VIA_RANGE = 2                  -- squares from a wall panel
Pn.MAX_FIXTURES, Pn.MAX_SOURCES, Pn.MAX_TANKS = 48, 16, 12

----------------------------------------------------------- small helpers
local function int(v)
    v = tonumber(v)
    if not v or v ~= math.floor(v) or v ~= v then return nil end
    return v
end

local function who(player)
    local n = try(player, "getUsername")
    return (type(n) == "string" and n ~= "") and n or "player"
end

-- One console line per panel change, in the mod's "DazedPlumbing: ..." style.
local function log(player, cmd, key, what)
    print("DazedPlumbing: panel " .. who(player) .. " " .. cmd .. " at " .. tostring(key) .. (what and (" " .. what) or ""))
end

local function refuse(player, key)
    Note.say(player, key, nil, true)
    return nil
end

--- Is there a wall panel at via, within reach of the player, that names this main? (Phase 3 places them.)
local function viaPanel(player, via, key)
    if type(via) ~= "table" then return false end
    local vx, vy, vz = int(via.x), int(via.y), int(via.z)
    if not (vx and vy and vz) or not CN.near(player, vx, vy, vz, Pn.VIA_RANGE) then return false end
    local sq = CU.squareAt(vx, vy, vz)
    local objs = sq and sq:getObjects()
    if not objs then return false end
    for i = 0, objs:size() - 1 do
        local md = try(objs:get(i), "getModData")
        if md and md.dazedPanelMain == key then return true end
    end
    return false
end

--- The main a command is about, if this player may work it: main, entry, key; or nil (the player is told why).
function Pn.authorised(player, args)
    if not S.authority() or type(args) ~= "table" then return nil end
    local x, y, z = int(args.x), int(args.y), int(args.z)
    if not (x and y and z) then return nil end
    local key = NK.key(x, y, z)
    local main = W.mainAt(key)
    local e = W.store().mains[key]
    if not main then return refuse(player, "IGUI_DazedPlumb_MainGone") end
    if not e then return refuse(player, "IGUI_DazedPlumb_MainNone") end
    if not (W.near(player, x, y, z) or viaPanel(player, args.via, key)) then
        return refuse(player, "IGUI_DazedPlumb_PanelFar")
    end
    return main, e, key
end

----------------------------------------------------------- the fixtures and the fill order
--- The untapped fixture squares in fill order (priority squares first, then as found), closed ones included.
function Pn.order(main, e)
    local natural, known = {}, {}
    for _, f in ipairs((W.fixtures(main))) do
        local k = W.fixKey(f)
        if k and not known[k] then known[k] = true natural[#natural + 1] = k end
    end
    local out, used = {}, {}
    for _, k in ipairs((W.squares(e.prio))) do
        if known[k] and not used[k] then used[k] = true out[#out + 1] = k end
    end
    for _, k in ipairs(natural) do
        if not used[k] then out[#out + 1] = k end
    end
    return out, natural, known
end

local function sameList(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

----------------------------------------------------------- what is on the main's water
-- Every tank the main can reach (its own lines, and tanks piped to those), and every source pushing into them,
-- a purifier's own feeders included. Bounded, so a sprawling network cannot make one reply huge.
function Pn.network(main)
    local tanks, feeding = W.tanks(main)
    local out = { tanks = {}, sources = {}, feeding = feeding }
    local seenT, seenS, queue, head = {}, {}, {}, 1
    for _, t in ipairs(tanks) do
        if not seenT[t.obj] then seenT[t.obj] = true queue[#queue + 1] = t end
    end
    local function addSource(obj, a)
        if obj and a and not seenS[obj] and #out.sources < Pn.MAX_SOURCES then
            seenS[obj] = true
            out.sources[#out.sources + 1] = { obj = obj, adapter = a }
        end
    end
    local function walk(endStr, pushTanks)
        for _, comp in ipairs(K.componentsOf(endStr)) do
            local r = L.resolveCached(comp, "water")
            for _, s in ipairs(r.sources) do addSource(s.obj, s.adapter) end
            for _, n in ipairs(r.nodes) do
                local sq = try(n.obj, "getSquare")
                if sq and n.node and not seenS[n.obj] then
                    addSource(n.obj, L.adapters[n.node.id] or L.adapterFor(n.obj))
                    walk(NK.endString(NK.key(sq:getX(), sq:getY(), sq:getZ()), "node", n.node.id), false)
                end
            end
            if pushTanks then
                for _, t in ipairs(r.tanks) do
                    if not seenT[t.obj] and #queue < Pn.MAX_TANKS then seenT[t.obj] = true queue[#queue + 1] = t end
                end
            end
        end
    end
    while head <= #queue do
        local t = queue[head]
        head = head + 1
        out.tanks[#out.tanks + 1] = t
        for _, q in ipairs(t.squares()) do
            walk(NK.endString(NK.key(q:getX(), q:getY(), q:getZ()), "tank", "tank"), true)
        end
    end
    return out
end

local function sourceKind(obj, a)
    if a.id == U.ID then
        local info = U.describe(obj)
        return (info and info.kind == "hand") and "handpump" or "pump"
    end
    if a.id == Pu.ID then return "purifier" end
    if a.id == Dw.ID then return "well" end
    if a.id == D.ID then return "downspout" end
    if a.id == Rn.ID then return "rainbarrel" end
    return "other"
end

local function giving(obj, a)
    local ok, v = pcall(a.available, obj)
    return ok and tonumber(v) or 0
end

local function wellText(obj)
    local sq = try(obj, "getSquare")
    if not sq then return "" end
    local w = U.well(sq)
    return string.format("%d/%d L", math.floor(w.reserve + 0.5), math.floor(w.cap + 0.5))
end

--- One SOURCES ON LINE row (no words: the board translates `state`).
function Pn.sourceRow(obj, a)
    local sq = try(obj, "getSquare")
    local kind = sourceKind(obj, a)
    local link = L.linkOf(obj, a.id)
    local paused = link ~= nil and link.source ~= "tank"
    local row = { kind = kind, x = sq and sq:getX(), y = sq and sq:getY(), z = sq and sq:getZ(),
                  label = a.label, lpm = math.floor(giving(obj, a) * 10 + 0.5) / 10, off = U.isOff(obj) }
    if kind == "pump" then
        row.canOff, row.canFlow, row.flow = true, true, U.flow(obj)
        row.powered, row.watts = U.powered(obj), U.watts(obj)
        row.detail = wellText(obj)
        if row.off then row.state = "off" elseif not row.powered then row.state = "nopower"
        elseif paused then row.state = "paused" elseif U.working and U.working(obj) then row.state = "running"
        else row.state = "idle" end
    elseif kind == "handpump" then
        row.state, row.detail = "manual", wellText(obj)
    elseif kind == "purifier" then
        row.canOff, row.canFlow, row.flow = true, true, U.flow(obj)
        row.powered, row.watts = Pu.powered(obj), Pu.watts(obj)
        local f = Pu.state(obj).filter
        row.detail = f and string.format("%d%%", math.floor(f + 0.5)) or "--"
        if row.off then row.state = "off" elseif not row.powered then row.state = "nopower"
        elseif paused then row.state = "paused" elseif Pu.working(obj) then row.state = "running"
        else row.state = "idle" end
    elseif kind == "well" then
        row.canOff = true
        row.powered, row.watts = DazedPlumb.wiredPower(obj), Dw.WATTS
        row.state = Dw.status(obj)
        row.detail = string.format("%d L/min", Dw.RATE)
    elseif kind == "downspout" then
        local wv = D.water(obj)
        row.state, row.detail = wv > 0.001 and "ready" or "idle", string.format("%.1f L", wv)
    elseif kind == "rainbarrel" then
        local wv = Rn.amount(obj)
        row.state, row.detail = wv > 0.001 and "ready" or "empty", string.format("%d L", math.floor(wv + 0.5))
    else
        row.state, row.detail = row.lpm > 0 and "running" or "idle", ""
    end
    return row
end

--- A tank row for the board.
local function tankRow(t, feeding)
    local d = P.data(t.obj) or {}
    local info = P.describe(t.obj) or {}
    local sq = try(t.obj, "getSquare")
    return { name = d.name, size = info.size, x = sq and sq:getX(), y = sq and sq:getY(), z = sq and sq:getZ(),
             amount = math.floor(math.max(0, t.amount()) * 10 + 0.5) / 10,
             cap = M.capacity(d.size or info.size, d.tier or info.tier, "water"),
             tainted = t.tainted() == true, leaking = M.isLeaking(d) == true, frozen = M.isFrozen(d) == true,
             feeding = feeding ~= nil and feeding.obj == t.obj }
end

local function roomName(x, y, z)
    local rd = B.predefinedRoomAt(x, y, z)
    local n = rd and try(rd, "getName")
    return (type(n) == "string" and n ~= "") and n or nil
end

--- Everything the board shows that the synced entry does not carry.
function Pn.info(main, e, key)
    local info = { key = key, flow = W.flow(), reach = W.reach() }
    for _, f in ipairs({ "k", "at", "rate", "shut", "drain", "drained", "valves", "prio", "lpm", "today", "histDay" }) do info[f] = e[f] end
    if e.hist then info.hist = {} for i = 1, 24 do info.hist[i] = e.hist[i] or 0 end end
    info.day, info.hour = W.clock()
    info.status = W.status(main, e)
    local fp = W.footprint(e)
    local _, _, _, _, z0, z1 = R.fpBounds(fp)
    info.building = { kind = e.k == "s" and "structure" or "building", tiles = fp and R.fpCount(fp) or 0,
                      floors = z0 and (z1 - z0 + 1) or 0 }
    local net = Pn.network(main)
    info.tanks, info.sources = {}, {}
    for _, t in ipairs(net.tanks) do info.tanks[#info.tanks + 1] = tankRow(t, net.feeding) end
    for _, s in ipairs(net.sources) do info.sources[#info.sources + 1] = Pn.sourceRow(s.obj, s.adapter) end
    -- fixtures: the fill order first, then the ones with taps of their own
    local order = Pn.order(main, e)
    local rank = {}
    for i, k in ipairs(order) do rank[k] = i end
    local _, closed = W.squares(e.valves)
    local town = X.townWater()
    local rows, tappedRows = {}, {}
    for _, f in ipairs(W.allFixtures(main)) do
        local sq = try(f, "getSquare")
        local k = W.fixKey(f)
        if sq and k then
            local fc = try(f, "getFluidContainer")
            local own = W.tapped(f)
            local row = { x = sq:getX(), y = sq:getY(), z = sq:getZ(), kind = X.kindOf(f),
                          cap = math.max(X.capacity(f), fc and (try(fc, "getCapacity") or 0) or 0),
                          amount = math.floor(X.amount(f) * 10 + 0.5) / 10, tainted = X.tainted(f),
                          room = e.k == "b" and roomName(sq:getX(), sq:getY(), sq:getZ()) or nil,
                          closed = closed[k] == true, prio = rank[k], used = e.used and e.used[k] or nil,
                          ownTap = own, townWater = town and X.selfFed(f) }
            if own then tappedRows[#tappedRows + 1] = row else rows[#rows + 1] = row end
        end
    end
    local function byRank(a, b)
        return (a.prio or 9999) < (b.prio or 9999)
    end
    R.sort(rows, byRank)
    info.fixtures = {}
    for _, r in ipairs(rows) do if #info.fixtures < Pn.MAX_FIXTURES then info.fixtures[#info.fixtures + 1] = r end end
    for _, r in ipairs(tappedRows) do if #info.fixtures < Pn.MAX_FIXTURES then info.fixtures[#info.fixtures + 1] = r end end
    info.fixtureCount = #rows + #tappedRows
    return info
end

----------------------------------------------------------- the commands
local function changed(player, cmd, key, what)
    S.touch(W.TAG, true)
    log(player, cmd, key, what)
end

local function fixtureSquare(main, args)
    local fx, fy, fz = int(args.fx), int(args.fy), int(args.fz)
    if not (fx and fy and fz) then return nil end
    local k = NK.key(fx, fy, fz)
    for _, f in ipairs((W.fixtures(main))) do
        if W.fixKey(f) == k then return k end
    end
    return nil
end

function Pn.mainValve(player, args)
    local main, e, key = Pn.authorised(player, args)
    if not main then return end
    local k = fixtureSquare(main, args)
    if not k then return refuse(player, "IGUI_DazedPlumb_PanelNoFixture") end
    local list = W.squares(e.valves)
    local out = {}
    for _, v in ipairs(list) do if v ~= k then out[#out + 1] = v end end
    if args.closed == true then out[#out + 1] = k end
    local enc = W.encodeSquares(out)
    if enc == e.valves then return end
    e.valves = enc
    changed(player, "mainValve", key, k .. (args.closed == true and " closed" or " open"))
end

function Pn.mainPrio(player, args)
    local main, e, key = Pn.authorised(player, args)
    if not main then return end
    local k = fixtureSquare(main, args)
    if not k then return refuse(player, "IGUI_DazedPlumb_PanelNoFixture") end
    local dir = args.dir
    if dir ~= "up" and dir ~= "down" and dir ~= "top" then return end
    local order, natural = Pn.order(main, e)
    local at
    for i, v in ipairs(order) do if v == k then at = i end end
    if not at then return end
    if dir == "top" then
        table.remove(order, at)
        table.insert(order, 1, k)
    else
        local to = at + (dir == "up" and -1 or 1)
        if to < 1 or to > #order then return end
        order[at], order[to] = order[to], order[at]
    end
    local enc = nil
    if not sameList(order, natural) then enc = W.encodeSquares(order) end
    if enc == e.prio then return end
    e.prio = enc
    changed(player, "mainPrio", key, k .. " " .. dir)
end

function Pn.mainRate(player, args)
    local main, e, key = Pn.authorised(player, args)
    if not main then return end
    local r = tonumber(args.rate)
    if not r or r ~= r then return end
    local flow = W.flow()
    r = math.max(1, math.min(flow, math.floor(r + 0.5)))
    local store = (r < flow) and r or nil              -- the full line rate is the default: nothing stored
    if store == e.rate then return end
    e.rate = store
    changed(player, "mainRate", key, tostring(r))
end

function Pn.mainShut(player, args)
    local main, e, key = Pn.authorised(player, args)
    if not main then return end
    local shut = args.shut == true
    if (e.shut == true) == shut then return end
    e.shut = shut or nil
    if not shut then e.drained = nil end
    -- the line menu's pause follows (and its onSource hook finds the entry already agreeing)
    local a = L.adapters[W.ID]
    if a and L.linkOf(main, W.ID) then L.setSource(main, a, shut and "manual" or "tank") end
    if shut and e.drain then W.applyDrain(main, e) end
    changed(player, "mainShut", key, shut and "shut" or "open")
end

function Pn.mainDrain(player, args)
    local main, e, key = Pn.authorised(player, args)
    if not main then return end
    local drain = args.drain == true
    if (e.drain == true) == drain then return end
    e.drain = drain or nil
    if drain and e.shut then W.applyDrain(main, e) end
    changed(player, "mainDrain", key, drain and "on" or "off")
end

function Pn.mainMachine(player, args)
    local main, _, key = Pn.authorised(player, args)
    if not main then return end
    local mx, my, mz = int(args.mx), int(args.my), int(args.mz)
    if not (mx and my and mz) then return end
    local row, obj
    for _, s in ipairs(Pn.network(main).sources) do
        local sq = try(s.obj, "getSquare")
        if sq and sq:getX() == mx and sq:getY() == my and sq:getZ() == mz then
            obj, row = s.obj, Pn.sourceRow(s.obj, s.adapter)
            break
        end
    end
    if not obj then return refuse(player, "IGUI_DazedPlumb_PanelNoMachine") end
    local md = obj:getModData()
    local did = {}
    -- the same mutations DUP_PowerSwitch and DUP_SetFlow make
    if args.off ~= nil and row.canOff then
        local off = args.off == true
        if (md.dazedOff == true) ~= off then md.dazedOff = off or nil did[#did + 1] = off and "off" or "on" end
    end
    local flow = tonumber(args.flow)
    if flow and row.canFlow then
        for _, f in ipairs(U.FLOWS) do
            if math.abs(f - flow) < 0.001 and md.dazedFlow ~= f then md.dazedFlow = f did[#did + 1] = "flow " .. f end
        end
    end
    if #did == 0 then return end
    if obj.transmitModData then obj:transmitModData() end
    log(player, "mainMachine", key, NK.key(mx, my, mz) .. " " .. table.concat(did, " "))
end

function Pn.mainInfo(player, args)
    local main, e, key = Pn.authorised(player, args)
    if not main then return end
    CN.reply(player, W.MODULE, "mainInfo", Pn.info(main, e, key))
end

for _, c in ipairs({ "mainValve", "mainPrio", "mainRate", "mainShut", "mainDrain", "mainMachine" }) do
    local name = c
    CN.on(W.MODULE, name, function(player, args) Pn[name](player, args) end, Pn.EVERY_MS)
end
CN.on(W.MODULE, "mainInfo", function(player, args) Pn.mainInfo(player, args) end, Pn.INFO_EVERY_MS)

return Pn
