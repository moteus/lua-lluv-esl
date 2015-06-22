package.path = "../src/?.lua;" .. package.path

local utils     = require "utils"
local TEST_CASE = require "lunit".TEST_CASE
local em        = require "lluv.esl.EventEmitter"

local pcall, error, type, table, ipairs, print = pcall, error, type, table, ipairs, print
local IT, RUN = utils.IT, utils.RUN

local counter = function()
  local counter = 0
  return function(inc)
    if inc then counter = counter + inc
    else counter = counter + 1 end
    return counter
  end
end

local ENABLE = true

local _ENV = TEST_CASE'EventEmitter basic' if ENABLE then
local it = IT(_ENV or _M)

local emitter

function setup()
  emitter = em.EventEmitter.new()
end

it('should call only once', function()
  local called = counter()
  emitter:once('A', function()
    assert_equal(1, called())
  end)
  emitter:emit('A')
  assert_equal(1, called(0))
  emitter:emit('A')
  assert_equal(1, called(0))
end)

it('should call many time', function()
  local called = counter()
  local i = 1
  emitter:on('A', function()
    assert_equal(i, called())
  end)
  for j = 1, 5 do
    emitter:emit('A')
    assert_equal(i, called(0))
    i = i + 1
  end
end)

it('should remove many', function()
  local called = counter()
  local i = 1
  local handler = function()
    assert_equal(i, called())
  end

  emitter:on('A', handler)
  emitter:emit('A')
  assert_equal(1, called(0))

  emitter:off('A', handler)
  emitter:emit('A')
  assert_equal(1, called(0))
end)

it('should remove once', function()
  local called = counter()
  local i = 1
  local handler = function()
    assert_equal(i, called())
  end

  emitter:once('A', handler)
  emitter:off('A', handler)
  emitter:emit('A')
  assert_equal(0, called(0))
end)

it('should remove all', function()
  local called = counter()

  emitter:once('A', function() called() end)
  emitter:on('A', function() called() end)
  emitter:off('A', handler)
  emitter:emit('A')
  assert_equal(0, called(0))
end)

it('should call multimple subscrabers', function()
  local called1 = counter()
  local called2 = counter()

  emitter:once('A', function() called1() end)
  emitter:on('A', function() called2() end)

  emitter:emit('A')
  assert_equal(1, called1(0))
  assert_equal(1, called2(0))

  emitter:emit('A')
  assert_equal(1, called1(0))
  assert_equal(2, called2(0))
end)

end

local _ENV = TEST_CASE'EventEmitter tree' if ENABLE then
local it = IT(_ENV or _M)

local emitter

function setup()
  emitter = em.TreeEventEmitter.new()
end

it('should calls handle only once', function()
  local called = counter()
  local handler = function() called() end
  emitter:on('A', handler)
  emitter:on('A', handler)
  emitter:on('A::*', handler)
  emitter:on('A::*', handler)
  emitter:emit('A')
  assert_equal(2, called(0))
end)

it('should match', function()
  local called1 = counter()
  local called2 = counter()
  emitter:on('A', function() called1() end)
  emitter:on('A::*', function() called2() end)

  emitter:emit('A')
  assert_equal(1, called1(0))
  assert_equal(1, called2(0))

  emitter:emit('A::B')
  assert_equal(1, called1(0))
  assert_equal(2, called2(0))
end)

end


RUN()
