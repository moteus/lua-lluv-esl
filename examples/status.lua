package.path = "..\\src\\?.lua;" .. package.path

local uv  = require "lluv"
local esl = require "lluv.esl"

local cnn = esl.Connection()

cnn:open(function(self, err)
  if err then return print(err) end

  self:bgapi("status", function(self, err, reply)
    print(err or reply:getBody())
    self:close()
  end)
end)

uv.run()
