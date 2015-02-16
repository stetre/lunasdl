-- System agent: system.lua

local ts = sdl.now()

sdl.start(function (host, pages)
   sdl.printf("%s: Creating agents", name_)
   for _,file in ipairs(pages) do
      sdl.create(nil,"download", host, file)
   end
   sdl.stop(function ()
         sdl.printf("%s: Elapsed %.1f seconds", name_, sdl.since(ts))
      end )
   end)

