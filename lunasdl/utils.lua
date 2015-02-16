
local utils = {}

local socket = require("lunasdl.socket")
utils.now = socket.gettime
utils.since = function(ts) return utils.now() - ts end

function utils.assertf(level, condition, ...)
-- Alternative to assert().
-- Returns condition if it is true, otherwise raises an error()
-- level = same as in error() 
-- ... = error messsage to be formatted (string.format() style)
-- error message is optional, and is formatted only if needed
   if condition then return condition end
   local errmsg = next({...}) and string.format(...) or "assertf failed"
   error(errmsg,level+1)
end

function utils.copytable(t) 
-- Returns a copy of table t (note that this is NOT a deep copy)
   local tt = {} for k,v in pairs(t) do tt[k] = t[k] end
   return tt
end

local function deeptostring(t, islast, indent, tt)
   local tt = tt or {}
   -- if tt[t] then error("table has loops") end
   local s = "" -- destination string
   local indent0 = indent or ""
   if islast then
      indent = indent0 .. "    "
   else
      indent = indent0 .. "│   " 
   end
   if not t then return string.format("%s <... empty ...>\n",indent0) end
   if tt[t] then return string.format("%s...\n",indent0) end
   tt[t] = true
   local last
   for i,v in pairs(t) do 
   --print(i,v) 
   last = i end
   --do return end
   
   local prefix = indent0 .. "├── "
   for i,v in pairs(t) do
   -- if i == "__index" or i == t then goto continue end -- skip it
      if i == last then prefix = indent0 .. "└── " end
      s = s .. string.format("%s%s: %s\n",prefix,i,v)
      if type(v)=="table" then 
         s = s .. deeptostring(v, i == last, indent, tt)
      end
      ::continue::
   end
   return s
end

function utils.deeptostring(t, islast, indent, s)
   return deeptostring(t)
end

function utils.dumpdata(data, filename, mode)
-- Dumps data in a file to be used with gnuplot
-- (eg. gnuplot> plot "data.log" using 1:2 with lines)
-- 'data' = sequence of numbers (array without gaps starting from index=1)
-- 'filename'= name of file where to dump the data
   local file = assert(io.open(filename, mode or "w"))
   for i,v in ipairs(data) do
      file:write(string.format("%u %.9f\n",i,v))
   end
   file:close()
end

function utils.stats(data)
-- Computes mean, variax, minimum and maximum over
-- the sequence of numbers contained in data
   local max,min = 0, math.huge
   local mean, delta, m2, var = 0, 0, 0, 0
   for i=1,#data do 
      local d = data[i]
      if d < min then min = d end
      if d > max then max = d end
      delta = d - mean
      mean = mean + delta/i
      m2 = m2 + delta*(d-mean)
   end
   if #data > 1 then
      var = m2 / (#data-1)
   end
   return  mean, var, min, max
end

function utils.errmsgstrip(msg)
   return string.gsub(msg, ".+%:%d+%:% ", function () return "" end)
end

function utils.format(level, formatstring, ...)
-- string.format() wrapper that when an error occurs, raises an
-- error() pointing at the specified level
-- (to be used in functions that accept (formatstring,...) to point the finger
-- to the caller if the arguments are malformed)
   if not formatstring then return "" end
   --if not next({...}) then return formatstring end
   local ok, msg = pcall(function(fmt,...) 
      return assert(string.format(fmt,...))
   end, formatstring, ...)
   if not ok then 
      -- strip the pointer to this function:
      msg = string.gsub(msg, ".+%:%d+%:% ", function () return "" end)
      error(msg,level+1) 
   end
   return msg
end


function utils.concat(t,sep)
   local s = {}
   for k,v in ipairs(t) do
      if v == nil then s[k]="nil"
      --elseif v == true then s[k] = "true"
      --elseif v == false then s[k] = "false"
      else s[k] = tostring(v) 
      end
   end
   return table.concat(s,sep)
end

function utils.loadscript(scriptname)
-- same as loadfile(scriptname), but it returns a loader which 
-- accepts the environment as parameter (see PIL3/14.5)
   local f, errmsg = io.open(scriptname,"r")
   if not f then return nil, errmsg end
   local ld = "local _ENV=... " .. f:read("*a")
   f:close()
   local loader, errmsg = load(ld,string.format("@%s",scriptname))
   if not loader then return nil, errmsg end
   return loader
end

return utils
