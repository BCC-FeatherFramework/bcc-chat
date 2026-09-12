ChatModeration = {}

local mutes, providers = {}, {}
local allowedScopes = { all = true, channel = true }

local function isCallable(value)
    return type(value) == 'function'
        or (type(value) == 'table' and type(rawget(value, '__cfx_functionReference')) == 'string')
end

local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for key, child in pairs(value) do if type(child) ~= 'function' then out[key] = copy(child) end end
    return out
end

local function uuid()
    return ('xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'):gsub('[xy]', function(c)
        local value = c == 'x' and math.random(0, 15) or math.random(8, 11)
        return ('%x'):format(value)
    end)
end

local function owner() return GetInvokingResource() or GetCurrentResourceName() end

local function isUuid(value)
    return type(value) == 'string'
        and value:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$') ~= nil
end

local function authorized(request)
    local source = tonumber(request and request.source) or 0
    if source == 0 then return true end
    local decision = ChatRoles.Authorize('muteManage', source)
    return type(decision) == 'table' and decision.ok == true and decision.value.allowed == true
end

local function actorCharacterId(source)
    source = tonumber(source) or 0
    if source <= 0 then return nil end
    local actor = ChatRoles.GetActor(source)
    return actor.ok and actor.value.characterId or nil
end

function ChatModeration.LoadPersistent()
    local loaded = ChatPersistence.LoadActiveMutes()
    if not loaded.ok then return loaded end
    mutes = {}
    for _, mute in ipairs(loaded.value) do mutes[mute.muteId] = mute end
    return ChatResults.Ok({ loaded = #loaded.value })
end

function ChatModeration.Issue(request)
    if type(request) ~= 'table' or not isUuid(request.characterId) then
        return ChatResults.Err('invalid_input',
            FeatherCore.Locale.translate(request and request.source, 'errorMuteCharacter'))
    end
    if not authorized(request) then
        return ChatResults.Err('forbidden',
            FeatherCore.Locale.translate(request.source, 'errorMuteForbidden'))
    end
    local scope = request.scope or (request.channelKey and 'channel' or 'all')
    if not allowedScopes[scope] or (scope == 'channel' and type(request.channelKey) ~= 'string') then
        return ChatResults.Err('invalid_input', FeatherCore.Locale.translate(request.source, 'errorMuteScope'))
    end
    local duration = tonumber(request.durationSeconds)
    if duration and (duration ~= duration or duration < 1 or duration > Config.Moderation.maximumMuteSeconds) then
        return ChatResults.Err('invalid_input', FeatherCore.Locale.translate(request.source, 'errorMuteDuration'))
    end
    local now = os.time()
    local mute = {
        muteId = uuid(),
        characterId = request.characterId,
        scope = scope,
        channelKey = scope == 'channel' and request.channelKey or nil,
        reasonCode = tostring(request.reasonCode or 'operator'):sub(1, 64),
        issuedByCharacterId = actorCharacterId(request.source),
        issuedAt = now,
        expiresAt = duration and (now + math.floor(duration)) or nil,
        revision = 1,
        ownerResource = owner()
    }
    local persisted = ChatPersistence.InsertMute(mute)
    if not persisted.ok then return persisted end
    mutes[mute.muteId] = mute
    TriggerEvent('chat.mute.issued.v1', copy(mute))
    return ChatResults.Ok(copy(mute))
end

function ChatModeration.Revoke(muteId, expectedRevision, requestSource)
    local mute = type(muteId) == 'string' and mutes[muteId] or nil
    if not mute then
        return ChatResults.Err('not_found', FeatherCore.Locale.translate(requestSource, 'errorMuteMissing'))
    end
    if not authorized({ source = requestSource, characterId = mute.characterId, channelKey = mute.channelKey }) then
        return ChatResults.Err('forbidden', FeatherCore.Locale.translate(requestSource, 'errorMuteForbidden'))
    end
    if tonumber(expectedRevision) ~= mute.revision then
        return ChatResults.Err('revision_conflict', FeatherCore.Locale.translate(requestSource, 'errorMuteRevision'),
            { currentRevision = mute.revision })
    end
    local actorId = actorCharacterId(requestSource)
    local persisted = ChatPersistence.RevokeMute(mute, actorId)
    if not persisted.ok then return persisted end
    mutes[muteId] = nil
    TriggerEvent('chat.mute.revoked.v1',
        { muteId = muteId, characterId = mute.characterId, revision = mute.revision + 1 })
    return ChatResults.Ok(true)
end

function ChatModeration.GetSnapshot(subject)
    if type(subject) ~= 'table' or type(subject.characterId) ~= 'string' then
        return ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorMuteCharacter'))
    end
    local now, result = os.time(), {}
    for id, mute in pairs(mutes) do
        if mute.expiresAt and mute.expiresAt <= now then
            ChatPersistence.ExpireMute(mute)
            mutes[id] = nil
        elseif mute.characterId == subject.characterId then
            result[#result + 1] = copy(mute)
        end
    end
    return ChatResults.Ok(result)
end


function ChatModeration.PruneExpired()
    local now, removed = os.time(), 0
    for id, mute in pairs(mutes) do
        if mute.expiresAt and mute.expiresAt <= now then
            mutes[id] = nil
            removed = removed + 1
        end
    end
    return ChatResults.Ok({ removed = removed })
end

function ChatModeration.Check(actor, channelKey)
    local snapshot = ChatModeration.GetSnapshot({ characterId = actor.characterId })
    for _, mute in ipairs(snapshot.value) do
        if mute.scope == 'all' or mute.channelKey == channelKey then
            return ChatResults.Err('muted', FeatherCore.Locale.translate(actor.source, 'errorMuted'), {
                muteId = mute.muteId, reasonCode = mute.reasonCode, expiresAt = mute.expiresAt
            })
        end
    end
    return ChatResults.Ok(true)
end

function ChatModeration.RegisterProvider(name, implementation, options)
    if type(name) ~= 'string' or not name:match('^[a-z][a-z0-9_.-]*$')
        or type(implementation) ~= 'table' or not isCallable(implementation.Evaluate) then
        return ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorModerationInvalid'))
    end
    if providers[name] then
        return ChatResults.Err('conflict', FeatherCore.Locale.translate(0, 'errorModerationConflict'))
    end
    options = type(options) == 'table' and options or {}
    providers[name] = { ownerResource = owner(), implementation = implementation, required = options.required == true }
    return ChatResults.Ok({ name = name, required = providers[name].required })
end

function ChatModeration.Evaluate(request)
    local text = request.text
    for name, provider in pairs(providers) do
        local called, result = pcall(provider.implementation.Evaluate, copy(request))
        if not called or type(result) ~= 'table' then
            if provider.required then
                return ChatResults.Err('moderation_unavailable',
                    FeatherCore.Locale.translate(request.actor and request.actor.source, 'errorModerationUnavailable'),
                    { provider = name })
            end
        elseif result.ok == false then
            return ChatResults.Err(result.code or 'invalid_content',
                result.message or FeatherCore.Locale.translate(request.actor and request.actor.source, 'errorRejected'))
        else
            local value = result.ok == true and result.value or result
            if value and value.allowed == false then
                return ChatResults.Err(value.code or 'invalid_content',
                    value.message or
                    FeatherCore.Locale.translate(request.actor and request.actor.source, 'errorRejected'))
            end
            if value and type(value.text) == 'string' then text = value.text end
        end
    end
    return ChatResults.Ok({ text = text })
end

AddEventHandler('onResourceStop', function(resource)
    for name, provider in pairs(providers) do if provider.ownerResource == resource then providers[name] = nil end end
end)

exports('RegisterModerationProvider', ChatModeration.RegisterProvider)
exports('IssueMute', ChatModeration.Issue)
exports('RevokeMute', ChatModeration.Revoke)
exports('GetMuteSnapshot', ChatModeration.GetSnapshot)
