-- Main script: main.lua

local sdl = require("lunasdl")

local duration = tonumber(({...})[1]) or 10 -- seconds
local interval = tonumber(({...})[2]) or 1 -- seconds

sdl.logopen("example.log")

assert(sdl.createsystem("System","system",duration,interval))
