-- Brand-Stammdaten. `points` = Anzahl Brandherde (zufaellig min..max), jeder
-- muss geloescht werden. `intensity` = Feuer je Herd (Groesse des Brandes).
-- `spread` = Ausbreitung (maxChildren). `gas` = Benzinbrand.
-- `vehicle` = ein ausbrennendes Fahrzeug wird mit gespawnt.
-- Alle Orte liegen im STADTGEBIET von Los Santos.

WSFire.Fires = {
    vehicle = {
        label = 'Fahrzeugbrand',
        code = 'Brand F1',
        points = { 1, 2 },
        intensity = 5,
        spread = 1,
        gas = true,
        vehicle = true,
        locations = {
            vector4(-47.0, -1759.0, 29.4, 50.0),    -- Davis
            vector4(1136.0, -770.0, 57.9, 100.0),   -- Mirror Park
            vector4(-536.0, -270.0, 35.6, 210.0),   -- Rockford Hills
            vector4(820.0, -1290.0, 26.3, 90.0),    -- La Mesa
            vector4(240.0, -1379.0, 33.7, 320.0),   -- nahe Pillbox
            vector4(-1220.0, -900.0, 11.9, 30.0),   -- Morningwood
            vector4(-260.0, -960.0, 31.2, 160.0),   -- Downtown
        },
    },
    dumpster = {
        label = 'Müllcontainerbrand',
        code = 'Brand F1',
        points = { 1, 1 },
        intensity = 4,
        spread = 0,
        gas = false,
        locations = {
            vector4(-180.0, -1290.0, 31.3, 0.0),    -- Strawberry
            vector4(276.0, -930.0, 29.3, 90.0),     -- Downtown Gasse
            vector4(-620.0, -1030.0, 22.3, 180.0),  -- Little Seoul
            vector4(1130.0, -470.0, 66.6, 250.0),   -- Mirror Park Blvd
            vector4(80.0, -1930.0, 21.1, 315.0),    -- Chamberlain Hills
            vector4(470.0, -1315.0, 29.2, 200.0),   -- La Mesa Gewerbe
        },
    },
    building = {
        label = 'Gebäudebrand',
        code = 'Brand F3',
        points = { 3, 5 },
        intensity = 6,
        spread = 2,
        gas = false,
        locations = {
            vector4(-14.0, -1444.0, 31.1, 270.0),   -- Strawberry Ave
            vector4(266.0, -580.0, 43.2, 70.0),     -- Pillbox Hill
            vector4(-320.0, -720.0, 33.5, 180.0),   -- Alta St
            vector4(1213.0, -1590.0, 53.6, 20.0),   -- El Burro Heights
            vector4(-810.0, -1080.0, 11.1, 120.0),  -- Vespucci
            vector4(340.0, -200.0, 54.1, 250.0),    -- Vinewood
        },
    },
    brush = {
        label = 'Flächenbrand',
        code = 'Brand F2',
        points = { 2, 4 },
        intensity = 5,
        spread = 3,
        gas = false,
        -- Gruenflaechen/Brachen INNERHALB der Stadt (kein Umland)
        locations = {
            vector4(-90.0, -1820.0, 26.7, 0.0),     -- Chamberlain Hills Brache
            vector4(-1300.0, -1490.0, 4.4, 0.0),    -- Del Perro Beach Gras
            vector4(1240.0, -1560.0, 52.6, 0.0),    -- El Burro Gras
            vector4(360.0, -690.0, 28.9, 0.0),      -- Downtown Brache
            vector4(-560.0, -1780.0, 20.0, 0.0),    -- Elysian Gewerbegras
            vector4(180.0, -1650.0, 29.3, 0.0),     -- Davis Gruenstreifen
        },
    },
}
