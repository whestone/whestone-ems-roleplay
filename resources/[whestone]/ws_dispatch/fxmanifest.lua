fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ws_dispatch'
author 'Whestone EMS'
description 'Whestone EMS - Leitstelle: Callout-Engine und PvE-Einsaetze'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/callout_data.lua',
}

client_scripts {
    'client/scenario.lua',
    'client/main.lua',
    'client/transport.lua',
    'client/callouts/*.lua',
}

server_scripts {
    'server/main.lua',
}

files {
    'locales/*.json',
}

dependencies {
    'ws_core',
    'ox_target',
}
