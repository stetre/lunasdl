
local function heap(cmp)
   local cmp = assert(cmp, "missing compare function")
   local self = {}
   return setmetatable(self,
      {
      __index = {
      -------------------------------------------------
      first = function(self)
         return self[1]
      end,
      -------------------------------------------------
      count = function(self)
         return #self
      end,
      -------------------------------------------------
      insert = function(self, element)
         self[#self + 1] = element
         local i = #self
         local i2, parent
         while i > 1 do
            i2 = i/2
            parent = i2 - (i2)%1 -- floor(i/2)
            if cmp(self[parent],self[i]) then break end
            self[i], self[parent] = self[parent], self[i]
            i = parent
         end
      end,
      -------------------------------------------------
      delete = function(self)
      -- remove root
         local len = #self
         if len == 0 then return end
         local root
         root, self[1] = self[1], self[len]
         self[len] = nil
         if len > 2 then
            self:heapify()
         end
         return root
      end,
      -------------------------------------------------
      heapify = function(self, i)
         local cmp = cmp
         local i = i or 1
         local first = i
         local i2 = 2*i
         local left, right = i2 , i2+1
         if left <= #self and cmp(self[left],self[first]) then
            first = left
         end
         if right <= #self and cmp(self[right],self[first]) then
            first = right
         end
         if first ~= i then
            self[i], self[first] = self[first], self[i]
            self:heapify(first)
         end
      end,
      -------------------------------------------------
      }, -- __index
      })
end

return heap
