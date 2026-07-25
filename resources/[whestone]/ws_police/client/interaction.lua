-- Anhaltezeichen: anvisierte Fahrzeuge/Personen zum Anhalten bringen.
-- Callout-Verdaechtige (Statebag ws:suspect) ignorieren das Zeichen.

local lastStop = 0

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

local function rotationToDirection(rot)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

-- Entity in Blickrichtung der Kamera (Fahrzeuge + Peds)
local function getAimedEntity()
    local camCoord = GetGameplayCamCoord()
    local dir = rotationToDirection(GetGameplayCamRot(2))
    local dest = camCoord + dir * WSPolice.Stop.range

    local handle = StartShapeTestCapsule(
        camCoord.x, camCoord.y, camCoord.z,
        dest.x, dest.y, dest.z,
        1.2, 14, cache.ped, 4
    )
    local status, hit, entity
    repeat
        status, hit, _, _, entity = GetShapeTestResult(handle)
        Wait(0)
    until status == 2

    if hit == 1 and entity and entity ~= 0 and DoesEntityExist(entity) then
        return entity
    end
end

local function notifyStop(key, ntype)
    lib.notify({ title = locale('stop_title'), description = locale(key), type = ntype or 'inform' })
end

-- Verdaechtige UND fluechtende Fahrer ignorieren das Anhaltezeichen
local function isSuspect(ped)
    local s = Entity(ped).state
    return s and (s['ws:suspect'] == true or s['ws:fleeing'] == true)
end

local function stopPed(ped)
    if isSuspect(ped) then
        return notifyStop('stop_ignored', 'error')
    end
    if not ensureControl(ped) then return end

    ClearPedTasks(ped)
    SetBlockingOfNonTemporaryEvents(ped, true)
    TaskStandStill(ped, WSPolice.Stop.duration * 1000)
    SetTimeout(WSPolice.Stop.duration * 1000, function()
        if DoesEntityExist(ped) and not isSuspect(ped) then
            SetBlockingOfNonTemporaryEvents(ped, false)
        end
    end)
    notifyStop('stop_ped', 'success')
end

-- Wird das Fahrzeug von einer Verkehrskontrolle oder als Verdaechtiger
-- gehalten? Dann uebernimmt jene Logik das Halten/Freigeben.
local function isBeingControlled(driver)
    local s = Entity(driver).state
    return s['ws:suspect'] == true or s['ws:trafficstop'] == true
end

local function stopVehicle(veh)
    local driver = GetPedInVehicleSeat(veh, -1)
    if driver == 0 or not DoesEntityExist(driver) then
        return notifyStop('stop_nothing', 'error')
    end
    if IsPedAPlayer(driver) then return end
    if isSuspect(driver) then
        return notifyStop('stop_ignored', 'error')
    end
    if not ensureControl(driver) or not ensureControl(veh) then return end

    ClearPedTasks(driver)
    SetBlockingOfNonTemporaryEvents(driver, true)

    -- Rechts ranfahren: Ziel etwas voraus und nach rechts versetzt
    local pos = GetEntityCoords(veh)
    local fwd = GetEntityForwardVector(veh)
    local right = vector3(fwd.y, -fwd.x, 0.0) -- 90 Grad rechts
    local target = pos + fwd * 15.0 + right * 3.5
    TaskVehicleDriveToCoord(driver, veh, target.x, target.y, target.z, 12.0, 0,
        GetEntityModel(veh), 786603, 3.0, true)
    notifyStop('stop_vehicle', 'success')

    CreateThread(function()
        -- Phase 1: bis zu 7s zum Rechts-ranfahren geben
        local arriveBy = GetGameTimer() + 7000
        while GetGameTimer() < arriveBy do
            Wait(200)
            if not DoesEntityExist(veh) or not DoesEntityExist(driver) or isBeingControlled(driver) then return end
            if #(GetEntityCoords(veh) - target) < 4.0 or GetEntitySpeed(veh) < 0.5 then break end
        end

        -- Phase 2: Fahrzeug fest stehen halten (eingefroren) - KEIN Zeitlimit.
        -- Es bleibt stehen, bis eine Verkehrskontrolle uebernimmt oder der
        -- Officer sich weit entfernt (dann faehrt es weiter).
        while DoesEntityExist(veh) and DoesEntityExist(driver) do
            if isBeingControlled(driver) then return end -- Kontrolle uebernimmt das Halten
            if #(GetEntityCoords(veh) - GetEntityCoords(cache.ped)) > 60.0 then break end
            if ensureControl(veh) then
                SetVehicleHandbrake(veh, true)
                FreezeEntityPosition(veh, true)
            end
            Wait(500)
        end

        -- Freigabe (Officer ist weg): weiterfahren lassen
        if DoesEntityExist(veh) and DoesEntityExist(driver) and not isBeingControlled(driver) then
            if ensureControl(veh) then
                FreezeEntityPosition(veh, false)
                SetVehicleHandbrake(veh, false)
            end
            if ensureControl(driver) then
                SetBlockingOfNonTemporaryEvents(driver, false)
                TaskVehicleDriveWander(driver, veh, 12.0, 786603)
            end
        end
    end)
end

RegisterCommand('anhalten', function()
    if LocalPlayer.state['ws:job'] ~= 'police' or LocalPlayer.state['ws:duty'] ~= true then return end

    local now = GetGameTimer()
    if now - lastStop < WSPolice.Stop.cooldown * 1000 then return end
    lastStop = now

    local entity = getAimedEntity()
    if not entity then
        return notifyStop('stop_nothing', 'error')
    end

    -- Kurze Geste, wenn zu Fuss
    if not cache.vehicle then
        lib.requestAnimDict('gestures@m@standing@casual')
        TaskPlayAnim(cache.ped, 'gestures@m@standing@casual', 'gesture_point', 8.0, -8.0, 1200, 48, 0.0, false, false, false)
    end

    if IsEntityAVehicle(entity) then
        stopVehicle(entity)
    elseif IsEntityAPed(entity) and not IsPedAPlayer(entity) then
        if IsPedInAnyVehicle(entity, false) then
            stopVehicle(GetVehiclePedIsIn(entity, false))
        else
            stopPed(entity)
        end
    end
end, false)
RegisterKeyMapping('anhalten', 'Polizei: Anhaltezeichen geben', 'keyboard', 'U')
