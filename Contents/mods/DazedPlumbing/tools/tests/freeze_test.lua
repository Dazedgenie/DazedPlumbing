-- Checks that Plumbing honours ice and cracks set by Dazed Climate (DUP_Net, DUP_Model). Run from run_all.sh.
local root = arg[1] or "../../common/media/lua"
package.path = root .. "/shared/?.lua;" .. package.path
DazedClimate = { Plumbing = { enabled = function() return DazedClimate.on end } , on = true }
require "DazedPlumbing/DUP_Net"
require "DazedPlumbing/DUP_Model"
local N, M = DazedPlumb.Net, DazedPlumb.Model
local fails, n = 0, 0
local function check(ok, msg) n = n + 1 if not ok then fails = fails + 1 print("FAIL " .. msg) end end

-- A three-square water line; freezing the middle square splits it.
local pipes = {
    ["0,0,0"] = { f = "water", mask = 2 }, ["1,0,0"] = { f = "water", mask = 10 }, ["2,0,0"] = { f = "water", mask = 8 },
}
check(#N.component(pipes, "0,0,0").keys == 3, "a thawed line joins all three squares")
pipes["1,0,0"].frozen = true
check(#N.component(pipes, "0,0,0").keys == 1, "a frozen square stops flow like a closed valve")
check(#N.component(pipes, "0,0,0", true).keys == 3, "a frozen square is still part of the structure")
pipes["1,0,0"].frozen = nil
check(#N.component(pipes, "0,0,0").keys == 3, "thawing opens the line again")
pipes["1,0,0"].frozen = true

DazedClimate.on = false
check(#N.component(pipes, "0,0,0").keys == 3, "with Climate's ice off, a frozen-marked square flows")
DazedClimate.on = true
pipes["1,0,0"].frozen = nil

-- A frozen tank gives and takes nothing.
local d = { size = "small", tier = "crafted", type = "water", amount = 180, condition = 100 }
d.frozen = true
check(M.available(d) == 0 and M.room(d) == 0, "a frozen tank offers nothing and has no room")
check(M.take(d, 10) == 0 and d.amount == 180, "taking from a frozen tank gets nothing and loses nothing")
check(M.addWater(d, 10, false) == 0 and d.amount == 180, "pouring into a frozen tank goes nowhere")
check(M.leak(d, 5) == 0 and not M.isLeaking(d), "a frozen tank does not leak")
DazedClimate.on = false
check(M.available(d) == 180, "with Climate's ice off, a frozen-marked tank works")
DazedClimate.on = true
d.frozen = nil
check(M.available(d) == 180 and M.room(d) == 20, "a thawed tank works again")

-- A cracked tank leaks on top of wear until it is welded.
d.cracked = true
local cap = M.capacity("small", "crafted", "water")
check(math.abs(M.leakRate(d) - cap * M.CRACK_FRAC_PER_HOUR) < 1e-9, "a sound but cracked tank leaks at the crack rate")
check(M.isLeaking(d), "a cracked tank with water in it reads as leaking")
local lost = M.leak(d, 1)
check(math.abs(lost - cap * M.CRACK_FRAC_PER_HOUR) < 1e-9, "an hour costs one hour of crack leak")
d.condition = 0
check(M.leakRate(d) > cap * M.CRACK_FRAC_PER_HOUR, "wear and crack leaks add up")
d.cracked, d.condition = nil, 100
check(M.leakRate(d) == 0, "welded and sound, it stops leaking")

print(string.format("freeze_test: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
