local L = require 'betelgeuse.lang'

local im_size = { 1920, 1080 }

local dx = L.const(L.array2d(L.uint8(), 3, 3), {
                      { 1, 0, -1 },
                      { 2, 0, -2 },
                      { 1, 0, -1 }})

local dy = L.const(L.array2d(L.uint8(), 3, 3), {
                      {  1,  2,  1 },
                      {  0,  0,  0 },
                      { -1, -2, -1 }})

local gaussian = L.const(L.array2d(L.uint8(), 3, 3), {
                      { 20, 32, 20 },
                      { 32, 48, 32 },
                      { 20, 32, 20 }})

-- local gaussian = L.const(L.array2d(L.uint8(), 5, 5), {
--                       { 1,  4,  6,  4, 1 },
--                       { 4, 15, 24, 15, 4 },
--                       { 6, 24, 40, 24, 6 },
--                       { 4, 15, 24, 15, 4 },
--                       { 1,  4,  6,  4, 1 }})

local function conv(taps)
   local pad_size = im_size
   -- local pad_size = { im_size[1]+16, im_size[2]+3 }
   local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))
   local pad = L.pad(0, 0, 0, 0)(I)
   -- local pad = L.pad(8, 8, 2, 1)(I)
   local st = L.stencil(-1, -1, 3, 3)(pad)
   local wt = L.broadcast(pad_size[1], pad_size[2])(taps)
   local st_wt = L.zip_rec()(L.concat(st, wt))
   local conv = L.chain(L.map(L.map(L.mul())), L.map(L.reduce(L.add())))
   -- local conv = L.chain(conv, L.map(div256()), L.map(L.trunc(8)))
   local m = L.crop(0, 0, 0, 0)(conv(st_wt))
   -- local m = L.crop(8, 8, 2, 1)(conv(st_wt))
   local mod = L.lambda(m, I)
   return mod
end

local I = L.input(L.array2d(L.uint8(), im_size[1], im_size[2]))

-- compute image gradients
local Ix = conv(dx)(I)
local Iy = conv(dy)(I)

-- multiply gradients together
local IxIx = L.map(L.mul())(L.zip()(L.concat(Ix, Ix)))
local IxIy = L.map(L.mul())(L.zip()(L.concat(Ix, Iy)))
local IyIy = L.map(L.mul())(L.zip()(L.concat(Iy, Iy)))

local IxIx = L.stencil(-1, -1, 3, 3)(IxIx)
local IxIy = L.stencil(-1, -1, 3, 3)(IxIy)
local IyIy = L.stencil(-1, -1, 3, 3)(IyIy)

-- average the gradients for 2x2 structure tensor
local A11 = L.map(L.reduce(L.add()))(IxIx)
local A12 = L.map(L.reduce(L.add()))(IxIy)
local A21 = A12
local A22 = L.map(L.reduce(L.add()))(IyIy)

local diag = L.zip()(L.concat(A11, A22))

-- calculate det(A)
local d1 = L.map(L.mul())(diag)
local d2 = L.map(L.mul())(L.zip()(L.concat(A12, A21)))
local det = L.map(L.sub())(L.zip()(L.concat(d1, d2)))

-- calculate k*tr(A)^2
local tr = L.map(L.add())(diag)
local tr2 = L.map(L.mul())(L.zip()(L.concat(tr, tr)))
local ktr2 = L.map(L.div())(L.zip()(L.concat(tr2, L.broadcast(im_size[1], im_size[2])(L.const(L.uint8(), 20)))))

-- corner response = det(A)-k*tr(A)^2
local Mc = L.map(L.sub())(L.zip()(L.concat(det, ktr2)))

local mod = L.lambda(Mc, I)


local gv = require 'graphview'
gv(mod)

local P = require 'betelgeuse.passes'

-- utilization
local rates = {
   -- { 1, 32 },
   -- { 1, 16 },
   -- { 1,  8 },
   -- { 1,  4 },
   -- { 1,  2 },
   { 1,  1 },
   -- { 2,  1 },
   -- { 4,  1 },
   -- { 8,  1 },
}

local res = {}
for i,rate in ipairs(rates) do
   local util = P.reduction_factor(mod, rate)
   res[i] = P.translate(mod)
   -- res[i] = P.transform(res[i], util)
   -- res[i] = P.streamify(res[i], rate)
   -- res[i] = P.peephole(res[i])
end

gv(res[1])

return mod
