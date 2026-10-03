--[[ Dazed Utilities: Plumbing -- who is in charge, and keeping clients in step.

     The AUTHORITY (single player, or the server) owns every change to the world: pipes, tanks,
     wells, links. A client never writes them. The mechanics live in the core (DazedCore.Sync);
     this file keeps Plumbing's own names for them and registers the tables it syncs. `version`
     reads the core's counter, so caches keyed on it rebuild when any synced table changes. ]]

require "DazedCore/DC_Boot"

DazedPlumb = DazedPlumb or {}
DazedPlumb.Sync = DazedPlumb.Sync or {}
local S = DazedPlumb.Sync
local C = DazedCore.Sync

S.KEYS = { "DazedPlumbNet", "DazedPlumbWells", "DazedPlumbMains" }
for _, key in ipairs(S.KEYS) do C.track(key) end

-- S.version and S.dirty are the core's, read live; nothing here ever assigns them.
setmetatable(S, { __index = function(_, k)
    if k == "version" then return C.version end
    if k == "dirty" then return C.dirty end
end })

function S.isClient() return C.isClient() end
function S.authority() return C.authority() end
function S.touch(key, now) C.touch(key, now) end
function S.flush() C.flush() end

--- Tell a player something short, by translation key.
function S.note(character, key) DazedCore.Note.say(character, key) end

return S
