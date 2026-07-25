-- Notfall-Stammdaten. patientState bestimmt die noetige Behandlung:
-- 'cardiac' (Reanimation), 'unconscious' (stabilisieren), 'trauma' (Wunde).
-- Neue Notfaelle: einfach hier ergaenzen.

WSEms.Emergencies = {
    cardiac = {
        label = 'Herz-Kreislauf-Stillstand',
        code = 'Notfall Rot',
        patientState = 'cardiac',
        xp = 60,
        peds = { 'a_m_o_genstreet_01', 'a_m_m_business_01', 'a_f_m_business_02', 'a_m_y_business_03' },
        locations = {
            vector4(-269.4, -955.3, 31.2, 0.0),   -- Downtown
            vector4(228.6, -865.5, 30.5, 0.0),    -- Legion Square
            vector4(-1037.8, -1396.0, 5.5, 0.0),  -- Vespucci Beach
            vector4(1136.0, -982.0, 46.2, 0.0),   -- Mirror Park
            vector4(-710.56, -154.95, 37.42, 86.08), -- Rockford Hills
            vector4(380.87, 326.25, 103.57, 342.22), -- Vinewood Hills
        },
    },
    overdose = {
        label = 'Drogennotfall / Überdosis',
        code = 'Notfall Rot',
        patientState = 'unconscious',
        xp = 55,
        peds = { 'a_m_y_downtown_01', 'a_m_y_soucent_02', 'a_f_y_scdressy_01', 'a_m_y_beach_02' },
        locations = {
            vector4(182.30, -1677.17, 29.77, 253.47), -- Davis
            vector4(-1291.5, -1158.0, 6.0, 0.0),      -- Del Perro Beach
            vector4(334.28, -1379.01, 32.51, 61.07),  -- Nahe Pillbox
            vector4(-45.0, -1449.0, 31.0, 0.0),       -- Strawberry
            vector4(-96.20, 400.08, 112.42, 277.73),  -- Vinewood Hills
        },
    },
    fall = {
        label = 'Sturz aus großer Höhe',
        code = 'Notfall Gelb',
        patientState = 'trauma',
        xp = 55,
        peds = { 'a_m_y_hipster_01', 'a_m_m_farmer_01', 'a_m_y_ktown_01', 'a_f_y_hipster_02' },
        locations = {
            vector4(-150.0, -620.0, 33.0, 0.0),   -- Baustelle Downtown
            vector4(711.0, -1290.0, 25.0, 0.0),   -- La Mesa
            vector4(-662.79, -894.60, 24.59, 122.00), -- Little Seoul
            vector4(115.08, -1289.99, 28.26, 108.05), -- Strawberry
            vector4(1271.91, -1722.90, 54.66, 109.00), -- El Burro
        },
    },
    traffic = {
        label = 'Verkehrsunfall mit Verletzten',
        code = 'Notfall Rot',
        patientState = 'trauma',
        xp = 70,
        peds = { 'a_m_y_business_01', 'a_f_y_business_02', 'a_m_m_eastsa_01', 'a_f_m_soucent_01' },
        wreck = true, -- Unfallwrack neben dem Patienten
        locations = {
            vector4(296.0, -585.0, 43.2, 0.0),    -- Pillbox Hill
            vector4(-256.0, -715.0, 33.5, 0.0),   -- Alta St
            vector4(-522.0, -260.0, 35.5, 0.0),   -- Rockford Hills
            vector4(806.0, -1291.0, 26.3, 0.0),   -- La Mesa
            vector4(168.0, -1653.0, 29.3, 0.0),   -- Davis
        },
    },
    allergic = {
        label = 'Allergischer Schock',
        code = 'Notfall Rot',
        patientState = 'unconscious',
        xp = 55,
        peds = { 'a_f_y_business_01', 'a_m_y_juggalo_01', 'a_m_y_genstreet_01', 'a_f_y_tourist_01' },
        locations = {
            vector4(-631.0, -1223.0, 11.8, 0.0),  -- Restaurant Little Seoul
            vector4(119.46, -1051.25, 29.19, 50.88), -- Downtown Imbiss
            vector4(-1197.0, -770.0, 17.3, 0.0),  -- Morningwood
            vector4(1232.33, -354.24, 69.08, 248.20), -- Mirror Park Cafe
        },
    },
    workplace = {
        label = 'Arbeitsunfall',
        code = 'Notfall Gelb',
        patientState = 'trauma',
        xp = 60,
        peds = { 's_m_y_construct_01', 's_m_y_construct_02', 's_m_m_dockwork_01', 's_m_y_garbage' },
        locations = {
            vector4(-141.0, -595.0, 32.4, 0.0),   -- Baustelle Downtown
            vector4(1057.30, -2408.27, 29.92, 281.87), -- Industriegebiet El Burro
            vector4(-424.83, -1719.94, 19.25, 227.07), -- Recyclinghof
            vector4(883.0, -2350.0, 30.3, 0.0),   -- Lagerhallen
        },
    },
    drowning = {
        label = 'Beinahe-Ertrinken',
        code = 'Notfall Rot',
        patientState = 'unconscious',
        xp = 65,
        peds = { 'a_m_y_beach_01', 'a_f_y_beach_01', 'a_m_y_surfer_01', 'a_f_y_fitness_01' },
        locations = {
            vector4(-1525.59, -1128.62, 0.90, 143.33), -- Del Perro Strand
            vector4(-1287.84, -1794.14, 0.93, 154.89), -- Vespucci Beach
            vector4(-1814.42, -975.25, 1.50, 341.34),  -- Great Ocean Hwy
            vector4(-1480.0, -1430.0, 2.7, 0.0),  -- Del Perro Beach (alter Punkt lag im Ozean)
        },
    },
}
