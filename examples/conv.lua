local L = require 'betelgeuse.lang'
local P = require 'betelgeuse.passes'
local R = require 'rigelSimple'
local G = require 'graphview'

-- parse command line args
local rate = { tonumber(arg[1]) or 1, tonumber(arg[2]) or 1 }

local div256 = function()
   local x = L.input(L.uint(17))
   local c = L.const(L.uint(17), 256)
   return L.lambda(L.div()(L.concat(x, c)), x)
end

-- convolution
local im_size = { 32, 32 }
local pad_size = im_size
-- local pad_size = { im_size[1]+16, im_size[2]+3 }
local I = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))
local pad = L.pad(0, 0, 0, 0)(I)
-- local pad = L.pad(8, 8, 2, 1)(I)
local st = L.stencil(-1, -1, 4, 4)(pad)
local taps = L.const(L.array2d(L.fixed(9, 0), 4, 4), {
                        {  4, 14, 14,  4 },
                        { 14, 32, 32, 14 },
                        { 14, 32, 32, 14 },
                        {  4, 14, 14,  4 }})
local wt = L.broadcast(pad_size[1], pad_size[2])(taps)
local st_wt = L.zip_rec()(L.concat(st, wt))
local conv = L.chain(L.map(L.map(L.mul())), L.map(L.reduce(L.add())))
local conv = L.chain(conv, L.map(L.shift(8)), L.map(L.trunc(8, 0)))
local m = L.crop(0, 0, 0, 0)(conv(st_wt))
-- local m = L.crop(8, 8, 2, 1)(conv(st_wt))
local mod = L.lambda(m, I)

G(mod)

-- translate to rigel and optimize
local res
local util = P.reduction_factor(mod, rate)
res = P.translate(mod)
-- res = P.transform(res, util)
res = P.streamify(res, rate)
-- res = P.peephole(res)
G(res)
res = P.make_mem_happy(res)

-- call harness
local in_size = { L.unwrap(mod).x.t.w, L.unwrap(mod).x.t.h }
local out_size = { L.unwrap(mod).f.type.w, L.unwrap(mod).f.type.h }

local fname = arg[0]:match("([^/]+).lua")

R.harness{
   fn = res,
   inFile = "box_32.raw", inSize = in_size,
   outFile = fname, outSize = out_size,
   earlyOverride = 4800, -- downsample is variable latency, overestimate cycles
}

-- return the pre-translated module
return mod
