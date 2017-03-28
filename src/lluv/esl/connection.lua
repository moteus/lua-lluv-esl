local uv           = require "lluv"
local ut           = require "lluv.utils"
local EventEmitter = require "EventEmitter".EventEmitter
local ESLUtils     = require "lluv.esl.utils"
local ESLError     = require "lluv.esl.error"
local cjson        = require "cjson.safe"
local lom          = require "lxp.lom"

local EOL      = '\n'
local EOF      = uv.error("LIBUV", uv.EOF)
local ENOTCONN = uv.error('LIBUV', uv.ENOTCONN)

local encodeURI, decodeURI = ESLUtils.encodeURI, ESLUtils.decodeURI
local split_status = ESLUtils.split_status
local dummy, call_q, is_callable = ESLUtils.dummy, ESLUtils.call_q, ESLUtils.is_callable
local super = ESLUtils.super
local append_uniq, is_in = ESLUtils.append_uniq, ESLUtils.is_in

-------------------------------------------------------------------------------
local CmdQueue = ut.class() do

function CmdQueue:__init()
  self._q = ut.List.new()
  return self
end

function CmdQueue:reset()        self._q:reset()       return self end

function CmdQueue:push_front(v)  self._q:push_front(v) return self end

function CmdQueue:push(v)        self._q:push_back(v)  return self end

function CmdQueue:pop()   return self._q:pop_front()               end

function CmdQueue:peek()  return self._q:peek_front()              end

function CmdQueue:size()  return self._q:size()                    end

function CmdQueue:empty() return self._q:empty()                   end

end 
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
local ESLEvent = ut.class() do

function ESLEvent:__init(headers, body)
  if type(headers) == 'string' then
    self._headers = {}
    self:addHeader('Event-Name', headers)
    if body then
      self:addHeader('Event-Subclass', body)
    end
  else
    self._headers = headers
    self._body    = body or self._headers._body
    self._headers._body = nil
  end

  return self
end

local function pass(...) return ... end

