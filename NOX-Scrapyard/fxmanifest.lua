fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Custom - Scrapyard Job'
description 'Scrap extraction job - qb-target + ox_lib'
version '1.0.0'

shared_script {
    '@ox_lib/init.lua',
    'config.lua'
}

client_script 'client/main.lua'
server_script 'server/main.lua'

dependencies {
    'qb-core',
    'qb-target',
    'ox_lib',
}
