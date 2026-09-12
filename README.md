# BCC Chat for Feather

This resource keeps the BCC Vue interface and `bcc-chat` resource name while
implementing Feather Chat Contract 1. It replaces VORP identity, permissions,
and client-authoritative delivery with Feather services.

## Installation

```cfg
ensure oxmysql
ensure feather-core
ensure feather-character
ensure feather-roles
ensure bcc-chat
```

Do not start `feather-chat` at the same time. BCC Chat does not depend on VORP,
`bcc-utils`, Feather Menu, ACE permissions, Discord authorization, or
chat-owned role tables. OxMySQL is used only for the persistence described
below.

Press `T` to open chat. `Config.Channels` controls the universal channels:
`local.say`, `local.whisper`, `local.shout`, `roleplay.me`, `roleplay.do`, and
`ooc.global`. `system` is always present for trusted resource messages. The
optional `staff` channel is visible only to characters whose authoritative
Feather role meets `Config.Permissions.staffRead`.

Jobs, societies, and organizations own their membership and register their own
channels and access providers. Chat does not copy their membership records.

## Feather contracts

Core supplies authenticated session context and RPC transport. Character
supplies authoritative character identity. Feather Roles supplies the active
character role; BCC Chat reads it through the existing public exports and never
assigns or edits roles.

BCC Chat uses the relevant Feather Roles contract calls:

- `GetCapabilities()` verifies that actor authority is available.
- `AwaitReady()` prevents Chat from starting before Roles is ready.
- `GetActorRole(source)` resolves the role of the currently active Character.
- `roles.assignment.changed.v1` refreshes staff-channel access after a role
  changes.

Chat intentionally does not call `AssignCharacterRole()`, `GetHistory()`, or
`GetHighestAccountRole()`. Those APIs are for role management, auditing, and
account-protection workflows. Chat only consumes the active Character role.

Trusted server resources can send structured system messages:

```lua
exports['bcc-chat']:SendMessage({
    channelKey = 'system',
    authorLabelKey = 'authorSystem',
    body = { text = 'Welcome.' },
    targets = { playerSource }
})
```

Gameplay resources may use `RegisterChannel`, `UpdateChannel`,
`UnregisterChannel`, and `RegisterChannelAccessProvider`. Provider checks
receive authenticated Feather account, character, and session identifiers.
Protected providers return `eligible`, `canSend`, and `canReceive`; provider
failure denies access rather than falling back to global delivery.

The removed Cfx compatibility surface is intentionally not reintroduced. This
resource does not expose `chat:addMessage`, templates, legacy modes,
`chatMessage`, `_chat:messageEntered`, message hooks, or the old BCC
`sendAnnouncement` event/export. Use the structured contract instead.

## Public exports

