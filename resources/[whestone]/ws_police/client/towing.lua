-- Abschleppdienst: Ein echter Abschleppwagen faehrt an, laedt das Fahrzeug
-- auf und transportiert es ab. Funktioniert fuer beliebige Fahrzeuge
-- (auch Unfallwracks aus Callouts - deren Einsatzziel wird dabei erfuellt).

local TOW_TRUCK_MODEL = 'towtruck'
local TOW_DRIVER_MODEL = 's_m_m_trucker_01'

local activeTows = {} -- Ziel-Fahrzeug -> true (mehrere Auftraege parallel moeglich)
local MAX_CONCURRENT_TOWS = 3
local spawnedEntities = {} -- selbst erzeugte Trucks/Fahrer (fuer Cleanup bei Resource-Stopp)

-- Fahrzeugklassen, die nicht abgeschleppt werden (Zweiraeder, Boote,
-- Luftfahrzeuge, Einsatzfahrzeuge, Zuege)
local blockedClasses = { [8] = true, [13] = true, [14] = true, [15] = true, [16] = true, [18] = true, [21] = true }

local function ensureControl(entity)
    if not DoesEntityExist(entity) then return false end
    if NetworkHasControlOfEntity(entity) then return true end
    NetworkRequestControlOfEntity(entity)
    local tries = 0
    while not NetworkHasControlOfEntity(entity) and tries < 50 do
        Wait(20)
        tries = tries + 1
    end
    return NetworkHasControlOfEntity(entity)
end

local function notifyTow(key, ntype)
    lib.notify({ title = locale('tow_title'), description = locale(key), type = ntype or 'inform' })
end

local function canTowVehicle(veh)
    if LocalPlayer.state['ws:job'] ~= 'police' or LocalPlayer.state['ws:duty'] ~= true then return false end
    if activeTows[veh] then return false end
    if blockedClasses[GetVehicleClass(veh)] then return false end
    if GetEntityModel(veh) == joaat(TOW_TRUCK_MODEL) then return false end
    if IsEntityAttached(veh) then return false end -- haengt bereits am Haken
    if #(GetEntityVelocity(veh)) > 2.0 then return false end

    -- keine lebenden Insassen (Spieler oder NPCs)
    for seat = -1, GetVehicleModelNumberOfSeats(GetEntityModel(veh)) - 2 do
        local ped = GetPedInVehicleSeat(veh, seat)
        if ped ~= 0 and DoesEntityExist(ped) and not IsEntityDead(ped) then
            return false
        end
    end
    return true
end

local function findSpawnPoint(coords)
    for _, dist in ipairs({ 140.0, 100.0, 180.0 }) do
        local angle = math.rad(math.random(0, 359))
        local found, pos, heading = GetClosestVehicleNodeWithHeading(
            coords.x + math.cos(angle) * dist,
            coords.y + math.sin(angle) * dist,
            coords.z, 1, 3.0, 0)
        if found then
            return pos, heading
        end
    end
end

local function cleanupTow(truck, driver, target)
    for _, ent in ipairs({ target, driver, truck }) do
        if ent and DoesEntityExist(ent) and ensureControl(ent) then
            SetEntityAsMissionEntity(ent, true, true)
            DeleteEntity(ent)
        end
        if ent then spawnedEntities[ent] = nil end
    end
end

