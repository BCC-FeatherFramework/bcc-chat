local isRDR = not TerraingridActivate and true or false
local FeatherMenu = exports['feather-menu'].initiate()

local chatInputActive = false
local chatInputActivating = false
local chatLoaded = false
local currentRoleMenu = nil
local currentDisplayNameMenu = nil

local function sendUiConfig()
    SendNUIMessage({
        type = 'ON_CONFIG',
        config = {
            hideOlderMessagesHours = tonumber(Config.HideOlderMessagesHours) or 3
        }
    })
end

local function sendLocale()
    SendNUIMessage({
        type = 'ON_LOCALE',
        locale = {
            localeCode = Config.defaultlang == 'ro_lang' and 'ro-RO' or 'en-GB',
            general = _U('general'),
            ooc = _U('ooc'),
            admin = _U('admin'),
            announcements = _U('announcements'),
            other = _U('other'),
            visible = _U('visible'),
            hidden = _U('hidden'),
            whenActive = _U('when_active'),
            showOlderMessages = _U('show_older_messages'),
            hideOlderMessages = _U('hide_older_messages'),
            nameButton = _U('chat_name_button'),
            nameTitle = _U('chat_name_title'),
            emojiFaces = _U('emoji_faces'),
            emojiPeople = _U('emoji_people'),
            emojiHearts = _U('emoji_hearts'),
            emojiWestern = _U('emoji_western'),
            emojiAnimals = _U('emoji_animals'),
            emojiWorld = _U('emoji_world')
        }
    })
end

RegisterNetEvent('chatMessage')
RegisterNetEvent('chat:addTemplate')
RegisterNetEvent('chat:addMessage')
RegisterNetEvent('chat:addSuggestion')
RegisterNetEvent('chat:addSuggestions')
RegisterNetEvent('chat:addMode')
RegisterNetEvent('chat:removeMode')
RegisterNetEvent('chat:removeSuggestion')
RegisterNetEvent('chat:clear')

RegisterNetEvent('__cfx_internal:serverPrint')
RegisterNetEvent('_chat:messageEntered')

AddEventHandler('chatMessage', function(author, color, text)
    local args = { text }

    if author ~= '' then
        table.insert(args, 1, author)
    end

    SendNUIMessage({
        type = 'ON_MESSAGE',
        message = {
            color = color,
            multiline = true,
            args = args,
            mode = 'all'
        }
    })
end)

AddEventHandler('__cfx_internal:serverPrint', function(msg)
    if string.len(msg) == 0 then
        return
    end

    SendNUIMessage({
        type = 'ON_MESSAGE',
        message = {
            templateId = 'print',
            multiline = true,
            args = { msg },
            mode = '_global'
        }
    })
end)

local addMessage = function(message)
    if type(message) == 'string' then
        message = {
            args = { message }
        }
    end

    SendNUIMessage({
        type = 'ON_MESSAGE',
        message = message
    })
end

exports('addMessage', addMessage)
AddEventHandler('chat:addMessage', addMessage)

local addSuggestion = function(name, help, params)
    SendNUIMessage({
        type = 'ON_SUGGESTION_ADD',
        suggestion = {
            name = name,
            help = help,
            params = params or nil
        }
    })
end

exports('addSuggestion', addSuggestion)
AddEventHandler('chat:addSuggestion', addSuggestion)

AddEventHandler('chat:addSuggestions', function(suggestions)
    for _, suggestion in ipairs(suggestions) do
        SendNUIMessage({
            type = 'ON_SUGGESTION_ADD',
            suggestion = suggestion
        })
    end
end)

AddEventHandler('chat:removeSuggestion', function(name)
    SendNUIMessage({
        type = 'ON_SUGGESTION_REMOVE',
        name = name
    })
end)

AddEventHandler('chat:addMode', function(mode)
    SendNUIMessage({
        type = 'ON_MODE_ADD',
        mode = mode
    })
end)

AddEventHandler('chat:removeMode', function(name)
    SendNUIMessage({
        type = 'ON_MODE_REMOVE',
        name = name
    })
end)

AddEventHandler('chat:addTemplate', function(id, html)
    SendNUIMessage({
        type = 'ON_TEMPLATE_ADD',
        template = {
            id = id,
            html = html
        }
    })
end)

AddEventHandler('chat:clear', function()
    SendNUIMessage({
        type = 'ON_CLEAR'
    })
end)

local function roleStyle()
    return {
        ['color'] = '#E0E0E0'
    }
