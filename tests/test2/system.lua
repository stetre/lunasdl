-- system.lua

local T = sdl.timer(60,"T") 

local ip = "127.0.0.1"
local n_tests = 1
local baseport = 8080
local timeout = 30
local test = {}     -- agent' pids
local index = {}    -- pid to test index
local ready = {}
local n_ready = 0
local n_failure = 0
local n_success = 0
local n_started = 0
   
local function Start(n, port, t)
   n_tests = n or n_tests
   baseport = port or baseport
   timeout = t or timeout

   local port = baseport
   for i=1,n_tests do
      remport = port + 1
      test[i] = { }
      sdl.create(nil,"responder", ip, remport, timeout)
      test[i].responder = offspring_
      index[offspring_] = i
      sdl.create(nil,"initiator", ip, port, ip, remport, timeout)
      test[i].initiator = offspring_
      index[offspring_] = i
      port = port + 2
   end
   sdl.set(T)
   sdl.nextstate("WaitingReady")
end


local function SendStart()
   if n_ready < (2 * n_tests) then return end
   sdl.reset(T)
   for i=1,n_tests do
      local t = test[i]
      if ready[t.responder] and ready[t.initiator] then
         sdl.send({ "START" }, t.initiator )
         n_started = n_started + 1
      end
   end
   if n_started == 0 then sdl.kill(self_) end
   sdl.nextstate("Active")
end   
      
local function WaitingReady_Ready()
   n_ready = n_ready + 1
   ready[sender_] = true
   SendStart()
end   
      
local function WaitingReady_Failure()
   ready[sender_] = false  
   n_ready = n_ready + 1
   n_failure = n_failure + 1
   SendStart()
end

local function WaitingReady_T()
   --sdl.printf("error")
   sdl.kill(self_)
end

local function Finish()
   local n = n_success + n_failure
   if n == n_ready then
      sdl.systemreturn(n_tests, n_success/2, n_failure/2)
      return sdl.stop()
   end
end
   
local function Active_Success()
   n_success = n_success + 1
   Finish()
end

local function Active_Failure()
   n_failure = n_failure + 1
   Finish()
end

sdl.start(Start)
sdl.transition("WaitingReady","READY",WaitingReady_Ready)
sdl.transition("WaitingReady","FAILURE",WaitingReady_Failure)
sdl.transition("WaitingReady","T",WaitingReady_T)
sdl.transition("Active","SUCCESS",Active_Success)
sdl.transition("Active","FAILURE",Active_Failure)
