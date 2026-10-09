--[[ Dazed Utilities: Plumbing -- the smoker: a propane-fired box with an item container that smokes raw meat and fish while lit.
     State is ModData `dazedSmoker` { lit, hour, out, prog = { [item id] = hours } }; sprites dazedplumb_01_252..255 (facings E, S, W, N). ]]

require "DazedCore/DC_Boot"
require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Links"
require "DazedPlumbing/DUP_Sync"
require "DazedPlumbing/DUP_DrilledWells"

DazedPlumb.Smokers = DazedPlumb.Smokers or {}
local Sm = DazedPlumb.Smokers
local P, L = DazedPlumb.Parts, DazedPlumb.Links
local try = P.try
local min, max = math.min, math.max

Sm.BASE = DazedPlumb.DrilledWells.BASE + DazedPlumb.DrilledWells.COUNT
Sm.COUNT = 4
Sm.FACINGS = { "E", "S", "W", "N" }
Sm.ITEM = "Base.DazedSmoker"
Sm.ID = "dazed_smoker"
Sm.KEY = "dazedSmoker"
Sm.CONTAINER = "smoker"          -- the tile's container type (IGUI_ContainerTitle_smoker)

Sm.BURN_PER_HOUR = 0.05          -- kg of propane an hour while lit
Sm.SMOKE_HOURS = 8               -- in-game hours of smoke that make a raw item smoked
Sm.FRESH_MULT = 6                -- smoked food keeps this many times longer
Sm.MAX_CATCHUP_HOURS = 48        -- most hours settled at once after an absence
Sm.NEVER = 1e8                   -- an offAge at or above this means the food never goes off
Sm.EPS = 1e-6
Sm.FOOD_TYPES = { meat = true, fish = true, game = true, seafood = true, poultry = true }
Sm.SUFFIX = "(Smoked)"           -- used when the translation is missing

----------------------------------------------------------- sprites
function Sm.sprite(facing)
    for i, f in ipairs(Sm.FACINGS) do
        if f == facing then return P.TILESET .. "_" .. (Sm.BASE + i - 1) end
    end
end

--- {facing} for a smoker sprite name, or nil.
function Sm.spriteInfo(name)
    local idx = P.indexOf(name)
    if not idx or idx < Sm.BASE or idx >= Sm.BASE + Sm.COUNT then return nil end
    return { facing = Sm.FACINGS[idx - Sm.BASE + 1] }
end

function Sm.isSmoker(obj)
    local spr = obj and try(obj, "getSprite")
    return spr ~= nil and Sm.spriteInfo(try(spr, "getName")) ~= nil
end

function Sm.allItems() return { Sm.ITEM } end

----------------------------------------------------------- the model (pure)
--- Kg of propane burnt in `hours` of smoking.
function Sm.burn(hours) return max(0, hours or 0) * Sm.BURN_PER_HOUR end

--- Hours a lit smoker really smokes over a gap of `gap` hours with `gasKg` on its line (capped at MAX_CATCHUP_HOURS).
function Sm.runHours(gap, gasKg, lit)
    if not lit then return 0 end
    local h = min(max(0, gap or 0), Sm.MAX_CATCHUP_HOURS)
    return max(0, min(h, max(0, gasKg or 0) / Sm.BURN_PER_HOUR))
end

--- An item's smoke so far plus `hours`: the new total and whether it is now done.
function Sm.progress(prev, hours)
    local total = max(0, prev or 0) + max(0, hours or 0)
    return total, total >= Sm.SMOKE_HOURS - Sm.EPS
end

--- Hours still to go for an item with `prev` hours of smoke.
function Sm.hoursLeft(prev) return max(0, Sm.SMOKE_HOURS - max(0, prev or 0)) end

--- A freshness age (days) after smoking: FRESH_MULT times longer, and "never" stays never.
function Sm.smokedAge(n)
    n = tonumber(n)
    if not n or n >= Sm.NEVER then return n end
    return math.floor(n * Sm.FRESH_MULT + 0.5)
end

