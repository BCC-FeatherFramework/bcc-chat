ChatThemes = {}

local themes = {}
local allowedColors = {
    background = true,
    panel = true,
    border = true,
    primary = true,
    muted = true,
    danger = true,
    localSpeech = true,
    roleplay = true,
    ooc = true,
    organization = true,
    staff = true,
    system = true
}

local function validColor(value)
    return type(value) == 'string' and (#value == 7 or #value == 9) and value:match('^#%x+$') ~= nil
end
local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for key, child in pairs(value) do
        out[key] = copy(child)
    end
    return out
end

local function validate(theme)
    if type(theme) ~= 'table' or type(theme.themeKey) ~= 'string'
        or not theme.themeKey:match('^[a-z][a-z0-9_.-]*$') then
        return nil, ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorThemeKey'))
    end
    local tokens = type(theme.tokens) == 'table' and theme.tokens or {}
    local normalized = { themeKey = theme.themeKey, schemaVersion = 1, tokens = {} }
    for key, value in pairs(tokens) do
        if not allowedColors[key] or not validColor(value) then
            return nil,
                ChatResults.Err('invalid_input', FeatherCore.Locale.translate(0, 'errorThemeToken'), { token = key })
        end
        normalized.tokens[key] = value
    end
    return normalized
end

function ChatThemes.Register(theme)
    local value, failure = validate(theme)
    if not value then return failure end
    if themes[value.themeKey] then
        return ChatResults.Err('conflict',
            FeatherCore.Locale.translate(0, 'errorThemeConflict'))
    end
    value.ownerResource = GetInvokingResource() or GetCurrentResourceName()
    themes[value.themeKey] = value
    TriggerEvent('chat.theme.registered.v1', { themeKey = value.themeKey, schemaVersion = 1 })
    return ChatResults.Ok(copy(value))
end

function ChatThemes.Get(key)
    local theme = themes[key] or themes[Config.Theme.default]
    return theme and ChatResults.Ok(copy(theme)) or
        ChatResults.Err('not_found', FeatherCore.Locale.translate(0, 'errorThemeMissing'))
end

local function installBuiltins()
    for _, theme in ipairs(Config.Theme.themes) do ChatThemes.Register(theme) end
end

AddEventHandler('onResourceStop', function(resource)
    for key, theme in pairs(themes) do
        if theme.ownerResource == resource and resource ~= GetCurrentResourceName() then themes[key] = nil end
    end
end)

exports('RegisterTheme', ChatThemes.Register)
exports('GetTheme', ChatThemes.Get)
installBuiltins()
