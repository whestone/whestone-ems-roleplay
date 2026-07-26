WSPolice = {}

-- Mission Row PD (alle Koordinaten anpassbar)
WSPolice.Station = {
    blip = { coords = vector3(428.4, -984.4, 30.7), sprite = 60, color = 29, scale = 0.9, label = 'Mission Row PD' },

    -- Umkleide (Spindraum)
    cloakroom = vector3(454.17, -990.63, 30.69),

    -- Waffenkammer
    armory = vector3(452.09, -980.18, 30.69),

    -- Fahrzeugausgabe (Parkplatz hinter der Wache)
    garage = vector3(457.71, -1010.84, 28.31),
    garageSpawn = vector4(449.46, -1018.83, 28.52, 93.29),
}

-- Dienstkleidung: Vanilla-Modelle (US-Setting), Freischaltung ueber minRank
WSPolice.Uniforms = {
    { label = 'Streifenpolizist',        model = 's_m_y_cop_01',       minRank = 0 },
    { label = 'Streifenpolizistin',      model = 's_f_y_cop_01',       minRank = 0 },
    { label = 'Sheriff-Deputy',          model = 's_m_y_sheriff_01',   minRank = 0 },
    { label = 'Sheriff-Deputy (w)',      model = 's_f_y_sheriff_01',   minRank = 0 },
    { label = 'Highway Patrol',          model = 's_m_y_hwaycop_01',   minRank = 1 },
    { label = 'Park Ranger',             model = 's_m_y_ranger_01',    minRank = 1 },
    { label = 'Park Ranger (w)',         model = 's_f_y_ranger_01',    minRank = 1 },
    { label = 'Detective (Zivilanzug)',  model = 's_m_m_fiboffice_01', minRank = 3 },
    { label = 'SWAT-Einsatzanzug',       model = 's_m_y_swat_01',      minRank = 4 },
}

-- Zivilmodell nach Dienstende
WSPolice.CivilianModel = 'mp_m_freemode_01'

-- Loadouts: [Waffe] = Munition (0 = Nahkampf/keine Munition)
WSPolice.Loadouts = {
    standard = {
        minRank = 0,
        label = 'Standard-Ausrüstung',
        weapons = {
            { 'WEAPON_COMBATPISTOL', 120 },
            { 'WEAPON_STUNGUN', 5 },
            { 'WEAPON_NIGHTSTICK', 0 },
            { 'WEAPON_FLASHLIGHT', 0 },
        },
    },
    rifle = {
        minRank = 3,
        label = 'Gewehrschrank',
        weapons = {
            { 'WEAPON_CARBINERIFLE', 180 },
        },
    },
}

-- Skill-Waffenschrank: Freischaltung ueber das Skillsystem (Tablet -> Skills)
WSPolice.SkillWeapons = {
    [1] = { label = 'SMG', weapons = { { 'WEAPON_SMG', 120 } } },
    [2] = { label = 'Pumpgun', weapons = { { 'WEAPON_PUMPSHOTGUN', 24 } } },
    [3] = { label = 'Marksman-Gewehr', weapons = { { 'WEAPON_MARKSMANRIFLE', 60 } } },
}

-- Fahrzeug-Tuning je Fahrzeug-Skill-Level (beim Ausparken angewendet)
WSPolice.VehicleTuning = {
    [1] = { engine = 1, brakes = 1 },
    [2] = { engine = 2, brakes = 2, transmission = 1, turbo = true },
    [3] = { engine = 3, brakes = 2, transmission = 2, suspension = 3, turbo = true, armor = 4, bulletproofTires = true },
}

-- Anhaltezeichen (Taste U): stoppt anvisierte Fahrzeuge und Personen
WSPolice.Stop = {
    range = 30.0,   -- max. Distanz in Metern
    duration = 20,  -- Sekunden, die Fahrzeuge/Personen stehen bleiben
    cooldown = 3,   -- Sekunden zwischen zwei Anhaltezeichen
}

