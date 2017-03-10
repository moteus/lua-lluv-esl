-- Porting `call_flow_subscribe.lua` from FusionPBX
local uv   = require "lluv"
local ut   = require "lluv.utils"
local esl  = require "lluv.esl"
local pg   = require "lluv.pg"
local log  = require "log".new(
  require "log.writer.stderr".new(),
  require "log.formatter.mix".new()
)

local function E(e) return 'esl::event::' .. e .. '::**' end

local database = pg.new{
  database  = 'fusionpbx',
  user      = 'fusionpbx',
  -- password  = '',
  reconnect = 10,
}

local freeswitch = esl.Connection{
  reconnect = 10, no_execute_result = true, no_bgapi = true;
  subscribe = {
    'PRESENCE_PROBE',
  };
  filter = {
    proto = 'flow',
  };
}

freeswitch:open()

database:connect()

local function turn_lamp(on, user, uuid, cb)
  local userid, domain, proto = ut.split_first(user, "@", true)
  proto, userid = ut.split_first(userid, "+", true)
  if userid then
    user = userid  .. "@" .. domain
  else
    proto = "sip"
  end

  local event = esl.Event("PRESENCE_IN")
  event:addHeader("proto", proto);
  event:addHeader("event_type", "presence");
  event:addHeader("alt_event_type", "dialog");
  event:addHeader("Presence-Call-Direction", "outbound");
  event:addHeader("from", user);
  event:addHeader("login", user);
  event:addHeader("unique-id", uuid);
  event:addHeader("status", "Active (1 waiting)");
  if on then
    event:addHeader("answer-state", "confirmed");
    event:addHeader("rpid", "unknown");
    event:addHeader("event_count", "1");
  else
    event:addHeader("answer-state", "terminated");
  end

  freeswitch:sendEvent(event, function(self, err)
    if err then
      log.error('can not send event: %s', tostring(err))
    end
    if cb then cb() end
  end)
end

local function find_call_flow(user, cb)
  local ext, domain_name = ut.split_first(user, '@', true)
  if not domain_name then return cb() end

  local sql = [[select t1.call_flow_uuid, t1.call_flow_status
    from v_call_flows t1 inner join v_domains t2 on t1.domain_uuid = t2.domain_uuid
    where t2.domain_name = $1 and t1.call_flow_feature_code = $2
  ]]

  database:query(sql, {domain_name, ext}, function(self, err, row)
    if err then
      log.error('can not execute query: %s', tostring(err))
      return cb()
    end
    row = row[1]
    if not row then return cb() end
    return cb(row[1], row[2])
  end)
end

freeswitch:on(E'PRESENCE_PROBE', function(self, eventName, event)
  --handle only blf with `flow+` prefix
  if event:getHeader('proto') ~= 'flow' then return end

  local from, to = event:getHeader('from'), event:getHeader('to')
  local expires = tonumber(event:getHeader('expires'))
  if expires and expires > 0 then
    find_call_flow(to, function(call_flow_uuid, call_flow_status)
      if call_flow_uuid then
        log.notice("Find call flow: %s staus: %s", to, tostring(call_flow_status))
        turn_lamp(call_flow_status == "false", to, call_flow_uuid)
      else
        log.warningf("Can not find call flow: %s", to)
      end
    end)
  else
    log.notice("%s UNSUBSCRIBE from %s", from, to)
  end
end)

-- connection monitoring

freeswitch:on('esl::reconnect', function()
  log.warning("Connected to FreeSWITCH")
end)

freeswitch:on('esl::disconnect', function(self, _, err)
  log.warning('Disconnected from FreeSWITCH  - %s', err and tostring(err) or 'NO ERROR')
end)

database:on('reconnect', function()
  log.warning("Connected to database")
end)

database:on('disconnect', function(self, _, err)
  log.warning('Disconnected from database  - %s', err and tostring(err) or 'NO ERROR')
end)

log.notice("start")

uv.run()

log.notice("stop")