Every export returns the Core result envelope: `{ ok = true, value = ... }`
on success, `{ ok = false, code = 'stable_code', message = '...' }` on
failure. All of these are server-side exports (`exports['bcc-chat']:...`
called from another resource's `server_scripts`) unless noted otherwise.
Registrations (channels, suggestions, themes, moderation providers) are
owned by whichever resource called them (`GetInvokingResource()`), and are
removed automatically when that owning resource stops. They are **not**
removed when *bcc-chat itself* restarts because that wipes its own
in-memory registries — see the re-registration note under Suggestions.

### Lifecycle

- `GetCapabilities()` -- resource name, contract version, current health
  state, and a `features` map (`messaging`, `channels`, `moderation`,
  `persistence`, `messageHistory`, `characterRoles`, `discordPresentation`,
  etc., each `1` if enabled/available or `0` otherwise).
- `GetHealth()` -- `{ state, phase, since, checks, failure }`. `state` is
  `starting`, `ready`, or `failed`.
- `AwaitReady(timeoutMs)` -- blocks (yields) the calling thread until Chat
  reaches `ready` or `timeoutMs` (default 10000, max 60000) elapses. Call
  this before any other export from a resource that starts around the same
  time as bcc-chat, the same way bcc-chat itself waits on `feather-core` and
  `feather-roles`.

### Channels

- `RegisterChannel(definition)` -- registers a new channel. Key fields:
  `channelKey` (lowercase, dot/underscore/hyphen, unique, owner-held for its
  lifetime), `label`, `visibility` (`public` / `eligible` / `discoverable` /
  `hidden` / `system`), `accessProvider` (required if visibility is
  `eligible`/`discoverable`/`hidden` -- must name a provider already
  registered via `RegisterChannelAccessProvider`), `presentation.variant`
  (one of `localSpeech`, `roleplay`, `ooc`, `organization`, `staff`,
  `system`, `success`, `warning`, `danger`), and `routing` (`{ type =
  'global' }`, `{ type = 'proximity', radius = <1-100>, kind = 'player' |
  'action' | 'scene' }`, or `{ type = 'explicit' }` for resource-targeted
  delivery only -- see `SendMessage` below). Fails with `conflict` if the
  key is already taken.
- `UpdateChannel(channelKey, patch, expectedRevision)` -- merges `patch`
  (any of `label`, `labelKey`, `shortLabel`, `description`, `visibility`,
  `accessProvider`, `presentation`, `input`, `routing`) into a channel you
  own. `expectedRevision` must match the channel's current `revision`
  (optimistic concurrency) or it fails with `revision_conflict`.
- `UnregisterChannel(channelKey)` -- removes a channel you own.
- `RegisterChannelAccessProvider(name, implementation)` -- `name` is a
  lowercase dotted key (e.g. `'bcc-banks.tellers'`); `implementation` must
  expose a `CheckAccess({ channelKey, actor, operation })` function, where
  `operation` is `'send'`, `'receive'`, or `'list'` and `actor` carries
  authenticated `characterId`/`sessionId`/`accountId` (never trust a raw
  source). Return `{ eligible = true, canSend = true, canReceive = true,
  display = { badge = '...' } }` (or `{ ok = false, code, message }` to
  deny outright). A protected channel with a failed/missing provider always
  denies access -- it never falls back to public delivery.

### Suggestions

- `RegisterSuggestion(definition)` -- adds a `/command` entry to the
  composer's autocomplete. Fields: `key` (unique, lowercase dotted, e.g.
  `'bcc-banks.bankadmin'`), `trigger` (`'/yourcommand'`, 2-32 chars),
  `description`, optional `descriptionKey`/`descriptionArgs` for
  localization, optional `parameters` (up to 8, each `{ name, nameKey,
  required }`), and optional `accessProvider` to restrict *visibility* of
  the suggestion (reuse `'bcc-chat.roles.staff'` for staff-only, the same
  provider bcc-chat registers for its own `/staff` channel, instead of
  standing up a new one). Fails with `conflict` if the key is already
  registered.

  **Suggestions do not survive a bcc-chat restart.** They live in an
  in-memory table inside bcc-chat's own Lua state, which resets from
  scratch when *bcc-chat* restarts -- regardless of which resource
  originally registered them. Call `RegisterSuggestion` both once at your
  own resource's startup and again on `AddEventHandler('onResourceStart',
  function(resource) if resource == 'bcc-chat' then ... end end)`:

  ```lua
  local function registerMySuggestion()
      local ready = exports['bcc-chat']:AwaitReady(30000)
      if type(ready) ~= 'table' or not ready.ok then return end
      exports['bcc-chat']:RegisterSuggestion({
          key = 'my-resource.mycommand',
          trigger = '/mycommand',
          description = 'What it does'
      })
  end

  CreateThread(registerMySuggestion)
  AddEventHandler('onResourceStart', function(resource)
      if resource == 'bcc-chat' then CreateThread(registerMySuggestion) end
  end)
  ```

- `RemoveSuggestion(key)` -- removes a suggestion you registered.

### Messaging

- `SendMessage(request)` -- sends a `system`-kind message as a trusted
  server resource, not a player. `channelKey` must be `'system'` or a
  channel you own; `body.text` is validated the same way as player
  messages. `targets` is an optional array of player source IDs (defaults
  to every connected player currently eligible to receive the channel);
  capped at `Config.MaximumResourceTargets`. Resource-level rate limiting
  applies per calling resource, separate from per-player rate limits.
  ```lua
  exports['bcc-chat']:SendMessage({
      channelKey = 'system',
      authorLabelKey = 'authorSystem',
      body = { text = 'Welcome.' },
      targets = { playerSource }
  })
  ```

### Moderation

- `RegisterModerationProvider(name, implementation, options)` -- `name` is
  a lowercase dotted key; `implementation` exposes `Evaluate(request)`
  returning `{ allowed = true }`, `{ allowed = false, code, message }`, or
  `{ text = 'normalized replacement' }`. Pass `{ required = true }` in
  `options` to fail-closed (reject the message) if this provider errors or
  is unreachable, instead of silently skipping it.
- `IssueMute(request)` -- `{ characterId, scope = 'all' | 'channel',
  channelKey, durationSeconds, reasonCode, source }`. `source` is the
  issuing player's source ID (`0` for console/system, always authorized);
  a real source is checked against the `muteManage` permission level.
  Omitting `durationSeconds` issues a permanent mute.
- `RevokeMute(muteId, expectedRevision, requestSource)` -- same
  optimistic-concurrency pattern as `UpdateChannel`.
- `GetMuteSnapshot({ characterId })` -- returns the array of currently
  active mutes for that character (expired ones are pruned as a side
  effect of the read).

### Theming

- `RegisterTheme(theme)` -- `{ themeKey, tokens = { background, panel,
  border, primary, muted, danger, localSpeech, roleplay, ooc, organization,
  staff, system } }`. Every token must be a `#RRGGBB`/`#RRGGBBAA` hex color;
  no other CSS is accepted. Fails with `conflict` if `themeKey` is taken.
