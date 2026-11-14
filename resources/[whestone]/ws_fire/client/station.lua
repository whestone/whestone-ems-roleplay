lib.locale()

local function isFire()
    return LocalPlayer.state['ws:job'] == 'fire'
end
local function isOnDuty()
    return isFire() and LocalPlayer.state['ws:duty'] == true
end
local function myRank()
    return LocalPlayer.state['ws:rank'] or 0
end

-- ---------------------------------------------------------------------------
-- Dienst / Umkleide
-- ---------------------------------------------------------------------------

local function applyPed(pedModel, preset)
    local model = joaat(pedModel)
    lib.requestModel(model, 10000)
    SetPlayerModel(cache.playerId, model)
    SetModelAsNoLongerNeeded(model)
    Wait(150)
    local ped = PlayerPedId()
    SetPedDefaultComponentVariation(ped) -- korrektes Standard-Outfit als Basis
    if preset then
        for slot, drawable in pairs(preset.components or {}) do
            SetPedComponentVariation(ped, slot, drawable, 0, 0)
        end
        if preset.props then
            ClearAllPedProps(ped)
            for slot, drawable in pairs(preset.props) do
                SetPedPropIndex(ped, slot, drawable, 0, true)
            end
        end
    end
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    return ped
end

local function presetById(id)
    for _, u in ipairs(WSFire.Uniforms) do
        if u.id == id then return u end
    end
end

local function startDuty(preset)
    if not lib.callback.await('ws_fire:setDuty', false, true) then return end
    applyPed(preset.ped, preset)
end

local function endDuty()
    if not lib.callback.await('ws_fire:setDuty', false, false) then return end
    local ped = applyPed(WSFire.CivilianModel, nil)
    RemoveAllPedWeapons(ped, true)
    SetPedArmour(ped, 0)
end

local function openCloakroom()
    if isOnDuty() then
        lib.registerContext({ id = 'ws_fire_cloak', title = locale('cloakroom_title'), options = {
            { title = locale('duty_end'), icon = 'right-from-bracket', onSelect = endDuty },
        } })
        lib.showContext('ws_fire_cloak')
        return
    end
    local rank = myRank()
    local skins = {}
    for _, u in ipairs(WSFire.Uniforms) do
        skins[#skins + 1] = {
            model = u.id, image = u.image or u.ped,
            label = u.label, minRank = u.minRank or 0, locked = rank < (u.minRank or 0),
        }
    end
    local choice = exports.ws_core:OpenVehicleSelect({
        title = locale('cloakroom_title'), accent = 'fire', fallback = '🧑‍🚒',
        imageBase = 'peds', vehicles = skins,
    })
    if choice then
        local preset = presetById(choice)
        if preset then startDuty(preset) end
    end
end

-- ---------------------------------------------------------------------------
-- Ausruestung (Feuerloescher + Weste)
-- ---------------------------------------------------------------------------

local function takeSupply()
    local ped = PlayerPedId()
    if WSFire.Supply.extinguisher then
        -- Viel Munition + unendliches Magazin, sonst ist der Loescher nach einem
        -- "Schuss" leer und verschwindet sofort aus der Hand.
        GiveWeaponToPed(ped, joaat('WEAPON_FIREEXTINGUISHER'), 50000, false, true)
        SetPedInfiniteAmmoClip(ped, true)
    end
    if WSFire.Supply.heal then SetEntityHealth(ped, GetEntityMaxHealth(ped)) end
    if WSFire.Supply.armour then SetPedArmour(ped, WSFire.Supply.armour) end
    lib.notify({ title = locale('supply_title'), description = locale('supply_received'), type = 'success' })
end

-- ---------------------------------------------------------------------------
-- Fahrzeugausgabe
-- ---------------------------------------------------------------------------

local function spawnVehicle(model)
    local netId = lib.callback.await('ws_fire:spawnVehicle', false, model)
    if not netId then
        lib.notify({ title = locale('garage_title'), description = locale('garage_denied'), type = 'error' })
        return
    end
    local timeout = GetGameTimer() + 5000
    while not NetworkDoesEntityExistWithNetworkId(netId) and GetGameTimer() < timeout do Wait(50) end
    if not NetworkDoesEntityExistWithNetworkId(netId) then return end

    local veh = NetToVeh(netId)
    NetworkRequestControlOfEntity(veh)
    local tries = 0
    while not NetworkHasControlOfEntity(veh) and tries < 40 do Wait(25) tries = tries + 1 end

    SetVehicleOnGroundProperly(veh) -- sauber auf den Hallenboden setzen (nicht schwebend/im Dach)
    SetVehicleNumberPlateText(veh, ('LSFD%03d'):format(math.random(0, 999)))
    SetVehicleDirtLevel(veh, 0.0)
    SetVehRadioStation(veh, 'OFF')

    -- Fahrzeug-Skill tunt auch das LF (Motor/Bremsen, ab Stufe 2 Getriebe)
    local tuning = LocalPlayer.state['ws:skill_vehicles'] or 0
    if tuning > 0 then
        SetVehicleModKit(veh, 0)
        local function applyMod(t, i)
            local maxIndex = GetNumVehicleMods(veh, t) - 1
            if maxIndex >= 0 then SetVehicleMod(veh, t, math.min(i, maxIndex), false) end
        end
        applyMod(11, tuning)
        applyMod(12, math.min(tuning, 2))
        if tuning >= 2 then applyMod(13, tuning - 1) end
        if tuning >= 3 then SetVehicleTyresCanBurst(veh, false) end
    end

    if NetworkHasControlOfEntity(veh) then
        SetPedIntoVehicle(PlayerPedId(), veh, -1)
    else
        TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
    end
    lib.notify({ title = locale('garage_title'), description = locale('garage_received'), type = 'success' })
