fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'bcc-chat'
author '@iseeyoucopy BCC Scripts / Feather Framework adaptation'
description 'BCC Chat adapted to Feather Contract 1'
version '1.2.0'

shared_scripts {
    'config.lua',
    'shared/results.lua',
    'shared/imports.lua',
    'locale/*.lua'
}

client_scripts {
    'client/imports.lua',
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/migrations.lua',
    'server/persistence.lua',
    'server/foundation.lua',
    'server/discord.lua',
    'server/roles.lua',
    'server/channels.lua',
    'server/moderation.lua',
    'server/themes.lua',
    'server/main.lua'
}

ui_page 'ui/dist/index.html'

files {
    "ui/dist/index.html",
    "ui/dist/js/*.*",
    "ui/dist/css/*.*",
    "ui/dist/img/*.*"
}

dependencies {
    'oxmysql',
    'feather-core',
    'feather-character',
    'feather-roles',
    'feather-toolkit'
}
