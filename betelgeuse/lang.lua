--- A high level language for Rigel.
-- @module lang
require 'betelgeuse.util'
local asdl = require 'asdl'
local List = asdl.List

-- @todo: consider supporting tiling/stripping?
-- @todo: flatMap?
local L = {}

local T = asdl.NewContext()
T:Define [[
Type = fixed(number i, number f)
     | tuple(Type* ts)
     | array2d(Type t, number w, number h)

Value = input(Type t)
      | const(Type t, any v)
#      | placeholder(Type t)
      | concat(Value* vs) # @todo: it might be nice if i can index this with [n]
      | index(Value v, number n) # @todo: should this be a Module or a Value?
      | apply(Module m, Value v)
      attributes(Type type)

Module = add(boolean expanding)
       | sub(boolean expanding)
       | mul(boolean expanding)
       | div(boolean expanding)
       | shift(number n, boolean expanding)
       | trunc(number i, number f)
       | buffer(number size)
       | map(Module m)
       | reduce(Module m)
       | zip
       | stencil(number offset_x, number offset_y, number extent_x, number extent_y)
       | gather_stencil(number w, number y)
#       | partition_x(number n)
#       | partition_y(number n)
       | pad(number left, number right, number top, number bottom)
       | crop(number left, number right, number top, number bottom)
       | upsample(number x, number y)
       | downsample(number x, number y)
# @todo: try to figure out how to remove broadcast entirely, or at least w/h
       | broadcast(number w, number h)
#       | lift # @todo: this should raise rigel modules into this language
       | lambda(Value f, input x)
       attributes(function type_func)

# Connect = connect(Value v, Value placeholder)
]]

local function is_array_type(t)
   return t.kind == 'array2d'
end

local function is_primitive_type(t)
   return t.kind == 'fixed'
end

local L_mt = {
   __call = function(f, x)
      return L.apply(f, x)
   end
}

-- @todo: maybe make this an element in the asdl rep?
local function L_wrap(m)
   return setmetatable({ internal = m, kind = 'wrapped' }, L_mt)
end

local function L_unwrap(w)
   if w.kind == 'wrapped' then
      return w.internal
   else
      return w
   end
end

--- Returns a module that will create a stencil of the image at every input.
-- [a] -> [[a]]
function L.stencil(off_x, off_y, ext_x, ext_y)
   local function type_func(t)
      assert(t.kind == 'array2d', 'stencil requires input type to be of array2d')
      return T.array2d(T.array2d(t.t, ext_x, ext_y), t.w, t.h)
   end

   return L_wrap(T.stencil(off_x, off_y, ext_x, ext_y, type_func))
end

