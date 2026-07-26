lib.locale()

-- EMS-Notfall-Engine: generiert medizinische Notfaelle fuer Sanitaeter im
-- Dienst, verwaltet Angebot/Annahme und schliesst bei Einlieferung ab.

local Emergencies = {}
local nextUid = 0
local lastAt = 0
local nextInterval = 0

-- Pseudo-Notfalltyp fuer handlungsunfaehige Spieler. Bewusst NICHT in
-- WSEms.Emergencies eingetragen, damit die Zufallsgenerierung ihn nie zieht:
-- er hat weder feste Orte noch einen Patienten-Ped - der Patient ist der
-- Spieler selbst.
local PLAYER_RESCUE_ID = 'player_rescue'
local PLAYER_RESCUE = {
    label = 'Menschenrettung – Person am Boden',
    code = 'Notfall Rot',
    xp = 40, -- zusaetzlich zur Wiederbelebungs-XP aus ws_core
}

local function emData(em)
    if em.id == PLAYER_RESCUE_ID then return PLAYER_RESCUE end
    return WSEms.Emergencies[em.id]
end

local function emsOnDuty()
    return exports.ws_core:GetOnDutyPlayers('ambulance')
end

local function notify(src, description, ntype)
    TriggerClientEvent('ox_lib:notify', src, {
        title = locale('dispatch_title'), description = description, type = ntype or 'inform',
    })
end

local function countActive()
    local n = 0
    for _ in pairs(Emergencies) do n = n + 1 end
    return n
end

local function findAssignment(src)
    for _, em in pairs(Emergencies) do
        if em.medic == src then return em end
    end
end

