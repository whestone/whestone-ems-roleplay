lib.locale()

-- Abtransport per NPC-Rettungswagen (analog zum Gefangenentransporter der Cops):
-- Ein RTW faehrt an, laedt den stabilen Patienten + alle stabilen Patienten in
-- der Naehe ein und transportiert sie ab (weniger XP als die Eigenlieferung).

local CFG = WSEms.Transport
local activeTransport = false
local spawnedEntities = {} -- selbst erzeugte RTW/Fahrer (Cleanup bei Resource-Stopp)

local function isOnDuty()
    return LocalPlayer.state['ws:job'] == 'ambulance' and LocalPlayer.state['ws:duty'] == true
end

local function ensureControl(entity)
    if not DoesEntityExist(entity) then return false end
    if NetworkHasControlOfEntity(entity) then return true end
    NetworkRequestControlOfEntity(entity)
    local tries = 0
    while not NetworkHasControlOfEntity(entity) and tries < 40 do Wait(20) tries = tries + 1 end
    return NetworkHasControlOfEntity(entity)
end

local function notifyT(key, ntype)
    lib.notify({ title = locale('transport_title'), description = locale(key), type = ntype or 'inform' })
end

local function findSpawnPoint(coords)
    for _, dist in ipairs({ 140.0, 100.0, 180.0 }) do
        local angle = math.rad(math.random(0, 359))
        local found, pos, heading = GetClosestVehicleNodeWithHeading(
            coords.x + math.cos(angle) * dist, coords.y + math.sin(angle) * dist, coords.z, 1, 3.0, 0)
        if found then return pos, heading end
    end
end

