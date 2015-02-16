--===========================================================================================
-- timers.lua     Timers heap
--===========================================================================================

local printf = function(...) print(string.format(...)) end
--local printf = function(...) end

heap = require("lunasdl.heap")
reactor = require("lunasdl.reactor")

local timers = {} -- module table

local T = {} -- table of created timers (key=tid)
-- T[tid] = { exptime, timeout, callback, info }, 
-- exptime = 0 if inactive

local function compare(a, b) return a[1] < b[1] end
local active = heap(compare) -- priority queue of active timers
-- entries = { exptime, tid }

local gettime = function() error("gettime not initialized") end

local next_tid = 1   -- nexttid to be used

local ADVANCE = 1e-3 
local advance = ADVANCE

function timers.init(gettimefunc, adv )
   gettime = gettimefunc
   advance = adv or ADVANCE
end

function timers.deleteall()
   local tid
   for tid in pairs(T) do timers.delete(tid) end
end

function timers.trigger()
   -- calls callbacks of all active timers with exptime < tnow
   -- returns next exptime, or 0 if no active timers
   local tid, tmr, tnow
   local te = active:first()
   while te do
      tnow = gettime()
      if te[1] > tnow then return te[1]-advance end
      active:delete()
      tid = te[2]
      tmr = T[tid]
      if not tmr or tmr[1] ~= te[1] then 
         -- timer was deleted, stopped or its timeout changed
         goto continue 
      end
      --printf("%.9f: timer %u expired (exptime = %.9f)",tnow,tid, tmr[1])
      tmr[1] = 0
      tmr[3](tid, tmr[4])
      te = nil
      ::continue::
      te = active:first()
      end
   return 0
end
      
function timers.create(timeout, callback, info)
-- creates a new timer and returns timer identifier (tid)
   if not callback or type(callback) ~= "function" then
      return nil, "missing or invalid callback"
   end
   local tid = next_tid
   next_tid = next_tid+1
   T[tid] = { 0 , timeout, callback, info }
   --printf("created timer %u timeout=%.9f",tid,timeout)
   return tid
end


local function search(tid)
-- search for timer identified by tid
   local tmr = T[tid]
   if tmr then return tmr end
   return nil, string.format("unknown tid=%u",tid)
end


function timers.delete(tid)
-- deletes timer identified by tid
   local tmr, errmsg = search(tid)
   if not tmr then return nil, errmsg end
   tmr[1] = 0 -- stop timer
   T[tid] = nil
   return tmr[4]
end

function timers.start(tid, exptime)
-- (re)starts timer identified by tid so to expire at exptime
   local tmr, errmsg = search(tid)
   if not tmr then return nil, errmsg end
   -- overwrites any previous exptime...
   local tstart = gettime()
   tmr[1] = exptime or tstart + tmr[2]
   active:insert({ tmr[1], tid }) -- te
   local te = active:first()
   if te then reactor.triggerat(te[1]-advance) end
   --printf("%.9f: starting timer %u exptime = %.9f",gettime(), tid, tmr[1])
   return tstart
end

function timers.stop(tid)
-- stops timer identified by tid
   local tmr, errmsg = search(tid)
   if not tmr then return nil, errmsg end
   tmr[1] = 0
   return true
end

function timers.timeout(tid, timeout )
-- set (opt.) and get timer's callback
   local tmr, errmsg = search(tid)
   if not tmr then return nil, errmsg end
   if timeout then tmr[2] = timeout end
   return tmr[2]
end

function timers.callback(tid, callback)
-- set (opt.) and get timer's callback
   local tmr, errmsg = search(tid)
   if not tmr then return nil, errmsg end
   if callback then tmr[3] = callback end
   return tmr[3]
end

function timers.info(tid, info)
-- set (opt.) and get user defined info associated with timer
   local tmr, errmsg = search(tid)
   if not tmr then return nil, errmsg end
   if info then tmr[4] = info end
   return tmr[4]
end

function timers.isrunning(tid)
-- returns true if timer is running, false otherwise , and the exptime
   local tmr, errmsg = search(tid)
   if not tmr then return nil, errmsg end
   if tmr[1] == 0 then
      return false, math.huge
   end
   return true, tmr[1]
end

return timers
