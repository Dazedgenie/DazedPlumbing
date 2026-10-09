--[[ Dazed Plumbing -- what a tank IS, as the game sees it.

     The identity of a placed tank is its SPRITE NAME, the way Dazed Power
     recognises its parts: tile `dazedplumb_01_<N>`.

     A tank is 1, 2 or 3 squares long (small, large, xl). Its sprites sit in
     three blocks, in this order, each laid out
         N = blockStart + (row * 4 + facing) * pieces + (piece - 1)
         row = typeIndex * 2 + tierIndex       (0..5)
         facing: 0 E, 1 S, 2 W, 3 N;   piece: 1..pieces, along the tank
     small  block 0..23   (1 piece)    large block 24..71 (2)    xl block 72..143 (3)
     Piece 1 is the MASTER (SpriteGridPos 0,0): it carries the state and the
     item. Facing S/N lays the pieces along +x (SpriteGridPos p-1,0), facing
     E/W along +y (0,p-1). tools/pack_tiles.py writes the sheet in exactly
     this order; change one and you must change the other. Append only: a
     saved world remembers sprite names.

     The state a tank keeps lives in the object's ModData table `dazedplumb`
     (flat fields: see DUP_Model).
]]

require "DazedCore/DC_Util"
require "DazedPlumbing/DUP_Model"

DazedPlumb.Parts = DazedPlumb.Parts or {}
local P = DazedPlumb.Parts
local M = DazedPlumb.Model

P.TILESET = "dazedplumb_01"
P.COLS = 4
P.FACINGS = { "E", "S", "W", "N" }
P.FACING_INDEX = { E = 1, S = 2, W = 3, N = 4 }
P.KEY = "dazedplumb"            -- the ModData table's name

