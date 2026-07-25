lib.locale()

---@class WSCallout
---@field uid number
---@field id string
---@field coords vector4
---@field state 'offered'|'active'
---@field primary number|nil
---@field assigned table<number, boolean>
---@field entities table<number, string> netId -> kind ('suspect'|'injured'|'wreck'|'prop')
---@field suspects table<number, {resolved: boolean}>
---@field arrests number

---@type table<number, WSCallout>
local Callouts = {}
local nextUid = 0
local lastCalloutAt = 0
local nextInterval = 0
local lastLocation = {} -- calloutId -> zuletzt genutzter Orts-Index

local function notify(src, description, ntype, title)
    TriggerClientEvent('ox_lib:notify', src, {
        title = title or locale('dispatch_title'),
        description = description,
        type = ntype or 'inform',
    })
end

local function onDutyOfficers()
    return exports.ws_core:GetOnDutyPlayers('police')
end

local function countActive()
    -- Externe Faelle (Verkehrskontrollen) zaehlen nicht gegen das
    -- Auto-Callout-Limit, damit weiterhin normale Einsaetze generiert werden
    local n = 0
    for _, co in pairs(Callouts) do
        if not co.external then n = n + 1 end
    end
    return n
end

local function findAssignment(src)
    for _, co in pairs(Callouts) do
        if co.assigned[src] then return co end
    end
    return nil
end

local function cleanupCallout(co, reason)
    for netId in pairs(co.entities) do
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent and ent ~= 0 and DoesEntityExist(ent) then
            DeleteEntity(ent)
        end
    end
    for src in pairs(co.assigned) do
        TriggerClientEvent('ws_dispatch:ended', src, co.uid, reason)
    end
    Callouts[co.uid] = nil
end

-- Externe Faelle (Verkehrskontrolle) haben keinen "complete"-Abschluss - sobald
-- ihr einziger Verdaechtiger eingeliefert/transportiert ist, Fall aufraeumen
local function maybeCloseExternal(co)
    if not co or not co.external then return end
    for _, s in pairs(co.suspects) do
        if not s.resolved then return end
    end
    cleanupCallout(co, 'completed')
end

