-- Agent script: hello.lua

local T = sdl.timer(1,"T_EXPIRED")

function Start()
   print("Just one second...")
   sdl.set(T)
   sdl.nextstate("Waiting")
end

function TExpired()
   print("Hello World!")
   sdl.stop()
end

sdl.start(Start)
sdl.transition("Waiting","T_EXPIRED",TExpired)
