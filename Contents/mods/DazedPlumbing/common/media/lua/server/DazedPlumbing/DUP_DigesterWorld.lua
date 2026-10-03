--[[ Dazed Utilities: Plumbing -- digesters in the live world (authority only).
     Registers every digester that streams in or is placed and settles it on load (the hours away, at most 48) and once a minute. ]]

require "DazedPlumbing/DUP_Digesters"

local Dg = DazedPlumb.Digesters
local PRIORITY = 6

local function onLoad(obj)
    if isClient and isClient() then return end      -- a client takes what the server sends
    Dg.register(obj)
    local ok, err = pcall(Dg.refresh, obj)
    if not ok then print("DazedPlumbing: digester load failed: " .. tostring(err)) end
end

local function registerSprites()
    for n = Dg.BASE, Dg.BASE + Dg.COUNT - 1 do
        local name = DazedPlumb.Parts.TILESET .. "_" .. n
        MapObjects.OnLoadWithSprite(name, onLoad, PRIORITY)
        MapObjects.OnNewWithSprite(name, onLoad, PRIORITY)
    end
end

-- At file load AND on game start, like the tanks: the login area's chunks stream in before OnGameStart.
registerSprites()
Events.OnGameStart.Add(registerSprites)
Events.OnServerStarted.Add(registerSprites)
Events.EveryOneMinute.Add(function()
    if isClient and isClient() then return end
    Dg.tick()
end)
