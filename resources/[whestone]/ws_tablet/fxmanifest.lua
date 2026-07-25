fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ws_tablet'
author 'Whestone EMS'
description 'Whestone EMS - Polizei-Tablet: Einsatzuebersicht, Beamte, Leitstelle'
version '0.1.0'

ui_page 'html/index.html'

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
    'html/index.html',
    'locales/*.json',
}

dependencies {
    'ws_core',
    'ws_dispatch',
}
