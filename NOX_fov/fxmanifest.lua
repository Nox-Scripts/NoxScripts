fx_version 'cerulean'
game 'gta5'

author 'DX3'
description 'DX3_Fov — Ultimate Edition v3.0'
version '3.0.0'

shared_script 'config.lua'

client_scripts {
    'client/fovdriver.lua',
    'client/effects.lua',
    'client/hud.lua',
    'client/footfov.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}
