RegisterServerEvent('chat:init')
RegisterServerEvent('chat:addTemplate')
RegisterServerEvent('chat:addMessage')
RegisterServerEvent('chat:addSuggestion')
RegisterServerEvent('chat:removeSuggestion')
RegisterServerEvent('_chat:messageEntered')
RegisterServerEvent('chat:clear')
RegisterServerEvent('__cfx_internal:commandFallback')
RegisterNetEvent('bcc-chat:sendAnnouncement')
RegisterNetEvent('bcc-chat:requestRoleMenu')
RegisterNetEvent('bcc-chat:setPlayerRole')
RegisterNetEvent('bcc-chat:clearPlayerRole')
RegisterNetEvent('bcc-chat:requestDisplayNameMenu')
RegisterNetEvent('bcc-chat:setDisplayNameMode')

RegisterNetEvent('playerJoining')

local VORPcore = exports.vorp_core:GetCore()

local HISTORY_LIMIT = 150
local CHAT_TABLE = 'bcc_chat_messages'
local ROLE_TABLE = 'bcc_chat_roles'
local PLAYER_ROLE_TABLE = 'bcc_chat_player_roles'
local DISPLAY_NAME_TABLE = 'bcc_chat_name_preferences'
local discordRoleCache = {}
local roleListCache = nil
local assignedRoleCache = {}
local displayNamePreferenceCache = {}
local routeMessage

local DISPLAY_NAME_MODES = {
    player_name = true,
    character_name = true,
    character_with_player = true
}

local function normalizeSourceId(src)
    local numericSource = tonumber(src)
    if numericSource then
        return numericSource
    end

    return src
end

local function normalizeMessageTimestamp(value)
    if type(value) == 'number' then
        return value
    end

    return os.time()
end

local function getDiscordIdentifier(src)
    src = normalizeSourceId(src)

    if not src or src <= 0 then
        return nil
    end

    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        if identifier:sub(1, 8) == 'discord:' then
            return identifier:sub(9)
        end
    end

    return nil
end

local function trim(value)
    if value == nil then
        return nil
    end

    local trimmed = tostring(value):gsub('^%s+', ''):gsub('%s+$', '')
    if trimmed == '' then
        return nil
    end

    return trimmed
end

local function normalizeIdentifier(value)
    local trimmed = trim(value)
    return trimmed and trimmed:lower() or nil
end

local function getCharacter(src)
    src = normalizeSourceId(src)

    if not src or src <= 0 then
        return nil, nil
    end

    local user = VORPcore.getUser(src)
    if not user or not user.getUsedCharacter then
        return nil, nil
    end

    return user, user.getUsedCharacter
end

