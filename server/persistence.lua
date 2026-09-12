ChatPersistence = {}

local ready = false

local function failure(reason)
    return ChatResults.Err('persistence_unavailable',
        FeatherCore.Locale.translate(0, 'errorPersistenceUnavailable'), {
            reason = tostring(reason)
        })
end

local function retentionDays(channel)
    if channel.routing and channel.routing.type == 'explicit' then
        return 0
    end
    local configured = Config.Persistence and Config.Persistence.retentionDays or {}
    local exact = tonumber(configured[channel.channelKey])
    if exact then return exact end

    local variant = channel.presentation and channel.presentation.variant
    local routing = channel.routing and channel.routing.type
    if channel.channelKey == 'staff' or variant == 'staff' then
        return tonumber(configured.staff) or 0
    end
    if variant == 'organization' then
        return tonumber(configured.organization) or 0
    end
    if routing == 'proximity' then
        return tonumber(configured.proximity) or 0
    end
    if routing == 'global' then
        return tonumber(configured.global) or 0
    end
    return tonumber(configured.default) or 0
end

function ChatPersistence.Initialize()
    local migrations = ChatMigrations.Run()
    if not migrations.ok then return migrations end

    local called, recovered = pcall(function()
        MySQL.update.await([[UPDATE `bcc_chat_mutes`
            SET `status` = 'expired', `revision` = `revision` + 1
            WHERE `status` = 'active' AND `expires_at` IS NOT NULL AND `expires_at` <= ?]],
            { os.time() })
        MySQL.update.await('DELETE FROM `bcc_chat_messages` WHERE `expires_at` <= ?', { os.time() })
        if Config.Persistence.messages then
            return tonumber(MySQL.scalar.await(
                'SELECT COALESCE(MAX(`sequence`), 0) FROM `bcc_chat_messages`')) or 0
        end
        return 0
    end)
    if not called then return failure(recovered) end

    ready = true
    return ChatResults.Ok({ migrations = migrations.value, maxSequence = recovered })
end

function ChatPersistence.IsReady()
    return ready
end

function ChatPersistence.LoadActiveMutes()
    if not Config.Persistence.mutes then return ChatResults.Ok({}) end
    if not ready then return failure('not_ready') end

    local called, rows = pcall(function()
        return MySQL.query.await([[SELECT `mute_id`, `character_id`, `scope`, `channel_key`,
            `reason_code`, `issued_by_character_id`, `issued_by_resource`, `starts_at`,
            `expires_at`, `revision`
            FROM `bcc_chat_mutes`
            WHERE `status` = 'active' AND (`expires_at` IS NULL OR `expires_at` > ?)]],
            { os.time() }) or {}
    end)
    if not called then return failure(rows) end

    local mutes = {}
    for _, row in ipairs(rows) do
        mutes[#mutes + 1] = {
            muteId = row.mute_id,
            characterId = row.character_id,
            scope = row.scope,
            channelKey = row.channel_key,
            reasonCode = row.reason_code,
            issuedByCharacterId = row.issued_by_character_id,
            ownerResource = row.issued_by_resource,
            issuedAt = tonumber(row.starts_at),
            expiresAt = tonumber(row.expires_at),
            revision = tonumber(row.revision) or 1
        }
    end
    return ChatResults.Ok(mutes)
end

function ChatPersistence.InsertMute(mute)
    if not Config.Persistence.mutes then return ChatResults.Ok({ persisted = false }) end
    if not ready then return failure('not_ready') end

    local called, problem = pcall(function()
        MySQL.insert.await([[INSERT INTO `bcc_chat_mutes`
            (`mute_id`, `character_id`, `scope`, `channel_key`, `reason_code`, `status`,
             `issued_by_character_id`, `issued_by_resource`, `starts_at`, `expires_at`, `revision`)
            VALUES (?, ?, ?, ?, ?, 'active', ?, ?, ?, ?, ?)]], {
            mute.muteId,
            mute.characterId,
            mute.scope,
            mute.channelKey,
            mute.reasonCode,
            mute.issuedByCharacterId,
            mute.ownerResource,
            mute.issuedAt,
            mute.expiresAt,
            mute.revision
        })
    end)
    return called and ChatResults.Ok({ persisted = true }) or failure(problem)
end

function ChatPersistence.RevokeMute(mute, actorCharacterId)
    if not Config.Persistence.mutes then return ChatResults.Ok({ persisted = false }) end
    if not ready then return failure('not_ready') end

    local called, affected = pcall(function()
        return MySQL.update.await([[UPDATE `bcc_chat_mutes`
            SET `status` = 'revoked', `revoked_at` = ?, `revoked_by_character_id` = ?,
                `revision` = `revision` + 1
            WHERE `mute_id` = ? AND `revision` = ? AND `status` = 'active']], {
            os.time(), actorCharacterId, mute.muteId, mute.revision
        })
    end)
    if not called then return failure(affected) end
    if tonumber(affected) ~= 1 then
        return ChatResults.Err('revision_conflict',
            FeatherCore.Locale.translate(0, 'errorMuteRevision'))
    end
    return ChatResults.Ok({ persisted = true })
