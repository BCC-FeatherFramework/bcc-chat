local sequence, rateWindows, resourceRateWindows, repeats, idempotency = 0, {}, {}, {}, {}
local commandsInstalled, rolesProviderInstalled, cleanupStarted = false, false, false

local function isCallable(value)
    return type(value) == 'function'
        or (type(value) == 'table' and type(rawget(value, '__cfx_functionReference')) == 'string')
end

local function cleanText(value, maximum)
    if type(value) ~= 'string' or #value == 0 or #value > maximum * 4 then return nil end
    if not utf8.len(value) then return nil end
    value = value:gsub('[\0-\8\11\12\14-\31\127]', ''):match('^%s*(.-)%s*$')
    if value == '' or #value > maximum * 4 then return nil end
    -- BCC's renderer understands caret color markup. Player text is kept plain;
    -- channel/theme colors remain trusted presentation metadata.
    value = value:gsub('%^#%x%x%x%x%x%x', ''):gsub('%^[0-9_*~=r/]', ''):gsub('~[a-z]~', '')
    value = value:match('^%s*(.-)%s*$')
    if value == '' then return nil end
    local characters = utf8.len(value)
    if not characters or characters > maximum then return nil end
    local _, lines = value:gsub('\n', '\n')
    if lines + 1 > Config.MaximumLines then return nil end
    local safe = pcall(function()
        for _, codepoint in utf8.codes(value) do
            if (codepoint >= 0x202A and codepoint <= 0x202E) or (codepoint >= 0x2066 and codepoint <= 0x2069) then
                error('bidirectional control')
            end
        end
    end)
    if not safe then return nil end
    return value
end

local function uuid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return template:gsub('[xy]', function(c)
        local v = c == 'x' and math.random(0, 15) or math.random(8, 11)
        return ('%x'):format(v)
    end)
end

local function actorFor(source, context)
    if not context or not context.characterId or not context.sessionId then
        return nil, ChatResults.Err(
            'character_required',
            FeatherCore.Locale.translate(source, 'errorCharacterRequired')
        )
    end
    if not exports['feather-core']:IsSessionCurrent(source, context.sessionId, context.characterId) then
        return nil, ChatResults.Err('session_stale', FeatherCore.Locale.translate(source, 'errorSessionStale'))
    end
    local resolved = exports['feather-core']:GetProvider('character-profile', nil, 1)
    if type(resolved) ~= 'table' or not resolved.ok then
        return nil,
            ChatResults.Err('identity_unavailable', FeatherCore.Locale.translate(source, 'errorIdentityUnavailable'))
    end
    local implementation = resolved.value and resolved.value.implementation
    if type(implementation) ~= 'table' or not isCallable(implementation.GetProfile) then
        return nil, ChatResults.Err(
            'identity_unavailable',
            FeatherCore.Locale.translate(source, 'errorIdentityInvalid')
        )
    end
    local called, profile = pcall(implementation.GetProfile, context.characterId)
    if not called or type(profile) ~= 'table' or not profile.ok then
        return nil,
            ChatResults.Err('identity_unavailable', FeatherCore.Locale.translate(source, 'errorIdentityUnavailable'))
    end
    local value = profile.value or {}
    local first = value.firstName or value.firstname or value.first_name or ''
    local last = value.lastName or value.lastname or value.last_name or ''
    local displayName = (tostring(first) .. ' ' .. tostring(last)):match('^%s*(.-)%s*$')
    if displayName == '' then displayName = FeatherCore.Locale.translate(source, 'authorUnknown') end
    return {
        source = source,
        accountId = context.accountId,
        characterId = context.characterId,
        sessionId = context.sessionId,
        displayName = displayName
    }
end

local function limited(actor)
    local now, key = GetGameTimer(), actor.characterId
    local window = rateWindows[key]
    if not window or now - window.started > Config.RateLimit.windowMs then
        rateWindows[key] = { started = now, count = 1 }
        return false
    end
    window.count = window.count + 1
    return window.count > Config.RateLimit.maximum
