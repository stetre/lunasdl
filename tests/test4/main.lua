sdl = require("lunasdl")

local maxlevels = tonumber(({...})[1]) or 3

sdl.logopen("test.log")
sdl.traceson() sdl.tracesoff("switch")
assert(sdl.createsystem(nil, "system", maxlevels))
