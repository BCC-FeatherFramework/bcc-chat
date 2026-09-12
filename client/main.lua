-- `visible` gates whether chat can be opened at all; it starts false and is
-- only set true once the character has fully spawned (Feather:Character:Spawned)
-- so the composer/window aren't usable before there's an actual character.
local chatInputActive, chatInputActivating, chatLoaded, visible = false, false, false, false
local hidden = false
local state = {
    channels = {},
    suggestions = {},
    rendered = {},
    renderedOrder = {},
    historyLoaded = {},
    historyLoading = {},
    selectedChannel = 'local.say',
    revision = 0
}
local function buildLocale()
    return {
        localeCode = FeatherCore.Locale.translate(0, 'uiLocaleCode'),
        general = FeatherCore.Locale.translate(0, 'uiGeneral'),
        global = FeatherCore.Locale.translate(0, 'uiGlobal'),
        ooc = FeatherCore.Locale.translate(0, 'uiOoc'),
        admin = FeatherCore.Locale.translate(0, 'uiAdmin'),
        announcements = FeatherCore.Locale.translate(0, 'uiAnnouncements'),
        other = FeatherCore.Locale.translate(0, 'uiOther'),
        visible = FeatherCore.Locale.translate(0, 'uiVisible'),
        hidden = FeatherCore.Locale.translate(0, 'uiHidden'),
        whenActive = FeatherCore.Locale.translate(0, 'uiWhenActive'),
        showOlderMessages = FeatherCore.Locale.translate(0, 'uiShowOlder'),
        hideOlderMessages = FeatherCore.Locale.translate(0, 'uiHideOlder'),
        nameButton = FeatherCore.Locale.translate(0, 'uiName'),
        nameTitle = FeatherCore.Locale.translate(0, 'uiNameTitle'),
        emojiFaces = FeatherCore.Locale.translate(0, 'uiFaces'),
        emojiPeople = FeatherCore.Locale.translate(0, 'uiPeople'),
        emojiHearts = FeatherCore.Locale.translate(0, 'uiHearts'),
        emojiWestern = FeatherCore.Locale.translate(0, 'uiWestern'),
        emojiAnimals = FeatherCore.Locale.translate(0, 'uiAnimals'),
        emojiWorld = FeatherCore.Locale.translate(0, 'uiWorld'),
        emojiComponents = FeatherCore.Locale.translate(0, 'uiComponents'),
        emojiFood = FeatherCore.Locale.translate(0, 'uiFood'),
        emojiTravel = FeatherCore.Locale.translate(0, 'uiTravel'),
        emojiActivities = FeatherCore.Locale.translate(0, 'uiActivities'),
        emojiObjects = FeatherCore.Locale.translate(0, 'uiObjects'),
        emojiSymbols = FeatherCore.Locale.translate(0, 'uiSymbols'),
        emojiFlags = FeatherCore.Locale.translate(0, 'uiFlags'),
        emojiSearch = FeatherCore.Locale.translate(0, 'uiEmojiSearch'),
        emojiNoResults = FeatherCore.Locale.translate(0, 'uiEmojiNoResults')
    }
end
local variantColors = {
    localSpeech = '#f5f1df',
    roleplay = '#d8b4fe',
    ooc = '#9cc7ff',
    organization = '#e7c66b',
    staff = '#ef8c8c',
    system = '#d8c59f',
    success = '#8bcf9b',
    warning = '#e7c66b',
    danger = '#ef8c8c'
}
local function closeChat()
    chatInputActive, chatInputActivating = false, false
    SetNuiFocus(false, false)
end

local function openChat()
    if not visible or chatInputActive or chatInputActivating or IsPauseMenuActive() then
        return
    end
    chatInputActivating = true
    SendNUIMessage({ type = 'ON_OPEN' })
    SetNuiFocus(true, true)
    chatInputActive, chatInputActivating = true, false
end

