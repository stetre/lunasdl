--===========================================================================================
-- reactor.lua
--===========================================================================================

local printf = function(...) print(string.format(...)) end
local printf = function(...) end

local array = require("lunasdl.array")
local utils = require("lunasdl.utils")

local reactor = {}      -- singleton
local configured=false
local tnextrigger = 0   -- next trigger() time
local trigger = nil     -- trigger callback

local rgettime = function () error("gettime function not initialized") end

-- 'mode' = "r" or "w"
local rselect = function () error("select function not initialized") end
local rselectadd = function (object, mode) return true end
local rselectdel = function (object, mode) return true end
local rselectreset = function () return true end


-- Reactor controlled garbage collection -----------------------------------------
-- If enabled, the reactor automatically calls collectgarbage() when it computes
-- a timeout for select() which higher than gcthreshold, which should mean that
-- the application is not under heavy load.
local DEFAULT_GCTHRESHOLD = 1 -- seconds
local gcflag = false
local gcthreshold = 1 -- seconds. 

function reactor.gcon(threshold)
-- stop Lua automatic collection and start reactor controlled collection
   collectgarbage("stop") 
   gcflag = true
   gcthreshold = threshold or DEFAULT_GCTHRESHOLD
end
function reactor.gcoff() 
-- restart Lua automatic collection 
   collectgarbage("restart")
   gcflag = false 
end

-- Socket objects registration/deregistration ------------------------------------
local rdset -- =array() -- objects waiting for octets to read
local wrset -- =array() -- objects waiting to perform a non blocking write
-- rdset and wrset elements ('objects') are sockets created via the LuaSocket module 
-- or of compatible types
-- the info associated with each socket in the array() is composed of:
-- info[1] = user defined callback, called when the socket is ready
-- info[2] = user defined information (may be nil)
--
-- When the object is ready for a read or write operation, the callback is invoked 
-- passing it the object itself and the user defined info. The callback is expected
-- to accept arguments in this order:
--
--    callback(object, info)
--


function reactor.register(object, mode, callback, info)
   if type(callback)~="function" then return nil, "missing callback" end
   assert(mode and type(mode)=="string" and (mode=="r" or mode=="w"), "invalid mode")
   local set = mode =="r" and rdset or wrset
   assert(rselectadd(object,mode))
   object:settimeout(0, "t")
   set:insert(object,{ callback, info })
   return true
end

function reactor.deregister(object, mode)
   assert(mode and type(mode)=="string" and (mode=="r" or mode=="w"), "invalid mode")
   local set = mode =="r" and rdset or wrset
   local info = set:info(object)
   if not info then return nil end
   assert(rselectdel(object,mode))
   set:remove(object)
   return info[2]
end

function reactor.setinfo(object, mode, info)
   assert(mode and type(mode)=="string" and (mode=="r" or mode=="w"), "invalid mode")
   local set = mode =="r" and rdset or wrset
   local i = set:info(object)
   if not i then 
      return nil 
   else 
      i[2] = info
      set:setinfo(object, i)
   end
   return info
end


local function readready(r)
-- invoke callback of objects that are ready for 'read'
   for _,object in ipairs(r) do
      local info = rdset:info(object) 
      if info then info[1](object, info[2]) end
   end
end


local function writeready(w)
-- invoke callback of objects that ar ready for 'write'
   for _,object in ipairs(w) do
      local info = wrset:info(object) 
      if info then info[1](object, info[2]) end
   end
end


local function notrigger() return 0 end

function reactor.triggerat(t)
   tnextrigger = t
end

function reactor.configselect(poll, add, del, reset)
   if not poll or type(poll)~="function" then
      return nil, "missing or invalid poll function"  end
   if add and type(add)~="function" then
      return nil, "invalid add function"  end
   if del and type(del)~="function" then
      return nil, "invalid del function"  end
   if reset and type(reset)~="function" then
      return nil, "invalid reset function" end
   rselect = poll or rselect
   rselectadd = add or rselectadd
   rselectdel = del or rselectdel
   rselectreset = selres or rselectreset
   return true
end

function reactor.config(gettime, triggerfunc)
-- configure the reactor
   if type(triggerfunc)~="function" and triggerfunc~=nil then
      return nil, "invalid triggerfunc"
   end
   -- throw away any previous rdset and wrset:
   rdset = nil
   wrset = nil
   obj = nil
   rdset = array()   
   wrset = array()   
   obj = {}
   rgettime = gettime or rgettime
   trigger = triggerfunc or notrigger
   --printf("reactor: triggerfunc=%s",triggerfunc)
   configured = true
   return true
end


function reactor.loop(startfunc, flushfunc)
   local never = math.huge
   local tnext
   local tnow
   local flush = false
-- local n

   --print("starting reactor loop")
   if not configured then 
      return nil, "reactor not configured"
   end

   rselectreset()

   local NON_BLOCKING = 1e-6 -- (almost) non blocking timeout
   local BLOCKING     = nil -- blocking timeout

   local timeout = NON_BLOCKING

   if gcflag then collectgarbage() end

   while true do  -- main loop
      --printf("select timeout = %.9f", timeout and timeout or math.huge)
      local r, w, errmsg = rselect(rdset,wrset,timeout)
      if errmsg and errmsg ~= "timeout" then error(errmsg)  end
      tnext = tnextrigger -- freeze it (timers may alter it with triggerat()
      -- serve sockets
      if r then readready(r) end
      if w then writeready(w) end

      -- compute next timeout for select, and trigger the timer wheel
      tnow = rgettime()
      if tnow >= tnext then tnextrigger = trigger() end

      if startfunc then startfunc() startfunc=nil end
      -- user defined start function, to be called only once, after the
      -- select-based ticks generator has begun its operation (timers 
      -- should not be started before entering the loop: if a timer must
      -- be started immediately, start it here)

      if flushfunc then flush = flushfunc() else flush = false end
      -- the user defined flush function is expected to return true if it needs 
      -- to be called again as soon as possible, false otherwise

      tnext = tnextrigger
      --printf("%.9f %s",tnext,tostring(flush))

      if flush then 
         timeout = NON_BLOCKING
      elseif tnext == 0 then
         timeout = BLOCKING
         tnextrigger = never
         if gcflag then collectgarbage() end
      else
         if tnext == never then timeout = BLOCKING 
         else
            tnow = rgettime()
            timeout = tnext > tnow and tnext-tnow or NON_BLOCKING
         end
         if gcflag and timeout and timeout > gcthreshold then
            collectgarbage()
            -- recompute timeout
            if tnext == never then timeout = BLOCKING 
            else
               tnow = rgettime()
               timeout = tnext > tnow and tnext-tnow or NON_BLOCKING
            end
         end
      end
   end
end

return reactor
