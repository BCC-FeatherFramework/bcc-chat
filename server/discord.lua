ChatDiscord = {}

local cache, sourceIds = {}, {}

local function configuredRole(roleId)
    for _, role in ipairs(Config.Discord.roles or {}) do
        if type(role) == 'table' and tostring(role.roleId) == tostring(roleId) then
            local labelKey = type(role.labelKey) == 'string' and role.labelKey or nil
            local color = tostring(role.color or '#FFFFFF')
            if labelKey and labelKey:match('^[a-z][a-zA-Z0-9_.-]*$')
                and color:match('^#%x%x%x%x%x%x$') then
                return { visible = true, labelKey = labelKey, color = color }
            end
        end
    end
end

local function discordId(source)
    if sourceIds[source] then return sourceIds[source] end
    for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
        if identifier:sub(1, 8) == 'discord:' then
            sourceIds[source] = identifier:sub(9)
            return sourceIds[source]
        end
    end
end

local function fetchRoles(id, guildId, token)
    local pending, completed = promise.new(), false
    PerformHttpRequest(('https://discord.com/api/v10/guilds/%s/members/%s'):format(guildId, id),
        function(status, response)
            if completed then return end
            completed = true
            if status ~= 200 then
                pending:resolve({})
                return
            end
            local decoded, document = pcall(json.decode, response or '')
            pending:resolve(decoded and type(document) == 'table' and type(document.roles) == 'table'
                and document.roles or {})
        end, 'GET', '', {
            ['Accept'] = 'application/json',
            ['Authorization'] = 'Bot ' .. token
        })
    SetTimeout(5000, function()
        if completed then return end
        completed = true
        pending:resolve({})
    end)
    return pending
end

local function memberRoles(source)
    local id = discordId(source)
    if not id then return {} end

    local now = os.time()
    local existing = cache[id]
    if existing and now - existing.createdAt < math.max(10, tonumber(Config.Discord.cacheSeconds) or 60) then
        return existing.roles
    end

    local guildId = GetConvar(Config.Discord.guildIdConvar, '')
    local token = GetConvar(Config.Discord.botTokenConvar, '')
    if guildId == '' or token == '' then return existing and existing.roles or {} end

    if existing then
        -- Serve the stale-but-known roles immediately and refresh in the background instead of
        -- blocking this player's message submission on Discord's API for up to 5 seconds.
        Citizen.CreateThread(function()
            cache[id] = { createdAt = os.time(), roles = Citizen.Await(fetchRoles(id, guildId, token)) }
        end)
        return existing.roles
    end

    local roles = Citizen.Await(fetchRoles(id, guildId, token))
    cache[id] = { createdAt = now, roles = roles }
    return roles
end

function ChatDiscord.GetPresentation(source)
    if not Config.Discord.enabled or not Config.Discord.roleTags then
        return ChatResults.Ok({ visible = false })
    end

    local called, roles = pcall(memberRoles, source)
    if not called or type(roles) ~= 'table' then return ChatResults.Ok({ visible = false }) end
    for _, roleId in ipairs(roles) do
        local presentation = configuredRole(roleId)
        if presentation then return ChatResults.Ok(presentation) end
    end
    return ChatResults.Ok({ visible = false })
end

AddEventHandler('playerDropped', function()
    local id = sourceIds[source]
    if id then cache[id] = nil end
    sourceIds[source] = nil
end)
