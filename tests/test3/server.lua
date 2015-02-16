-- Agent script: server.lua

socket = require("socket")

local s 
local cli = {} 

function Close(c)
   sdl.logf("%s: %s:%s disconnected", name_, c:getpeername())
   sdl.deregister(c)
   c:close()
   cli[c]=nil
end


function Stop()
   if s then
      sdl.deregister(s)
      s:close()
   end
   sdl.stop()
end

function Failure(reason)
   sdl.printf("failure '%s'",reason)
-- sdl.send({ "FAILURE", reason }, parent_)
   Stop()
   os.exit()
end


local function Receive(c)
   local data, err = c:receive()
   sdl.logf("%s: received '%s' from %s:%s",name_, data, c:getpeername())
   if data ~= "ping" then return end -- ignore
   c:send("pong\n")
end


local function Accept(s)
   local c, err = s:accept()
   if not c then
      sdl.logf(err)
      return
   end
   sdl.logf("%s: %s:%s connected", name_, c:getpeername())
   sdl.register(c, Receive)
   cli[c] = true
end


function Start(ip, port, backlog)
   local ok, err
   
   sdl.logf("%s: opening server %s:%u",name_, ip,port)
   s , err = socket.bind(ip,port)
   if not s then Failure(err) return end
   ok, err = s:setoption("reuseaddr",true)
   if not ok then Failure(err) return end
   sdl.register(s, Accept)

   sdl.nextstate("Active")
end


function Active_Stop()
   sdl.logf("%s: closing server %s:%u",name_,s:getsockname())
   sdl.deregister(s)
   s:close()
   for c in pairs(cli) do Close(c) end
   Stop()
end

sdl.start(Start)
sdl.transition("Active","STOP", Active_Stop)

