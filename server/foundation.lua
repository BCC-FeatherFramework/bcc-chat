ChatFoundation = {}

local resourceName = GetCurrentResourceName()
local resourceVersion = GetResourceMetadata(resourceName, 'version', 0) or '0.0.0'
local health = { state = 'starting', phase = 'dependencies', since = os.time(), checks = {} }

local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = copy(child) end
    return out
end

function ChatFoundation.SetState(state, phase, failure)
    health = { state = state, phase = phase, since = os.time(), checks = health.checks, failure = failure }
end

function ChatFoundation.GetHealth() return copy(health) end

function ChatFoundation.ValidateConfig()
    local failures = {}
    local function positive(path, value, maximum)
        value = tonumber(value)
        if not value or value <= 0 or value > maximum then failures[#failures + 1] = path end
    end
    positive('MaximumMessageLength', Config.MaximumMessageLength, 2000)
    positive('MaximumLines', Config.MaximumLines, 20)
    positive('MaximumVisibleMessages', Config.MaximumVisibleMessages, 1000)
    positive('RateLimit.windowMs', Config.RateLimit and Config.RateLimit.windowMs, 600000)
    positive('RateLimit.maximum', Config.RateLimit and Config.RateLimit.maximum, 1000)
    positive('Persistence.historyPageSize', Config.Persistence and Config.Persistence.historyPageSize, 100)
    positive('Persistence.cleanupIntervalMinutes',
        Config.Persistence and Config.Persistence.cleanupIntervalMinutes, 1440)
    local channelNames = {
        'localSay',
        'localWhisper',
        'localShout',
        'roleplayMe',
        'roleplayDo',
        'globalOoc',
        'staff'
    }
    for _, name in ipairs(channelNames) do
        local channel = Config.Channels and Config.Channels[name]
        if type(channel) ~= 'table' or type(channel.enabled) ~= 'boolean' then
            failures[#failures + 1] = 'Channels.' .. name
        elseif name ~= 'globalOoc' and name ~= 'staff' and channel.enabled then
            positive('Channels.' .. name .. '.radius', channel.radius, 100)
        end
    end
    for name, level in pairs(Config.Permissions or {}) do
        level = tonumber(level)
        if not level or level < 0 or level > 999 or level % 1 ~= 0 then
            failures[#failures + 1] = 'Permissions.' .. name
        end
    end
    if type(Config.Channels) ~= 'table' then failures[#failures + 1] = 'Channels' end
    if type(Config.Features) ~= 'table' then failures[#failures + 1] = 'Features' end
    if type(Config.RolePresentation) ~= 'table' then failures[#failures + 1] = 'RolePresentation' end
    if type(Config.Persistence) ~= 'table' or type(Config.Persistence.mutes) ~= 'boolean'
        or type(Config.Persistence.messages) ~= 'boolean'
        or Config.Persistence.preferences ~= false
        or type(Config.Persistence.retentionDays) ~= 'table' then
        failures[#failures + 1] = 'Persistence'
    else
        for key, days in pairs(Config.Persistence.retentionDays) do
            days = tonumber(days)
            if type(key) ~= 'string' or not days or days < 0 or days > 3650 or days % 1 ~= 0 then
                failures[#failures + 1] = 'Persistence.retentionDays.' .. tostring(key)
            end
        end
    end
    if type(Config.Discord) ~= 'table' or type(Config.Discord.enabled) ~= 'boolean'
        or type(Config.Discord.roleTags) ~= 'boolean' or type(Config.Discord.roles) ~= 'table' then
        failures[#failures + 1] = 'Discord'
    end
    if type(Config.OpenKey) ~= 'string' or Config.OpenKey == '' then failures[#failures + 1] = 'OpenKey' end
    if #failures > 0 then
        return ChatResults.Err('invalid_configuration',
            FeatherCore.Locale.translate(0, 'errorConfigInvalid'), { fields = failures })
    end
    health.checks.configuration = { state = 'healthy' }
    return ChatResults.Ok(true)
end

function ChatFoundation.GetCapabilities()
    return ChatResults.Ok({
        resource = resourceName,
        contract = 1,
        version = resourceVersion,
        state = health.state,
        features = {
            messaging = 1,
            channels = 1,
            channelProviders = 1,
            proximity = 1,
            suggestions = 1,
            theming = 1,
            moderation = 1,
            persistence = (Config.Persistence.mutes or Config.Persistence.messages) and 1 or 0,
            persistentMutes = Config.Persistence.mutes and 1 or 0,
            messageHistory = Config.Persistence.messages and 1 or 0,
            privateMessages = 0,
            characterRoles = 1,
            discordPresentation = Config.Discord.enabled and Config.Discord.roleTags and 1 or 0,
            legacyCfxApi = 0,
            arbitraryTemplates = 0
        }
    })
end

function ChatFoundation.AwaitReady(timeoutMs)
    timeoutMs = tonumber(timeoutMs) or 10000
    if timeoutMs < 0 or timeoutMs > 60000 then
        return ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorTimeoutRange'))
    end
    local deadline = GetGameTimer() + timeoutMs
    while health.state == 'starting' and GetGameTimer() < deadline do Wait(0) end
    if health.state == 'ready' then return ChatResults.Ok(ChatFoundation.GetHealth()) end
    if health.state == 'failed' then
        return ChatResults.Err('not_ready',
            FeatherCore.Locale.translate(0, 'errorStartFailed'), health.failure)
    end
    return ChatResults.Err('timeout', FeatherCore.Locale.translate(0, 'errorReadyTimeout'))
end

exports('GetCapabilities', ChatFoundation.GetCapabilities)
exports('GetHealth', function() return ChatResults.Ok(ChatFoundation.GetHealth()) end)
exports('AwaitReady', ChatFoundation.AwaitReady)
