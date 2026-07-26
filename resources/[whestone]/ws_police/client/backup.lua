-- KI-Verstaerkung (Taste F7): eine Streife mit Beamten faehrt zum Officer,
-- unterstuetzt bei feindlichen Verdaechtigen und verschwindet danach wieder.

local active = false
local dismiss = false
local lastRequest = 0
local spawnedEntities = {} -- selbst erzeugte Streife/Beamte (Cleanup bei Resource-Stopp)

-- Eigene Relationship-Gruppe: Verstaerkung ist dem Spieler gegenueber
-- freundlich (greift ihn NIE an, auch nicht bei Fahndungssternen) und
-- feindlich gegenueber Callout-Verdaechtigen (greift automatisch ein).
local BACKUP_GROUP = joaat('WS_BACKUP')
CreateThread(function()
    AddRelationshipGroup('WS_BACKUP')
    local playerGroup = joaat('PLAYER')
    SetRelationshipBetweenGroups(1, BACKUP_GROUP, playerGroup) -- Respekt
    SetRelationshipBetweenGroups(1, playerGroup, BACKUP_GROUP)
    for _, name in ipairs({ 'WS_SUSPECT', 'WS_HOSTILE' }) do
        AddRelationshipGroup(name)
        local g = joaat(name)
        SetRelationshipBetweenGroups(5, BACKUP_GROUP, g) -- Hass
        SetRelationshipBetweenGroups(5, g, BACKUP_GROUP)
    end
    -- Ergebene/gefesselte Verdaechtige (WS_PRISONER) NICHT bekaempfen -
    -- Respekt statt Hass, sonst schiesst die Verstaerkung sie am Boden nieder
    AddRelationshipGroup('WS_PRISONER')
    local prisoner = joaat('WS_PRISONER')
    SetRelationshipBetweenGroups(1, BACKUP_GROUP, prisoner)
    SetRelationshipBetweenGroups(1, prisoner, BACKUP_GROUP)
end)

local function notifyBackup(key, ntype)
    lib.notify({ title = locale('backup_title'), description = locale(key), type = ntype or 'inform' })
end

local function findSpawnPoint(coords)
    for _, dist in ipairs({ 130.0, 90.0, 170.0 }) do
        local angle = math.rad(math.random(0, 359))
        local found, pos, heading = GetClosestVehicleNodeWithHeading(
            coords.x + math.cos(angle) * dist,
            coords.y + math.sin(angle) * dist,
            coords.z, 1, 3.0, 0)
        if found then return pos, heading end
    end
end

local function nearestHostileSuspect(coords)
    local best, bestDist
    for _, ped in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(ped) and not IsEntityDead(ped) then
            local s = Entity(ped).state
            if s['ws:suspect'] and not s['ws:cuffed'] and not s['ws:surrendered'] then
                local d = #(GetEntityCoords(ped) - coords)
                if d < 60.0 and (not bestDist or d < bestDist) then
                    best, bestDist = ped, d
                end
            end
        end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- Stufen-Auswahl (Leitstelle im Tablet)
-- ---------------------------------------------------------------------------

local function unlockedLevel()
    return math.min(3, LocalPlayer.state['ws:skill_support'] or 0)
end

-- Tatsaechlich gerufene Stufe: die in der Leitstelle gewaehlte, sofern
-- freigeschaltet - sonst die hoechste freigeschaltete. 0 = nicht freigeschaltet.
local function effectiveTier()
    local unlocked = unlockedLevel()
    if unlocked < 1 then return 0 end
    local sel = LocalPlayer.state['ws:backupTier']
    if sel and sel >= 1 and sel <= unlocked then return sel end
    return unlocked
end

-- Vom Tablet genutzt: aktuelle Auswahl + alle Stufen mit Freischalt-Status
exports('GetBackupInfo', function()
    local unlocked = unlockedLevel()
    local tiers = {}
    for i = 1, 3 do
        local t = WSPolice.Backup.Tiers[i]
        tiers[i] = {
            tier = i,
            label = t.label or ('Stufe ' .. i),
            officers = t.officers or 2,
            unlocked = i <= unlocked,
        }
    end
    return { level = unlocked, selected = effectiveTier(), tiers = tiers }
end)

