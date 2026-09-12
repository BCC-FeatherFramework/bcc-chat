ChatChannels = {}

local channels, accessProviders, suggestions = {}, {}, {}
local revision, generation = 0, 0
local allowedVisibility = { public = true, eligible = true, discoverable = true, hidden = true, system = true }
local allowedVariants = {
    localSpeech = true,
    roleplay = true,
    ooc = true,
    organization = true,
    staff = true,
    system = true,
    success = true,
    warning = true,
    danger = true
}
local allowedAccents = {
    ['channel.localSpeech'] = true,
    ['channel.roleplay'] = true,
    ['channel.ooc'] = true,
    ['channel.organization'] = true,
    ['channel.staff'] = true,
    ['channel.system'] = true,
    ['channel.success'] = true,
    ['channel.warning'] = true,
    ['channel.danger'] = true
}

local function isCallable(value)
    return type(value) == 'function'
        or (type(value) == 'table' and type(rawget(value, '__cfx_functionReference')) == 'string')
end

local function owner() return GetInvokingResource() or GetCurrentResourceName() end
local function trim(value) return type(value) == 'string' and value:match('^%s*(.-)%s*$') or nil end
local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for key, child in pairs(value) do if type(child) ~= 'function' then out[key] = copy(child) end end
    return out
end

local function validKey(value)
    return type(value) == 'string' and #value <= 96 and value:match('^[a-z][a-z0-9_.-]*$') ~= nil
end

