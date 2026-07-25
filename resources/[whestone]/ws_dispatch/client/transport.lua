-- Gefangenentransport: Ein NPC-Transporter faehrt an, laedt festgenommene
-- Verdaechtige ein und transportiert sie ab (weniger XP als Eigenlieferung).

local TRANSPORT_VAN = 'policet'
local TRANSPORT_DRIVER = 's_m_y_cop_01'

local activeTransport = false
local spawnedEntities = {} -- selbst erzeugte Vans/Fahrer (fuer Cleanup bei Resource-Stopp)

local function notifyTransport(key, ntype)
    lib.notify({ title = locale('dispatch_title'), description = locale(key), type = ntype or 'inform' })
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

local function cleanupTransport(van, driver, prisoner)
    for _, ent in ipairs({ prisoner, driver, van }) do
        if ent and DoesEntityExist(ent) and EnsureControl(ent) then
            SetEntityAsMissionEntity(ent, true, true)
            DeleteEntity(ent)
        end
        if ent then spawnedEntities[ent] = nil end
    end
    activeTransport = false
end

local function requestTransport(ped)
    if activeTransport then return end
    activeTransport = true

    local ok = lib.progressBar({
        duration = 3000,
        label = locale('transport_requesting'),
        canCancel = true,
        disable = { move = true, combat = true },
        -- Funkgeraet-Animation (Oberkoerper)
        anim = { dict = 'random@arrests', clip = 'generic_radio_chatter', flag = 49 },
    })
    if not ok or not DoesEntityExist(ped) then
        activeTransport = false
        return
    end

    local pedPos = GetEntityCoords(ped)
    local netId = NetworkGetNetworkIdFromEntity(ped)

    local spawnPos, spawnHeading = findSpawnPoint(pedPos)
    if not spawnPos then
        notifyTransport('transport_failed', 'error')
        activeTransport = false
        return
    end

    local vanHash, driverHash = joaat(TRANSPORT_VAN), joaat(TRANSPORT_DRIVER)
    lib.requestModel(vanHash, 10000)
    lib.requestModel(driverHash, 10000)

    local van = CreateVehicle(vanHash, spawnPos.x, spawnPos.y, spawnPos.z, spawnHeading, true, true)
    local driver = CreatePed(4, driverHash, spawnPos.x, spawnPos.y, spawnPos.z, spawnHeading, true, true)
    SetModelAsNoLongerNeeded(vanHash)
    SetModelAsNoLongerNeeded(driverHash)
    SetEntityAsMissionEntity(van, true, true)
    SetEntityAsMissionEntity(driver, true, true)
    spawnedEntities[van] = true
    spawnedEntities[driver] = true
    SetPedIntoVehicle(driver, van, -1)
    SetBlockingOfNonTemporaryEvents(driver, true)
    SetDriverAbility(driver, 1.0)
    SetDriverAggressiveness(driver, 0.0)
    SetVehicleSiren(van, true)

    notifyTransport('transport_enroute', 'success')

    -- Naechster Strassenknoten am Gefangenen als Anfahrtsziel
    local nodeFound, roadPos = GetClosestVehicleNode(pedPos.x, pedPos.y, pedPos.z, 1, 3.0, 0)
    local drivePos = nodeFound and roadPos or pedPos
    -- Einsatzfahrt: Ampeln ignorieren, Verkehr umfahren (Sonderrechte)
    TaskVehicleDriveToCoordLongrange(driver, van, drivePos.x, drivePos.y, drivePos.z, 22.0, 786468, 10.0)

    local deadline = GetGameTimer() + 90000
    while GetGameTimer() < deadline do
        Wait(500)
        if not DoesEntityExist(van) or not DoesEntityExist(ped) then
            return cleanupTransport(van, driver, nil)
        end
        if #(GetEntityCoords(van) - GetEntityCoords(ped)) < 35.0 then break end
    end
    if not DoesEntityExist(ped) or IsEntityDead(ped) then
        return cleanupTransport(van, driver, nil)
    end
    if #(GetEntityCoords(van) - GetEntityCoords(ped)) >= 35.0 then
        SetEntityCoords(van, drivePos.x, drivePos.y, drivePos.z, false, false, false, false)
        SetPedIntoVehicle(driver, van, -1)
    end

    ClearPedTasks(driver)
    TaskVehicleTempAction(driver, van, 27, 3000)
    Wait(1500)

    -- Gefangenen einladen
    if not EnsureControl(ped) then
        return cleanupTransport(van, driver, nil)
    end
    ClearPedTasksImmediately(ped)
    local seated = false
    for _, seat in ipairs({ 1, 2, 3, 0 }) do
        if IsVehicleSeatFree(van, seat) then
            SetPedIntoVehicle(ped, van, seat)
            seated = true
            break
        end
    end
    if not seated then
        return cleanupTransport(van, driver, nil)
    end

    notifyTransport('transport_pickup', 'success')
    TriggerServerEvent('ws_dispatch:transportSuspect', netId)

    -- Abfahrt mit Sonderrechten: ausserhalb der Sichtweite alles entfernen
    TaskVehicleDriveToCoordLongrange(driver, van, spawnPos.x, spawnPos.y, spawnPos.z, 22.0, 786468, 20.0)
    local away = GetGameTimer() + 30000
    while GetGameTimer() < away do
        Wait(1000)
        if not DoesEntityExist(van) then break end
        if #(GetEntityCoords(van) - pedPos) > 80.0 then break end
    end

    cleanupTransport(van, driver, ped)
end

exports.ox_target:addGlobalPed({
    {
        name = 'ws_transport',
        label = locale('target_transport'),
        icon = 'fa-solid fa-van-shuttle',
        canInteract = function(entity)
            local s = Entity(entity).state
            return LocalPlayer.state['ws:duty'] == true
                and not activeTransport
                and s['ws:cuffed'] == true
                and not IsPedInAnyVehicle(entity, false)
                and not IsEntityAttached(entity)
        end,
        onSelect = function(data)
            CreateThread(function()
                requestTransport(data.entity)
            end)
        end,
    },
})

-- Bei Resource-Stopp mitten im Transport selbst erzeugte Vans/Fahrer entfernen
-- (der Gefangene selbst wird vom Callout-System aufgeraeumt)
AddEventHandler('onResourceStop', function(res)
    if res ~= cache.resource then return end
    for ent in pairs(spawnedEntities) do
        if DoesEntityExist(ent) then DeleteEntity(ent) end
    end
end)
