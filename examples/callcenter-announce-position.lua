-- callcenter-announce-position.lua
-- Announce queue position to members of all active queues
-- Code based on code from FreeSWITCH wiki

package.path = "..\\src\\?.lua;" .. package.path

local uv  = require "lluv"
local ut  = require "lluv.utils"
local esl = require "lluv.esl"

local cnn = esl.Connection{'127.0.0.1', 8021, 'ClueCon',
  reconnect = 10, no_execute_result = true, no_bgapi = true;
}

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

cnn:on('esl::reconnect', function()
  print("Connection done")
end)

cnn:on('esl::disconnect', function(self, _, err)
  print(string.format('Disconnected  - %s', err and tostring(err) or 'NO ERROR'))
end)

cnn:open()

uv.run()
