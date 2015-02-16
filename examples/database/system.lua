-- System agent script: system.lua

sdl.start(function (n_entries)
   -- create the database process
   sdl.create("Database","database",n_entries)

   -- create the user process and send it a START signal
   sdl.create("User","user")
   sdl.send({ "START" }, offspring_)

   sdl.stop()
end)

