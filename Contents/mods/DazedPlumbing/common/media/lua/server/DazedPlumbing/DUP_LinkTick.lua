--[[ Dazed Utilities: Plumbing -- the pipe and network tick (authority only). ]]
require "DazedPlumbing/DUP_Links"
require "DazedPlumbing/DUP_Fixtures"
require "DazedPlumbing/DUP_Mains"
require "DazedPlumbing/DUP_MainPanel"
require "DazedPlumbing/DUP_Pumps"

Events.EveryOneMinute.Add(function()
    if isClient and isClient() then return end
    DazedPlumb.Pipes.tick()          -- wear first, so a pipe broken this minute feeds nothing
    DazedPlumb.Mains.beforeFlow()    -- the panel's figures: which fixtures lost water since the last fill
    DazedPlumb.Links.tick()
    DazedPlumb.Mains.afterFlow()     -- litres this minute, today's chart, drain on shut-off
    DazedPlumb.Mains.housekeep()     -- forget mains that were lifted
    DazedPlumb.Pumps.housekeep()     -- forget refilled wells with no pump (every ten minutes)
end)
