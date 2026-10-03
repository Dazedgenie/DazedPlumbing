--[[ Dazed Utilities: Plumbing -- the water purifier.

     A purifier stands BETWEEN a source and a tank:

         pump --pipe--> purifier --pipe--> water tank

     It is a link NODE (the pump may be piped into it, like into a tank) and
     itself a link SOURCE (it is piped on to a tank): whatever flows in is held
     in a small buffer, then pushed on CLEAN. Ground water is tainted; a tank
     that gets only the purifier's water stays clean.

       power    it works only on a powered square, or wired to a powered Dazed Power
                controller with Dazed Power (see DUP_Power: it is a real
                Dazed Power load while it works).
       filter   a FILTER CARTRIDGE (craft from purifying tablets) makes it fast.
                Without one it still purifies, but only BARE_RATE L/min.
                A cartridge lasts FILTER_LITRES litres, then is spent.
       buffer   BUF_CAP litres, lost if the purifier is lifted (the filter's
                remaining life travels with it).

     State, flat numbers on the object's ModData table `dazedPurifier`:
         { buf = litres waiting, filter = 0..100 remaining, nil = none fitted }
     SPRITES: dazedplumb_01_184..187 = facings E, S, W, N.
]]

require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Links"

DazedPlumb.Purifiers = DazedPlumb.Purifiers or {}
local R = DazedPlumb.Purifiers
local P, L, K, U = DazedPlumb.Parts, DazedPlumb.Links, DazedPlumb.Pipes, DazedPlumb.Pumps
local try = P.try

R.BASE = U.BASE + U.COUNT
R.COUNT = 4
R.FACINGS = { "E", "S", "W", "N" }
R.ITEM = "Base.DazedPurifier"
R.FILTER_ITEM = "Base.DazedPurifierFilter"
R.ID = "dazed_purifier"

R.BUF_CAP = 20            -- litres it holds
R.FILTER_RATE = 20        -- L/min with a cartridge
R.BARE_RATE = 2           -- L/min without
R.FILTER_LITRES = 500     -- litres one cartridge treats
R.WATTS = 150             -- power load while working (see DUP_Power)

----------------------------------------------------------- sprites
function R.sprite(facing)
    for i, f in ipairs(R.FACINGS) do
        if f == facing then return P.TILESET .. "_" .. (R.BASE + i - 1) end
    end
end

function R.spriteInfo(name)
    local idx = type(name) == "string" and string.match(name, "^" .. P.TILESET .. "_(%d+)$")
    idx = idx and tonumber(idx)
    if not idx or idx < R.BASE or idx >= R.BASE + R.COUNT then return nil end
    return { facing = R.FACINGS[idx - R.BASE + 1] }
end

function R.isPurifier(obj)
    local spr = obj and try(obj, "getSprite")
    return spr ~= nil and R.spriteInfo(try(spr, "getName")) ~= nil
end

function R.allItems() return { R.ITEM, R.FILTER_ITEM } end

----------------------------------------------------------- state
function R.state(obj)
    local md = obj:getModData()
    md.dazedPurifier = md.dazedPurifier or { buf = 0 }
    return md.dazedPurifier
end

--- Litres a minute at full flow: fast with a cartridge, a trickle without.
function R.fullRate(obj)
    return (R.state(obj).filter or 0) > 0 and R.FILTER_RATE or R.BARE_RATE
end

--- Litres a minute at the flow it is set to (the same `dazedFlow` setting as the pump).
function R.rate(obj) return R.fullRate(obj) * U.flow(obj) end
function R.watts(obj) return R.WATTS * U.flow(obj) end

function R.powered(obj)
    if DazedPlumb.wiredPower and DazedPlumb.wiredPower(obj) then return true end
    local sq = obj and try(obj, "getSquare")
    return sq ~= nil and try(sq, "haveElectricity") == true
end

--- Is it working right now? (No side effects.)
function R.working(obj)
    if not R.isPurifier(obj) or U.isOff(obj) or not R.powered(obj) then return false end
    if (R.state(obj).buf or 0) <= 0.001 then return false end
    local link = L.linkOf(obj, R.ID)
    if not link or link.source ~= "tank" then return false end
    local st = L.status(obj, L.adapters[R.ID])
    for _, r in ipairs(st.receivers) do
        if r.room() > 0.001 then return true end
    end
    return false
end

----------------------------------------------------------- the link roles
function R.register()
    -- 1. a NODE: pumps may pipe into it
    L.registerNode({
        id = R.ID, kind = "water",
        match = function(o) return R.isPurifier(o) end,
        room = function(o) return math.max(0, R.BUF_CAP - (R.state(o).buf or 0)) end,
        add = function(o, amt, dirty)
            local st = R.state(o)
            local took = math.min(math.max(0, amt or 0), R.BUF_CAP - (st.buf or 0))
            st.buf = (st.buf or 0) + took
            if took > 0 and o.transmitModData then o:transmitModData() end
            return took
        end,
    })
    -- 2. a SOURCE: it pushes clean water on to a tank
    return L.register({
        id = R.ID, produces = "water", tainted = false, noNodes = true,
        label = "ContextMenu_DazedPlumb_PurifierLine",
        match = function(o) return R.isPurifier(o) end,
        available = function(o)
            if U.isOff(o) or not R.powered(o) then return 0 end
            return math.min(R.state(o).buf or 0, R.rate(o))
        end,
        take = function(o, amt)
            local st = R.state(o)
            local give = math.min(math.max(0, amt or 0), st.buf or 0)
            if give <= 0 then return 0 end
            st.buf = st.buf - give
            if (st.filter or 0) > 0 then                       -- the cartridge wears
                st.filter = st.filter - give * 100 / R.FILTER_LITRES
                if st.filter <= 0 then st.filter = nil end     -- spent
            end
            if o.transmitModData then o:transmitModData() end
            return give
        end,
    })
end
R.register()

return R
