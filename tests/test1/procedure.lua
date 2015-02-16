
local tsend

local function Start()
   --tsend= sdl.sendat({ "RETURN" }, self_, sdl.now()+1)
   tsend = sdl.send({ "RETURN" }, self_)
   sdl.nextstate("Active")
end

local function Active_Return()
   local delay = recvtime_ - tsend
   --sdl.printf("%s: received %s",name_,signame_)
   sdl.procreturn(delay)
end

local function Any_Any()
   --sdl.printf("%s: received %s",name_,signame_)
   sdl.save()
end

sdl.start(Start)
sdl.transition("Active","RETURN",Active_Return)
sdl.transition("Any","*",Any_Any)
sdl.default("Any")
