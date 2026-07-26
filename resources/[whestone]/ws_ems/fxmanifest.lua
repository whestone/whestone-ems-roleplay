fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ws_ems'
author 'Whestone EMS'
description 'Whestone EMS - Rettungsdienst: Station, Behandlung, Transport'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@ws_core/shared/config.lua', -- WSConfig.Downed fuer die Wiederbelebung
    'config.lua',
    'shared/emergencies.lua',
}

client_scripts {
    'client/defi.lua', -- zuerst: stellt WSDefiMinigame bereit
    'client/station.lua',
    'client/treatment.lua',
    'client/callouts.lua',
    'client/revive.lua',
    'client/transport.lua',
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
