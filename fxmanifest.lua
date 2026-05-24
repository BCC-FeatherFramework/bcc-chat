fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

game 'rdr3'
lua54 'yes'

shared_scripts {
    'config.lua',
    'locale.lua',
    'languages/en_lang.lua',
    'languages/ro_lang.lua'
}

server_script '@oxmysql/lib/MySQL.lua'

author '@iseeyoucopy BCC Scripts'
description 'RedM chat resource rebuilt on the BCC Vue structure'
version '1.0.0'

ui_page 'ui/index.html'

client_script {
    'client/client.lua'
}

server_script {
    'server/server.lua'
}

server_export 'sendAnnouncement'

dependencies {
    'oxmysql',
    'vorp_core',
    'feather-menu'
}

files {
    "ui/index.html",
    "ui/js/*.*",
    "ui/css/*.*",
    "ui/fonts/*.*",
    "ui/img/*.*"
}
