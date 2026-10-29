-- LÖVE config for the data exporter: no window, no audio, nothing but Lua.
function love.conf(t)
    t.identity = "crimson-red-export"
    t.version  = "11.4"
    t.window   = false
    for k in pairs(t.modules) do t.modules[k] = false end
    t.modules.filesystem = true
    t.modules.system     = true
    t.modules.event      = true
end
