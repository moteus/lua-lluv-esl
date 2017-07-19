# lua-lluv-esl

[![License](http://img.shields.io/badge/License-MIT-brightgreen.svg)](LICENSE)

## FreeSWITCH ESL implementation for lluv library

```Lua
local cnn = esl.Connection()

cnn:open(function(self)
  self:bgapi("status", function(self, err, reply)
    print(err or reply:getBody())
    self:close()
  end)
end)
```
