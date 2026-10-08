

author 'TrapRepublic'
description 'TrapRepublic-BikeTrikz - Auto Wheelie + Shift-Arrow Trick Poses (merged build)'
version '1.0.0'

lua54 'yes'

fx_version 'cerulean'
game 'gta5'

shared_scripts {
    'Config.lua',
}

client_scripts {
    'Client/*.lua',
}

server_scripts {
    'server/sv.lua',
}

files {
    'data/handling.meta',
}

data_file 'HANDLING_FILE' 'data/handling.meta'