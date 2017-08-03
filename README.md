# lua-lluv-esl

[![License](http://img.shields.io/badge/License-MIT-brightgreen.svg)](LICENSE)
[![Build Status](https://travis-ci.org/moteus/lua-lluv-esl.svg?branch=master)](https://travis-ci.org/moteus/lua-lluv-esl)
[![Coverage Status](https://coveralls.io/repos/github/moteus/lua-lluv-esl/badge.svg?branch=master)](https://coveralls.io/github/moteus/lua-lluv-esl?branch=master)

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
