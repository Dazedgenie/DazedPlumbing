--[[ Dazed Plumbing -- the WATER MAIN: a house plumbed from the outside.

     A water main stands outdoors beside a building and is piped to the network like any machine
     (it is a link SINK that takes water). Right-click -> Connect a building... opens the core's
     Building Picker; the chosen house (or player-built structure) is remembered in the global
     table DazedPlumbMains, synced to clients. Every minute the network tops up every water
     fixture inside that footprint, as a tap would, up to the main's line rate. A fixture with a
     tap of its own keeps its tap. While the town supply still runs the fixtures are endless
     anyway and nothing is moved. A tank run dry means dry taps; a tainted tank, tainted taps.

       reach   the main must stand within MainReach squares of the footprint (sandbox, 6)
       rate    MainFlow litres a minute for the whole house (sandbox, 30)
       one main serves one building; one building takes one main

     DazedPlumbMains = { ["x,y,z" of the main] = { k, x, y, z, id, rects, at } }
       k, x, y, z, id   the core's building target (DazedCore.Buildings.encodeTargets form)
       rects            its footprint as DazedCore.Reach.encodeRects gives it
     SPRITES: dazedplumb_01_232..235 = facings E, S, W, N. ]]

require "DazedCore/DC_Boot"
require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Links"
require "DazedPlumbing/DUP_Fixtures"
require "DazedPlumbing/DUP_Sync"

DazedPlumb.Mains = DazedPlumb.Mains or {}
local W = DazedPlumb.Mains
local P, L, X, S = DazedPlumb.Parts, DazedPlumb.Links, DazedPlumb.Fixtures, DazedPlumb.Sync
local B, R, U, N = DazedCore.Buildings, DazedCore.Reach, DazedCore.Util, DazedCore.Note
local try = P.try

W.BASE = 232
W.COUNT = 4
W.FACINGS = { "E", "S", "W", "N" }
W.ITEM = "Base.DazedWaterMain"
W.ID = "dazed_main"
W.TAG = "DazedPlumbMains"
W.MODULE = "DazedPlumb"
W.BAND = 3                       -- floors above and below the main it may reach the footprint on
W.DEFAULT_REACH, W.DEFAULT_FLOW = 6, 30

-- The Dazed Core preset values: { easy, standard, realistic, hardcore } per option.
W.PRESETS = { NeedWrench = { false, true, true, true }, MainReach = { 8, 6, 6, 4 }, MainFlow = { 40, 30, 20, 15 } }
if DazedCore and DazedCore.Preset then DazedCore.Preset.register("DazedPlumb", W.PRESETS) end

----------------------------------------------------------- sprites and sandbox
function W.sprite(facing)
    for i, f in ipairs(W.FACINGS) do
        if f == facing then return P.TILESET .. "_" .. (W.BASE + i - 1) end
    end
end

function W.spriteInfo(name)
    local idx = P.indexOf(name)
    if not idx or idx < W.BASE or idx >= W.BASE + W.COUNT then return nil end
    return { facing = W.FACINGS[idx - W.BASE + 1] }
end

function W.isMain(obj)
    local spr = obj and try(obj, "getSprite")
    return spr ~= nil and W.spriteInfo(try(spr, "getName")) ~= nil
end

function W.allItems() return { W.ITEM } end

--- Squares a main may stand from the building (sandbox).
function W.reach()
    local v = tonumber(U.sandbox("DazedPlumb", "MainReach", W.DEFAULT_REACH))
    return math.max(1, math.min(30, math.floor((v or W.DEFAULT_REACH) + 0.5)))
end

--- Litres a minute one main delivers to its house (sandbox).
function W.flow()
    local v = tonumber(U.sandbox("DazedPlumb", "MainFlow", W.DEFAULT_FLOW))
    return math.max(1, v or W.DEFAULT_FLOW)
end

----------------------------------------------------------- the registry
function W.store()
    local t = ModData.getOrCreate(W.TAG)
    t.mains = t.mains or {}
    return t
end