P.PIECES = { small = 1, large = 2, xl = 3 }
P.ROWS = {}                      -- 1-based list of { size, type, tier } (18)
P.ROW_OF = {}
P.BLOCK = {}                     -- size -> first tile index of its block
P.TILE_COUNT = 0
for _, size in ipairs(M.SIZES) do
    P.BLOCK[size] = P.TILE_COUNT
    for _, typ in ipairs(M.TYPES) do
        for _, tier in ipairs(M.TIERS) do
            P.ROWS[#P.ROWS + 1] = { size = size, type = typ, tier = tier }
            P.ROW_OF[size .. "|" .. typ .. "|" .. tier] = #P.ROWS
        end
    end
    P.TILE_COUNT = P.TILE_COUNT + (#M.TYPES * #M.TIERS) * 4 * P.PIECES[size]
end
P.ROW_COUNT = #P.ROWS            -- 18

local function cap(s) return s:sub(1, 1):upper() .. s:sub(2) end

--- Item type (full) for a tank: Base.DazedTank<Size><Type><Tier>.
function P.itemFor(size, typ, tier)
    local s = (size == "xl") and "XL" or cap(size)
    return "Base.DazedTank" .. s .. cap(typ) .. cap(tier)
end

--- Every item the mod declares, for its boot check.
function P.allItems()
    local out = {}
    for _, r in ipairs(P.ROWS) do out[#out + 1] = P.itemFor(r.size, r.type, r.tier) end
    return out
end

--- Sprite name for a variant (piece 1 = the master), or nil.
function P.sprite(size, typ, tier, facing, piece)
    local row = P.ROW_OF[tostring(size) .. "|" .. tostring(typ) .. "|" .. tostring(tier)]
    local n = P.PIECES[size]
    if not row or not n then return nil end
    local r = (row - 1) % (#M.TYPES * #M.TIERS)              -- row within its size
    local f = (P.FACING_INDEX[facing or "S"] or 2) - 1
    return P.TILESET .. "_" .. (P.BLOCK[size] + (r * 4 + f) * n + ((piece or 1) - 1))
end

--- Decompose one of the mod's sprite names, or nil. Anything but a string is
--  not ours (a hook handed arguments in a shifted order must fall through).
-- The name pattern, built once per tileset name instead of on every object a scan looks at.
local namePat, namePrefix, namePatFor = nil, nil, nil
function P.namePattern()
    if namePatFor ~= P.TILESET then namePat, namePrefix, namePatFor = "^" .. P.TILESET .. "_(%d+)$", P.TILESET .. "_", P.TILESET end
    return namePat
end

--- "dazedplumb_01_": every sprite this mod draws starts with it.
function P.prefix()
    if namePatFor ~= P.TILESET then P.namePattern() end
    return namePrefix
end

--- Does a sprite name belong to this mod? One cheap test before any pattern match.
function P.ours(name)
    if type(name) ~= "string" then return false end
    local prefix = P.prefix()
    return string.sub(name, 1, #prefix) == prefix
end

local function spriteInfoRaw(name)
    local idx = string.match(name, P.namePattern())
    if not idx then return nil end
    idx = tonumber(idx)
    if idx >= P.TILE_COUNT then return nil end
    local size = M.SIZES[1]
    for _, sz in ipairs(M.SIZES) do
        if idx >= P.BLOCK[sz] then size = sz end
    end
    local n = P.PIECES[size]
    local rel = idx - P.BLOCK[size]
    local piece = rel % n + 1
    local rf = math.floor(rel / n)                          -- row*4 + facing
    local facing = P.FACINGS[rf % 4 + 1]
    local r = P.ROWS[P.ROW_OF[size .. "|" .. M.TYPES[1] .. "|" .. M.TIERS[1]] + math.floor(rf / 4)]
    if not r then return nil end
    local gx, gy = 0, 0
    if facing == "E" or facing == "W" then gy = piece - 1 else gx = piece - 1 end
    return { size = size, type = r.type, tier = r.tier, facing = facing, index = idx,
             piece = piece, pieces = n, gx = gx, gy = gy, master = (piece == 1) }
end

-- The tile number in one of this mod's sprite names ("dazedplumb_01_212" -> 212), or nil; kept per name.
local indexMemo = DazedCore.Util.memo1(function(name) return tonumber(string.match(name, P.namePattern())) end, 512)

--- The tile number of a sprite name of ours, or nil (anything else stops at the prefix test).
function P.indexOf(name)
    if not P.ours(name) then return nil end
    return indexMemo(name)
end

-- A sprite's answer never changes, so it is kept per name; callers share the table and must only read it.
local spriteInfoMemo = DazedCore.Util.memo1(spriteInfoRaw, 512)

function P.spriteInfo(name)
    if not P.ours(name) then return nil end
    return spriteInfoMemo(name)
end

local Util = DazedCore.Util
local try = Util.try
P.try = try

--- Is a world object still standing on a square? A lifted or destroyed one answers false.
function P.alive(o)
    local ix = try(o, "getObjectIndex")
    return type(ix) == "number" and ix >= 0
end

-- Objects whose ModData changed inside a batch (a minute tick), sent once when the batch ends.
local batchDepth, batchDirty = 0, {}

--- Send an object's ModData to the clients: now, or once at the end of the running batch.
function P.transmit(obj)
    if not obj then return end
    if batchDepth > 0 then batchDirty[obj] = true return end
    if obj.transmitModData then obj:transmitModData() end
end

--- Run fn(...) holding back P.transmit sends, then send each changed object once. Errors still reach the caller.
function P.batch(fn, ...)
    batchDepth = batchDepth + 1
    local ok, err = pcall(fn, ...)
    batchDepth = batchDepth - 1
    if batchDepth == 0 then
        local list = {}
        for o in pairs(batchDirty) do list[#list + 1] = o end
        batchDirty = {}
        for _, o in ipairs(list) do
            if o.transmitModData then pcall(o.transmitModData, o) end
        end
    end
    if not ok then error(err, 0) end
end

-- Console lines said once per session, by key, so a failing engine path is one line in a report.
local said = {}
function P.once(key, text)
    if said[key] then return end
    said[key] = true
    print("DazedPlumbing: " .. text)
end

--- Start a timed action's sound (its class SOUND: a game sound name, or a function of the action).
function P.startSound(action)
    local name = action.SOUND
    if type(name) == "function" then name = name(action) end
    local ch = action.character
    if type(name) ~= "string" or not (ch and ch.playSound) then return end
    local ok, id = pcall(ch.playSound, ch, name)
    if ok then action.sound = id end
end

--- Stop it again (on finish or interruption).
function P.stopSound(action)
    local ch = action.character
    if action.sound and action.sound ~= 0 and ch and ch.stopOrTriggerSound then pcall(ch.stopOrTriggerSound, ch, action.sound) end
    action.sound = nil
end

--- A tile property's value, or nil; the core's helper, kept under Plumbing's old name.
P.prop = Util.prop

--- Does the tile carry this flag property? The core's helper, kept under Plumbing's old name.
P.propIs = Util.propIs

--- Everything the mod knows about an object, or nil if it is not a tank.
function P.describe(obj)
    local spr = try(obj, "getSprite")
    local name = spr and try(spr, "getName")
    return P.spriteInfo(name)
end

function P.isTank(obj) return P.describe(obj) ~= nil end

local function sameTank(a, b)
    return a.size == b.size and a.type == b.type and a.tier == b.tier and a.facing == b.facing
end

--- Directions a tank's pieces may run from its master, the one the sprite
--  sheet assumes first. The engine decides where piece N really lands from
--  each tile's SpriteGridPos, so rather than trust the assumption the lookups
--  below try all four and take the one that has the matching piece.
local function directions(info)
    local ax, ay = info.gx, info.gy                       -- assumed: toward +x or +y
    local dirs = { { ax > 0 and 1 or 0, ay > 0 and 1 or 0 } }
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        if not (d[1] == dirs[1][1] and d[2] == dirs[1][2]) then dirs[#dirs + 1] = d end
    end
    return dirs
end

local function objectsAt(x, y, z)
    local cell = getCell and getCell()
    local sq = cell and cell:getGridSquare(x, y, z)
    return sq and try(sq, "getObjects") or nil
end

--- The piece number `want` of the same tank, at (x, y, z), or nil.
local function pieceAt(info, want, x, y, z)
    local objs = objectsAt(x, y, z)
    if not objs then return nil end
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        local oi = P.describe(o)
        if oi and oi.piece == want and sameTank(oi, info) then return o end
    end
    return nil
end

--- The master piece of the tank this object is a piece of (the object itself
--  when it is the master, or when the master cannot be found).
function P.master(obj)
    local info = P.describe(obj)
    if not info or info.master then return obj end
    local sq = try(obj, "getSquare")
    if not sq then return obj end
    local k = info.piece - 1
    for _, d in ipairs(directions(info)) do
        local m = pieceAt(info, 1, sq:getX() - d[1] * k, sq:getY() - d[2] * k, sq:getZ())
        if m then return m end
    end
    return obj
end

--- The squares a tank covers, master first. `master` is its master object.
function P.squares(master)
    local info = P.describe(master)
    local sq = try(master, "getSquare")
    local out = {}
    if not sq then return out end
    out[1] = sq
    if not info or info.pieces < 2 then return out end
    local cell = getCell and getCell()
    if not cell then return out end
    -- which way do the other pieces lie? the way where piece 2 is found
    local dir
    for _, d in ipairs(directions(info)) do
        if pieceAt(info, 2, sq:getX() + d[1], sq:getY() + d[2], sq:getZ()) then dir = d break end
    end
    dir = dir or directions(info)[1]
    for p = 2, info.pieces do
        local q = cell:getGridSquare(sq:getX() + dir[1] * (p - 1), sq:getY() + dir[2] * (p - 1), sq:getZ())
        if q then out[#out + 1] = q end
    end
    return out
end

--- The tank's state table on the MASTER object, defaulted. Identity fields
--  are rewritten from the sprite every time, so an object whose ModData was
--  scrubbed is still known.
function P.data(obj)
    obj = P.master(obj)
    local md = obj:getModData()
    if md[P.KEY] == nil then md[P.KEY] = {} end
    local d = md[P.KEY]
    local info = P.describe(obj)
    if info then
        d.size, d.type, d.tier, d.facing = info.size, info.type, info.tier, info.facing
        M.normalize(d)
    end
    return d
end

--- What vanilla's moveable round trip leaves on a placed object's ModData
--  (the saved copy of the previous object's, among other things). Dropped
--  after a placement so each move does not nest the state one level deeper.
P.VANILLA_CARRIED = { "modData", "name", "health", "maxHealth", "thumpSound", "color",
                      "lightSource", "canBeLockedByPadlock", "lockedByKeyId", "lockedByCode" }

function P.scrubCarried(obj)
    local md = obj and obj.getModData and obj:getModData()
    if not md then return false end
    local changed = false
    for _, k in ipairs(P.VANILLA_CARRIED) do
        if md[k] ~= nil then md[k] = nil; changed = true end
    end
    return changed
end

--- Every object on the squares of a right-click's objects, ours first.
--  The game hands menus only the object it picked under the mouse (often the floor or a counter),
--  so small or surface-mounted things like a sprinkler or an industrial sink are found this way.
-- Every menu of the mod asks about the same right-click: the answer is kept for that worldobjects table, briefly.
local around = { wo = nil, at = -1, list = nil }
P.AROUND_MS = 500

function P.objectsAround(worldobjects)
    local now = getTimestampMs and getTimestampMs() or nil
    if now and worldobjects ~= nil and around.wo == worldobjects and now >= around.at and now - around.at <= P.AROUND_MS then
        return around.list
    end
    local list = P.objectsAroundUncached(worldobjects)
    if now and worldobjects ~= nil then around = { wo = worldobjects, at = now, list = list } end
    return list
end

function P.objectsAroundUncached(worldobjects)
    local ours, rest, seenSq, seenObj = {}, {}, {}, {}
    local prefix = P.TILESET .. "_"
    local function add(o)
        if not o or seenObj[o] then return end
        seenObj[o] = true
        local name = try(o, "getSpriteName")
        if type(name) == "string" and string.sub(name, 1, #prefix) == prefix then ours[#ours + 1] = o else rest[#rest + 1] = o end
    end
    for _, o in ipairs(worldobjects or {}) do
        add(o)
        local sq = try(o, "getSquare")
        if sq and not seenSq[sq] then
            seenSq[sq] = true
            local objs = try(sq, "getObjects")
            if objs then for i = 0, objs:size() - 1 do add(objs:get(i)) end end
        end
    end
    for _, o in ipairs(rest) do ours[#ours + 1] = o end
    return ours
end

--- Translation-ready label for a type/size.
function P.typeKey(typ) return "IGUI_DazedPlumb_Type_" .. cap(typ) end
function P.sizeKey(size) return "IGUI_DazedPlumb_Size_" .. cap(size) end