-- Vom Tablet gesetzt: gewaehlte Stufe (nur freigeschaltete erlaubt).
-- Sofort lokal wirksam + serverseitig persistent gespeichert.
exports('SetBackupTier', function(tier)
    tier = tonumber(tier)
    if not tier or tier < 1 or tier > unlockedLevel() then return false end
    LocalPlayer.state:set('ws:backupTier', tier, true)
    TriggerServerEvent('ws_police:saveBackupTier', tier)
    return true
end)

local function requestBackup()
    if LocalPlayer.state['ws:job'] ~= 'police' or LocalPlayer.state['ws:duty'] ~= true then return end

    local now = GetGameTimer()
    -- F7 waehrend aktivem Einsatz = Verstaerkung wieder wegschicken (Toggle)
    if active then
        dismiss = true
        return notifyBackup('backup_dismissed', 'inform')
    end
    -- Stufe aus Skill + Leitstellen-Auswahl (ohne Skill keine Verstaerkung)
    local level = effectiveTier()
    if level < 1 then
        return notifyBackup('backup_no_skill', 'error')
    end
    local tier = WSPolice.Backup.Tiers[level]
    if now - lastRequest < WSPolice.Backup.cooldown * 1000 then
        return notifyBackup('backup_cooldown', 'error')
    end
    active = true
    dismiss = false
    lastRequest = now

    local ok = lib.progressBar({
        duration = 3000,
        label = locale('backup_requesting'),
        canCancel = true,
        disable = { move = true, combat = true },
        anim = { dict = 'random@arrests', clip = 'generic_radio_chatter', flag = 49 },
    })
    if not ok then
        active = false
        return
    end

    local origin = GetEntityCoords(cache.ped)
    local spawnPos, spawnHeading = findSpawnPoint(origin)
    if not spawnPos then
        notifyBackup('backup_failed', 'error')
        active = false
        return
    end

    local vehHash = joaat(tier.vehicle)
    local pedHash = joaat(tier.ped)
    -- lib.requestModel wirft bei Timeout einen Fehler -> abfangen, sonst
    -- stirbt der Thread und `active` bleibt fuer immer haengen
    local okModels = pcall(function()
        lib.requestModel(vehHash, 10000)
        lib.requestModel(pedHash, 10000)
    end)
    if not okModels then
        notifyBackup('backup_failed', 'error')
        active = false
        return
    end

    local veh = CreateVehicle(vehHash, spawnPos.x, spawnPos.y, spawnPos.z, spawnHeading, true, true)
    if not veh or veh == 0 then
        notifyBackup('backup_failed', 'error')
        active = false
        return
    end
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleSiren(veh, true)
    spawnedEntities[veh] = true

    local cops = {}
    -- Anzahl auf die Sitzplaetze des Fahrzeugs begrenzen, sonst spawnt ein
    -- Beamter ohne gueltigen Sitz irgendwo im Nirgendwo
    local officerCount = math.min(tier.officers or 2, GetVehicleModelNumberOfSeats(vehHash))
    for i = 1, officerCount do
        local seat = (i == 1) and -1 or (i - 2)
        local cop = CreatePed(4, pedHash, spawnPos.x, spawnPos.y, spawnPos.z, spawnHeading, true, true)
        SetEntityAsMissionEntity(cop, true, true)
        spawnedEntities[cop] = true
        SetPedIntoVehicle(cop, veh, seat)
        SetPedAsCop(cop, false) -- kein GTA-Cop-Verhalten (kein Angriff bei Sternen)
        SetPedRelationshipGroupHash(cop, BACKUP_GROUP)
        SetPedArmour(cop, tier.armour)
        SetPedAccuracy(cop, tier.accuracy)
        SetPedFleeAttributes(cop, 0, false)
        GiveWeaponToPed(cop, joaat(tier.weapon), 120, false, true)
        SetPedDropsWeaponsWhenDead(cop, false) -- keine Waffe faellt auf den Boden
        SetPedCombatAttributes(cop, 46, true)
        cops[#cops + 1] = cop
    end
    SetModelAsNoLongerNeeded(vehHash)
    SetModelAsNoLongerNeeded(pedHash)

    local driver = cops[1]
    SetDriverAbility(driver, 1.0)
    notifyBackup('backup_enroute', 'success')
    TaskVehicleDriveToCoordLongrange(driver, veh, origin.x, origin.y, origin.z, 20.0, 786468, 12.0)

    -- Anfahrt
    local deadline = GetGameTimer() + 45000
    while GetGameTimer() < deadline do
        Wait(500)
        if not DoesEntityExist(veh) then active = false return end
        if dismiss then break end
        if #(GetEntityCoords(veh) - GetEntityCoords(cache.ped)) < 25.0 then break end
    end

    -- Verkeilt/nicht angekommen? Als letzte Rettung an den naechsten
    -- Strassenknoten beim Officer setzen (wie bei Abschlepper/Transport)
    if not dismiss and DoesEntityExist(veh)
        and #(GetEntityCoords(veh) - GetEntityCoords(cache.ped)) >= 25.0 then
        local p = GetEntityCoords(cache.ped)
        local found, nodePos = GetClosestVehicleNode(p.x, p.y, p.z, 1, 3.0, 0)
        local dest = found and nodePos or p
        SetEntityCoords(veh, dest.x, dest.y, dest.z, false, false, false, false)
        for i, cop in ipairs(cops) do
            if DoesEntityExist(cop) and not IsPedInVehicle(cop, veh, false) then
                SetPedIntoVehicle(cop, veh, (i == 1) and -1 or (i - 2))
            end
        end
    end

    if not dismiss then
        notifyBackup('backup_arrived', 'success')

        -- Vor Ort: aussteigen und feindliche Verdaechtige bekaempfen, sonst sichern
        for _, cop in ipairs(cops) do
            if DoesEntityExist(cop) then
                TaskLeaveVehicle(cop, veh, 0)
            end
        end
        Wait(1500)
    end

    -- Einsatzverhalten, bis Wegschicken, keine Bedrohung mehr oder Officer weit weg
    while active and not dismiss do
        Wait(2000)
        local ppos = GetEntityCoords(cache.ped)
        if not DoesEntityExist(veh) or #(GetEntityCoords(veh) - ppos) > WSPolice.Backup.despawnDistance then
            break
        end

        local threat = nearestHostileSuspect(ppos)
        for _, cop in ipairs(cops) do
            if DoesEntityExist(cop) and not IsEntityDead(cop) then
                if threat then
                    if not IsPedInCombat(cop, threat) then
                        TaskCombatPed(cop, threat, 0, 16)
                    end
                elseif not IsPedInAnyVehicle(cop, false) and #(GetEntityCoords(cop) - ppos) > 4.0 then
                    -- Keine gueltige Bedrohung mehr: zum Officer zurueck. Das
                    -- bricht einen evtl. noch laufenden Kampf-Task ab, damit nicht
                    -- auf einen soeben Ergebenen/Gefesselten weitergeschossen wird.
                    TaskGoToEntity(cop, cache.ped, -1, 3.0, 2.0, 1073741824.0, 0)
                end
            end
        end
    end

    -- Abzug: einsteigen und wegfahren, dann ausserhalb der Sichtweite entfernen
    for _, cop in ipairs(cops) do
        if DoesEntityExist(cop) and not IsEntityDead(cop) then
            TaskEnterVehicle(cop, veh, 10000, (cop == driver) and -1 or 0, 2.0, 1, 0)
        end
    end
    Wait(6000)
    if DoesEntityExist(veh) and DoesEntityExist(driver) and not IsEntityDead(driver) then
        local target = GetEntityCoords(veh) + GetEntityForwardVector(veh) * 200.0
        local found, awayPos = GetClosestVehicleNode(target.x, target.y, target.z, 1, 3.0, 0)
        local dest = found and awayPos or target
        TaskVehicleDriveToCoordLongrange(driver, veh, dest.x, dest.y, dest.z, 20.0, 786468, 30.0)
    end

    local off = GetGameTimer() + 25000
    while GetGameTimer() < off do
        Wait(1000)
        if not DoesEntityExist(veh) then break end
        if #(GetEntityCoords(veh) - GetEntityCoords(cache.ped)) > 90.0 then break end
    end

    for _, cop in ipairs(cops) do
        if DoesEntityExist(cop) then DeleteEntity(cop) end
        spawnedEntities[cop] = nil
    end
    if DoesEntityExist(veh) then DeleteEntity(veh) end
    spawnedEntities[veh] = nil
    active = false
end

RegisterCommand('verstaerkung', requestBackup, false)
RegisterKeyMapping('verstaerkung', 'Polizei: Verstärkung anfordern', 'keyboard', 'F7')

-- Bei Resource-Stopp mitten im Einsatz selbst erzeugte Streife/Beamte entfernen
AddEventHandler('onResourceStop', function(res)
    if res ~= cache.resource then return end
    for ent in pairs(spawnedEntities) do
        if DoesEntityExist(ent) then DeleteEntity(ent) end
    end
end)
