local uv  = require "lluv"
local esl = require "lluv.esl"

local fs = { '127.0.0.1', '8021', 'ClueCon' }

local pbx = esl.Connection{ fs[1], fs[2], fs[3],
  reconnect = 5; no_execute_result = true; no_bgapi = true;
  subscribe = {
    'CHANNEL_CREATE'
  };
  filter    = {
    ['Caller-Direction'] = 'inbound',
  };
}:open()

pbx:on('esl::event::CHANNEL_CREATE::**', function(self, eventName, event)
  print(eventName)
end)

pbx:on('esl::reconnect', function(self, eventName)
  -- connected to FS
  print(eventName)
end)

pbx:on('esl::disconnect', function(self, eventName, err)
  -- connection lost
  print(eventName, err)
end)

pbx:on('esl::error::**', function(self, eventName, err)
  print(eventName, err)
end)

pbx:on('esl::close', function(self, eventName, err)
  print(eventName, err)
end)


uv.run()