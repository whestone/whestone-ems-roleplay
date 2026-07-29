WSFire = {}

-- Feuerwache (Davis / El Rancho). Koordinaten im Spiel feinjustierbar.
WSFire.Station = {
    blip = { coords = vector3(1193.6, -1465.0, 35.0), sprite = 436, color = 47, scale = 0.9, label = 'Feuerwache' },

    cloakroom  = vector3(1193.6, -1470.5, 34.9),   -- Umkleide
    supply     = vector3(1197.6, -1470.5, 34.9),   -- Ausruestung (Feuerloescher + Weste)
    garage     = vector3(1198.0, -1455.0, 34.9),   -- Fahrzeugausgabe (vor den Toren)
    garageSpawn = vector4(1189.0, -1448.0, 35.0, 265.0),
}

-- Dienstkleidung (Vanilla hat nur einen Feuerwehr-Ped)
WSFire.Uniforms = {
    { label = 'Feuerwehrmann', model = 's_m_y_fireman_01', minRank = 0 },
}

WSFire.CivilianModel = 'mp_m_freemode_01'

-- Fahrzeuge (Vanilla-Fuhrpark; Addons einfach ergaenzen)
WSFire.Vehicles = {
    { model = 'firetruk', label = 'Löschfahrzeug (LF)', minRank = 0 },
}

-- Ausruestung beim Dienstantritt: Feuerloescher + Schutzweste + Selbstheilung
WSFire.Supply = { extinguisher = true, heal = true, armour = 50 }

-- XP-Belohnungen
WSFire.XP = {
    extinguish = 15,  -- je geloeschtem Brandherd
    complete = 50,    -- Abschluss-Bonus, wenn der ganze Einsatz aus ist
}

-- Loeschmechanik
WSFire.Firefighting = {
    -- Feuerloescher (zu Fuss)
    extinguisher = {
        weapon = 'WEAPON_FIREEXTINGUISHER',
        range = 9.0,    -- Reichweite des Sprühstrahls
        radius = 2.6,   -- Wirkradius am Auftreffpunkt
        power = 55.0,   -- Loeschkraft pro Sekunde (Brandherd-"Leben" = 100)
    },
    -- Wasserwerfer (im/am Loeschfahrzeug, Taste halten)
    cannon = {
        range = 34.0,
        radius = 5.5,
        power = 120.0,  -- deutlich staerker als der Handloescher
    },
    -- Jeder Brandherd hat 100 "Leben"; Wasser reduziert es bis 0 = geloescht.
    -- Der Feuerwehr-Skill (firefighting) macht das Loeschen schneller.
    pointHealth = 100.0,
    skillBonus = 0.20, -- +20% Loeschkraft je Skill-Stufe
}

-- Notruf-Engine (wie beim Rettungsdienst)
WSFire.Callout = {
    intervalMin = 140,
    intervalMax = 320,
    acceptTimeout = 90,
    perCallout = 2,        -- 1 gleichzeitiger Einsatz je N Feuerwehrleute im Dienst
    spawnDistance = 220.0, -- Feuer erst entzuenden, wenn jemand naeher ist
}
