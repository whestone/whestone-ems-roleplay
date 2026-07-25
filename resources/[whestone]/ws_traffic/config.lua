WSTraffic = {}

-- XP-Belohnungen
WSTraffic.WarnXP = 8    -- Verwarnung (immer)
WSTraffic.TicketXP = 25 -- Bussgeld, nur bei tatsaechlichem Verstoss
-- Festnahme-XP kommen aus ws_dispatch (Einlieferung 25 / Transport 15)

-- Wahrscheinlichkeiten fuer den generierten Datensatz (0-100)
WSTraffic.Chances = {
    licenseExpired = 15, -- Fuehrerschein abgelaufen
    licenseRevoked = 8,  -- Fuehrerschein entzogen
    noRegistration = 12, -- Zulassung fehlt
    drunk = 18,          -- alkoholisiert
    contraband = 15,     -- Schmuggelware im Fahrzeug
    -- Anteil der ertappten Fahrer, die bei der Festnahme fliehen:
    fleeRisk = 40,
}

-- Zufaellige Fahrernamen fuer den Datensatz
WSTraffic.Names = {
    'Michael Torres', 'Sandra Klein', 'Kevin Brooks', 'Laura Meyer',
    'Andre Dubois', 'Jessica Wong', 'Tobias Faber', 'Nadine Roth',
    'Marcus Hill', 'Elena Petrova', 'Frank Wagner', 'Chantal Berg',
    'Dennis Kaya', 'Sophie Lindqvist', 'Roman Novak', 'Melanie Voss',
}

-- Dauer der Aktionen in Millisekunden
WSTraffic.Durations = {
    papers = 3000,
    breath = 5000,
    search = 5000,
}
