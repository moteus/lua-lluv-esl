package.path = "..\\src\\?.lua;" .. package.path

local uv  = require "lluv"
local esl = require "lluv.esl"
local log = require "log".new(
  require "log.writer.stdout".new(),
  require "log.formatter.mix".new()
)

local ESLServer = function(host, port, cb)
  uv.tcp():bind(host, port, function(server, err, host, port)
    if err then
      print("Can not bind:", tostring(err))
      return server:close()
    end

    print("Bind on: " .. host .. ":" .. port)

    print("LISTEN_START:", server:listen(function(server, err)
      print("LISTEN: ", err or "OK")
      if err then return end

      -- create client socket in same loop as server
      local cli, err = server:accept()
      if not cli then print("ACCEPT: ", err) else print("ACCEPT: ", cli:getpeername()) end
      if cli then
        local cnn = esl.Connection(cli)
        cb(cnn)
      end
    end))
  end)
end

ESLServer("*", 8885, function(cnn)
  -- cnn:on("esl::send", function(self, event, msg) print("SEND", msg) end)
  -- cnn:on("esl::recv", function(self, name, event) print("RECV", event:getHeader('Event-Name')) print(event:encode()) end)

  cnn:open(function(self, err, event)
    print('open:', event:getReply())

    self:myevents(function(self, err, event)
      print("myevents :", event:getReply())
    end)

    self:execute('answer', function(self, err, event)
      print('answer:', event:getReply())
    end)

    self:execute('echo', function(self, err, event)
      print('echo:', event:getReply())
    end)
  end)

  cnn:on("esl::error::**", function(self, name, err)
    print("ERROR", name, err)
  end)
  cnn:on("esl::close", function(self, name, err)
    print("CLOSE", name, err)
  end)
end)

uv.run()