fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ws_fire'
author 'Whestone EMS'
description 'Whestone EMS - Feuerwehr: Wache, Löschfahrzeug, echte Brände'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/fires.lua',
}

client_scripts {
    'client/station.lua',
    'client/callouts.lua',
    'client/firefighting.lua',
}

server_scripts {
    'server/main.lua',
    'server/callouts.lua',
}

files {
    'locales/*.json',
}

dependencies {
    'ws_core',
    'ox_target',
}
