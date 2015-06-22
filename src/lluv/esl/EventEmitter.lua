local ut = require "lluv.utils"

local EventEmitter = ut.class() do

function EventEmitter:__init()
  self._handlers = {}
  self._once     = {}

  return self
end

function EventEmitter:on(event, handler)
  local name = event:upper()
  local list = self._handlers[name] or {}

  for i = 1, #list do
    if list[i] == handler then
      return self
    end
  end

  list[#list + 1] = handler
  self._handlers[name] = list

  return self
end

function EventEmitter:many(event, ttl, handler)
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

function EventEmitter:once(event, handler)
  return self:many(event, 1, handler)
end

function EventEmitter:off(event, handler)
  local name = event:upper()
  local list = self._handlers[name]

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

    if #list == 0 then self._handlers[name] = nil end

  else

    for handler in pairs(self._once) do
      for i = 1, #list do
        if list[i] == handler then
          self._once[handler] = nil
          break
        end
      end
    end

    self._handlers[name] = nil 

  end

  return self
end

function EventEmitter:emit(event, ...)
  local list = self._handlers[event:upper()]

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
  self._sep   = sep or '::'
  self._wld   = wildcard or '*'

  self._tree  = {}
  return self
end

local function find_emitter(self, event, tree, cb, ...)
  local name, tail = ut.split_first(event, self._sep, true)
  name = name:upper()

  local node = tree[name] -- contain subtree and/or emitter
  if not node then
    node = {nil, nil}
    tree[name] = node
  end

  if tail and tail ~= self._wld then -- find in subtree
    tree = node[1]
    if not tree then
      tree = {}
      node[1] = tree
    end
    return find_emitter(self, tail, tree, cb, ...)
  end

  local emitter = node[2]
  if not emitter then
    emitter = EventEmitter.new()
    node[2] = emitter
  end

  if tail == self._wld then
    cb(emitter, self._wld, ...)
  else
    cb(emitter, name, ...)
  end
end

function TreeEventEmitter:many(event, ...)
  find_emitter(self, event, self._tree, EventEmitter.many, ...)
  return self
end

function TreeEventEmitter:once(event, ...)
  find_emitter(self, event, self._tree, EventEmitter.once, ...)
  return self
end

function TreeEventEmitter:on(event, ...)
  find_emitter(self, event, self._tree, EventEmitter.on, ...)
  return self
end

function TreeEventEmitter:off(event, ...)
  find_emitter(self, event, self._tree, EventEmitter.off, ...)
  return self
end

local function do_emit(self, event, tree, ...)
  local name, tail = ut.split_first(event, self._sep, true)
  name = name:upper()

  local node = tree[name]
  if not node then return self end

  if node[2] then -- has emitter
    node[2]:emit(self._wld, ...)
    if not tail then
      node[2]:emit(name, ...)
    end
  end

  if not (tail and node[1]) then return self end

  return do_emit(self, tail, node[1], ...)
end

function TreeEventEmitter:emit(event, ...)
  do_emit(self, event, self._tree, ...)
  return self
end

end

return {
  EventEmitter     = EventEmitter,
  TreeEventEmitter = TreeEventEmitter
}
