-- agent.lua

local delay

local function Stop() 
   if state_ == "Stopping" then
      sdl.send({ "STOPPING", delay }, sender_)
      sdl.stop()
   else
      sdl.nextstate("Stopping")
   end
end

local function Active_Stop()
   --sdl.printf("%s: received %s state=%s",name_, signame_,state_)
   Stop()
end

local function AtReturn(dly)
   delay = dly
   Stop()
end

local function Init() 
   sdl.procedure(AtReturn, nil, "procedure")
   sdl.nextstate("Active")
end

sdl.start(Init)
sdl.transition("Active","STOP",Active_Stop)
sdl.transition("Stopping","STOP",Active_Stop)
