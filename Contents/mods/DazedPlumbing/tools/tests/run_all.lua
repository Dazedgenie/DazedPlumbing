-- Runs every headless test: `lua run_all.lua [<DazedCore lua root>]` from this folder (set LUA to name another interpreter).
-- It is a .lua file because the Steam Workshop refuses .sh files in an upload.
local lua = os.getenv("LUA") or "lua"
local root = "../../common/media/lua"
local core = arg and arg[1] and (" " .. arg[1]) or ""
local ok = true
for _, t in ipairs({ "net", "plumbing", "place", "mains", "fuel", "digester", "freeze" }) do
    local r1 = os.execute(lua .. " " .. t .. "_test.lua " .. root .. core)
    if r1 ~= true and r1 ~= 0 then ok = false end
end
os.exit(ok and 0 or 1)
