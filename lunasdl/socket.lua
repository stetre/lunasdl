--=============================================================================
-- LuaSocket loader                                                        
--=============================================================================


if package.searchpath("socket",package.path) then
   return require("socket")
end

-- Some notes on LunaSDL and LuaSocket
-------------------------------------------------------

-- LunaSDL itself uses LuaSocket's facilities only for the 'gettime' function 
-- and for the polling function. Beside these, it does not use directly any 
-- other functionality provided by LuaSocket but it just give means to agent 
-- scripts to use them and register sockets in LunaSDL's event loop.
--
-- The choice of socket.gettime() as default 'gettime' function is mainly due 
-- to portability considerations and to reduce at the minimum the dependencies 
-- on other modules. As far as I know, however, socket.gettime is based (at least 
-- on POSIX systems) on gettimeofday(2), which is not guaranteed to be monotonic.
-- This may cause problems, because LunaSDL itself assumes that the system time 
-- increases monotonically. If this is the case, one can provide a different 
-- function (e.g. based on clock_gettime(2)) by means of sdl.setwallclock().
-- 
-- LunaSDL may be used even if LuaSocket is not available. Just provide a gettime
-- function to replace socket.gettime. If you don't, LunaSDL uses Lua's os.time()
-- and still works, but its granularity of 1 second may be too coarse for your
-- needs. Of course, in this case the agent script can not use timers.
-- 
-- LunaSDL may also be used with alternatives to LuaSocket, but in this case you 
-- need to provide it with a proper polling function (see sdl.pollfuncs() in the
-- reference manual).
--
-- Another option is to use LuaSocket but with a custom polling function that 
-- replaces LuaSocket's native socket.select(). This may be useful, for example, 
-- when dealing with a lot of sockets (socket.select() is based on select(2) which
-- has a low limit on the file descriptors it can handle). Again, this can be 
-- accomplished by means of the sdl.pollfuncs() configuration functions.


-------------------------------------------------------------------------------
-- Backup implementation of the LuaSocket functionalities directly used by
-- LunaSDL, in case LuaSocket is not available.
--
-- This implementation does not provide support for socket or other file
-- descriptor objects, and since it uses os.time() as 'gettime' function,
-- timestamps and timeout have only second precision.
--
-- It is intended only as provisional backup before the sdl.setwallclock()
-- and sdl.pollfuncs() are called to set proper replacements for LuaSocket's
-- gettime() and select() functions.

local socket = {}

socket._VERSION = "no socket"

local gettime = os.time -- 1 second precision

function socket.setgettime(func) gettime = func end

function socket.gettime() return gettime() end

function socket.select(recvt, sendt, timeout) 
   if (recvt and table.unpack(recvt)) or (sendt and table.unpack(sendt)) then
      error("sorry, no support for sockets (use LuaSocket or sdl.pollfuncs)")
   end
   if timeout and type(timeout) ~= "number" then
      error("invalid timeout",2)
   end
   if not timeout or timeout < 0 or timeout > .5 then
      timeout = .5  -- a blocking timeout, for our purposes...
   end
   if timeout > 0 then
      local exptime = gettime() + timeout
      repeat now = gettime() until now >= exptime
   end
   return nil, nil, "timeout"
end

return socket
