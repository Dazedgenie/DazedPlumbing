--[[ Dazed Plumbing -- its tab in Dazed Control (Dazed Core 1.8.1 and later). Runs on the authority only.

     Shows the wells and pumps, the tanks, the water mains and any pipe end whose machine or tank was removed
     ("stuck links"), with admin buttons that call the mod's own functions directly:
       pumpSwitch   an electric pump on or off (ModData dazedOff, as the pump's own switch)
       wellRefill   a well's reserve back to its cap
       tankFill     a tank to capacity, clean (as the admin Fill action)
       tankEmpty    a tank to nothing
       clearLink    drop a pipe end whose device is gone, and the dead-end pipe it leaves (as Clear line does)
     Pumps and wells come from the global wells table, the links registry and the pipe ends, so they are listed
     loaded or not. Tanks have no global list: only loaded tanks and piped tanks can be listed. Anything on an
     unloaded square is shown as unloaded and is never treated as missing.
     With an older Core there is no Dazed Control and this file does nothing. ]]

if isClient and isClient() then return end

pcall(require, "DazedCore/DC_Net")
pcall(require, "DazedCore/DC_Control")
pcall(require, "DazedCore/DC_Reach")

local C = DazedCore and DazedCore.Control
local Net = DazedCore and DazedCore.Net
if not (C and C.register and Net and Net.on) then return end

for _, m in ipairs({ "DazedPlumbing/DUP_Parts", "DazedPlumbing/DUP_Pipes", "DazedPlumbing/DUP_Links",
                     "DazedPlumbing/DUP_Pumps", "DazedPlumbing/DUP_Mains", "DazedPlumbing/DUP_Fixtures",
                     "DazedPlumbing/DUP_TankFluid" }) do
    pcall(require, m)
end

DazedPlumb = DazedPlumb or {}
DazedPlumb.Control = DazedPlumb.Control or {}
local T = DazedPlumb.Control

T.MODULE = "DazedPlumbingControl"
T.CAP = 14                         -- items shown per card before "and N more"
T.MARKS_EACH = 40                  -- map marks per kind
T.REFILL_BELOW = 0.5               -- a well shows Refill once below this share of its cap
T.TYPES = { water = "Water", gas = "Petrol", propane = "Propane" }
T.SIZES = { small = "small", large = "large", xl = "XL" }
T.WHAT = { dazed_pump = "pump", dazed_main = "water main" }

local floor = math.floor

---------------------------------------------------------------- helpers

local function parts()
    local D = DazedPlumb
    return D.Parts, D.Model, D.Pipes, D.Net, D.Links, D.Pumps, D.Mains
end

local function try(obj, method, ...)
    local P = DazedPlumb.Parts
    if P and P.try then return P.try(obj, method, ...) end
    if not obj or not obj[method] then return nil end
    local ok, v = pcall(obj[method], obj, ...)
    if ok then return v end
    return nil
end

local function squareAt(x, y, z)
    local cell = getCell and getCell()
    return cell and try(cell, "getGridSquare", x, y, z) or nil
end

local function hoursNow()
    local gt = getGameTime and getGameTime()
    local h = gt and try(gt, "getWorldAgeHours")
    return type(h) == "number" and h or 0
end

-- A global table without creating it: ModData.get where the game has it.
local function globalTable(key)
    if not ModData then return nil end
    if ModData.get then
        local ok, t = pcall(ModData.get, key)
        if ok then return t end
    end
    if ModData.getOrCreate then return ModData.getOrCreate(key) end
    return nil
end

local function whole(v, lo, hi)
    return type(v) == "number" and v == floor(v) and v >= lo and v <= hi
end

-- x, y, z from a client's args, or nil when any is not a whole tile number.
local function xyz(args)
    if type(args) ~= "table" then return nil end
    local x, y, z = args.x, args.y, args.z
    if not (whole(x, -1000000, 1000000) and whole(y, -1000000, 1000000) and whole(z, -32, 64)) then return nil end
    return x, y, z
end

local function key(x, y, z) return x .. "," .. y .. "," .. z end

local function at(x, y) return string.format("%d, %d", floor(x), floor(y)) end

local function fmt(v) return tostring(floor((tonumber(v) or 0) + 0.5)) end

local TONE_RANK = { red = 1, amber = 2, blue = 3, green = 4, muted = 5 }
local function sortItems(list)
    local function less(a, b)
        local ra, rb = TONE_RANK[a.tone] or 9, TONE_RANK[b.tone] or 9
        if ra ~= rb then return ra < rb end
        return (a._k or "") < (b._k or "")
    end
    local R = DazedCore.Reach
    if R and R.sort then R.sort(list, less) else table.sort(list, less) end
    return list
end

-- The first T.CAP items, then one "and N more" row; the internal fields are dropped.
local function capped(list, what)
    local out = {}
    for i, it in ipairs(list) do
        if i > T.CAP then
            out[#out + 1] = { text = "and " .. (#list - T.CAP) .. " more " .. what, tone = "muted" }
            break
        end
        out[#out + 1] = { text = it.text, sub = it.sub, tone = it.tone, buttons = it.buttons }
    end
    return out
end

local function btn(label, command, args, danger)
    return { label = label, module = T.MODULE, command = command, args = args, danger = danger or nil }
end

-- The object on a loaded square that `test` accepts, or nil.
local function objectOn(sq, test)
    local objs = sq and try(sq, "getObjects")
    if not objs then return nil end
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        local ok, yes = pcall(test, o)
        if ok and yes then return o end
    end
    return nil
end

-- The master piece of the tank with a piece on (x, y, z), or nil (the square must be loaded).
local function tankOn(x, y, z)
    local P = DazedPlumb.Parts
    local o = P and objectOn(squareAt(x, y, z), function(obj) return P.describe(obj) ~= nil end)
    if not o then return nil end
    local m = P.master(o)
    if not P.alive(m) then return nil end
    return m
end

local function pumpOn(x, y, z)
    local U = DazedPlumb.Pumps
    return U and objectOn(squareAt(x, y, z), U.isPump) or nil
end

-- Is the device a pipe end names gone from its loaded square? Returns "gone", "unloaded", "here" or nil (unknown kind).
local function endState(e, fluid)
    local P, _, _, _, L = parts()
    local sq = squareAt(e.x, e.y, e.z)
    if not sq then return "unloaded" end
    if e.role == "tank" then
        local found = objectOn(sq, function(o)
            local info = P.describe(o)
            return info ~= nil and (fluid == nil or info.type == fluid)
        end)
        return found and "here" or "gone"
    elseif e.role == "node" then
        local n = L.nodes and L.nodes[e.id]
        if not n then return nil end
        return objectOn(sq, n.match) and "here" or "gone"
    end
    local a = L.adapters and L.adapters[e.id]
    if not a then return nil end
    local m, why = L.machineAt(e.x, e.y, e.z, a)
    if m then return "here" end
    return why
end

-- The fluid of the pipes holding an end string.
local function fluidOf(idx, s)
    local K = DazedPlumb.Pipes
    local pipes = K.pipes()
    for _, k in ipairs(idx[s] or {}) do
        local rec = pipes[k]
        if rec and rec.f then return rec.f end
    end
    return nil
end

local function raining()
    local cm = getClimateManager and getClimateManager()
    local r = cm and try(cm, "getRainIntensity")
    return type(r) == "number" and r > 0.05
end

---------------------------------------------------------------- reading the world

-- Wells and pumps. Every pump square comes from the wells table (one per pump that ever drew), the links registry
-- and the pipe ends, so pumps on unloaded ground are still listed.
local function scanPumps(idx, out)
    local P, _, _, N, L, U = parts()
    if not (U and N) then return end
    local wells = globalTable(U.WELLS)
    wells = wells and wells.wells or {}
    local now, rain = hoursNow(), raining()
    local spots = {}
    for k, w in pairs(wells) do
        if type(w) == "table" then
            out.wells = out.wells + 1
            spots[k] = true
        end
    end
    local reg = globalTable("DazedPlumbLinks")
    for _, e in pairs(reg and reg.links or {}) do
        if type(e) == "table" and e.id == U.ID and e.x then spots[key(e.x, e.y, e.z)] = true end
    end
    for s in pairs(idx) do
        local e = N.parseEnd(s)
        if e and e.id == U.ID and e.x then spots[e.key] = true end
    end
    for k in pairs(spots) do
        local x, y, z = N.split(k)
        if x and N.key(x, y, z) == k then
            local w = wells[k]
            local reserve, cap
            if type(w) == "table" then
                cap = tonumber(w.cap) or U.BASE_CAP
                reserve = U.recharged(tonumber(w.reserve) or 0, cap, now - (tonumber(w.hour) or now), rain)
            end
            if reserve and reserve < 1 then out.dryWells = out.dryWells + 1 end
            local wellText = reserve and ("well " .. fmt(reserve) .. " / " .. fmt(cap) .. " L") or "well full (not drawn yet)"
            local piped = idx[k .. "|source|" .. U.ID] ~= nil
            -- Refill is offered once a well is down to half (a full one needs nothing)
            local refill = (reserve and reserve < cap * T.REFILL_BELOW) and btn("Refill well", "wellRefill", { x = x, y = y, z = z }) or nil
            local sq = squareAt(x, y, z)
            local item = { x = x, y = y, z = z, _k = k, buttons = {} }
            local pump = sq and pumpOn(x, y, z)
            if sq and not pump and not w then
                item = nil                     -- a pipe end or a link with no pump and no well: the stuck list has it
            elseif not sq then
                item.text = "Pump at " .. at(x, y)
                item.sub = "unloaded - " .. wellText .. (piped and ", piped" or "")
                item.tone = "muted"
            else
                local info = pump and U.describe(pump)
                if not info then
                    item.text = "Well at " .. at(x, y)
                    item.sub = "no pump here - " .. wellText
                    item.tone = "muted"
                elseif info.kind == "electric" then
                    local off = U.isOff(pump)
                    local powered = U.powered(pump)
                    local state
                    if off then state, item.tone = "switched off", "amber"
                    elseif not powered then state, item.tone = "no power", "amber"
                    else state, item.tone = fmt(U.flowRate(pump)) .. " L/min", "green" end
                    item.text = "Electric pump at " .. at(x, y)
                    item.sub = state .. ", flow " .. fmt(U.flow(pump) * 100) .. "% - " .. wellText .. (piped and "" or ", not piped")
                    item.buttons[#item.buttons + 1] = off and btn("On", "pumpSwitch", { x = x, y = y, z = z, on = true })
                        or btn("Off", "pumpSwitch", { x = x, y = y, z = z, on = false })
                else
                    item.text = "Hand pump at " .. at(x, y)
                    item.sub = U.STROKE .. " L a stroke - " .. wellText .. (piped and "" or ", not piped")
                    item.tone = "green"
                end
                if info and reserve and reserve < 1 then item.tone = "red" end
            end
            if item then
                if refill then item.buttons[#item.buttons + 1] = refill end
                out.pumps[#out.pumps + 1] = item
            end
        end
    end
end

local function tankItem(master)
    local P, M = parts()
    local d = P.data(master)
    local sq = try(master, "getSquare")
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local cap = M.capacity(d.size, d.tier, d.type)
    local unit = M.UNIT[d.type] or "L"
    local amount = d.amount or 0
    local state, tone
    if d.type == "water" then
        if M.isTainted(d) then state, tone = "tainted", "amber" else state, tone = "clean", "green" end
    else
        state, tone = string.lower(T.TYPES[d.type] or tostring(d.type)), "green"
    end
    if amount <= 0.0001 then state, tone = "empty", "muted" end
    local flags = {}
    if d.cracked then flags[#flags + 1] = "cracked" tone = "red" end
    if M.isFrozen(d) then flags[#flags + 1] = "frozen" if tone ~= "red" then tone = "blue" end end
    if M.isLeaking(d) and not d.cracked then flags[#flags + 1] = "leaking" if tone == "green" then tone = "amber" end end
    local name = (type(d.name) == "string" and d.name ~= "") and d.name
        or ((T.TYPES[d.type] or "?") .. " tank, " .. (T.SIZES[d.size] or tostring(d.size)))
    local buttons = {}
    local args = { x = x, y = y, z = z }
    if amount < cap - 0.5 then buttons[#buttons + 1] = btn("Fill", "tankFill", args) end
    if amount > 0.0001 then buttons[#buttons + 1] = btn("Empty", "tankEmpty", { x = x, y = y, z = z }, true) end
    return {
        x = x, y = y, z = z, _k = key(x, y, z), tone = tone, buttons = buttons,
        text = name .. " at " .. at(x, y),
        sub = fmt(amount) .. " / " .. fmt(cap) .. " " .. unit .. " " .. state .. (#flags > 0 and (", " .. table.concat(flags, ", ")) or ""),
    }
end

-- Tanks: every loaded one (the world's register), then every piped one. Pipe ends whose device is gone are stuck.
local function scanTanksAndEnds(idx, out)
    local P, _, _, N = parts()
    local seen = {}
    local world = DazedPlumb.World
    for obj in pairs(world and world.tanks or {}) do
        if P.alive(obj) then
            local m = P.master(obj)
            local sq = P.alive(m) and try(m, "getSquare")
            local k = sq and key(sq:getX(), sq:getY(), sq:getZ())
            if k and not seen[k] then
                seen[k] = true
                out.loadedTanks = out.loadedTanks + 1
                local ok, item = pcall(tankItem, m)
                if ok then out.tanks[#out.tanks + 1] = item end
            end
        end
    end
    local Wn = DazedPlumb.Mains
    for s in pairs(idx) do
        local e = N.parseEnd(s)
        if e and e.x then
            local fluid = fluidOf(idx, s)
            local st = endState(e, fluid)
            if st == "gone" then
                local what = e.role == "tank" and "tank" or T.WHAT[e.id] or e.id
                out.stuck[#out.stuck + 1] = { x = e.x, y = e.y, z = e.z, _k = s, tone = "red",
                    text = "Pipe end at " .. at(e.x, e.y),
                    sub = "linked to a removed " .. tostring(what),
                    buttons = { btn("Clear link", "clearLink", { x = e.x, y = e.y, z = e.z, role = e.role, id = e.id }, true) } }
            elseif e.role == "tank" then
                local m = st == "here" and tankOn(e.x, e.y, e.z)
                local msq = m and try(m, "getSquare")
                local k = msq and key(msq:getX(), msq:getY(), msq:getZ()) or e.key
                if not seen[k] then
                    seen[k] = true
                    if m then
                        out.loadedTanks = out.loadedTanks + 1
                        local ok, item = pcall(tankItem, m)
                        if ok then out.tanks[#out.tanks + 1] = item end
                    elseif st == "unloaded" then
                        out.tanks[#out.tanks + 1] = { x = e.x, y = e.y, z = e.z, _k = e.key, tone = "muted",
                            text = (T.TYPES[fluid or ""] or "Piped") .. " tank at " .. at(e.x, e.y),
                            sub = "unloaded, piped" }
                    end
                end
            elseif Wn and e.role == "sink" and e.id == Wn.ID and st == "here" then
                local entry = Wn.store().mains[e.key]
                if not entry then
                    out.mains[#out.mains + 1] = { x = e.x, y = e.y, z = e.z, _k = e.key, tone = "amber",
                        text = "Water main at " .. at(e.x, e.y), sub = "piped, not connected to a building" }
                end
            end
        end
    end
end

local function scanMains(idx, out)
    local W = DazedPlumb.Mains
    if not W then return end
    local N = DazedPlumb.Net
    for k, e in pairs(W.store().mains) do
        local x, y, z = N.split(k)
        if x and type(e) == "table" then
            local main, why = W.mainAt(k)
            local item = { x = x, y = y, z = z, _k = k, text = "Water main at " .. at(x, y) }
            local house = "building " .. tostring(e.id or "?")
            if main then
                local piped = idx[k .. "|sink|" .. W.ID] ~= nil
                local ok, _, total = pcall(W.fixtures, main)
                local fx = ok and tonumber(total) and (", " .. floor(total) .. " fixtures") or ""
                item.sub = "feeds " .. house .. fx .. (piped and " - ok" or " - not piped")
                item.tone = piped and "green" or "amber"
            elseif why == "gone" then
                item.sub = house .. " - main removed, dropped within a minute"
                item.tone = "red"
            else
                item.sub = "feeds " .. house .. " - unloaded"
                item.tone = "muted"
            end
            out.mains[#out.mains + 1] = item
        end
    end
end

--- Everything the tab shows, read from the authority's state. Cached for half a second so the view and the
--  map marks of one refresh share it; every command clears it.
local cache = { at = nil, data = nil }
function T.forget() cache.at, cache.data = nil, nil end

function T.scan()
    local nowMs = getTimestampMs and getTimestampMs() or nil
    if cache.data and nowMs and cache.at and nowMs >= cache.at and nowMs - cache.at < 500 then return cache.data end
    local out = { pumps = {}, tanks = {}, mains = {}, stuck = {}, wells = 0, dryWells = 0, loadedTanks = 0 }
    local P, _, K = parts()
    if P and K and DazedPlumb.Net and DazedPlumb.Links then
        local idx = K.index() or {}
        local steps = { scanPumps, scanTanksAndEnds, scanMains }
        for _, fn in ipairs(steps) do
            local ok, err = pcall(fn, idx, out)
            if not ok then print("DazedPlumbing: control tab scan failed: " .. tostring(err)) end
        end
    end
    sortItems(out.pumps)
    sortItems(out.tanks)
    sortItems(out.mains)
    sortItems(out.stuck)
    cache.at, cache.data = nowMs, out
    return out
end

local function townWater()
    local X = DazedPlumb.Fixtures
    if not (X and X.townWater) then return nil end
    local ok, on = pcall(X.townWater)
    return ok and on == true
end

---------------------------------------------------------------- the tab

function T.view()
    local s = T.scan()
    local town = townWater()
    local mainsItems = {}
    for _, it in ipairs(s.stuck) do mainsItems[#mainsItems + 1] = it end
    for _, it in ipairs(s.mains) do mainsItems[#mainsItems + 1] = it end
    local pumps = capped(s.pumps, "pumps")
    if #pumps == 0 then pumps = { { text = "No pumps or wells yet", tone = "muted" } } end
    local tanks = capped(s.tanks, "tanks")
    if #tanks == 0 then tanks = { { text = "No loaded or piped tanks", tone = "muted" } } end
    local links = capped(mainsItems, "mains and links")
    if #links == 0 then links = { { text = "No water mains, no stuck links", tone = "muted" } } end
    return {
        lamps = {
            { town and "Town water on" or "Town water off", town and "green" or "off" },
            { "Wells: " .. s.wells, s.dryWells > 0 and "amber" or (s.wells > 0 and "green" or "off") },
            { "Tanks loaded: " .. s.loadedTanks, s.loadedTanks > 0 and "green" or "off" },
            { "Stuck links: " .. #s.stuck, #s.stuck > 0 and "red" or "green" },
        },
        cards = {
            { title = "Wells and pumps", items = pumps },
            { title = "Tanks", items = tanks,
              lines = { "Only loaded tanks and piped tanks are listed: an unpiped tank in an unloaded area cannot be seen." } },
            { title = "Mains and links", items = links },
        },
    }
end

function T.marks()
    local s = T.scan()
    local out = {}
    local function add(list, prefix, limit)
        local n = 0
        for _, it in ipairs(list) do
            if it.x and it.y then
                n = n + 1
                if n > limit then break end
                out[#out + 1] = { x = it.x, y = it.y, label = prefix .. it.text, tone = it.tone }
            end
        end
    end
    add(s.stuck, "Stuck: ", T.MARKS_EACH)
    add(s.pumps, "", T.MARKS_EACH)
    add(s.tanks, "", T.MARKS_EACH)
    add(s.mains, "", T.MARKS_EACH)
    return out
end

C.register("plumbing", {
    title = "Plumbing",
    order = 50,
    commands = {
        [T.MODULE .. ".pumpSwitch"] = "admin",
        [T.MODULE .. ".wellRefill"] = "admin",
        [T.MODULE .. ".tankFill"] = "admin",
        [T.MODULE .. ".tankEmpty"] = "admin",
        [T.MODULE .. ".clearLink"] = "admin",
    },
    view = T.view,
    marks = T.marks,
})

---------------------------------------------------------------- the commands (admin only, re-checked here)

local function admin(player) return C.atLeast(C.level(player), "admin") end

local function handler(command, fn)
    Net.on(T.MODULE, command, function(player, args)
        if not admin(player) then return end
        T.forget()
        fn(args)
    end, 250)
end
T.handler = handler

-- An electric pump on or off, as its own switch does.
handler("pumpSwitch", function(args)
    local x, y, z = xyz(args)
    if not x or type(args.on) ~= "boolean" then return end
    local U, P = DazedPlumb.Pumps, DazedPlumb.Parts
    local pump = pumpOn(x, y, z)
    local info = pump and U.describe(pump)
    if not (info and info.kind == "electric" and P.alive(pump)) then return end
    pump:getModData().dazedOff = (not args.on) or nil
    P.transmit(pump)
end)

-- A well back to full. Only a well the table already holds (one never drawn from is full anyway).
handler("wellRefill", function(args)
    local x, y, z = xyz(args)
    if not x then return end
    local U = DazedPlumb.Pumps
    local wells = U and ModData and ModData.getOrCreate(U.WELLS)
    local w = wells and wells.wells and wells.wells[key(x, y, z)]
    if type(w) ~= "table" then return end
    local cap = tonumber(w.cap)
    if not cap or cap <= 0 then return end
    w.reserve, w.hour = cap, hoursNow()
    DazedPlumb.Sync.touch(U.WELLS)
end)

local function reconcile(obj)
    local TF = DazedPlumb.TankFluid
    if TF and TF.reconcile then pcall(TF.reconcile, obj) end
end

-- A tank to capacity, clean, as the admin Fill action does.
handler("tankFill", function(args)
    local x, y, z = xyz(args)
    if not x then return end
    local P, M = DazedPlumb.Parts, DazedPlumb.Model
    local m = tankOn(x, y, z)
    if not m then return end
    reconcile(m)
    local d = P.data(m)
    d.amount = M.capacity(d.size, d.tier, d.type)
    d.dirty = nil
    P.transmit(m)
    reconcile(m)
end)

-- A tank to nothing.
handler("tankEmpty", function(args)
    local x, y, z = xyz(args)
    if not x then return end
    local P = DazedPlumb.Parts
    local m = tankOn(x, y, z)
    if not m then return end
    reconcile(m)
    local d = P.data(m)
    d.amount = 0
    d.dirty = nil
    P.transmit(m)
    reconcile(m)
end)

local ROLES = { tank = true, sink = true, source = true, node = true }

-- Drop a pipe end whose device is gone from its loaded square, and the dead-end pipe it leaves, as Clear line
-- does for a machine that is still there. Refused while the device is there or its square is unloaded.
handler("clearLink", function(args)
    local x, y, z = xyz(args)
    if not x or not ROLES[args.role] then return end
    local id = args.id
    if type(id) ~= "string" or id == "" or #id > 64 or string.find(id, "|", 1, true) then return end
    local K, N = DazedPlumb.Pipes, DazedPlumb.Net
    local idx = K.index() or {}
    local s = N.endString(N.key(x, y, z), args.role, id)
    if not idx[s] then return end
    local e = N.parseEnd(s)
    if not e or endState(e, fluidOf(idx, s)) ~= "gone" then return end
    K.disconnect(s)
    if args.role ~= "tank" then
        local reg = ModData and ModData.getOrCreate("DazedPlumbLinks")
        if reg and reg.links then reg.links[N.key(x, y, z) .. "|" .. id] = nil end
    end
end)

return T
