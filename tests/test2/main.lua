local socket = require("socket")
local sdl = require("lunasdl")
local utils = require("lunasdl.utils")

local n = tonumber(({...})[1]) or 1 -- no. of tests (0->max)
local port = tonumber(({...})[2]) or 8080 -- base port
local timeout = tonumber(({...})[3]) or 10 -- timeout
local rep = tonumber(({...})[4]) or 3 -- no. of repetitions

sdl.logopen("test.log")
--sdl.traceson()

local ts = sdl.now()
print("hello world")
sdl.printf("print('hello world') executed in %.0f us",sdl.since(ts)*1e6)
sdl.printf("maximum number of file descriptors is %u",socket._SETSIZE)

max = math.floor(socket._SETSIZE / 2) - 2 
if n == 0 or n > max then 
   n = max 
   sdl.printf("limiting n to %u",n)
end

for k=1,rep do
   local ts = sdl.now()
   io.write(string.format("%u - running %u tests.....",k,n)) io.flush()
   local ok, m, nok, nko = sdl.createsystem(nil,"system", n, port, timeout)
   if not ok then
      io.write(string.format("test failed (%s)\n",m))
   else
      io.write(string.format("%.0f succeeded, %.0f failed (%.3f s)\n"
      ,nok, nko, sdl.since(ts)))
   end
   io.flush()
end
