local uv         = require "lluv"
local Connection = require "lluv.esl.connection".Connection

local DummyLogger = {} do
  local lvl = {'emerg','alert','fatal','error','warning','notice','info','debug','trace'}
  for _, l in ipairs(lvl) do
    DummyLogger[l] = dummy;
    DummyLogger[l..'_dump'] = dummy;
  end

  local api = {'writer', 'formatter', 'format', 'lvl', 'set_lvl', 'set_writer', 'set_formatter', 'set_format'}
  for _, meth in ipairs(api) do
    DummyLogger[meth] = dummy
  end
end

local Server = function(options, cb)
  local host = options.host or '127.0.0.1'
  local port = options.port
  local log  = options.logger or DummyLogger

  local function on_myevents(cli, err)
    if err then
      log.error('can not subscribe: %s', tostring(err))
      return cli:close()
    end
    return cb(cli)
  end

  local function on_open(cli, err)
    if err then
      log.error('can not open connection: %s', tostring(err))
      return cli:close()
    end
    if options.myevents then
      return cli:myevents(on_myevents)
    end
    return cb(cli)
  end

  local function on_new_connection(cli)
    if options.myevents or options.open then
      return cli:open(on_open)
    end
    return cb(cli)
  end

  local function create_connection(cli)
    local cnn = Connection{
      socket = cli;
      no_execute_result = options.no_execute_result;
    }
    on_new_connection(cnn)
  end

  return uv.tcp():bind(host, port, function(server, err, _host, _port)
    if err then
      log.fatal("can not bind on %s:%s: %s", tostring(host), tostring(port), tostring(err))
      return server:close()
    end

    log.info("Bind on %s:%s", tostring(_host), tostring(_port))

    server:listen(function(server, err)
      if err then
        log.fatal("can not listen on socket: %s", tostring(host), tostring(port), tostring(err))
        return server:close()
      end

      -- create client socket in same loop as server
      local cli, err = server:accept()

      if not cli then
        log.warning('can not accept connection: %s', tostring(err))
      else
        log.notice('accepted new connection %s:%s', cli:getpeername())
      end
  
      if cli then
        create_connection(cli)
      end
    end)
  end)
end

return Server