
local level
local s = ""

function AtReturn(ss)
   s = s .. " " .. ss
   sdl.restore()
end

function Waiting_Stop()
   sdl.printf("level=%u: received STOP", level)
   sdl.save()
   sdl.procreturn(s)
end

function Start(lvl, maxlvl)
   level = lvl
   sdl.printf("level=%u parent=%u caller=%u",level, parent_, caller_)
   
   s = "" .. level
   if level < maxlvl then
      sdl.procedure(AtReturn, nil, "procedure", level+1, maxlvl)
   end
   sdl.nextstate("Waiting")
end

sdl.start(Start)
sdl.transition("Waiting","STOP",Waiting_Stop)
