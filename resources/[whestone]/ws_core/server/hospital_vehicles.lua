-- Roller-Reihe am Krankenhaus: wird gespawnt, sobald ein Spieler in der
-- Naehe ist (OneSync: Entities ohne Spieler im Umkreis materialisieren
-- nicht zuverlaessig), und laufend aufgefuellt.

local spawned = {} -- Spawnpunkt-Index -> Entity
local taken = {}   -- weggefahrene Roller: Entity -> Zeitpunkt der letzten Nutzung

local function buildSpawnPoints()
    local cfg = WSConfig.HospitalVehicles
    local delta = vector3(cfg.to.x - cfg.from.x, cfg.to.y - cfg.from.y, cfg.to.z - cfg.from.z)
    local count = math.max(1, math.floor(#delta / cfg.spacing))

    local points = {}
    for i = 0, count do
        local t = i / count
        points[#points + 1] = vector4(
            cfg.from.x + delta.x * t,
            cfg.from.y + delta.y * t,
            cfg.from.z + delta.z * t,
            cfg.from.w
        )
    end
    return points
end

local function anyPlayerNear(coords, radius)
    for _, src in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(src)
        if ped and ped > 0 and #(GetEntityCoords(ped) - coords) < radius then
            return true
        end
    end
    return false
end

local function ensureVehicles(points)
    local cfg = WSConfig.HospitalVehicles
    local created = 0

    for i, p in ipairs(points) do
        local veh = spawned[i]
        local needsSpawn = not veh or not DoesEntityExist(veh)

        -- Wurde der Roller weggefahren, bleibt er dem Fahrer erhalten -
        -- am Spawnpunkt wird ein neuer bereitgestellt, der alte kommt auf
        -- die Despawn-Liste (verlassene Roller werden spaeter geloescht)
        if not needsSpawn and #(GetEntityCoords(veh) - vector3(p.x, p.y, p.z)) > 3.0 then
            taken[veh] = os.time()
            spawned[i] = nil
            needsSpawn = true
        end

        if needsSpawn then
            local v = CreateVehicle(joaat(cfg.model), p.x, p.y, p.z, p.w, true, true)
            local tries = 0
            while not DoesEntityExist(v) and tries < 50 do
                Wait(25)
                tries = tries + 1
            end
            if DoesEntityExist(v) then
                spawned[i] = v
                created = created + 1
            end
        end
    end

    if created > 0 then
        print(('[ws_core] %d Roller am Krankenhaus bereitgestellt.'):format(created))
    end
end

CreateThread(function()
    local points = buildSpawnPoints()
    local cfg = WSConfig.HospitalVehicles
    local anchor = vector3(
        (cfg.from.x + cfg.to.x) / 2,
        (cfg.from.y + cfg.to.y) / 2,
        (cfg.from.z + cfg.to.z) / 2
    )
    print(('[ws_core] Roller-Spawner aktiv: %d Spawnpunkte am Krankenhaus.'):format(#points))

    while true do
        Wait(10000)
        -- Erst spawnen, wenn jemand in der Naehe ist - sonst haengen die
        -- Fahrzeuge in einem nie instanziierten Zustand fest
        if anyPlayerNear(anchor, 300.0) then
            ensureVehicles(points)
        end
    end
end)

local function isOccupied(veh)
    for seat = -1, 0 do
        local ped = GetPedInVehicleSeat(veh, seat)
        if ped and ped ~= 0 then return true end
    end
    return false
end

-- Verlassene Roller nach Ablauf der Frist loeschen; solange jemand
-- draufsitzt, wird der Timer zurueckgesetzt
CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        local limit = (WSConfig.HospitalVehicles.despawnMinutes or 10) * 60

        for veh, lastUsed in pairs(taken) do
            if not DoesEntityExist(veh) then
                taken[veh] = nil
            elseif isOccupied(veh) then
                taken[veh] = now
            elseif now - lastUsed >= limit then
                DeleteEntity(veh)
                taken[veh] = nil
            end
        end
    end
end)

-- Beim Stoppen die unbenutzten Roller (Spawnpunkt + verlassene) entfernen
AddEventHandler('onResourceStop', function(res)
    if res ~= cache.resource then return end
    local points = buildSpawnPoints()
    for i, veh in pairs(spawned) do
        local p = points[i]
        if DoesEntityExist(veh) and p and #(GetEntityCoords(veh) - vector3(p.x, p.y, p.z)) < 3.0 then
            DeleteEntity(veh)
        end
    end
    for veh in pairs(taken) do
        if DoesEntityExist(veh) and not isOccupied(veh) then
            DeleteEntity(veh)
        end
    end
end)
