WSSocial = {}

-- Reichweite (Meter), in der /me- und /do-Texte fuer andere sichtbar sind
WSSocial.RpRange = 20.0

-- Anzeigedauer der schwebenden RP-Texte in ms
WSSocial.RpDuration = 8000

-- Dienstzeit-Rangliste: wie viele Plaetze anzeigen
WSSocial.BoardSize = 10

-- Kaffeeautomaten: Weltobjekte dieser Modelle werden per ox_target nutzbar -
-- damit funktioniert JEDER Kaffeeautomat auf der Map ohne feste Koordinaten.
WSSocial.CoffeeProps = { 'prop_vend_coffe_01' }

-- Zusaetzliche feste Automaten-Standorte (z.B. an einer Wache, wo kein
-- Weltobjekt steht). Eigene vector3-Koordinaten eintragen:
WSSocial.CoffeeMachines = {
    -- vector3(454.0, -992.0, 30.7),
}

-- Kaffee stellt die Sprint-Ausdauer wieder her (Flavor, kein XP)
WSSocial.CoffeeRestoreStamina = true

-- Emotes. Zwei Formen moeglich:
--   scenario = 'WORLD_HUMAN_...'  (selbststaendig, kein Anim-Dict noetig)
--   anim = { dict = '...', clip = '...', flag = 1 }
-- Jede Bewegung beendet das Emote automatisch.
WSSocial.Emotes = {
    -- Fuer alle Fraktionen
    general = {
        { label = 'Arme verschränken', scenario = 'WORLD_HUMAN_GUARD_STAND' },
        { label = 'Anlehnen',          scenario = 'WORLD_HUMAN_LEANING' },
        { label = 'Rauchen',           scenario = 'WORLD_HUMAN_SMOKING' },
        { label = 'Kaffee trinken',    scenario = 'WORLD_HUMAN_AA_COFFEE' },
        { label = 'Trinken',           scenario = 'WORLD_HUMAN_DRINKING' },
        { label = 'Handy benutzen',    scenario = 'WORLD_HUMAN_STAND_MOBILE' },
        { label = 'Herumstehen',       scenario = 'WORLD_HUMAN_HANG_OUT_STREET' },
        { label = 'Hände hoch',        anim = { dict = 'missminuteman_1ig_2', clip = 'handsup_base', flag = 49 } },
    },
    -- Nur Polizei
    police = {
        { label = 'Streifen-Idle',     scenario = 'WORLD_HUMAN_COP_IDLES' },
        { label = 'Klemmbrett',        scenario = 'WORLD_HUMAN_CLIPBOARD' },
        { label = 'Fernglas',          scenario = 'WORLD_HUMAN_BINOCULARS' },
        { label = 'Wache stehen',      scenario = 'WORLD_HUMAN_GUARD_PATROL' },
    },
    -- Nur Rettungsdienst
    ambulance = {
        { label = 'Patient versorgen', scenario = 'CODE_HUMAN_MEDIC_TEND_TO_DEAD' },
        { label = 'Klemmbrett',        scenario = 'WORLD_HUMAN_CLIPBOARD' },
    },
}
