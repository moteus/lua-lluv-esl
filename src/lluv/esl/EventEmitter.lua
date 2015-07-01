local ut = require "lluv.utils"

local BasicEventEmitter = ut.class() do

function BasicEventEmitter:__init()
  self._handlers = {}
  self._once     = {}

  return self
end

function BasicEventEmitter:on(event, handler)
  local list = self._handlers[event] or {}

  for i = 1, #list do
    if list[i] == handler then
      return self
    end
  end

  list[#list + 1] = handler
  self._handlers[event] = list

  return self
end

function BasicEventEmitter:many(event, ttl, handler)
  self:off(event, handler)

  local function listener(...)
    ttl = ttl - 1
    if ttl == 0 then self:off(event, handler) end
    handler(...)
  end

  self:on(event, listener)
  self._once[handler] = listener

  return self
end

function BasicEventEmitter:once(event, handler)
  return self:many(event, 1, handler)
end

function BasicEventEmitter:off(event, handler)
  local list = self._handlers[event]

  if not list then return self end

  if handler then

    local listener = self._once[handler] or handler
    self._once[handler] = nil

    for i = 1, #list do
      if list[i] == listener then
        table.remove(list, i)
        break
      end
    end

    if #list == 0 then self._handlers[event] = nil end

  else

    for handler in pairs(self._once) do
      for i = 1, #list do
        if list[i] == handler then
          self._once[handler] = nil
          break
        end
      end
    end

    self._handlers[event] = nil 

  end

  return self
end

function BasicEventEmitter:emit(event, ...)
  local list = self._handlers[event]

  if list then
    for i = #list, 1, -1 do
      if list[i] then
        -- we need this check because cb could remove some listners
        list[i](...)
        -- or uv.defer(list[i], ...)
      end
    end
  end

  return self
end

end

local TreeEventEmitter = ut.class() do

function TreeEventEmitter:__init(sep, wildcard)
  self._sep   = sep or '.'
  self._wld   = wildcard or '*'

  self._tree  = {}
  return self
end

local function ensure_emitter(node, i)
  local e = node[i]
  if e then return e end
  e = BasicEventEmitter.new()
  node[i] = e
  return e
end

local function find_emitter(self, event, node, cb, ...)
  local name, tail = ut.split_first(event, self._sep, true)

  if tail and tail ~= self._wld then -- find in subtree
    local tree = node[name]
    if not tree then
      tree = {}
      node[name] = tree
    end
    return find_emitter(self, tail, tree, cb, ...)
  end

  local emitter = ensure_emitter(node, tail == self._wld and 2 or 1)
  cb(emitter, name, ...)
end

function TreeEventEmitter:many(event, ...)
  find_emitter(self, event, self._tree, BasicEventEmitter.many, ...)
  return self
end

function TreeEventEmitter:once(event, ...)
  find_emitter(self, event, self._tree, BasicEventEmitter.once, ...)
  return self
end

function TreeEventEmitter:on(event, ...)
  find_emitter(self, event, self._tree, BasicEventEmitter.on, ...)
  return self
end

function TreeEventEmitter:off(event, ...)
  find_emitter(self, event, self._tree, BasicEventEmitter.off, ...)
  return self
end

local function do_emit(self, event, node, ...)
  if not node then return end

  local name, tail = ut.split_first(event, self._sep, true)

  if node[2] then -- Level emitter
    node[2]:emit(name, ...)
  end

  if not tail then
    if node[1] then -- Has emitter
      node[1]:emit(name, ...)
    end
    return self
  end

  return do_emit(self, tail, node[name], ...)
end

function TreeEventEmitter:emit(event, ...)
  if self._tree[1] then
    self._tree[1]:emit(self._wld, ...)
  end

  do_emit(self, event, self._tree, ...)
  return self
end

end

local EventEmitter = ut.class() do

function EventEmitter:__init(opt)
  if not opt or not opt.wildcard then
    self._impl = BasicEventEmitter.new()
  else
    self._impl = TreeEventEmitter.new(opt.delimiter)
  end
  return self
end

function EventEmitter:on(...)
  self._impl:on(...)
  return self
end

function EventEmitter:many(...)
  self._impl:many(...)
  return self
end

function EventEmitter:once(...)
  self._impl:once(...)
  return self
end

function EventEmitter:off(...)
  self._impl:off(...)
  return self
end

function EventEmitter:emit(...)
  self._impl:emit(...)
  return self
end

end

return {
  EventEmitter      = EventEmitter,
  BasicEventEmitter = BasicEventEmitter,
  TreeEventEmitter  = TreeEventEmitter,
}
