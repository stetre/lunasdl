
function AtReturn(s)
   sdl.printf("procedure returned '%s'",s)
   sdl.nextstate("Waiting")
end

function Waiting_Stop()
   sdl.printf("caller: received STOP")
   sdl.stop()
end

function Start(maxlevel)
   sdl.procedure(AtReturn, nil, "procedure", 1, maxlevel)
   sdl.send({ "STOP" }, self_)
   sdl.nextstate("-")
end

sdl.start(Start)
sdl.transition("Waiting","STOP",Waiting_Stop)
