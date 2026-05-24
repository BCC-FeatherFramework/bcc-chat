# bcc-chat

`bcc-chat` is a Vue-based RedM chat resource with channel tabs, persistent history, localization, Discord-backed role tags, and announcement/admin routing.

## Features

- Vue NUI chat built in the BCC resource structure
- Channel tabs for `General`, `OOC`, `Other`, `Announcements`, and `Admin`
- Persistent chat history stored in MySQL through `oxmysql`
- Old message hiding with a configurable threshold
- English and Romanian localization
- Discord role tag support for visible chat prefixes
- Admin-only `Admin` channel and admin-write-only `Announcements`
- Export/event API for other resources to send announcements

## Dependencies

- `oxmysql`
- `vorp_core`
- `feather-menu`

## Installation

1. Ensure the dependencies start before `bcc-chat`.
2. Add `bcc-chat` to your server config.

Example:

```cfg
ensure oxmysql
ensure vorp_core
ensure feather-menu
ensure bcc-chat
```

## Configuration

Main settings are in [config.lua](/bcc-chat/config.lua).

### Localization

```lua
Config.defaultlang = 'ro_lang'
```

Supported language files:

- `en_lang`
- `ro_lang`

### Old Message Threshold

Messages older than this number of hours are hidden behind the "show older messages" toggle in the UI.

```lua
Config.HideOlderMessagesHours = 3
```

### Admin Access

This resource supports:

- ACE-based access through `Config.AdminAce`
- exact identifier matching through `Config.AdminIdentifiers`
- Discord role-based access through `Config.AdminDiscordRoles`

If you want to ignore ACE and only use identifiers/Discord, leave:

```lua
Config.AdminAce = false
```

### Discord Integration

`bcc-chat` can pull Discord role membership directly and use it for:

- admin access
- announcement access
- visible role prefixes in chat

Relevant config:

```lua
Config.DiscordGuildId = '...'
Config.DiscordBotToken = '...'
Config.DiscordRoleCacheSeconds = 60
Config.AutoSyncDiscordRoles = true
Config.AutoSyncDiscordRoleColors = true
```

If you do not want Discord-backed role tags, disable the related sync settings or clear the role configuration.

## Channels

### General

- public
- used for regular/default chat messages

### OOC

- public
- visible only in the `OOC` tab

### Other

- public
- visible only in the `Other` tab

### Announcements

- readable by everyone
- writable only by configured admins
- can also be sent by other resources through the provided export/event API

### Admin

- readable and writable only by configured admins
- intended for staff/admin communication

## Persistence

Chat messages are stored in MySQL using `oxmysql`.

Table name:

```text
bcc_chat_messages
```

The table is created automatically on resource start if it does not exist.

Saved data includes:

- channel/mode
- author
- rendered author display
- role tag
- args
- color
- template/templateId
- params
- timestamp

## Commands

### `/clearchathistory`

- clears the `bcc_chat_messages` table
- admin only

### `/testannounce <message>`

- sends a real announcement through the announcements channel
- admin only in-game
- usable from server console

## Exports and Events

### Server export

```lua
exports['bcc-chat']:sendAnnouncement(message, author)
```

### Server event

```lua
TriggerEvent('bcc-chat:sendAnnouncement', message, author)
```

These are intended for other resources that need to send messages into the `Announcements` channel.

## Frontend Build

Build the UI with:

```bash
cd /home/redmuser/txData/VORPCore_F822F1.base/resources/[BCC]/bcc-chat/ui
yarn install
yarn build
```

## Notes

- Restart `bcc-chat` after changing config or server-side Lua.
- Rebuild the UI after changing files in `ui/src`.