function W.keyOf(obj)
    local sq = try(obj, "getSquare")
    if not sq then return nil end
    return DazedPlumb.Net.key(sq:getX(), sq:getY(), sq:getZ())
end

--- The building a main serves, or nil.
function W.entry(obj)
    local k = W.keyOf(obj)
    return k and W.store().mains[k] or nil
end

--- The main serving a building id, as its registry key, or nil.
function W.servedBy(id, skipKey)
    for k, e in pairs(W.store().mains) do
        if e.id == id and k ~= skipKey then return k end
    end
    return nil
end

-- Footprints decoded once per rects string.
local fpCache = {}
function W.footprint(e)
    if not (e and e.rects) then return nil end
    local c = fpCache[e.rects]
    if not c then
        c = R.fpOfRects(R.decodeRects(e.rects))
        fpCache[e.rects] = c
    end
    return c
end

--- The square the main stands on, from a registry key.
local function split(key)
    if type(key) ~= "string" then return nil end
    local x, y, z = DazedPlumb.Net.split(key)
    if x and DazedPlumb.Net.key(x, y, z) == key then return x, y, z end   -- whole keys only, as before
    return nil
end

--- The main at a registry key, or nil and "gone" (square loaded, nothing there) / "unloaded".
function W.mainAt(key)
    local x, y, z = split(key)
    local sq = x and U.squareAt(x, y, z)
    if not sq then return nil, "unloaded" end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if W.isMain(o) then return o end
    end
    return nil, "gone"
end

----------------------------------------------------------- connecting (authority)
--- Does a main at (x, y, z) reach a footprint?
function W.reaches(fp, x, y, z)
    return B.reaches(fp, x, y, z, W.reach(), W.BAND)
end

--- Connect the main to the building under (sx, sy, sz). Returns true, or false and a note key.
function W.connect(obj, sx, sy, sz)
    if not S.authority() then return false end
    local key = W.keyOf(obj)
    if not key then return false, "IGUI_DazedPlumb_MainGone" end
    local t = B.targetAt(sx, sy, sz)
    if not t then return false, "IGUI_DazedPlumb_MainNoBuilding" end
    local mains = W.store().mains
    local cur = mains[key]
    if cur and cur.id == t.id then return W.disconnect(obj) end           -- a second click takes it away
    local fp = B.footprintOf(t)
    local x, y, z = split(key)
    if not (fp and W.reaches(fp, x, y, z)) then return false, "IGUI_DazedPlumb_MainFar" end
    if W.servedBy(t.id, key) then return false, "IGUI_DazedPlumb_MainTaken" end
    mains[key] = { k = t.k, x = t.x, y = t.y, z = t.z, id = t.id, rects = R.encodeRects(R.rectsOf(fp)),
                   at = U.worldHours() }
    S.touch(W.TAG, true)
    return true, "IGUI_DazedPlumb_MainConnected"
end

function W.disconnect(obj)
    if not S.authority() then return false end
    local key = W.keyOf(obj)
    if not (key and W.store().mains[key]) then return false end
    W.store().mains[key] = nil
    S.touch(W.TAG, true)
    return true, "IGUI_DazedPlumb_MainDisconnected"
end

