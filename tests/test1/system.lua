-- system.lua

local ts = sdl.now() -- timestamp

local utils = require("lunasdl.utils")
local delays = {} -- delays returned by agents

local T = sdl.timer(0.0001,"T") -- "create" timer

local n_agents = 1000 -- number of agents
local stopped = 0    -- number of agents that stopped
local agent = {}     -- agents' pids
local next_agent = 1
   
local function Active_T()
   sdl.create(nil,"agent")
   agent[next_agent] = offspring_
   sdl.send({ "STOP" }, offspring_)
   if next_agent < n_agents then
      next_agent = next_agent +1
      sdl.set(T)
   end
end

local function Start(n) 
   n_agents = n or n_agents
   sdl.set(T)
   sdl.nextstate("Active")
end

local function Active_Stopping()
   stopped = stopped+1
   delays[#delays+1] = signal_[2] -- signals' delays
   --print(#delays, delays[#delays])
   if stopped == n_agents then
      local elapsed = sdl.since(ts)
      local mean, var, min, max = utils.stats(delays)
      sdl.systemreturn(n_agents, elapsed, mean,var,min,max)
      sdl.stop()
   end
end

sdl.start(Start)
sdl.transition("Active","T",Active_T)
sdl.transition("Active","STOPPING",Active_Stopping)