end

function ChatPersistence.ExpireMute(mute)
    if not Config.Persistence.mutes or not ready then return ChatResults.Ok({ persisted = false }) end
    local called, problem = pcall(function()
        MySQL.update.await([[UPDATE `bcc_chat_mutes`
            SET `status` = 'expired', `revision` = `revision` + 1
            WHERE `mute_id` = ? AND `revision` = ? AND `status` = 'active']],
            { mute.muteId, mute.revision })
    end)
    return called and ChatResults.Ok({ persisted = true }) or failure(problem)
end

function ChatPersistence.SaveMessage(channel, message)
    if not Config.Persistence.messages then return ChatResults.Ok({ persisted = false }) end
    if not ready then return failure('not_ready') end

    local days = retentionDays(channel)
    if days <= 0 then return ChatResults.Ok({ persisted = false, retentionDays = 0 }) end

    local author = type(message.author) == 'table' and message.author or {}
    local presentation = type(message.presentation) == 'table' and message.presentation or {}
    local reference = type(message.reference) == 'table' and message.reference or {}
    local called, problem = pcall(function()
        MySQL.insert.await([[INSERT INTO `bcc_chat_messages`
            (`message_id`, `channel_key`, `kind`, `author_character_id`, `author_display_name`,
             `author_badge`, `presentation_variant`, `normalized_text`, `reference_id`,
             `sequence`, `created_at`, `expires_at`)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
            message.messageId,
            message.channelKey,
            message.kind,
            author.characterId,
            author.displayName,
            author.badge,
            presentation.variant or 'system',
            message.body.text,
            reference.id,
            message.sequence,
            message.createdAt,
            message.createdAt + (days * 86400)
        })
    end)
    return called and ChatResults.Ok({ persisted = true, retentionDays = days }) or failure(problem)
end

function ChatPersistence.ListMessages(channel, beforeSequence, requestedLimit)
    if not Config.Persistence.messages then
        return ChatResults.Err('feature_disabled', FeatherCore.Locale.translate(0, 'errorHistoryDisabled'))
    end
    if not ready then return failure('not_ready') end
    if retentionDays(channel) <= 0 then return ChatResults.Ok({ messages = {}, nextSequence = nil }) end

    local limit = math.min(math.max(1, math.floor(tonumber(requestedLimit)
        or Config.Persistence.historyPageSize)), Config.Persistence.historyPageSize)
    local before = tonumber(beforeSequence)
    local query = [[SELECT `message_id`, `channel_key`, `kind`, `author_character_id`,
        `author_display_name`, `author_badge`, `presentation_variant`, `normalized_text`,
        `reference_id`, `sequence`, `created_at`
        FROM `bcc_chat_messages`
        WHERE `channel_key` = ? AND `expires_at` > ?]]
    local parameters = { channel.channelKey, os.time() }
    if before and before > 0 then
        query = query .. ' AND `sequence` < ?'
        parameters[#parameters + 1] = math.floor(before)
    end
    query = query .. ' ORDER BY `sequence` DESC LIMIT ?'
    parameters[#parameters + 1] = limit

    local called, rows = pcall(function() return MySQL.query.await(query, parameters) or {} end)
    if not called then return failure(rows) end

    local messages = {}
    for index = #rows, 1, -1 do
        local row = rows[index]
        messages[#messages + 1] = {
            messageId = row.message_id,
            channelKey = row.channel_key,
            kind = row.kind,
            author = row.author_character_id and {
                characterId = row.author_character_id,
                displayName = row.author_display_name,
                badge = row.author_badge
            } or { displayName = row.author_display_name },
            body = { text = row.normalized_text, format = 'plain' },
            presentation = { variant = row.presentation_variant },
            reference = row.reference_id and { type = 'chat.message', id = row.reference_id } or nil,
            sequence = tonumber(row.sequence),
            createdAt = tonumber(row.created_at)
        }
    end
    local nextSequence = #rows == limit and tonumber(rows[#rows].sequence) or nil
    return ChatResults.Ok({ messages = messages, nextSequence = nextSequence })
end

function ChatPersistence.Cleanup()
    if not ready then return failure('not_ready') end
    local called, result = pcall(function()
        local expiredMutes = MySQL.update.await([[UPDATE `bcc_chat_mutes`
            SET `status` = 'expired', `revision` = `revision` + 1
            WHERE `status` = 'active' AND `expires_at` IS NOT NULL AND `expires_at` <= ?]],
            { os.time() })
        local deletedMessages = MySQL.update.await(
            'DELETE FROM `bcc_chat_messages` WHERE `expires_at` <= ?', { os.time() })
        return { expiredMutes = tonumber(expiredMutes) or 0, deletedMessages = tonumber(deletedMessages) or 0 }
    end)
    return called and ChatResults.Ok(result) or failure(result)
end
