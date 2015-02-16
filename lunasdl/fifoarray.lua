local fifo = require("lunasdl.fifo")

local function fifoarray(n)
-- array of n fifo queues
   local self = {}
   for i=1,n do
      self[i] = fifo()
   end
   return setmetatable(self,
      {
      __index = {
      --------------------------------------------------
      push = function(self,i,val) self[i]:push(val) end,
      --------------------------------------------------
      pop = function(self,i) return self[i]:pop()  end,
      --------------------------------------------------
      isempty = function(self)
         for i=1,#self do
            if not self[i]:isempty() then return false end
         end
         return true
      end,
      --------------------------------------------------
      
      }, -- __index
      })
end

return fifoarray
