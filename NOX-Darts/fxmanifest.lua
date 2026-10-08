fx_version "cerulean"
game "gta5"
lua54 "yes"

author "Prodigy Studios"
version "1.0.1"

shared_scripts {
    "@ox_lib/init.lua",
    "editable/sh_*.lua",
}

client_scripts {
    "bridge/client.lua",
    "editable/cl_*.lua",
    "client/*.lua",
}

server_scripts {
    "@oxmysql/lib/MySQL.lua",
    "bridge/server.lua",
    "editable/sv_*.lua",
    "server/*.lua",
}

escrow_ignore {
    "editable/*.lua",
    "bridge/*.lua",
}

files {
    "dui/*",
    "dui/img/*",
    "locales/*.json"
}
dependencies {
    'ox_lib',
    'oxmysql',
    'qb-core',
    'NOX-DartsAssets',
}
