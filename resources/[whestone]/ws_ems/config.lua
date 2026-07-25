WSEms = {}

-- Pillbox Hill Medical Center (alle Koordinaten anpassbar)
WSEms.Station = {
    blip = { coords = vector3(305.3, -1433.4, 30.5), sprite = 61, color = 1, scale = 0.9, label = 'Pillbox Medical' },

    -- Umkleide
    cloakroom = vector3(306.77, -1432.63, 29.97),

    -- Ausruestung / Notfallrucksack
    supply = vector3(308.3, -1433.9, 30.5),

    -- Fahrzeugausgabe (Parkplatz vor dem Krankenhaus)
    garage = vector3(295.76, -1447.65, 29.97),
    garageSpawn = vector4(315.37, -1448.08, 29.8, 226.49),

    -- Einlieferung: Patienten hier abgeben (Notaufnahme)
    dropoff = vector4(294.49, -1439.35, 29.8, 49.94),
}

-- Helipad auf dem Pillbox-Dach
WSEms.Helipad = {
    spawn = vector4(313.31, -1465.15, 46.51, 315.19),   -- Heli-Spawnpunkt
    menu = vector3(314.05, -1451.99, 46.51),            -- Ausparkmenü
    dropoff = vector4(299.43, -1453.45, 46.51, 328.88), -- Patientenabgabe (Dach)
    elevator = {
        up = vector4(334.75, -1432.86, 46.51, 136.61),   -- Dach -> Erdgeschoss
        down = vector4(293.61, -1447.64, 29.97, 138.26), -- Erdgeschoss -> Dach
    },
}

-- Rettungshelikopter (livery 1 = Air-Ambulance-Lackierung des polmav)
WSEms.Helicopters = {
    { model = 'polmav', label = 'Air Ambulance (Maverick)', livery = 1, minRank = 2 },
}

-- Dienstkleidung (Vanilla-Modelle). EMS hat in Vanilla nur maennliche Peds.
WSEms.Uniforms = {
    { label = 'Rettungssanitäter',      model = 's_m_m_paramedic_01', minRank = 0 },
    { label = 'Notarzt (weißer Kittel)', model = 's_m_m_doctor_01',    minRank = 4 },
}

-- Zivilmodell nach Dienstende
WSEms.CivilianModel = 'mp_m_freemode_01'

-- Rettungsfahrzeuge (Vanilla-Fuhrpark ist begrenzt; Addons einfach ergaenzen)
WSEms.Vehicles = {
    { model = 'ambulance', label = 'Rettungswagen (RTW)',    minRank = 0 },
    { model = 'lguard',    label = 'Lifeguard SUV (Granger)', minRank = 1 },
}

-- Ausruestung (Notfallrucksack): Selbstheilung + Weste beim Dienstantritt
WSEms.SupplyHealsSelf = true

-- XP-Belohnungen
WSEms.XP = {
    diagnose = 10,  -- Patient untersuchen
    treat = 40,     -- erfolgreich behandeln/reanimieren
    deliver = 60,   -- Patient ins Krankenhaus einliefern
}

-- Max. Distanz Sanitaeter <-> Notaufnahme fuer die Einlieferung
WSEms.DeliverRadius = 12.0

-- Behandlungsdauer (ms)
WSEms.Durations = {
    diagnose = 4000,
    treat = 8000,
}

-- Schwierigkeit des Defibrillator-Minispiels (lib.skillCheck):
-- moegliche Werte 'easy' | 'medium' | 'hard', beliebig viele Runden
WSEms.DefiChecks = { 'easy', 'easy', 'medium' }

-- Notfall-Engine
WSEms.Callout = {
    intervalMin = 120,     -- Sekunden zwischen Notfaellen (Bereich)
    intervalMax = 300,
    acceptTimeout = 90,    -- Sekunden bis ein nicht angenommener Notfall verfaellt
    perCallout = 2,        -- 1 gleichzeitiger Notfall je N Sanitaeter im Dienst
    spawnDistance = 200.0, -- Patient erst spawnen, wenn Sanitaeter naeher ist
}
