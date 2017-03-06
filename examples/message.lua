package.path = "..\\src\\?.lua;" .. package.path

local uv  = require "lluv"
local esl = require "lluv.esl"

local from, to, msg = arg[1], arg[2], arg[3]

local script_name = string.match(arg[0], '([^\\/]+)$')
script_name = string.match(script_name, '(.-)%.lua$') or script_name

if not (from and to and msg) then
  io.write('Usage:\n\t', script_name, ' <FROM> <TO> <MESSAGE>', '\n')
  io.write('Example:\n\t', script_name, ' 200@domain.name 100@domain.name hello', '\n')
  os.exit(-1)
end

local function sip_contact(cnn, user, cb)
  cnn:api("sofia_contact " .. user, function(self, err, reply)
    local contact
    if not err then
      contact = (reply:getHeader('Content-Type') == 'api/response') and reply:getBody()
    end

    return cb(self, err, contact, reply)
  end)
end

local function sip_message_continue(cnn, options, cb)
  local event = esl.Event('custom', 'SMS::SEND_MESSAGE');

  event:addHeader('proto',      'sip');
  event:addHeader('dest_proto', 'sip');

  event:addHeader('from',      options.from)
  event:addHeader('from_full', 'sip:' .. options.from)

  event:addHeader('to',          options.to)
  event:addHeader('sip_profile', options.profile)
  event:addHeader('subject',     options.subject or 'SIP SIMPLE')

  if options.waitReport then
    event:addHeader('blocking', 'true')
  end

  local content_type = options.type or 'text/plain'
  event:addBody(options.body, content_type)
  event:addHeader('type', content_type)

  cnn:sendEvent(event, function(self, err, reply)
    if err then
      return cb(self, err)
    end

    local uuid = reply:getReplyOk()
    if not uuid then
      return cb(self, nil, reply)
    end

    local eventName = 'esl::event::CUSTOM::' .. uuid

    local timeout

    cnn:on(eventName, function(self, event, reply, ...)
      if (reply:getHeader('Nonblocking-Delivery') == 'true') or reply:getHeader('Delivery-Failure') then
        self:off(eventName)
        timeout:close()
        cb(self, nil, reply)
      end
    end)

    timeout = uv.timer():start(options.timeout * 1000, function()
      self:off(eventName)
      cb(self, 'timeout')
    end)
  end)
end

-- To works correctly need subscribe to `CUSTOM SMS::SEND_MESSAGE`
-- and for optimisation also add filter like
-- `filter Nonblocking-Delivery true`, 
-- `filter Delivery-Failure true` and `filter Delivery-Failure false`
local function sip_message(cnn, options, cb)
  assert(options.to)
  assert(options.from)
  options.subject = options.subject  or options.to
  options.body    = options.body     or ''
  options.timeout = options.timeout  or 120

  if (not options.profile) or options.checkContact then
    sip_contact(cnn, options.to, function(self, err, contact, reply)
      local profile
      if contact then
        profile = string.match(contact, '^sofia/(.-)/')
      end
      if profile then
        options.profile = options.profile or profile
        uv.defer(sip_message_continue, cnn, options, cb)
      else
        cb(self, err, reply)
      end
    end)
    return
  end

  return sip_message_continue(cnn, options, cb)
end

local cnn = esl.Connection{
  -- subscribe to result messages
  subscribe = {'CUSTOM SMS::SEND_MESSAGE'};
  -- ignore not result messages
  filter    = {
    ["Nonblocking-Delivery"] = "true",
    ["Delivery-Failure"]     = {"true", "false"},
  };
}

cnn:open()

sip_message(cnn, {
  from         = from;
  to           = to;
  body         = msg;
  -- profile      = 'internal';
  -- subject      = '----';
  -- type         = 'text/plain';
  waitReport   = true;
  checkContact = true;
  -- timeout      = 120;
}, function(_, err, res)
  uv.defer(function() cnn:close() end)

  -- e.g. IO fail
  if err then
    print('Fail send message: ' .. tostring(err))
    return
  end

  -- We send message without waiting response. So we really can not
  -- be sure either this message delivery or not.
  if res:getHeader('Nonblocking-Delivery') == 'true' then
    print("Async send - pass")
    return
  end

  -- We send message with waiting response.
  if res:getHeader('Delivery-Failure') then
    local code = res:getHeader('Delivery-Result-Code') or '--'
    if res:getHeader('Delivery-Failure') == 'true' then
      print('Sync send - fail (' .. code .. ')')
    else
      print('Sync send - pass (' .. code .. ')')
    end
    return
  end

  -- E.g. if we use `sip_contact` to get profile and user not registered.
  if nil == res:getReply() then
    print('Fail send message: ' .. res:getBody() or '----')
    return
  end

  -- This can be if `sendEvent` returns error?
  local _, _, msg = res:getReply()
  print('Fail send message: ' .. (msg or '----'))

  return
end)

uv.run()
