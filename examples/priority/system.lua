-- System agent: system.lua

local function Send(n)
-- if n=nil, self-sends a signal named 'NORMAL' without priority
-- otherwise self-sends a signal named 'LEVELn', with priority n
   if not n then
      sdl.send({ string.format("NORMAL") }, self_)
   else
      sdl.send({ string.format("LEVEL%u",n) }, self_, n)
   end
end

function Start()
   -- send a few signal with different priorities to self

   -- this has no priority (i.e. lower than lowest priority):
   Send()   

   -- these also have no priority because their level is higher
   -- than the configured number (=3) of priority levels:
   Send(5)  
   Send(4) 

   -- these have increasing priorities:
   Send(3) -- lowest (> no priority)
   Send(2) -- medium priority
   Send(1) -- highest (level 1 is always the highest)

   -- this has priority 1 because the receiver decided so
   -- by using the sdl.priorityinput function (see below)
   Send(6)

   -- finally, this also has no priority, and since signals with
   -- the same priority are dispatched first-in-first-out, it 
   -- should arrive last:
   sdl.send({ "STOP" }, self_ ) 

   -- summarizing, the order of arrival should be the following:
   sdl.printf("expected order of arrival:")
   sdl.printf("LEVEL1, LEVEL6, LEVEL2, LEVEL3, NORMAL, LEVEL5, LEVEL4, STOP")

   sdl.nextstate("Active")
end

function Recvd() sdl.printf("received %s",signame_) end

sdl.start(Start)
sdl.transition("Active","*", Recvd)
sdl.transition("Active","STOP", function () Recvd() sdl.stop() end)

-- set the priority of 'LEVEL6' input signals to 1 (i.e. highest priority):
sdl.priorityinput("LEVEL6",1)
