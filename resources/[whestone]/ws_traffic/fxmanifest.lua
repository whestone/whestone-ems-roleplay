fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ws_traffic'
author 'Whestone EMS'
description 'Whestone EMS - Verkehrskontrollen'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

files {
    'locales/*.json',
}

dependencies {
    'ws_core',
    'ws_dispatch',
    'ox_target',
}