-- Ausruestungsmenue (Taste F6): platzierbare Absperr-Objekte
WSPolice.Equipment = {
    maxProps = 30, -- max. gleichzeitig platzierte eigene Objekte
    props = {
        cone    = { model = 'prop_mp_cone_02',        forward = 1.2 },
        barrier = { model = 'prop_barrier_work05',    forward = 2.2 },
        spike   = { model = 'p_ld_stinger_s',         forward = 2.5 },
    },
}

-- KI-Verstaerkung (Taste F7): eine Streife faehrt an und unterstuetzt.
-- Freischaltung und Ausbaustufe ueber den Skill-Zweig "Unterstuetzung"
-- (ws:skill_support). OHNE Skillpunkt (Stufe 0) gibt es KEINE Verstaerkung.
WSPolice.Backup = {
    cooldown = 60,            -- Sekunden zwischen zwei Anforderungen
    despawnDistance = 150.0,  -- entfernt sich der Officer weiter, verschwindet die Streife

    -- Stufe 1-3 des Unterstuetzungs-Skills. `officers` = Anzahl Beamte je Stufe
    -- (frei einstellbar, Standard 2; wird auf die Sitzplaetze des Fahrzeugs
    -- begrenzt). `label` erscheint in der Leitstellen-Auswahl im Tablet.
    Tiers = {
        [1] = { vehicle = 'police',  ped = 's_m_y_cop_01',  weapon = 'WEAPON_PISTOL',       armour = 50,  accuracy = 55, officers = 2, label = 'Streife (Stanier) · Pistolen' },
        [2] = { vehicle = 'police3', ped = 's_m_y_cop_01',  weapon = 'WEAPON_SMG',          armour = 75,  accuracy = 65, officers = 2, label = 'Interceptor · MPs' },
        [3] = { vehicle = 'riot',    ped = 's_m_y_swat_01', weapon = 'WEAPON_CARBINERIFLE', armour = 100, accuracy = 80, officers = 2, label = 'Riot · NOOSE (Sturmgewehre)' },
    },
}

-- Dienstfahrzeuge (Vanilla-Modelle), Rangbeschraenkung ueber minRank
WSPolice.Vehicles = {
    { model = 'police',     label = 'Streifenwagen (Stanier)',     minRank = 0 },
    { model = 'police2',    label = 'Streifenwagen (Buffalo)',     minRank = 1 },
    { model = 'policet',    label = 'Gefangenentransporter',       minRank = 1 },
    { model = 'pranger',    label = 'Park Ranger (Granger)',       minRank = 1 },
    { model = 'police3',    label = 'Interceptor',                 minRank = 2 },
    { model = 'policeb',    label = 'Polizeimotorrad',             minRank = 2 },
    { model = 'policeb2',   label = 'Polizeimotorrad (neu)',       minRank = 2 },
    { model = 'polfaction2',label = 'Faction Cruiser',             minRank = 2 },
    { model = 'sheriff',    label = 'Sheriff Cruiser',             minRank = 2 },
    { model = 'polcaracara',label = 'Caracara Verfolgung (4x4)',   minRank = 3 },
    { model = 'polterminus',label = 'Terminus (Offroad)',          minRank = 3 },
    { model = 'polcoquette4', label = 'Coquette Pursuit',          minRank = 4 },
    { model = 'polbuffalo6',label = 'Buffalo STX',                 minRank = 3 },
    { model = 'sheriff2',   label = 'Sheriff SUV (Granger)',       minRank = 3 },
    { model = 'police4',    label = 'Zivilstreife (unmarkiert)',   minRank = 3 },
    { model = 'fbi',        label = 'Zivilfahrzeug (Buffalo)',     minRank = 4 },
    { model = 'fbi2',       label = 'Zivilfahrzeug (Granger)',     minRank = 4 },
    { model = 'riot',       label = 'SWAT Riot',                   minRank = 5 },
    { model = 'pbus',       label = 'Gefangenenbus',               minRank = 5 },
    { model = 'polgauntlet',label = 'Gauntlet',                    minRank = 5 },
}
