-- callcenter-announce-position.lua
-- Announce queue position to members of all active queues
-- Code based on code from FreeSWITCH wiki

package.path = "..\\src\\?.lua;" .. package.path

local reconnect_interval = 10000

local uv  = require "lluv"
local ut  = require "lluv.utils"
local esl = require "lluv.esl"

local cnn = esl.Connection('127.0.0.1', 8022, 'ftjD28edM444')

local function notify_q(q)
  cnn:api("callcenter_config queue list members " .. q, function(self, err, reply)
    if err then return end

    local pos, members = 1, reply:getBody()

    for line in members:gmatch("[^\r\n]+") do
      if line:find("Trying", nil, true) or line:find("Waiting", nil, true) then
        local _, _, _, caller_uuid = ut.usplit(line, '|', true)
        cnn:api("uuid_broadcast "..caller_uuid.." ivr/ivr-you_are_number.wav aleg")
        cnn:api("uuid_broadcast "..caller_uuid.." digits/"..pos..".wav aleg")
        pos = pos + 1
      end
    end
  end)
end

local function notify_all_q()
  cnn:api("callcenter_config queue list", function(self, err, reply)
    if err then return end

    local _, queues = ut.split_first(reply:getBody(), "[\r\n]+")

    if queues then
      for line in queues:gmatch("[^\r\n]+") do
        local q, f = ut.split_first(line, '|', true)
        if f then notify_q(q) end
      end
    end
  end)
end

local function esl_reconnect(cnn, interval, on_connect, on_disconnect)
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

  if cnn:closed() then
    cnn:open()
  end

  return timer
end

esl_reconnect(cnn, reconnect_interval, function(self)
  print("Connection done")
end, function(self, err)
  print(string.format('Disconnected  - %s', err and tostring(err) or 'NO ERROR'))
end)

uv.run()