--- Drop entries whose main is gone (square loaded, no main there). Once a minute.
function W.housekeep()
    if not S.authority() then return end
    local drop = {}
    for key in pairs(W.store().mains) do
        local m, why = W.mainAt(key)
        if not m and why == "gone" then drop[#drop + 1] = key end
    end
    for _, k in ipairs(drop) do W.store().mains[k] = nil end
    if #drop > 0 then S.touch(W.TAG) end
end

----------------------------------------------------------- the fixtures it feeds
--- Is this fixture fed by a tap line of its own? Then the main leaves it alone.
local function tapped(obj)
    local link = L.linkOf(obj, X.ID)
    return link ~= nil and link.source == "tank" and link.tx ~= nil
end

-- The fixtures in a main's footprint are looked for again when the pipes or the mains change, else every
-- FIXTURE_REFRESH_MINUTES; between looks each minute only checks the found ones still stand and have no tap.
W.FIXTURE_REFRESH_MINUTES = 10
local found = {}

-- Every loaded fixture standing in a footprint.
local function scanFootprint(fp)
    local all = {}
    for z, set in pairs(fp.levels) do
        for sk in pairs(set) do
            local x, y = R.sqXY(sk)
            local sq = U.squareAt(x, y, z)
            if sq then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    if X.isFixture(o) then all[#all + 1] = o end
                end
            end
        end
    end
    return all
end

function W.fixtures(obj)
    local key = W.keyOf(obj)
    local e = key and W.store().mains[key]
    if not e then return {}, 0 end
    local minute = math.floor(U.worldHours() * 60)
    local v = S.versionOf(DazedPlumb.Pipes.KEY) .. "|" .. S.versionOf(W.TAG) .. "|" .. tostring(e.rects)
    local c = found[key]
    if c and c.v == v and c.minute == minute then return c.list, c.total end
    if not c or c.v ~= v or minute < c.at or minute - c.at >= W.FIXTURE_REFRESH_MINUTES then
        local fp = W.footprint(e)
        c = { v = v, at = minute, all = fp and scanFootprint(fp) or {} }
        found[key] = c
    end
    local list, total = {}, 0
    for _, o in ipairs(c.all) do
        if P.alive(o) then
            total = total + 1
            if not tapped(o) then list[#list + 1] = o end
        end
    end
    c.minute, c.list, c.total = minute, list, total
    return list, total
end

--- Litres the house can take this minute, capped at the line rate.
function W.room(obj)
    local list = W.fixtures(obj)
    local room = 0
    for _, f in ipairs(list) do room = room + (X.room(f) or 0) end
    return math.min(room, W.flow())
end

--- Deliver up to `amount` litres around the house; returns what went in.
function W.put(obj, amount, dirty)
    local left = math.min(amount or 0, W.flow())
    local total = 0
    for _, f in ipairs((W.fixtures(obj))) do
        if left <= 0.001 then break end
        local got = X.put(f, left, dirty) or 0
        left, total = left - got, total + got
    end
    return total
end

function W.register()
    return L.register({
        id = W.ID, supplies = "water", label = "ContextMenu_DazedPlumb_MainLine",
        match = W.isMain, room = W.room, put = W.put,
        rate = function() return W.flow() end,
    })
end
W.register()

----------------------------------------------------------- the picker's commands
-- A client's click, or Remove all, goes to the authority through the core's command layer
-- (single player runs it at once). A pick is a toggle, so repeats from one player inside half a second are dropped.
W.PICK_EVERY_MS = 500

function W.send(player, cmd, args)
    return DazedCore.Net.send(player, W.MODULE, cmd, args)
end

-- The player stands within the main's reach (plus two) of it, no more than BAND floors away.
local function near(player, x, y, z)
    if not DazedCore.Net.near(player, x, y, nil, W.reach() + 2) then return false end
    local pz = try(player, "getZ")
    return type(pz) == "number" and type(z) == "number" and math.abs(pz - z) <= W.BAND
end

--- Run one of the picker's commands for a player (authority).
function W.onCommand(module, cmd, player, args)
    if module ~= W.MODULE or type(args) ~= "table" then return end
    if cmd ~= "mainPick" and cmd ~= "mainClear" then return end
    if not S.authority() then return end
    local key = args.x and (args.x .. "," .. args.y .. "," .. args.z)
    local main = key and W.mainAt(key)
    if not main or not near(player, args.x, args.y, args.z) then
        N.say(player, "IGUI_DazedPlumb_MainGone", nil, true)
        return
    end
    local ok, note
    if cmd == "mainPick" then ok, note = W.connect(main, args.sx, args.sy, args.sz)
    else ok, note = W.disconnect(main) end
    if note then N.say(player, note, nil, not ok) end
end

DazedCore.Net.on(W.MODULE, "mainPick", function(player, args) W.onCommand(W.MODULE, "mainPick", player, args) end, W.PICK_EVERY_MS)
DazedCore.Net.on(W.MODULE, "mainClear", function(player, args) W.onCommand(W.MODULE, "mainClear", player, args) end)

return W