end

local function returnVehicle()
    if lib.callback.await('ws_fire:returnVehicle', false) then
        lib.notify({ title = locale('garage_title'), description = locale('garage_returned'), type = 'success' })
    else
        lib.notify({ title = locale('garage_title'), description = locale('garage_return_failed'), type = 'error' })
    end
end

local function openGarage()
    local rank = myRank()
    local vehicles = {}
    for _, v in ipairs(WSFire.Vehicles) do
        vehicles[#vehicles + 1] = {
            model = v.model, label = v.label, minRank = v.minRank or 0,
            locked = rank < (v.minRank or 0),
            unavailable = not IsModelInCdimage(joaat(v.model)),
        }
    end
    local choice = exports.ws_core:OpenVehicleSelect({
        title = locale('garage_title'), accent = 'fire', fallback = '🚒',
        returnLabel = locale('garage_return'), vehicles = vehicles,
    })
    if choice == '__return' then returnVehicle()
    elseif choice then spawnVehicle(choice) end
end

-- ---------------------------------------------------------------------------
-- Blip & Zonen
-- ---------------------------------------------------------------------------

CreateThread(function()
    local b = WSFire.Station.blip
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
    coords = WSFire.Station.cloakroom, radius = 1.5,
    options = {
        { name = 'ws_fire_cloak', label = locale('target_cloakroom'), icon = 'fa-solid fa-shirt',
          canInteract = isFire, onSelect = openCloakroom },
    },
})

exports.ox_target:addSphereZone({
    coords = WSFire.Station.supply, radius = 1.5,
    options = {
        { name = 'ws_fire_supply', label = locale('target_supply'), icon = 'fa-solid fa-fire-extinguisher',
          canInteract = isOnDuty, onSelect = takeSupply },
    },
})

exports.ox_target:addSphereZone({
    coords = WSFire.Station.garage, radius = 2.5,
    options = {
        { name = 'ws_fire_garage', label = locale('target_garage'), icon = 'fa-solid fa-truck-fast',
          canInteract = isOnDuty, onSelect = openGarage },
    },
})

-- ---------------------------------------------------------------------------
-- /brandcheck (nur Admins): teleportiert der Reihe nach durch ALLE Feuerwehr-
-- Punkte (Station + saemtliche Brandorte) zur Erreichbarkeits-Pruefung.
-- Erneut ausfuehren = naechster Punkt; '/brandcheck stop' beendet.
-- ---------------------------------------------------------------------------

local checkList, checkIdx

local function buildCheckList()
    local list = {}
    local st = WSFire.Station
    list[#list + 1] = { label = 'Station: Umkleide', pos = st.cloakroom }
    list[#list + 1] = { label = 'Station: Ausrüstung', pos = st.supply }
    list[#list + 1] = { label = 'Station: Fahrzeugausgabe', pos = st.garage }
    list[#list + 1] = { label = 'Station: Fahrzeug-Spawn', pos = st.garageSpawn }

    local types = {}
    for id in pairs(WSFire.Fires) do types[#types + 1] = id end
    table.sort(types)
    for _, id in ipairs(types) do
        local d = WSFire.Fires[id]
        for i, loc in ipairs(d.locations) do
            list[#list + 1] = { label = ('%s %d/%d'):format(id, i, #d.locations), pos = loc }
        end
    end
    return list
end

RegisterCommand('brandcheck', function(_, args)
    if args[1] == 'stop' then
        checkList, checkIdx = nil, nil
        lib.notify({ title = 'Brand-Check', description = 'Prüfung beendet.', type = 'inform' })
        return
    end
    if not lib.callback.await('ws_fire:isAdmin', false) then return end

    checkList = checkList or buildCheckList()
    checkIdx = (checkIdx or 0) + 1
    if checkIdx > #checkList then
        lib.notify({ title = 'Brand-Check', description = 'Alle Punkte geprüft!', type = 'success' })
        checkList, checkIdx = nil, nil
        return
    end

    local e = checkList[checkIdx]
    SetEntityCoords(cache.ped, e.pos.x, e.pos.y, e.pos.z, false, false, false, false)
    lib.notify({
        title = 'Brand-Check',
        description = ('%s (%d/%d)\n%.2f, %.2f, %.2f\nWeiter: /brandcheck'):format(
            e.label, checkIdx, #checkList, e.pos.x, e.pos.y, e.pos.z),
        type = 'inform',
        duration = 15000,
    })
end, false)
