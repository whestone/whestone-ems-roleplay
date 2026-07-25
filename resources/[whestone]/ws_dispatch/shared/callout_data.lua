-- Einsatz-Stammdaten (Server waehlt Typ + Ort, Client fuehrt Szenario aus).
-- Neue Callouts: Eintrag hier ergaenzen + Handler-Datei unter client/callouts/.
-- Koordinaten sind Startwerte und koennen frei angepasst/ergaenzt werden.

CalloutData = {
    traffic_accident = {
        label = 'Verkehrsunfall',
        code = 'Code 2',
        xp = 60,
        locations = {
            vector4(295.3, -584.7, 43.26, 0.0),     -- Pillbox Hill, Klinikviertel
            vector4(-256.1, -715.7, 33.52, 0.0),    -- Downtown, Alta St
            vector4(425.9, -654.3, 28.5, 0.0),      -- Textile City
            vector4(-522.4, -260.8, 35.5, 0.0),     -- Rockford Hills
            vector4(210.9, -1355.0, 30.6, 0.0),     -- Strawberry, Davis Ave
            vector4(-1035.9, -492.5, 36.6, 0.0),    -- Morningwood Blvd
            vector4(806.3, -1291.5, 26.3, 0.0),     -- La Mesa
            vector4(-68.5, -1096.9, 26.4, 0.0),     -- Legion Square Sued
            vector4(1210.6, -430.5, 66.9, 0.0),     -- Mirror Park Blvd
            vector4(-1305.7, -834.9, 16.9, 0.0),    -- Vespucci Blvd
            vector4(-614.6, -1035.2, 21.9, 0.0),    -- Little Seoul, Ginger St
            vector4(168.5, -1653.5, 29.3, 0.0),     -- Davis, Macdonald St
            vector4(-876.4, -158.6, 37.8, 0.0),     -- Morningwood Nord
            vector4(1112.7, -775.3, 57.3, 0.0),     -- East Vinewood
            vector4(482.24, -4.18, 85.25, 49.64),   -- Vinewood, Laguna Pl
        },
    },
    shoplifting = {
        label = 'Ladendiebstahl',
        code = 'Code 2',
        xp = 70,
        locations = {
            vector4(24.4, -1346.9, 29.5, 270.0),    -- 24/7 Strawberry
            vector4(-47.5, -1757.5, 29.42, 50.0),   -- LTD Grove Street
            vector4(372.6, 326.8, 53.2, 255.0),     -- 24/7 Downtown Vinewood
            vector4(-706.2, -913.7, 19.2, 90.0),    -- 24/7 Little Seoul
            vector4(1163.4, -323.8, 69.2, 100.0),   -- LTD Mirror Park
            vector4(-1222.3, -906.9, 12.3, 35.0),   -- Rob's Liquor Vespucci Canals
            vector4(-1487.6, -379.1, 40.2, 135.0),  -- Rob's Liquor Morningwood
            vector4(1135.8, -982.3, 46.4, 280.0),   -- Rob's Liquor Murrieta Heights
            vector4(425.9, -806.2, 29.5, 90.0),     -- Binco Strawberry
            vector4(-1193.4, -772.3, 17.3, 215.0),  -- Suburban Morningwood
            vector4(-715.9, -157.4, 37.0, 120.0),   -- Ponsonbys Rockford Hills
            vector4(75.5, -1392.9, 29.4, 270.0),    -- Discount Store Strawberry
        },
    },
    brawl = {
        label = 'Schlägerei',
        code = 'Code 2',
        xp = 80,
        locations = {
            vector4(197.8, -934.0, 30.7, 0.0),      -- Legion Square
            vector4(-1183.4, -1304.1, 5.0, 0.0),    -- Vespucci Beach
            vector4(129.6, -1299.4, 29.2, 0.0),     -- Vanilla Unicorn Parkplatz
            vector4(-1387.8, -586.7, 30.2, 0.0),    -- Del Perro, Bahama Mamas
            vector4(156.8, -1727.4, 29.3, 0.0),     -- Davis, Grove St Ecke
            vector4(-538.1, -216.1, 37.6, 0.0),     -- Rockford Plaza
            vector4(1130.5, -644.2, 56.8, 0.0),     -- Mirror Park See
            vector4(240.3, -862.5, 29.7, 0.0),      -- Legion Square Parkhaus
            vector4(-1655.5, -1063.7, 13.0, 0.0),   -- Del Perro Pier
            vector4(288.5, -1256.8, 29.4, 0.0),     -- Strawberry, Klinikumfeld
            vector4(-772.2, -1277.3, 5.1, 0.0),     -- Puerto Del Sol Marina
            vector4(-351.0, -1017.8, 30.6, 0.0),    -- Little Seoul Nord
        },
    },
    vehicle_theft = {
        label = 'Fahrzeugdiebstahl',
        code = 'Code 3',
        xp = 100,
        locations = {
            vector4(215.8, -810.1, 30.73, 340.0),   -- Legion Square Parkplatz
            vector4(-339.4, -1004.5, 30.6, 270.0),  -- Little Seoul
            vector4(1136.0, -982.0, 46.4, 279.0),   -- Murrieta Heights
            vector4(-796.1, -1291.5, 5.0, 180.0),   -- Vespucci
            vector4(486.7, -1315.6, 29.2, 200.0),   -- Strawberry, Verwahrhof
            vector4(-930.9, -455.3, 39.6, 115.0),   -- Morningwood
            vector4(1024.2, -2313.5, 30.9, 85.0),   -- El Burro Heights Industrie
            vector4(-68.1, -614.4, 35.9, 160.0),    -- Downtown Parkdeck
            vector4(-1414.6, -644.7, 28.0, 305.0),  -- Del Perro
            vector4(895.6, -1054.4, 32.9, 90.0),    -- La Mesa
            vector4(-462.0, -1716.0, 18.7, 30.0),   -- Elysian Island Zufahrt
            vector4(120.4, -1570.9, 29.3, 45.0),    -- Davis
        },
    },
    armed_robbery = {
        label = 'Bewaffneter Überfall',
        code = 'Code 3',
        xp = 120,
        locations = {
            vector4(28.2, -1339.7, 29.5, 270.0),    -- 24/7 Strawberry
            vector4(1163.4, -323.8, 69.2, 100.0),   -- LTD Mirror Park
            vector4(-1222.3, -906.9, 12.3, 35.0),   -- Rob's Liquor Vespucci Canals
            vector4(-47.5, -1757.5, 29.4, 50.0),    -- LTD Grove Street
            vector4(-707.5, -914.2, 19.2, 90.0),    -- 24/7 Little Seoul
            vector4(372.6, 326.8, 53.2, 255.0),     -- 24/7 Downtown Vinewood
            vector4(-1487.6, -379.1, 40.2, 135.0),  -- Rob's Liquor Morningwood
            vector4(1135.8, -982.3, 46.4, 280.0),   -- Rob's Liquor Murrieta Heights
            vector4(149.9, -1042.3, 29.4, 340.0),   -- Fleeca Bank Legion Square
            vector4(313.8, -280.6, 54.2, 340.0),    -- Fleeca Bank Hawick Ave
            vector4(-630.1, -236.7, 38.1, 35.0),    -- Vangelico Juwelier
            vector4(-1820.5, 794.5, 138.1, 130.0),  -- LTD Great Ocean Hwy
        },
    },
}
