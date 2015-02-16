-- Main script: main.lua

local sdl = require("lunasdl")

local host = "www.w3.org" -- web site where to download the pages

local pages = { -- list of desired pages 
 "/TR/html401/html40.txt",
 "/TR/2002/REC-xhtml1-20020801/xhtml1.pdf",
 "/TR/REC-html32.html",
 "/TR/2000/REC-DOM-Level-2-Core-20001113/DOM2-Core.txt"
}

--sdl.logopen("example.log")

assert(sdl.createsystem(nil, "system", host, pages))
