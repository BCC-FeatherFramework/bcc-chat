ChatRoles = {}

local roleSubscription

local function copy(value)
    if type(value) ~= 'table' then return value end

    local output = {}
    for key, child in pairs(value) do output[key] = copy(child) end
    return output
end

local function permissionLevel(permission)
    local value = Config.Permissions and Config.Permissions[permission]
    return math.max(0, math.floor(tonumber(value) or 0))
end

function ChatRoles.AwaitReady(timeoutMs)
    local capabilitiesCalled, capabilities = pcall(function()
        return exports['feather-roles']:GetCapabilities()
    end)
    local features = capabilitiesCalled and type(capabilities) == 'table' and capabilities.ok == true
        and type(capabilities.value) == 'table' and capabilities.value.features or nil
    if type(features) ~= 'table' or features.actorAuthority ~= 1 then
        return ChatResults.Err(
            'role_provider_unavailable',
            FeatherCore.Locale.translate(0, 'errorRolesUnavailable')
        )
    end

    local readyCalled, result = pcall(function()
        return exports['feather-roles']:AwaitReady(timeoutMs or 10000)
    end)
    if not readyCalled or type(result) ~= 'table' or result.ok ~= true then
        return ChatResults.Err(
            'role_provider_unavailable',
            FeatherCore.Locale.translate(0, 'errorRolesUnavailable')
        )
    end
    return ChatResults.Ok(result.value)
end

function ChatRoles.GetActor(source)
    source = tonumber(source)
    if not source or source <= 0 then
        return ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorRoleSource'))
    end

    local called, result = pcall(function()
        return exports['feather-roles']:GetActorRole(source)
    end)
    if not called or type(result) ~= 'table' or result.ok ~= true or type(result.value) ~= 'table'
        or type(result.value.role) ~= 'table' then
        return ChatResults.Err(
            'role_provider_unavailable',
            FeatherCore.Locale.translate(source, 'errorRolesUnavailable')
        )
    end

    local role = result.value.role
    return ChatResults.Ok({
        source = source,
        accountId = result.value.accountId,
        characterId = result.value.characterId,
        sessionId = result.value.sessionId,
        role = {
            key = tostring(role.key or 'player'),
            name = tostring(role.name or role.key or 'Player'),
            level = math.max(0, math.floor(tonumber(role.level) or 0))
        }
    })
end

function ChatRoles.Authorize(permission, source)
    source = tonumber(source) or 0
    if source == 0 then
        return ChatResults.Ok({ allowed = true, system = true })
    end

    local actor = ChatRoles.GetActor(source)
    if not actor.ok then
        return actor
    end

    local required = permissionLevel(permission)
    local allowed = actor.value.role.level >= required
    return ChatResults.Ok({
        allowed = allowed,
        permission = permission,
        requiredLevel = required,
        role = copy(actor.value.role)
    })
end

function ChatRoles.GetPresentation(source)
    if Config.Features and Config.Features.rolePresentation == false then
        return ChatResults.Ok({ visible = false })
    end

    local actor = ChatRoles.GetActor(source)
    if not actor.ok then return actor end

    local role = actor.value.role
    local configured = Config.RolePresentation and Config.RolePresentation[role.key] or nil
    if type(configured) ~= 'table' or configured.visible ~= true then
        return ChatResults.Ok({ visible = false, roleKey = role.key, level = role.level })
    end

    local label = configured.labelKey and FeatherCore.Locale.translate(source, configured.labelKey) or role.name
    label = tostring(label):sub(1, 32)
    local color = tostring(configured.color or '#FFFFFF')
    if not color:match('^#%x%x%x%x%x%x$') then color = '#FFFFFF' end
    return ChatResults.Ok({
        visible = true,
        roleKey = role.key,
        level = role.level,
        label = label,
        labelKey = configured.labelKey,
        color = color
    })
end

function ChatRoles.CheckChannelAccess(request)
    local actor = type(request) == 'table' and request.actor or nil
    local source = actor and tonumber(actor.source) or 0
    local operation = type(request) == 'table' and request.operation or 'receive'
    local permission = operation == 'send' and 'staffSend' or 'staffRead'
    local decision = ChatRoles.Authorize(permission, source)
    if not decision.ok then return decision end

    return ChatResults.Ok({
        eligible = decision.value.allowed,
        canSend = decision.value.allowed,
        canReceive = decision.value.allowed
    })
end

local function invalidateRoleAccess(payload)
    local characterId = type(payload) == 'table' and payload.characterId or nil
    if not characterId then return end

    for _, playerId in ipairs(GetPlayers()) do
        local source = tonumber(playerId)
        local session = source and exports['feather-core']:GetSessionContext(source) or nil
        if type(session) == 'table' and session.ok == true
            and session.value.characterId == characterId then
            TriggerClientEvent('bcc-chat:directory-invalidated', source, -1)
        end
    end
end

function ChatRoles.Subscribe()
    if roleSubscription then return ChatResults.Ok({ token = roleSubscription }) end

    local result = exports['feather-core']:SubscribeEvent('roles.assignment.changed.v1', invalidateRoleAccess)
    if type(result) ~= 'table' or result.ok ~= true then
        return ChatResults.Err(
            'role_subscription_failed',
            FeatherCore.Locale.translate(0, 'errorRoleSubscription')
        )
    end
    roleSubscription = result.value and result.value.token
    return ChatResults.Ok({ token = roleSubscription })
end

AddEventHandler('onResourceStop', function(resource)
    if resource == 'feather-roles' or resource == 'feather-core' then roleSubscription = nil end
end)

exports('GetActorRoleSnapshot', ChatRoles.GetActor)
exports('CheckRolePermission', ChatRoles.Authorize)
