--[[ Dazed Plumbing -- smokers in the live world (authority only).
     Registers every smoker that streams in or is placed, settles it on load (the hours away, at most 48) and once a minute. ]]

require "DazedPlumbing/DUP_Smokers"

local Sm = DazedPlumb.Smokers
local PRIORITY = 6

local function onLoad(obj)
    if isClient and isClient() then return end      -- a client takes what the server sends
    Sm.register(obj)
    local ok, err = pcall(Sm.refresh, obj)
    if not ok then print("DazedPlumbing: smoker load failed: " .. tostring(err)) end
end

local function registerSprites()
    for n = Sm.BASE, Sm.BASE + Sm.COUNT - 1 do
        local name = DazedPlumb.Parts.TILESET .. "_" .. n
        MapObjects.OnLoadWithSprite(name, onLoad, PRIORITY)
        MapObjects.OnNewWithSprite(name, onLoad, PRIORITY)
    end
end

-- At file load AND on game start, like the digester: the login area's chunks stream in before OnGameStart.
registerSprites()
Events.OnGameStart.Add(registerSprites)
Events.OnServerStarted.Add(registerSprites)
Events.EveryOneMinute.Add(function()
    if isClient and isClient() then return end
    Sm.tick()
end)
