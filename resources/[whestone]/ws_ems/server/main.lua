lib.locale()

local ActiveVehicles = {}

local function isEms(src)
    return exports.ws_core:GetJob(src) == 'ambulance'
end

local function deleteVehicle(src)
    local veh = ActiveVehicles[src]
    if veh and DoesEntityExist(veh) then DeleteEntity(veh) end
    ActiveVehicles[src] = nil
end

lib.callback.register('ws_ems:isAdmin', function(src)
    return IsPlayerAceAllowed(src, 'ws.admin')
end)

lib.callback.register('ws_ems:setDuty', function(src, onDuty)
    if not isEms(src) then return false end
    return exports.ws_core:SetDuty(src, onDuty)
end)

lib.callback.register('ws_ems:spawnVehicle', function(src, model)
    if not isEms(src) or not exports.ws_core:IsOnDuty(src) then return nil end

    local entry
    for _, v in ipairs(WSEms.Vehicles) do
        if v.model == model then entry = v break end
    end
    if not entry or exports.ws_core:GetRank(src) < (entry.minRank or 0) then return nil end

    deleteVehicle(src)

    local sp = WSEms.Station.garageSpawn
    local veh = CreateVehicle(joaat(model), sp.x, sp.y, sp.z, sp.w, true, true)
    if not veh or veh == 0 then return false, 'model' end

    local tries = 0
    while not DoesEntityExist(veh) and tries < 100 do Wait(25) tries = tries + 1 end
    if not DoesEntityExist(veh) then return false, 'model' end

    ActiveVehicles[src] = veh
    return NetworkGetNetworkIdFromEntity(veh)
end)

lib.callback.register('ws_ems:spawnHeli', function(src, model)
    if not isEms(src) or not exports.ws_core:IsOnDuty(src) then return nil end

    local entry
    for _, v in ipairs(WSEms.Helicopters) do
        if v.model == model then entry = v break end
    end
    if not entry or exports.ws_core:GetRank(src) < (entry.minRank or 0) then return nil end

    deleteVehicle(src)

    local sp = WSEms.Helipad.spawn
    local veh = CreateVehicle(joaat(model), sp.x, sp.y, sp.z, sp.w, true, true)
    if not veh or veh == 0 then return false, 'model' end

    local tries = 0
    while not DoesEntityExist(veh) and tries < 100 do Wait(25) tries = tries + 1 end
    if not DoesEntityExist(veh) then return false, 'model' end

    ActiveVehicles[src] = veh
    return NetworkGetNetworkIdFromEntity(veh)
end)

lib.callback.register('ws_ems:returnVehicle', function(src)
    local veh = ActiveVehicles[src]
    if not veh or not DoesEntityExist(veh) then
        ActiveVehicles[src] = nil
        return false
    end
    -- Rueckgabe an der Garage ODER auf dem Helipad
    local pos = GetEntityCoords(veh)
    local hp = WSEms.Helipad.spawn
    if #(pos - WSEms.Station.garage) > 60.0
        and #(pos - vector3(hp.x, hp.y, hp.z)) > 60.0 then
        return false
    end
    deleteVehicle(src)
    return true
end)

-- ---------------------------------------------------------------------------
-- Patienten (aus EMS-Notfaellen)
-- ---------------------------------------------------------------------------

-- Ped als Patient markieren (von der EMS-Notfall-Engine genutzt)
exports('RegisterPatient', function(netId, state)
    local ent = NetworkGetEntityFromNetworkId(netId)
    local tries = 0
    while (not ent or ent == 0 or not DoesEntityExist(ent)) and tries < 40 do
        Wait(50) tries = tries + 1
        ent = NetworkGetEntityFromNetworkId(netId)
    end
    if not ent or ent == 0 or not DoesEntityExist(ent) then return false end

    local st = Entity(ent).state
    st:set('ws:patient', true, true)
    st:set('ws:patient_state', state or 'unconscious', true)
    st:set('ws:patient_diag', false, true)
    return true
end)

-- Zustand aktualisieren + XP bei Fortschritt (server-validiert)
RegisterNetEvent('ws_ems:updatePatient', function(netId, state, diagnosed)
    local src = source
    if not isEms(src) or not exports.ws_core:IsOnDuty(src) then return end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end
    local st = Entity(ent).state
    if not st['ws:patient'] then return end

    if diagnosed and not st['ws:patient_diag'] then
        st:set('ws:patient_diag', true, true)
        exports.ws_core:AddXP(src, WSEms.XP.diagnose, locale('xp_diagnose'))
    end

    if state and state ~= st['ws:patient_state'] then
        local wasStable = st['ws:patient_state'] == 'stable'
        st:set('ws:patient_state', state, true)
        if state == 'stable' and not wasStable then
            exports.ws_core:AddStat(src, 'treatments', 1)
            exports.ws_core:AddXP(src, WSEms.XP.treat, locale('xp_treat'))
        end
    end
end)

-- Patient in der Notaufnahme eingeliefert
RegisterNetEvent('ws_ems:deliverPatient', function(netId)
    local src = source
    if not isEms(src) or not exports.ws_core:IsOnDuty(src) then return end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end
    local st = Entity(ent).state
    if not st['ws:patient'] or st['ws:patient_state'] ~= 'stable' then return end

    -- Einlieferung an der Notaufnahme ODER auf dem Helipad
    local pos = GetEntityCoords(ent)
    local d, h = WSEms.Station.dropoff, WSEms.Helipad.dropoff
    local dist = math.min(
        #(pos - vector3(d.x, d.y, d.z)),
        #(pos - vector3(h.x, h.y, h.z)))
    if dist > WSEms.DeliverRadius + 5.0 then return end

    exports.ws_core:AddXP(src, WSEms.XP.deliver, locale('xp_deliver'))
    exports.ws_core:AddStat(src, 'patients', 1)
    TriggerEvent('ws_ems:patientDelivered', netId, src)
    DeleteEntity(ent)
end)

-- Patient per gerufenem NPC-RTW abtransportiert (kein Distanz-Check, da der
-- NPC-Wagen den Transport uebernimmt; etwas weniger XP als die Eigenlieferung)
RegisterNetEvent('ws_ems:transportPatient', function(netId)
    local src = source
    if not isEms(src) or not exports.ws_core:IsOnDuty(src) then return end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end
    local st = Entity(ent).state
    if not st['ws:patient'] or st['ws:patient_state'] ~= 'stable' then return end

    exports.ws_core:AddXP(src, WSEms.XP.transport or WSEms.XP.deliver, locale('xp_transport'))
    exports.ws_core:AddStat(src, 'patients', 1)
    TriggerEvent('ws_ems:patientDelivered', netId, src)
    DeleteEntity(ent)
end)

AddEventHandler('ws_core:dutyChanged', function(src, onDuty)
    if not onDuty then deleteVehicle(src) end
end)

AddEventHandler('playerDropped', function()
    deleteVehicle(source)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= cache.resource then return end
    for src in pairs(ActiveVehicles) do deleteVehicle(src) end
end)
