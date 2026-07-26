lib.locale()

local function isEms()
    return LocalPlayer.state['ws:job'] == 'ambulance'
end
local function isOnDuty()
    return isEms() and LocalPlayer.state['ws:duty'] == true
end
local function myRank()
    return LocalPlayer.state['ws:rank'] or 0
end

-- ---------------------------------------------------------------------------
-- Dienst / Umkleide
-- ---------------------------------------------------------------------------

local function applyModel(modelName, randomOutfit)
    local model = joaat(modelName)
    lib.requestModel(model, 10000)
    SetPlayerModel(cache.playerId, model)
    SetModelAsNoLongerNeeded(model)
    Wait(150)

    local ped = PlayerPedId()
    if randomOutfit then
        SetPedRandomComponentVariation(ped, 0)
    else
        SetPedDefaultComponentVariation(ped)
    end
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    return ped
end

local function startDuty(model)
    if not lib.callback.await('ws_ems:setDuty', false, true) then return end
    applyModel(model, true)
end

local function endDuty()
    if not lib.callback.await('ws_ems:setDuty', false, false) then return end
    applyModel(WSEms.CivilianModel, false)
end

local function openCloakroom()
    if isOnDuty() then
        lib.registerContext({ id = 'ws_ems_cloakroom', title = locale('cloakroom_title'), options = {
            { title = locale('duty_end'), icon = 'right-from-bracket', onSelect = endDuty },
        } })
        lib.showContext('ws_ems_cloakroom')
        return
    end

    -- Grafische Auswahl (NUI in ws_core): Ped-Bild, Modellcode, Freischaltrang
    local rank = myRank()
    local skins = {}
    for _, uniform in ipairs(WSEms.Uniforms) do
        skins[#skins + 1] = {
            model = uniform.model,
            label = uniform.label,
            minRank = uniform.minRank or 0,
            locked = rank < (uniform.minRank or 0),
        }
    end
    local choice = exports.ws_core:OpenVehicleSelect({
        title = locale('cloakroom_title'),
        accent = 'ems',
        fallback = '🧑‍⚕️',
        imageBase = 'peds',
        vehicles = skins,
    })
    if choice then startDuty(choice) end
end

-- ---------------------------------------------------------------------------
-- Notfallrucksack (Ausruestung)
-- ---------------------------------------------------------------------------

local function takeSupply()
    local ped = PlayerPedId()
    if WSEms.SupplyHealsSelf then
        SetEntityHealth(ped, GetEntityMaxHealth(ped))
        SetPedArmour(ped, 50)
    end
    lib.notify({ title = locale('supply_title'), description = locale('supply_received'), type = 'success' })
end

-- ---------------------------------------------------------------------------
-- Garage
-- ---------------------------------------------------------------------------

local function spawnVehicle(model)
    local netId = lib.callback.await('ws_ems:spawnVehicle', false, model)
    if not netId then
        lib.notify({ title = locale('garage_title'), description = locale('garage_denied'), type = 'error' })
        return
    end

    local timeout = GetGameTimer() + 5000
    while not NetworkDoesEntityExistWithNetworkId(netId) and GetGameTimer() < timeout do
        Wait(50)
    end
    if not NetworkDoesEntityExistWithNetworkId(netId) then return end

    local veh = NetToVeh(netId)
    NetworkRequestControlOfEntity(veh)
    local tries = 0
    while not NetworkHasControlOfEntity(veh) and tries < 40 do Wait(25) tries = tries + 1 end

    SetVehicleNumberPlateText(veh, ('EMS%04d'):format(math.random(0, 9999)))
    SetVehicleDirtLevel(veh, 0.0)
    SetVehRadioStation(veh, 'OFF')

    -- Fahrzeug-Skill tunt auch den RTW (Motor/Bremsen, ab Stufe 2 Getriebe+Turbo)
    local tuning = LocalPlayer.state['ws:skill_vehicles'] or 0
    if tuning > 0 then
        SetVehicleModKit(veh, 0)
        local function applyMod(modType, index)
            local maxIndex = GetNumVehicleMods(veh, modType) - 1
            if maxIndex >= 0 then
                SetVehicleMod(veh, modType, math.min(index, maxIndex), false)
            end
        end
        applyMod(11, tuning)
        applyMod(12, math.min(tuning, 2))
        if tuning >= 2 then
            applyMod(13, tuning - 1)
            ToggleVehicleMod(veh, 18, true)
        end
        -- Oberste Stufe: schusssichere Reifen (platzen nicht mehr durch Beschuss)
        if tuning >= 3 then SetVehicleTyresCanBurst(veh, false) end
    end
    -- Spieler direkt auf den Fahrersitz setzen (SetPedIntoVehicle ist
    -- zuverlaessiger als der Warp-Task, gerade bei groesserer Distanz)
    if NetworkHasControlOfEntity(veh) then
        SetPedIntoVehicle(PlayerPedId(), veh, -1)
    else
        TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
    end
    lib.notify({ title = locale('garage_title'), description = locale('garage_received'), type = 'success' })
