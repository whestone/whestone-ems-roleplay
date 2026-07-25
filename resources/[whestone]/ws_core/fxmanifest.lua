fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ws_core'
author 'Whestone EMS'
description 'Whestone EMS - Framework-Kern: Charaktere, Duty, Raenge, PvE-Regeln'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

client_scripts {
    'client/downed.lua', -- vor main.lua: stellt WSDowned fuer den Respawn-Pfad bereit
    'client/main.lua',
    'client/pve.lua',
    'client/doors.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/downed.lua',
    'server/hospital_vehicles.lua',
}

ui_page 'html/jobselect.html'

files {
    'locales/*.json',
    'html/jobselect.html',
}

dependencies {
    'ox_lib',
    'oxmysql',
}
