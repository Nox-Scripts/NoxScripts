fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'TR75'
description 'Turbo blow-off valve + backfire sound/flame effects, networked (QBCore)'
version '1.1.1'

-- Only the backfire half actually needs qb-core (QBCore.Functions.Notify
-- for its /togglebackfire, /togglemultipop, /backfire_mode and
-- /backfire_revlimiter commands). The turbo valve half has no qb-core
-- dependency of its own, but since both live in this one resource now,
-- qb-core needs to be started first either way.
dependency 'qb-core'

-- Backfire's tunables. The turbo valve's tunables are plain local variables
-- at the top of client/turbo_valves.lua instead -- edit that file directly
-- to change BOV volume, cooldowns, auto-trigger timing, gear-shift trigger,
-- flame-on-valve, etc.
shared_scripts {
    'config.lua'
}

client_scripts {
    'client/shared_fx.lua',  -- must load first: exhaust-flame + turbo-check helpers shared by both scripts below
    'client/turbo_valves.lua',
    'client/backfire.lua'
}

server_scripts {
    'server/turbo_valves.lua',
    'server/backfire.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/sounds/*.mp3'
}
