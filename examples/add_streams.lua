local L = require 'betelgeuse.lang'

-- add two image streams
local im_size = { 1920, 1080 }
local I = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))
local J = L.input(L.array2d(L.fixed(9, 0), im_size[1], im_size[2]))
local ij = L.zip_rec()(L.concat(I, J))
local m = L.map(L.add())(ij)