local function validate(definition)
    if type(definition) ~= 'table' or not validKey(definition.channelKey) then
        return nil, ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorInvalidChannelKey'))
    end
    local label = trim(definition.label)
    if not label or #label > 64 then
        return nil,
            ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorLabelRequired'))
    end
    local shortLabel, description = trim(definition.shortLabel), trim(definition.description)
    local labelKey = trim(definition.labelKey)
    if labelKey and (#labelKey > 96 or not labelKey:match('^[a-z][a-zA-Z0-9_.-]*$')) then
        return nil, ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorLabelKeyInvalid'))
    end
    if shortLabel and #shortLabel > 32 then
        return nil,
            ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorShortLabelLong'))
    end
    if description and #description > 160 then
        return nil,
            ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorDescriptionLong'))
    end
    local visibility = definition.visibility or 'public'
    if not allowedVisibility[visibility] then
        return nil,
            ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorVisibilityInvalid'))
    end
    local presentation = type(definition.presentation) == 'table' and definition.presentation or {}
    local variant = presentation.variant or 'localSpeech'
    if not allowedVariants[variant] then
        return nil,
            ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorVariantInvalid'))
    end
    local accentToken = presentation.accentToken or ('channel.' .. variant)
    if not allowedAccents[accentToken] then
        return nil,
            ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorAccentInvalid'))
    end
    local icon = trim(presentation.icon)
    if icon and (#icon > 32 or not icon:match('^[a-z0-9_-]+$')) then
        return nil,
            ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorIconInvalid'))
    end
    local accessProvider = definition.accessProvider
    local protected = visibility == 'eligible' or visibility == 'discoverable' or visibility == 'hidden'
    if protected and not validKey(accessProvider) then
        return nil, ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorProtectedProvider'))
    end
    local routing = type(definition.routing) == 'table' and copy(definition.routing) or { type = 'global' }
    if routing.type ~= 'global' and routing.type ~= 'proximity' and routing.type ~= 'explicit' then
        return nil, ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorRoutingInvalid'))
    end
    if routing.type == 'proximity' then
        routing.radius = tonumber(routing.radius)
        if not routing.radius or routing.radius <= 0 or routing.radius > 100 then
            return nil, ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorRadiusInvalid'))
        end
    end
    if routing.kind ~= nil and routing.kind ~= 'player' and routing.kind ~= 'action' and routing.kind ~= 'scene' then
        return nil, ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorKindInvalid'))
    end
    local aliases = {}
    local suppliedAliases = type(definition.input) == 'table' and definition.input.aliases or {}
    if type(suppliedAliases) ~= 'table' or #suppliedAliases > 8 then
        return nil, ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorAliasesInvalid'))
    end
    for _, alias in ipairs(suppliedAliases) do
        if type(alias) ~= 'string' or #alias < 2 or #alias > 32 or not alias:match('^/[a-z][a-z0-9_-]*$') then
            return nil, ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorAliasInvalid'))
        end
        aliases[#aliases + 1] = alias
    end
    return {
        channelKey = definition.channelKey,
        label = label,
        labelKey = labelKey,
        shortLabel = shortLabel,
        description = description,
        visibility = visibility,
        accessProvider = accessProvider,
        presentation = { variant = variant, accentToken = accentToken, icon = icon },
        input = {
            aliases = aliases,
            allowMultiline = type(definition.input) == 'table' and definition.input.allowMultiline == true,
            maximumLength = math.min(Config.MaximumMessageLength,
                math.max(1,
                    tonumber(type(definition.input) == 'table' and definition.input.maximumLength) or
                    Config.MaximumMessageLength))
        },
        routing = routing,
        revision = tonumber(definition.revision) or 1
    }
end

local function publicChannel(channel)
    local result = copy(channel)
    result.ownerResource = nil
    return result
end

function ChatChannels.Register(definition)
    local normalized, failure = validate(definition)
    if not normalized then return failure end
    if channels[normalized.channelKey] then
        return ChatResults.Err('conflict',
            FeatherCore.Locale.translate(0, 'errorChannelConflict'))
    end
    generation = generation + 1
    normalized.ownerResource, normalized.generation = owner(), generation
    channels[normalized.channelKey] = normalized
    revision = revision + 1
    TriggerClientEvent('bcc-chat:directory-invalidated', -1, revision)
    TriggerEvent('chat.channel.registered.v1', {
        channelKey = normalized.channelKey,
        ownerResource = normalized.ownerResource,
        generation = normalized.generation,
        revision = normalized.revision
    })
    return ChatResults.Ok(publicChannel(normalized))
end

function ChatChannels.Unregister(channelKey)
    local channel = channels[channelKey]
    if not channel then return ChatResults.Err('not_found', FeatherCore.Locale.translate(0, 'errorNotFound')) end
    if channel.ownerResource ~= owner() then
        return ChatResults.Err('forbidden',
            FeatherCore.Locale.translate(0, 'errorForbiddenOwner'))
    end
    channels[channelKey], revision = nil, revision + 1
    TriggerClientEvent('bcc-chat:directory-invalidated', -1, revision)
    TriggerEvent('chat.channel.unregistered.v1', {
        channelKey = channelKey,
        ownerResource = channel.ownerResource,
        generation = channel.generation,
        revision = channel.revision
    })
    return ChatResults.Ok(true)
end

function ChatChannels.Update(channelKey, patch, expectedRevision)
    local current = channels[channelKey]
    if not current then return ChatResults.Err('not_found', FeatherCore.Locale.translate(0, 'errorNotFound')) end
    if current.ownerResource ~= owner() then
        return ChatResults.Err('forbidden',
            FeatherCore.Locale.translate(0, 'errorForbiddenOwner'))
    end
    if tonumber(expectedRevision) ~= current.revision then
        return ChatResults.Err('revision_conflict', FeatherCore.Locale.translate(0, 'errorRevisionConflict'),
            { currentRevision = current.revision })
    end
    if type(patch) ~= 'table' then
        return ChatResults.Err('invalid_input',
            FeatherCore.Locale.translate(0, 'errorPatchRequired'))
    end
    local merged = copy(current)
    local mutableFields = {
        'label',
        'labelKey',
        'shortLabel',
        'description',
        'visibility',
        'accessProvider',
        'presentation',
        'input',
        'routing'
    }
    for _, key in ipairs(mutableFields) do
        if patch[key] ~= nil then merged[key] = copy(patch[key]) end
    end
    merged.revision = current.revision + 1
    local normalized, failure = validate(merged)
    if not normalized then return failure end
    normalized.ownerResource = current.ownerResource
    normalized.generation = current.generation
    channels[channelKey] = normalized
    revision = revision + 1
    TriggerClientEvent('bcc-chat:directory-invalidated', -1, revision)
    TriggerEvent('chat.channel.updated.v1', {
        channelKey = channelKey,
        ownerResource = normalized.ownerResource,
        generation = normalized.generation,
        revision = normalized.revision
    })
    return ChatResults.Ok(publicChannel(normalized))
end

function ChatChannels.RegisterAccessProvider(name, implementation)
    if not validKey(name) or type(implementation) ~= 'table' or not isCallable(implementation.CheckAccess) then
        return ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorProviderInvalid'))
    end
    if accessProviders[name] then
        return ChatResults.Err('conflict',
            FeatherCore.Locale.translate(0, 'errorProviderConflict'))
    end
    accessProviders[name] = { ownerResource = owner(), implementation = implementation }
    return ChatResults.Ok({ name = name, ownerResource = accessProviders[name].ownerResource })
end

function ChatChannels.CheckAccess(channel, actor, operation)
    if channel.visibility == 'public' then return ChatResults.Ok({ eligible = true }) end
    if channel.visibility == 'system' then
        return ChatResults.Err('channel_access_denied',
            FeatherCore.Locale.translate(actor.source, 'errorPlayerSystem'))
    end
    local provider = accessProviders[channel.accessProvider]
    if not provider then
        return ChatResults.Err('channel_unavailable',
            FeatherCore.Locale.translate(actor.source, 'errorProviderUnavailable'))
    end
    local ok, result = pcall(provider.implementation.CheckAccess,
        { channelKey = channel.channelKey, actor = copy(actor), operation = operation })
    if not ok or type(result) ~= 'table' then
        return ChatResults.Err('channel_unavailable',
            FeatherCore.Locale.translate(actor.source, 'errorProviderFailed'))
    end
    if result.ok == false then return result end
    local value = result.ok == true and result.value or result
    if not value or value.eligible ~= true or (operation == 'send' and value.canSend == false)
        or (operation == 'receive' and value.canReceive == false) then
        return ChatResults.Err('channel_access_denied', FeatherCore.Locale.translate(actor.source, 'errorAccessDenied'))
    end
    return ChatResults.Ok(copy(value))
end

function ChatChannels.ListFor(actor)
    local result = {}
    for _, channel in pairs(channels) do
        local access = ChatChannels.CheckAccess(channel, actor, 'list')
        local listed = channel.visibility ~= 'hidden' and channel.visibility ~= 'system'
        if listed and (access.ok or channel.visibility == 'discoverable') then
            result[#result + 1] = publicChannel(channel)
        end
    end
    table.sort(result, function(a, b) return a.channelKey < b.channelKey end)
    local publicSuggestions = {}
    for _, suggestion in pairs(suggestions) do
        local access = ChatResults.Ok({ eligible = true })
        if suggestion.accessProvider then
            access = ChatChannels.CheckAccess({
                channelKey = 'suggestion.' .. suggestion.key,
                visibility = 'eligible',
                accessProvider = suggestion.accessProvider
            }, actor, 'list')
        end
        if access.ok then
            publicSuggestions[#publicSuggestions + 1] = {
                key = suggestion.key,
                trigger = suggestion.trigger,
                description = suggestion.description,
                descriptionKey = suggestion.descriptionKey,
                descriptionArgs = copy(suggestion.descriptionArgs),
                parameters = copy(suggestion.parameters)
            }
        end
    end
    table.sort(publicSuggestions, function(a, b) return a.key < b.key end)
    return ChatResults.Ok({ revision = revision, channels = result, suggestions = publicSuggestions })
end

function ChatChannels.Get(key) return channels[key] end

function ChatChannels.RegisterSuggestion(definition)
    if type(definition) ~= 'table' or not validKey(definition.key) or type(definition.trigger) ~= 'string' then
        return ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorSuggestionInvalid'))
    end
    if suggestions[definition.key] then
        return ChatResults.Err('conflict',
            FeatherCore.Locale.translate(0, 'errorSuggestionConflict'))
    end
    local trigger = trim(definition.trigger)
    if not trigger or #trigger < 2 or #trigger > 32 or trigger:sub(1, 1) ~= '/' then
        return ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorTriggerInvalid'))
    end
    if type(definition.parameters) == 'table' and #definition.parameters > 8 then
        return ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorParametersInvalid'))
    end
    if definition.accessProvider ~= nil and not validKey(definition.accessProvider) then
        return ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorProviderInvalid'))
    end
    local item = {
        key = definition.key,
        trigger = trigger,
        description = tostring(definition.description or ''):sub(1, 128),
        descriptionKey = trim(definition.descriptionKey),
        descriptionArgs = copy(definition.descriptionArgs or {}),
        parameters = copy(definition.parameters or {}),
        accessProvider = definition.accessProvider,
        ownerResource = owner()
    }
    suggestions[definition.key] = item
    revision = revision + 1
    TriggerClientEvent('bcc-chat:directory-invalidated', -1, revision)
    return ChatResults.Ok(copy(item))
end

function ChatChannels.RemoveSuggestion(key)
    local item = suggestions[key]
    if not item then return ChatResults.Err('not_found', FeatherCore.Locale.translate(0, 'errorSuggestionMissing')) end
    if item.ownerResource ~= owner() then
        return ChatResults.Err('forbidden',
            FeatherCore.Locale.translate(0, 'errorForbiddenOwner'))
    end
    suggestions[key], revision = nil, revision + 1
    TriggerClientEvent('bcc-chat:directory-invalidated', -1, revision)
    return ChatResults.Ok(true)
end

AddEventHandler('onResourceStop', function(resource)
    local changed = false
    for key, channel in pairs(channels) do
        if channel.ownerResource == resource then
            channels[key], changed = nil, true
            TriggerEvent('chat.channel.unregistered.v1', {
                channelKey = key,
                ownerResource = resource,
                generation = channel.generation,
                revision = channel.revision,
                reason = 'owner_stopped'
            })
        end
    end
    for key, provider in pairs(accessProviders) do
        if provider.ownerResource == resource then
            accessProviders[key], changed = nil, true
        end
    end
    for key, suggestion in pairs(suggestions) do
        if suggestion.ownerResource == resource then
            suggestions[key], changed = nil, true
        end
    end
    if changed then
        revision = revision + 1
        TriggerClientEvent('bcc-chat:directory-invalidated', -1, revision)
    end
end)

exports('RegisterChannel', ChatChannels.Register)
exports('UpdateChannel', ChatChannels.Update)
exports('UnregisterChannel', ChatChannels.Unregister)
exports('RegisterChannelAccessProvider', ChatChannels.RegisterAccessProvider)
exports('RegisterSuggestion', ChatChannels.RegisterSuggestion)
exports('RemoveSuggestion', ChatChannels.RemoveSuggestion)
