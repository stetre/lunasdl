--=============================================================================
-- LunaSDL engine                                                       
--=============================================================================

local socket = require("lunasdl.socket")
local reactor = require("lunasdl.reactor")
local utils = require("lunasdl.utils")
local timers = require("lunasdl.timers")
local array = require("lunasdl.array")
local fifo = require("lunasdl.fifo")
local fifoarray = require("lunasdl.fifoarray")
local heap = require("lunasdl.heap")

local DEFAULT_PATH = "?;?.lua" -- path for agent scripts
local DEFAULT_NPRIO = 1    -- no. of priority levels
local DEFAULT_GETTIME = socket.gettime -- not guaranteed to be monotonic
local DEFAULT_POLLFUNC = socket.select -- select function for reactor
local DEFAULT_POLLADD = nil --function(object, mode) return true end
local DEFAULT_POLLDEL = nil --function(object, mode) return true end
local DEFAULT_POLLRESET = nil --function() return true end 

-- singleton sdl table
local sdl = {
   _VERSION = "LunaSDL 0.2",
   path = DEFAULT_PATH, -- path to scripts (package.path like)
} 


-- get path from LUNASDL_PATH, if defined
local p = os.getenv("LUNASDL_PATH")
if p then 
   -- substitute any ';;' with the default path:
   sdl.path = string.gsub(p,";;", function () return ";"..DEFAULT_PATH..";" end)
end


local nextpid = 0       -- next pid to be assigned
local ENV = {}          -- agents' Lua environments table, indexed by pid
local ENV_TEMPLATE      -- template for agent's dedicated environment
local pidstack = {}     -- stack of pids for switching between processes

local scheduler = {}     -- normal signals scheduler
local scheduler1 = {}    -- alter ego

local nprio = DEFAULT_NPRIO   -- no. of priority levels (N)
local prioschedulers = {} -- priority schedulers 1 (highest) .. N (lowest)
local prioschedulers1 = {} -- alter egos
-- normal scheduler corresponds to N+1 (lower than lowest)

local logfilename          -- log file name
local logfile              -- log file handle
local logenabled = false   -- enable logs in logfile
local traceflag = nil      -- traces mode nil = disabled, 
local traceinclude         -- enabled traces
local traceexclude         -- disabled traces

local loaders = {}   -- loaders[script] = { loader, fullname }
 

-- forward declarations
local gettmrinfo
local timercreatedisabled
local timercreate
local timerdelete 
local timeractive
local timerset
local timerreset
local timermodify
local ttsend
local deregister
local register
local configfunctions
local systemfunctions

local function sdlreset()
   sdl_ = nil
   timers.deleteall()
   ENV = {}
   pidstack = {}
   scheduler = {}
   scheduler1 = {}
   nprio = DEFAULT_NPRIO
   prioschedulers = {}
   prioschedulers1 = {}
   nextpid = 0
   configfunctions()
end

--=============================================================================
-- Miscellanea
--=============================================================================

local assertf = utils.assertf
local copytable = utils.copytable

local pollfunc = DEFAULT_POLLFUNC
local polladd = DEFAULT_POLLADD
local polldel = DEFAULT_POLLDEL
local pollreset = DEFAULT_POLLRESET

local gettime = DEFAULT_GETTIME
local NEVER = math.huge

local startingtime = gettime()
function sdl.startingtime() return startingtime end
local now = function () return gettime() - startingtime end
local function since(ts) return now() - ts end
sdl.now = now
sdl.since = since


local osexit = os.exit -- save the original os.exit
os.exit = function(code,close) -- override
-- if code == nil then code = true end
-- if close == nil then close = true end
   sdl.logclose()
   osexit(code,close)
end
   
-- reactor controlled garbage collection @@ documentare ?
function sdl.gcon(threshold) return reactor.gcon(threshold) end
function sdl.gcoff() return reactor.gcoff() end

--=============================================================================
-- SDL agents                                                              
--=============================================================================
--[[

   ENV[pid]    -- dedicated Lua environment for agent identified by pid
                  (_ENV=ENV[pid] when the agent is the current)

   Locally global variables (ie, stored as globals in ENVpid):

   self_       current agent's pid
   name_       agent name
   block_      block identifier (pid of the root block)
   parent_     parent's pid
   state_      current state
   signal_     current signal
   signame_    current signal name (same as signal_[1])
   sender_     sender of current signal (pid or tid)
   caller_     the pid of the original procedure caller (procedure)
   sendtime_   send timestamp of current signal
   recvtime_   receive timestamp of current signal
   exptime_    time of expiration of the current signal
   istimer_    true if the current signal is from a timer
   offspring_  pid of last created agent (process or block)

   For internal use only:
   sdl_ = { 
   names = {} or nil,   name <-> pid map (= nil if not a block)
   children = array(),  pids of (direct) children
   timers = array(),    tids of timers owned by this agent
   states = {},         state-machine table
   defstate = nil,      default state ("asterisk" state)
   saved = fifo(),      saved signals queue
   exportedfunc = {},   list of exported functions 
                        (exportedfunc["funcname"]=func)
   startfunc = nil,     start transition function
   procedureof          if this is a procedure call, contains the pid of 
                        the agent the procedure acts on behalf of
                        = nil if not a procedure call
   isblock = false,     true if this is a block
   procedure = nil,     pid of called procedure where to redirect signals
   atreturn = nil,      function to be called when the procedure returns 
                        or nextstate (string) or nil
   atstopfunc = nil,    function to be called when the agent actually terminates
   inputpriority = {}   priorities for input signals
   }

--]]

local function agentkind(env)
-- returns the kind of the agent whose environment is env
   local env = env or _ENV
   if env.caller_ then
      return "procedure" -- not really a 'kind', but...
   elseif env.sdl_.isblock then 
      return env.self_ == 0 and "system" or "block"
   else
      return "process"
   end
end