-- Hide the chat whenever something else is covering the screen (pause menu,
-- cinematic, map, loading screen, fade transition, gameplay hint, or shop
-- browsing) -- see feather-toolkit's ToolkitScreen.IsObscured for exactly
-- which natives that covers and why. Being dead is deliberately excluded:
-- players should still be able to read/use chat while dead.
-- Edge-triggered so it only pushes an NUI update on actual state changes,
-- not every frame.
local function isObscured()
    local result = exports['feather-toolkit']:IsScreenObscured({ dead = true })
    return type(result) == 'table' and result.ok and result.value == true
end

CreateThread(function()
    while true do
        Wait(0)
        local nowHidden = isObscured()
        if nowHidden ~= hidden then
            hidden = nowHidden
            if hidden and chatInputActive then closeChat() end
            SendNUIMessage({ type = 'ON_HIDE_STATE', hidden = hidden })
        end
    end
end)

local function renderMessage(message)
    if type(message) ~= 'table' or type(message.body) ~= 'table' then
        return
    end
    if type(message.messageId) ~= 'string' or state.rendered[message.messageId] then
        return
    end
    state.rendered[message.messageId] = true
    state.renderedOrder[#state.renderedOrder + 1] = message.messageId
    if #state.renderedOrder > Config.MaximumVisibleMessages * 2 then
        state.rendered[state.renderedOrder[1]] = nil
        table.remove(state.renderedOrder, 1)
    end
    local author = type(message.author) == 'table' and message.author.displayName or nil
    if type(message.author) == 'table' and message.author.labelKey then
        author = FeatherCore.Locale.translate(0, message.author.labelKey)
    end
    author = author or FeatherCore.Locale.translate(0, 'authorSystem')
    local badge = type(message.author) == 'table' and message.author.badge or nil
    if type(message.author) == 'table' and message.author.badgeKey then
        badge = FeatherCore.Locale.translate(0, message.author.badgeKey)
    end
    if badge then
        author = ('%s | %s'):format(tostring(badge), tostring(author))
    end
    local authorColor = type(message.author) == 'table' and tostring(message.author.badgeColor or '') or ''
    if not authorColor:match('^#%x%x%x%x%x%x$') then authorColor = nil end
    local mode = message.channelKey == 'system' and '_global'
        or (message.channelKey == 'local.say' and 'all' or message.channelKey)
    SendNUIMessage({
        type = 'ON_MESSAGE',
        message = {
            messageId = message.messageId,
            mode = mode,
            createdAt = message.createdAt,
            multiline = true,
            authorColor = authorColor,
            args = { author, message.body.text }
        }
    })
end

local function requestHistory(channelKey)
    if not Config.Persistence.messages or type(channelKey) ~= 'string'
        or state.historyLoaded[channelKey] or state.historyLoading[channelKey] then
        return
    end
    state.historyLoading[channelKey] = true
    FeatherCore.RPC.Call('chat.history.list.v1', {
        channelKey = channelKey,
        limit = Config.Persistence.historyPageSize
    }, function(result)
        state.historyLoading[channelKey] = nil
        if type(result) ~= 'table' or not result.ok or type(result.value) ~= 'table' then
            return
        end
        state.historyLoaded[channelKey] = true
        for _, message in ipairs(result.value.messages or {}) do
            renderMessage(message)
        end
    end)
end

local function publishDirectory(value)
    local previous = {}
    for _, item in ipairs(state.channels) do
        previous[item.channelKey] = true
    end

    local previousSuggestions = {}
    for key in pairs(state.suggestions) do
        previousSuggestions[key] = true
    end

    state.channels, state.revision = value.channels or {}, value.revision or 0
    local found = false
    for _, item in ipairs(state.channels) do
        found = found or item.channelKey == state.selectedChannel
        previous[item.channelKey] = nil
        if item.channelKey ~= 'local.say' then
            local displayName = item.labelKey and FeatherCore.Locale.translate(0, item.labelKey) or item.shortLabel or
                item.label
            SendNUIMessage({
                type = 'ON_MODE_ADD',
                mode = {
                    name = item.channelKey,
                    displayName = displayName,
                    color = variantColors[item.presentation and item.presentation.variant] or '#f5f1df',
                    isChannel = true
                }
            })
        end
    end
    for key in pairs(previous) do
        SendNUIMessage({ type = 'ON_MODE_REMOVE', name = key })
    end
    if not found and state.channels[1] then
        state.selectedChannel = state.channels[1].channelKey
    end
    requestHistory(state.selectedChannel)

    local suggestions = {}
    for _, suggestion in ipairs(value.suggestions or {}) do
        suggestions[suggestion.key] = suggestion.trigger
        previousSuggestions[suggestion.key] = nil
        local description = suggestion.description
        if suggestion.descriptionKey then
            description = FeatherCore.Locale.translate(0, suggestion.descriptionKey,
                table.unpack(suggestion.descriptionArgs or {}))
        end
        local parameters = {}
        for _, parameter in ipairs(suggestion.parameters or {}) do
            local copy = {}
            for key, child in pairs(parameter) do
                copy[key] = child
            end
            if copy.nameKey then
                copy.name = FeatherCore.Locale.translate(0, copy.nameKey)
            end
            parameters[#parameters + 1] = copy
        end
        SendNUIMessage({
            type = 'ON_SUGGESTION_ADD',
            suggestion = {
                name = suggestion.trigger,
                help = description,
                params = parameters
            }
        })
    end
    for key in pairs(previousSuggestions) do
        SendNUIMessage({ type = 'ON_SUGGESTION_REMOVE', name = state.suggestions[key] })
    end
    state.suggestions = suggestions
end

local function refreshDirectory()
    FeatherCore.RPC.Call('chat.channel.list.v1', {}, function(result)
        if type(result) == 'table' and result.ok and type(result.value) == 'table' then
            -- chat.channel.list.v1 requires a live character session server-side
            -- (see actorFor in server/main.lua); succeeding here is itself proof one
            -- exists right now. That catches the case where bcc-chat restarts mid-
            -- session -- the character already spawned before this Lua VM existed,
            -- so no fresh Feather:Character:Spawned event is coming to set `visible`.
            visible = true
            publishDirectory(result.value)
        end
    end)
end

RegisterNetEvent('bcc-chat:message', function(message)
    renderMessage(message)
end)

RegisterNetEvent('bcc-chat:feedback', function(message)
    SendNUIMessage({
        type = 'ON_MESSAGE',
        message = {
            mode = '_global',
            args = {
                FeatherCore.Locale.translate(0, 'uiChat'),
                tostring(message or FeatherCore.Locale.translate(0, 'uiRequestFailed'))
            }
        }
    })
end)

RegisterNetEvent('Feather:Character:Spawned', function()
    visible = true
end)

RegisterNetEvent('bcc-chat:reset-session', function()
    -- A session reset means the previous character's spawn no longer applies
    -- (character switch, death recovery, disconnect); re-lock chat until the
    -- next Feather:Character:Spawned fires for whichever character follows.
    visible = false
    closeChat()
    state.channels, state.suggestions, state.rendered, state.renderedOrder = {}, {}, {}, {}
    state.historyLoaded, state.historyLoading = {}, {}
    state.selectedChannel, state.revision = 'local.say', 0
    SendNUIMessage({ type = 'ON_CLEAR' })
    refreshDirectory()
end)
RegisterNetEvent('bcc-chat:directory-invalidated', function(revision)
    if tonumber(revision) ~= state.revision then
        refreshDirectory()
    end
end)

RegisterNUICallback('loaded', function(_, cb)
    chatLoaded = true
    SendNUIMessage({
        type = 'ON_CONFIG',
        config = {
            hideOlderMessagesHours = Config.HideOlderMessagesHours or 3,
            maximumVisibleMessages = Config.MaximumVisibleMessages,
            fadeDelayMs = Config.FadeDelayMs,
            submitCloses = Config.SubmitCloses,
            historyEnabled = Config.Persistence.messages,
            displayNamePreferences = Config.Features.displayNamePreferences,
            accessibility = Config.Accessibility
        }
    })
    local selectedTheme
    for _, theme in ipairs(Config.Theme.themes or {}) do
        if theme.themeKey == Config.Theme.default then
            selectedTheme = theme
        end
    end
    if selectedTheme then
        SendNUIMessage({ type = 'ON_THEME', theme = selectedTheme })
    end
    SendNUIMessage({ type = 'ON_LOCALE', locale = buildLocale() })
    refreshDirectory()
    cb('ok')
end)

RegisterNUICallback('selectChannel', function(data, cb)
    if type(data) == 'table' and type(data.channelKey) == 'string' then
        state.selectedChannel = data.channelKey == 'all' and 'local.say' or data.channelKey
        requestHistory(state.selectedChannel)
    end
    cb('ok')
end)

RegisterNUICallback('chatResult', function(data, cb)
    if Config.SubmitCloses ~= false or type(data) ~= 'table' or data.canceled then
        closeChat()
    end
    if type(data) ~= 'table' or data.canceled or type(data.message) ~= 'string' then
        cb('ok')
        return
    end
    if data.message:sub(1, 1) == '/' then
        ExecuteCommand(data.message:sub(2))
        cb('ok')
        return
    end
    local selected = type(data.mode) == 'string' and data.mode or state.selectedChannel
    if selected == 'all' then selected = 'local.say' end
    state.selectedChannel = selected
    FeatherCore.RPC.Call('chat.message.submit.v1',
        {
            text = data.message,
            channelKey = selected,
            submissionId = ('%s:%s'):format(GetGameTimer(),
                math.random(100000, 999999))
        }, function(result, transportError)
            if type(result) ~= 'table' or not result.ok then
                local message = type(result) == 'table' and result.message
                    or (transportError and transportError.message)
                    or FeatherCore.Locale.translate(0, 'uiSubmitFailed')
                SendNUIMessage({
                    type = 'ON_MESSAGE',
                    message = {
                        mode = '_global',
                        args = { FeatherCore.Locale.translate(0, 'uiChat'), message }
                    }
                })
            end
        end)
    cb('ok')
end)

RegisterNUICallback('openDisplayNameMenu', function(_, cb)
    closeChat()
    TriggerEvent('bcc-chat:open-settings')
    cb('ok')
end)

RegisterNUICallback('loadedThemes', function(_, cb)
    cb('ok')
end)

RegisterCommand('+bccchat', openChat, false)
RegisterCommand('-bccchat', function() end, false)
RegisterKeyMapping('+bccchat', FeatherCore.Locale.translate(0, 'keyMappingOpen'), 'keyboard', Config.OpenKey)
RegisterCommand('toggleChat', function()
    visible = not visible
    if not visible then
        closeChat()
    end
end, false)

RegisterCommand('clearchathistory', function()
    SendNUIMessage({ type = 'ON_CLEAR' })
end, false)

RegisterCommand('bccchat:reset', function()
    closeChat()
    state.historyLoaded, state.historyLoading = {}, {}
    SendNUIMessage({ type = 'ON_CLEAR' })
    refreshDirectory()
end, false)

exports('OpenChat', function(options)
    if type(options) == 'table' and type(options.channelKey) == 'string' then
        state.selectedChannel = options.channelKey
        requestHistory(state.selectedChannel)
    end
    openChat()
    return { ok = true, value = true }
end)

exports('CloseChat', function()
    closeChat()
    return { ok = true, value = true }
end)

exports('SetChatVisible', function(value)
    visible = value == true
    if not visible then
        closeChat()
    end
    return { ok = true, value = visible }
end)

exports('FocusChannel', function(key)
    state.selectedChannel = key
    requestHistory(key)
    return { ok = true, value = key }
end)

exports('GetChatState', function()
    return {
        ok = true,
        value = {
            open = chatInputActive,
            visible = visible,
            loaded = chatLoaded,
            selectedChannel = state.selectedChannel,
            revision = state.revision
        }
    }
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        SetNuiFocus(false, false)
    end
end)
