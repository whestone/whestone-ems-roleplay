fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ws_police'
author 'Whestone EMS'
description 'Whestone EMS - Polizeistation: Umkleide, Waffenkammer, Fahrzeugausgabe'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
    'client/lights.lua',
    'client/interaction.lua',
    'client/towing.lua',
    'client/equipment.lua',
    'client/backup.lua',
    -- 'client/fieldtest.lua', -- freier Alkoholtest an Zivilisten deaktiviert
    --                            (Alkoholtest nur noch in der Verkehrskontrolle)
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
