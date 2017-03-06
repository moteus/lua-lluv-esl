local esl = {
  _NAME      = 'lluv-esl';
  _VERSION   = '0.1.0-dev';
  _COPYRIGHT = "Copyright (c) 2015-2017 Alexey Melnichuk";
  _LICENSE   = "MIT";
}

local Connection = require "lluv.esl.connection"

esl.Event      = Connection.ESLEvent
esl.Parser     = Connection.ESLParser
esl.Connection = Connection.ESLConnection
esl.Server     = require "lluv.esl.server"

return esl
