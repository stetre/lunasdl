-- System agent script: system.lua

local caller -- caller agent's pid
local T1 = sdl.timer(1,"T1")
local cnt = 0

local lyrics = {
   "Softly glowing, watch the river flowing",
   "It's reflections shine into my eyes",
   "I see clearer when you hold the mirror",
   "And can reach the stars up in the sky tonight",
   "(Under the moonlight, dancing in the moonlight)",
   "All around the universe, you're looking down",
   "I know you're watching over me",
   "La Luna, is it a mild case of madness?",
   "(Under the moonlight, underneath the moonlight)",
   "La Luna, you take me out of the darkness",
   "(Under the moonlight, dancing in the moonlight)"
}

function Active_T1()
   cnt = cnt+1
   local v = lyrics[cnt]
   if v then
      sdl.send({ "VERSE", v }, caller)
      sdl.set(T1)
   else
      sdl.sendat({ "STOP" }, caller, sdl.now() + 2)
      sdl.printf("%s: stopping", name_)
      sdl.stop()
   end
end 

function Start()
   caller = sdl.create("Caller","caller")
   sdl.send({ "START" }, caller)
   sdl.set(T1)
   sdl.nextstate("Active")
end


sdl.start(Start)
sdl.transition("Active","T1",Active_T1)
