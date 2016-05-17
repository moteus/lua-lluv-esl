local string = require "string"
local ut     = require "lluv.utils"
local uuid   = require "uuid"

local utils = {}

-- [+-][OK|ERR|USAGE|...][Message]
function utils.split_status(str)
  local ok, status, msg = string.match(str, "^%s*([-+])([^%s]+)%s*(.-)%s*$")
  if not ok then return nil, str end
  return ok == '+', status, msg
end

-------------------------------------------------------------------------------
utils.dial_string = {} do

local BaseLeg = ut.class() do

function BaseLeg:__init()
  self.private_ = {
    params = {};
  }

  self.options = setmetatable({},{
    __index = function(_, key)
      return self:get(key)
    end;
    __newindex = function(_,key,value)
      return self:set(key,value)
    end;
  })

  return o
end

function BaseLeg:set(name, value)
  if name == nil then return self end
  if type(name) == "table" then
    for k, v in pairs(name) do if type(k) == "string" then
      self:set(k,v)
    end end
  else
    self.private_.params[name] = value
  end  
  return self
end

function BaseLeg:get(name)
  return self.private_.params[name]
end

function BaseLeg:build(mask)
  local t = self.private_.params
  if not t then return '' end
  mask = mask or '[%s]'
  local options = ''
  for k,v in pairs(t) do if type(k) == 'string' then
    if options ~= '' then options = options .. ',' end
    options = options .. k .. '=' .. tostring(v)
  end end
  if options == '' then return '' end
  return (string.format(mask, options))
end

end

local Leg = ut.class(BaseLeg) do

function Leg:__init(target)
  Leg.__base.__init(self)
  self.private_.target = target
  return self
end

function Leg:target()
  return self.private_.target
end

function Leg:set_target(value)
  self.private_.target = value:match("^%s*(.-)%s*$")
end

function Leg:endpoint()
  if self.private_.target then
    return (self.private_.target:match("^([^/]+)/"))
  end
end

function Leg:build()
  if self.private_.target then
    return BaseLeg.build(self, "[%s]") .. self.private_.target
  end
end

end

local DialString = ut.class(BaseLeg) do

function DialString:__init()
  DialString.__base.__init(self)
  self.private_.legs = {};
  self.private_.params = {};
  self.private_.separator = '|';
  return self
end

function DialString:set_separator(value)
  assert(value == "|" or value == ",")
  self.private_.separator = value
  return self
end

function DialString:separator()
  return self.private_.separator
end

function DialString:add_leg(leg)
  local i = #self.private_.legs + 1
  self.private_.legs[i] = {leg = leg}
  return i
end

function DialString:remove_leg(leg)
  if not leg then return nil end 
  for i, leg_info in ipairs(self.private_.legs) do
    if leg_info.leg == leg then
      table.remove(self.private_.legs, i)
      break
    end
  end
  return leg
end

function DialString:leg_by(name, pat)
  for _, leg_info in ipairs(self.private_.legs) do
    if leg_info.leg.options[name] == pat then
      return leg
    end
  end
end

function DialString:build()
  local t = {}
  for _, leg_info in ipairs(self.private_.legs) do
    local str = leg_info.leg:build()
    if str then table.insert(t, str) end
  end
  if #t == 0 then return end
  return BaseLeg.build(self, "{%s}") .. table.concat(t,self:separator())
end

function DialString:each_leg(fn)
  for _, leg_info in ipairs(self.private_.legs) do
    if 'break' == fn(leg_info.leg) then return 'break' end
  end
end

end

local EnterpriseDialString = ut.class(BaseLeg) do

function EnterpriseDialString:__init()
  EnterpriseDialString.__base.__init(self)
  self.private_.strings = {};
  self.private_.params = {};
  return self
end

function EnterpriseDialString:add_string(dialString)
  local i = #self.private_.strings + 1
  self.private_.strings[i] = {dial_string = dialString}
  return i
end

function EnterpriseDialString:build()
  local t = {}
  for _, string_info in ipairs(self.private_.strings) do
    local str = string_info.dial_string:build()
    if str then table.insert(t, str) end
  end
  if #t == 0 then return end
  return BaseLeg.build(self, "<%s>") .. table.concat(t,":_:")
end

function EnterpriseDialString:each_string(fn)
  for _, string_info in ipairs(self.private_.strings) do
    if 'break' == fn(string_info.dial_string) then return 'break' end
  end
end

function EnterpriseDialString:each_leg(fn)
  for _, string_info in ipairs(self.private_.strings) do
    if 'break' == string_info.dial_string:each_leg(fn) then return 'break' end
  end
end

function EnterpriseDialString:remove_leg(leg)
  for _, string_info in ipairs(self.private_.strings) do
    local result = string_info.dial_string:remove_leg(leg)
    if result then return result end
  end
  return leg
end

function EnterpriseDialString:leg_by(name, pat)
  for _, string_info in ipairs(self.private_.strings) do
    local result = string_info.dial_string:leg_by(name, pat)
    if result then return result end
  end
end

end

local function CreateDialString(t)
  local dialString = DialString.new()
  if t.SEP then dialString:set_separator(t.SEP)
  elseif t.sequence ~= nil then
    dialString:set_separator(t.sequence and ',' or '|')
  end
  local i = 1
  while(t[i])do
    local leg = t[i]
    if type(leg) == "string" then
      dialString:add_leg(Leg.new(leg))
    else
      dialString:add_leg(Leg.new(leg[1]):set(leg))
    end
    i = i + 1
  end
  return dialString:set(t.options)
end

local function CreateEnterpriseDialString(t)
  local entString = EnterpriseDialString.new()
  local i = 1
  while(t.strings[i])do
    local dialString = CreateDialString(t.strings[i])
    entString:add_string(dialString)
    i = i + 1
  end
  return entString:set(t.options)
end

local function CreateString(t)
  if not t.strings then return CreateDialString(t) end
  return CreateEnterpriseDialString(t)
end

utils.dial_string.create     = assert(CreateString)
utils.dial_string.leg        = function(...) return Leg.new(...) end
utils.dial_string.enterprise = function(...) return EnterpriseDialString.new(...) end
utils.dial_string.new        = function(...) return DialString.new(...) end

end
-------------------------------------------------------------------------------

local function hex_to_char(h)
  return string.char(tonumber(h, 16))
end

local function char_to_hex(ch)
  return string.format("%%%.2X", string.byte(ch))
end

function utils.decodeURI(str)
  return (string.gsub(str, '%%(%x%x)', hex_to_char))
end

function utils.encodeURI(str)
  return (string.gsub(str, '[^A-Za-z0-9.%-\\/_: ]', char_to_hex))
end

function utils.uuid()
  return uuid.new()
end

return utils
