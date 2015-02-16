-- Agent script: user.lua (database user)

function Start()
   -- find the pid of the agent named "Database" in this block:
   local database = sdl.pidof("Database")
   assert(database,"cannot find database")
   sdl.printf("%s: Database pid is %u", name_, database)
   
   local ts
   ts = sdl.now()

   -- get an entry from the database
   ts = sdl.now()
   local i = 123
   local val = sdl.remfunc(database,"get",i)
   local elapsed = sdl.since(ts)
   sdl.printf("%s: entry %u is '%s' (retrieved in %.6f s)", name_, i, val, elapsed)

   -- overwrite it in the database...
   ts = sdl.now()
   sdl.remfunc(database,"set",i,string.format("hello %u %u %u",1,2,3))
   sdl.printf("%s: entry %u set in %.6f s", name_, i, sdl.since(ts))

   -- ... and then get it again
   ts = sdl.now()
   val = sdl.remfunc(database,"get",i)
   elapsed = sdl.since(ts)
   sdl.printf("%s: entry %u is '%s' (retrieved in %.6f s)", name_, i, val, elapsed)

   -- exit the LunaSDL application
   os.exit(true,true)
end

sdl.start(function (n)  sdl.nextstate("Idle") end)
sdl.transition("Idle","START",Start)
