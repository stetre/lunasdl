local sdl = require("lunasdl")
local utils = require("lunasdl.utils")

local n = tonumber(({...})[1]) or 100
local rep = tonumber(({...})[2]) or 3

--sdl.logopen("test.log")
--sdl.traceson("signal","agent")

local ts = sdl.now()
print("hello world")
print(string.format("print('hello world') executed in %.0f us",sdl.since(ts)*1e6))

for k=1,rep do
   io.write(string.format("%u - creating %u agents.....",k,n)) io.flush()
   local ok, m, elapsed, mean = sdl.createsystem("System","system", n)
   if not ok then
   io.write(string.format("test failed (%s)\n",m))
   else
   io.write(string.format("test succeded in %.1f s, average signal delay is %.0f us\n",
                        elapsed, mean*1e6))
   end
   io.flush()
end