local function getPrimaryIdentifier(src, character)
    src = normalizeSourceId(src)

    local candidates = {
        character and character.identifier or nil
    }

    if src and src > 0 then
        for i = 0, GetNumPlayerIdentifiers(src) - 1 do
            candidates[#candidates + 1] = GetPlayerIdentifier(src, i)
        end
    end

    for _, candidate in ipairs(candidates) do
        local normalized = normalizeIdentifier(candidate)
        if normalized then
            return normalized
        end
    end

    return nil
end

local function getPlayerIdentity(src)
    local _, character = getCharacter(src)
    local identifier = getPrimaryIdentifier(src, character)

    if not identifier then
        return nil
    end

    return {
        identifier = identifier,
        charid = character and character.charIdentifier or nil,
        firstname = character and character.firstname or nil,
        lastname = character and character.lastname or nil
    }
end

local function fetchDiscordRoles(discordId)
    if not discordId or discordId == '' then
        return false
    end

    if not Config.DiscordGuildId or Config.DiscordGuildId == '' then
        return false
    end

    if not Config.DiscordBotToken or Config.DiscordBotToken == '' then
        return false
    end

    local cacheSeconds = Config.DiscordRoleCacheSeconds or 60
    local cacheEntry = discordRoleCache[discordId]

    if cacheEntry and (os.time() - cacheEntry.timestamp) < cacheSeconds then
        return cacheEntry.roles
    end

    local promiseHandle = promise.new()
    local url = ('https://discord.com/api/guilds/%s/members/%s'):format(Config.DiscordGuildId, discordId)

    PerformHttpRequest(url, function(statusCode, responseBody)
        if statusCode ~= 200 then
            promiseHandle:resolve(false)
            return
        end

        local ok, memberData = pcall(json.decode, responseBody)
        if not ok or not memberData or not memberData.roles then
            promiseHandle:resolve(false)
            return
        end

        discordRoleCache[discordId] = {
            roles = memberData.roles,
            timestamp = os.time()
        }

        promiseHandle:resolve(memberData.roles)
    end, 'GET', '', {
        ['Content-Type'] = 'application/json',
        ['Authorization'] = 'Bot ' .. Config.DiscordBotToken
    })

    return Citizen.Await(promiseHandle)
end

local function playerHasDiscordRole(src, wantedRoles)
    if not wantedRoles or #wantedRoles == 0 then
        return false
    end

    local discordId = getDiscordIdentifier(src)
    local roleIDs = fetchDiscordRoles(discordId)

    if not roleIDs or roleIDs == false then
        return false
    end

    for _, wantedRole in ipairs(wantedRoles) do
        for _, roleID in ipairs(roleIDs) do
            if tostring(wantedRole) == tostring(roleID) then
                return true
            end
        end
    end

    return false
end

local function playerMatchesAccess(src, aceObject, discordRoles)
    src = normalizeSourceId(src)

    if not src or src <= 0 then
        return true
    end

    local aceAllowed = aceObject and IsPlayerAceAllowed(src, aceObject) or false
    local discordAllowed = playerHasDiscordRole(src, discordRoles)
    local identifierAllowed = false
    local hasIdentifierRules = Config.AdminIdentifiers and #Config.AdminIdentifiers > 0

    if hasIdentifierRules then
        local playerIdentifiers = GetPlayerIdentifiers(src)
        for _, allowedIdentifier in ipairs(Config.AdminIdentifiers) do
            local normalizedAllowed = tostring(allowedIdentifier):gsub("^identifier%.", "")
            for _, playerIdentifier in ipairs(playerIdentifiers) do
                if normalizedAllowed == tostring(playerIdentifier) then
                    identifierAllowed = true
                    break
                end
            end

            if identifierAllowed then
                break
            end
        end
    end

    if not aceObject and (not discordRoles or #discordRoles == 0) then
        return true
    end

    if aceObject and discordRoles and #discordRoles > 0 then
        return aceAllowed or discordAllowed or identifierAllowed
    end

    if aceObject then
        return aceAllowed or identifierAllowed
    end

    if discordRoles and #discordRoles > 0 then
        return discordAllowed or identifierAllowed
    end

    if hasIdentifierRules then
        return identifierAllowed
    end

    return true
end

local function clearRoleCaches(identifier, charid)
    roleListCache = nil

    if identifier then
        assignedRoleCache[identifier .. ':' .. tostring(charid or 0)] = nil
    else
        assignedRoleCache = {}
    end
end

local function clearDisplayNamePreferenceCache(identifier, charid)
    if identifier then
        displayNamePreferenceCache[identifier .. ':' .. tostring(charid or 0)] = nil
    else
        displayNamePreferenceCache = {}
    end
end

local function getCharacterFullName(identity)
    if not identity then
        return nil
    end

    local parts = {}

    if identity.firstname then
        parts[#parts + 1] = identity.firstname
    end

    if identity.lastname then
        parts[#parts + 1] = identity.lastname
    end

    local characterName = table.concat(parts, ' ')
    return characterName ~= '' and characterName or nil
end

local function getDisplayNamePreference(identity)
    if not identity or not identity.identifier then
        return 'player_name'
    end

    local cacheKey = identity.identifier .. ':' .. tostring(identity.charid or 0)
    local cached = displayNamePreferenceCache[cacheKey]

    if cached and os.time() - cached.timestamp < 60 then
        return cached.mode
    end

    local row = MySQL.single.await(
        ('SELECT `display_mode` FROM `%s` WHERE `identifier` = ? AND (`charid` = ? OR `charid` IS NULL) ORDER BY `charid` DESC LIMIT 1'):format(DISPLAY_NAME_TABLE),
        { identity.identifier, identity.charid }
    )

    local mode = row and row.display_mode or 'player_name'
    if not DISPLAY_NAME_MODES[mode] then
        mode = 'player_name'
    end

    displayNamePreferenceCache[cacheKey] = {
        mode = mode,
        timestamp = os.time()
    }

    return mode
end

local function getChatAuthorName(src)
    src = normalizeSourceId(src)

    if not src or src <= 0 then
        return nil
    end

    local identity = getPlayerIdentity(src)
    local playerName = GetPlayerName(src) or ('ID %s'):format(src)
    local characterName = getCharacterFullName(identity)
    local mode = getDisplayNamePreference(identity)

    if mode == 'character_name' and characterName then
        return characterName
    end

    if mode == 'character_with_player' and characterName then
        return ('%s (%s)'):format(characterName, playerName)
    end

    return playerName
end

local function getConfiguredRolePriority(roleId)
    for index, configuredRole in ipairs(Config.DiscordRoleList or {}) do
        if tostring(configuredRole[1]) == tostring(roleId) then
            return index
        end
    end

    return 0
end

local function getChatRoles()
    if roleListCache then
        return roleListCache
    end

    local rows = MySQL.query.await(
        ('SELECT `role_id`, `label`, `tag`, `priority`, `enabled` FROM `%s` WHERE `enabled` = 1 ORDER BY `priority` ASC, `id` ASC'):format(ROLE_TABLE)
    ) or {}

    roleListCache = rows
    return rows
end

local function getChatRoleById(roleId)
    roleId = trim(roleId)
    if not roleId then
        return nil
    end

    local row = MySQL.single.await(
        ('SELECT `role_id`, `label`, `tag`, `priority`, `enabled` FROM `%s` WHERE `role_id` = ? AND `enabled` = 1 LIMIT 1'):format(ROLE_TABLE),
        { roleId }
    )

    return row
end

local function getAssignedChatRole(identity)
    if not identity or not identity.identifier then
        return nil
    end

    local cacheKey = identity.identifier .. ':' .. tostring(identity.charid or 0)
    local cached = assignedRoleCache[cacheKey]

    if cached and os.time() - cached.timestamp < 60 then
        return cached.role
    end

    local row = MySQL.single.await(
        ([[
            SELECT r.`role_id`, r.`label`, r.`tag`, r.`priority`
            FROM `%s` pr
            INNER JOIN `%s` r ON r.`role_id` = pr.`role_id`
            WHERE pr.`identifier` = ?
              AND (pr.`charid` = ? OR pr.`charid` IS NULL)
              AND r.`enabled` = 1
            ORDER BY r.`priority` DESC, pr.`id` DESC
            LIMIT 1
        ]]):format(PLAYER_ROLE_TABLE, ROLE_TABLE),
        { identity.identifier, identity.charid }
    )

    assignedRoleCache[cacheKey] = {
        role = row,
        timestamp = os.time()
    }

    return row
end

local function getPlayerDiscordTag(src)
    src = normalizeSourceId(src)

    if not src or src <= 0 then
        return ''
    end

    local identity = getPlayerIdentity(src)
    local assignedRole = getAssignedChatRole(identity)

    if assignedRole and assignedRole.tag and assignedRole.tag ~= '' then
        return assignedRole.tag
    end

    local roleList = getChatRoles()

    if #roleList == 0 then
        return ''
    end

    local fallbackTag = roleList[1] and roleList[1].tag or ''
    local discordId = getDiscordIdentifier(src)
    local roleIDs = fetchDiscordRoles(discordId)

    if not roleIDs or roleIDs == false then
        return fallbackTag
    end

    local chosenTag = fallbackTag

    for _, configuredRole in ipairs(roleList) do
        local configuredRoleId = tostring(configuredRole.role_id)
        local configuredRoleTag = configuredRole.tag or ''

        for _, roleID in ipairs(roleIDs) do
            if tostring(roleID) == configuredRoleId then
                chosenTag = configuredRoleTag
            end
        end
    end

    return chosenTag
end

exports('addMessage', function(target, message)
    if not message then
        message = target
        target = -1
    end

    if not target or not message then
        return
    end

    TriggerClientEvent('chat:addMessage', target, message)
end)

local function sendAnnouncementInternal(message, author)
    if not message or message == '' then
        return false
    end

    routeMessage(0, author or 'Server', message, 'announcements', true)
    return true
end

exports('sendAnnouncement', sendAnnouncementInternal)

AddEventHandler('bcc-chat:sendAnnouncement', function(message, author)
    local invokingResource = GetInvokingResource()

    if not invokingResource then
        return
    end

    sendAnnouncementInternal(message, author or invokingResource)
end)

local hooks = {}
local hookIdx = 1

exports('registerMessageHook', function(hook)
    local resource = GetInvokingResource()
    hooks[hookIdx + 1] = {
        fn = hook,
        resource = resource
    }

    hookIdx = hookIdx + 1
end)

local modes = {}

local builtinModes = {
    {
        name = 'ooc',
        displayKey = 'ooc',
        color = '#f2d8bf',
        isChannel = true,
        cb = function(source, outMessage, hookRef)
            hookRef.setRouting(-1)
            hookRef.updateMessage({
                template = '<span style="color: {{channelColor}}; font-weight: 700;">[{{channel}}]</span> {}',
                params = {
                    channel = _U('channel_ooc'),
                    channelColor = '#f2d8bf'
                }
            })
        end
    },
    {
        name = 'admin',
        displayKey = 'admin',
        color = '#ff7d7d',
        seObject = Config.AdminAce,
        readRoles = Config.AdminDiscordRoles,
        sendSeObject = Config.AdminAce,
        sendRoles = Config.AdminDiscordRoles,
        isChannel = true,
        cb = function(source, outMessage, hookRef)
            hookRef.setRouting(getMatchingPlayersForMode('admin'))
            hookRef.updateMessage({
                template = '<span style="color: {{channelColor}}; font-weight: 700;">[{{channel}}]</span> {}',
                params = {
                    channel = _U('channel_admin'),
                    channelColor = '#ff7d7d'
                }
            })
        end
    },
    {
        name = 'announcements',
        displayKey = 'announcements',
        color = '#ffd166',
        sendSeObject = Config.AdminAce,
        sendRoles = Config.AdminDiscordRoles,
        isChannel = true,
        cb = function(source, outMessage, hookRef)
            hookRef.setRouting(-1)
            hookRef.updateMessage({
                template = '<span style="color: {{channelColor}}; font-weight: 700;">[{{channel}}]</span> {}',
                params = {
                    channel = _U('channel_announcement'),
                    channelColor = '#ffd166'
                }
            })
        end
    },
    {
        name = 'other',
        displayKey = 'other',
        color = '#9ad1ff',
        isChannel = true,
        cb = function(source, outMessage, hookRef)
            hookRef.setRouting(-1)
            hookRef.updateMessage({
                template = '<span style="color: {{channelColor}}; font-weight: 700;">[{{channel}}]</span> {}',
                params = {
                    channel = _U('channel_other'),
                    channelColor = '#9ad1ff'
                }
            })
        end
    }
}

local function getMatchingPlayers(seObject)
    local players = GetPlayers()
    local retval = {}

    for index, playerId in ipairs(players) do
        if IsPlayerAceAllowed(playerId, seObject) then
            retval[#retval + 1] = playerId
        end
    end

    return retval
end

function getMatchingPlayersForMode(modeName)
    local players = GetPlayers()
    local retval = {}
    local modeData = modes[modeName]

    if not modeData then
        return retval
    end

    for _, playerId in ipairs(players) do
        if playerMatchesAccess(playerId, modeData.seObject, modeData.readRoles) then
            retval[#retval + 1] = playerId
        end
    end

    return retval
end

local function ensureChatTable()
    MySQL.query.await(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `mode` VARCHAR(64) NULL,
            `author` VARCHAR(255) NULL,
            `author_display` VARCHAR(255) NULL,
            `role_tag` VARCHAR(255) NULL,
            `args` LONGTEXT NOT NULL,
            `color` VARCHAR(64) NULL,
            `template` LONGTEXT NULL,
            `templateId` VARCHAR(128) NULL,
            `params` LONGTEXT NULL,
            `multiline` TINYINT(1) NOT NULL DEFAULT 1,
            `visibility` VARCHAR(64) NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            INDEX `idx_bcc_chat_mode_id` (`mode`, `id`),
            INDEX `idx_bcc_chat_created` (`created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(CHAT_TABLE))
end

local function ensureRoleTables()
    MySQL.query.await(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `role_id` VARCHAR(64) NOT NULL,
            `label` VARCHAR(120) NOT NULL,
            `tag` VARCHAR(255) NOT NULL,
            `priority` INT NOT NULL DEFAULT 0,
            `enabled` TINYINT(1) NOT NULL DEFAULT 1,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uq_bcc_chat_roles_role_id` (`role_id`),
            INDEX `idx_bcc_chat_roles_enabled_priority` (`enabled`, `priority`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(ROLE_TABLE))

    MySQL.query.await(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(120) NOT NULL,
            `charid` INT NULL,
            `role_id` VARCHAR(64) NOT NULL,
            `assigned_by` VARCHAR(120) NULL,
            `assigned_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uq_bcc_chat_player_roles_character` (`identifier`, `charid`),
            INDEX `idx_bcc_chat_player_roles_role_id` (`role_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(PLAYER_ROLE_TABLE))

    MySQL.query.await(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(120) NOT NULL,
            `charid` INT NULL,
            `display_mode` VARCHAR(64) NOT NULL DEFAULT 'player_name',
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uq_bcc_chat_name_preferences_character` (`identifier`, `charid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(DISPLAY_NAME_TABLE))
end

local function isColorCode(value)
    local color = trim(value)
    return color and (color:match('^%^%d$') or color:match('^%^#%x%x%x%x%x%x$')) or false
end

local function discordColorToChatColor(color)
    local numericColor = tonumber(color)

    if not numericColor or numericColor <= 0 then
        return nil
    end

    return ('^#%06X'):format(numericColor)
end

local function buildRoleTag(labelOrTag, color)
    local label = trim(labelOrTag)
    local colorCode = trim(color)

    if not label then
        return nil
    end

    if isColorCode(colorCode) then
        return ('%s%s | ^0'):format(colorCode, label)
    end

    return tostring(labelOrTag)
end

local function roleLabelFromTag(roleId, tag)
    for _, configuredRole in ipairs(Config.DiscordRoleList or {}) do
        if tostring(configuredRole[1]) == tostring(roleId) then
            if isColorCode(configuredRole[3]) then
                return tostring(configuredRole[2])
            end

            if configuredRole[3] then
                return tostring(configuredRole[3])
            end
        end
    end

    local cleanTag = tostring(tag or ''):gsub('%^#%x%x%x%x%x%x', ''):gsub('%^%d', ''):gsub('|', ''):gsub('%s+$', '')
    return trim(cleanTag) or tostring(roleId)
end

local function buildConfiguredRoleOverrides()
    local overrides = {}

    for index, configuredRole in ipairs(Config.DiscordRoleList or {}) do
        local roleId = trim(configuredRole[1])
        local tag = buildRoleTag(configuredRole[2], configuredRole[3])

        if roleId and tag and tag ~= '' then
            overrides[roleId] = {
                role_id = roleId,
                label = roleLabelFromTag(roleId, tag),
                tag = tag,
                priority = index
            }
        end
    end

    return overrides
end

local function upsertChatRole(role)
    MySQL.insert.await(
        ([[
            INSERT INTO `%s` (`role_id`, `label`, `tag`, `priority`, `enabled`)
            VALUES (?, ?, ?, ?, 1)
            ON DUPLICATE KEY UPDATE
                `label` = VALUES(`label`),
                `tag` = VALUES(`tag`),
                `priority` = VALUES(`priority`),
                `enabled` = 1
        ]]):format(ROLE_TABLE),
        { role.role_id, role.label, role.tag, role.priority or 0 }
    )
end

local function fetchDiscordGuildRoles()
    if not Config.DiscordGuildId or Config.DiscordGuildId == '' then
        return nil
    end

    if not Config.DiscordBotToken or Config.DiscordBotToken == '' then
        return nil
    end

    local promiseHandle = promise.new()
    local url = ('https://discord.com/api/guilds/%s/roles'):format(Config.DiscordGuildId)

    PerformHttpRequest(url, function(statusCode, responseBody)
        if statusCode ~= 200 then
            print(('[bcc-chat] Discord role sync failed: HTTP %s'):format(statusCode or 'unknown'))
            promiseHandle:resolve(nil)
            return
        end

        local ok, roles = pcall(json.decode, responseBody)
        if not ok or type(roles) ~= 'table' then
            print('[bcc-chat] Discord role sync failed: invalid Discord response.')
            promiseHandle:resolve(nil)
            return
        end

        promiseHandle:resolve(roles)
    end, 'GET', '', {
        ['Content-Type'] = 'application/json',
        ['Authorization'] = 'Bot ' .. Config.DiscordBotToken
    })

    return Citizen.Await(promiseHandle)
end

local function shouldSyncDiscordRole(role)
    if not role or not role.id then
        return false
    end

    if Config.AutoSyncDiscordSkipEveryoneRole ~= false and tostring(role.id) == tostring(Config.DiscordGuildId) then
        return false
    end

    if Config.AutoSyncDiscordSkipManagedRoles ~= false and role.managed then
        return false
    end

    return true
end

local function seedConfiguredRoles()
    local overrides = buildConfiguredRoleOverrides()

    if Config.AutoSyncDiscordRoles then
        local discordRoles = fetchDiscordGuildRoles()

        if discordRoles then
            for _, discordRole in ipairs(discordRoles) do
                if shouldSyncDiscordRole(discordRole) then
                    local roleId = tostring(discordRole.id)
                    local override = overrides[roleId]
                    local label = override and override.label or trim(discordRole.name)
                    local color = Config.AutoSyncDiscordRoleColors ~= false and discordColorToChatColor(discordRole.color) or nil
                    local tag = override and override.tag or buildRoleTag(label, color or '^7')

                    if label and tag then
                        upsertChatRole({
                            role_id = roleId,
                            label = label,
                            tag = tag,
                            priority = tonumber(discordRole.position) or 0
                        })
                    end
                end
            end
        end
    end

    for _, configuredRole in pairs(overrides) do
        configuredRole.priority = getConfiguredRolePriority(configuredRole.role_id)
        upsertChatRole(configuredRole)
    end

    clearRoleCaches()
end

local function ensureChatColumn(name, definition)
    local exists = MySQL.single.await(('SHOW COLUMNS FROM `%s` LIKE ?'):format(CHAT_TABLE), { name })
    if not exists then
        MySQL.update.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(CHAT_TABLE, name, definition))
    end
end

local function encodeJson(value)
    if value == nil then
        return nil
    end

    return json.encode(value)
end

local function decodeJson(value, fallback)
    if not value or value == '' then
        return fallback
    end

    local ok, decoded = pcall(json.decode, value)
    if ok and decoded ~= nil then
        return decoded
    end

    return fallback
end

local function saveMessageToHistory(message, visibility)
    MySQL.insert.await(
        ('INSERT INTO `%s` (`mode`, `author`, `author_display`, `role_tag`, `args`, `color`, `template`, `templateId`, `params`, `multiline`, `visibility`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'):format(CHAT_TABLE),
        {
            message.mode,
            message.author or nil,
            message.authorDisplay or (message.args and message.args[1] or nil),
            message.roleTag or nil,
            encodeJson(message.args or {}),
            encodeJson(message.color),
            message.template,
            message.templateId,
            encodeJson(message.params),
            message.multiline and 1 or 0,
            visibility
        }
    )
end

local function canPlayerSeeMode(src, modeName)
    if not modeName then
        return true
    end

    local modeData = modes[modeName]
    if not modeData then
        return true
    end

    if not playerMatchesAccess(src, modeData.seObject, modeData.readRoles) then
        return false
    end

    return true
end

local function sendHistoryToPlayer(src)
    local rows = MySQL.query.await(
        ('SELECT `mode`, `author`, `author_display`, `role_tag`, `args`, `color`, `template`, `templateId`, `params`, `multiline`, UNIX_TIMESTAMP(`created_at`) AS `created_at_unix` FROM `%s` ORDER BY `id` DESC LIMIT ?'):format(CHAT_TABLE),
        { HISTORY_LIMIT }
    )

    if not rows or #rows == 0 then
        return
    end

    for index = #rows, 1, -1 do
        local row = rows[index]

        if canPlayerSeeMode(src, row.mode) then
            TriggerClientEvent('chat:addMessage', src, {
                mode = row.mode or 'all',
                args = decodeJson(row.args, {}),
                color = decodeJson(row.color, nil),
                template = row.template,
                templateId = row.templateId,
                params = decodeJson(row.params, nil),
                multiline = row.multiline == 1,
                author = row.author,
                authorDisplay = row.author_display,
                roleTag = row.role_tag,
                createdAt = normalizeMessageTimestamp(row.created_at_unix)
            })
        end
    end
end

local function registerModeInternal(modeData, resource)
    if not modeData.name or not (modeData.displayName or modeData.displayKey) or not modeData.cb then
        return false
    end

    local displayName = modeData.displayName or _U(modeData.displayKey)

    modes[modeData.name] = modeData
    modes[modeData.name].resource = resource

    local clObj = {
        name = modeData.name,
        displayName = displayName,
        color = modeData.color or '#fff',
        isChannel = modeData.isChannel,
        isGlobal = modeData.isGlobal,
    }

    if not modeData.seObject then
        TriggerClientEvent('chat:addMode', -1, clObj)
    else
        for index, playerId in ipairs(getMatchingPlayersForMode(modeData.name)) do
            TriggerClientEvent('chat:addMode', playerId, clObj)
        end
    end

    return true
end

exports('registerMode', function(modeData)
    local resource = GetInvokingResource()
    return registerModeInternal(modeData, resource)
end)

local function unregisterHooks(resource)
    local toRemove = {}

    for key, value in pairs(hooks) do
        if value.resource == resource then
            table.insert(toRemove, key)
        end
    end

    for _, value in ipairs(toRemove) do
        hooks[value] = nil
    end

    toRemove = {}

    for key, value in pairs(modes) do
        if value.resource == resource then
            table.insert(toRemove, key)
        end
    end

    for _, value in ipairs(toRemove) do
        TriggerClientEvent('chat:removeMode', -1, {
            name = value
        })

        modes[value] = nil
    end
end

routeMessage = function(source, author, message, mode, fromConsole)
    mode = mode or 'all'

    if source >= 1 then
        author = getChatAuthorName(source) or GetPlayerName(source)
    end

    local outMessage = {
        color = { 255, 255, 255 },
        multiline = true,
        args = { message },
        mode = mode,
        createdAt = os.time()
    }

    if author ~= '' then
        local roleTag = ''
        local authorDisplay = author

        if source >= 1 and mode ~= 'admin' and mode ~= 'announcements' then
            roleTag = getPlayerDiscordTag(source)
            if roleTag and roleTag ~= '' then
                authorDisplay = roleTag .. author
            end
        end

        outMessage.author = author
        outMessage.authorDisplay = authorDisplay
        outMessage.roleTag = roleTag
        outMessage.args = { authorDisplay, message }
    end

    if mode and modes[mode] then
        local modeData = modes[mode]

        if not playerMatchesAccess(source, modeData.sendSeObject, modeData.sendRoles) then
            return
        end

        if not playerMatchesAccess(source, modeData.seObject, modeData.readRoles) then
            return
        end
    end

    local messageCanceled = false
    local routingTarget = -1
    local historyVisibility = mode

    local hookRef = {
        updateMessage = function(t)
            for key, value in pairs(t) do
                if key == 'template' then
                    outMessage.template = value:gsub('%{%}', outMessage.template or '@default')
                elseif key == 'params' then
                    if not outMessage.params then
                        outMessage.params = {}
                    end

                    for paramKey, paramValue in pairs(value) do
                        outMessage.params[paramKey] = paramValue
                    end
                else
                    outMessage[key] = value
                end
            end
        end,

        cancel = function()
            messageCanceled = true
        end,

        setSeObject = function(object)
            routingTarget = getMatchingPlayers(object)
            historyVisibility = object
        end,

        setRouting = function(target)
            routingTarget = target
        end
    }

    for hookIndex, hook in pairs(hooks) do
        if hook.fn then
            hook.fn(source, outMessage, hookRef)
        end
    end

    if modes[mode] then
        modes[mode].cb(source, outMessage, hookRef)
    end

    if messageCanceled then
        return
    end

    TriggerEvent('chatMessage', source, #outMessage.args > 1 and outMessage.args[1] or '', outMessage.args[#outMessage.args])

    if not WasEventCanceled() then
        if type(routingTarget) ~= 'table' then
            TriggerClientEvent('chat:addMessage', routingTarget, outMessage)
        else
            for index, playerId in ipairs(routingTarget) do
                TriggerClientEvent('chat:addMessage', playerId, outMessage)
            end
        end
    end

    saveMessageToHistory(outMessage, historyVisibility)

    if not fromConsole then
        local modeLabel = ''

        if modes[mode] then
            local resolvedName = modes[mode].displayName or (modes[mode].displayKey and _U(modes[mode].displayKey)) or mode
            modeLabel = ' (' .. resolvedName .. ')'
        end

        print(author .. '^7' .. modeLabel .. ': ' .. message .. '^7')
    end
end

AddEventHandler('_chat:messageEntered', function(author, color, message, mode)
    if not message or not author then
        return
    end

    routeMessage(source, author, message, mode)
end)

AddEventHandler('__cfx_internal:commandFallback', function(command)
    TriggerClientEvent('chat:addMessage', source, {
        args = { 'System', ('Unknown command: /%s'):format(command) }
    })

    CancelEvent()
end)

AddEventHandler('playerJoining', function()
    if not next(modes) then
        return
    end

    local src = source

    for modeName, modeData in pairs(modes) do
        if playerMatchesAccess(src, modeData.seObject, modeData.readRoles) then
            TriggerClientEvent('chat:addMode', src, {
                name = modeData.name,
                displayName = modeData.displayName or _U(modeData.displayKey),
                color = modeData.color or '#fff',
                isChannel = modeData.isChannel,
                isGlobal = modeData.isGlobal,
            })
        end
    end
end)

AddEventHandler('chat:init', function()
    local src = source

    for modeName, modeData in pairs(modes) do
        if playerMatchesAccess(src, modeData.seObject, modeData.readRoles) then
            TriggerClientEvent('chat:addMode', src, {
                name = modeData.name,
                displayName = modeData.displayName or _U(modeData.displayKey),
                color = modeData.color or '#fff',
                isChannel = modeData.isChannel,
                isGlobal = modeData.isGlobal,
            })
        end
    end

    sendHistoryToPlayer(src)
end)

AddEventHandler('onResourceStop', function(resource)
    unregisterHooks(resource)
end)

local function sendSystemMessage(src, message)
    if src == 0 then
        print(('[bcc-chat] %s'):format(message))
        return
    end

    TriggerClientEvent('chat:addMessage', src, {
        mode = 'all',
        args = { message }
    })
end

local function getPlayerDisplayName(src, identity)
    local parts = {}

    if identity and identity.firstname then
        parts[#parts + 1] = identity.firstname
    end

    if identity and identity.lastname then
        parts[#parts + 1] = identity.lastname
    end

    local characterName = table.concat(parts, ' ')
    if characterName ~= '' then
        return ('%s (%s)'):format(characterName, GetPlayerName(src) or src)
    end

    return GetPlayerName(src) or ('ID %s'):format(src)
end

local function buildRoleMenuPayload(src)
    local roles = getChatRoles()
    local players = {}

    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        local identity = getPlayerIdentity(target)

        if identity and identity.identifier then
            local assignedRole = getAssignedChatRole(identity)
            players[#players + 1] = {
                source = target,
                name = getPlayerDisplayName(target, identity),
                identifier = identity.identifier,
                charid = identity.charid,
                roleId = assignedRole and assignedRole.role_id or nil,
                roleLabel = assignedRole and assignedRole.label or nil,
                roleTag = assignedRole and assignedRole.tag or nil
            }
        end
    end

    table.sort(players, function(a, b)
        return tostring(a.name):lower() < tostring(b.name):lower()
    end)

    return {
        isAdmin = playerMatchesAccess(src, Config.AdminAce, Config.AdminDiscordRoles),
        roles = roles,
        players = players
    }
end

local function openRoleMenu(src)
    if src == 0 then
        print('[bcc-chat] /chatroles can only open a menu in game.')
        return
    end

    if not playerMatchesAccess(src, Config.AdminAce, Config.AdminDiscordRoles) then
        sendSystemMessage(src, '^1You do not have permission to manage chat roles.')
        return
    end

    TriggerClientEvent('bcc-chat:openRoleMenu', src, buildRoleMenuPayload(src))
end

local function buildDisplayNameMenuPayload(src)
    local identity = getPlayerIdentity(src)
    local currentMode = getDisplayNamePreference(identity)
    local playerName = GetPlayerName(src) or ('ID %s'):format(src)
    local characterName = getCharacterFullName(identity)

    return {
        currentMode = currentMode,
        preview = {
            player_name = playerName,
            character_name = characterName or playerName,
            character_with_player = characterName and ('%s (%s)'):format(characterName, playerName) or playerName
        }
    }
end

local function openDisplayNameMenu(src)
    if src == 0 then
        print('[bcc-chat] /chatname can only open a menu in game.')
        return
    end

    TriggerClientEvent('bcc-chat:openDisplayNameMenu', src, buildDisplayNameMenuPayload(src))
end

AddEventHandler('bcc-chat:requestRoleMenu', function()
    openRoleMenu(source)
end)

AddEventHandler('bcc-chat:requestDisplayNameMenu', function()
    openDisplayNameMenu(source)
end)

AddEventHandler('bcc-chat:setPlayerRole', function(targetSource, roleId)
    local src = source

    if not playerMatchesAccess(src, Config.AdminAce, Config.AdminDiscordRoles) then
        sendSystemMessage(src, '^1You do not have permission to manage chat roles.')
        return
    end

    local target = normalizeSourceId(targetSource)
    local identity = getPlayerIdentity(target)
    local role = getChatRoleById(roleId)

    if not target or not identity or not role then
        sendSystemMessage(src, '^1Could not assign that chat role.')
        return
    end

    local adminIdentity = getPlayerIdentity(src)
    MySQL.insert.await(
        ([[
            INSERT INTO `%s` (`identifier`, `charid`, `role_id`, `assigned_by`)
            VALUES (?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                `role_id` = VALUES(`role_id`),
                `assigned_by` = VALUES(`assigned_by`),
                `assigned_at` = CURRENT_TIMESTAMP
        ]]):format(PLAYER_ROLE_TABLE),
        {
            identity.identifier,
            identity.charid,
            role.role_id,
            adminIdentity and adminIdentity.identifier or ('source:' .. tostring(src))
        }
    )

    clearRoleCaches(identity.identifier, identity.charid)
    sendSystemMessage(src, ('^2Assigned %s to %s.'):format(role.label, GetPlayerName(target) or target))
    TriggerClientEvent('bcc-chat:openRoleMenu', src, buildRoleMenuPayload(src))
end)

AddEventHandler('bcc-chat:clearPlayerRole', function(targetSource)
    local src = source

    if not playerMatchesAccess(src, Config.AdminAce, Config.AdminDiscordRoles) then
        sendSystemMessage(src, '^1You do not have permission to manage chat roles.')
        return
    end

    local target = normalizeSourceId(targetSource)
    local identity = getPlayerIdentity(target)

    if not target or not identity then
        sendSystemMessage(src, '^1Could not clear that chat role.')
        return
    end

    MySQL.update.await(
        ('DELETE FROM `%s` WHERE `identifier` = ? AND (`charid` = ? OR `charid` IS NULL)'):format(PLAYER_ROLE_TABLE),
        { identity.identifier, identity.charid }
    )

    clearRoleCaches(identity.identifier, identity.charid)
    sendSystemMessage(src, ('^2Cleared chat role for %s.'):format(GetPlayerName(target) or target))
    TriggerClientEvent('bcc-chat:openRoleMenu', src, buildRoleMenuPayload(src))
end)

AddEventHandler('bcc-chat:setDisplayNameMode', function(mode)
    local src = source
    local chosenMode = trim(mode)

    if not DISPLAY_NAME_MODES[chosenMode] then
        sendSystemMessage(src, '^1' .. _U('chat_name_invalid'))
        return
    end

    local identity = getPlayerIdentity(src)

    if not identity or not identity.identifier then
        sendSystemMessage(src, '^1' .. _U('chat_name_save_failed'))
        return
    end

    MySQL.insert.await(
        ([[
            INSERT INTO `%s` (`identifier`, `charid`, `display_mode`)
            VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE
                `display_mode` = VALUES(`display_mode`),
                `updated_at` = CURRENT_TIMESTAMP
        ]]):format(DISPLAY_NAME_TABLE),
        {
            identity.identifier,
            identity.charid,
            chosenMode
        }
    )

    clearDisplayNamePreferenceCache(identity.identifier, identity.charid)
    sendSystemMessage(src, '^2' .. _U('chat_name_updated'))
    TriggerClientEvent('bcc-chat:openDisplayNameMenu', src, buildDisplayNameMenuPayload(src))
end)

RegisterCommand('chatroles', function(source)
    openRoleMenu(source)
end, false)

RegisterCommand('chatname', function(source)
    openDisplayNameMenu(source)
end, false)

RegisterCommand('clearchathistory', function(source)
    local src = source

    if src ~= 0 and not playerMatchesAccess(src, Config.AdminAce, Config.AdminDiscordRoles) then
        TriggerClientEvent('chat:addMessage', src, {
            mode = 'all',
            args = { '^1You do not have permission to clear chat history.' }
        })
        return
    end

    MySQL.query.await(('DELETE FROM `%s`'):format(CHAT_TABLE))
    TriggerClientEvent('chat:clear', -1)

    if src == 0 then
        print('[bcc-chat] Chat history cleared.')
    else
        TriggerClientEvent('chat:addMessage', src, {
            mode = 'all',
            args = { '^2Chat history cleared.' }
        })
    end
end, false)

RegisterCommand('testannounce', function(source, args)
    local src = source

    if src ~= 0 and not playerMatchesAccess(src, Config.AdminAce, Config.AdminDiscordRoles) then
        TriggerClientEvent('chat:addMessage', src, {
            mode = 'all',
            args = { '^1You do not have permission to send announcements.' }
        })
        return
    end

    local text = table.concat(args or {}, ' ')
    if text == '' then
        if src == 0 then
            print('[bcc-chat] Usage: testannounce <message>')
        else
            TriggerClientEvent('chat:addMessage', src, {
                mode = 'all',
                args = { '^3Usage:^7 /testannounce <message>' }
            })
        end
        return
    end

    local author = src == 0 and 'Server' or GetPlayerName(src)
    routeMessage(src, author, text, 'announcements', src == 0)
end, false)

CreateThread(function()
    ensureChatTable()
    ensureRoleTables()
    seedConfiguredRoles()
    ensureChatColumn('author_display', 'VARCHAR(255) NULL AFTER `author`')
    ensureChatColumn('role_tag', 'VARCHAR(255) NULL AFTER `author_display`')

    local resource = GetCurrentResourceName()

    for index, modeData in ipairs(builtinModes) do
        registerModeInternal(modeData, resource)
    end
end)