local function createCallout(calloutId)
    local officers = onDutyOfficers()
    if #officers == 0 then return false, 'keine Officer im Dienst' end

    local data = calloutId and CalloutData[calloutId]
    if calloutId and not data then return false, ('unbekannter Callout: %s'):format(calloutId) end

    if not data then
        local ids = {}
        for id in pairs(CalloutData) do ids[#ids + 1] = id end
        calloutId = ids[math.random(#ids)]
        data = CalloutData[calloutId]
    end

    -- Nicht zweimal hintereinander derselbe Ort
    local locIndex = math.random(#data.locations)
    if #data.locations > 1 and locIndex == lastLocation[calloutId] then
        locIndex = (locIndex % #data.locations) + 1
    end
    lastLocation[calloutId] = locIndex

    nextUid = nextUid + 1
    local co = {
        uid = nextUid,
        id = calloutId,
        coords = data.locations[locIndex],
        state = 'offered',
        primary = nil,
        assigned = {},
        entities = {},
        suspects = {},
        arrests = 0,
    }
    Callouts[co.uid] = co

    local offer = { uid = co.uid, id = co.id, label = data.label, code = data.code, coords = co.coords }
    for _, src in ipairs(officers) do
        TriggerClientEvent('ws_dispatch:offer', src, offer)
    end

    SetTimeout(WSDispatch.AcceptTimeout * 1000, function()
        local c = Callouts[co.uid]
        if c and c.state == 'offered' then
            Callouts[co.uid] = nil
            for _, src in ipairs(onDutyOfficers()) do
                TriggerClientEvent('ws_dispatch:offerExpired', src, co.uid)
            end
        end
    end)

    return true
end

-- Automatische Einsatzgenerierung
CreateThread(function()
    nextInterval = math.random(WSDispatch.IntervalMin, WSDispatch.IntervalMax)
    while true do
        Wait(10000)
        local officers = onDutyOfficers()
        if #officers > 0 then
            local maxConcurrent = math.max(1, math.floor(#officers / WSDispatch.OfficersPerCallout))
            local now = os.time()
            if countActive() < maxConcurrent and (now - lastCalloutAt) >= nextInterval then
                if createCallout() then
                    lastCalloutAt = now
                    nextInterval = math.random(WSDispatch.IntervalMin, WSDispatch.IntervalMax)
                end
            end
        end
    end
end)

RegisterNetEvent('ws_dispatch:accept', function(uid)
    local src = source
    local co = Callouts[uid]
    if not co then
        return notify(src, locale('offer_gone'), 'error')
    end
    if not exports.ws_core:IsOnDuty(src) then return end
    if findAssignment(src) then
        return notify(src, locale('already_assigned'), 'error')
    end

    local isPrimary = false
    if co.state == 'offered' then
        co.state = 'active'
        co.primary = src
        isPrimary = true
        for _, o in ipairs(onDutyOfficers()) do
            if o ~= src then
                TriggerClientEvent('ws_dispatch:offerTaken', o, uid, GetPlayerName(src))
            end
        end
    end

    co.assigned[src] = true
    local data = CalloutData[co.id]
    TriggerClientEvent('ws_dispatch:assigned', src,
        { uid = co.uid, id = co.id, label = data.label, code = data.code, coords = co.coords }, isPrimary)
end)

-- Primary registriert gespawnte Entities (fuer Statebags + Server-Cleanup)
RegisterNetEvent('ws_dispatch:registerEntity', function(uid, netId, kind)
    local src = source
    local co = Callouts[uid]
    if not co or co.primary ~= src then return end

    -- Frisch gespawnte Entities brauchen einen Moment, bis sie server-seitig existieren
    local ent = NetworkGetEntityFromNetworkId(netId)
    local tries = 0
    while (not ent or ent == 0 or not DoesEntityExist(ent)) and tries < 40 do
        Wait(50)
        tries = tries + 1
        ent = NetworkGetEntityFromNetworkId(netId)
    end
    if not ent or ent == 0 or not DoesEntityExist(ent) then
        print(('[ws_dispatch] Entity %d (Callout #%d, %s) konnte nicht registriert werden!'):format(netId, uid, kind))
        return
    end

    co.entities[netId] = kind
    local st = Entity(ent).state
    st:set('ws:callout', uid, true)
    if kind == 'suspect' then
        st:set('ws:suspect', true, true)
        co.suspects[netId] = { resolved = false }
    elseif kind == 'injured' then
        st:set('ws:injured', true, true)
    elseif kind == 'wreck' then
        st:set('ws:wreck', true, true)
    end
end)

-- Zustandsaenderungen an Verdaechtigen (kapituliert/gefesselt) laufen ueber den
-- Server, damit die Statebags fuer alle Clients repliziert werden
local allowedKeys = { surrendered = true, cuffed = true }
RegisterNetEvent('ws_dispatch:updateSuspect', function(netId, key, value)
    local src = source
    if not allowedKeys[key] then return end

    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end

    local uid = Entity(ent).state['ws:callout']
    local co = uid and Callouts[uid]
    if not co or not co.assigned[src] then return end

    Entity(ent).state:set('ws:' .. key, value == true, true)
end)

RegisterNetEvent('ws_dispatch:deliverSuspect', function(netId)
    local src = source
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end

    local st = Entity(ent).state
    local uid = st['ws:callout']
    local co = uid and Callouts[uid]
    if not co or not co.assigned[src] or not st['ws:cuffed'] then return end

    local suspect = co.suspects[netId]
    if not suspect or suspect.resolved then return end

    local dropoff = WSDispatch.JailDropoff
    local dist = #(GetEntityCoords(ent) - vector3(dropoff.x, dropoff.y, dropoff.z))
    if dist > WSDispatch.DeliverRadius + 5.0 then return end

    suspect.resolved = true
    co.arrests = co.arrests + 1
    co.entities[netId] = nil
    DeleteEntity(ent)

    exports.ws_core:AddXP(src, WSDispatch.ArrestXP, locale('xp_arrest'))
    exports.ws_core:AddStat(src, 'arrests', 1)
    for officer in pairs(co.assigned) do
        notify(officer, locale('suspect_delivered'), 'success')
    end
    if co.primary then
        TriggerClientEvent('ws_dispatch:suspectResolved', co.primary, uid, netId)
    end
    maybeCloseExternal(co)
end)

-- Diagnose: Primary meldet, dass die Szene aufgebaut wurde (sichtbar in txAdmin-Konsole)
RegisterNetEvent('ws_dispatch:sceneReady', function(uid)
    local src = source
    local co = Callouts[uid]
    if not co or co.primary ~= src then return end
    print(('[ws_dispatch] Szene aufgebaut: Callout #%d (%s) durch %s'):format(uid, co.id, GetPlayerName(src)))
end)

-- Durchsuchung eines gestellten/festgenommenen Verdaechtigen: einmalig,
-- server-seitig ausgewuerfelt (Anti-Cheat), Fundstueck bringt XP
lib.callback.register('ws_dispatch:searchSuspect', function(src, netId)
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return false end

    local st = Entity(ent).state
    local uid = st['ws:callout']
    local co = uid and Callouts[uid]
    if not co or not co.assigned[src] then return false end
    if not (st['ws:cuffed'] or st['ws:surrendered']) then return false end

    local suspect = co.suspects[netId]
    if not suspect then return false end
    if suspect.searched then return { already = true } end
    suspect.searched = true

    local roll = math.random(100)
    local acc = 0
    for _, find in ipairs(WSDispatch.SearchFinds) do
        acc = acc + find.chance
        if roll <= acc then
            exports.ws_core:AddXP(src, find.xp, locale('xp_search'))
            return { item = locale(find.item), xp = find.xp }
        end
    end
    return { nothing = true }
end)

-- Uebergabe an den Gefangenentransport: zaehlt als Festnahme, gibt aber
-- weniger XP als die Eigenlieferung zur Wache. Die Entity wird vom
-- Transport-System (client/transport.lua) abtransportiert und entfernt.
RegisterNetEvent('ws_dispatch:transportSuspect', function(netId)
    local src = source
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end

    local st = Entity(ent).state
    local uid = st['ws:callout']
    local co = uid and Callouts[uid]
    if not co or not co.assigned[src] or not st['ws:cuffed'] then return end

    local suspect = co.suspects[netId]
    if not suspect or suspect.resolved then return end

    suspect.resolved = true
    co.arrests = co.arrests + 1
    co.entities[netId] = nil

    exports.ws_core:AddXP(src, WSDispatch.TransportXP, locale('xp_transport'))
    exports.ws_core:AddStat(src, 'arrests', 1)
    for officer in pairs(co.assigned) do
        notify(officer, locale('suspect_transported'), 'success')
    end
    if co.primary then
        TriggerClientEvent('ws_dispatch:suspectResolved', co.primary, uid, netId)
    end
    maybeCloseExternal(co)
end)

-- Verdaechtiger tot oder despawned (nur Primary meldet)
RegisterNetEvent('ws_dispatch:suspectDown', function(uid, netId)
    local src = source
    local co = Callouts[uid]
    if not co or co.primary ~= src then return end
    local suspect = co.suspects[netId]
    if suspect then suspect.resolved = true end
end)

-- Nebenziele: Verletzte versorgt / Wrack abgeschleppt
RegisterNetEvent('ws_dispatch:objectiveDone', function(netId)
    local src = source
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then
        print(('[ws_dispatch] objectiveDone abgelehnt: Entity %s existiert nicht (von %s)'):format(netId, GetPlayerName(src) or src))
        return
    end

    local st = Entity(ent).state
    local uid = st['ws:callout']
    local co = uid and Callouts[uid]
    if not co or not co.assigned[src] then
        print(('[ws_dispatch] objectiveDone abgelehnt: kein zugewiesener Callout (Entity %s, uid=%s, von %s)'):format(netId, tostring(uid), GetPlayerName(src) or src))
        return
    end

    local kind = co.entities[netId]
    -- Fallback: Statebags sind fuehrend, falls die Entity-Verwaltung das
    -- Ziel verloren hat (sonst muss der Spieler die Aktion wiederholen)
    if kind ~= 'wreck' and kind ~= 'injured' then
        if st['ws:injured'] == true then
            kind = 'injured'
            print(('[ws_dispatch] objectiveDone: Entity %s ueber Statebag als "injured" aufgeloest'):format(netId))
        elseif st['ws:wreck'] == true then
            kind = 'wreck'
            print(('[ws_dispatch] objectiveDone: Entity %s ueber Statebag als "wreck" aufgeloest'):format(netId))
        end
    end

    if kind == 'wreck' then
        -- Wrack wird vom Abschleppwagen (ws_police/towing) abtransportiert
        -- und dort geloescht - hier nur aus der Verwaltung nehmen
        co.entities[netId] = nil
    elseif kind == 'injured' then
        st:set('ws:injured', false, true)
        co.entities[netId] = 'prop' -- versorgt: zaehlt nicht mehr als offenes Ziel
    else
        return
    end

    -- Fortschritt an alle Beteiligten melden
    local remaining = 0
    for _, k in pairs(co.entities) do
        if k == 'wreck' or k == 'injured' then remaining = remaining + 1 end
    end
    for officer in pairs(co.assigned) do
        notify(officer, remaining > 0
            and locale('objective_done_remaining', remaining)
            or locale('objective_done'), 'success')
    end

    if co.primary then
        TriggerClientEvent('ws_dispatch:objectiveResolved', co.primary, uid, netId, kind)
    end
end)

RegisterNetEvent('ws_dispatch:complete', function(uid)
    local src = source
    local co = Callouts[uid]
    if not co or co.primary ~= src then return end

    local data = CalloutData[co.id]

    -- Festnahmen zahlen sich aus: volle XP nur bei voller Festnahmequote
    local totalSuspects = 0
    for _ in pairs(co.suspects) do totalSuspects = totalSuspects + 1 end
    local xp = data.xp
    local reduced = false
    if totalSuspects > 0 and co.arrests < totalSuspects then
        local factor = WSDispatch.MinXPFactor + (1.0 - WSDispatch.MinXPFactor) * (co.arrests / totalSuspects)
        xp = math.floor(data.xp * factor + 0.5)
        reduced = true
    end

    for officer in pairs(co.assigned) do
        exports.ws_core:AddXP(officer, xp, data.label)
        exports.ws_core:AddStat(officer, 'callouts', 1)
        notify(officer, reduced
            and locale('callout_completed_reduced', data.label)
            or locale('callout_completed', data.label), 'success')
    end
    cleanupCallout(co, 'completed')
end)

-- Einsatz verlassen bzw. (als Einsatzleiter) abbrechen
local function abortAssignment(src)
    local co = findAssignment(src)
    if not co then
        notify(src, locale('no_assignment'), 'error')
        return false
    end
    if co.primary ~= src then
        co.assigned[src] = nil
        TriggerClientEvent('ws_dispatch:ended', src, co.uid, 'left')
        return true
    end
    for officer in pairs(co.assigned) do
        notify(officer, locale('callout_cancelled'), 'error')
    end
    cleanupCallout(co, 'cancelled')
    return true
end

RegisterCommand('abbrechen', function(source)
    if source == 0 then return end
    abortAssignment(source)
end, false)

-- Tod beendet den Einsatz: Einsatzleiter tot -> Abbruch fuer alle,
-- Unterstuetzer tot -> nur aus dem Einsatz entfernt
local function onOfficerDown(src)
    local co = findAssignment(src)
    if not co then return end
    if co.primary == src then
        for officer in pairs(co.assigned) do
            notify(officer, locale('callout_officer_down'), 'error')
        end
        cleanupCallout(co, 'cancelled')
    else
        co.assigned[src] = nil
        TriggerClientEvent('ws_dispatch:ended', src, co.uid, 'left')
    end
end

RegisterNetEvent('baseevents:onPlayerDied', function()
    onOfficerDown(source)
end)
RegisterNetEvent('baseevents:onPlayerKilled', function()
    onOfficerDown(source)
end)

-- Test-/Admin-Kommando: /callout [id] erzwingt einen Einsatz (Konsole oder ACE)
RegisterCommand('callout', function(source, args)
    local ok, err = createCallout(args[1])
    local msg = ok and 'Callout erstellt' or ('Fehler: ' .. tostring(err))
    if source == 0 then
        print('[ws_dispatch] ' .. msg)
    else
        notify(source, msg, ok and 'success' or 'error')
    end
end, true)

AddEventHandler('ws_core:dutyChanged', function(src, onDuty)
    if onDuty then return end
    local co = findAssignment(src)
    if not co then return end
    if co.primary == src then
        for officer in pairs(co.assigned) do
            if officer ~= src then notify(officer, locale('callout_cancelled'), 'error') end
        end
        cleanupCallout(co, 'cancelled')
    else
        co.assigned[src] = nil
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local co = findAssignment(src)
    if not co then return end
    if co.primary == src then
        for officer in pairs(co.assigned) do
            if officer ~= src then notify(officer, locale('callout_cancelled'), 'error') end
        end
        cleanupCallout(co, 'cancelled')
    else
        co.assigned[src] = nil
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= cache.resource then return end
    for _, co in pairs(Callouts) do
        cleanupCallout(co, 'cancelled')
    end
end)

-- Exports fuer ws_tablet
exports('CreateCallout', function(calloutId)
    return createCallout(calloutId)
end)
exports('GetActiveCallouts', function()
    local list = {}
    for uid, co in pairs(Callouts) do
        -- Externe Faelle (Verkehrskontrolle) haben keinen CalloutData-Eintrag
        local data = CalloutData[co.id]
        local officers = 0
        for _ in pairs(co.assigned) do officers = officers + 1 end
        list[#list + 1] = {
            uid = uid,
            id = co.id,
            label = co.label or (data and data.label) or co.id,
            code = co.code or (data and data.code) or '',
            state = co.state,
            officers = officers,
            primary = co.primary and GetPlayerName(co.primary) or nil,
            arrests = co.arrests,
        }
    end
    table.sort(list, function(a, b) return a.uid < b.uid end)
    return list
end)
exports('GetCalloutTypes', function()
    local list = {}
    for id, d in pairs(CalloutData) do
        list[#list + 1] = { id = id, label = d.label, code = d.code }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end)
exports('GetPlayerCalloutUid', function(src)
    local co = findAssignment(src)
    return co and co.uid or nil
end)
exports('AbortAssignment', abortAssignment)

-- Externe Festnahme (z.B. Verkehrskontrolle): legt einen leichten Ein-
-- Verdaechtigen-Fall an, damit der komplette bestehende Ablauf (fesseln,
-- eskortieren, ins Auto, einliefern / transportieren, durchsuchen) greift.
-- Der Verdaechtige wird direkt als "kapituliert" markiert (kooperativ).
exports('RegisterExternalSuspect', function(officer, netId, opts)
    opts = opts or {}
    if not exports.ws_core:IsOnDuty(officer) then return nil end

    local ent = NetworkGetEntityFromNetworkId(netId)
    local tries = 0
    while (not ent or ent == 0 or not DoesEntityExist(ent)) and tries < 40 do
        Wait(50)
        tries = tries + 1
        ent = NetworkGetEntityFromNetworkId(netId)
    end
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end

    -- Bereits als Verdaechtiger erfasst? (Doppelregistrierung vermeiden)
    if Entity(ent).state['ws:callout'] then return Entity(ent).state['ws:callout'] end

    nextUid = nextUid + 1
    local co = {
        uid = nextUid,
        id = opts.id or 'traffic',
        label = opts.label or locale('ext_case_label'),
        code = opts.code or 'Code 1',
        external = true,
        state = 'active',
        primary = officer,
        assigned = { [officer] = true },
        entities = { [netId] = 'suspect' },
        suspects = { [netId] = { resolved = false } },
        arrests = 0,
    }
    Callouts[co.uid] = co

    local st = Entity(ent).state
    st:set('ws:callout', co.uid, true)
    st:set('ws:suspect', true, true)
    st:set('ws:surrendered', true, true)
    return co.uid
end)
