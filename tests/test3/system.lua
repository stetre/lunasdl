-- system.lua

local server
local client = {}
local n_success = 0
local n_failure = 0
local n_tests = 1
local ncli = 0
local params 

local T = sdl.timer(.001,"T")

local function Start(nclients, ip, port, npings, ping_int, timeout)
   n_tests = nclients or n_tests
   params = { ip, port, npings, ping_int, timeout }
-- sdl.printf("%s: %u",name_, n_tests)

   server = assert(sdl.create("Server", "server", ip, port))
   sdl.set(T)
   sdl.nextstate("Active")
end

local function Active_T()
   if ncli < n_tests then 
      client[ncli] = sdl.create(string.format("Client%u",ncli), "client", table.unpack(params))
      ncli = ncli + 1
   end
   if ncli == n_tests then 
      sdl.modify(T,1,"Tmonitor")
   end
   sdl.set(T)
end

local function Active_Tmonitor()
   --sdl.printf("tests=%u, succeeded=%u, failed=%u",n_tests,n_success,n_failure)
   sdl.set(T)
end


local function Finished()
   local n = n_success + n_failure
   if n == ncli then
      sdl.systemreturn(ncli, n_success, n_failure)
      sdl.send({ "STOP" }, server)  
      sdl.stop()
   end
end

local function Active_Success()
   n_success = n_success + 1
   Finished()
end

local function Active_Failure()
   n_failure = n_failure + 1
   sdl.logf("FAILURE '%s'",signal_[2])
   Finished()
end

sdl.start(Start)
sdl.transition("Active","T",Active_T)
sdl.transition("Active","Tmonitor",Active_Tmonitor)
sdl.transition("Active","SUCCESS",Active_Success)
sdl.transition("Active","FAILURE",Active_Failure)
