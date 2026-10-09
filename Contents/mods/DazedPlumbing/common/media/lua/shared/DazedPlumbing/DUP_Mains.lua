--[[ Dazed Utilities: Plumbing -- the WATER MAIN: a house plumbed from the outside.

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

     DazedPlumbMains = { ["x,y,z" of the main] = { k, x, y, z, id, rects, at, [panel fields] } }
       k, x, y, z, id   the core's building target (DazedCore.Buildings.encodeTargets form)
       rects            its footprint as DazedCore.Reach.encodeRects gives it
     The Main Water Panel (DUP_MainPanel, DUP_Board) adds optional fields; a missing one means the old behaviour:
       rate     house throttle, L/min, 1..MainFlow        shut     the main is shut off (feeds nothing)
       drain    empty the fixtures when shut off          drained  that drain has been done for this shut-off
       valves   closed fixture squares "x,y,z;..."        prio     fill order, fixture squares "x,y,z;..."
       lpm      litres delivered last minute              today    litres since the game day began
       hist     24 hourly litres, [hour + 1]              histDay  the day stamp hist and today belong to
       used     fixture square -> world hour it last lost water (fixtures still found only)
     SPRITES: dazedplumb_01_232..235 = facings E, S, W, N. ]]

require "DazedCore/DC_Boot"
require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Model"
require "DazedPlumbing/DUP_Links"
require "DazedPlumbing/DUP_Fixtures"
require "DazedPlumbing/DUP_Sync"

DazedPlumb.Mains = DazedPlumb.Mains or {}
local W = DazedPlumb.Mains
local P, L, X, S, M = DazedPlumb.Parts, DazedPlumb.Links, DazedPlumb.Fixtures, DazedPlumb.Sync, DazedPlumb.Model
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

-- The Dazed Utilities preset values: { easy, standard, realistic, hardcore } per option.
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
    -- not the mains table's version: the minute's figures change it, and the footprint is in the key already
    local v = S.versionOf(DazedPlumb.Pipes.KEY) .. "|" .. tostring(e.rects)
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

----------------------------------------------------------- the panel's settings
-- Fixture squares as one string, "x,y,z;x,y,z", in order: the closed valves and the fill order. A string keeps the
-- synced entry small; anything malformed in it is dropped, never fatal.
W.SQUARES_MAX = 64