end

local function resourceLimited(resource)
    local now = GetGameTimer()
    local window = resourceRateWindows[resource]
    if not window or now - window.started > Config.ResourceRateLimit.windowMs then
        resourceRateWindows[resource] = { started = now, count = 1 }
        return false
    end
    window.count = window.count + 1
    return window.count > Config.ResourceRateLimit.maximum
end

local function repeated(actor, channelKey, text)
    local key, now = actor.characterId .. ':' .. channelKey, GetGameTimer()
    local record = repeats[key]
    repeats[key] = {
        text = text,
        at = now,
        count = record and record.text == text and now - record.at < 15000 and
            record.count + 1 or 1
    }
    return repeats[key].count > 2
end

local function canReceive(channel, target)
    local session = exports['feather-core']:GetSessionContext(target)
    if type(session) ~= 'table' or not session.ok then return false end
    local targetActor = {
        source = target,
        accountId = session.value.accountId,
        characterId = session.value.characterId,
        sessionId = session.value.sessionId
    }
    return ChatChannels.CheckAccess(channel, targetActor, 'receive').ok
end

local function recipients(channel, actor)
    local routing = channel.routing or {}
    if routing.type == 'explicit' then
        -- Explicit/targeted channels have no generic recipient set: only sendResourceMessage's
        -- per-message `targets` list may deliver to them. Fail closed instead of broadcasting.
        return {}
    end
    if routing.type == 'proximity' then
        local senderPed = GetPlayerPed(actor.source)
        if not senderPed or senderPed == 0 then return {} end
        local origin, bucket, output = GetEntityCoords(senderPed), GetPlayerRoutingBucket(actor.source), {}
        for _, id in ipairs(GetPlayers()) do
            local target, ped = tonumber(id), GetPlayerPed(id)
            if ped and ped ~= 0 and GetPlayerRoutingBucket(target) == bucket then
                local point = GetEntityCoords(ped)
                local dx, dy, dz = origin.x - point.x, origin.y - point.y, origin.z - point.z
                if math.sqrt(dx * dx + dy * dy + dz * dz) <= tonumber(routing.radius)
                    and canReceive(channel, target) then
                    output[#output + 1] = target
                end
            end
        end
        return output
    end
    local output = {}
    for _, id in ipairs(GetPlayers()) do
        local target = tonumber(id)
        if canReceive(channel, target) then
            output[#output + 1] = target
        end
    end
    return output
end

local function submit(payload, source, context)
    local actor, failure = actorFor(source, context)
    if not actor then return failure end
    if limited(actor) then
        return ChatResults.Err('rate_limited',
            FeatherCore.Locale.translate(source, 'errorRateLimited'))
    end
    if type(payload) ~= 'table' or type(payload.channelKey) ~= 'string' then
        return ChatResults.Err('invalid_input',
            FeatherCore.Locale.translate(source, 'errorChannelInput'))
    end
    local channel = ChatChannels.Get(payload.channelKey)
    if not channel then
        return ChatResults.Err('channel_unavailable',
            FeatherCore.Locale.translate(source, 'errorChannelUnavailable'))
    end
    local text = cleanText(payload.text, channel.input.maximumLength)
    if not text then
        return ChatResults.Err('invalid_content',
            FeatherCore.Locale.translate(source, 'errorInvalidContent'))
    end
    local submissionId = type(payload.submissionId) == 'string' and payload.submissionId:sub(1, 64) or nil
    local cacheKey = submissionId and (actor.sessionId .. ':' .. submissionId)
    if cacheKey and idempotency[cacheKey] then return ChatResults.Ok(idempotency[cacheKey], { replayed = true }) end
    local access = ChatChannels.CheckAccess(channel, actor, 'send')
    if not access.ok then return access end
    local mute = ChatModeration.Check(actor, channel.channelKey)
    if not mute.ok then return mute end
    if repeated(actor, channel.channelKey, text) then
        return ChatResults.Err('rate_limited',
            FeatherCore.Locale.translate(source, 'errorRepeatLimited'))
    end
    local moderated = ChatModeration.Evaluate({ actor = actor, channelKey = channel.channelKey, text = text })
    if not moderated.ok then return moderated end
    text = cleanText(moderated.value.text, channel.input.maximumLength)
    if not text then
        return ChatResults.Err('invalid_content',
            FeatherCore.Locale.translate(source, 'errorModeratedContent'))
    end
    if not exports['feather-core']:IsSessionCurrent(source, actor.sessionId, actor.characterId) then
        return ChatResults.Err('session_stale', FeatherCore.Locale.translate(source, 'errorSessionChanged'))
    end
    local rolePresentation = ChatRoles.GetPresentation(source)
    if not rolePresentation.ok then return rolePresentation end
    local discordPresentation = ChatDiscord.GetPresentation(source)
    local accessBadge = access.value.badge
        or (type(access.value.display) == 'table' and access.value.display.badge or nil)
    local trustedPresentation = rolePresentation.value.visible and rolePresentation.value
        or (discordPresentation.ok and discordPresentation.value.visible and discordPresentation.value or nil)
    sequence = sequence + 1
    local message = {
        messageId = uuid(),
        channelKey = channel.channelKey,
        kind = channel.routing.kind or 'player',
        author = {
            characterId = actor.characterId,
            displayName = actor.displayName,
            badge = trustedPresentation and trustedPresentation.label or accessBadge,
            badgeKey = trustedPresentation and trustedPresentation.labelKey or nil,
            badgeColor = trustedPresentation and trustedPresentation.color or nil
        },
        body = { text = text, format = 'plain' },
        presentation = channel.presentation,
        createdAt = os.time(),
        sequence = sequence
    }
    local persisted = ChatPersistence.SaveMessage(channel, message)
    if not persisted.ok then return persisted end
    for _, target in ipairs(recipients(channel, actor)) do
        TriggerClientEvent('bcc-chat:message', target, message)
    end
    local accepted = { messageId = message.messageId, submissionId = submissionId, sequence = sequence }
    if cacheKey then
        idempotency[cacheKey] = accepted
        SetTimeout(Config.IdempotencyTtlMs, function()
            idempotency[cacheKey] = nil
        end)
    end
    TriggerEvent('chat.message.accepted.v1', {
        messageId = message.messageId,
        channelKey = channel.channelKey,
        characterId = actor.characterId,
        sequence = sequence
    })
    return ChatResults.Ok(accepted)
end

local function sendResourceMessage(request)
    if type(request) ~= 'table' or type(request.channelKey) ~= 'string' or type(request.body) ~= 'table' then
        return ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorMessageInput'))
    end
    local text = cleanText(request.body.text, Config.MaximumMessageLength)
    if not text then
        return ChatResults.Err(
            'invalid_content',
            FeatherCore.Locale.translate(0, 'errorMessageInvalid')
        )
    end
    local channel = ChatChannels.Get(request.channelKey)
    if not channel then
        return ChatResults.Err('channel_unavailable',
            FeatherCore.Locale.translate(0, 'errorChannelUnavailable'))
    end
    local invoking = GetInvokingResource()
    invoking = type(invoking) == 'string' and invoking or GetCurrentResourceName()
    if resourceLimited(invoking) then
        return ChatResults.Err('rate_limited',
            FeatherCore.Locale.translate(0, 'errorResourceRateLimited'))
    end
    if channel.channelKey ~= 'system' and channel.ownerResource ~= invoking then
        return ChatResults.Err('forbidden', FeatherCore.Locale.translate(0, 'errorChannelOwner'))
    end
    sequence = sequence + 1
    local message = {
        messageId = uuid(),
        channelKey = channel.channelKey,
        kind = 'system',
        author = {
            displayName = request.authorLabel and tostring(request.authorLabel):sub(1, 64) or nil,
            labelKey = request.authorLabel and nil or (request.authorLabelKey or 'authorSystem')
        },
        body = { text = text, format = 'plain' },
        presentation = channel.presentation,
        createdAt = os.time(),
        sequence = sequence
    }
    local targets = request.targets
    if type(targets) ~= 'table' or #targets == 0 then targets = GetPlayers() end
    if #targets > Config.MaximumResourceTargets then
        return ChatResults.Err('limit_exceeded',
            FeatherCore.Locale.translate(0, 'errorTooManyTargets'))
    end
    local persisted = ChatPersistence.SaveMessage(channel, message)
    if not persisted.ok then return persisted end
    local delivered = 0
    for _, target in ipairs(targets) do
        target = tonumber(target)
        local session = target and exports['feather-core']:GetSessionContext(target) or nil
        if type(session) == 'table' and session.ok then
            TriggerClientEvent('bcc-chat:message', target, message)
            delivered = delivered + 1
        end
    end
    return ChatResults.Ok({ messageId = message.messageId, sequence = sequence, delivered = delivered })
end

local function commandSubmit(source, channelKey, args)
    if source <= 0 then return end
    local session = exports['feather-core']:GetSessionContext(source)
    if type(session) ~= 'table' or not session.ok then return end
    local result = submit({
        channelKey = channelKey,
        text = table.concat(args, ' '),
        submissionId = ('command:%s:%s'):format(GetGameTimer(), math.random(100000, 999999))
    }, source, session.value)
    if not result.ok then TriggerClientEvent('bcc-chat:feedback', source, result.message) end
end

local function install()
    local configuration = ChatFoundation.ValidateConfig()
    if not configuration.ok then
        ChatFoundation.SetState('failed', 'configuration', configuration)
        return
    end
    if not ChatPersistence.IsReady() then
        local persistence = ChatPersistence.Initialize()
        if not persistence.ok then
            ChatFoundation.SetState('failed', 'database_migrations', persistence)
            return
        end
        sequence = math.max(sequence, tonumber(persistence.value.maxSequence) or 0)
        local loadedMutes = ChatModeration.LoadPersistent()
        if not loadedMutes.ok then
            ChatFoundation.SetState('failed', 'mute_recovery', loadedMutes)
            return
        end
    end
    local ready = exports['feather-core']:AwaitReady(30000)
    if type(ready) ~= 'table' or not ready.ok then
        ChatFoundation.SetState('failed', 'core_unavailable', ready)
        return
    end
    local providerDeadline, characterProvider = GetGameTimer() + 30000, nil
    repeat
        characterProvider = exports['feather-core']:GetProvider('character-profile', nil, 1)
        if type(characterProvider) == 'table' and characterProvider.ok then break end
        Wait(250)
    until GetGameTimer() >= providerDeadline
    if type(characterProvider) ~= 'table' or not characterProvider.ok then
        ChatFoundation.SetState('failed', 'character_unavailable', characterProvider)
        return
    end
    local rolesReady = ChatRoles.AwaitReady(30000)
    if not rolesReady.ok then
        ChatFoundation.SetState('failed', 'roles_unavailable', rolesReady)
        return
    end
    if not rolesProviderInstalled then
        local provider = ChatChannels.RegisterAccessProvider('bcc-chat.roles.staff', {
            CheckAccess = ChatRoles.CheckChannelAccess
        })
        if not provider.ok then
            ChatFoundation.SetState('failed', 'role_provider_registration', provider)
            return
        end
        rolesProviderInstalled = true
    end
    local subscription = ChatRoles.Subscribe()
    if not subscription.ok then
        ChatFoundation.SetState('failed', 'role_subscription', subscription)
        return
    end

    local builtins = {{
        channelKey = 'system',
        label = FeatherCore.Locale.translate(0, 'channelSystem'),
        labelKey = 'channelSystem',
        visibility = 'system',
        presentation = { variant = 'system' },
        routing = { type = 'explicit' }
    }}

    local function addEnabled(config, definition)
        if type(config) == 'table' and config.enabled == true then
            builtins[#builtins + 1] = definition
        end
    end

    addEnabled(Config.Channels.localSay,
        {
            channelKey = 'local.say',
            label = FeatherCore.Locale.translate(0, 'channelSay'),
            labelKey = 'channelSay',
            visibility = 'public',
            presentation = { variant = 'localSpeech' },
            routing = { type = 'proximity', radius = Config.Channels.localSay.radius }
        })
    addEnabled(Config.Channels.localWhisper,
        {
            channelKey = 'local.whisper',
            label = FeatherCore.Locale.translate(0, 'channelWhisper'),
            labelKey = 'channelWhisper',
            visibility = 'public',
            presentation = { variant = 'localSpeech' },
            routing = { type = 'proximity', radius = Config.Channels.localWhisper.radius }
        })
    addEnabled(Config.Channels.localShout,
        {
            channelKey = 'local.shout',
            label = FeatherCore.Locale.translate(0, 'channelShout'),
            labelKey = 'channelShout',
            visibility = 'public',
            presentation = { variant = 'localSpeech' },
            routing = { type = 'proximity', radius = Config.Channels.localShout.radius }
        })
    addEnabled(Config.Channels.roleplayMe,
        {
            channelKey = 'roleplay.me',
            label = FeatherCore.Locale.translate(0, 'channelAction'),
            labelKey = 'channelAction',
            visibility = 'public',
            presentation = { variant = 'roleplay' },
            routing = { type = 'proximity', radius = Config.Channels.roleplayMe.radius, kind = 'action' }
        })
    addEnabled(Config.Channels.roleplayDo,
        {
            channelKey = 'roleplay.do',
            label = FeatherCore.Locale.translate(0, 'channelScene'),
            labelKey = 'channelScene',
            visibility = 'public',
            presentation = { variant = 'roleplay' },
            routing = { type = 'proximity', radius = Config.Channels.roleplayDo.radius, kind = 'scene' }
        })
    addEnabled(Config.Channels.globalOoc,
        {
            channelKey = 'ooc.global',
            label = FeatherCore.Locale.translate(0, 'channelOoc'),
            labelKey = 'channelOoc',
            visibility = 'public',
            presentation = { variant = 'ooc' },
            routing = { type = 'global' }
        })
    addEnabled(Config.Channels.staff,
        {
            channelKey = 'staff',
            label = FeatherCore.Locale.translate(0, 'channelStaff'),
            labelKey = 'channelStaff',
            visibility = 'eligible',
            accessProvider = 'bcc-chat.roles.staff',
            presentation = { variant = 'staff' },
            routing = { type = 'global' }
        })
    for _, definition in ipairs(builtins) do
        if not ChatChannels.Get(definition.channelKey) then
            local result = ChatChannels.Register(definition)
            if not result.ok then
                ChatFoundation.SetState('failed', 'channel_registration', result)
                return
            end
        end
    end
    local routes = {
        exports['feather-core']:RegisterRpc('chat.channel.list.v1', function(_, source, context)
            local actor, err = actorFor(source, context)
            return actor and ChatChannels.ListFor(actor) or err
        end, {
            contract = 1,
            direction = 'client_to_server',
            requireCharacter = true,
            windowMs = 2000,
            maxCalls = 5,
            maxPayloadBytes = 64,
            maxDepth = 2,
            maxNodes = 4,
            validatePayload = function(p) return type(p) == 'table' and next(p) == nil end
        }),
        exports['feather-core']:RegisterRpc('chat.message.submit.v1', function(payload, source, context)
            local result = submit(payload, source, context)
            if not result.ok then
                TriggerEvent('chat.message.rejected.v1', {
                    source = source,
                    characterId = context and context.characterId or nil,
                    channelKey = type(payload) == 'table' and payload.channelKey or nil,
                    code = result.code
                })
            end
            return result
        end, {
            contract = 1,
            direction = 'client_to_server',
            requireCharacter = true,
            windowMs = 10000,
            maxCalls = 12,
            maxPayloadBytes = 2400,
            maxDepth = 3,
            maxNodes = 12
        })
    }
    if Config.Persistence.messages then
        routes[#routes + 1] = exports['feather-core']:RegisterRpc('chat.history.list.v1',
            function(payload, source, context)
                local actor, actorFailure = actorFor(source, context)
                if not actor then return actorFailure end
                if type(payload) ~= 'table' or type(payload.channelKey) ~= 'string' then
                    return ChatResults.Err('invalid_input',
                        FeatherCore.Locale.translate(source, 'errorHistoryInput'))
                end
                local channel = ChatChannels.Get(payload.channelKey)
                if not channel then
                    return ChatResults.Err('channel_unavailable',
                        FeatherCore.Locale.translate(source, 'errorChannelUnavailable'))
                end
                local access = ChatChannels.CheckAccess(channel, actor, 'receive')
                if not access.ok then return access end
                return ChatPersistence.ListMessages(channel, payload.beforeSequence, payload.limit)
            end, {
                contract = 1,
                direction = 'client_to_server',
                requireCharacter = true,
                windowMs = 5000,
                maxCalls = 6,
                maxPayloadBytes = 256,
                maxDepth = 2,
                maxNodes = 8,
                validatePayload = function(payload)
                    local before = type(payload) == 'table' and payload.beforeSequence or nil
                    local limit = type(payload) == 'table' and payload.limit or nil
                    return type(payload) == 'table'
                        and type(payload.channelKey) == 'string'
                        and #payload.channelKey <= 96
                        and (before == nil or (type(before) == 'number' and before == before
                            and before >= 1 and before <= 9007199254740991 and before % 1 == 0))
                        and (limit == nil or (type(limit) == 'number' and limit == limit
                            and limit >= 1 and limit <= Config.Persistence.historyPageSize
                            and limit % 1 == 0))
                end
            })
    end
    for _, result in ipairs(routes) do
        if type(result) ~= 'table' or not result.ok then
            ChatFoundation.SetState('failed', 'rpc_registration', result)
            return
        end
    end
    if not commandsInstalled then
        local aliases = {}
        if Config.Channels.localSay.enabled then aliases.say = 'local.say' end
        if Config.Channels.roleplayMe.enabled then aliases.me = 'roleplay.me' end
        if Config.Channels.roleplayDo.enabled then aliases['do'] = 'roleplay.do' end
        if Config.Channels.localWhisper.enabled then aliases.whisper = 'local.whisper' end
        if Config.Channels.localShout.enabled then aliases.shout = 'local.shout' end
        if Config.Channels.globalOoc.enabled then aliases.ooc = 'ooc.global' end
        if Config.Channels.staff.enabled then aliases.staff = 'staff' end
        for command, channelKey in pairs(aliases) do
            RegisterCommand(command, function(source, args)
                commandSubmit(source, channelKey, args)
            end, false)
            ChatChannels.RegisterSuggestion({
                key = 'command.' .. command,
                trigger = '/' .. command,
                description = FeatherCore.Locale.translate(0, 'commandSendTo', channelKey),
                descriptionKey = 'commandSendTo',
                descriptionArgs = { channelKey },
                accessProvider = channelKey == 'staff' and 'bcc-chat.roles.staff' or nil,
                parameters = {{
                    name = FeatherCore.Locale.translate(0, 'commandMessage'),
                    nameKey = 'commandMessage',
                    required = true
                }}
            })
        end
        commandsInstalled = true
    end
    if not cleanupStarted then
        cleanupStarted = true
        CreateThread(function()
            while true do
                Wait(Config.Persistence.cleanupIntervalMinutes * 60000)
                ChatPersistence.Cleanup()
                ChatModeration.PruneExpired()
            end
        end)
    end
    ChatFoundation.SetState('ready', 'ready')
end

exports('SendMessage', sendResourceMessage)
CreateThread(install)

AddEventHandler('onResourceStop', function(resource)
    if resource == 'feather-core' or resource == 'feather-character' or resource == 'feather-roles' then
        ChatFoundation.SetState('starting', resource .. '_restarting')
        TriggerClientEvent('bcc-chat:reset-session', -1)
    end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == 'feather-core' then
        CreateThread(function()
            Wait(500)
            install()
        end)
    elseif resource == 'feather-character' or resource == 'feather-roles' then
        CreateThread(function()
            local deadline = GetGameTimer() + 30000
            while GetGameTimer() < deadline do
                local character = exports['feather-core']:GetProvider('character-profile', nil, 1)
                local roles = ChatRoles.AwaitReady(250)
                if type(character) == 'table' and character.ok and roles.ok then
                    local subscription = ChatRoles.Subscribe()
                    if subscription.ok then
                        ChatFoundation.SetState('ready', 'ready')
                        return
                    end
                end
                Wait(250)
            end
            ChatFoundation.SetState('failed', resource .. '_unavailable')
        end)
    end
end)

AddEventHandler('core.session.left.v1', function(event)
    local source = type(event) == 'table' and tonumber(event.source) or nil
    local characterId = type(event) == 'table' and event.characterId or nil
    if characterId then
        rateWindows[characterId] = nil
        for key in pairs(repeats) do
            if key:sub(1, #characterId + 1) == characterId .. ':' then
                repeats[key] = nil
            end
        end
    end
    if source then
        TriggerClientEvent('bcc-chat:reset-session', source)
    end
end)

AddEventHandler('core.session.ready.v1', function(event)
    local source = type(event) == 'table' and tonumber(event.source) or nil
    if not source then return end

    TriggerClientEvent('bcc-chat:directory-invalidated', source, -1)

    if not Config.Features.joinAnnouncements or not Config.JoinAnnouncement.enabled then return end
    SetTimeout(1000, function()
        local session = exports['feather-core']:GetSessionContext(source)
        if type(session) ~= 'table' or not session.ok or session.value.sessionId ~= event.sessionId then return end
        sendResourceMessage({
            channelKey = 'system',
            authorLabelKey = 'authorAnnouncement',
            body = { text = FeatherCore.Locale.translate(source, Config.JoinAnnouncement.textKey) },
            targets = { source }
        })
    end)
end)

RegisterCommand('ChatContractSmokeTest', function(source)
    if source ~= 0 then return end
    local caps = ChatFoundation.GetCapabilities()
    local healthy = ChatFoundation.GetHealth().state == 'ready'
    local moderationReady = type(ChatModeration.Check) == 'function'
    print(('[ChatContractSmokeTest] capabilities %s'):format(caps.ok and 'PASS' or 'FAIL'))
    print(('[ChatContractSmokeTest] health %s'):format(healthy and 'PASS' or 'FAIL'))
    print(('[ChatContractSmokeTest] built-in %s'):format(ChatChannels.Get('local.say') and 'PASS' or 'FAIL'))
    print(('[ChatContractSmokeTest] default theme %s'):format(ChatThemes.Get(Config.Theme.default).ok and 'PASS' or
        'FAIL'))
    print(('[ChatContractSmokeTest] moderation %s'):format(moderationReady and 'PASS' or 'FAIL'))
end, true)

RegisterCommand('ChatSessionSmokeTest', function(source, args)
    if source ~= 0 then return end
    local target = tonumber(args[1])
    local session = target and exports['feather-core']:GetSessionContext(target) or nil
    local actor = session and session.ok and actorFor(target, session.value) or nil
    print(('[ChatSessionSmokeTest] source=%s %s'):format(tostring(target), actor and 'PASS' or 'FAIL'))
end, true)

RegisterCommand('ChatChannelSmokeTest', function(source)
    if source ~= 0 then return end
    local key = 'smoke.channel'
    local created = ChatChannels.Register({
        channelKey = key,
        label = FeatherCore.Locale.translate(0, 'channelSystem'),
        visibility = 'public',
        routing = { type = 'global' },
        presentation = { variant = 'system' }
    })
    local removed = created.ok and ChatChannels.Unregister(key) or
        ChatResults.Err('not_created', FeatherCore.Locale.translate(0, 'errorSmokeNotCreated'))
    print(('[ChatChannelSmokeTest] register/remove %s'):format(created.ok and removed.ok and 'PASS' or 'FAIL'))
end, true)

RegisterCommand('ChatModerationSmokeTest', function(source)
    if source ~= 0 then return end
    local issued = ChatModeration.Issue({
        source = 0,
        characterId = '00000000-0000-4000-8000-000000000000',
        scope = 'channel',
        channelKey = 'local.say',
        durationSeconds = 10,
        reasonCode = 'smoke'
    })
    local blocked = issued.ok and not ChatModeration.Check({ characterId = issued.value.characterId }, 'local.say').ok
    local revoked = issued.ok and ChatModeration.Revoke(issued.value.muteId, issued.value.revision, 0)
    print(('[ChatModerationSmokeTest] issue/check/revoke %s'):format(blocked and revoked.ok and 'PASS' or 'FAIL'))
end, true)

RegisterCommand('ChatSecuritySmokeTest', function(source)
    if source ~= 0 then return end
    local tests = {
        cleanText('<script>alert(1)</script>', 500) ~= nil,
        cleanText(('a'):rep(Config.MaximumMessageLength + 1), Config.MaximumMessageLength) == nil,
        cleanText('safe\226\128\174spoof', Config.MaximumMessageLength) == nil,
        cleanText('one\ntwo\nthree\nfour\nfive', Config.MaximumMessageLength) == nil
    }
    local passed = true
    for _, value in ipairs(tests) do
        passed = passed and value
    end
    print(('[ChatSecuritySmokeTest] validation %s'):format(passed and 'PASS' or 'FAIL'))
end, true)

RegisterCommand('ChatPersistenceSmokeTest', function(source)
    if source ~= 0 then return end
    local called, result = pcall(function()
        local tables = tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN
                ('bcc_chat_schema_migrations', 'bcc_chat_mutes', 'bcc_chat_messages')]])) or 0
        local ledger = tonumber(MySQL.scalar.await(
            'SELECT COUNT(*) FROM `bcc_chat_schema_migrations`')) or 0
        return { tables = tables, ledger = ledger }
    end)
    print(('[ChatPersistenceSmokeTest] readiness %s'):format(
        ChatPersistence.IsReady() and 'PASS' or 'FAIL'))
    print(('[ChatPersistenceSmokeTest] tables %s'):format(
        called and result.tables == 3 and 'PASS' or 'FAIL'))
    print(('[ChatPersistenceSmokeTest] migration ledger %s'):format(
        called and result.ledger >= 1 and 'PASS' or 'FAIL'))
end, true)

RegisterCommand('ChatRestartChecklist', function(source)
    if source ~= 0 then return end
    print('[ChatRestartChecklist] restart bcc-chat; verify focus releases, UI clears, built-ins return, '
        .. 'and external owners re-register')
    print('[ChatRestartChecklist] restart feather-core/feather-character/feather-roles; '
        .. 'verify submissions fail closed until dependencies recover')
end, true)
