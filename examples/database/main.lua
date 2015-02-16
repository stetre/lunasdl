-- Main script: main.lua

local sdl = require("lunasdl")

-- get the no. of entries in the database
local n_entries = tonumber(({...})[1]) or 1000 

sdl.logopen("example.log")

assert(sdl.createsystem(nil,"system", n_entries))
