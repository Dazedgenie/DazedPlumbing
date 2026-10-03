--[[ Dazed Utilities: Plumbing -- the machines that need power, told to the core as DazedCore.Power loads.
     The electric water pump (400 W), purifier (150 W) and electric fuel pump (200 W) are billed by a power mod; the fuel pump needs its wire, the others also run off a powered square.

     "Really working" = switched on, powered, piped to a tank with room, and (for the pump) the ground still has water. ]]

require "DazedCore/DC_Boot"
require "DazedPlumbing/DUP_Pumps"
require "DazedPlumbing/DUP_Purifiers"
require "DazedPlumbing/DUP_FuelPumps"

local U, Pu, Fp = DazedPlumb.Pumps, DazedPlumb.Purifiers, DazedPlumb.FuelPumps
local P, L = DazedPlumb.Parts, DazedPlumb.Links
local try = P.try
local W = DazedCore.Power

--- Is this electric pump working right now? (No side effects.)
function U.working(obj)
    local info = U.describe(obj)
    if not info or info.kind ~= "electric" then return false end
    local sq = try(obj, "getSquare")
    if not sq or U.isOff(obj) or not U.powered(obj) then return false end
    local link = L.linkOf(obj, U.ID)
    if not link or link.source ~= "tank" then return false end
    local st = L.status(obj, L.adapters[U.ID])
    local room = 0
    for _, r in ipairs(st.receivers) do room = room + r.room() end
    if room <= 0.001 then return false end
    return U.well(sq).reserve > 0.5
end

W.registerLoad({
    id = "dazed_pump", kind = "waterpump", items = { U.ITEM.electric },
    match = function(o) local i = U.describe(o) return i ~= nil and i.kind == "electric" end,
    watts = function(o) return U.watts(o) end,
    working = function(o) return U.working(o) end,
})
W.registerLoad({
    id = "dazed_purifier", kind = "purifier", items = { Pu.ITEM },
    match = function(o) return Pu.isPurifier(o) end,
    watts = function(o) return Pu.watts(o) end,
    working = function(o) return Pu.working(o) end,
})

-- The electric fuel pump counts as working only while it is moving fuel (Fp.markBusy).
W.registerLoad({
    id = "dazed_fuelpump", kind = "fuelpump", items = { Fp.ITEM.electric },
    match = function(o) return Fp.kindOf(o) == "electric" end,
    watts = function() return Fp.WATTS end,
    working = function(o) return Fp.working(o) end,
})

return W