end

local function returnVehicle()
    if lib.callback.await('ws_ems:returnVehicle', false) then
        lib.notify({ title = locale('garage_title'), description = locale('garage_returned'), type = 'success' })
    else
        lib.notify({ title = locale('garage_title'), description = locale('garage_return_failed'), type = 'error' })
    end
end

-- Grafische Auswahl (NUI in ws_core): Bild, Modellcode, Freischaltrang
local function buildVehicleCards(list)
    local rank = myRank()
    local vehicles = {}
    for _, v in ipairs(list) do
        vehicles[#vehicles + 1] = {
            model = v.model,
            label = v.label,
            minRank = v.minRank or 0,
            locked = rank < (v.minRank or 0),
            unavailable = not IsModelInCdimage(joaat(v.model)),
        }
    end
    return vehicles
end

local function openGarage()
    local choice = exports.ws_core:OpenVehicleSelect({
        title = locale('garage_title'),
        accent = 'ems',
        fallback = '🚑',
        returnLabel = locale('garage_return'),
        vehicles = buildVehicleCards(WSEms.Vehicles),
    })
    if choice == '__return' then
        returnVehicle()
    elseif choice then
        spawnVehicle(choice)
    end
end

-- ---------------------------------------------------------------------------
-- Helipad (Pillbox-Dach): Heli ausparken, Aufzug zur Notaufnahme
-- ---------------------------------------------------------------------------

local function spawnHeli(entry)
    local netId = lib.callback.await('ws_ems:spawnHeli', false, entry.model)
    if not netId then
        lib.notify({ title = locale('heli_title'), description = locale('garage_denied'), type = 'error' })
        return
    end

    local timeout = GetGameTimer() + 5000
    while not NetworkDoesEntityExistWithNetworkId(netId) and GetGameTimer() < timeout do
        Wait(50)
    end
    if not NetworkDoesEntityExistWithNetworkId(netId) then return end

    local veh = NetToVeh(netId)
    NetworkRequestControlOfEntity(veh)
    local tries = 0
    while not NetworkHasControlOfEntity(veh) and tries < 40 do Wait(25) tries = tries + 1 end

    SetVehicleNumberPlateText(veh, ('EMS%04d'):format(math.random(0, 9999)))
    SetVehicleDirtLevel(veh, 0.0)
    SetVehRadioStation(veh, 'OFF')
    if entry.livery then SetVehicleLivery(veh, entry.livery) end

    if NetworkHasControlOfEntity(veh) then
        SetPedIntoVehicle(PlayerPedId(), veh, -1)
    else
        TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
    end
    lib.notify({ title = locale('heli_title'), description = locale('heli_received'), type = 'success' })
end

local function openHeliMenu()
    local choice = exports.ws_core:OpenVehicleSelect({
        title = locale('heli_title'),
        accent = 'ems',
        fallback = '🚁',
        returnLabel = locale('garage_return'),
        vehicles = buildVehicleCards(WSEms.Helicopters),
    })
    if choice == '__return' then
        returnVehicle()
    elseif choice then
        for _, v in ipairs(WSEms.Helicopters) do
            if v.model == choice then spawnHeli(v) break end
        end
    end
end

-- Aufzug: teleportiert mit Blende; ein gestuetzter Patient (attached) faehrt mit
local function useElevator(dest)
    DoScreenFadeOut(400)
    local t = GetGameTimer() + 1500
    while not IsScreenFadedOut() and GetGameTimer() < t do Wait(25) end

    SetEntityCoords(cache.ped, dest.x, dest.y, dest.z, false, false, false, false)
    SetEntityHeading(cache.ped, dest.w)

    -- Kollision am Ziel abwarten, sonst faellt man durch den Boden
    RequestCollisionAtCoord(dest.x, dest.y, dest.z)
    t = GetGameTimer() + 2000
    while not HasCollisionLoadedAroundEntity(cache.ped) and GetGameTimer() < t do Wait(25) end
    Wait(150)
    DoScreenFadeIn(400)
end

-- ---------------------------------------------------------------------------
-- Blip & Interaktionszonen
-- ---------------------------------------------------------------------------

CreateThread(function()
    local b = WSEms.Station.blip
    local blip = AddBlipForCoord(b.coords.x, b.coords.y, b.coords.z)
    SetBlipSprite(blip, b.sprite)
    SetBlipColour(blip, b.color)
    SetBlipScale(blip, b.scale)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(b.label)
    EndTextCommandSetBlipName(blip)
end)

exports.ox_target:addSphereZone({
    coords = WSEms.Station.cloakroom, radius = 1.5,
    options = {
        { name = 'ws_ems_cloakroom', label = locale('target_cloakroom'), icon = 'fa-solid fa-shirt',
          canInteract = isEms, onSelect = openCloakroom },
    },
})

