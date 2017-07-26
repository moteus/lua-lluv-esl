pcall(require, "luacov")

local esl         = require "lluv.esl"
local utils       = require "utils"
local TEST_CASE   = require "lunit".TEST_CASE
local json        = require "cjson.safe"

print("------------------------------------")
print("Module    name: " .. esl._NAME);
print("Module version: " .. esl._VERSION);
print("Lua    version: " .. (jit and jit.version or _VERSION))
print("------------------------------------")
print("")

local pcall, error, type, table, tostring, print, debug = pcall, error, type, table, tostring, print, debug
local RUN = utils.RUN
local IT, CMD, PASS, SKIP_CASE = utils.IT, utils.CMD, utils.PASS, utils.SKIP_CASE
local nreturn, is_equal = utils.nreturn, utils.is_equal

local ENABLE = true

local _ENV = TEST_CASE'esl.event' if ENABLE then

local it = IT(_ENV or _M)

it('should crete new events', function()
  assert_error(function() esl.Event() end)
  local event = assert_table(esl.Event("CUSTOM"))
  assert_equal("CUSTOM", event:getType())
  assert_equal("CUSTOM", event:getHeader('Event-Name'))
end)

it('should crete new event with subclass', function()
  local event = assert_table(esl.Event("CUSTOM", 'TEST'))
  assert_equal("CUSTOM", event:getType())
  assert_equal("CUSTOM", event:getHeader('Event-Name'))
  assert_equal("TEST",   event:getHeader('Event-Subclass'))
end)

it('should crete new event from table', function()
  local event = assert_table(esl.Event({
    ['Event-Name'] = "CUSTOM", 
    ['X-Foo'] = '1'
  }))
  assert_equal("CUSTOM", event:getType())
  assert_equal("1",      event:getHeader('X-Foo'))
end)

it('event headers should not be case sensitivity', function()
  local event = assert_table(esl.Event("CUSTOM"))
  assert_equal("CUSTOM", event:getHeader('Event-Name'))
  do return skip('Not implemented') end
  assert_equal("CUSTOM", event:getHeader('event-name'))
  assert_equal("CUSTOM", event:getHeader('EVENT-NAME'))
  assert_equal("CUSTOM", event:getHeader('EvEnT-nAmE'))
end)

it('should support array headers', function()
  local event = assert_table(esl.Event("CUSTOM"))
  if not event.pushHeader then return skip('Not implemented') end
  event:pushHeader('X-Foo', '1')
  event:pushHeader('X-Foo', '2')
  event:pushHeader('X-Foo', '3')
  event:pushHeader('X-Foo', '4')
  assert(is_equal({'1', '2', '3', '4'}, event:getHeader('X-Foo')))
end)

it('should support multiple headers with same name', function()
  local event = assert_table(esl.Event("CUSTOM"))
  if not event.getHeaders then return skip('Not implemented') end
  event:addHeader('X-Foo', '1')
  event:addHeader('X-Foo', '2')
  event:addHeader('X-Foo', '3')
  event:addHeader('X-Foo', '4')
  -- returns first header only
  assert_equal('1', event:getHeader('X-Foo'))
  -- returns all headers
  assert(is_equal({'1', '2', '3', '4'}, event:getHeaders('X-Foo')))
end)

it('should deal with body', function()
  local event = assert_table(esl.Event("CUSTOM"))
  assert_nil(event:getBody())
  assert(event:addBody('hello', 'text/plain'))
  assert_equal('hello', event:getBody())
  assert_equal('text/plain', event:getHeader('Content-Type'))
  assert_nil(event:getHeader('Content-Length'))
  assert(event:addBody('world'))
  assert_equal('world', event:getBody())
  assert_nil(event:getHeader('Content-Type'))
  assert_nil(event:getHeader('Content-Length'))
end)

end

RUN()