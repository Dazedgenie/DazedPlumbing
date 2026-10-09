--[[ Dazed Utilities: Plumbing -- the biogas digester: hand-fed rotten food and manure make propane for a piped tank (a link SOURCE of "propane", no power).
     State is flat numbers in ModData `dazedDigester` { waste, buf, hour }; sprites are dazedplumb_01_244..247 (facings E, S, W, N). ]]

require "DazedCore/DC_Boot"
require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Links"
require "DazedPlumbing/DUP_Sync"
require "DazedPlumbing/DUP_FuelPumps"

DazedPlumb.Digesters = DazedPlumb.Digesters or {}
local Dg = DazedPlumb.Digesters
local P, L = DazedPlumb.Parts, DazedPlumb.Links
local try = P.try
local min, max = math.min, math.max

Dg.BASE = DazedPlumb.FuelPumps.BASE + DazedPlumb.FuelPumps.COUNT
Dg.COUNT = 4
Dg.FACINGS = { "E", "S", "W", "N" }
Dg.ITEM = "Base.DazedDigester"
Dg.ID = "dazed_digester"
Dg.KEY = "dazedDigester"

Dg.SLURRY_CAP = 40               -- units of waste the drum holds
Dg.GAS_PER_UNIT = 0.05           -- kg of propane one unit makes in all
Dg.DIGEST_HOURS = 24             -- mean in-game hours a unit takes
Dg.BUF_CAP = 2                   -- kg of gas held while the tank is full
Dg.MAX_CATCHUP_HOURS = 48        -- most hours settled at once after an absence
Dg.COLD_BELOW, Dg.FROZEN_BELOW, Dg.COLD_FACTOR = 10, 0, 0.5
Dg.RESIDUE = 0.005               -- slurry below this many units is swept up as digested
Dg.EPS = 1e-4
Dg.UNITS = { food = 1, dung = 2, compost = 2 }
Dg.COMPOST_ITEM = "Base.CompostBag"     -- a drainable: one use is one add

----------------------------------------------------------- sprites
function Dg.sprite(facing)
    for i, f in ipairs(Dg.FACINGS) do
        if f == facing then return P.TILESET .. "_" .. (Dg.BASE + i - 1) end
    end
end

--- {facing} for a digester sprite name, or nil.
function Dg.spriteInfo(name)
    local idx = type(name) == "string" and string.match(name, "^" .. P.TILESET .. "_(%d+)$")
    idx = idx and tonumber(idx)
    if not idx or idx < Dg.BASE or idx >= Dg.BASE + Dg.COUNT then return nil end
    return { facing = Dg.FACINGS[idx - Dg.BASE + 1] }
end

function Dg.isDigester(obj)
    local spr = obj and try(obj, "getSprite")
    return spr ~= nil and Dg.spriteInfo(try(spr, "getName")) ~= nil
end

function Dg.allItems() return { Dg.ITEM } end

----------------------------------------------------------- the model (pure)
--- Share of full speed at an air temperature in degrees C (unknown counts as warm).
function Dg.tempFactor(t)
    if type(t) ~= "number" then return 1 end
    if t < Dg.FROZEN_BELOW then return 0 end
    if t < Dg.COLD_BELOW then return Dg.COLD_FACTOR end
    return 1
end

--- Let `hours` pass on `waste` units of slurry at speed `factor`, with `room` kg left in the gas buffer.
--  Returns the units digested and the kg of gas they made.
function Dg.digest(waste, hours, factor, room)
    waste = max(0, waste or 0)
    local eff = max(0, hours or 0) * max(0, factor or 0)
    if waste <= 0 or eff <= 0 then return 0, 0 end
    local digested = waste * (1 - math.exp(-eff / Dg.DIGEST_HOURS))
    if waste - digested < Dg.RESIDUE then digested = waste end
    local gas = digested * Dg.GAS_PER_UNIT
    if room ~= nil and gas > max(0, room) then
        gas = max(0, room)
        digested = gas / Dg.GAS_PER_UNIT
    end
    return digested, gas
end

