-- System agent script: system.lua

local T1 = sdl.timer(10,"T1_EXPIRED")
local player1, player2

function Start(duration, interval)
   local duration = duration or 10
   local interval = interval or 1
   sdl.printf("%s: duration=%u s, interval=%u s",name_,duration, interval)

   player1=sdl.create("player1","player",interval)
   player2=sdl.create("player2","player")

   sdl.send({ "START", player2 }, player1 )
   sdl.set(T1,sdl.now()+duration)

   sdl.nextstate("ACTIVE")
end

function Active_T1Expired()
   sdl.send({ "STOP" }, player1 )
   sdl.send({ "STOP" }, player2 )
   sdl.stop()  
end

sdl.start(Start)
sdl.transition("ACTIVE","T1_EXPIRED",Active_T1Expired)

