WSConfig = {}

-- Standard-Job, falls noch keiner gewaehlt wurde
WSConfig.DefaultJob = 'police'

WSConfig.Jobs = {
    police = {
        label = 'Los Santos Police Department',
        short = 'LSPD',
        blipColor = 29,
        -- Skill-Zweige dieses Jobs (Progression ist je Job getrennt)
        skills = { 'weapons', 'vehicles', 'stamina' },
        -- Vordereingang Mission Row PD
        spawn = vector4(428.23, -984.28, 30.71, 176.0),
        -- Befoerderung erfolgt automatisch beim Erreichen der XP-Schwelle
        ranks = {
            [0] = { name = 'cadet',      label = 'Polizeianwärter', xp = 0 },
            [1] = { name = 'officer',    label = 'Officer',         xp = 300 },
            [2] = { name = 'senior',     label = 'Senior Officer',  xp = 1000 },
            [3] = { name = 'sergeant',   label = 'Sergeant',        xp = 2500 },
            [4] = { name = 'lieutenant', label = 'Lieutenant',      xp = 6000 },
            [5] = { name = 'captain',    label = 'Captain',         xp = 12000 },
            [6] = { name = 'chief',      label = 'Chief of Police', xp = 25000 },
        },
    },
    ambulance = {
        label = 'Los Santos Medical Services',
        short = 'EMS',
        blipColor = 1,
        skills = { 'medic', 'vehicles', 'stamina' },
        -- Vordereingang Pillbox Hill Medical Center
        spawn = vector4(305.3, -1433.4, 30.0, 240.0),
        ranks = {
            [0] = { name = 'trainee',   label = 'Praktikant',        xp = 0 },
            [1] = { name = 'emt',       label = 'Rettungssanitäter', xp = 300 },
            [2] = { name = 'paramedic', label = 'Notfallsanitäter',  xp = 1000 },
            [3] = { name = 'senior',    label = 'Senior Paramedic',  xp = 2500 },
            [4] = { name = 'doctor',    label = 'Notarzt',           xp = 6000 },
            [5] = { name = 'chief',     label = 'Ärztlicher Leiter', xp = 12000 },
            [6] = { name = 'director',  label = 'Klinikdirektor',    xp = 25000 },
        },
    },
}

-- Fallback-Spawn (falls Job keinen eigenen spawn hat)
WSConfig.DefaultSpawn = vector4(428.23, -984.28, 30.71, 176.0)

-- true = beim Verbinden immer an der Job-Station spawnen (statt letzter Position)
WSConfig.AlwaysSpawnAtStation = true

-- Job-Auswahl beim Verbinden anzeigen (EMS/LSPD)
WSConfig.JobSelectOnJoin = true

-- Aussichtspunkt waehrend der Fraktionsauswahl (Dach des Maze Bank Tower).
-- Der Spieler steht dort eingefroren und unverwundbar; ueber einen eigenen
-- Routing-Bucket ist er zusaetzlich fuer alle anderen Spieler unsichtbar.
-- Auf nil setzen = Auswahl findet am normalen Spawn statt.
WSConfig.JobSelectLobby = vector4(-75.7, -818.6, 326.17, 130.0)

-- Respawn nach Tod: Pillbox Hill Medical Center
WSConfig.DeathSpawn = vector4(341.0, -1397.3, 32.51, 48.5)

-- Handlungsunfaehig ("am Boden") statt sofortigem Tod: Wer stirbt, geht zu
-- Boden und kann vom Rettungsdienst wiederbelebt werden. Laeuft die Zeit ab
-- oder gibt der Spieler auf, greift der normale Respawn (DeathSpawn).
WSConfig.Downed = {
    enabled = true,
    bleedoutTime = 300,     -- Sekunden am Boden, bevor man endgueltig stirbt
    giveUpAfter = 30,       -- Sekunden, bevor /aufgeben erlaubt ist
    reviveHealth = 0.5,     -- Gesundheit nach Wiederbelebung (Anteil vom Maximum)
    reviveDuration = 10000, -- ms Behandlungsdauer (Medizin-Skill verkuerzt)
    reviveXP = 100,         -- XP fuer den Sanitaeter
    alertEms = true,        -- automatischer Notruf an alle EMS im Dienst
}

-- Roller-Reihe am Krankenhaus (fuer Spieler nach dem Respawn):
-- Spawnpunkte werden linear zwischen from und to verteilt
WSConfig.HospitalVehicles = {
    model = 'faggio',
    from = vector4(300.42, -1389.09, 31.31, 98.79),
    to = vector4(317.93, -1368.05, 31.81, 98.79),
    spacing = 2.0,       -- Abstand zwischen den Rollern in Metern
    despawnMinutes = 10, -- verlassene (weggefahrene) Roller nach X Minuten loeschen
}

-- Speicherintervall in Minuten
WSConfig.SaveInterval = 5

-- Alle Tueren des GTA-Tuersystems entriegeln (z.B. Bank-Schaltertueren),
-- damit hinter Tresen gespawnte Verdaechtige erreichbar sind
WSConfig.UnlockAllDoors = true

-- Skillsystem: max. Stufe je Zweig (weapons/vehicles/stamina);
-- 1 Skillpunkt pro Befoerderung, Verteilung ueber das Tablet
WSConfig.MaxSkillLevel = 3

-- Ausdauer-Skill: Stamina-Regeneration pro Sekunde je Stufe (1.0 = voll)
WSConfig.StaminaRegen = { [1] = 0.25, [2] = 0.6, [3] = 1.0 }