local function towVehicle(target)
    local ok = lib.progressBar({
        duration = 3000,
        label = locale('tow_requesting'),
        canCancel = true,
        disable = { move = true, combat = true },
        -- Funkgeraet-Animation (Oberkoerper)
        anim = { dict = 'random@arrests', clip = 'generic_radio_chatter', flag = 49 },
    })
    if not ok or not DoesEntityExist(target) then
        return
    end

    local targetPos = GetEntityCoords(target)
    local targetNetId = NetworkGetNetworkIdFromEntity(target)
    local isWreck = Entity(target).state['ws:wreck'] == true

    local spawnPos, spawnHeading = findSpawnPoint(targetPos)
    if not spawnPos then
        notifyTow('tow_failed', 'error')
        return
    end

    local truckHash, driverHash = joaat(TOW_TRUCK_MODEL), joaat(TOW_DRIVER_MODEL)
    lib.requestModel(truckHash, 10000)
    lib.requestModel(driverHash, 10000)

    local truck = CreateVehicle(truckHash, spawnPos.x, spawnPos.y, spawnPos.z, spawnHeading, true, true)
    local driver = CreatePed(4, driverHash, spawnPos.x, spawnPos.y, spawnPos.z, spawnHeading, true, true)
    SetModelAsNoLongerNeeded(truckHash)
    SetModelAsNoLongerNeeded(driverHash)
    SetEntityAsMissionEntity(truck, true, true)
    SetEntityAsMissionEntity(driver, true, true)
    spawnedEntities[truck] = true
    spawnedEntities[driver] = true
    SetPedIntoVehicle(driver, truck, -1)
    SetBlockingOfNonTemporaryEvents(driver, true)
    SetDriverAbility(driver, 1.0)
    SetDriverAggressiveness(driver, 0.0)
    SetVehicleSiren(truck, true) -- Gelblicht (Rundumleuchte) an

    notifyTow('tow_enroute', 'success')

    -- Ziel ist der naechste Strassenknoten am Fahrzeug - die exakte
    -- Wrack-Position liegt oft abseits der Route und ist nicht anfahrbar
    local nodeFound, roadPos = GetClosestVehicleNode(targetPos.x, targetPos.y, targetPos.z, 1, 3.0, 0)
    local drivePos = nodeFound and roadPos or targetPos
    TaskVehicleDriveToCoordLongrange(driver, truck, drivePos.x, drivePos.y, drivePos.z, 18.0, 786603, 10.0)

    -- Anfahrt abwarten; nur wenn der Fahrer sich wirklich verkeilt,
    -- als letzte Rettung an den Strassenknoten setzen
    local deadline = GetGameTimer() + 90000
    while GetGameTimer() < deadline do
        Wait(500)
        if not DoesEntityExist(truck) or not DoesEntityExist(target) then
            return cleanupTow(truck, driver, nil)
        end
        if #(GetEntityCoords(truck) - GetEntityCoords(target)) < 35.0 then break end
    end
    if #(GetEntityCoords(truck) - GetEntityCoords(target)) >= 35.0 then
        SetEntityCoords(truck, drivePos.x, drivePos.y, drivePos.z, false, false, false, false)
        SetPedIntoVehicle(driver, truck, -1)
    end

    ClearPedTasks(driver)
    TaskVehicleTempAction(driver, truck, 27, 3000)
    Wait(2000)

    -- Aufladen
    if not DoesEntityExist(target) or not ensureControl(target) then
        return cleanupTow(truck, driver, nil)
    end
    AttachVehicleToTowTruck(truck, target, false, 0.0, 0.0, 0.0)
    Wait(1000)
    notifyTow('tow_pickup', 'success')

    -- Unfallwrack aus einem Callout? Einsatzziel als erledigt melden.
    if isWreck then
        TriggerServerEvent('ws_dispatch:objectiveDone', targetNetId)
    end

    -- Abtransport: wegfahren und ausserhalb der Sichtweite alles entfernen
    TaskVehicleDriveToCoordLongrange(driver, truck, spawnPos.x, spawnPos.y, spawnPos.z, 15.0, 786603, 20.0)
    local away = GetGameTimer() + 30000
    while GetGameTimer() < away do
        Wait(1000)
        if not DoesEntityExist(truck) then break end
        if #(GetEntityCoords(truck) - targetPos) > 80.0 then break end
    end

    cleanupTow(truck, driver, target)
end

exports.ox_target:addGlobalVehicle({
    {
        name = 'ws_towrequest',
        label = locale('tow_request'),
        icon = 'fa-solid fa-truck-ramp-box',
        canInteract = canTowVehicle,
        onSelect = function(data)
            local target = data.entity
            if activeTows[target] then return end

            local count = 0
            for _ in pairs(activeTows) do count = count + 1 end
            if count >= MAX_CONCURRENT_TOWS then
                return notifyTow('tow_limit', 'error')
            end

            activeTows[target] = true
            CreateThread(function()
                -- pcall: bricht towVehicle mit einem Fehler ab (Modell nicht
                -- ladbar, Ziel verschwunden), MUSS der Slot trotzdem frei
                -- werden - sonst blockieren 3 Fehlschlaege den Abschleppdienst
                -- fuer den Rest der Session dauerhaft
                local ok, err = pcall(towVehicle, target)
                activeTows[target] = nil
                if not ok then
                    print(('[ws_police] Abschleppauftrag fehlgeschlagen: %s'):format(err))
                    notifyTow('tow_error', 'error')
                end
            end)
        end,
    },
})

-- Bei Resource-Stopp (z.B. Neustart mitten im Abschleppvorgang) selbst
-- erzeugte Trucks/Fahrer entfernen, damit keine Waisen zurueckbleiben
AddEventHandler('onResourceStop', function(res)
    if res ~= cache.resource then return end
    for ent in pairs(spawnedEntities) do
        if DoesEntityExist(ent) then DeleteEntity(ent) end
    end
end)