--- Kg of propane an hour that `waste` units make at speed `factor`, right now.
function Dg.rate(waste, factor)
    return max(0, waste or 0) * (1 / Dg.DIGEST_HOURS) * Dg.GAS_PER_UNIT * max(0, factor or 0)
end

--- Room left for waste, in units.
function Dg.room(waste) return max(0, Dg.SLURRY_CAP - max(0, waste or 0)) end

----------------------------------------------------------- state
local worldHours = DazedCore.Util.worldHours

--- The digester's state table, defaulted and kept in range. A new one starts empty, settled now.
function Dg.state(obj)
    local md = obj:getModData()
    local st = md[Dg.KEY]
    if type(st) ~= "table" then
        st = { waste = 0, buf = 0, hour = worldHours() }
        md[Dg.KEY] = st
    end
    st.waste = min(Dg.SLURRY_CAP, max(0, tonumber(st.waste) or 0))
    st.buf = min(Dg.BUF_CAP, max(0, tonumber(st.buf) or 0))
    return st
end

--- The air temperature at the machine in degrees C, or nil when the engine cannot say.
function Dg.tempAt(obj)
    local cm = getClimateManager and getClimateManager()
    if not cm then return nil end
    local sq = obj and try(obj, "getSquare")
    local t = sq and try(cm, "getAirTemperatureForSquare", sq)
    if type(t) ~= "number" then t = try(cm, "getTemperature") end
    return type(t) == "number" and t or nil
end

--- Settle the hours since the digester was last settled (at most MAX_CATCHUP_HOURS). Authority only.
--  Returns true when it made gas.
function Dg.settle(obj, now, temp)
    local st = Dg.state(obj)
    now = now or worldHours()
    local last = st.hour
    st.hour = now
    if type(last) ~= "number" then return false end
    local gap = min(now - last, Dg.MAX_CATCHUP_HOURS)
    if gap <= 0 then return false end
    local d, gas = Dg.digest(st.waste, gap, Dg.tempFactor(temp), Dg.BUF_CAP - st.buf)
    st.waste = max(0, st.waste - d)
    st.buf = min(Dg.BUF_CAP, st.buf + gas)
    return gas > 0
end

-- What each machine last showed the clients, so the minute tick sends only visible changes.
local shown = setmetatable({}, { __mode = "k" })

--- Tell the clients when what the menu shows has changed.
function Dg.publish(obj)
    local st = Dg.state(obj)
    local key = string.format("%.1f|%.2f", st.waste, st.buf)
    if shown[obj] == key then return end
    shown[obj] = key
    if obj.transmitModData then obj:transmitModData() end
end

--- Bring a digester up to date with the clock (authority only) and publish it.
function Dg.refresh(obj)
    Dg.settle(obj, nil, Dg.tempAt(obj))
    Dg.publish(obj)
end

----------------------------------------------------------- the live registry and tick
Dg.live = Dg.live or setmetatable({}, { __mode = "k" })

function Dg.register(obj)
    if obj then Dg.live[obj] = true end
end

local alive = P.alive

--- Settle every loaded digester (authority only). A lifted or broken one drops out.
function Dg.tick()
    if not DazedPlumb.Sync.authority() then return end
    for obj in pairs(Dg.live) do
        if not alive(obj) then
            Dg.live[obj] = nil
        else
            local ok, err = pcall(Dg.refresh, obj)
            if not ok then
                print("DazedPlumbing: digester tick failed: " .. tostring(err))
                Dg.live[obj] = nil
            end
        end
    end
end

----------------------------------------------------------- what may be added
local function isFood(item)
    if instanceof and instanceof(item, "Food") then return true end
    return false
end

--- Is this food rotten (or spoiled)? Every engine call is guarded; unknown counts as not rotten.
function Dg.rotten(item)
    if try(item, "isRotten") == true or try(item, "isSpoiled") == true then return true end
    local age, off = try(item, "getAge"), try(item, "getOffAgeMax")
    return type(age) == "number" and type(off) == "number" and off > 0 and off < 1e8 and age >= off
