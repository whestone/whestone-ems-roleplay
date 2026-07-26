WSHud = {}

-- Skalen-Ende des Tachos (km/h)
WSHud.MaxSpeedKmh = 200

-- Aktualisierungsrate des HUD in ms (100 = 10x/Sek, fluessig genug)
WSHud.UpdateInterval = 100

-- Optionales Tanksystem. Auf enabled=false stellen = nur Tacho ohne Sprit.
WSHud.Fuel = {
    enabled = true,

    default = 100.0,     -- Fuellung, mit der ein Fahrzeug erstmals erfasst wird
    consumption = 2.0,   -- Prozent pro Minute bei Volllast (grobe Faustregel)
    lowThreshold = 15.0, -- ab diesem Stand blinkt die Tankanzeige

    -- Betankung: An diesen Zapfsaeulen-Weltobjekten kann getankt werden
    -- (ox_target). So funktioniert JEDE Tankstelle auf der Map ohne Koordinaten.
    pumpProps = {
        'prop_gas_pump_1a', 'prop_gas_pump_1b', 'prop_gas_pump_1c', 'prop_gas_pump_1d',
        'prop_gas_pump_old2', 'prop_gas_pump_old3', 'prop_vintage_pump',
    },
    refuelDistance = 6.0, -- max. Abstand Zapfsaeule <-> Fahrzeug
    refuelTime = 8000,    -- Dauer der Betankung (ms)
}
