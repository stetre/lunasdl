-- Agent script: player.lua

local interval = 5
local T = sdl.timer(interval,"T_EXPIRED")
local peer

local function PrintSignal()
   sdl.printf("%s: Received %s from %u",name_,signame_,sender_)
end

local function Init(ping_interval)
   interval = ping_interval or interval
   sdl.nextstate("Waiting")
end

local function Waiting_Start()
   PrintSignal()
   peer = signal_[2]
   sdl.set(T, sdl.now()+interval)
   sdl.nextstate("Initiator")
end   

local function Initiator_TExpired()
   sdl.send({ "PING", self_ }, peer)
   sdl.set(T, sdl.now()+interval)
end

local function Initiator_Pong()
   PrintSignal()
end   

local function Waiting_Ping()
   PrintSignal()
   sdl.send({ "PONG", self_ }, signal_[2])
   sdl.nextstate("Responder")
end   

local Responder_Ping = Waiting_Ping

local function Any_Stop()
   PrintSignal()
   sdl.stop()
end


sdl.start(Init)
sdl.transition("Waiting", "START", Waiting_Start)
sdl.transition("Waiting", "PING", Waiting_Ping)
sdl.transition("Initiator", "T_EXPIRED", Initiator_TExpired)
sdl.transition("Initiator", "PONG", Initiator_Pong)
sdl.transition("Responder", "PING", Responder_Ping)
sdl.transition("Any", "STOP", Any_Stop)
sdl.default("Any")

