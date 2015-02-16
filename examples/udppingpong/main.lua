-- Main script: main.lua
local sdl = require("lunasdl")

local port = tonumber(({...})[1]) or 8080
local duration = tonumber(({...})[2]) or 10 -- seconds
local interval = tonumber(({...})[3]) -- (or nil) seconds 

local role = interval and "initiator" or "responder"

local ip = "127.0.0.1"
local remip = ip
local remport = port+1

if role == "initiator" then --swap UDP address
   port, remport = remport, port
   ip, remip = remip, ip
end

sdl.logopen(string.format("%s.log",role))
sdl.traceson()

assert(sdl.createsystem("system","system",ip,port,remip,remport,duration,interval))