end

--- What an item is as waste: "dung", "compost" or "food" and its units, or nil when it is not waste.
function Dg.classify(item)
    local ft = item and try(item, "getFullType")
    if type(ft) ~= "string" then return nil end
    local name = string.match(ft, "%.(.+)$") or ft
    if ft == Dg.COMPOST_ITEM then
        local uses = try(item, "getCurrentUses")
        if type(uses) == "number" and uses <= 0 then return nil end
        return "compost", Dg.UNITS.compost
    end
    if string.find(name, "^Dung") or string.find(name, "Manure") or string.find(name, "Droppings") then
        return "dung", Dg.UNITS.dung
    end
    if isFood(item) and Dg.rotten(item) then return "food", Dg.UNITS.food end
    return nil
end

--- Take one unit of waste item out of the pack (a use of a compost bag). Returns true when it went.
function Dg.consume(item, kind)
    if kind == "compost" then
        local before = try(item, "getCurrentUses")
        local called = false
        for _, m in ipairs({ "UseAndSync", "Use" }) do
            if type(item[m]) == "function" and pcall(item[m], item) then called = true break end
        end
        if not called then return false end
        local after = try(item, "getCurrentUses")
        return not (type(before) == "number" and type(after) == "number" and after >= before)
    end
    local cont = try(item, "getContainer")
    if not cont then return false end
    if not pcall(cont.Remove, cont, item) then return false end
    if sendRemoveItemFromContainer then pcall(sendRemoveItemFromContainer, cont, item) end
    return true
end

--- Feed one item to the digester (authority). Returns the units added, or 0 and a reason: "bad" or "full".
function Dg.add(obj, item)
    local kind, units = Dg.classify(item)
    if not kind then return 0, "bad" end
    local st = Dg.state(obj)
    if Dg.room(st.waste) < units - Dg.EPS then return 0, "full" end
    Dg.settle(obj, nil, Dg.tempAt(obj))                 -- the new waste starts digesting from now
    if not Dg.consume(item, kind) then return 0, "bad" end
    st.waste = st.waste + units
    Dg.publish(obj)
    return units
end

----------------------------------------------------------- the line and the status
--- What the digester is piped to: { state = "ok"|"unpiped"|"down"|"paused", room = kg free in its tanks }.
function Dg.line(obj)
    local a = L.adapters[Dg.ID]
    local out = { state = "unpiped", room = 0 }
    if not a then return out end
    local st = L.status(obj, a)
    if not st.connected then return out end
    if not st.working then out.state = "down" return out end
    local link = L.linkOf(obj, Dg.ID)
    if link and link.source ~= "tank" then out.state = "paused" return out end
    out.state = "ok"
    for _, r in ipairs(st.receivers) do out.room = out.room + max(0, r.room()) end
    return out
end

--- The status key (IGUI_DazedPlumb_Digester_<key>) and the speed factor now.
function Dg.status(obj)
    local st = Dg.state(obj)
    local factor = Dg.tempFactor(Dg.tempAt(obj))
    if st.waste <= Dg.RESIDUE then return "idle", factor end
    if factor <= 0 then return "frozen", factor end
    if st.buf >= Dg.BUF_CAP - Dg.EPS then return "held", factor end
    return factor < 1 and "cold" or "ok", factor
end

----------------------------------------------------------- the link adapter
-- A SOURCE of propane: it offers its buffered gas to the tank on its line.
function Dg.register_adapter()
    return L.register({
        id = Dg.ID, produces = "propane", tainted = false, noNodes = true, label = "ContextMenu_DazedPlumb_DigesterLine",
        match = function(o) return Dg.isDigester(o) end,
        available = function(o)
            Dg.refresh(o)
            return Dg.state(o).buf
        end,
        take = function(o, amt)
            local st = Dg.state(o)
            local give = min(max(0, amt or 0), st.buf)
            if give <= 0 then return 0 end
            st.buf = st.buf - give
            Dg.publish(o)
            return give
        end,
    })
end
Dg.register_adapter()

return Dg