end

local function addHeader(page, title, subtitle)
    page:RegisterElement('header', {
        value = title,
        slot = 'header',
        style = {
            ['color'] = '#d4b06a'
        }
    })

    if subtitle and subtitle ~= '' then
        page:RegisterElement('subheader', {
            value = subtitle,
            slot = 'header',
            style = {
                ['color'] = '#E0E0E0',
                ['font-size'] = '16px'
            }
        })
    end

    page:RegisterElement('line', {
        slot = 'header',
        style = {}
    })
end

local function openRoleMenu(payload)
    if currentRoleMenu then
        currentRoleMenu:Close()
        currentRoleMenu = nil
    end

    local roles = payload.roles or {}
    local players = payload.players or {}
    local menu = FeatherMenu:RegisterMenu(('bcc-chat:roles:%s'):format(GetGameTimer()), {
        top = '5%',
        left = '5%',
        ['720width'] = '440px',
        ['1080width'] = '520px',
        ['2kwidth'] = '620px',
        ['4kwidth'] = '760px',
        style = {},
        contentslot = {
            style = {
                ['height'] = '460px',
                ['min-height'] = '360px'
            }
        },
        draggable = true,
        canclose = true
    })

    currentRoleMenu = menu

    local mainPage = menu:RegisterPage('bcc-chat:roles:main')
    local roleListPage = menu:RegisterPage('bcc-chat:roles:list')
    local playerPage = menu:RegisterPage('bcc-chat:roles:players')

    addHeader(mainPage, 'Chat Roles', 'Manage bcc-chat role prefixes')

    mainPage:RegisterElement('button', {
        label = ('Online Players (%s)'):format(#players),
        slot = 'content',
        style = roleStyle()
    }, function()
        playerPage:RouteTo()
    end)

    mainPage:RegisterElement('button', {
        label = ('Role List (%s)'):format(#roles),
        slot = 'content',
        style = roleStyle()
    }, function()
        roleListPage:RouteTo()
    end)

    mainPage:RegisterElement('button', {
        label = 'Refresh',
        slot = 'content',
        style = roleStyle()
    }, function()
        TriggerServerEvent('bcc-chat:requestRoleMenu')
    end)

    addHeader(roleListPage, 'Role List', 'Saved in bcc_chat_roles')

    if #roles == 0 then
        roleListPage:RegisterElement('textdisplay', {
            value = 'No chat roles are saved.',
            slot = 'content',
            style = roleStyle()
        })
    else
        for _, role in ipairs(roles) do
            roleListPage:RegisterElement('textdisplay', {
                value = ('%s | %s | Priority %s'):format(role.label or role.role_id, role.role_id, role.priority or 0),
                slot = 'content',
                style = roleStyle()
            })
        end
    end

    roleListPage:RegisterElement('line', {
        slot = 'footer',
        style = {}
    })

    roleListPage:RegisterElement('button', {
        label = 'Back',
        slot = 'footer',
        style = roleStyle()
    }, function()
        mainPage:RouteTo()
    end)

    addHeader(playerPage, 'Online Players', 'Choose a player to assign a role')

    if #players == 0 then
        playerPage:RegisterElement('textdisplay', {
            value = 'No online players found.',
            slot = 'content',
            style = roleStyle()
        })
    else
        for _, player in ipairs(players) do
            local selectedPlayer = player
            local roleLabel = player.roleLabel or 'Discord/default'
            local playerLabel = ('[%s] %s - %s'):format(player.source, player.name, roleLabel)

            playerPage:RegisterElement('button', {
                label = playerLabel,
                slot = 'content',
                style = roleStyle(),
                id = player.source
            }, function()
                local assignPage = menu:RegisterPage(('bcc-chat:roles:assign:%s:%s'):format(selectedPlayer.source, GetGameTimer()))

                addHeader(assignPage, selectedPlayer.name, 'Assign a saved chat role')

                assignPage:RegisterElement('button', {
                    label = 'Use Discord/default role',
                    slot = 'content',
                    style = roleStyle()
                }, function()
                    TriggerServerEvent('bcc-chat:clearPlayerRole', selectedPlayer.source)
                end)

                for _, role in ipairs(roles) do
                    local selectedRole = role
                    assignPage:RegisterElement('button', {
                        label = role.label or role.role_id,
                        slot = 'content',
                        style = roleStyle(),
                        id = role.role_id
                    }, function()
                        TriggerServerEvent('bcc-chat:setPlayerRole', selectedPlayer.source, selectedRole.role_id)
                    end)
                end

                assignPage:RegisterElement('line', {
                    slot = 'footer',
                    style = {}
                })

                assignPage:RegisterElement('button', {
                    label = 'Back',
                    slot = 'footer',
                    style = roleStyle()
                }, function()
                    playerPage:RouteTo()
                end)

                assignPage:RouteTo()
            end)
        end
    end

    playerPage:RegisterElement('line', {
        slot = 'footer',
        style = {}
    })

    playerPage:RegisterElement('button', {
        label = 'Back',
        slot = 'footer',
        style = roleStyle()
    }, function()
        mainPage:RouteTo()
    end)

    menu:Open({
        startupPage = mainPage
    })
end

local function openDisplayNameMenu(payload)
    if currentDisplayNameMenu then
        currentDisplayNameMenu:Close()
        currentDisplayNameMenu = nil
    end

    local currentMode = payload.currentMode or 'player_name'
    local preview = payload.preview or {}
    local menu = FeatherMenu:RegisterMenu(('bcc-chat:name:%s'):format(GetGameTimer()), {
        top = '5%',
        left = '5%',
        ['720width'] = '420px',
        ['1080width'] = '500px',
        ['2kwidth'] = '580px',
        ['4kwidth'] = '680px',
        style = {},
        contentslot = {
            style = {
                ['height'] = '360px',
                ['min-height'] = '280px'
            }
        },
        draggable = true,
        canclose = true
    })

    currentDisplayNameMenu = menu

    local mainPage = menu:RegisterPage('bcc-chat:name:main')

    addHeader(mainPage, _U('chat_name_title'), _U('chat_name_subtitle'))

    local options = {
        { mode = 'player_name', label = _U('chat_name_player'), preview = preview.player_name },
        { mode = 'character_name', label = _U('chat_name_character'), preview = preview.character_name },
        { mode = 'character_with_player', label = _U('chat_name_character_with_player'), preview = preview.character_with_player }
    }

    for _, option in ipairs(options) do
        local selectedOption = option
        local prefix = currentMode == option.mode and '• ' or ''
        local suffix = currentMode == option.mode and (' (%s)'):format(_U('chat_name_current')) or ''

        mainPage:RegisterElement('button', {
            label = ('%s%s%s'):format(prefix, option.label, suffix),
            slot = 'content',
            style = roleStyle()
        }, function()
            TriggerServerEvent('bcc-chat:setDisplayNameMode', selectedOption.mode)
        end)

        mainPage:RegisterElement('textdisplay', {
            value = _U('chat_name_preview', option.preview or 'N/A'),
            slot = 'content',
            style = roleStyle()
        })
    end

    mainPage:RegisterElement('line', {
        slot = 'footer',
        style = {}
    })

    mainPage:RegisterElement('button', {
        label = _U('chat_name_close'),
        slot = 'footer',
        style = roleStyle()
    }, function()
        menu:Close()
        currentDisplayNameMenu = nil
    end)

    menu:Open({
        startupPage = mainPage
    })
end

RegisterNetEvent('bcc-chat:openRoleMenu')
AddEventHandler('bcc-chat:openRoleMenu', openRoleMenu)

RegisterNetEvent('bcc-chat:openDisplayNameMenu')
AddEventHandler('bcc-chat:openDisplayNameMenu', openDisplayNameMenu)

TriggerEvent('chat:addSuggestion', '/chatroles', 'Open the bcc-chat role manager')
TriggerEvent('chat:addSuggestion', '/chatname', _U('chat_name_suggestion'))

RegisterNUICallback('chatResult', function(data, cb)
    chatInputActive = false
    SetNuiFocus(false, false)

    if not data.canceled then
        local id = PlayerId()
        local r, g, b = 0, 0x99, 255

        if data.message:sub(1, 1) == '/' then
            ExecuteCommand(data.message:sub(2))
        else
            TriggerServerEvent('_chat:messageEntered', GetPlayerName(id), { r, g, b }, data.message, data.mode)
        end
    end

    cb('ok')
end)

RegisterNUICallback('openDisplayNameMenu', function(_, cb)
    chatInputActive = false
    SetNuiFocus(false, false)
    TriggerServerEvent('bcc-chat:requestDisplayNameMenu')
    cb('ok')
end)

local function refreshCommands()
    if not GetRegisteredCommands then
        return
    end

    local registeredCommands = GetRegisteredCommands()
    local suggestions = {}

    for _, command in ipairs(registeredCommands) do
        if IsAceAllowed(('command.%s'):format(command.name)) and command.name ~= 'toggleChat' then
            table.insert(suggestions, {
                name = '/' .. command.name,
                help = ''
            })
        end
    end

    TriggerEvent('chat:addSuggestions', suggestions)
end

local function refreshThemes()
    local themes = {}

    for resIdx = 0, GetNumResources() - 1 do
        local resource = GetResourceByFindIndex(resIdx)

        if GetResourceState(resource) == 'started' then
            local numThemes = GetNumResourceMetadata(resource, 'chat_theme')

            if numThemes > 0 then
                local themeName = GetResourceMetadata(resource, 'chat_theme')
                local themeData = json.decode(GetResourceMetadata(resource, 'chat_theme_extra') or 'null')

                if themeName and themeData then
                    themeData.baseUrl = 'nui://' .. resource .. '/'
                    themes[themeName] = themeData
                end
            end
        end
    end

    SendNUIMessage({
        type = 'ON_UPDATE_THEMES',
        themes = themes
    })
end

AddEventHandler('onClientResourceStart', function()
    Wait(500)
    refreshCommands()
    refreshThemes()
end)

AddEventHandler('onClientResourceStop', function()
    Wait(500)
    refreshCommands()
    refreshThemes()
end)

RegisterNUICallback('loaded', function(_, cb)
    TriggerServerEvent('chat:init')

    refreshCommands()
    refreshThemes()
    sendUiConfig()
    sendLocale()

    chatLoaded = true

    cb('ok')
end)

local CHAT_HIDE_STATES = {
    SHOW_WHEN_ACTIVE = 0,
    ALWAYS_SHOW = 1,
    ALWAYS_HIDE = 2
}

local kvpEntry = GetResourceKvpString('hideState')
local chatHideState = kvpEntry and tonumber(kvpEntry) or CHAT_HIDE_STATES.SHOW_WHEN_ACTIVE
local isFirstHide = true

if not isRDR and RegisterKeyMapping then
    RegisterKeyMapping('toggleChat', 'Toggle chat', 'keyboard', 'l')

    RegisterCommand('toggleChat', function()
        if chatHideState == CHAT_HIDE_STATES.SHOW_WHEN_ACTIVE then
            chatHideState = CHAT_HIDE_STATES.ALWAYS_SHOW
        elseif chatHideState == CHAT_HIDE_STATES.ALWAYS_SHOW then
            chatHideState = CHAT_HIDE_STATES.ALWAYS_HIDE
        else
            chatHideState = CHAT_HIDE_STATES.SHOW_WHEN_ACTIVE
        end

        isFirstHide = false
        SetResourceKvp('hideState', tostring(chatHideState))
    end, false)
end

CreateThread(function()
    SetTextChatEnabled(false)
    SetNuiFocus(false, false)

    local lastChatHideState = -1
    local origChatHideState = -1

    while true do
        Wait(0)

        if not chatInputActive then
            if IsControlPressed(0, isRDR and `INPUT_MP_TEXT_CHAT_ALL` or 245) then
                chatInputActive = true
                chatInputActivating = true

                SendNUIMessage({
                    type = 'ON_OPEN'
                })
            end
        end

        if chatInputActivating then
            if not IsControlPressed(0, isRDR and `INPUT_MP_TEXT_CHAT_ALL` or 245) then
                SetNuiFocus(true, true)
                chatInputActivating = false
            end
        end

        if chatLoaded then
            local forceHide = IsScreenFadedOut() or IsPauseMenuActive()
            local wasForceHide = false

            if chatHideState ~= CHAT_HIDE_STATES.ALWAYS_HIDE then
                if forceHide then
                    origChatHideState = chatHideState
                    chatHideState = CHAT_HIDE_STATES.ALWAYS_HIDE
                end
            elseif not forceHide and origChatHideState ~= -1 then
                chatHideState = origChatHideState
                origChatHideState = -1
                wasForceHide = true
            end

            if chatHideState ~= lastChatHideState then
                lastChatHideState = chatHideState

                SendNUIMessage({
                    type = 'ON_SCREEN_STATE_CHANGE',
                    hideState = chatHideState,
                    fromUserInteraction = not forceHide and not isFirstHide and not wasForceHide
                })

                isFirstHide = false
            end
        end
    end
end)