-- Stabile NPC-Patienten im Umkreis, die noch nicht im Fahrzeug sitzen
local function nearbyStablePatients(coords, radius, max)
    local list = {}
    for _, ped in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(ped) and DoesEntityExist(ped) and not IsPedInAnyVehicle(ped, false) then
            local s = Entity(ped).state
            if s['ws:patient'] and s['ws:patient_state'] == 'stable'
                and #(GetEntityCoords(ped) - coords) <= radius then
                list[#list + 1] = ped
                if #list >= max then break end
            end
        end
    end
    return list
end

local function cleanup(rtw, driver)
    for _, ent in ipairs({ driver, rtw }) do
        if ent and DoesEntityExist(ent) and ensureControl(ent) then
            SetEntityAsMissionEntity(ent, true, true)
            DeleteEntity(ent)
        end
        if ent then spawnedEntities[ent] = nil end
    end
    activeTransport = false
end

local function requestTransport(patient)
    if activeTransport then return end
    activeTransport = true

    local ok = lib.progressBar({
        duration = 3000,
        label = locale('transport_requesting'),
        canCancel = true,
        disable = { move = true, combat = true, car = true },
        anim = { dict = 'random@arrests', clip = 'generic_radio_chatter', flag = 49 },
    })
    if not ok or not DoesEntityExist(patient) then
        activeTransport = false
        return
    end

    local scenePos = GetEntityCoords(patient)
    local spawnPos, spawnHeading = findSpawnPoint(scenePos)
    if not spawnPos then
        notifyT('transport_failed', 'error')
        activeTransport = false
        return
    end

    local vehHash, driverHash = joaat(CFG.vehicle), joaat(CFG.driver)
    lib.requestModel(vehHash, 10000)
    lib.requestModel(driverHash, 10000)

    local rtw = CreateVehicle(vehHash, spawnPos.x, spawnPos.y, spawnPos.z, spawnHeading, true, true)
    local driver = CreatePed(4, driverHash, spawnPos.x, spawnPos.y, spawnPos.z, spawnHeading, true, true)
    SetModelAsNoLongerNeeded(vehHash)
    SetModelAsNoLongerNeeded(driverHash)
    SetEntityAsMissionEntity(rtw, true, true)
    SetEntityAsMissionEntity(driver, true, true)
    spawnedEntities[rtw] = true
    spawnedEntities[driver] = true
    SetPedIntoVehicle(driver, rtw, -1)
    SetBlockingOfNonTemporaryEvents(driver, true)
    SetDriverAbility(driver, 1.0)
    SetDriverAggressiveness(driver, 0.0)
    SetVehicleSiren(rtw, true)

    notifyT('transport_enroute', 'success')

    local nodeFound, roadPos = GetClosestVehicleNode(scenePos.x, scenePos.y, scenePos.z, 1, 3.0, 0)
    local drivePos = nodeFound and roadPos or scenePos
    TaskVehicleDriveToCoordLongrange(driver, rtw, drivePos.x, drivePos.y, drivePos.z, 22.0, 786468, 10.0)

    local deadline = GetGameTimer() + 90000
    while GetGameTimer() < deadline do
        Wait(500)
        if not DoesEntityExist(rtw) then return cleanup(rtw, driver) end
        if #(GetEntityCoords(rtw) - scenePos) < 35.0 then break end
    end
    if not DoesEntityExist(rtw) then return cleanup(rtw, driver) end
    if #(GetEntityCoords(rtw) - scenePos) >= 35.0 then
        SetEntityCoords(rtw, drivePos.x, drivePos.y, drivePos.z, false, false, false, false)
        SetPedIntoVehicle(driver, rtw, -1)
    end

    ClearPedTasks(driver)
    TaskVehicleTempAction(driver, rtw, 27, 3000)
    Wait(1500)

    -- Ziel-Patient + alle stabilen Patienten in der Naehe einladen
    local maxSeats = GetVehicleModelNumberOfSeats(vehHash)
    local candidates = nearbyStablePatients(GetEntityCoords(rtw), CFG.pickupRadius, maxSeats)
    local seen = {}
    for _, p in ipairs(candidates) do seen[p] = true end
    if DoesEntityExist(patient) and not seen[patient] then
        table.insert(candidates, 1, patient)
    end

    local loaded = 0
    for _, ped in ipairs(candidates) do
        if loaded >= maxSeats - 1 then break end -- Sitz -1 = Fahrer
        if DoesEntityExist(ped) and ensureControl(ped) then
            local seat
            for _, s in ipairs({ 0, 1, 2, 3 }) do
                if IsVehicleSeatFree(rtw, s) then seat = s break end
            end
            if seat then
                ClearPedTasksImmediately(ped)
                SetPedIntoVehicle(ped, rtw, seat)
                TriggerServerEvent('ws_ems:transportPatient', NetworkGetNetworkIdFromEntity(ped))
                loaded = loaded + 1
            end
        end
    end

    if loaded == 0 then
        notifyT('transport_none', 'error')
        return cleanup(rtw, driver)
    end
    notifyT('transport_pickup', 'success')

    -- Abfahrt zum Krankenhaus, dann ausser Sichtweite entfernen
    local dp = WSEms.Station.dropoff
    TaskVehicleDriveToCoordLongrange(driver, rtw, dp.x, dp.y, dp.z, 22.0, 786468, 20.0)
    local away = GetGameTimer() + 40000
    while GetGameTimer() < away do
        Wait(1000)
        if not DoesEntityExist(rtw) then break end
        if #(GetEntityCoords(rtw) - scenePos) > 120.0 then break end
    end
    cleanup(rtw, driver)
end

exports.ox_target:addGlobalPed({
    {
        name = 'ws_ems_transport',
        label = locale('transport_target'),
        icon = 'fa-solid fa-truck-medical',
        distance = 2.5,
        canInteract = function(entity)
            local s = Entity(entity).state
            return isOnDuty() and not activeTransport
                and s['ws:patient'] and s['ws:patient_state'] == 'stable'
                and not IsPedInAnyVehicle(entity, false)
                and not IsEntityAttached(entity)
        end,
        onSelect = function(data)
            CreateThread(function() requestTransport(data.entity) end)
        end,
    },
})

AddEventHandler('onResourceStop', function(res)
    if res ~= cache.resource then return end
    for ent in pairs(spawnedEntities) do
        if DoesEntityExist(ent) then DeleteEntity(ent) end
    end
end)
