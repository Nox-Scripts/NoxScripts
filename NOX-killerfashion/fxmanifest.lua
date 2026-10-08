fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'KillerFashion Inc'
description 'KillerFashion Inc - sew clothes & bags at the sewing machines, sell them on the street (with hand props and a live placement editor)'
version '2.5.3'

ui_page 'html/audio.html'

files {
    'html/audio.html',
    'html/sounds/sewing.mp3',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/props.lua',
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

dependencies {
    'qb-core',
    'qb-target',
    'qb-inventory',
    'ox_lib',
}
