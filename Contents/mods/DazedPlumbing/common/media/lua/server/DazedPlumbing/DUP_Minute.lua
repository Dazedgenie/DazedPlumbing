--[[ Dazed Plumbing -- the one once-a-minute pass (authority only).
     Tanks, pipes and mains, smokers and digesters each register a step here instead of hooking EveryOneMinute on their own,
     so the minute is one hook that runs them in a fixed order, and a step that errors is logged without stopping the rest. ]]

DazedPlumb = DazedPlumb or {}
local M = DazedPlumb.Minute or {}
DazedPlumb.Minute = M
M.steps = M.steps or {}

-- add(name, order, fn): a step with the same name replaces the old one (a file loaded twice stays one step).
function M.add(name, order, fn)
    for i, s in ipairs(M.steps) do
        if s.name == name then table.remove(M.steps, i) break end
    end
    M.steps[#M.steps + 1] = { name = name, order = order, fn = fn }
    table.sort(M.steps, function(a, b) return a.order < b.order end)
end

function M.run()
    if isClient and isClient() then return end
    for _, s in ipairs(M.steps) do
        local ok, err = pcall(s.fn)
        if not ok then print("DazedPlumbing: minute step '" .. s.name .. "' failed: " .. tostring(err)) end
    end
end

if not M.hooked then
    M.hooked = true
    Events.EveryOneMinute.Add(function() M.run() end)
end
