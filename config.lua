Config = {}

Config.defaultlang = 'en_lang'

Config.HideOlderMessagesHours = 3

-- If you want to use a specific ACE, set it here.
-- Set to nil/false to ignore ACE checks and use AdminIdentifiers below.
Config.AdminAce = false

-- Exact admin identifiers to match your current server.cfg setup.
Config.AdminIdentifiers = {
    -- example 'identifier.fivem:123456785',
    --example 'identifier.steam:1dfmdfhldfd446d3',
}

Config.DiscordGuildId = ''
Config.DiscordBotToken = ''
Config.DiscordRoleCacheSeconds = 60
Config.AutoSyncDiscordRoles = true
Config.AutoSyncDiscordRoleColors = true
Config.AutoSyncDiscordSkipManagedRoles = true
Config.AutoSyncDiscordSkipEveryoneRole = true

Config.AdminDiscordRoles = {
    -- examples '12095760078341510719', -- Moderator
    -- '124073630925445033459', -- Administrator
}

-- Optional overrides for synced Discord chat roles.
-- Leave this empty to use Discord role names/colors automatically.
-- Format: {discordRoleId, "Label", "ColorCode"} builds "ColorCodeLabel | ^0"
-- Example: {'1234567890', 'Sheriff', '^#D8A657'}
Config.DiscordRoleList = {
}
