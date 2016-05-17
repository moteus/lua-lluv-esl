local ut = require "lluv.utils"

local ESLError = ut.class() do

function ESLError:__init(no, name, msg, ext)
  self._no     = assert(no)
  self._name   = assert(name)
  self._msg    = msg or ''
  self._ext    = ext
  return self
end

function ESLError:cat()    return 'ESL'        end

function ESLError:no()     return self._no     end

function ESLError:name()   return self._name   end

function ESLError:msg()    return self._msg    end

function ESLError:ext()    return self._ext    end

function ESLError:__tostring()
  local err = string.format("[%s][%s] %s (%d)",
    self:cat(), self:name(), self:msg(), self:no()
  )
  if self:ext() then
    err = string.format("%s - %s", err, self:ext())
  end
  return err
end

function ESLError:__eq(rhs)
  return self._no == rhs._no
end

end

local errors = {} for k, v in pairs{
  EPROTO = -1;
  ERESET = -2;
  EAUTH  = -3;
  EINTR  = -4;
}do errors[k], errors[v] = v, k end

return setmetatable(errors,{__call = function(t, no, ...)
  local name
  if type(no) == 'string' then
    name, no = no, t[no]
  else
    assert(type(no) == "number")
    name = assert(t[no], "unknown error")
  end
  return ESLError.new(no, name, ...)
end})

