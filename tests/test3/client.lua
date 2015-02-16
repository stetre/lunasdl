-- Agent script: client.lua

socket = require("socket")

local timeout = 10
local interval = 1 -- ping interval
local npings = 3 -- no. of pings
local counter = 0 -- sent pings
local T1 = sdl.timer(interval,"T1") -- ping timer
local T2 = sdl.timer(timeout,"T2") -- error timer
local s, srvip, srvport

function Stop()
   if s then
      sdl.logf("%s: closing %s:%s",name_,s:getsockname())
      --s:shutdown()
      sdl.deregister(s)
      s:close()
   end
   sdl.stop()
end

function Failure(reason)
   sdl.printf("failure '%s'",reason)
   sdl.send({ "FAILURE", reason }, parent_)
   Stop()
end

local function Send() -- socket 'send' callback
   sdl.logf("@@")
end

local function Ping()
   counter = counter + 1
   s:send("ping\n")
   if counter < npings then sdl.set(T1) end
   sdl.set(T2)
end

local function Receive(s) -- socket 'read' callback
   local data, err = s:receive()
   sdl.logf("%s: received '%s' from %s:%s", name_, data, s:getpeername())
   if data ~= "pong" then return end -- ignore
   if counter == npings then
      sdl.send({ "SUCCESS" }, parent_)
      Stop()
   end
end

function Start(ip, port, n, int, t)
   local ok, errmsg
   srvip = ip
   srvport = port 
   npings = n or npings
   interval = int or interval
   timeout = t or timeout
   
   sdl.modify(T1,interval)
   sdl.modify(T2,timeout)
   
   
   sdl.logf("%s: connecting to %s:%u", name_, ip, port)
   s , errmsg = socket.connect(ip, port)
   if not s then Failure(errmsg) return end
   sdl.logf("%s: connected (%s:%u)", name_, s:getsockname())
   ok, errmsg = s:setoption("reuseaddr",true)
   if not ok then Failure(errmsg) return end
   sdl.register(s, Receive)
   --sdl.register(s, Receive, Send)
   Ping()
   sdl.nextstate("Active")
end

function Active_T1()
   Ping()
end

function Active_T2()
   Failure("T2 expired")
end

sdl.start(Start)
sdl.transition("Active","T1", Active_T1)
sdl.transition("Active","T2", Active_T2)

