-- System agent script: system.lua

socket = require("socket")

local T1 = sdl.timer(10,"T1")
local player
local s, peerip, peerport, role


local function udprecv() -- socket 'read' callback
   -- get the UDP datagram and the sender's address
   local msg, fromip, fromport = s:receivefrom()
   sdl.printf("received '%s' from %s:%s",msg,fromip,fromport)

   -- check that it is an expected message
   assert(msg == "PING" or msg == "PONG" or msg == "STOP")

   -- send the corresponding signal to the local player agent
   sdl.send({ msg, self_ }, player)
   if msg == "STOP" then
      sdl.stop()
   end
end


function Start(ip, port, remip, remport, duration, ping_interval)
   peerip = remip
   peerport = remport
   role = ping_interval and "initiator" or "responder"
   
   sdl.printf("starting %s at %s:%s (peer system is at %s:%s)", 
         role,ip,port,peerip,peerport)

   -- create a UDP socket and bind it to ip:port
   s = assert(socket.udp())
   assert(s:setsockname(ip,port))
   assert(s:setoption("reuseaddr",true))

   -- register the socket in the event loop
   sdl.register(s, udprecv)

   -- create the player agent 
   player=sdl.create("player","pingpong.player", ping_interval) -- 

   -- send it the start signal (initiator side only)
   if role == "initiator" then
      sdl.send({ "START", self_ }, player )
   end

   -- start the overall timer
   sdl.set(T1,sdl.now()+duration)

   sdl.nextstate("Active")
end


function Active_T1Expired()
   sdl.send({ "STOP" }, player )
   s:sendto("STOP",peerip,peerport)
   sdl.stop(function () sdl.deregister(s) s:close() end) 
end


function Active_Any() 
   -- signal from local player, redirect signal name to peer system
   s:sendto(signame_,peerip,peerport)
end


sdl.start(Start)
sdl.transition("Active","T1",Active_T1Expired)
sdl.transition("Active","*",Active_Any)

