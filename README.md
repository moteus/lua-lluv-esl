# lua-lluv-esl

```Lua
local cnn = esl.Connection()

cnn:open(function(self)
  self:bgapi("status", function(self, err, reply)
    print(err or reply:getBody())
    self:close()
  end)
end)
```