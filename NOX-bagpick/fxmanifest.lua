fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'NOX Bagpick'
author 'NOX'
version '1.0.0'

shared_scripts {
    'config.lua',
    'bridge/shared.lua',
    'locales/locales.lua',
    'locales/fr.lua',
    'locales/en.lua'
}

client_scripts {
    'bridge/client.lua',
    'client/client.lua'
}

server_scripts {
    'bridge/server.lua',
    'server/server.lua'
}
