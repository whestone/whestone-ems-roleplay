WSDispatch = {}

-- Abstand zwischen automatisch generierten Callouts (Sekunden, zufaellig im Bereich)
WSDispatch.IntervalMin = 120
WSDispatch.IntervalMax = 300

-- Verstreicht diese Zeit ohne Annahme, verfaellt der Einsatz (Sekunden)
WSDispatch.AcceptTimeout = 90

-- 1 gleichzeitiger Einsatz je angefangene N Officer im Dienst
WSDispatch.OfficersPerCallout = 3

-- Szenario wird erst aufgebaut, wenn der Primary-Officer naeher als X Meter ist
WSDispatch.SpawnDistance = 220.0

-- XP-Bonus je eingeliefertem Verdaechtigen (zusaetzlich zur Einsatz-XP)
WSDispatch.ArrestXP = 25

-- XP fuer die Uebergabe an den Gefangenentransport (bequemer als
-- Eigenlieferung zur Wache, daher weniger XP)
WSDispatch.TransportXP = 15

-- Durchsuchung von Verdaechtigen: einmalig je Verdaechtigem moeglich.
-- Fundstuecke mit Wahrscheinlichkeit (chance) und XP; Summe < 100 laesst
-- Raum fuer "nichts gefunden".
WSDispatch.SearchFinds = {
    { item = 'find_weapon', chance = 40, xp = 20 },
    { item = 'find_drugs',  chance = 25, xp = 15 },
    { item = 'find_loot',   chance = 15, xp = 10 },
}

-- Einsatz-XP skaliert mit der Festnahmequote: alle festgenommen = 100%,
-- keiner festgenommen (erschossen/entkommen) = nur dieser Mindestanteil
WSDispatch.MinXPFactor = 0.4

-- Gefangenenuebergabe (Bookingpoint): Parkplatz hinter Mission Row PD
WSDispatch.JailDropoff = vector4(476.57, -1022.08, 28.05, 272.54)

-- Max. Distanz Spieler <-> Uebergabepunkt fuer "Einliefern"
WSDispatch.DeliverRadius = 10.0
