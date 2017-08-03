-- package.path = "..\\src\\?.lua;" .. package.path

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

local require = require 

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

local _ENV = TEST_CASE'esl.parser' if ENABLE then

local it = IT(_ENV or _M)

it('should parse xml events', function()
local str = [[Content-Length: 912
Content-Type: text/event-xml

<event>
  <headers>
    <Unique-ID>aed541be-c2c2-4f5d-94b6-3fe57ca4c8e9</Unique-ID>
    <Core-UUID>d72e096d-db60-4ceb-a241-1c98e5856acc</Core-UUID>
    <Event-Name>CHANNEL_DESTROY</Event-Name>
    <FreeSWITCH-Hostname>alexey-PC</FreeSWITCH-Hostname>
    <FreeSWITCH-Switchname>alexey-PC</FreeSWITCH-Switchname>
    <FreeSWITCH-IPv4>192.168.123.60</FreeSWITCH-IPv4>
    <FreeSWITCH-IPv6>%3A%3A1</FreeSWITCH-IPv6>
    <Event-Date-Local>2017-08-03%2014%3A40%3A13</Event-Date-Local>
    <Event-Date-GMT>Thu,%2003%20Aug%202017%2011%3A40%3A13%20GMT</Event-Date-GMT>
    <Event-Date-Timestamp>1501760413927040</Event-Date-Timestamp>
    <Event-Calling-File>switch_core_session.c</Event-Calling-File>
    <Event-Calling-Function>switch_core_session_perform_destroy</Event-Calling-Function>
    <Event-Calling-Line-Number>1474</Event-Calling-Line-Number>
    <Event-Sequence>203908</Event-Sequence>
  </headers>
</event>
]]
  local parser = esl.Parser()
  parser:append(str)

  local event, headers = assert_table(parser:next_event())

  assert_equal('CHANNEL_DESTROY', event:getType())
  assert_equal('::1', event:getHeader('FreeSWITCH-IPv6'))

  assert_table(headers)
  assert_equal('text/event-xml', headers['Content-Type'])
  assert_equal('912', headers['Content-Length'])
end)

it('should parse json events', function()
local str = [[Content-Length: 513
Content-Type: text/event-json

{"Event-Name":"CHANNEL_DESTROY","Core-UUID":"d72e096d-db60-4ceb-a241-1c98e5856acc","FreeSWITCH-Hostname":"alexey-PC","FreeSWITCH-Switchname":"alexey-PC","FreeSWITCH-IPv4":"192.168.123.60","FreeSWITCH-IPv6":"::1","Event-Date-Local":"2017-08-03 15:06:25","Event-Date-GMT":"Thu, 03 Aug 2017 12:06:25 GMT","Event-Date-Timestamp":"1501761985066904","Event-Calling-File":"switch_core_session.c","Event-Calling-Function":"switch_core_session_perform_destroy","Event-Calling-Line-Number":"1474","Event-Sequence":"206140"}
]]
  local parser = esl.Parser()
  parser:append(str)

  local event, headers = assert_table(parser:next_event())

  assert_equal('CHANNEL_DESTROY', event:getType())
  assert_equal('::1', event:getHeader('FreeSWITCH-IPv6'))

  assert_table(headers)
  assert_equal('text/event-json', headers['Content-Type'])
  assert_equal('513', headers['Content-Length'])
end)

it('should parse plain events', function()
local str = [[Content-Length: 546
Content-Type: text/event-plain

Event-Name: CHANNEL_DESTROY
Unique-ID: e4326ec3-1d9a-44fd-917b-c5dded3c1b29
Core-UUID: d72e096d-db60-4ceb-a241-1c98e5856acc
FreeSWITCH-Hostname: alexey-PC
FreeSWITCH-Switchname: alexey-PC
FreeSWITCH-IPv4: 192.168.123.60
FreeSWITCH-IPv6: %3A%3A1
Event-Date-Local: 2017-08-03%2015%3A18%3A32
Event-Date-GMT: Thu,%2003%20Aug%202017%2012%3A18%3A32%20GMT
Event-Date-Timestamp: 1501762712687522
Event-Calling-File: switch_core_session.c
Event-Calling-Function: switch_core_session_perform_destroy
Event-Calling-Line-Number: 1474
Event-Sequence: 207341

]]
  local parser = esl.Parser()
  parser:append(str)

  local event, headers = assert_table(parser:next_event())

  assert_equal('CHANNEL_DESTROY', event:getType())
  assert_equal('::1', event:getHeader('FreeSWITCH-IPv6'))

  assert_table(headers)
  assert_equal('text/event-plain', headers['Content-Type'])
  assert_equal('546', headers['Content-Length'])
end)

end


RUN()

