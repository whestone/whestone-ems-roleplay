WSFire = {}

-- Feuerwache (Davis / El Rancho). Koordinaten im Spiel feinjustierbar.
WSFire.Station = {
    blip = { coords = vector3(1193.6, -1465.0, 35.0), sprite = 436, color = 47, scale = 0.9, label = 'Feuerwache' },

    cloakroom  = vector3(1195.2455, -1477.6442, 34.8596),   -- Umkleide
    supply     = vector3(1194.9385, -1470.4056, 34.8596),   -- Ausruestung (Feuerloescher + Weste)
    garage     = vector3(1197.6178, -1474.1884, 34.8596),   -- Fahrzeugausgabe (Fahrzeugauswahl)
    garageSpawn = vector4(1200.7523, -1458.8905, 34.9342, 0.1872), -- Autospawn (LF, im Freien vor der Halle)
}

-- Dienstkleidung. Vanilla hat nur EINEN Feuerwehr-Ped (s_m_y_fireman_01),
-- Varianten daher ueber Komponenten/Props (Helm an/aus etc.).
-- id = eindeutiger Rueckgabewert; ped = Modell; image = Vorschaubild (default ped);
-- components/props = { [slot] = drawable }. props = {} -> alle Props (Helm) weg.
-- Drawable-Indizes ggf. im Spiel feinjustieren.
WSFire.Uniforms = {
    { id = 'ff_full',   label = 'Vollmontur (Helm)', ped = 's_m_y_fireman_01', minRank = 0, props = { [0] = 0 } },
    { id = 'ff_nohelm', label = 'Ohne Helm',         ped = 's_m_y_fireman_01', minRank = 0, props = {} },
    { id = 'ff_scba',   label = 'Atemschutz',        ped = 's_m_y_fireman_01', minRank = 0, components = { [11] = 1, [8] = 1 }, props = { [0] = 0 } },
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
        power = 55.0,   -- Loeschkraft pro Sekunde
    },
    -- Wasserwerfer (im/am Loeschfahrzeug, Taste halten)
    cannon = {
        range = 34.0,
        power = 120.0,  -- deutlich staerker als der Handloescher
    },
    -- Jeder Brandherd hat 750 "Leben"; Wasser reduziert es bis 0 = geloescht.
    -- Der Feuerwehr-Skill (firefighting) macht das Loeschen schneller.
    -- Richtwerte Loeschdauer je Herd: Loescher ~14 s, Wasserwerfer ~6 s.
    pointHealth = 750.0,
    skillBonus = 0.20, -- +20% Loeschkraft je Skill-Stufe
    -- Trefferbreite des Wasserstrahls (senkrechter Abstand zur Ziellinie, Meter):
    hitRadius = 1.8,      -- Handloescher: schmal & praezise, loescht EINEN Herd
    cannonRadius = 4.5,   -- Wasserwerfer: breiterer Strahl
    cannonArea = false,   -- Wasserwerfer: true = Flaeche (alle Herde im Strahl), false = nur ein Herd
}

-- Notruf-Engine (wie beim Rettungsdienst)
WSFire.Callout = {
    intervalMin = 140,
    intervalMax = 320,
    acceptTimeout = 90,
    perCallout = 2,        -- 1 gleichzeitiger Einsatz je N Feuerwehrleute im Dienst
    spawnDistance = 220.0, -- Feuer erst entzuenden, wenn jemand naeher ist
}
