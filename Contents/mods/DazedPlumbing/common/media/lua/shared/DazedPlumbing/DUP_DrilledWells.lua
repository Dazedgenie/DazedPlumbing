--[[ Dazed Utilities: Plumbing -- the drilled well: a link SOURCE of clean water and a Dazed Power load (kind "well") that, like the
     electric fuel pump, runs only when wired to a powered controller. Sprites dazedplumb_01_248..251 (facings E, S, W, N) follow the digester's. ]]

require "DazedCore/DC_Boot"
require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Links"
require "DazedPlumbing/DUP_Pumps"
require "DazedPlumbing/DUP_Digesters"

DazedPlumb.DrilledWells = DazedPlumb.DrilledWells or {}
local Dw = DazedPlumb.DrilledWells
local P, L, U = DazedPlumb.Parts, DazedPlumb.Links, DazedPlumb.Pumps
local try = P.try
local min, max = math.min, math.max

Dw.BASE = DazedPlumb.Digesters.BASE + DazedPlumb.Digesters.COUNT
Dw.COUNT = 4
Dw.FACINGS = { "E", "S", "W", "N" }
Dw.ITEM = "Base.DazedDrilledWell"
Dw.ID = "dazed_drilledwell"
Dw.KIND = "well"                 -- the Dazed Power load kind (LOADS label IGUI_DazedPower_Load_well)

Dw.RATE = 15                     -- litres of clean water a minute while it pumps
Dw.WATTS = 400                   -- what it draws while pumping
Dw.EPS = 0.001

----------------------------------------------------------- sprites
function Dw.sprite(facing)
    for i, f in ipairs(Dw.FACINGS) do
        if f == facing then return P.TILESET .. "_" .. (Dw.BASE + i - 1) end
    end
end

--- {facing} for a drilled well sprite name, or nil.
function Dw.spriteInfo(name)
    local idx = P.indexOf(name)
    if not idx or idx < Dw.BASE or idx >= Dw.BASE + Dw.COUNT then return nil end
    return { facing = Dw.FACINGS[idx - Dw.BASE + 1] }
end

function Dw.isWell(obj)
    local spr = obj and try(obj, "getSprite")
    return spr ~= nil and Dw.spriteInfo(try(spr, "getName")) ~= nil
end

function Dw.allItems() return { Dw.ITEM } end

----------------------------------------------------------- the model (pure)
--- Litres the well delivers in `minutes` with `room` litres free on its line; nothing without power.
function Dw.output(minutes, room, powered)
    if not powered then return 0 end
    local n = min(Dw.RATE * max(0, minutes or 0), max(0, room or 0))
    return n > Dw.EPS and n or 0
end

----------------------------------------------------------- power
--- Can the well pump now? Returns true, or false and a reason: "gone", "off" or "nopower".
-- The square's own power does not count: only a powered Dazed Power controller's wire does.
function Dw.ready(obj)
    if not Dw.isWell(obj) then return false, "gone" end
    if U.isOff(obj) then return false, "off" end
    if not DazedPlumb.wiredPower(obj) then return false, "nopower" end
    return true
end

----------------------------------------------------------- the line and the status
--- What the well is piped to: { state = "ok"|"unpiped"|"down"|"paused", room = litres free in its tanks }.
function Dw.line(obj)
    local a = L.adapters[Dw.ID]
    local out = { state = "unpiped", room = 0 }
    if not a then return out end
    local st = L.status(obj, a)
    if not st.connected then return out end
    if not st.working then out.state = "down" return out end
    local link = L.linkOf(obj, Dw.ID)
    if link and link.source ~= "tank" then out.state = "paused" return out end
    out.state = "ok"
    for _, r in ipairs(st.receivers) do out.room = out.room + max(0, r.room() or 0) end
    return out
end

--- The status key (IGUI_DazedPlumb_Well_<key>): off, nopower, unpiped, down, paused, full or pumping.
function Dw.status(obj)
    local ok, why = Dw.ready(obj)
    if not ok then return why end
    local line = Dw.line(obj)
    if line.state ~= "ok" then return line.state end
    if line.room <= Dw.EPS then return "full" end
    return "pumping"
end

--- Is it pumping right now (billed by Dazed Power while true)? No side effects.
function Dw.working(obj) return Dw.status(obj) == "pumping" end

----------------------------------------------------------- the link adapter
-- A SOURCE of clean water: it offers its rate while wired and powered; the network caps it by the tanks' room.
function Dw.register()
    return L.register({
        id = Dw.ID, produces = "water", tainted = false, label = "ContextMenu_DazedPlumb_WellLine",
        match = function(o) return Dw.isWell(o) end,
        available = function(o) return Dw.output(1, Dw.RATE, Dw.ready(o)) end,
        take = function(o, amt) return Dw.output(1, amt, Dw.ready(o)) end,
    })
end
Dw.register()

return Dw
