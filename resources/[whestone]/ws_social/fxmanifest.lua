fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ws_social'
author 'Whestone EMS'
description 'Whestone EMS - Soziales/Rollenspiel: Emotes, /me & /do, Dienstzeit'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/emotes.lua',
    'client/rp.lua',
    'client/dutytime.lua',
    'client/coffee.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

files {
    'locales/*.json',
}

dependencies {
    'ws_core',
    'ox_lib',
    'ox_target',
    'oxmysql',
}