--- Encode a list of square keys ("x,y,z") as one string, dropping malformed and repeated keys; nil when empty.
function W.encodeSquares(list)
    local bits, seen = {}, {}
    for _, k in ipairs(list or {}) do
        if type(k) == "string" and not seen[k] and #bits < W.SQUARES_MAX and split(k) then
            seen[k] = true
            bits[#bits + 1] = k
        end
    end
    if #bits == 0 then return nil end
    return table.concat(bits, ";")
end

--- Decode a square string: the ordered list of keys and the same keys as a set.
function W.decodeSquares(str)
    local list, set = {}, {}
    if type(str) ~= "string" or str == "" then return list, set end
    for part in string.gmatch(str, "[^;]+") do
        if not set[part] and #list < W.SQUARES_MAX and split(part) then
            set[part] = true
            list[#list + 1] = part
        end
    end
    return list, set
end

-- Decoded strings are kept per string value, so the minute tick does not parse the same settings again.
local sqCache, sqCacheN = {}, 0
local function squares(str)
    if type(str) ~= "string" then return {}, {} end
    local c = sqCache[str]
    if not c then
        if sqCacheN >= 256 then sqCache, sqCacheN = {}, 0 end
        local l, st = W.decodeSquares(str)
        c = { l, st }
        sqCache[str], sqCacheN = c, sqCacheN + 1
    end
    return c[1], c[2]
end
W.squares = squares

--- Litres a minute this house may draw: its own throttle when set, within 1 and the line rate; 0 while shut.
function W.rateOf(e)
    if e and e.shut then return 0 end
    local flow = W.flow()
    local r = e and tonumber(e.rate)
    if not r then return flow end
    return math.max(1, math.min(flow, r))
end

--- The square key of a fixture.
local function fixKey(o)
    local sq = try(o, "getSquare")
    return sq and DazedPlumb.Net.key(sq:getX(), sq:getY(), sq:getZ()) or nil
end
W.fixKey = fixKey

--- The fixtures the main feeds this minute, in fill order: the panel's priority squares first, in that order,
--  then the rest as found. Closed valves are left out.
function W.ordered(obj, e)
    e = e or W.entry(obj)
    local list = W.fixtures(obj)
    if not e or (not e.prio and not e.valves) then return list end
    local _, closed = squares(e.valves)
    local prio = squares(e.prio)
    local bySq, rest = {}, {}
    for _, f in ipairs(list) do
        local k = fixKey(f)
        if k and not closed[k] then
            bySq[k] = bySq[k] or {}
            bySq[k][#bySq[k] + 1] = f
            rest[#rest + 1] = { k = k, f = f }
        end
    end
    local out, used = {}, {}
    for _, k in ipairs(prio) do
        for _, f in ipairs(bySq[k] or {}) do out[#out + 1] = f end
        used[k] = true
    end
    for _, r in ipairs(rest) do
        if not used[r.k] then out[#out + 1] = r.f end
    end
    return out
end

----------------------------------------------------------- feeding the house
-- What each main moved this minute and what its fixtures held after the last fill: server-only, never synced.
local run = {}
W.run = run
local function runOf(key)
    local r = run[key]
    if not r then
        r = { delivered = 0, last = {} }
        run[key] = r
    end
    return r
end

--- Litres the house can take this minute, capped at its rate (nothing while shut).
function W.room(obj)
    local e = W.entry(obj)
    if not e or e.shut then return 0 end
    local room = 0
    for _, f in ipairs(W.ordered(obj, e)) do room = room + (X.room(f) or 0) end
    return math.min(room, W.rateOf(e))
end

--- Deliver up to `amount` litres around the house in fill order; returns what went in.
function W.put(obj, amount, dirty)
    local e = W.entry(obj)
    if not e or e.shut then return 0 end
    local left = math.min(amount or 0, W.rateOf(e))
    local total = 0
    for _, f in ipairs(W.ordered(obj, e)) do
        if left <= 0.001 then break end
        local got = X.put(f, left, dirty) or 0
        left, total = left - got, total + got
    end
    local key = W.keyOf(obj)
    if key and total > 0 then
        local r = runOf(key)
        r.delivered = r.delivered + total
    end
    return total
end

--- The line menu's pause and the panel's shut-off are one switch: pausing the main's line shuts it.
local function onSource(obj, source)
    if not S.authority() then return end
    local e = W.entry(obj)
    if not e then return end
    local shut = (source ~= "tank") or nil
    if e.shut ~= shut then
        e.shut = shut
        if not shut then e.drained = nil end
        S.touch(W.TAG, true)
    end
end

function W.register()
    return L.register({
        id = W.ID, supplies = "water", label = "ContextMenu_DazedPlumb_MainLine",
        match = W.isMain, room = W.room, put = W.put, onSource = onSource,
        rate = function(o) return W.rateOf(W.entry(o)) end,
    })
end
W.register()

----------------------------------------------------------- the minute's figures (authority)
W.STATS_SYNC_MINUTES = 5          -- figures alone are sent at most this often; settings go at once
W.USE_DROP = 0.5                  -- litres a fixture must lose between ticks to count as used

--- Today's stamp and the hour of the day (0-23), from the game clock.
function W.clock()
    local wh = U.worldHours()
    local gt = getGameTime and getGameTime()
    local tod = gt and try(gt, "getTimeOfDay")
    if type(tod) ~= "number" then tod = wh % 24 end
    return math.floor((wh - tod) / 24 + 0.5), math.floor(tod) % 24
end

local function round1(v) return math.floor((v or 0) * 10 + 0.5) / 10 end

-- Litres in every fed fixture, summed per square.
local function levels(obj)
    local out = {}
    for _, f in ipairs((W.fixtures(obj))) do
        local k = fixKey(f)
        if k then out[k] = (out[k] or 0) + X.amount(f) end
    end
    return out
end

--- Empty every fixture the main feeds, once per shut-off (authority). Returns the litres let out.
function W.applyDrain(obj, e)
    e = e or W.entry(obj)
    if not (S.authority() and e and e.shut and e.drain) or e.drained then return 0 end
    local out = 0
    for _, f in ipairs((W.fixtures(obj))) do out = out + X.empty(f) end
    e.drained = true
    local key = W.keyOf(obj)
    if key then runOf(key).last = levels(obj) end      -- the drain is not somebody using a tap
    S.touch(W.TAG, true)
    return out
end

-- The line menu's pause and the panel's shut-off agree: when either says paused, both do (old saves included).
local function reconcile(obj, e)
    local link = L.linkOf(obj, W.ID)
    if not link then return end
    if e.shut and link.source == "tank" then
        L.setSource(obj, L.adapters[W.ID], "manual")
    elseif not e.shut and link.source ~= "tank" then
        e.shut = true
        S.touch(W.TAG)
    end
end

--- Before the network moves water: a fixture that lost litres since the last fill was used.
function W.beforeFlow()
    if not S.authority() then return end
    local hour = math.floor(U.worldHours())
    for key, e in pairs(W.store().mains) do
        local obj = W.mainAt(key)
        local r = run[key]
        if obj and r then
            r.delivered = 0
            local now = levels(obj)
            for k, was in pairs(r.last) do
                if now[k] and was - now[k] >= W.USE_DROP then
                    e.used = e.used or {}
                    if e.used[k] ~= hour then e.used[k] = hour r.statsDirty = true end
                end
            end
        elseif obj then
            runOf(key)
        end
    end
end

--- After the network moved water: the minute's litres, today and the hour's bar, the drain and the fill levels.
function W.afterFlow()
    if not S.authority() then return end
    local day, hour = W.clock()
    local minute = math.floor(U.worldHours() * 60)
    local sendNow = false
    for key, e in pairs(W.store().mains) do
        local obj = W.mainAt(key)
        if obj then
            local r = runOf(key)
            reconcile(obj, e)
            if e.shut and e.drain and not e.drained then W.applyDrain(obj, e) end
            local got = round1(r.delivered)
            r.delivered = 0
            if e.histDay ~= day and (e.histDay ~= nil or got > 0) then
                e.histDay, e.today, e.hist = day, nil, nil
                r.statsDirty = true
            end
            if got > 0 then
                e.today = round1((e.today or 0) + got)
                e.hist = e.hist or {}
                for i = 1, 24 do e.hist[i] = e.hist[i] or 0 end
                e.hist[hour + 1] = round1(e.hist[hour + 1] + got)
                r.statsDirty = true
            end
            local lpm = got > 0 and got or nil
            if e.lpm ~= lpm then
                if (e.lpm == nil) ~= (lpm == nil) then sendNow = true end
                e.lpm = lpm
                r.statsDirty = true
            end
            -- used marks only for fixtures still found, so the table cannot outgrow the house
            if e.used then
                local known, any = {}, false
                for _, f in ipairs(W.allFixtures(obj)) do local k = fixKey(f) if k then known[k] = true end end
                for k in pairs(e.used) do if not known[k] then e.used[k] = nil r.statsDirty = true end end
                for _ in pairs(e.used) do any = true break end
                if not any then e.used = nil end
            end
            r.last = levels(obj)
            if r.statsDirty and (sendNow or minute % W.STATS_SYNC_MINUTES == 0) then
                r.statsDirty = nil
                S.touch(W.TAG)
            end
        end
    end
    -- forget the figures of mains that are gone
    for key in pairs(run) do
        if not W.store().mains[key] then run[key] = nil end
    end
end

--- Every fixture found in the footprint that still stands, tapped ones too.
function W.allFixtures(obj)
    W.fixtures(obj)
    local c = found[W.keyOf(obj) or ""]
    local out = {}
    for _, o in ipairs(c and c.all or {}) do
        if P.alive(o) then out[#out + 1] = o end
    end
    return out
end
W.tapped = tapped

----------------------------------------------------------- what the panel's lamps say
--- The tanks the main draws from, the one it points at first.
function W.tanks(obj)
    local a = L.adapters[W.ID]
    if not (a and obj) then return {}, nil end
    local st = L.status(obj, a)
    local link = L.linkOf(obj, W.ID)
    local feeding
    for _, t in ipairs(st.tanks) do
        local sq = try(t.obj, "getSquare")
        if link and link.tx and sq and sq:getX() == link.tx and sq:getY() == link.ty and sq:getZ() == link.tz then feeding = t end
    end
    return st.tanks, feeding, st
end

--- The lamps and dials for a main: { supply, demand (L/min), rationed, dry, tainted, paused, frozen, piped }.
--  Accepts the main or its registry entry (then the main is found by the entry's key).
function W.status(obj, e)
    if type(obj) == "table" and obj.rects ~= nil and e == nil then
        e = obj
        obj = nil
        for k, v in pairs(W.store().mains) do if v == e then obj = W.mainAt(k) break end end
    end
    e = e or (obj and W.entry(obj))
    local out = { supply = e and e.lpm or 0, demand = 0, rationed = false, dry = false, tainted = false,
                  paused = e ~= nil and e.shut == true, frozen = false, piped = false }
    if not (obj and e) then return out end
    local link = L.linkOf(obj, W.ID)
    if link and link.source ~= "tank" then out.paused = true end
    local want = 0
    for _, f in ipairs(W.ordered(obj, e)) do want = want + (X.room(f) or 0) end
    out.demand = math.min(want, W.flow())
    local tanks, _, st = W.tanks(obj)
    out.piped = st ~= nil and st.working == true
    local have = 0
    for _, t in ipairs(tanks) do
        local d = P.data(t.obj)
        have = have + math.max(0, t.amount())
        if t.tainted() then out.tainted = true end
        if d and M.isFrozen(d) then out.frozen = true end
    end
    out.dry = out.piped and have <= 0.001
    out.rationed = not out.paused and want > 0.001 and (want > W.rateOf(e) + 0.001 or have < math.min(want, W.rateOf(e)) - 0.001)
    return out
end

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

W.near = near

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
