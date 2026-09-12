ChatMigrations = {}

local definitions = {
    {
        id = '001_chat_persistence',
        statements = {
            [[CREATE TABLE IF NOT EXISTS `bcc_chat_mutes` (
                `mute_id` CHAR(36) NOT NULL,
                `character_id` CHAR(36) NOT NULL,
                `scope` VARCHAR(32) NOT NULL,
                `channel_key` VARCHAR(96) NULL,
                `reason_code` VARCHAR(64) NOT NULL,
                `status` VARCHAR(16) NOT NULL DEFAULT 'active',
                `issued_by_character_id` CHAR(36) NULL,
                `issued_by_resource` VARCHAR(100) NOT NULL,
                `starts_at` BIGINT UNSIGNED NOT NULL,
                `expires_at` BIGINT UNSIGNED NULL,
                `revoked_at` BIGINT UNSIGNED NULL,
                `revoked_by_character_id` CHAR(36) NULL,
                `revision` BIGINT UNSIGNED NOT NULL DEFAULT 1,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`mute_id`),
                INDEX `idx_bcc_chat_mutes_subject` (`character_id`, `status`, `expires_at`),
                INDEX `idx_bcc_chat_mutes_channel` (`channel_key`, `status`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
            [[CREATE TABLE IF NOT EXISTS `bcc_chat_messages` (
                `message_id` CHAR(36) NOT NULL,
                `channel_key` VARCHAR(96) NOT NULL,
                `kind` VARCHAR(24) NOT NULL,
                `author_character_id` CHAR(36) NULL,
                `author_display_name` VARCHAR(128) NULL,
                `author_badge` VARCHAR(64) NULL,
                `presentation_variant` VARCHAR(32) NOT NULL,
                `normalized_text` TEXT NOT NULL,
                `reference_id` CHAR(36) NULL,
                `sequence` BIGINT UNSIGNED NOT NULL,
                `created_at` BIGINT UNSIGNED NOT NULL,
                `expires_at` BIGINT UNSIGNED NOT NULL,
                PRIMARY KEY (`message_id`),
                INDEX `idx_bcc_chat_messages_channel_sequence` (`channel_key`, `sequence`),
                INDEX `idx_bcc_chat_messages_expiry` (`expires_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]]
        }
    }
}

local function hash(value)
    local result = 2166136261
    for index = 1, #value do
        result = ((result ~ value:byte(index)) * 16777619) & 0xffffffff
    end
    return ('fnv1a32:%08x'):format(result)
end

function ChatMigrations.Run()
    local called, result = pcall(function()
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `bcc_chat_schema_migrations` (
            `id` VARCHAR(100) NOT NULL,
            `checksum` VARCHAR(64) NOT NULL,
            `applied_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

        local applied = {}
        for _, row in ipairs(MySQL.query.await(
            'SELECT `id`, `checksum` FROM `bcc_chat_schema_migrations`') or {}) do
            applied[row.id] = row.checksum
        end

        local appliedCount = 0
        for _, migration in ipairs(definitions) do
            local checksum = hash(table.concat(migration.statements, '\n-- next statement --\n'))
            if applied[migration.id] and applied[migration.id] ~= checksum then
                return ChatResults.Err('migration_checksum_mismatch',
                    FeatherCore.Locale.translate(0, 'errorMigrationChanged'), {
                        migrationId = migration.id,
                        expected = applied[migration.id],
                        actual = checksum
                    })
            end
            if not applied[migration.id] then
                for _, statement in ipairs(migration.statements) do
                    MySQL.query.await(statement)
                end
                MySQL.insert.await(
                    'INSERT INTO `bcc_chat_schema_migrations` (`id`, `checksum`) VALUES (?, ?)',
                    { migration.id, checksum })
                appliedCount = appliedCount + 1
            end
        end
        return ChatResults.Ok({ applied = appliedCount, total = #definitions })
    end)

    if not called then
        return ChatResults.Err('migration_failed', FeatherCore.Locale.translate(0, 'errorMigrationFailed'), {
            reason = tostring(result)
        })
    end
    return result
end
