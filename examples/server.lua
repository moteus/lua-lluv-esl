package.path = "..\\src\\?.lua;" .. package.path

-- FS Dialplan extension
--[[
<extension name="outbound_esl">
  <condition field="destination_number" expression="^5004$">
    <action application="socket" data="127.0.0.1:8885 async"/>
  </condition>
</extension>
--]]

local uv   = require "lluv"
local esl  = require "lluv.esl"
local log  = require "log".new(
  require "log.writer.stderr".new(),
  require "log.formatter.mix".new()
)

esl.Server({port = 8885, myevents = true, logger = log}, function(self)
  self:execute('answer', function(self, err, reply)
    if err then return end
    self:execute('playback', 'local_stream://default', function(self, err, reply)
      if err then return end
      self:hangup()
    end)
  end)
end)

uv.run()
