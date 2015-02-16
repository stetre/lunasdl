-- Agent script: initiator.lua

socket = require("socket")

local timeout = 10
local T = sdl.timer(timeout,"T")
local s, remip, remport

function Stop()
   if s then
      sdl.deregister(s)
      s:close()
   end
   sdl.stop()
end

function Failure(reason)
   sdl.send({ "FAILURE", reason }, parent_)
   Stop()
end

local function Receive() -- socket 'read' callback
   local msg, fromip, fromport = s:receivefrom()
   sdl.logf("received '%s' from %s:%s",msg,fromip,fromport)
   if msg ~= "pong" or state_ ~= "Waiting" then return end -- ignore
   sdl.send({ "SUCCESS" }, parent_)
   Stop()
end

function Start(ip, port, remIp, remPort, t)
   local ok, errmsg
   timeout = t or timeout
   remip = remIp
   remport = remPort 
   
   -- create a UDP socket and bind it to ip:port
   sdl.logf("opening initiator %s:%u",ip,port)
   s , errmsg = socket.udp()
   if not s then Failure(errmsg) return end
   ok, errmsg = s:setsockname(ip,port)
   if not ok then Failure(errmsg) return end
   ok, errmsg = s:setoption("reuseaddr",true)
   if not ok then Failure(errmsg) return end
   sdl.register(s, Receive)

   sdl.send({ "READY" }, parent_)

   sdl.nextstate("Idle")
end


function Idle_Start()
   s:sendto("ping",remip,remport)
   sdl.set(T,sdl.now()+timeout)
   sdl.nextstate("Waiting")
end


function Waiting_T()
   Failure("timer expired")
end

sdl.start(Start)
sdl.transition("Idle","START", Idle_Start)
sdl.transition("Waiting","T", Waiting_T)

