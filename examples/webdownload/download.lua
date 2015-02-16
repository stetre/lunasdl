-- Agent script: download.lua

socket = require("socket")

local nread = 0 -- bytes read
local bs = 2^10 -- block size

function Callback(c) -- socket 'read' callback
   local s, status, partial = c:receive(bs)
   if status == "closed" then
      if partial then nread = nread + #partial end
      sdl.deregister(c)
      c:close()
      sdl.printf("%s: read %u bytes (finished)", name_, nread)
      return sdl.stop()
   end
   s = s or partial
   nread = nread + #s
   sdl.logf("%s: read %u bytes", name_, nread)
end

sdl.start(function (host, file)
      sdl.printf("%s: connecting to %s:80", name_, host)
      local c = assert(socket.connect(host, 80))

      sdl.register(c, Callback)

      sdl.printf("%s: retrieving '%s'", name_, file)
      c:send("GET " .. file .." HTTP/1.0\r\n\r\n")

      sdl.nextstate("_")
   end)