function ESLEvent:encode(fmt, raw)
  if self._body then
    self:addHeader('Content-Length', tostring(#self._body))
  end

  fmt = fmt or 'plain'

  if fmt == 'plain' then
    local data, encoder = {}, raw and pass or encodeURI
    for k, v in pairs(self._headers) do
      data[#data + 1] = k .. ': ' .. encoder(v)
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
      data[#data + 1] = '  <body>'
      data[#data + 1] = self._body --! @fixme do xml encode value
      data[#data + 1] = '  </body>' .. EOL
    end

    data[#data + 1] = '</event>'

    return table.concat(data)
  end

  error('Unsupported format:' .. fmt)
end

ESLEvent.serialize = ESLEvent.encode

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
  self:delBody()

  self._body = (self._body or '') .. body
  if type then self:addHeader('Content-Type', type) end

  return self
end

function ESLEvent:delBody()
  self._body = nil
  self:delHeader('Content-Type')
  self:delHeader('Content-Length')

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
    local ok, status, msg = split_status(reply)
    if ok == nil then
      --! @todo invalid reply (raise protocol error)
    end
    return ok, status, msg
  end
end

function ESLEvent:getReplyOk(txt)
  local ok, status, msg = self:getReply()
  if ok then
    if txt then return txt == msg end
    return msg
  end
end

function ESLEvent:getReplyErr(txt)
  local ok, status, msg = self:getReply()
  if not ok then
    if txt then return txt == msg end
    return msg
  end
end

end
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
local ESLParser = ut.class() do

function ESLParser:__init(options)
  self._buf = ut.Buffer.new(EOL)
  self._max_buffer_size = options and options.max_buffer_size
  self._self            = options and options.self or self
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
  if self._max_buffer_size and self._on_overflow and self._buf:size() > self._max_buffer_size then
    self._on_overflow(self._self, self._buf:size())
  end
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
      return nil, ESLError(ESLError.EPROTO, "invalid header: " .. line)
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

function ESLParser:on_overflow(handler)
  self._on_overflow = handler
end

end
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
local function AutoReconnect(cnn, interval, on_connect, on_disconnect)
  local timer = uv.timer():start(0, interval, function(self)
    self:stop()
    cnn:open()
  end):stop()

  local connected = true

  cnn:on('esl::close', function(self, event, ...)
    local flag = connected

    connected = false

    if flag then on_disconnect(self, ...) end

    if timer:closed() or timer:closing() then
      return
    end

    timer:again()
  end)

  cnn:on('esl::ready', function(self, event, ...)
    connected = true
    on_connect(self, ...)
  end)

  return timer
end
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
local ESLConnection = ut.class(EventEmitter) do

local function encode_cmd(cmd, args)
  cmd = cmd .. EOL
  if args then
    if type(args) == "table" then
      for k, v in pairs(args) do
        if k ~= '_body' then
          cmd = cmd .. k .. ": " .. encodeURI(v) .. EOL
        end
      end

      if args._body then
        return cmd .. 
          'Content-Length: ' .. tostring(#args._body) ..
          EOL .. EOL ..
          args._body
      end
    else
      cmd = cmd .. args .. EOL
    end
  end

  return cmd .. EOL
end

local function is_socket(s)
  return ((type(s) == 'userdata')or(type(s) == 'table')) and s.start_read and s
end

local function on_write_done(cli, err, self)
  if err then
    self:emit('esl:error:io', err)
    self:_close(err)
  end
end

local register_execute_complite_handler, remove_execute_complite_handler, remove_all_execute_complite_handler do

local EXECUTE_EVENT_NAME = "esl::event::CHANNEL_EXECUTE_COMPLETE::"
local HANGUP_EVENT_NAME  = "esl::event::CHANNEL_HANGUP_COMPLETE::"

local function execute_complite_handler(self, eventName, event)
  local channel_uuid = string.sub(eventName, #EXECUTE_EVENT_NAME + 1)
  local callbacks = self._callbacks[channel_uuid]
  if not callbacks then return end

  local command_uuid = event:getHeader('Application-UUID')
  local cb = command_uuid and callbacks[command_uuid]
  if not cb then return end

  remove_execute_complite_handler(self, channel_uuid, command_uuid)
  return cb(self, nil, event)
end

local function hangup_complite_handler(self, eventName, event)
  local channel_uuid = string.sub(eventName, #HANGUP_EVENT_NAME + 1)
  local callbacks = self._callbacks[channel_uuid]
  if not callbacks then return end

  local err = ESLError(ESLError.EHANGUP, 'channel hangup')
  for command_uuid, cb in pairs(callbacks) do
    callbacks[command_uuid] = nil
    cb(self, err, event)
  end
end

register_execute_complite_handler = function(self, channel_uuid, command_uuid, cb)
  local callbacks = self._callbacks[channel_uuid]
  if not callbacks then
    callbacks = {}
    self._callbacks[channel_uuid] = callbacks
    self:on(EXECUTE_EVENT_NAME .. channel_uuid, execute_complite_handler)
    self:on(HANGUP_EVENT_NAME .. channel_uuid, hangup_complite_handler)
  end

  callbacks[command_uuid] = cb or dummy
end

remove_execute_complite_handler = function(self, channel_uuid, command_uuid)
  local callbacks = self._callbacks[channel_uuid]
  if not callbacks then
    return
  end

  local cb = assert(callbacks[command_uuid])
  callbacks[command_uuid] = nil

  if not next(callbacks) then
    self._callbacks[channel_uuid] = nil
    self:off(EXECUTE_EVENT_NAME .. channel_uuid, execute_complite_handler)
    self:off(HANGUP_EVENT_NAME .. channel_uuid, execute_complite_handler)
  end
end

remove_all_execute_complite_handler = function(self)
  for channel_uuid in pairs(self._callbacks) do
    self._callbacks[channel_uuid] = nil
    self:off(EXECUTE_EVENT_NAME .. channel_uuid, execute_complite_handler)
    self:off(HANGUP_EVENT_NAME .. channel_uuid, execute_complite_handler)
  end
end

end

local function build_events(events)
  if type(events) == 'table' then
    if is_in('ALL', events) then
      events = 'ALL'
    else
      local regular, custom = {}, {}
      for _, event in ipairs(events) do
        -- handle 'CUSTOM SMS::MESSAGE' and 'CUSTOM::SMS::MESSAGE'
        local base, sub = ut.split_first(event, '%s+')
        if not sub then base, sub = ut.split_first(event, '::', true) end

        if base == 'CUSTOM' then
          append_uniq(custom, base)
          if sub then append_uniq(custom, sub) end
        else
          append_uniq(regular, event)
        end
      end

      events = nil
      if #regular > 0 then
        events = table.concat(regular, ' ')
      end

      if #custom > 0 then
        events = events and (events .. ' ') or ''
        events = events .. table.concat(custom, ' ')
      end
    end
  end

  return events or 'ALL'
end

local function build_filter(header)
  local t = {}
  for k, v in pairs(header) do
    if type(k) == 'number' then k = 'Event-Name' end
    if type(v) == 'table' then
      for i = 1, #v do
        t[#t + 1] = {k, v[i]}
      end
    else
      t[#t + 1] = {k, v}
    end
  end
  return t
end

local function on_buffer_overflow(self, size)
  self:emit('esl::overflow::buffer', size)
end

function ESLConnection:__init(host, port, password)
  self = super(self, '__init', {wildcard = true, delimiter = '::'})

  local cli, options = is_socket(host)
  if cli then
    host, port = cli:getpeername()
  elseif type(host) == 'table' then
    options = host
    cli = is_socket(options.socket or options[1])
    if cli then
      host, port = cli:getpeername()
    else
      host     = options.host     or options[1]
      port     = options.port     or options[2]
      password = options.password or options[3]
    end
  end

  self._inbound   = not cli
  self._opening   = nil
  self._cli       = cli
  self._host      = host or '127.0.0.1'
  self._port      = port or 8021
  self._pass      = password or 'ClueCon'
  self._parser    = ESLParser.new{self = self,
    max_buffer_size = options and options.alarm_buffer_size
  }
  self._bgjobs    = nil
  self._authed    = false
  self._filtered  = nil
  self._async     = nil
  self._lock      = nil
  self._callbacks = {}
  self._handlers  = {}
  self._execute_wait_response = not (options and options.no_execute_result)
  self._events    = {}

  self._parser:on_overflow(on_buffer_overflow)

  if not (options and options.no_bgapi) then
    append_uniq(self._events, 'BACKGROUND_JOB')
  end

  if self._execute_wait_response then
    append_uniq(self._events, 'CHANNEL_EXECUTE_COMPLETE')
    append_uniq(self._events, 'CHANNEL_HANGUP_COMPLETE')
  end

  if self._inbound then
    if options and options.subscribe then
      self._auto_subscribe = build_events(options.subscribe)
    end

    if (#self._events > 0) and (self._auto_subscribe ~= 'ALL') then
      local events = table.concat(self._events, ' ')
      if self._auto_subscribe then
        self._auto_subscribe = events .. ' ' .. self._auto_subscribe
      else
        self._auto_subscribe = events
      end
    end

    if options and options.filter then
      self._auto_filter = build_filter(options.filter)
    end
  end

  if self._inbound and options and options.reconnect then
    local interval = 30
    if type(options.reconnect) == 'number' then
      interval = options.reconnect * 1000
    end
    self._reconnect_interval = interval
  end

  self._open_q    = ut.Queue.new()
  self._close_q   = ut.Queue.new()
  self._queue     = CmdQueue.new()
  self._delay_q   = ut.Queue.new()

  return self
end

function ESLConnection:_close(err, cb)
  if is_callable(err) then
    cb, err = err
  end

  if not self._cli then
    if cb then uv.defer(cb, self) end
    return
  end

  if cb then self._close_q:push(cb) end

  if self._cli:closed() or self._cli:closing() then
    return
  end

  local cb_err = err or ESLError(ESLError.EINTR, 'user interrupt')
  self._cli:close(function()
    self._cli = nil

    call_q(self._open_q, self, cb_err)

    call_q(self._queue,  self, cb_err)

    if self._bgjobs then
      for jid, fn in pairs(self._bgjobs) do
        fn(self, cb_err)
      end
    end

    for _, callbacks in pairs(self._callbacks) do
      for uuid, cb in pairs(callbacks) do
        callbacks[uuid] = nil
        cb(self, err)
      end
    end

    remove_all_execute_complite_handler(self)

    call_q(self._close_q, self, err)

    self._filtered, self._bgjobs = nil
    self._authed = false

    self:emit('esl::close', err)
  end)
end

function ESLConnection:close(cb)
  if self._reconnect then
    self._reconnect:close()
    self._reconnect = nil
  end
  self:_close(nil, cb)
end

function ESLConnection:closed()
  return not self._cli
end

local IS_EVENT = {
  ['text/event-plain'] = true;
  ['text/event-json']  = true;
  ['text/event-xml']   = true;
  ['log/data']         = true;
}

function ESLConnection:_on_event(event, headers)
  self:emit('esl::recv', event, headers)

  local ct = headers['Content-Type']

  if ct == 'command/reply' or ct == 'api/response' then
    local cb = self._queue:pop()
    assert(cb)
    return cb(self, nil, event, headers)
  end

  if IS_EVENT[ct] then
    local name = event:type()
    if not name then
      if ct == 'log/data' then
        name = 'LOG'
      else name = '__UNKNOWN__' end
    end

    if name == 'BACKGROUND_JOB' then
      local jid = event:getHeader('Job-UUID')
      fn = self._bgjobs[jid]
      if fn then
        self._bgjobs[jid] = nil
        fn(self, nil, event, headers)
      end
      return
    end

    uuid = event:getHeader('Event-UUID') or event:getHeader('Unique-ID') or event:getHeader('Core-UUID')
    if uuid then name = name .. '::' .. uuid end

    self:emit('esl::event::' .. name, event, headers)

    return
  end

  if ct == 'text/disconnect-notice' then
    local err = ESLError(ESLError.ERESET, 'Connection was reset')
    self:emit('esl::error::io', err)
    return self:_close(err)
  end

  if self._authed == nil then -- this is first event
    assert(ct == 'auth/request')
    self._authed = false
    return self:_write(encode_cmd("auth " .. self._pass))
  end
end

-- allows execute commands before `ready` state
-- @note you can execute only one command at the time.
-- You have to wait until command done and only then
-- send new one
local function directSendRecv(self, cmd, args, cb)
  if is_callable(args) then
    cb, args = args
  end

  cmd = encode_cmd(cmd, args)
  self:_write(cmd)
  return self._queue:push_front(cb or dummy)
end

local function on_ready(self, ...)
  self._authed = true

  self:emit('esl::ready')

  while true do
    local data = self._delay_q:pop()
    if not data then break end
    self:_write(data)
  end

  call_q(self._open_q, self, nil, ...)
end

-- called after init connection done
local function on_auth(self, reply, headers)
  -- here we can not use we regular functions because we not ready yeat
  -- so we have to use low level api.
  -- Because of that i use it only for `Inbound` connection.
  -- For `Outbound` connection we can do all this via regular functions
  -- After `Accept` but before pass object to client. So client could not
  -- execute any code before init part.
  -- Also for Outbound socket is more likely just need only `myevents` command.

  if self._auto_subscribe then
    return directSendRecv(self, 'event plain ' .. self._auto_subscribe, function(self, err, res)
      if err then
        self:emit('esl::error::io', err)
        return self:_close(err)
      end
      if self._auto_filter then
        local function filter(i)
          local f = self._auto_filter[i]
          if not f then
            return on_ready(self, reply, headers)
          end
          directSendRecv(self, 'filter ' .. f[1] .. ' ' .. f[2], function(self, err, res)
            if err then
              self:emit('esl::error::io', err)
              return self:_close(err)
            end
            self._filtered = true
            return filter(i + 1)
          end)
        end
        return filter(1)
      end
      return on_ready(self, reply, headers)
    end)
  end

  return on_ready(self, reply, headers)
end

local on_esl_reconnect  = function(self, ...) self:emit('esl::reconnect',  ...) end

local on_esl_disconnect = function(self, ...) self:emit('esl::disconnect', ...) end

function ESLConnection:open(cb)
  if self._authed then
    -- we already connected
    if cb then uv.defer(cb, self) end
    return
  end

  if self._inbound then
    if cb then self._open_q:push(cb) end

    -- we not connected but we in connecting process
    if self._cli then return end

    self._cli = uv.tcp()
  else
    if not self._cli then
      -- We really can not reconnect to Outbound connection
      if cb then uv.defer(cb, ENOTCONN) end
      return 
    end

    if cb then self._open_q:push(cb) end

    -- this is really only one time check
    -- so we do not need reset this flag again
    if self._opening then return end
    self._opening = true
  end

  if self._inbound then
    -- We apply fileter before `ready`. Also we can call `bgapi` just after `open`
    -- E.g.`cnn:open(); cnn:bgapi('status');`
    -- So we have to set this flag here (before first call of bgapi)
    self._filtered = self._auto_filter and #self._auto_filter > 0
  end

  local function on_connect(cli, err)
    if err then
      self:emit('esl::error::io', err)
      return self:_close(err)
    end

    self:emit('esl::connect')

    self._parser:reset()
    self._authed = nil
    self._bgjobs = {}

    cli:start_read(function(cli, err, data)
      if err then
        if err ~= EOF then
          self:emit('esl::error::io', err)
        end
        return self:_close(err)
      end

      self._parser:append(data)

      while true do
        local event, headers = self._parser:next_event()
        if not event then
          self:emit('esl::error::parser', headers)
          return self:_close(headers)
        end
        if event == true then return end
        self:_on_event(event, headers)
      end
    end)

    -- For Inbound connection FS response with `auth` response and
    -- we send password (see _event_handle function).
    -- After that FS response with auth result
    --
    -- For Outbound connection FS sends CHANNEL_DATA as first event
    -- getInfo() returns an ESLevent that contains this Channel Data.
    self._queue:push_front(function(self, err, reply, headers)
      if err then
        self:emit('esl::error::io', err)
        return self:_close(err)
      end

      if not self._inbound then
        self._channel_data = reply
        return on_ready(self, reply, headers)
      end

      if not reply:getReplyOk('accepted') then
        local ok, status, msg = reply:getReply()
        err = ESLError(ESLError.EAUTH, msg or "Auth fail")
        self:emit('esl::error::auth', err)
        return self:_close(err)
      end

      self:emit('esl::auth')
      return on_auth(self, reply, headers)
    end)
  end

  if not self._inbound then
    -- We have to response to FS
    local cmd = encode_cmd('connect')
    self:_write(cmd)
    return uv.defer(on_connect, self._cli)
  end

  local ok, err = self._cli:connect(self._host, self._port, on_connect)
  if not ok then
    return uv.defer(on_connect, self._cli, err)
  end

  if self._reconnect_interval and not self._reconnect then
    self._reconnect = AutoReconnect(self,
      self._reconnect_interval,
      on_esl_reconnect,
      on_esl_disconnect
    )
  end

  return self
end

function ESLConnection:getInfo()
  return self._channel_data
end

function ESLConnection:_write(data)
  self:emit('esl::send', data)
  self._cli:write(data, on_write_done, self)
end

function ESLConnection:send(cmd, args)
  if not self._cli then return nil, ENOTCONN end

  local ev = encode_cmd(cmd, args)

  if self._authed then
    self:_write(ev)
  else
    self._delay_q:push(ev)
  end

  return self
end

function ESLConnection:sendRecv(cmd, args, cb)
  if is_callable(args) then
    cb, args = args
  end
  local ok, err = self:send(cmd, args)
  if not ok then
    if cb then
      uv.defer(cb, self, err)
    end
  else
    self._queue:push(cb or dummy)
  end
  return self
end

function ESLConnection:sendEvent(event, cb)
  -- ESL library send event without urlencode
  self:sendRecv('sendevent ' .. event:type() .. '\n' .. event:encode('plain', true), cb);
end

function ESLConnection:api(cmd, ...)
  return self:sendRecv('api ' .. cmd, ...)
end

function ESLConnection:log(lvl, ...)
  return self:sendRecv('log ' .. lvl, ...)
end

function ESLConnection:nolog(...)
  return self:sendRecv('nolog', ...)
end

function ESLConnection:bgapi(cmd, args, cb)
  if type(args) == 'function' then
    cb, args = args
  end

  if type(args) == 'table' then
    args = table.concat(args, ' ')
  end

  local bgcmd = string.format("bgapi %s %s", cmd, args or '')
  local job_id

  local function on_command(self, err, reply)
    if err or not reply:getReplyOk() then
      if not err then
        self:emit('esl::error', reply)
        --! @fixme. This is protocol error.
        -- we send bgapi and does not recv Job-UUID
        -- We should reset connection
      end

      return cb(self, err, reply)
    end

    local jid = reply:getHeader('Job-UUID')
    self._bgjobs[jid] = job_id and function(...)
      self:filterDelete('Job-UUID', job_id)
      cb(...)
    end or cb
  end

  if self._filtered then
    job_id = ESLUtils.uuid()
    return self:filter('Job-UUID', job_id, function(self, err, reply)
      if err then
        return cb(self, err, reply)
      end
      return self:sendRecv(bgcmd, {['Job-UUID'] = job_id}, on_command)
    end)
  end

  return self:sendRecv(bgcmd, on_command)
end

function ESLConnection:hangup(cause, uuid, cb)
  if is_callable(uuid) then
    assert(not self._inbound)
    cb, uuid = uuid, self:getInfo():getHeader('Unique-ID')
  end

  local event = {}
  event['call-command'] = 'hangup'
  event['hangup-cause'] = cause

  self:sendRecv(uuid and ('sendmsg ' .. uuid) or 'sendmsg' , event, cb)
end

function ESLConnection:execute(...)
  local async = not not self._async
  local lock  = not not self._lock
  return self:_execute(async, lock, 'execute', ...)
end

function ESLConnection:executeLock(...)
  local async = not not self._async
  local lock  = not not self._lock
  if lock == nil then lock = true end
  return self:_execute(async, lock, 'execute', ...)
end

function ESLConnection:executeAsync(...)
  local async = self._async
  if async == nil then async = true end
  local lock  = not not self._lock
  return self:_execute(async, lock, 'execute', ...)
end

function ESLConnection:executeAsyncLock(...)
  local async = self._async
  if async == nil then async = true end
  local lock  = not not self._lock
  if lock == nil then lock = true end
  return self:_execute(async, lock, 'execute', ...)
end

function ESLConnection:_execute(async, lock, cmd, app, args, uuid, cb)
  -- `sendmsg` doesn't need uuid arg when in outbound mode

  if is_callable(args) then
    cb, args, uuid = args
  end

  if is_callable(uuid) then
    cb, uuid = uuid
  end

  if type(args) == 'table' then
    loops = args.loops
    args = table.concat(args, ' ')
  end

  cb = cb or dummy

  local event = {}
  event['call-command']     = cmd
  event['execute-app-name'] = app

  -- We should not use urlencode for args.
  -- Not sure why but in other cases commands may not works.
  -- ESL library do the same, but uses only header.
  -- So I just always pass args as content.
  if not args then 
    event['execute-app-arg'] = '_undef_'

  -- elseif (#args < 2048) and (not string.find(args, '[%z\n\r=,]')) then
  --   event['execute-app-arg'] = args

  else
    -- FS Book mentioned that need pass args more than 2048
    -- as content, but not as header
    event['Content-Type'] = 'text/plain'
    event._body = args
  end

  if loops then
    event['loops'] = loops
  end

  if self._inbound and not uuid then
    local err = ESLError(ESLError.EARGS, 'no uuid provided for Inbound connection')
    return uv.defer(cb, self, err)
  end

  if async then event['async'] = 'true' end
  if lock  then event['event-lock'] = 'true' end

  -- When we send `sendmsg uuid ....` to FS FS reply with
  -- Content-Type: command/reply\r\nReply-Text: +OK
  -- But execution is really not start yeat.
  -- When application start execute FS send `CHANNEL_EXECUTE` event
  -- When application done FS send CHANNEL_EXECUTE_COMPLETE.
  -- To identify such events with specific command we send 
  -- `Event-UUID` header and FS add its value as `Application-UUID`
  -- Not sure where is documented.
  -- Also if channel hangup before starting execute app there
  -- will no CHANNEL_EXECUTE_COMPLETE event so we have to handle
  -- `CHANNEL_HANGUP` or `CHANNEL_HANGUP_COMPLITE` events

  local channel_uuid = uuid or self:getInfo():getHeader('Unique-ID')
  local command_uuid = ESLUtils.uuid()
  event['Event-UUID'] = command_uuid

  if self._execute_wait_response then
    register_execute_complite_handler(self, channel_uuid, command_uuid, cb or dummy)
  end

  self:sendRecv(uuid and ('sendmsg ' .. uuid) or 'sendmsg', event, function(self, err, reply)
    if err or not reply:getReplyOk() then
      if self._execute_wait_response then
        remove_execute_complite_handler(self, channel_uuid, command_uuid)
      end
      return cb(self, err, reply)
    end
    if not self._execute_wait_response then
      return cb(self, err, reply)
    end
  end)

  return command_uuid
end

function ESLConnection:setAsyncExecute(value)
  self._async = value
  return self
end

function ESLConnection:setEventLock(value)
  self._lock = value
  return self
end

local function filter(self, header, value, cb)
  self._filtered = true
  return self:sendRecv('filter ' .. header .. ' ' .. value, cb)
end

local function filterExclude(self, header, value, cb)
  self._filtered = true
  return self:sendRecv('nixevents ' .. header .. ' ' .. value, cb)
end

local function filterDelete(self, header, value, cb)
  self._filtered = true
  return self:sendRecv('filter delete ' .. header .. (value and (' ' .. value) or ''), cb)
end

local function filter_impl(self, fn, header, value, cb)
  if type(header) == 'table' then
    cb = cb or value or dummy
    local t = build_filter(header)

    local n, first_err = #t
    for i = 1, #t do
      local r = t[i]
      fn(self, r[1], r[2], function(self, err, reply)
        n = n - 1
        first_err = first_err or err
        if n == 0 then cb(self, err or first_err, reply) end
      end)
    end
    if n == 0 then uv.defer(cb, self) end

    return self
  end

  if type(value) == 'function' then
    header, value, cb = 'Event-Name', header, value
  end

  return fn(self, header, value, cb)
end

function ESLConnection:filter(header, value, cb)
  return filter_impl(self, filter, header, value, cb)
end

function ESLConnection:filterExclude(header, value, cb)
  return filter_impl(self, filterExclude, header, value, cb)
end

function ESLConnection:filterDelete(header, value, cb)
  if type(value) == 'function' then
    cb, value = value
  end

  return filter_impl(self, filterDelete, header, value, cb)
end

function ESLConnection:myevents(cb)
  return self:sendRecv('myevents', cb)
end

function ESLConnection:events(etype, events, cb)
  if type(events) == 'function' then
    cb, events = events
  end

  events = build_events(events)

  if events ~= 'ALL' and not self._inbound then
    -- for `Inbound` connection we already subscribe to all `self._events`
    -- events when we did connection
    events = table.concat(self._events, ' ') .. ' ' .. events
  end

  return self:sendRecv('event ' .. etype .. ' ' .. events, cb)
end

-- this command unsubscribe from all events and also
-- flush all pending events. So use it very carefully.
function ESLConnection:noevents(cb)
  return self:sendRecv('noevents', cb)
end

function ESLConnection:subscribe(events, cb)
  return self:events('plain', events, cb)
end

function ESLConnection:divertEvents(on, cb)
  return self:sendRecv('divert_events ' .. (on and 'on' or 'off'), cb)
end

end
-------------------------------------------------------------------------------

return {
  Event      = ESLEvent.new;
  Parser     = ESLParser.new;
  Connection = ESLConnection.new;
}
