-- Procedure script: procedure.lua

local cnt = 0

function Waiting_Any()
   -- notice that sender_ is not self_ but caller_
   sdl.printf("%s: received '%s' from %u",name_,signal_[2],sender_)
   cnt = cnt +1
   -- save the signal for the caller:
   sdl.save()
end

function Waiting_Return()
   sdl.printf("%s: received %s from %u",name_,signame_,sender_)
   -- return from procedure, with return values:
   return sdl.procreturn("received verses",cnt)
   -- no code after sdl.procreturn()
end


function Init(...) 
   sdl.printf("%s: Init(%s)",name_,table.concat({...},","))
   -- time-triggered signals are handy in procedures because procedures
   -- can not create timers...
   sdl.sendat({ "RETURN" }, self_, sdl.now() + 5)
   sdl.nextstate("Waiting")
end


sdl.start(Init)
sdl.transition("Waiting","RETURN",Waiting_Return)
sdl.transition("Waiting","*",Waiting_Any)

