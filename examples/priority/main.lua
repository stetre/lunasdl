-- Main script: main.lua
local sdl = require("lunasdl")

sdl.logopen("example.log")
sdl.traceson()

-- set the number of priority levels:
sdl.prioritylevels(3)

assert(sdl.createsystem(nil,"system"))
