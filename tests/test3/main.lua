local socket = require("socket")
local sdl = require("lunasdl")

local port = tonumber(({...})[1]) or 8080 -- server port
local n = tonumber(({...})[2]) -- no. of tests (nil->max)
local npings = tonumber(({...})[3]) or 3
local ping_int = tonumber(({...})[4]) or 1
local timeout = tonumber(({...})[5]) or 10 -- timeout
local rep = tonumber(({...})[6]) or 3 -- no. of repetitions
local ip = "127.0.0.1"

--sdl.logopen("test.log")
--sdl.traceson() sdl.tracesoff("switch")

local ts = sdl.now()
print("hello world")
sdl.printf("print('hello world') executed in %.0f us",sdl.since(ts)*1e6)
sdl.printf("maximum number of file descriptors is %u",socket._SETSIZE)

max = math.floor(socket._SETSIZE/2) - 2
if not n or n > max then 
   n = max 
   sdl.printf("limiting n to %u",n)
end


for k=1,rep do
   local ts = sdl.now()
   io.write(string.format("%u - running %u tests.....",k,n)) io.flush()
   local ok, m, nok, nko = sdl.createsystem(nil,"system",n,ip,port,npings,ping_int,timeout)
   if not ok then
      io.write(string.format("test failed (%s)\n",m))
   else
      io.write(string.format("%.0f succeeded, %.0f failed (%.3f s)\n",nok, nko, sdl.since(ts)))
   end
   ok, m, nok, nko = nil, nil, nil, nil
   io.flush()
end
