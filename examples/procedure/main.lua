-- Main script: main.lua

local sdl = require("lunasdl")

sdl.logopen("example.log")
sdl.traceson()

assert(sdl.createsystem("System","system"))