local function createEmergency(id)
    local medics = emsOnDuty()
    if #medics == 0 then return false, 'keine Sanitäter im Dienst' end

    local data = id and WSEms.Emergencies[id]
    if id and not data then return false, ('unbekannter Notfall: %s'):format(id) end
    if not data then
        local ids = {}
        for k in pairs(WSEms.Emergencies) do ids[#ids + 1] = k end
        id = ids[math.random(#ids)]
        data = WSEms.Emergencies[id]
    end

    nextUid = nextUid + 1
    local em = {
        uid = nextUid, id = id,
        coords = data.locations[math.random(#data.locations)],
        state = 'offered', medic = nil,
        patients = {}, expected = nil, delivered = 0, -- mehrere Patienten moeglich
    }
    Emergencies[em.uid] = em

    local offer = { uid = em.uid, id = id, label = data.label, code = data.code, coords = em.coords }
    for _, src in ipairs(medics) do TriggerClientEvent('ws_ems:offer', src, offer) end

    SetTimeout(WSEms.Callout.acceptTimeout * 1000, function()
        local e = Emergencies[em.uid]
        if e and e.state == 'offered' then
            Emergencies[em.uid] = nil
            for _, src in ipairs(emsOnDuty()) do TriggerClientEvent('ws_ems:offerExpired', src, em.uid) end
        end
    end)
    return true
end

CreateThread(function()
    nextInterval = math.random(WSEms.Callout.intervalMin, WSEms.Callout.intervalMax)
    while true do
        Wait(10000)
        local medics = emsOnDuty()
        if #medics > 0 then
            local maxC = math.max(1, math.floor(#medics / WSEms.Callout.perCallout))
            local now = os.time()
            if countActive() < maxC and (now - lastAt) >= nextInterval then
                if createEmergency() then
                    lastAt = now
                    nextInterval = math.random(WSEms.Callout.intervalMin, WSEms.Callout.intervalMax)
                end
            end
        end
    end
end)

RegisterNetEvent('ws_ems:accept', function(uid)
    local src = source
    local em = Emergencies[uid]
    if not em then return notify(src, locale('offer_gone'), 'error') end
    if exports.ws_core:GetJob(src) ~= 'ambulance' or not exports.ws_core:IsOnDuty(src) then return end
    if em.state ~= 'offered' then return notify(src, locale('offer_taken_short'), 'error') end
    if findAssignment(src) then return notify(src, locale('already_assigned'), 'error') end

    em.state = 'active'
    em.medic = src
    local data = emData(em)
    TriggerClientEvent('ws_ems:assigned', src, {
        uid = em.uid, id = em.id, label = data.label, code = data.code, coords = em.coords,
    })
    for _, o in ipairs(emsOnDuty()) do
        if o ~= src then TriggerClientEvent('ws_ems:offerTaken', o, uid, GetPlayerName(src)) end
    end
end)

-- Client meldet die Gesamtzahl der Patienten der Szene (fuer den Abschluss)
RegisterNetEvent('ws_ems:sceneSpawned', function(uid, count)
    local src = source
    local em = Emergencies[uid]
    if not em or em.medic ~= src then return end
    em.expected = math.max(1, tonumber(count) or 1)
end)

-- Client meldet einen gespawnten Patienten
RegisterNetEvent('ws_ems:registerPatient', function(uid, netId)
    local src = source
    local em = Emergencies[uid]
    if not em or em.medic ~= src or em.id == PLAYER_RESCUE_ID then return end
    em.patients[netId] = true
    local data = emData(em)
    exports.ws_ems:RegisterPatient(netId, data.patientState)
end)

-- Einsatz abschliessen (bonus = Abschluss-XP des Notfalltyps zusaetzlich)
local function completeEmergency(em, src, bonus)
    local data = emData(em)
    if bonus then exports.ws_core:AddXP(src or em.medic, data.xp, data.label) end
    exports.ws_core:AddStat(em.medic, 'emergencies', 1)
    if em.medic then TriggerClientEvent('ws_ems:ended', em.medic, em.uid, 'completed') end
    notify(em.medic, locale('emergency_done', data.label), 'success')
    Emergencies[em.uid] = nil
end

-- Patient eingeliefert (Event aus main.lua deliverPatient bzw. dem NPC-RTW).
-- Erst wenn ALLE Patienten der Szene versorgt sind, ist der Einsatz fertig.
AddEventHandler('ws_ems:patientDelivered', function(netId, src)
    for _, em in pairs(Emergencies) do
        if em.patients and em.patients[netId] then
            em.patients[netId] = nil
            em.delivered = (em.delivered or 0) + 1
            if em.expected and em.delivered >= em.expected then
                completeEmergency(em, src, true)
            else
                local remaining = (em.expected or (em.delivered + 1)) - em.delivered
                notify(src, locale('patient_delivered_more', math.max(1, remaining)), 'inform')
            end
            return
        end
    end
end)

local function cancel(em, reason)
    if em.medic then TriggerClientEvent('ws_ems:ended', em.medic, em.uid, reason) end
    Emergencies[em.uid] = nil
end

-- ---------------------------------------------------------------------------
-- Menschenrettung: handlungsunfaehiger Spieler (Meldung aus ws_core)
-- Laeuft bewusst durch dieselbe Kette wie ein NPC-Notruf: Angebot an alle
-- Sanitaeter -> Annahme mit Y -> Blip + Route -> Abschluss bei Wiederbelebung.
-- ---------------------------------------------------------------------------

local function findRescue(targetSrc)
    for _, em in pairs(Emergencies) do
        if em.rescueSrc == targetSrc then return em end
    end
end

local function rescueOffer(em)
    return {
        uid = em.uid, id = em.id,
        label = PLAYER_RESCUE.label, code = PLAYER_RESCUE.code, coords = em.coords,
    }
end

AddEventHandler('ws_core:downedStarted', function(targetSrc)
    if findRescue(targetSrc) then return end
    local ped = GetPlayerPed(targetSrc)
    if not ped or ped == 0 then return end
    local pos = GetEntityCoords(ped)

    nextUid = nextUid + 1
    local em = {
        uid = nextUid, id = PLAYER_RESCUE_ID,
        coords = vector4(pos.x, pos.y, pos.z, 0.0),
        state = 'offered', medic = nil, rescueSrc = targetSrc,
    }
    Emergencies[em.uid] = em

    -- Kein Verfall wie bei NPC-Notrufen: Das Angebot bleibt offen, solange der
    -- Spieler am Boden liegt - sonst verschwindet der Hilferuf nach 90s.
    for _, src in ipairs(emsOnDuty()) do
        if src ~= targetSrc then TriggerClientEvent('ws_ems:offer', src, rescueOffer(em)) end
    end
end)

AddEventHandler('ws_core:downedFinished', function(targetSrc, revived)
    local em = findRescue(targetSrc)
    if not em then return end
    local uid = em.uid

    if revived and em.medic then
        exports.ws_core:AddXP(em.medic, PLAYER_RESCUE.xp, PLAYER_RESCUE.label)
        exports.ws_core:AddStat(em.medic, 'emergencies', 1)
        TriggerClientEvent('ws_ems:ended', em.medic, uid, 'completed')
        notify(em.medic, locale('emergency_done', PLAYER_RESCUE.label), 'success')
        Emergencies[uid] = nil
    else
        cancel(em, revived and 'completed' or 'lost')
    end

    -- Offenes Angebot bei allen anderen zurueckziehen
    for _, src in ipairs(emsOnDuty()) do
        TriggerClientEvent('ws_ems:offerExpired', src, uid)
    end
end)

-- Patient bei der Reanimation verloren. Bei mehreren Patienten zaehlt nur
-- dieser als verloren; die uebrigen koennen den Einsatz noch abschliessen.
RegisterNetEvent('ws_ems:patientLost', function(netId)
    local src = source
    for _, em in pairs(Emergencies) do
        if em.patients and em.patients[netId] and em.medic == src then
            em.patients[netId] = nil
            em.expected = (em.expected or 1) - 1
            if em.expected <= (em.delivered or 0) then
                if (em.delivered or 0) > 0 then
                    completeEmergency(em, src, false) -- ohne Bonus (Patient verloren)
                else
                    notify(src, locale('emergency_lost'), 'error')
                    cancel(em, 'lost')
                end
            else
                notify(src, locale('patient_lost_one'), 'error')
            end
            return
        end
    end
end)

RegisterCommand('notfallabbruch', function(source)
    if source == 0 then return end
    local em = findAssignment(source)
    if em then cancel(em, 'cancelled') end
end, false)

-- Test-/Admin: /notfall [id]
RegisterCommand('notfall', function(source, args)
    local ok, err = createEmergency(args[1])
    local msg = ok and 'Notfall erstellt' or ('Fehler: ' .. tostring(err))
    if source == 0 then print('[ws_ems] ' .. msg) else notify(source, msg, ok and 'success' or 'error') end
end, true)

AddEventHandler('ws_core:dutyChanged', function(src, onDuty)
    if onDuty then
        -- Wer neu in den Dienst kommt, bekommt noch offene Hilferufe nachgereicht
        for _, em in pairs(Emergencies) do
            if em.id == PLAYER_RESCUE_ID and em.state == 'offered' and em.rescueSrc ~= src then
                TriggerClientEvent('ws_ems:offer', src, rescueOffer(em))
            end
        end
        return
    end
    local em = findAssignment(src)
    if em then cancel(em, 'cancelled') end
end)

AddEventHandler('playerDropped', function()
    local em = findAssignment(source)
    if em then cancel(em, 'cancelled') end
end)

-- Exports fuer das Tablet (gleiche Feldnamen wie ws_dispatch, damit die
-- Tablet-Oberflaeche unveraendert funktioniert)
exports('CreateEmergency', function(id)
    return createEmergency(id)
end)
exports('GetActiveEmergencies', function()
    local list = {}
    for uid, em in pairs(Emergencies) do
        local d = emData(em)
        list[#list + 1] = {
            uid = uid, id = em.id, label = d.label, code = d.code,
            state = em.state,
            officers = em.medic and 1 or 0,
            primary = em.medic and GetPlayerName(em.medic) or nil,
            arrests = 0,
        }
    end
    table.sort(list, function(a, b) return a.uid < b.uid end)
    return list
end)
exports('GetEmergencyTypes', function()
    local list = {}
    for id, d in pairs(WSEms.Emergencies) do
        list[#list + 1] = { id = id, label = d.label, code = d.code }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end)
exports('GetPlayerEmergencyUid', function(src)
    local em = findAssignment(src)
    return em and em.uid or nil
end)
exports('AbortEmergency', function(src)
    local em = findAssignment(src)
    if not em then return false end
    cancel(em, 'cancelled')
    return true
end)
