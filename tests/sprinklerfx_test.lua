-- The sprinkler's spray cycle on a fake engine: the frame sprites read back as spraying in their facing, a spraying
-- sprinkler near a player walks the frames, an idle one and a far one stay plain, the server's idle flip stops the
-- cycle, the sandbox option off puts the plain sprite back, and the jobs go when nothing is left.
-- Run: lua sprinklerfx_test.lua <lua root> [<core root>]
local root = arg[1] or "../Contents/mods/DazedPlumbing/common/media/lua"
local core = arg[2] or "../../DazedCore/Contents/mods/DazedCore/common/media/lua"
package.path = core .. "/shared/?.lua;" .. core .. "/client/?.lua;" .. root .. "/shared/?.lua;" .. root .. "/server/?.lua;" .. root .. "/client/?.lua;" .. package.path
local E = dofile(core .. "/../../../../../../tools/tests/engine_stub.lua")   -- Core's shared engine stand-in
local print = E.realPrint
local fails, n = 0, 0
local function ok(c, msg) n = n + 1 if not c then fails = fails + 1 print("FAIL: " .. msg) end end

getSprite = function(name) return name end          -- the stub keeps sprite names, so a "sprite object" is its name
local clock = 0
getTimestampMs = function() return clock end
local player = { x = 5, y = 5, z = 0 }
function player:getX() return self.x end
function player:getY() return self.y end
function player:getZ() return self.z end
function player:isDead() return false end
getNumActivePlayers = function() return 1 end
getSpecificPlayer = function() return player end
SandboxVars.DazedPlumb = { SprinklerAnimation = true }

require "DazedPlumbing/DUP_Parts"
require "DazedPlumbing/DUP_Sprinklers"
require "DazedPlumbing/DUP_SprinklerFx"
local Z, F, T = DazedPlumb.Sprinklers, DazedPlumb.SprinklerFx, DazedCore.Tick
local TS = DazedPlumb.Parts.TILESET

-- sprites
ok(Z.frameSprite("E", 0) == TS .. "_264" and Z.frameSprite("N", 7) == TS .. "_295", "frame sprites 264..295")
ok(Z.frameSprite("S", 9) == Z.frameSprite("S", 1), "a frame number wraps")
for k = 0, 7 do
    for _, f in ipairs(Z.FACINGS) do
        local i = Z.spriteInfo(Z.frameSprite(f, k))
        ok(i and i.spraying and i.facing == f and i.frame == k, "frame " .. k .. " " .. f .. " reads back spraying")
    end
end
ok(Z.spriteInfo(TS .. "_296") == nil and Z.spriteInfo(TS .. "_263") == nil, "nothing past either end")
ok(Z.spriteInfo(TS .. "_208").frame == nil, "the plain spraying sprite is no frame")

-- a spraying sprinkler near the player, an idle one, and a spraying one far away
E.grid(10, 10)
local near = E.object(Z.sprite("S", true), E.square(6, 5))
local idle = E.object(Z.sprite("E", false), E.square(4, 4))
local far = E.object(Z.sprite("W", true), E.square(80, 80))
for _, o in ipairs({ near, idle, far }) do F.consider(o) end
F.consider(E.object(TS .. "_10", E.square(3, 3)))       -- a tank: not followed
ok(F.count == 3, "three sprinklers tracked")
ok(T.has(F.SCAN_ID), "the scan job is on")
F.scan()
ok(#F.active == 1 and F.active[1].obj == near, "only the near spraying one cycles")
ok(T.has(F.FRAME_ID), "the frame job is on")
local seen = {}
for step = 0, 15 do
    clock = step * F.FRAME_MS
    F.frames(clock)
    local i = Z.spriteInfo(near.sprite)
    ok(i and i.frame ~= nil and i.facing == "S", "step " .. step .. " shows a south frame")
    if i then seen[i.frame] = true end
end
local all = true
for k = 0, 7 do all = all and seen[k] == true end
ok(all, "every frame shows in a sweep")
ok(#F.CYCLE == 14 and F.CYCLE[1] == 0 and F.CYCLE[8] == 7 and F.CYCLE[9] == 6 and F.CYCLE[14] == 1, "the sweep goes 0..7 and back to 1")
local prev, smooth = F.frameAt(0, 0), true
for s2 = 1, 40 do local f = F.frameAt(s2 * F.FRAME_MS, 0); if math.abs(f - prev) ~= 1 then smooth = false end; prev = f end
ok(smooth, "every step moves the head one frame, turning at both ends")
ok(idle.sprite == Z.sprite("E", false) and far.sprite == Z.sprite("W", true), "idle and far ones keep their sprites")
ok(Z.isSprinkler(near) and Z.describe(near).spraying, "a sprinkler on a frame is still a spraying sprinkler")

-- the server's idle flip (switched off): the cycle stops and the idle sprite stays
Z.setSpraying(near, false)
ok(near.sprite == Z.sprite("S", false), "setSpraying(false) from a frame shows idle")
clock = clock + F.FRAME_MS
F.frames(clock)
ok(near.sprite == Z.sprite("S", false) and #F.active == 0, "the cycle stops on the idle sprite")
ok(not T.has(F.FRAME_ID), "the frame job goes when nothing cycles")

-- paused: no swaps
Z.setSpraying(near, true)
F.scan()
local before = near.sprite
isGamePaused = function() return true end
clock = clock + F.FRAME_MS * 3
F.frames(clock)
ok(near.sprite == before, "paused: no swap")
isGamePaused = nil
F.frames(clock)
ok(Z.spriteInfo(near.sprite).frame ~= nil, "unpaused: it turns again")

-- the option off: the plain spraying sprite comes back
SandboxVars.DazedPlumb.SprinklerAnimation = false
F.scan()
ok(near.sprite == Z.sprite("S", true), "option off puts the plain spraying sprite back")
ok(not T.has(F.FRAME_ID), "option off: no frame job")
SandboxVars.DazedPlumb.SprinklerAnimation = true

-- picked up: forgotten, and the scan job goes with the last one
F.onRemoved(near)
E.square(4, 4):RemoveTileObject(idle)
E.square(80, 80)
far.square = nil
F.scan()
ok(F.count == 0, "removed and gone ones are forgotten")
F.scan()
ok(not T.has(F.SCAN_ID), "the scan job goes when nothing is tracked")

-- the sweep finds one no event announced
local swept = E.object(Z.sprite("N", true), E.square(7, 8))
F.sweep()
ok(F.tracked[swept] ~= nil, "the sweep picks up a sprinkler round the player")

print(string.format("sprinklerfx_test: %d checks, %d failed", n, fails))
if fails > 0 then os.exit(1) end