- `GetTheme(key)` -- returns the requested theme, or `Config.Theme.default`
  if `key` isn't registered.

## Roles, moderation, and privacy

`Config.Permissions` maps BCC Chat operations to existing Feather role levels.
Role labels and colors in `Config.RolePresentation` are cosmetic only and can
be disabled. `IssueMute`, `RevokeMute`, and `GetMuteSnapshot` provide bounded
runtime mutes; management uses the authoritative Feather role level. Mutes are
persisted by default and follow the active Feather Character UUID.

Message history is opt-in (`Config.Persistence.messages = false` by default).
Retention is configured by channel class or exact channel key; zero means that
class is not stored. History reads are paginated, bounded, and re-check the
current channel receive policy. Explicit/targeted channels such as `system`
are never retained because their original recipient set cannot be reconstructed
safely. Expired rows are removed on startup and periodically.

Checksummed migrations create only `bcc_chat_schema_migrations`,
`bcc_chat_mutes`, and `bcc_chat_messages`. BCC Chat does not recreate the old
BCC role, player-role, or name-preference tables. `Config.Persistence.preferences`
must remain false because Feather Character owns display identity. Optional
Discord role tags are disabled by default; when enabled, IDs map only to
configured localized labels and colors. The bot secret comes from a server
convar, and Discord never grants chat authority.

All player content is plain text. Arbitrary HTML, templates, CSS, remote fonts,
and caller-supplied presentation colors are rejected. Client buffers are
bounded and reset with the character session.

The custom emoji picker uses native Unicode characters from the
[Unicode Emoji 17.0 catalog](https://www.unicode.org/Public/17.0.0/emoji/emoji-test.txt).
It provides the full supported catalog across standard categories, including
skin-tone and joined variants, plus a Western favorites category and name
search. Emoji Mart, Twemoji, remote scripts, and CDN artwork are not used.
Emoji appearance and support depend on the player's system and CEF emoji fonts.

The generated catalog is stored in `ui/src/emoji-data.mjs`; its generator is
`ui/build/generate-emojis.js`.

## Localization and checks

Locales register directly with Feather Core in `locale/*.lua`. User-facing Lua
labels and feedback resolve with `FeatherCore.Locale.translate`.

Console checks: `ChatContractSmokeTest`, `ChatSessionSmokeTest <source>`,
`ChatChannelSmokeTest`, `ChatModerationSmokeTest`, `ChatSecuritySmokeTest`, and
`ChatRestartChecklist`. `ChatPersistenceSmokeTest` verifies database readiness,
the three expected tables, and the migration ledger.
