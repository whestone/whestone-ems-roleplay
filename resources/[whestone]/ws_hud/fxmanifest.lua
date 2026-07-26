fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ws_hud'
author 'Whestone EMS'
description 'Whestone EMS - Fahrzeug-HUD: Tacho, Motor-/Blaulichtstatus, Tank'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/fuel.lua', -- zuerst: stellt WSFuel bereit
    'client/hud.lua',
}

ui_page 'html/hud.html'

files {
    'locales/*.json',
    'html/hud.html',
}

dependencies {
    'ox_lib',
    'ox_target',
}
