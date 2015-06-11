local uv           = require "lluv"
local ut           = require "lluv.utils"
local EventEmitter = require "lluv.esl.EventEmitter"
local cjson        = require "cjson.safe"
local lom          = require "lxp.lom"

local EOL = '\n'

local function hex_to_char(h)
  return string.char(tonumber(h, 16))
end

local function char_to_hex(ch)
  return string.format("%%%.2X", string.byte(ch))
end

local function decodeURI(str)
  return (string.gsub(str, '%%(%x%x)', hex_to_char))
end

local function encodeURI(str)
  return (string.gsub(str, '[^A-Za-z0-9.%-\\/_: ]', char_to_hex))
end

local ESLEvent = ut.class() do

function ESLEvent:__init(headers, body)
  self._headers = headers
  self._body    = body or self._headers._body
  self._headers._body = nil

  return self
end

function ESLEvent:encode(fmt)
  if self._body then
    self:addHeader('Content-Length', tostring(#self._body))
  end

  fmt = fmt or 'plain'

  if fmt == 'plain' then
    local data = {}
    for k, v in pairs(self._headers) do
      data[#data + 1] = k .. ': ' .. encodeURI(v)
    end
    data[#data + 1] = ''
    data[#data + 1] = self._body

    return table.concat(data, EOL)
  end

  if fmt == 'json' then
    self._headers._body = self._body
    local str = cjson.encode(self._headers._body)
    self._headers._body = nil
    return str
  end

  if fmt == 'xml' then
    local data = {
      '<event>' .. EOL,
      '  <headers>' .. EOL,
    }

    for k, v in pairs(self._headers) do
      data[#data + 1] = '    <' .. k .. '>' .. v .. '</' .. k .. '>' .. EOL
    end
    data[#data + 1] = '  </headers>' .. EOL

    if self._body then
      data[#data + 1] = '  <body>' .. EOL
      data[#data + 1] = self._body
      data[#data + 1] = '  </headers>' .. EOL
    end

    data[#data + 1] = '</event>'

    return table.concat(data)
  end

  error('Unsupported format:' .. fmt)
end

function ESLEvent:getHeader(name)
  return self._headers[name]
end

function ESLEvent:addHeader(name, value)
  self._headers[name] = value
  return self
end

function ESLEvent:delHeader(name)
  self._headers[name] = nil
  return self
end

function ESLEvent:getVariable(name)
  return self:getHeader('variable_' .. name)
end

function ESLEvent:addVariable(name, value)
  return self:addHeader('variable_' .. name, value)
end

function ESLEvent:delVariable(name)
  return self:delHeader('variable_' .. name)
end

function ESLEvent:getBody()
  return self._body
end

function ESLEvent:addBody(body, type)
  self._body = (self._body or '') .. body
  if type then self:addHeader('Content-Type', type) end

  return self
end

function ESLEvent:delBody()
  self._body = nil
  self:delHeader('Content-Type')

  return self
end

function ESLEvent:type()
  return self:getHeader('Event-Name')
end

function ESLEvent:headers()
  return next, self._headers
end

function ESLEvent:getReply()
  local reply = self._headers['Reply-Text']
  if reply then
    local ok, msg = reply:match("^[-+](%S+)%s+(.+)$")
    return ok, msg
  end
end

function ESLEvent:getReplyOk(txt)
  local ok, msg = self:getReply()
  if ok == 'OK' then
    if txt then return txt == msg end
    return msg
  end
end

function ESLEvent:getReplyErr(txt)
  local ok, msg = self:getReply()
  if ok == 'ERR' then
    if txt then return txt == msg end
    return msg
  end
end

end

local ESLParser = ut.class() do

function ESLParser:__init()
  self._buf = ut.Buffer.new(EOL)
  self:_reset_context()
  return self
end

function ESLParser:_reset_context()
  self._ctx = {
    state   = 'header';
    headers = {};
    content = {};
  }
end

function ESLParser:append(data)
  self._buf:append(data)
  return self
end

local decode_xml_event do

local function find_tag(t, name)
  for i = 1, #t do
    local elem = t[i]
    if type(elem) == 'table' and elem.tag == name then
      return elem
    end
  end
end

local function read_headers(t)
  t = find_tag(t, 'headers')
  if not t then return nil, 'invalid xml message' end

  local h = {}
  for i = 1, #t do
    local elem = t[i]
    if type(elem) == 'table' then
      h[elem.tag] = elem[1]
    end
  end

  return h
end

local function read_body(t)
  t = find_tag(t, 'body')
  if t then return t[1] end
end

decode_xml_event = function (msg)
  local t, err = lom.parse(msg)
  if not t then return nil, err end

  if t.tag ~= 'event' then return nil, 'invalid xml message' end

  local headers, err = read_headers(t)
  if not headers then return nil, err end

  headers._body = read_body(t)
  return headers
end

end

function ESLParser:_plain_event(data)
  local b = ut.Buffer.new(EOL):append(data)
  local headers = {}
  while true do
    local line = b:read_line()
    assert(line)
    if line == '' then
      local length = tonumber(headers['Content-Length'])
      if length and length > 0 then headers._body = b:read_n(length) end
      assert(nil == b:read_some())
      break
    end
    local key, val = ut.split_first(line, "%s*:%s*")
    headers[key] = decodeURI(val)
  end
  return headers
end

function ESLParser:_json_event(data)
  return cjson.decode(data)
end

function ESLParser:_xml_event(data)
  return decode_xml_event(data)
end

function ESLParser:next_event()
  local ctx     = self._ctx
  local headers = ctx.headers
  local content = ctx.content

  while ctx.state == 'header' do
    local line = self._buf:read_line()
    if not line then return true end

    if line == '' then
      local length = tonumber(headers['Content-Length'])
      if length and length > 0 then
        content.length = length
        ctx.state = 'content'
      else
        ctx.state = 'done'
      end
      break
    end

    local key, val = ut.split_first(line, "%s*:%s*")
    if not val then
      return nil, GNTPError_EPROTO("invalid header: " .. line)
    end

    headers[key] = decodeURI(val)
  end

  if ctx.state == 'content' then
    local data = self._buf:read_n(content.length)
    if not data then return true end
    content.body = data
    ctx.state = 'done'
  end

  self:_reset_context()

  local event
  if content.body then
    if     headers['Content-Type'] == 'text/event-plain' then event = self:_plain_event(content.body)
    elseif headers['Content-Type'] == 'text/event-json'  then event = self:_json_event(content.body)
    elseif headers['Content-Type'] == 'text/event-xml'   then event = self:_xml_event(content.body)
    end
  end

  event = event and ESLEvent.new(event) or ESLEvent.new(headers, content.body)

  return event, headers
end

function ESLParser:reset()
  self._buf:reset()
  self:_reset_context()
  return self
end

end

local ESLConnection = ut.class(EventEmitter) do

local function encode_cmd(cmd, args)
  cmd = cmd .. EOL
  if args then 
    if type(args) == "table" then
      cmd = cmd .. table.concat(args, EOL) .. EOL
    else
      cmd = cmd .. args .. EOL
    end
  end

  return cmd .. EOL
end

function ESLConnection:__init()
  self.__base.__init(self)

  self._host     = '127.0.0.1'
  self._port     = 8021
  self._pass     = 'ClueCon'
  self._queue    = ut.Queue.new()
  self._parser   = ESLParser.new()
  self._bgjobs   = nil
  self._authed   = false
  self._cli      = nil
  self._events   = {'BACKGROUND_JOB', 'CHANNEL_EXECUTE_COMPLETE'}

  return self
end

function ESLConnection:_close(err)
  self._cli:close()

  while true do
    local fn = self._queue:pop()
    if not fn then break end
    fn(self, err)
  end

  for jid, fn in pairs(self._bgjobs) do
    fn(self, err)
  end

  self._cli, self._bgjobs = nil
end

function ESLConnection:close()
  self:_close()
end

local IS_EVENT = {
  ['text/event-plain'] = true;
  ['text/event-json']  = true;
  ['text/event-xml']   = true;
}

function ESLConnection:_on_event(event, headers)
  if not event then
    return self:_close(headers)
  end

  local ct = headers['Content-Type']

  if ct == 'command/reply' or ct == 'api/response' then
    cb = self._queue:pop()
    return cb(self, nil, event, headers)
  end

  if IS_EVENT[ct] then
    local name = event:type()

    if name == 'BACKGROUND_JOB' then
      local jid = event:getHeader('Job-UUID')
      fn = self._bgjobs[jid]
      if fn then
        self._bgjobs[jid] = nil
        fn(self, nil, event, headers)
      end
      return
    end

    self:emit(name, self, event, headers)

    self:emit('*',  self, event, headers)

    return
  end

  if ct == 'text/disconnect-notice' then
    self._close('shutdown')
  end

  if self._authed == nil then -- this is first event
    assert(ct == 'auth/request')
    self._authed = false
    return self._cli:write(encode_cmd("auth " .. self._pass))
  end
end

function ESLConnection:open(cb)
  if self._cli then return end

  self._cli = uv.tcp():connect(self._host, self._port, function(cli, err)
    if err then
      self._cli = nil
      return cb(self, err)
    end

    self._parser:reset()
    self._authed = nil
    self._bgjobs = {}

    cli:start_read(function(cli, err, data)
      if err then return self:_close(err) end

      self._parser:append(data)

      while true do
        local event, headers = self._parser:next_event()
        if not event then return self:_close(headers) end
        if event == true then return end
        self:_on_event(event, headers)
      end
    end)

    self._queue:push(function(self, err, reply, headers)
      if err then self:_close(err)
      elseif reply:getReplyOk('accepted') then
        self._authed = true
        return self:subscribe(self._events, function(self, err, reply)
          if err then self:_close(err) end
          cb(self, err)
        end)
      end
      cb(self, err, reply, headers)
    end)

  end)

  return self
end

local function dummy()end

local function on_write_done(cli, err, self)
  if err then self:_close(err) end
end

function ESLConnection:sendRecv(cmd, args, cb)
  if type(args) == 'function' then
    cb, args = args
  end
  self._cli:write(encode_cmd(cmd, args), on_write_done, self)
  self._queue:push(cb or dummy)
  return self
end

function ESLConnection:api(cmd, ...)
  return self:sendRecv('api ' .. cmd, ...)
end

function ESLConnection:bgapi(cmd, args, cb)
  if type(args) == 'function' then
    cb, args = args
  end

  return self:sendRecv('bgapi ' .. cmd, args, function(self, err, reply)
    if err or not reply:getReplyOk() then
      return cb(self, err, reply)
    end

    local jid = reply:getHeader('Job-UUID')
    self._bgjobs[jid] = cb
  end)
end

function ESLConnection:filter(header, value, cb)
  if type(header) == 'table' then
    cb = value or dummy

    local t = {}
    for k, v in pairs(header) do
      if type(v) == 'table' then
        for i = 1, #v do
          t[#t + 1] = {k, v[i]}
        end
      else
        t[#t + 1] = {k, v}
      end
    end

    local function next_filter(self, err, reply)
      if err then return cb(self, err) end

      local r = t[#t]
      if not r then return cb(self, nil, reply) end
      t[#t] = nil

      return self:sendRecv('filter ' .. r[1] .. ' ' .. r[2], next_filter)
    end

    return next_filter(self)
  end

  return self:sendRecv('filter ' .. header .. ' ' .. value, cb)
end

function ESLConnection:filterExclude(header, value, cb)
  return self:sendRecv('nixevents ' .. header .. ' ' .. value, cb)
end

function ESLConnection:filterDelete(header, value, cb)
  if type(value) == 'function' then
    cb, value = value
  end

  return self._sendRecv('filter delete ' .. header .. (value and ' ' .. value or ''), cb)
end

function ESLConnection:events(etype, events, cb)
  if type(events) == 'function' then
    cb, events = events
  end

  events = events or 'all'

  if type(events) == 'table' then
    events = table.concat(events, ' ')
  end

  return self:sendRecv('event ' .. etype .. ' ' .. events, cb)
end

function ESLConnection:subscribe(events, cb)
  return self:events('plain', events, cb)
end

function ESLConnection:divertEvents(on, cb)
  return self:sendRecv('divert_events ' .. on and 'on' or 'off', cb)
end

end

return {
  Connection = ESLConnection.new
}
