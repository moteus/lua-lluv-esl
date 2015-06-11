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
    for i = 1, #list do
      list[i](...)
      -- or uv.defer(list[i], ...)
    end
  end

  return self
end

end

return EventEmitter
