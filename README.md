## LunaSDL: SDL-oriented concurrency in Lua

LunaSDL is a Lua module for event-driven concurrent programming, whose design
follows the concurrency model of the
[ITU-T Specification and Description Language (SDL)](http://en.wikipedia.org/wiki/Specification_and_Description_Language).

It provides functions for the implementation of systems composed of concurrent,
reactive and intercommunicating entities called *agents* 
(akin to [Lua coroutines](http://www.lua.org/manual/5.3/manual.html#2.6)).

LunaSDL requires [Lua](http://www.lua.org/) (>=5.2), and
[LuaSocket](https://github.com/diegonehab/luasocket).
It is is written in plain Lua, so no compiling is needed.

It has been tested on Linux (Fedora 21) and on OpenBSD (5.6). It may run
on any other OS supported by Lua and LuaSocket, but this has not been tested.

_Authored by:_ _[Stefano Trettel](https://www.linkedin.com/in/stetre)_

[![Lua logo](./doc/powered-by-lua.gif)](http://www.lua.org/)

#### License

MIT/X11 license (same as Lua). See [LICENSE](./LICENSE).

#### Documentation

See the [Reference Manual](https://stetre.github.io/lunasdl/doc/index.html).

#### Getting and installing

See [here](https://stetre.github.io/lunasdl/doc/index.html#_getting_and_installing).

#### Examples

See [here](https://stetre.github.io/lunasdl/doc/index.html#_examples).