-------------------------------------------------------------------------------
local function switchto(pid, noerr)
-- Makes agent identified by pid the current agent and returns true.
-- If pid is unknown, its behaviour depends on the value of 'noerr':
-- 1) noerr == false or nil: raises an error 
-- 2) noerr == true: leaves the current agent unchanged and returns false 
--  (in this case the caller must not call the corresponding switchback())
   local env = ENV[pid]
   if not env then 
      if noerr then 
         return false
      else
         error(string.format("unknown pid=%u",pid)) --[bug]
      end
   end
   pidstack[#pidstack+1] = self_ -- push current
   sdl.trace("switch","switchto ->%u [%s]",pid,table.concat(pidstack,","))
   _ENV = env
   return true
end

local function switchback()
-- switch back to the previous agent on the stack
   assertf(2,#pidstack>0,"too many switchback() calls") -- [bug]
   local pid = pidstack[#pidstack]
   sdl.trace("switch","switchback ->%u [%s]",pid,table.concat(pidstack,","))
   local env = ENV[pid]
   if not env then -- agent has terminated
      error(string.format("switchback to %u (exited)",pid)) --[bug]
   end
   _ENV = env
   pidstack[#pidstack]=nil
end


-------------------------------------------------------------------------------
local function searchscript(script)
-- searches script and loads it (if not already loaded)
   local ld = loaders[script]
   if ld then return ld end 
   ld = {}
   local fullname, errmsg = package.searchpath(script,sdl.path)
   if not fullname then return nil, errmsg end
   local loader, errmsg = utils.loadscript(fullname)
   if not loader then return nil, errmsg end
   ld.fullname = fullname
   ld.loader = loader
   loaders[script] = ld -- for future use...
   return ld
end

--**********************************************************************
local function newagent(isblock, isprocedure, atreturn, name, script, ...)
--**********************************************************************
-- isblock = true if block or system, false otherwise
-- isprocedure = true if procedure, false otherwise
-- local ts = now()
   if name and type(name)~="string" then 
      return nil, "name must be a string" 
   end
   if type(script)~="string" then 
      return nil, "missing or invalid script" 
   end
   if atreturn and type(atreturn)~="function" and type(atreturn)~="string" then
      return nil, "invalid atreturn"
   end

   local isprocess = not isblock and not isprocedure

   if isblock and not sdl_.isblock then
      return nil, string.format("cannot create block from within a %s",agentkind())
   end

   --[[
   -- a block agent can contain processes or blocks, a process agent can contain
   -- only other processes (SDL-2000 for New Millennium Systems - R. Reed)
   -- @@ a block can contain blocks and processes but not both, 
   --    a process cannot contain blocks nor processes
   --]]

   -- assign pid
   local pid = nextpid
   if ENV[pid] ~= nil then return nil, "nextpid in use" end
   nextpid = nextpid + 1

   -- create the dedicated environment and the sdl_ table
   local env
   if self_ == 0 and ENV[0]==nil then
      env = _ENV
   else
      env = copytable(ENV_TEMPLATE)
      env.sdl_ = {}
   end
   ENV[pid] = env
   env.sdl_.isblock = isblock
   env.isprocess_ = isprocess
   env.self_ = pid
   env.parent_ = self_ -- we still are in the parent's env
   if env.sdl_.isblock then env.sdl_.names = {} end

   local penv = ENV[env.parent_] -- parent agent

   -- insert in parent's children list
   if pid ~= 0 then 
      if not penv.sdl_.children then penv.sdl_.children = array() end
      penv.sdl_.children:insert(pid)
   end 

   if isprocedure then
      if not name then name = string.format("procedure%u",pid) end
      env.name_ = name
      assert(sdl_.procedure==nil) -- should not happen
      penv.sdl_.procedure = pid
      penv.sdl_.atreturn = atreturn
      env.caller_ = penv.caller_ or penv.self_
      env.sdl_.inputpriority = penv.sdl_.inputpriority
   else
      env.caller_ = nil
      if not name then name = string.format("agent%u",pid) end
      env.name_ = name 
      env.sdl_.inputpriority = {}   
   end

   -- insert in nametopid map of the containing block
   env.block_ = penv.sdl_.isblock and penv.self_ or penv.block_
   local benv = ENV[env.block_] -- block root agent
   if benv.sdl_.names[env.name_] ~= nil then 
      local errmsg = string.format("duplicated agent name '%s' in block '%s'"
                              ,env.name_,benv.name_)
      penv.sdl_.children:remove(pid)
      ENV[pid] = nil 
      env = nil
      return nil, errmsg
   end
   benv.sdl_.names[env.name_] = pid

   env.sdl_.states = {}
   -- All these are created only when needed:
   -- env.sdl_.exportedfunc = {}
   -- env.sdl_.timers = array()
   -- env.sdl_.children = array()
   -- env.sdl_.saved = fifo()

   -- finally, switch to the new agent and execute the agent script 
   -- and the start transition
   --------------------------------------------------------------
   switchto(pid) -- now _ENV = env

   local errmsg
   -- enable the creation of timers
   if not caller_ then sdl.timer = timercreate end

   -- load the script
   local ld
   ld, errmsg = searchscript(script)
   if not ld then goto failure end

   sdl.trace("agent","%s '%s' (%s) block=%u parent=%u",
                     agentkind(),name_,ld.fullname,block_,parent_)

   -- execute the script
   state_ = "?" -- the script should change this with a nextstate() or a stop()
   ld.loader(_ENV) 

   sdl.timer = timercreatedisabled -- rien ne va plus for timer creation

   -- execute the start transition function
   if not sdl_.startfunc then
      errmsg = string.format("missing sdl.start() in script '%s'",ld.fullname)
      goto failure
   end

   sdl.trace("agent","start transition")
   sdl_.startfunc(...)

   if state_ == "?" then
      errmsg = string.format("missing first sdl.nextstate() in script '%s'",ld.fullname)
      goto failure
   end

   ::failure::
   if errmsg and pid ~= 0 then sdl.stop() end
   switchback()
   --------------------------------------------------------------
   if errmsg then
      return nil, errmsg   
   end
-- sdl.trace("agent","newagent %u %.6f",pid,since(ts))
   return pid
end


-------------------------------------------------------------------------------

local releaselist = {} -- agents to be released
local releaseflag = true -- true if there are agents to be released

local function release()
   -- release all agents in the release list
   for pid in pairs(releaselist) do
   sdl.trace("agent","releasing pid=%u",pid)
      ENV[pid]=nil
      releaselist[pid]=nil
   end
   releaseflag = false
end

local function terminate()
   if releaselist[self_] then return end -- already terminated
   sdl.trace("agent", "terminating")

   if sdl_.children then
      assertf(1,not next(sdl_.children),"agent '%s' pid=%u has children (%s)"
         ,name_,self_, table.concat(sdl_.children,",") or "-") --[bug]
   end

   -- discard all saved signals
   sdl_.saved = nil

   -- delete all timers
   if sdl_.timers then
      for _,tid in ipairs(sdl_.timers) do timerdelete(tid) end
      sdl_.timers = nil
   end

   -- remove from name<->pid map of its block
   local benv = ENV[block_] -- block root
   benv.sdl_.names[name_] = nil
   if sdl_.names then
      sdl_.names = nil
   end
   -- remove list of exported functions
   sdl_.exportedfunc = nil

   -- remove from parent children list 
   local penv = ENV[parent_]
   if self_ ~= 0 then penv.sdl_.children:remove(self_) end

   -- call the finalizer, if any
   if sdl_.atstopfunc then sdl_.atstopfunc() end
   sdl_ = nil

   -- eventually release the agent entry (signals already scheduled to this 
   -- pid will be discarded by the dispatcher)
   releaselist[self_] = true
   releaseflag = true
-- ENV[self_]=nil -- notice that _ENV still references it
   if self_ == 0 then 
      sdl.finished = true
      release()
      error("system agent stops") -- exit from loop
   end

   -- if parent is stopping, and this was its last child, then free parent also
   if penv.state_ == nil and not next(penv.sdl_.children) and self_ ~= 0 then
      switchto(penv.self_)
      terminate()
      switchback()
   end
end


--=============================================================================
-- Agent information
--=============================================================================

local function pidof(name, block)
   assertf(2, type(name)=="string", "invalid name")
   local block = block or block_
   if not ENV[block] or not ENV[block].sdl_.names then
      return nil, string.format("unknown block=%u",block)
   end
   local pid = ENV[block].sdl_.names[name]
   if not pid then
      return nil, string.format("unknown agent '%s' in block=%u",name,block)
   end
   return pid
end

local function nameof(pid)
   local pid = pid or self_
   local env = ENV[pid]
   if not env then return nil, string.format("unknown pid=%u",pid) end
   return env.name_, env.block_, env.parent_, agentkind(env), env.state_
end

local function fullnameof(pid) --@@ TODO (?)
   -- return "agent0.agent1. ..."
end

local function blockof(pid)
   local pid = pid or self_
   local env = ENV[pid]
   if not env then return nil, string.format("unknown pid=%u",pid) end
   return env.block_
end

local function parentof(pid)
   local pid = pid or self_
   local env = ENV[pid]
   if not env then return nil, string.format("unknown pid=%u",pid) end
   return env.parent_
end

local function kindof(pid)
   local pid = pid or self_
   local env = ENV[pid]
   if not env then return nil, string.format("unknown pid=%u",pid) end
   return agentkind(env)
end

local function stateof(pid)
   local pid = pid or self_
   local env = ENV[pid]
   if not env then return nil, string.format("unknown pid=%u",pid) end
   return env.state_
end

local function childrenof(pid)
   local pid = pid or self_
   local env = ENV[pid]
   if not env then return nil, string.format("unknown pid=%u",pid) end
   if env.sdl_.children then
      return table.unpack(env.sdl_.children)
   end
   return nil
end

local function timersof(pid)
   local pid = pid or self_
   local env = ENV[pid]
   if not env then return nil, string.format("unknown pid=%u",pid) end
   if env.sdl_.timers then
      return table.unpack(env.sdl_.timers)
   end
   return nil
end


local function tree(pid, islast, indent, s)
   local pid = pid or self_
   local islast = islast == nil and true or islast
   local s = s or "\n" -- destination string
   local indent = indent or ""
   if pid==0 then
      prefix = ""
   elseif islast then
      prefix = indent .. "└── "
      indent = indent .. "    "
   else
      prefix = indent .. "├── "
      indent = indent .. "│   " 
   end
   local env = ENV[pid]
   if not env then return nil, string.format("unknown pid=%u",pid) end
   s = s .. string.format(
            "%s%s [%u] (%s) %s b=%u p=%u c=%s t=%s\n",
            prefix, env.name_, pid, agentkind(env), env.state_, 
            env.block_, env.parent_, 
            env.sdl_.children and next(env.sdl_.children) and 
               table.concat(env.sdl_.children,",") or "-",
            env.sdl_.timers and next(env.sdl_.timers) and 
               table.concat(env.sdl_.timers,",") or "-"
            )
   if env.sdl_.children then
      -- find last descendant
      local last
      for _,cpid in ipairs(env.sdl_.children) do last = cpid end
      -- print all descendants
      for _,cpid in ipairs(env.sdl_.children) do 
         s = tree(cpid,cpid==last,indent,s)
      end
   end
   return s
end


local function treeof(pid)
   return tree(pid)
end

--=============================================================================
-- Schedulers and dispatcher
--=============================================================================

-- elements inserted in schedulers must contain:
-- { signal, sender, dstpid, sendime, [expiry=NEVER], [istimer] }
--     1       2        3      4           5              6


local function dispatch(sig, sender, pid, sendtime, expiry, istimer, redirect)
-- redirect = true if sig has already made at least one round in this function
   local expiry = expiry or NEVER
   local istimer = istimer or false
   if not switchto(pid,true) then 
      -- destination may have stopped (or it is just wrong, who knows?)
      sdl.trace("discarded","discarded %s %u->%u (unknown destination)"
               ,sig[1],sender,pid)
      return
   end

   if state_ == nil then 
      -- destination is in 'stopping' state (has children still active)
      sdl.trace("discarded","discarded %s %u->%u (destination is stopping)"
                  ,sig[1],sender,pid)
      switchback()
      return
   end

   if now() > expiry then
      -- time-triggered signal arrived too late
      sdl.trace("discarded","discarded %s %u->%u (stale signal, expiry=%.6f)"
               ,sig[1],sender,pid,expiry)
      switchback()
      return
   end

   if istimer and not redirect then
      local info = gettmrinfo(sender)
      if info.discard > 0 then 
         -- timer was reset with signals already scheduled but not yet consumed
         sdl.trace("discarded","discarded %s %u->%u (timer reset)"
                  ,sig[1],sender,pid)
         info.discard = info.discard - 1 -- see note1T
         switchback()
         return
      end   
      info.status = 0 -- see note1T
   end

   if sdl_.procedure then
      sdl.trace("signal","redirecting signal %s %u->%u->%u (procedure call)"
            ,sig[1],sender,pid,sdl_.procedure)
      local dstpid = sdl_.procedure -- need to save this before switchback...
      switchback()
      return dispatch(sig, sender, dstpid, sendtime, expiry, istimer, true) 
   end

   signal_ = sig
   signame_ = sig[1]
   sender_ = sender
   sendtime_ = sendtime
   exptime_ = expiry
   istimer_ = istimer

   sdl.trace("signal","signal %s from %u",signame_,sender_)

   -- search for the proper transition for 'signame' in the current state
   local func = nil
   local t = sdl_.states[state_]
   if t then func = t[signame_] or t['*'] end
   if not func then -- try with default state
      t = sdl_.states[sdl_.defstate]
      if t then func = t[signame_] or t['*'] end
   end
   if func then
      recvtime_ = now()
      func()
   else
      -- implicit consumption and empty transition to the same state
      -- (to override this behavior, explicitly define a default transition)
      sdl.trace("signal","implicit empty transition (state '%s')", state_)
   end

   signal_= nil
   signame_= nil
   sender_= nil
   sendtime_= nil
   recvtime_= nil
   exptime_ = nil
   istimer_= nil

   switchback()
end


local function flushsched(sched)
   local s = sched:pop()
   while s do
      local ts = now()
      dispatch(table.unpack(s)) 
      sdl.trace("exec","exec time = %.6f",since(ts))
      s = sched:pop()
   end
end

local function flushfunc()
-- This function is called by the reactor to trigger the dispatcher
   scheduler, scheduler1 = scheduler1, scheduler
   prioschedulers, prioschedulers1 = prioschedulers1, prioschedulers
   -- Now all signals are in scheduler1, while scheduler is empty 
   -- and ready to receive newly sent signals (and same for prioschedulers)
   -- Flush scheduler, in order from highest to lowest priority:
   assert(scheduler:isempty() and prioschedulers:isempty())
   if not prioschedulers1:isempty() then
      for _,sched in ipairs(prioschedulers1) do 
         flushsched(sched)
      end
   end
   flushsched(scheduler1)
   -- Now scheduler1 is empty, and scheduler contains newly scheduled
   -- signals (if any). By returning 'true', the reactor will call this
   -- function again as soon as possible (otherwise it will block until
   -- the expiry of the next timer).
   --sdl.printf(scheduler:isempty(),prioschedulers:isempty())
   if releaseflag then release() end -- release agents
   return not scheduler:isempty() or not prioschedulers:isempty()
end

--=============================================================================
-- Create functions 
--=============================================================================

local function create(name, script,...)
   offspring_ = assertf(2, newagent(false, false, nil, name, script, ...))
   return offspring_
end

local function createblock(name, script,...)
   offspring_ = assertf(2,newagent(true, false, nil, name, script, ...))
   return offspring_
end

local function procedure(atreturn, name, script, ...)
-- don't change offspring_ here, because a procedure is not really an agent.
   return assertf(2,newagent(false, true, atreturn, name, script, ...))
end

local function procreturn(...)
   sdl.trace("agent","procedure return")
   local penv = ENV[parent_] -- the caller
   -- move signals from procedure's saved queue to caller's saved queue
   if sdl_.saved then
      local s = sdl_.saved:pop()
      while s do
         s[3] = penv.self_
         if not penv.sdl_.saved then penv.sdl_.saved = fifo() end
         penv.sdl_.saved:push(s)
         s = sdl_.saved:pop()
      end
   end
   ---------------------------------------------------------------
   switchto(parent_) --caller
   local atreturn = sdl_.atreturn
   sdl_.procedure = nil
   sdl_.atreturn = nil
   if atreturn then
      if type(atreturn) == "function" then
         atreturn(...)
      elseif type(atreturn) == "string" then
         sdl.nextstate(atreturn)
      end
   end
   switchback()
   ---------------------------------------------------------------
   state_ = nil -- mark as 'stopping'
   if not sdl_.children or not next(sdl_.children) then
      terminate()
   end
end


--=============================================================================
-- State machine definition functions
--=============================================================================

local function start(func) 
   assertf(2, type(func)=="function", "invalid func")
   sdl_.startfunc=func
end


local function transition(state, signame, func)
   assertf(2, type(state)=="string", "invalid state")
   assertf(2, type(signame)=="string", "invalid signame")
   assertf(2, type(func)=="function", "invalid func")
   if sdl_.states[state]==nil then 
      sdl_.states[state] = {} -- create state
   end
   sdl_.states[state][signame] = func
end


local function default(state)
   assertf(2, type(state)=="string", "invalid state")
   if sdl_.states[state]==nil then 
      sdl_.states[state]={} -- create state
   end
   sdl_.defstate=state
end   


local function nextstate(state) 
   if state==nil then return end -- dash state @@ documentare
   assertf(2, type(state)=="string","invalid state")
   local oldstate = state_
   state_ = state 
   sdl.trace("agent","nextstate %s -> %s", oldstate, state_)
   if oldstate ~= state_ then sdl.restore() end
end


local function stop(atstopfunc)
   sdl.trace("agent","stop")
   -- check that agent is not a procedure
   assertf(2,caller_==nil,"procedures shall use sdl.procreturn instead of sdl.stop")
   state_ = nil -- mark as 'stopping'
   if atstopfunc then
      assertf(2,type(atstopfunc)=="function","invalid atstopfunc")
      sdl_.atstopfunc = atstopfunc
   end 
   if not sdl_.children or not next(sdl_.children) then
      terminate()
   end
end
-- When an agent stop()s, it enters a 'stopping condition' (cfr. Z.101/9) and
-- it remains in that condition until all its children have terminated. Then it
-- terminates too. While in the stopping condition, the agent will not receive
-- signals, but it will be available for remote synchronous calls.


local function killemall(pid)
   switchto(pid)
   -- kill all children first
   if sdl_.children then
      local children = {}
      for i,cpid in ipairs(sdl_.children) do children[i] = cpid end
      for i,cpid in ipairs(children) do killemall(cpid) end
      sdl.trace("agent","killed")
   end
   terminate()
   switchback()
end

local function kill(pid)
   assertf(2,pid==nil or type(pid)=="number","invalid pid")
   local pid = pid or self_
   sdl.trace("agent","kill %u",pid)
   local env1 = ENV[pid]
   assertf(2,env1,"attempt to kill unknown pid=%u from pid=%u",pid,self_)
   -- check that the current agent is an ancestor
   while env1 do
      if env1.self_ == self_ then break end
      env1 = ENV[env1.parent_] 
   end
   assertf(2,env1,"attempt to kill a non-descendant pid=%u from pid=%u",pid,self_)
   if(pid ~= self_) then killemall(pid) return end
   -- kill all children first
   if sdl_.children then
      local children = {}
      for i,cpid in ipairs(sdl_.children) do children[i] = cpid end
      for i,cpid in ipairs(children) do killemall(cpid) end
      sdl.trace("agent","suicide committed")
   end
   terminate()
end

--=============================================================================
-- Send/save/restore signals
--=============================================================================


local function send(sig, dstpid, priority)
   assertf(2,type(sig)=="table", "invalid signal")
   assertf(2,type(dstpid)=="number", "invalid dstpid")
   assertf(2,priority==nil or type(priority)=="number", "invalid priority")
   local env = ENV[dstpid] -- destination agent
   priority = ( env and env.sdl_.inputpriority[sig[1]] ) or priority
   if priority and (( priority > nprio ) or ( priority < 1 )) then 
      priority = nil -- normal priority
   end
   local srcpid =  caller_ or self_
   local sendtime = now()
   if not priority then -- normal priority
      scheduler:push({ sig, srcpid, dstpid, sendtime })
   else -- priority 1 ... N
      prioschedulers:push(priority, { sig, srcpid, dstpid, sendtime })
   end
   sdl.trace("signal","send %s %u->%u (priority=%s) ",
      sig[1],srcpid,dstpid, priority and tostring(priority) or "normal")
   return sendtime
end


local function sendat(sig, dstpid, at, maxdelay)
   assertf(2,type(sig)=="table", "invalid signal")
   assertf(2,type(dstpid)=="number", "invalid dstpid")
   assertf(2,type(at)=="number", "invalid at")
   assertf(2,maxdelay==nil or type(maxdelay)=="number", "invalid at")
   local srcpid =  caller_ or self_
   local sendtime = now()
   ttsend(sig, srcpid, dstpid, at, maxdelay, sendtime) 
   return sendtime
end


local function priorityinput(signame, priority)
   assertf(2,type(signame)=="string", "invalid signame")
   assertf(2,priority==nil or type(priority)=="number", "invalid priority")
   sdl_.inputpriority[signame] = priority
   sdl.trace("signal","priority for %s input signals is set to %s",signame,
      priority and tostring(priority) or "normal")
end

local function save()
   sdl.trace("signal","save %s (sender=%u)",signal_[1],sender_)
   if not sdl_.saved then sdl_.saved = fifo() end
   sdl_.saved:push({ signal_, sender_, self_, sendime_, exptime_, istimer_ })
end

local function restore()
-- re-schedules all saved signals for the current agent
   if not sdl_.saved then return end 
   local s = sdl_.saved:pop()
   while s do
      sdl.trace("signal","restoring %s from %u",s[1][1],s[2])
      scheduler:push(s)
      s = sdl_.saved:pop()
   end
end


--=============================================================================
-- Synchronous remote function call
--=============================================================================

local function exportfunc(funcname, func)
   assertf(2,type(funcname)=="string", "invalid funcname")
   assertf(2, func == nil or type(func)=="function", "invalid func")
   if func then
      sdl.trace("remfunc","exporting function '%s' (%s)",funcname,func)
   else
      sdl.trace("remfunc","revoking exported function '%s'",funcname)
   end
   if not sdl_.exportedfunc then sdl_.exportedfunc = {} end
   sdl_.exportedfunc[funcname]=func
end


local function remfunc(pid, funcname, ...)
-- NOTE: this is a non-SDL construct: it is not a SDL 'remote procedure', because
-- such a procedure has states and a different mechanism (see Z.102/10.5), which
-- can be implemented using the basic SDL constructs.
   assertf(2, type(funcname)=="string", "invalid funcname")
   sdl.trace("remfunc","invoking remote call %s() to pid=%u",funcname,pid)
   assertf(2,switchto(pid),"attempt to invoke remfunc on unknown pid=%u from pid=%u",pid,self_)
   local func = sdl_.exportedfunc and sdl_.exportedfunc[funcname] or nil
   assertf(2,func,"attempt to invoke unknown remfunc '%s' on pid=%u from pid=%u",
                                 funcname,pid,self_)
   local retval = { func(...) }
   switchback()
   return table.unpack(retval)
end

   
--=============================================================================
-- Time-triggered signals (or "Real-time signalling", but...)
--=============================================================================

local function at_compare(ss1, ss2) -- compare 'at' values
   return ss1[2] < ss2[2]
end

local tttimer -- timer to trigger scheduling of signals
local ttqueue = heap(at_compare) -- priority queue (min heap)
-- contains time-scheduled signals ordered per 'at' value 
-- the first signal is the one with min(at), ie the next to be sent

local function start_tttimer(exptime)
   sdl.trace("signal","tttimer started (exptime=%.6f s)",exptime)
   assert(timers.start(tttimer,exptime))
end

local function ttqueue_flush()
   local ss = ttqueue:first()
   sdl.trace("signal","ttqueue_flush")
   while ss do
      local exptime = ss[2]
      if exptime > now() then -- not its time, yet
         start_tttimer(exptime)
         return
      end
      -- time to send it: remove it from the queue and push it in the priority 
      -- scheduler (don't bother to check for expiry: the dispatcher will do
      -- the check and possibly discard the signal).
      --local ts = now()
      ttqueue:delete()
      --sdl.trace("signal","ttqueue delete time = %.6f s (count=%u)",since(ts), ttqueue:count())
      ss[1][4] = now() -- adjust 'sendtime'
      prioschedulers:push(1, ss[1]) -- highest priority 
      ss = ttqueue:first()
   end
end

ttsend = function(sig, srcpid, dstpid, at, maxdelay, sendtime)
   local expiry = maxdelay and at + maxdelay or NEVER 
   -- at = when signal is expected to be actually delivered
   -- expiry = when sig must be considered stale
   local s = { sig, srcpid, dstpid, at, expiry }
   sdl.trace("signal","send %s %u->%u at %.6f (expires at %.6f)",sig[1],srcpid,dstpid,at,expiry)
   -- local ts = now()
   ttqueue:insert({ s, at, expiry })
   --sdl.trace("signal","ttqueue insert time = %.6f s (count=%u)",since(ts), ttqueue:count())
   ttqueue_flush()
   return sendtime
end

--=============================================================================
-- Timers                                                                     
--=============================================================================

gettmrinfo = function (tid)
   local info = timers.info(tid)
   if info==nil or (info.pid ~= self_ and info.pid ~= caller_) then
      error(string.format("pid=%u is not the owner of timer %u",self_,tid),3)
   end
   return info
end


local function timerexpired(tid, info)
   local sendtime = now()
   sdl.trace("timer","timer %u (%s) expired", tid, info.signame)
   info.status = 2 -- see note1T
   scheduler:push({ { info.signame }, tid, info.pid, sendtime, NEVER, true })
end

timercreatedisabled = function (duration, signame)
   error("cannot create timer in state transition or procedure",2)
end

timercreate = function (duration, signame)
   assertf(2, type(duration)=="number", "missing or invalid duration")
   assertf(2, type(signame)=="string", "missing or invalid signame")
   local tid = assertf(2,timers.create(duration, timerexpired, 
                     -- timer info:
                     {  pid = self_,      -- owner 
                        signame = signame,   -- signal name
                        duration = duration, -- default timeout
                        status = 0,          -- status (see note1T below)
                        discard = 0,         -- signals to be discarded
                     }))
   if not sdl_.timers then sdl_.timers = array() end
   sdl_.timers:insert(tid)
   sdl.trace("timer","timer %u (%s) created, duration=%.3f s",tid,signame,duration)
   return tid
end
-- (note1T) "A timer is active from the moment of setting up to the moment of
--          consumption of the timer signal" (Z101/11.15).
--          So, when the timer has expired and the signal is scheduled but not
--          yet consumed, the timer is to be regarded as active (even if it is
--          not active in the timers.lua module). 
--          status = 0     inactive
--          status = 1     active 
--          status = 2     active, signal dispatched

timermodify = function (tid, duration, signame)
   assertf(2, tid and type(tid)=="number", "missing or invalid tid")
   local info = gettmrinfo(tid)
   if info.status > 0 then timerreset(tid) end
   if duration then 
      assertf(2,type(duration)=="number","missing or invalid duration")
      info.duration = duration 
   end
   if signame then 
      assertf(2,type(signame)=="string","missing or invalid signame")
      info.signame = signame 
   end
   sdl.trace("timer","timer %u (%s) modified, duration=%.3f s",tid,info.signame,info.duration)
end


timerdelete = function (tid) 
-- local only: SDL does not provide means to delete a timer
   assertf(2, tid and type(tid)=="number", "missing or invalid tid")
   local info = gettmrinfo(tid)
   if info.status > 0 then timerreset(tid) end
   timers.delete(tid)
   sdl.trace("timer","timer %u (%s) deleted",tid,info.signame)
   sdl_.timers:remove(tid)
end


timerset = function (tid, at)
   assertf(2, tid and type(tid)=="number", "missing or invalid tid")
   assertf(2, at==nil or type(at)=="number", "invalid at")
   local info = gettmrinfo(tid)
   if info.status > 0 then timerreset(tid) end
   info.status = 1 -- see note1T
   local at = at or now() + info.duration
   sdl.trace("timer","set timer %u (%s) at=%.3f s",tid, info.signame, at)
   return timers.start(tid, at)
end

timerreset = function (tid)
   assertf(2, tid and type(tid)=="number", "missing or invalid tid")
   local info = gettmrinfo(tid)
   sdl.trace("timer","timer %u (%s) reset",tid,info.signame)
   local status = info.status
   if status == 0 then goto done end
   if status == 1 then
      timers.stop(tid) -- no signals will be scheduled for this activation
   else
      -- timer is not running, but a signal has been scheduled and not consumed
      -- and it must be discarded
      info.discard = info.discard+1 -- scheduled signal will be discarded 
   end
   info.status = 0 -- see note1T
   ::done::
   return now()
end

timeractive = function (tid)
   assertf(2, tid and type(tid)=="number", "missing or invalid tid")
   local info = gettmrinfo(tid)
   local active = info.status > 0
   local _ , exptime = timers.isrunning(tid) 
   return active, exptime
end


--=============================================================================
-- LuaSocket over reactor
--=============================================================================

-- LunaSDL requires the 'object' type to be compatible with pollfunc and
-- to have the following methods:
-- object:settimeout()  called by the reactor to make it non-blocking
-- object:tostring()    for traces

local function objectcallback(object, info)
   local pid = info[1]
   local callback = info[2]
   if not switchto(pid) then -- agent exited?
      deregister(object)
   end
   sdl.trace("loop","callback %s", tostring(object))
   callback(object)
   switchback()
end

register = function (object, readcallback, writecallback)
   -- register a object in the reactor
   assertf(2, readcallback==nil or type(readcallback)=="function","invalid readcallback")
   assertf(2, writecallback==nil or type(writecallback)=="function","invalid writecallback")
   sdl.trace("loop","register %s (%s%s)", tostring(object),
      readcallback and "r" or "", writecallback and "r" or "")

   if not readcallback and not writecallback then 
      return nil
   end
   if readcallback then
      reactor.register(object, "r", objectcallback, { self_, readcallback })
   end
   if writecallback then
      reactor.register(object, "w", objectcallback, { self_, writecallback })
   end
end

deregister = function (object, mode)
   sdl.trace("loop","deregister %s", tostring(object))
   assertf(2, mode == nil or type(mode)=="string","invalid mode")
   local mode = mode or "rw"
   assertf(2, mode == "rw" or mode=="wr" or mode=="r" or mode=="w","invalid mode")
   if mode == "r" then
      reactor.deregister(object, "r")
   elseif mode == "w" then
      reactor.deregister(object, "w")
   elseif mode == "rw" or mode == "wr" then
      reactor.deregister(object, "r")
      reactor.deregister(object, "w")
   end
end


--=============================================================================
-- Logs and traces 
--=============================================================================

function sdl.logopen(fname)
   assertf(2, fname and type(fname) == "string", "invalid logfile name")
   if logfile then sdl.logclose() end
   local file, errmsg = io.open(fname,"w")
   if not file then error(errmsg) end
   logenabled=true
   logfilename = fname
   logfile = file
   sdl.logf("%s - LunaSDL system logfile %s", os.date(),logfilename)
   sdl.logf("Software version: %s (%s, %s)", sdl._VERSION, _VERSION, socket._VERSION)
   if socket._VERSION == "no socket" and gettime == DEFAULT_GETTIME then
      sdl.logf("Warning: LuaSocket not found, using backup implementation")
      if gettime == DEFAULT_GETTIME then
         sdl.logf("Warning: timers and timestamps have 1 second resolution")
      end
      if pollfunc == DEFAULT_POLLFUNC then
         sdl.logf("Warning: no support for socket or other file descriptor objects")
      end
   end
   return logfile
end

function sdl.logfile()
   if not logfile then return nil, "no logfile" end
   return logfile, logfilename
end

function sdl.logclose()
   if not logfile then return end
   logfile:close()
   logenabled=false
   logfile = nil
   logfilename = nil
   sdl.tracesoff()
end

function sdl.logson()
   if not logfile then return end
   logenabled=true
end

function sdl.logsoff()
   if not logfile then return end
   logenabled=false
end

function sdl.logflush()
   if not logfile then return end
   logfile:flush()
end

local function preamble1(tag)
   local t = tag and utils.format(2,"[%s]",tag)
   local s = utils.format(3,"%.3f [%u]%s ",now(),self_ or 0, t or "")
   return s
end

local function preamble2(tag)
-- alternative preamble with agent name instead of pid
   local t = tag and utils.format(2,"[%s]",tag)
   local s = utils.format(3,"%.3f [%s]%s ", now(), name_ or "configuration", t or "")
   return s
end

local function nopreamble(tag) return nil end

local preamble = preamble1


local function logf(tag, formatstring, ...)
   if not logenabled then return end
   logfile:write(preamble(tag) or "")
   logfile:write(utils.format(2,formatstring,...))
   logfile:write("\n")
end


function sdl.logf(formatstring, ...)
   logf(nil,formatstring,...)
end


function sdl.printf(formatstring,...)
   local s = utils.format(2,formatstring,...)
   print(s)
   sdl.logf(s)
end


local function logtracing()
   if not traceflag then  
      sdl.logf("traces disabled")
   elseif not traceinclude and not traceexclude then
      sdl.logf("traces enabled")
   else
      local s = {}
      if traceinclude then
         s = {}
         for k,_ in pairs(traceinclude) do s[#s+1]=k end
         sdl.logf("enabled traces: %s",table.concat(s," "))
      end
      if traceexclude then
         s = {}
         for k,_ in pairs(traceexclude) do s[#s+1]=k end
         sdl.logf("disabled traces: %s",table.concat(s," "))
      end
   end
end


function sdl.traceson(...)
   local tags = ... and {...}
   traceflag = true
   if not tags then -- enable all
      traceinclude = nil
      traceexclude = nil
   else
      -- remove tags from excluded
      if traceexclude then 
         for _,v in pairs(tags) do
            traceexclude[v] = nil
         end
         if not next(tracexclude) then traceexclude=nil end
      end
      -- add tags in included
      if not traceinclude then traceinclude = {} end
      for _,v in pairs(tags) do
         traceinclude[v] = true
      end
   end
   logtracing()
end


function sdl.tracesoff(...)
   local tags = ... and {...}
   if not traceflag then return end 
   if not tags then -- enable all
      traceflag = false
      traceinclude = nil
      traceexclude = nil
   else
      -- remove tags from included
      if traceinclude then 
         for _,v in pairs(tags) do
            traceinclude[v] = nil
         end
         if not next(tracinclude) then traceinclude=nil end
      end
      -- add tags in excluded
      if not traceexclude then traceexclude = {} end
      for _,v in pairs(tags) do
         traceexclude[v] = true
      end
   end
   logtracing()
end

function sdl.trace(tag,formatstring,...)
   local ok=false
   if not logenabled or not traceflag then return end
   if not tag then return end
   if not traceinclude then ok=true else
         if traceinclude[tag] then ok=true end
   end
   if traceexclude and traceexclude[tag] then ok=false end
   if not ok then return end
   logf(tag,formatstring,...)
end


--=============================================================================
-- main() functions
--=============================================================================

local function notraceback (m) return m end
local traceback0 = notraceback

-- Enable/disable stack traceback
local function traceback(x)
   if x == "off" then traceback0 = notraceback return end
   traceback0 = debug.traceback 
end

local function envtemplate(env)
      ENV_TEMPLATE = copytable(env)
      ENV_TEMPLATE.sdl = sdl -- all processes need this...
end

local function logpreamble(func) --@@ documentare
   assertf(2, func==nil or type(func)=="function", "invalid preamble function")
   preamble = func and func or nopreamble
   sdl.logf("custom log preamble (%s)",preamble) 
end


local function prioritylevels(levels)
   nprio = levels or DEFAULT_NPRIO
   nprio = math.floor(nprio)
   assertf(2, type(nprio)=="number" and nprio > 0, "invalid number of priority levels")
   sdl.logf("priority levels = %u",nprio)
end

local function pollfuncs(poll, add, del, reset)
   sdl.logf("changing select functions") 
   assertf(2, type(poll)=="function", "invalid poll function")
   assertf(2, add==nil or type(add)=="function", "invalid add function")
   assertf(2, del==nil or type(del)=="function", "invalid del function")
   assertf(2, reset==nil or type(reset)=="function", "invalid reset function")
   pollfunc = poll
   polladd = add
   polldel = del
   pollreset = reset
end

local function setwallclock(func)
   -- just in case the logfile was already open with old timestamps:
   sdl.logf("restarting system wallclock") 
   if func then 
      assertf(2, type(func)=="function", "invalid func")
      gettime = func
   end
   startingtime = gettime()
   if socket._VERSION == "no socket" then
      socket.setgettime(func)
   end
end

local function configure()
   collectgarbage()
   local ok, errmsg = xpcall(function() 
      local errlvl = 5 -- 1=this 2=xpcall 3=configure 4=createsystem

      -- create the schedulers
      scheduler = fifo()
      scheduler1 = fifo()
      prioschedulers = fifoarray(nprio)
      prioschedulers1 = fifoarray(nprio)

      -- prepare the template environment
      if not ENV_TEMPLATE then envtemplate(_ENV) end

      -- configure the reactor and the timers module

      timers.init(now)
      assertf(errlvl, reactor.config(now, timers.trigger))
      assertf(errlvl, reactor.configselect(pollfunc, polladd, polldel,pollreset))

      -- create the timer for "real-time signalling"
      tttimer = timers.create(1,ttqueue_flush)
      
   end, traceback0)

   if not ok then
      print(errmsg)
      os.exit()
   end
end      

local function createfirst()
   -- create first agent (pid=0)
   _ENV.sdl = sdl
   sdl_ = {}
   sdl_.isblock = true
   self_ = 0 -- so that the system agent assumes itself as current
   local ok, errmsg = 
      newagent(true,false, nil,sdl.rootname, sdl.rootscript,table.unpack(sdl.rootargs))
   if not ok then 
      error(errmsg,6)
   end
   sdl.rootname = nil
   sdl.rootscript = nil
   sdl.rootargs = nil
end

function sdl.systemreturn(...)
-- assertf(2, self_==0, "only the system agent can use sdl.systemreturn")
   sdl.returnvalues = { ... }
end

local function createsystem(name, script, ...)
   assertf(2, name == nil or type(name)=="string", "invalid name")   
   assertf(2, type(script)=="string", "invalid script")  
   sdl.rootname = name
   sdl.rootscript = script
   sdl.rootargs = { ... }
   configure()
   systemfunctions()
   local ok, errmsg = xpcall(function() 
      return reactor.loop(createfirst,flushfunc)
      -- return reactor.loop(createfirst,flushfunc)
   end, traceback0)

   assert(not ok) -- ok is expected to be false
   ok = sdl.finished
   local retval = sdl.returnvalues and { table.unpack(sdl.returnvalues) } or {}
   if not ok then sdl.logf(errmsg) end
   sdl.logflush()
      
   sdlreset()

   if ok then
      -- the system agent has terminated (not an error)
      return true, table.unpack(retval)
   else
      -- an error occurred
      return nil, errmsg
   end
end

local function disabled() error("function not available in this phase",2) end

configfunctions = function()
   -- enabled in this phase
   sdl.prioritylevels = prioritylevels
   sdl.logpreamble = logpreamble 
   sdl.envtemplate = envtemplate
   sdl.setwallclock = setwallclock
   sdl.pollfuncs = pollfuncs 
   sdl.createsystem = createsystem
   sdl.traceback = traceback
   -- disabled in this phase
   sdl.timer = disabled
   sdl.modify = disabled
   sdl.set = disabled
   sdl.reset = disabled
   sdl.active = disabled
   sdl.pidof = disabled
   sdl.nameof = disabled
   sdl.treeof = disabled
   sdl.childrenof = disabled
   sdl.timersof = disabled
   sdl.send = disabled
   sdl.sendat = disabled
   sdl.priorityinput = disabled
   sdl.save = disabled
   sdl.restore = disabled
   sdl.exportfunc = disabled
   sdl.remfunc = disabled
   sdl.create = disabled
   sdl.createblock = disabled
   sdl.procedure = disabled
   sdl.procreturn = disabled
   sdl.transition = disabled
   sdl.default = disabled
   sdl.start = disabled
   sdl.nextstate = disabled
   sdl.stop = disabled
   sdl.kill = disabled
   sdl.register = disabled
   sdl.deregister = disabled
end


systemfunctions = function()
   -- functions that shouldn't be used from now on
   sdl.prioritylevels = disabled
   sdl.logpreamble = disabled
   sdl.envtemplate = disabled
   sdl.setwallclock = disabled
   sdl.pollfuncs = disabled
   sdl.createsystem = disabled
   sdl.traceback = disabled
   -- add functions that should be used only from now on
   sdl.timer = timercreatedisabled
   sdl.modify = timermodify
   sdl.set = timerset
   sdl.reset = timerreset
   sdl.active = timeractive
   sdl.pidof = pidof
   sdl.nameof = nameof
   sdl.treeof = treeof
   sdl.childrenof = childrenof
   sdl.timersof = timersof
   sdl.send = send
   sdl.sendat = sendat
   sdl.priorityinput = priorityinput
   sdl.save = save
   sdl.restore = restore
   sdl.exportfunc = exportfunc
   sdl.remfunc = remfunc
   sdl.create = create
   sdl.createblock = createblock
   sdl.procedure = procedure
   sdl.procreturn = procreturn
   sdl.transition = transition
   sdl.default = default
   sdl.start = start
   sdl.nextstate = nextstate
   sdl.stop = stop
   sdl.kill = kill
   sdl.register = register
   sdl.deregister = deregister
end

configfunctions()

return sdl