--- Returns a module that will create a stencil of the image at every input, offset by a specified amount.
-- ([a], [(i,j)]) -> [[a]]
function L.gather_stencil(ext_x, ext_y)
   local function type_func(t)
      assert(t.kind == 'tuple' and #t.ts == 2, 'gather_stencil requires input type to be tuple of {image, offsets}')

      local img_t = t.ts[1]
      local off_t = t.ts[2]
      assert(img_t.w == off_t.w and img_t.h == off_t.h, 'image and offsets must have same dimensions')
      assert(off_t.t.kind == 'tuple' and #off_t.t.ts == 2, 'offsets are expected to be 2-tuples')
      assert(off_t.t.ts[1].kind == 'int' and off_t.t.ts[2].kind == 'int', 'offsets should be ints')

      return T.array2d(T.array2d(img_t.t, ext_x, ext_y), img_t.w, img_t.h)
   end

   return L_wrap(T.gather_stencil(ext_x, ext_y, type_func))
end

--- Returns a module that will duplicate the input to a 2d array.
-- This module will return a 2d array where every element is equal to the input once applied.
-- a -> [a]
function L.broadcast(w, h)
   print("WARNING: broadcast is deprecated! Map with a module instead.")
   local function type_func(t)
      return T.array2d(t, w, h)
   end

   return L_wrap(T.broadcast(w, h, type_func))
end

--- Returns a module that will pad the input by a specified amount.
function L.pad(left, right, top, bottom)
   local function type_func(t)
      assert(t.kind == 'array2d', 'pad requires input type of array2d')
      return T.array2d(t.t, t.w+left+right, t.h+top+bottom)
   end

   return L_wrap(T.pad(left, right, top, bottom, type_func))
end

--- Returns a module that will crop the input by a specified amount.
function L.crop(left, right, top, bottom)
   local function type_func(t)
      assert(t.kind == 'array2d', 'crop requires input type of array2d')
      return T.array2d(t.t, t.w-left-right, t.h-top-bottom)
   end

   return L_wrap(T.crop(left, right, top, bottom, type_func))
end

function L.upsample(x, y)
   local function type_func(t)
      assert(t.kind == 'array2d', 'upsample requires input type of array2d')
      return T.array2d(t.t, t.w*x, t.h*y)
   end

   return L_wrap(T.upsample(x, y, type_func))
end

function L.downsample(x, y)
   local function type_func(t)
      assert(t.kind == 'array2d', 'downsample requires input type of array2d')
      assert(t.w % x == 0, 'please downsample by a multiple of image size')
      assert(t.h % y == 0, 'please downsample by a multiple of image size')
      return T.array2d(t.t, t.w/x, t.h/y)
   end

   return L_wrap(T.downsample(x, y, type_func))
end

--- Returns a module that will zip two inputs together.
-- ([a], [b]) -> [(a, b)].
function L.zip()
   local function type_func(t)
      assert(t.kind == 'tuple', 'zip requires input type to be tuple')
      for _,t in ipairs(t.ts) do
         assert(is_array_type(t), 'zip operates over tuple of arrays')
      end

      local w = t.ts[1].w
      local h = t.ts[1].h
      local types = {}
      for i,t  in ipairs(t.ts) do
         assert(t.w == w and t.h == h, 'inputs must have same array dimensions')
         types[i] = t.t
      end
      return L.array2d(L.tuple(types), w, h)
   end

   return L_wrap(T.zip(type_func))
end

--- Returns a module that will recursively zip inputs.
-- Given a tuple of inputs, it will recursively apply maps of zips while all inputs share the same outer array type.
-- For example, ([[[a]]], [[b]]) -> [[([a], b)]].
function L.zip_rec()
   return L_wrap(
      function(v)
         assert(v.type.kind == 'tuple')

         local m = L.zip()
         local types = {}
         for i,t in ipairs(v.type.ts) do
            types[i] = t
         end

         local function all_array_t()
            for _,t in ipairs(types) do
               if not is_array_type(t) then
                  return false
               end
            end
            return true
         end

         while all_array_t() do
            v = L.apply(m, v)
            m = L.map(m)

            for i,t in ipairs(types) do
               types[i] = t.t
            end
         end

         return v
      end
   )
end

-- @todo: at some point should consider if add/sub/mul/div should take in n inputs instead of just a binop, for the sake of extending bit widths.
--- Returns a module that adds two primitive types.
function L.add(expanding)
   local expanding = expanding or false

   local function type_func(t)
      assert(t.kind == 'tuple', 'binop requires tuple input')
      assert(#t.ts == 2, 'binop works on two elements')
      assert(t.ts[1].kind == t.ts[2].kind, 'binop requires both elements in tuple to be of same type')
      assert(is_primitive_type(t.ts[1]), 'binop requires input to be primitive type but was ' .. t.ts[1].kind)

      if (expanding) then
         return L.fixed(math.max(t.ts[1].i, t.ts[2].i) + 1,
                        math.max(t.ts[1].f, t.ts[2].f))
      else
         return L.fixed(math.max(t.ts[1].i, t.ts[2].i),
                        math.max(t.ts[1].f, t.ts[2].f))
      end
   end

   return L_wrap(T.add(expanding, type_func))
end

--- Returns a module that subtracts two primitive types.
function L.sub(expanding)
   local expanding = expanding or false

   local function type_func(t)
      assert(t.kind == 'tuple', 'binop requires tuple input')
      assert(#t.ts == 2, 'binop works on two elements')
      assert(t.ts[1].kind == t.ts[2].kind, 'binop requires both elements in tuple to be of same type')
      assert(is_primitive_type(t.ts[1]), 'binop requires input to be primitive type but was ' .. t.ts[1].kind)

      if (expanding) then
         return L.fixed(math.max(t.ts[1].i, t.ts[2].i) + 1,
                        math.max(t.ts[1].f, t.ts[2].f))
      else
         return L.fixed(math.max(t.ts[1].i, t.ts[2].i),
                        math.max(t.ts[1].f, t.ts[2].f))
      end
   end

   return L_wrap(T.sub(expanding, type_func))
end

--- Returns a module that multiplies two primitive types.
function L.mul(expanding)
   local expanding = expanding or false

   local function type_func(t)
      assert(t.kind == 'tuple', 'binop requires tuple input')
      assert(#t.ts == 2, 'binop works on two elements')
      assert(t.ts[1].kind == t.ts[2].kind, 'binop requires both elements in tuple to be of same type')
      assert(is_primitive_type(t.ts[1]), 'binop requires input to be primitive type but was ' .. t.ts[1].kind)

      if (expanding) then
         return L.fixed(math.max(t.ts[1].i, t.ts[2].i) * 2,
                        math.max(t.ts[1].f, t.ts[2].f) * 2)
      else
         return L.fixed(math.max(t.ts[1].i, t.ts[2].i),
                        math.max(t.ts[1].f, t.ts[2].f))
      end
   end

   return L_wrap(T.mul(expanding, type_func))
end

--- Returns a module that divides two primitive types.
function L.div(expanding)
   local expanding = expanding or false

   local function type_func(t)
      assert(t.kind == 'tuple', 'binop requires tuple input')
      assert(#t.ts == 2, 'binop works on two elements')
      assert(t.ts[1].kind == t.ts[2].kind, 'binop requires both elements in tuple to be of same type')
      assert(is_primitive_type(t.ts[1]), 'binop requires input to be primitive type but was ' .. t.ts[1].kind)

      if (expanding) then
         return L.fixed(math.max(t.ts[1].i, t.ts[2].i) * 2,
                        math.max(t.ts[1].f, t.ts[2].f) * 2)
      else
         return L.fixed(math.max(t.ts[1].i, t.ts[2].i),
                        math.max(t.ts[1].f, t.ts[2].f))
      end
   end

   return L_wrap(T.div(expanding, type_func))
end

--- Returns a module that shifts by n bits
function L.shift(n, expanding)
   local expanding = expanding or false

   local function type_func(t)
      assert(t.kind == 'fixed', 'shift requires fixed point input')
      if expanding then
         return L.fixed(t.i - n, t.f + n)
      else
         return t
      end
   end

   return L_wrap(T.shift(n, expanding, type_func))
end

--- Truncates to i integer and f fractional bits
function L.trunc(i, f)
   local function type_func(t)
      assert(is_primitive_type(t), 'truncate requires primitive input type')
      assert(t.i >= i and t.f >= f, 'truncate cannot expand types')
      return L.fixed(i, f)
   end

   return L_wrap(T.trunc(i, f, type_func))
end

--- Buffers a stream with a FIFO queue.
function L.buffer(size)
   local function type_func(t)
      return t
   end

   return L_wrap(T.buffer(size, type_func))
end

--- Returns a module that is a map given a module to apply.
function L.map(m)
   local m = L_unwrap(m)

   local function type_func(t)
      assert(is_array_type(t), 'map operates on arrays')
      return L.array2d(m.type_func(t.t), t.w, t.h)
   end

   return L_wrap(T.map(m, type_func))
end

--- Returns a module that is a sequence of modules being applied,
function L.chain(...)
   -- save varargs so returned function can use them
   local ms = {}
   for i,m in ipairs({...}) do
      ms[i] = m
   end

   return L_wrap(
      function(v)
         for _,m in ipairs(ms) do
            v = L.apply(m, v)
         end
         return v
      end
   )
end

--- Returns a module that is a reduce given the provided module.
-- This is implemented using a tree-reduction.
function L.reduce(m)
   local m = L_unwrap(m)

   local function type_func(t)
      assert(is_array_type(t), 'reduce operates on arrays')

      local in_type = t.t

      -- if we're not expanding bits, just calculate output
      if not m.expanding then
         return m.type_func(L.tuple(in_type, in_type))
      end

      -- tree depth is log2 for a binop
      local depth = math.log(t.w * t.h)/math.log(2)

      -- do a tree reduction with module type function to calculate output type
      for i=1,depth do
         in_type = m.type_func(L.tuple(in_type, in_type))
      end

      return in_type
   end

   return L_wrap(T.reduce(m, type_func))
end

--- Applies the module on the provided value.
function L.apply(m, v)
   local m = L_unwrap(m)

   if type(m) == 'function' then
      return m(v)
   else
      return T.apply(m, v, m.type_func(v.type))
   end
end

--- Creates an input value given a type.
function L.input(t)
   return T.input(t, t)
end

-- --- Creates a 1d array type.
-- function L.array(t, n)
--    return T.array2d(t, n, 1)
-- end

--- Creates a 2d array type.
function L.array2d(t, w, h)
   return T.array2d(t, w, h)
end

--- Creates a tuple type given any number of types.
function L.tuple(...)
   if #{...} == 1 then
      return T.tuple(List(...))
   else
      return T.tuple(List{...})
   end
end

function L.fixed(i, f)
   return T.fixed(i, f)
end

-- --- A placeholder that can be replaced later.
-- -- This might be needed for feedback loops.
-- -- @todo: figure out if this is actually needed.
-- -- @tparam Type t the type of the placeholder
-- function L.placeholder(t)
--    return T.placeholder(t, t)
-- end

--- Concatenates any number of values.
function L.concat(...)
   local t = {}
   for i,v in ipairs({...}) do
      t[i] = v.type
   end

   return T.concat(List{...}, L.tuple(t))
end

function L.index(v, n)
   return T.index(v, n, v.t.ts[n])
end

--- Returns a compile-time constant.
function L.const(t, v)
   return T.const(t, v, t)
end

--- Creates a module given a value and an input variable.
function L.lambda(f, x)
   local function type_func(t)
      -- @todo: should check if types are compatible, not if they completely match
      -- types are compatible if they are equivalent and the primitive fixed
      -- type of the value passed in is a subset of the fixed type of the input
      assert(tostring(x.type) == tostring(t), 'lambda expected ' .. tostring(x.type) .. ' but found ' .. tostring(t))
      return f.type
   end

   return L_wrap(T.lambda(f, x, type_func))
end

--- Exports library functions to the global namespace.
function L.import()
   local reserved = {
      import = true,
      debug = true,
   }

   for name, fun in pairs(L) do
      if not reserved[name] then
         rawset(_G, name, fun)
      end
   end
end

L.raw = T

L.unwrap = L_unwrap

return L
