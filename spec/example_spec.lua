local lfs = require 'lfs'
local dir = lfs.currentdir() .. '/examples/'

require 'betelgeuse'
local G = require 'graphview'
G.render = false

-- hopefully this doesn't break busted
for i,_ in ipairs(arg) do
   arg[i] = nil
end

describe('runs all results tests', function()
            dofile(lfs.currentdir() .. '/results/run-tests.lua')
end)

-- describe('tests in the examples directory', function()
--             for iter, dir_obj in lfs.dir(dir) do
--                if string.find(iter, '.lua') then
--                   insulate(
--                      function() it(iter, function()
--                                       dofile(dir .. iter)
--                                   end)
--                   end)
--                end
--             end
-- end)