--- A food's name once smoked: the suffix is added once.
function Sm.smokedName(name, suffix)
    suffix = suffix or Sm.SUFFIX
    name = tostring(name or "?")
    if string.sub(name, -#suffix) == suffix then return name end
    return name .. " " .. suffix
end

----------------------------------------------------------- what may be smoked
local function isFood(item) return instanceof ~= nil and instanceof(item, "Food") == true end

--- Is this meat or fish (vanilla food types, a Dazed Butchery cut, or an item that says so)?
function Sm.isMeat(item)
    local ft = try(item, "getFullType")
    if type(ft) == "string" and string.find(ft, "^Base%.DB_") then return true end
    local t = try(item, "getFoodType")
    if type(t) == "string" and Sm.FOOD_TYPES[string.lower(t)] then return true end
    return try(item, "isMeat") == true or try(item, "isFish") == true
end

--- May this item be smoked: raw meat or fish that is not burnt, rotten or already smoked?
function Sm.smokable(item)
    if not item or not isFood(item) or not Sm.isMeat(item) then return false end
    local md = try(item, "getModData")
    if md and md.dazedSmoked then return false end
    if try(item, "isCooked") == true or try(item, "isBurnt") == true or try(item, "isRotten") == true then return false end
    return true
end

--- Turn a raw item into smoked food in place: marked, cooked, keeping FRESH_MULT times longer and renamed.
function Sm.smoke(item)
    local md = try(item, "getModData")
    if md then md.dazedSmoked = true end
    try(item, "setCooked", true)
    local oa, om = try(item, "getOffAge"), try(item, "getOffAgeMax")
    if type(oa) == "number" then try(item, "setOffAge", Sm.smokedAge(oa)) end
    if type(om) == "number" then try(item, "setOffAgeMax", Sm.smokedAge(om)) end
    local suffix = getText and getText("IGUI_DazedPlumb_SmokedSuffix")
    if type(suffix) ~= "string" or suffix == "IGUI_DazedPlumb_SmokedSuffix" then suffix = Sm.SUFFIX end
    local name = try(item, "getDisplayName") or try(item, "getName")
    try(item, "setName", Sm.smokedName(name, suffix))
    try(item, "setCustomName", true)            -- after setName: the engine stores the name it has then
    return true
end

----------------------------------------------------------- state
local worldHours = DazedCore.Util.worldHours

--- The smoker's state table, defaulted. A new one starts unlit, settled now.
function Sm.state(obj)
    local md = obj:getModData()
    local st = md[Sm.KEY]
    if type(st) ~= "table" then
        st = { hour = worldHours() }
        md[Sm.KEY] = st
    end
    if type(st.prog) ~= "table" then st.prog = {} end
    return st
end
function Sm.isLit(obj) return Sm.state(obj).lit == true end

--- A stable key for an item (its engine id, synced in multiplayer).
function Sm.itemKey(item)
    local id = try(item, "getID")
    return tostring(id ~= nil and id or item)
end

--- Every smokable item in the smoker's container.
function Sm.contents(obj)
    local out = {}
    local cont = try(obj, "getContainer")
    local items = cont and try(cont, "getItems")
    if not items then return out, cont end
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if Sm.smokable(it) then out[#out + 1] = it end
    end
    return out, cont
end

----------------------------------------------------------- the line
--- What the smoker is piped to: { state = "ok"|"unpiped"|"down"|"paused", tanks = {handles}, kg = propane on the line }.
function Sm.line(obj)
    local a = L.adapters[Sm.ID]
    local out = { state = "unpiped", tanks = {}, kg = 0 }
    if not a then return out end
    local st = L.status(obj, a)
    if not st.connected then return out end
    if not st.working then out.state = "down" return out end
    local link = L.linkOf(obj, Sm.ID)
    if link and link.source ~= "tank" then out.state = "paused" return out end
    out.state, out.tanks = "ok", st.tanks
    for _, t in ipairs(st.tanks) do out.kg = out.kg + max(0, t.amount()) end
    return out
end

----------------------------------------------------------- settling
--- Take `kg` from the tanks, fullest first; returns what came out. A minute's burn is under a gram, so no coarse cut-off.
function Sm.draw(tanks, kg)
    local order = {}
    for _, t in ipairs(tanks) do order[#order + 1] = t end
    table.sort(order, function(a, b) return a.amount() > b.amount() end)
    local left, took = kg, 0
    for _, t in ipairs(order) do
        if left > Sm.EPS * Sm.BURN_PER_HOUR then
            local got = t.take(min(left, max(0, t.amount()))) or 0
            left, took = left - got, took + got
        end
    end
    return took
end

-- Show the clients the new item in full (name, cooked, freshness travel with the item, not its stats).
local function resend(cont, item)
    if not (isServer and isServer()) then return end
    if sendRemoveItemFromContainer then pcall(sendRemoveItemFromContainer, cont, item) end
    if sendAddItemToContainer then pcall(sendAddItemToContainer, cont, item) end
end

--- Add `hours` of smoke to every smokable item inside; returns how many became smoked. Forgets items no longer inside.
function Sm.smokeItems(obj, hours)
    local st = Sm.state(obj)
    local list, cont = Sm.contents(obj)
    local keep, done = {}, 0
    for _, it in ipairs(list) do
        local k = Sm.itemKey(it)
        local total, finished = Sm.progress(st.prog[k], hours)
        if finished then
            Sm.smoke(it)
            resend(cont, it)
            done = done + 1
        else
            keep[k] = total
        end
    end
    st.prog = keep
    return done
end

--- Settle the hours since the smoker was last settled (authority only). Returns the hours it smoked.
function Sm.settle(obj, now)
    if not DazedPlumb.Sync.authority() then return 0 end
    local st = Sm.state(obj)
    now = now or worldHours()
    local last = st.hour
    st.hour = now
    if type(last) ~= "number" or not st.lit then return 0 end
    local gap = min(now - last, Sm.MAX_CATCHUP_HOURS)
    if gap <= 0 then return 0 end
    local line = Sm.line(obj)
    local run = Sm.runHours(gap, line.state == "ok" and line.kg or 0, true)
    if run > 0 then
        local want = Sm.burn(run)
        local got = Sm.draw(line.tanks, want)
        if got < want - Sm.EPS * Sm.BURN_PER_HOUR then run = got / Sm.BURN_PER_HOUR end
    end
    if run > 0 then Sm.smokeItems(obj, run) end
    if run < gap - Sm.EPS then st.lit, st.out = nil, true end     -- out of gas or the line shut: it goes out
    return run
end

-- What each smoker last showed the clients, so the minute tick sends only visible changes.
-- Kahlua ignores weak keys, so the tick drops an entry once its smoker leaves the live list.
local shown = {}

--- Tell the clients when what the menu shows has changed (the lit state or a tenth of an hour of progress). Authority only.
function Sm.publish(obj, force)
    if not DazedPlumb.Sync.authority() then return end
    local st = Sm.state(obj)
    local parts = { tostring(st.lit), tostring(st.out) }
    for k, v in pairs(st.prog) do parts[#parts + 1] = k .. "=" .. string.format("%.1f", v) end
    table.sort(parts)
    local key = table.concat(parts, "|")
    Sm.live[obj] = true                                -- every remembered smoker is one the tick can drop
    if not force and shown[obj] == key then return end
    shown[obj] = key
    if obj.transmitModData then obj:transmitModData() end
end

--- Bring a smoker up to date (authority only) and publish it.
function Sm.refresh(obj)
    if not DazedPlumb.Sync.authority() then return end
    Sm.settle(obj)
    Sm.publish(obj)
end

--- Light or put out a smoker (authority). Returns true, or false and a reason ("nogas").
function Sm.setLit(obj, on)
    Sm.settle(obj)                                     -- the time before the change is settled under the old state
    local st = Sm.state(obj)
    if on then
        if Sm.line(obj).kg <= Sm.EPS then return false, "nogas" end
        st.lit, st.out = true, nil
    else
        st.lit = nil
    end
    st.hour = worldHours()
    Sm.publish(obj, true)
    return true
end

--- The status key (IGUI_DazedPlumb_Smoker_<key>): smoking, lit (nothing raw inside), out (went out, no gas) or unlit.
function Sm.status(obj)
    local st = Sm.state(obj)
    if st.lit then return #Sm.contents(obj) > 0 and "smoking" or "lit" end
    return st.out and "out" or "unlit"
end

--- Smokable items inside and the most hours any of them still needs (read from the synced progress).
function Sm.progressNow(obj)
    local st = Sm.state(obj)
    local list = Sm.contents(obj)
    local most = 0
    for _, it in ipairs(list) do most = max(most, Sm.hoursLeft(st.prog[Sm.itemKey(it)])) end
    return #list, most
end

----------------------------------------------------------- the live registry and tick
-- Plain keys: the tick removes a smoker that is gone (Kahlua does not honour __mode).
Sm.live = Sm.live or {}

function Sm.register(obj)
    if obj then Sm.live[obj] = true end
end

local alive = P.alive

--- Settle every loaded smoker (authority only). A lifted one drops out.
function Sm.tick()
    if not DazedPlumb.Sync.authority() then return end
    for obj in pairs(Sm.live) do
        if not alive(obj) then
            Sm.live[obj] = nil
        else
            local ok, err = pcall(Sm.refresh, obj)
            if not ok then
                print("DazedPlumbing: smoker tick failed: " .. tostring(err))
                Sm.live[obj] = nil
            end
        end
    end
    for obj in pairs(shown) do
        if not Sm.live[obj] then shown[obj] = nil end
    end
end

----------------------------------------------------------- the link adapter
-- A SINK of propane that holds nothing, like the fuel pump: it only stands on the line, and the settle draws its gas.
function Sm.register_adapter()
    return L.register({
        id = Sm.ID, supplies = "propane", label = "ContextMenu_DazedPlumb_SmokerLine",
        match = function(o) return Sm.isSmoker(o) end,
        room = function() return 0 end,
        put = function() return 0 end,
    })
end
Sm.register_adapter()

return Sm