exports.ox_target:addSphereZone({
    coords = WSEms.Station.supply, radius = 1.5,
    options = {
        { name = 'ws_ems_supply', label = locale('target_supply'), icon = 'fa-solid fa-briefcase-medical',
          canInteract = isOnDuty, onSelect = takeSupply },
    },
})

exports.ox_target:addSphereZone({
    coords = WSEms.Station.garage, radius = 2.5,
    options = {
        { name = 'ws_ems_garage', label = locale('target_garage'), icon = 'fa-solid fa-truck-medical',
          canInteract = isOnDuty, onSelect = openGarage },
    },
})

exports.ox_target:addSphereZone({
    coords = WSEms.Helipad.menu, radius = 1.8,
    options = {
        { name = 'ws_ems_helipad', label = locale('target_heli'), icon = 'fa-solid fa-helicopter',
          canInteract = isOnDuty, onSelect = openHeliMenu },
    },
})

local elev = WSEms.Helipad.elevator
exports.ox_target:addSphereZone({
    coords = vector3(elev.up.x, elev.up.y, elev.up.z), radius = 1.5,
    options = {
        { name = 'ws_ems_elev_down', label = locale('target_elevator_down'), icon = 'fa-solid fa-elevator',
          canInteract = isEms, onSelect = function() useElevator(elev.down) end },
    },
})

exports.ox_target:addSphereZone({
    coords = vector3(elev.down.x, elev.down.y, elev.down.z), radius = 1.5,
    options = {
        { name = 'ws_ems_elev_up', label = locale('target_elevator_up'), icon = 'fa-solid fa-elevator',
          canInteract = isEms, onSelect = function() useElevator(elev.up) end },
    },
})

-- ---------------------------------------------------------------------------
-- /emscheck (nur Admins): teleportiert der Reihe nach durch ALLE EMS-Punkte
-- (Station + saemtliche Notfallorte) zur Erreichbarkeits-Pruefung.
-- Erneut ausfuehren = naechster Punkt; '/emscheck stop' beendet.
-- ---------------------------------------------------------------------------

local checkList, checkIdx

local function buildCheckList()
    local list = {}
    local st = WSEms.Station
    list[#list + 1] = { label = 'Station: Umkleide', pos = st.cloakroom }
    list[#list + 1] = { label = 'Station: Notfallrucksack', pos = st.supply }
    list[#list + 1] = { label = 'Station: Fahrzeugausgabe', pos = st.garage }
    list[#list + 1] = { label = 'Station: Fahrzeug-Spawn', pos = st.garageSpawn }
    list[#list + 1] = { label = 'Station: Notaufnahme', pos = st.dropoff }

    local hp = WSEms.Helipad
    list[#list + 1] = { label = 'Helipad: Ausparkmenü', pos = hp.menu }
    list[#list + 1] = { label = 'Helipad: Heli-Spawn', pos = hp.spawn }
    list[#list + 1] = { label = 'Helipad: Patientenabgabe', pos = hp.dropoff }
    list[#list + 1] = { label = 'Helipad: Aufzug oben', pos = hp.elevator.up }
    list[#list + 1] = { label = 'Helipad: Aufzug unten', pos = hp.elevator.down }

    local types = {}
    for id in pairs(WSEms.Emergencies) do types[#types + 1] = id end
    table.sort(types)
    for _, id in ipairs(types) do
        local d = WSEms.Emergencies[id]
        for i, loc in ipairs(d.locations) do
            list[#list + 1] = { label = ('%s %d/%d'):format(id, i, #d.locations), pos = loc }
        end
    end
    return list
end

RegisterCommand('emscheck', function(_, args)
    if args[1] == 'stop' then
        checkList, checkIdx = nil, nil
        lib.notify({ title = 'EMS-Check', description = 'Prüfung beendet.', type = 'inform' })
        return
    end
    if not lib.callback.await('ws_ems:isAdmin', false) then return end

    checkList = checkList or buildCheckList()
    checkIdx = (checkIdx or 0) + 1
    if checkIdx > #checkList then
        lib.notify({ title = 'EMS-Check', description = 'Alle Punkte geprüft!', type = 'success' })
        checkList, checkIdx = nil, nil
        return
    end

    local e = checkList[checkIdx]
    SetEntityCoords(cache.ped, e.pos.x, e.pos.y, e.pos.z, false, false, false, false)
    lib.notify({
        title = 'EMS-Check',
        description = ('%s (%d/%d)\n%.2f, %.2f, %.2f\nWeiter: /emscheck'):format(
            e.label, checkIdx, #checkList, e.pos.x, e.pos.y, e.pos.z),
        type = 'inform',
        duration = 15000,
    })
end, false)
