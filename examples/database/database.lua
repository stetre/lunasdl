-- Agent script: database.lua (database process)

local database = {}

function set(i,val) -- 'set' method
   sdl.printf("%s: set(%u)='%s'", name_, i, val)   
   database[i]=val
   return database[i]
end

function get(i) -- 'get' method
   sdl.printf("%s: get(%u)='%s'", name_, i, database[i]) 
   return database[i]
end

sdl.start(function(n) 
   -- populate the database
   sdl.printf("%s: populating database with %u entries", name_, n)   
   for i=1,n do
      database[i] = string.format("entry no %u",i);
   end

   -- export the get/set functions for remote calls
   sdl.exportfunc("set",set)
   sdl.exportfunc("get",get)

   -- not important in this example
   sdl.nextstate("_") 
end)

