Config = {}

Config.OpenKey = 'T'
Config.HideOlderMessagesHours = 3
Config.MaximumMessageLength = 500
Config.MaximumLines = 4
Config.MaximumVisibleMessages = 100
Config.MaximumResourceTargets = 256
Config.FadeDelayMs = 10000
Config.SubmitCloses = true

-- Chat owns only universal channels. Staff access is supplied by the
-- Feather Roles adapter below; Jobs and Society register their own channels.
Config.Channels = {
    localSay = { enabled = true, radius = 15.0 },
    localWhisper = { enabled = true, radius = 3.0 },
    localShout = { enabled = true, radius = 35.0 },
    roleplayMe = { enabled = true, radius = 15.0 },
    roleplayDo = { enabled = true, radius = 15.0 },
    globalOoc = { enabled = true },
    staff = { enabled = true }
}

Config.Features = {
    joinAnnouncements = true,
    displayNamePreferences = false,
    rolePresentation = true
}

-- Permission levels are compared with the authoritative active-character role
-- returned by feather-roles. No role state is stored or assigned by BCC Chat.
Config.Permissions = {
    staffRead = 50,
    staffSend = 50,
    muteManage = 50
}

Config.RolePresentation = {
    player = { visible = false, labelKey = 'rolePlayer', color = '#FFFFFF' },
    moderator = { visible = true, labelKey = 'roleModerator', color = '#D8A657' },
    admin = { visible = true, labelKey = 'roleAdmin', color = '#FF7D7D' },
    owner = { visible = true, labelKey = 'roleOwner', color = '#FFD166' }
}

-- Discord can be added later as presentation/relay only. It never authorizes
-- chat actions, and secrets must come from server-only convars.
Config.Discord = {
    enabled = false,
    roleTags = false,
    cacheSeconds = 60,
    guildIdConvar = 'bcc_chat_discord_guild_id',
    botTokenConvar = 'bcc_chat_discord_token',
    roles = {
        -- { roleId = '1234567890', labelKey = 'yourDiscordRoleLabel', color = '#D8A657' }
    }
}

Config.JoinAnnouncement = {
    enabled = true,
    textKey = 'joinWelcome'
}

Config.RateLimit = { windowMs = 10000, maximum = 8 }
Config.ResourceRateLimit = { windowMs = 10000, maximum = 30 }
Config.IdempotencyTtlMs = 60000
Config.Moderation = { maximumMuteSeconds = 31536000 }

-- Mutes survive resource/server restarts by default. Message history is opt-in
-- and retained only for channel classes with a positive retention period.
-- Explicit/targeted channels such as system are never retained because their
-- original recipient set cannot be reconstructed safely during history reads.
Config.Persistence = {
    mutes = true,
    messages = false,
    preferences = false, -- Reserved; Character remains the identity owner.
    historyPageSize = 50,
    cleanupIntervalMinutes = 15,
    retentionDays = {
        default = 0,
        proximity = 0,
        global = 7,
        staff = 30,
        organization = 7
        -- Exact channel keys override classes, for example:
        -- ['society.00000000-0000-4000-8000-000000000000'] = 14
    }
}

Config.Accessibility = {
    fontScale = 1.0,
    density = 'comfortable',
    timestamps = true,
    reducedMotion = false,
    highContrast = false
}

Config.Theme = {
    default = 'bcc.default',
    themes = {
        {
            themeKey = 'bcc.default',
            tokens = {
                background = '#16120FCC',
                panel = '#211A16EE',
                border = '#6E543A',
                primary = '#F4EBDD',
                muted = '#B7AA97',
                danger = '#E06C5F',
                localSpeech = '#F4EBDD',
                roleplay = '#D8B4FE',
                ooc = '#9CC7FF',
                organization = '#E7C66B',
                staff = '#EF8C8C',
                system = '#B7AA97'
            }
        },
        {
            themeKey = 'bcc.high-contrast',
            tokens = {
                background = '#000000F2',
                panel = '#000000FF',
                border = '#FFFFFFFF',
                primary = '#FFFFFFFF',
                muted = '#E6E6E6FF',
                danger = '#FF6B6BFF',
                localSpeech = '#FFFFFFFF',
                roleplay = '#F1C4FFFF',
                ooc = '#B5DCFFFF',
                organization = '#FFE67AFF',
                staff = '#FF9B9BFF',
                system = '#FFFFFFFF'
            }
        }
    }
}
