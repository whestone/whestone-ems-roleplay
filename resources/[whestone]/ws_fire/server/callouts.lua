lib.locale()

-- Feuerwehr-Einsatz-Engine: generiert Braende fuer Feuerwehrleute im Dienst,
-- verwaltet Angebot/Annahme und schliesst ab, wenn alle Brandherde aus sind.

local Fires = {}
local nextUid = 0
local lastAt = 0
local nextInterval = 0

local function crewOnDuty()
    return exports.ws_core:GetOnDutyPlayers('fire')
end

local function notify(src, description, ntype)
    TriggerClientEvent('ox_lib:notify', src, {
        title = locale('dispatch_title'), description = description, type = ntype or 'inform',
    })
end

local function countActive()
    local n = 0
    for _ in pairs(Fires) do n = n + 1 end
    return n
end

local function findAssignment(src)
    for _, f in pairs(Fires) do
        if f.crew == src then return f end
    end
end

local function createFire(id)
    local crew = crewOnDuty()
    if #crew == 0 then return false, 'keine Feuerwehr im Dienst' end

    local data = id and WSFire.Fires[id]
    if id and not data then return false, ('unbekannter Brand: %s'):format(id) end
    if not data then
        local ids = {}
        for k in pairs(WSFire.Fires) do ids[#ids + 1] = k end
        id = ids[math.random(#ids)]
        data = WSFire.Fires[id]
    end

    nextUid = nextUid + 1
    local f = {
        uid = nextUid, id = id,
        coords = data.locations[math.random(#data.locations)],
        state = 'offered', crew = nil, pending = 0, spawnDone = false,
    }
    Fires[f.uid] = f

    local offer = { uid = f.uid, id = id, label = data.label, code = data.code, coords = f.coords }
    for _, src in ipairs(crew) do TriggerClientEvent('ws_fire:offer', src, offer) end

    SetTimeout(WSFire.Callout.acceptTimeout * 1000, function()
        local e = Fires[f.uid]
        if e and e.state == 'offered' then
            Fires[f.uid] = nil
            for _, src in ipairs(crewOnDuty()) do TriggerClientEvent('ws_fire:offerExpired', src, f.uid) end
        end
    end)
    return true
end

CreateThread(function()
    nextInterval = math.random(WSFire.Callout.intervalMin, WSFire.Callout.intervalMax)
    while true do
        Wait(10000)
        local crew = crewOnDuty()
        if #crew > 0 then
            local maxC = math.max(1, math.floor(#crew / WSFire.Callout.perCallout))
            local now = os.time()
            if countActive() < maxC and (now - lastAt) >= nextInterval then
                if createFire() then
                    lastAt = now
                    nextInterval = math.random(WSFire.Callout.intervalMin, WSFire.Callout.intervalMax)
                end
            end
        end
    end
end)

RegisterNetEvent('ws_fire:accept', function(uid)
    local src = source
    local f = Fires[uid]
    if not f then return notify(src, locale('offer_gone'), 'error') end
    if exports.ws_core:GetJob(src) ~= 'fire' or not exports.ws_core:IsOnDuty(src) then return end
    if f.state ~= 'offered' then return notify(src, locale('offer_taken_short'), 'error') end
    if findAssignment(src) then return notify(src, locale('already_assigned'), 'error') end

    f.state = 'active'
    f.crew = src
    local data = WSFire.Fires[f.id]
    TriggerClientEvent('ws_fire:assigned', src, {
        uid = f.uid, id = f.id, label = data.label, code = data.code, coords = f.coords,
    })
    for _, o in ipairs(crewOnDuty()) do
        if o ~= src then TriggerClientEvent('ws_fire:offerTaken', o, uid, GetPlayerName(src)) end
    end
end)

-- Client meldet die Gesamtzahl der Brandherde der Szene
RegisterNetEvent('ws_fire:sceneSpawned', function(uid, count)
    local src = source
    local f = Fires[uid]
    if not f or f.crew ~= src then return end
    f.pending = math.max(1, tonumber(count) or 1)
    f.spawnDone = true
end)

local function completeFire(f, src)
    local data = WSFire.Fires[f.id]
    exports.ws_core:AddXP(src or f.crew, WSFire.XP.complete, data.label)
    exports.ws_core:AddStat(f.crew, 'fires', 1)
    if f.crew then TriggerClientEvent('ws_fire:ended', f.crew, f.uid, 'completed') end
    notify(f.crew, locale('fire_done', data.label), 'success')
    Fires[f.uid] = nil
end

-- Ein Brandherd wurde geloescht (Meldung vom Client)
RegisterNetEvent('ws_fire:pointExtinguished', function(uid)
    local src = source
    local f = Fires[uid]
    if not f or f.crew ~= src then return end
    exports.ws_core:AddXP(src, WSFire.XP.extinguish, locale('xp_extinguish'))
    f.pending = math.max(0, (f.pending or 1) - 1)
    if f.spawnDone and f.pending <= 0 then
        completeFire(f, src)
    else
        notify(src, locale('point_out_more', math.max(0, f.pending)), 'inform')
    end
end)

local function cancel(f, reason)
    if f.crew then TriggerClientEvent('ws_fire:ended', f.crew, f.uid, reason) end
    Fires[f.uid] = nil
end

RegisterCommand('brandabbruch', function(source)
    if source == 0 then return end
    local f = findAssignment(source)
    if f then cancel(f, 'cancelled') end
end, false)

RegisterCommand('brand', function(source, args)
    local ok, err = createFire(args[1])
    local msg = ok and 'Brand erstellt' or ('Fehler: ' .. tostring(err))
    if source == 0 then print('[ws_fire] ' .. msg) else notify(source, msg, ok and 'success' or 'error') end
end, true)

AddEventHandler('ws_core:dutyChanged', function(src, onDuty)
    if onDuty then return end
    local f = findAssignment(src)
    if f then cancel(f, 'cancelled') end
end)

AddEventHandler('playerDropped', function()
    local f = findAssignment(source)
    if f then cancel(f, 'cancelled') end
end)

-- Exports fuer das Tablet (gleiche Feldnamen wie ws_ems/ws_dispatch,
-- damit die Tablet-Oberflaeche unveraendert funktioniert)
exports('CreateFire', function(id)
    return createFire(id)
end)
exports('GetActiveFires', function()
    local list = {}
    for uid, f in pairs(Fires) do
        local d = WSFire.Fires[f.id]
        list[#list + 1] = {
            uid = uid, id = f.id, label = d.label, code = d.code,
            state = f.state,
            officers = f.crew and 1 or 0,
            primary = f.crew and GetPlayerName(f.crew) or nil,
            arrests = 0,
        }
    end
    table.sort(list, function(a, b) return a.uid < b.uid end)
    return list
end)
exports('GetFireTypes', function()
    local list = {}
    for id, d in pairs(WSFire.Fires) do
        list[#list + 1] = { id = id, label = d.label, code = d.code }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end)
exports('GetPlayerFireUid', function(src)
    local f = findAssignment(src)
    return f and f.uid or nil
end)
exports('AbortFire', function(src)
    local f = findAssignment(src)
    if not f then return false end
    cancel(f, 'cancelled')
    return true
end)
