local uv           = require "lluv"
local ut           = require "lluv.utils"
local esl          = require "lluv.esl"
local ESLUtils     = require "lluv.esl.utils"
local EventEmitter = require "EventEmitter".EventEmitter

local cnn = esl.Connection('127.0.0.1', 8021, 'ClueCon')

local dial_string = {
  options = {
    ignore_early_media           = true;
    origination_caller_id_name   = 'lluv-esl';
    origination_caller_id_number = '100';
  };

  strings = { -- Enterprise dial string
    {  -- Group call 1
      options = {};
      sequence = true;
      {'user/101@pbx.office.local'};
    };

    { -- Group call 2
      options = {};
      sequence = true;
      {originate_delay_start = 5000; 'user/102@pbx.office.local'};
    };
  }
};

local Originate = ut.class(EventEmitter) do

function Originate:__init(cnn)
  self.__base.__init(self)
  self._cnn = cnn

  return self
end

function Originate:dial(dial_string, app)
  local cnn = self._cnn

  local session_uuid = ESLUtils.uuid()
  dial_string.options.x_session_uuid = session_uuid

  local dial_string = ESLUtils.dial_string.create(dial_string):build()
  local session_filter = {variable_x_session_uuid=session_uuid}

  local this = self
  local channels, state = {}, 'originate'
  local cleanup

  local on_channel_create = function(self, _, event)
    if session_uuid ~= event:getHeader('variable_x_session_uuid') then return end
    local uuid = event:getHeader('Unique-ID')
    channels[uuid] = true

    this:emit('create', event)
  end

  local on_channel_destroy = function(self, _, event)
    if session_uuid ~= event:getHeader('variable_x_session_uuid') then return end

    local uuid = event:getHeader('Unique-ID')
    channels[uuid] = nil

    this:emit('destroy', event)

    if state == 'originate' then return end

    if not next(channels) then
      cleanup()
      this:emit('end', event)
    end
  end

  local on_channel_answer = function(self, _, event)
    if session_uuid ~= event:getHeader('variable_x_session_uuid') then return end

    state = 'answer'

    this:emit('answer', event)
  end

  local on_channel_execute = function(self, _, event)
    if session_uuid ~= event:getHeader('variable_x_session_uuid') then return end

    this:emit('execute', event)
  end

  local on_channel_execute_complite = function(self, _, event)
    if session_uuid ~= event:getHeader('variable_x_session_uuid') then return end

    this:emit('execute_complete', event)
  end

  local on_channel_dtmf = function(self, _, event)
    if session_uuid ~= event:getHeader('variable_x_session_uuid') then return end

    this:emit('dtmf', event)
  end

  local events = {"CHANNEL_CREATE", "CHANNEL_DESTROY", "CHANNEL_ANSWER", "CHANNEL_EXECUTE", "DTMF"}

  cleanup = function()
    -- !todo unsubscribe from `events`

    cnn:filterDelete(session_filter);

    cnn:off('esl::event::CHANNEL_EXECUTE::*',           on_channel_execute          )
    cnn:off('esl::event::CHANNEL_EXECUTE_COMPLETE::*',  on_channel_execute_complite )
    cnn:off('esl::event::CHANNEL_CREATE::*',            on_channel_create           )
    cnn:off('esl::event::CHANNEL_DESTROY::*',           on_channel_destroy          )
    cnn:off('esl::event::CHANNEL_ANSWER::*',            on_channel_answer           )
    cnn:off('esl::event::DTMF::*',                      on_channel_dtmf             )
  end

  cnn:filter(session_filter);
  cnn:subscribe(events)

  -- cnn:on('esl::event::**',            on_channel_create           )

  cnn:on('esl::event::CHANNEL_CREATE::*',            on_channel_create           )
  cnn:on('esl::event::CHANNEL_DESTROY::*',           on_channel_destroy          )
  cnn:on('esl::event::CHANNEL_ANSWER::*',            on_channel_answer           )
  cnn:on('esl::event::CHANNEL_EXECUTE::*',           on_channel_execute          )
  cnn:on('esl::event::CHANNEL_EXECUTE_COMPLETE::*',  on_channel_execute_complite )
  cnn:on('esl::event::DTMF::*',                      on_channel_dtmf             )

  local cmd = string.format("originate %s %s", dial_string, app or '&park()')

  cnn:bgapi(cmd, function(self, err, event, headers)
    if state == 'originate' then state = 'ringing' end

    if not next(channels) then
      cleanup()
      this:emit('end', event)
    end
  end)
end

end

cnn:open(function(self, err)
  if err then
    print("Error:", err)
    return self:close()
  end

  print("Dial String:", ESLUtils.dial_string.create(dial_string):build())

  local originate = Originate.new(self)

  -- originate:onAny(function(self, eventName, event) print(eventName) end)

  originate:on('create', function(self, eventName, event)
    print('New channel:', event:getHeader('Channel-Name'))
  end)

  originate:on('destroy', function(self, eventName, event)
    print('Close channel:', event:getHeader('Channel-Name'), event:getHeader('Hangup-Cause'))
  end)

  originate:on('answer', function(self, eventName, event)
    print('Answer:', event:getHeader('Channel-Name'))
  end)

  originate:on('dtmf', function(self, eventName, event)
    local digit    = ev:getHeader("DTMF-Digit");
    local duration = ev:getHeader("DTMF-Duration");
    print('Dtmf:', event:getHeader('Channel-Name'), digit, duration)
  end)

  originate:on('execute', function(self, eventName, event)
    print('Execute', event:getHeader('Channel-Name'), event:getHeader('Application'))
  end)

  originate:on('execute_complete', function(self, eventName, event)
    print('Complete', event:getHeader('Channel-Name'), event:getHeader('Application'), event:getHeader('Application-Response'))
  end)

  originate:on('end', function(self, eventName, event)
    print('Hangup:', event:getHeader('Channel-Name') or event:getBody(), event:getHeader('Hangup-Cause'))
    cnn:close()
  end)

  originate:dial(dial_string, '&echo()')
end)

uv.run()
