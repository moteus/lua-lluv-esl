package.path = "..\\src\\?.lua;" .. package.path

local uv  = require "lluv"
local esl = require "lluv.esl"

local cnn = esl.Connection()

cnn:open(function(self, err)
  if err then return print(err) end

  self:bgapi("status", function(self, err, reply)
    print('Inner command --------------')
    print(err or reply:getBody())
    print('----------------------------')
    self:close()
  end)
end)

-- we can enqueue command before `open` done.
cnn:bgapi("status", function(self, err, reply)
  print('Outer command --------------')
  print(err or reply:getBody())
  print('----------------------------')
end)

uv.run()
