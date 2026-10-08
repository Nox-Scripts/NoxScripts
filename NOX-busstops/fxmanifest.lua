fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qb-busstops'
author 'NOX'
description 'Advanced Bus Stop Travel System - QBCore + qb-target + ox_lib'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

dependencies {
    'qb-core',
    'qb-target',
    'qb-inventory',
    'ox_lib'
}
