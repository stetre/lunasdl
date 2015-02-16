-- Agent script: caller.lua

function AtReturn(...)
   sdl.printf("AtReturn(%s)",table.concat({...},","))
   sdl.restore()
end

function Active_Start()
   sdl.printf("%s: received %s", name_, signame_)
   -- call the procedure, passing it some parameters
   sdl.procedure(AtReturn, "Procedure", "procedure", "hello",1,2,3)
end

function Active_Stop()
   sdl.printf("%s: received %s", name_, signame_)
   sdl.stop()
end

function Received()
   sdl.printf("%s: received '%s' from %u",name_,signal_[2],sender_)
end

function Init() 
   sdl.nextstate("Active")
end

sdl.start(Init)
sdl.transition("Active","START",Active_Start)
sdl.transition("Active","STOP",Active_Stop)
sdl.transition("Active","*", Received)
