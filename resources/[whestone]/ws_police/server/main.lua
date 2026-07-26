lib.locale()

-- Aktives Dienstfahrzeug je Officer (Entity-Handle, server-seitig)
local ActiveVehicles = {}

local function deleteVehicle(src)
    local veh = ActiveVehicles[src]
    if veh and DoesEntityExist(veh) then
        DeleteEntity(veh)
    end
    ActiveVehicles[src] = nil
end

local function isPolice(src)
    return exports.ws_core:GetJob(src) == 'police'
end

lib.callback.register('ws_police:setDuty', function(src, onDuty)
    if not isPolice(src) then return false end
    return exports.ws_core:SetDuty(src, onDuty)
end)

lib.callback.register('ws_police:getLoadout', function(src, kind)
    local loadout = WSPolice.Loadouts[kind]
    if not loadout then return nil end
    if not isPolice(src) or not exports.ws_core:IsOnDuty(src) then return nil end
    if exports.ws_core:GetRank(src) < loadout.minRank then return nil end
    return loadout.weapons
end)

lib.callback.register('ws_police:getSkillLoadout', function(src, level)
    local entry = WSPolice.SkillWeapons[level]
    if not entry then return nil end
    if not exports.ws_core:IsOnDuty(src) then return nil end
    if exports.ws_core:GetSkill(src, 'weapons') < level then return nil end
    return entry.weapons
end)

lib.callback.register('ws_police:spawnVehicle', function(src, model)
    if not exports.ws_core:IsOnDuty(src) then return nil end

    if not isPolice(src) then return nil end
    local entry
    for _, v in ipairs(WSPolice.Vehicles) do
        if v.model == model then entry = v break end
    end
    if not entry or exports.ws_core:GetRank(src) < entry.minRank then return nil end

    -- Nur ein Dienstfahrzeug pro Officer
    deleteVehicle(src)

    local sp = WSPolice.Station.garageSpawn
    local veh = CreateVehicle(joaat(model), sp.x, sp.y, sp.z, sp.w, true, true)
    -- Ungueltiges Modell (kein Vanilla, kein Addon) -> CreateVehicle liefert 0
    if not veh or veh == 0 then return false, 'model' end

    local tries = 0
    while not DoesEntityExist(veh) and tries < 100 do
        Wait(25)
        tries = tries + 1
    end
    if not DoesEntityExist(veh) then return false, 'model' end

    ActiveVehicles[src] = veh
    return NetworkGetNetworkIdFromEntity(veh)
end)

lib.callback.register('ws_police:returnVehicle', function(src)
    local veh = ActiveVehicles[src]
    if not veh or not DoesEntityExist(veh) then
        ActiveVehicles[src] = nil
        return false
    end

    -- Fahrzeug muss in der Naehe der Wache stehen
    local dist = #(GetEntityCoords(veh) - WSPolice.Station.garage)
    if dist > 60.0 then return false end

    deleteVehicle(src)
    return true
end)

-- Dienstantritt: gespeicherte Verstaerkungs-Auswahl wiederherstellen
-- (persistent in stats.backupTier). Dienstende: Fahrzeug einziehen.
AddEventHandler('ws_core:dutyChanged', function(src, onDuty)
    if onDuty then
        local tier = exports.ws_core:GetStat(src, 'backupTier')
        if tier and tier >= 1 then
            Player(src).state:set('ws:backupTier', tier, true)
        end
    else
        deleteVehicle(src)
    end
end)

-- Verstaerkungs-Auswahl speichern (aus der Leitstelle im Tablet). Server-seitig
-- gegen die tatsaechliche Freischalt-Stufe validiert und persistent abgelegt.
RegisterNetEvent('ws_police:saveBackupTier', function(tier)
    local src = source
    tier = tonumber(tier)
    if not isPolice(src) or not tier then return end
    local max = math.min(3, exports.ws_core:GetSkill(src, 'support') or 0)
    if tier < 1 or tier > max then return end
    exports.ws_core:SetStat(src, 'backupTier', tier)
    Player(src).state:set('ws:backupTier', tier, true)
end)

AddEventHandler('playerDropped', function()
    deleteVehicle(source)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= cache.resource then return end
    for src in pairs(ActiveVehicles) do
        deleteVehicle(src)
    end
end)
