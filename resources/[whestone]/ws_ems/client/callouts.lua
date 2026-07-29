lib.locale()

local currentAssignment
local currentBlip
local lastOffer
local activeScene

local function isEmsOnDuty()
    return LocalPlayer.state['ws:job'] == 'ambulance' and LocalPlayer.state['ws:duty'] == true
end

local function removeBlip()
    if currentBlip then RemoveBlip(currentBlip) currentBlip = nil end
end

local function enotify(key, ntype, ...)
    lib.notify({ title = locale('med_title'), description = locale(key, ...), type = ntype or 'inform' })
end

-- ---------------------------------------------------------------------------
-- Angebote
-- ---------------------------------------------------------------------------

RegisterNetEvent('ws_ems:offer', function(offer)
    lastOffer = offer
    local street = GetStreetNameFromHashKey(GetStreetNameAtCoord(offer.coords.x, offer.coords.y, offer.coords.z))
    lib.notify({
        id = 'ws_ems_offer',
        title = ('%s – %s'):format(offer.code, offer.label),
        description = locale('offer_desc', street),
        type = 'warning', icon = 'truck-medical', duration = 15000,
    })
    PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', false)
end)

RegisterNetEvent('ws_ems:offerTaken', function(uid, byName)
    if lastOffer and lastOffer.uid == uid then
        enotify('offer_taken', 'inform', byName)
    end
end)

RegisterNetEvent('ws_ems:offerExpired', function(uid)
    if lastOffer and lastOffer.uid == uid then
        lastOffer = nil
        enotify('offer_expired', 'error')
    end
end)

-- Gleiche Taste wie bei der Polizei (Y): beide Commands liegen auf Y,
-- durch die Job-Pruefung reagiert immer nur das passende System
RegisterCommand('notfall_annehmen', function()
    if not isEmsOnDuty() then return end
    if not lastOffer then return enotify('no_offer', 'error') end
    TriggerServerEvent('ws_ems:accept', lastOffer.uid)
end, false)
-- 'Z' = physische US-Taste, liegt auf deutschem QWERTZ-Layout auf der Y-Taste
RegisterKeyMapping('notfall_annehmen', 'Rettungsdienst: Notfall annehmen', 'keyboard', 'Z')

-- ---------------------------------------------------------------------------
-- Szenario
-- ---------------------------------------------------------------------------

local function forceDownAnim(ped)
    lib.requestAnimDict('dead')
    TaskPlayAnim(ped, 'dead', 'dead_a', 8.0, -8.0, -1, 1, 0.0, false, false, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
end

-- Verteil-Offsets fuer mehrere Verletzte rund um den Einsatzort
local PATIENT_SPOTS = { { 0.0, 0.0 }, { 6.0, 2.5 }, { -5.0, 4.5 } }

local function spawnAccidentPatient(ctx, callout, d, i)
    local c = callout.coords
    local spot = PATIENT_SPOTS[i] or { math.random(-6, 6) * 1.0, math.random(-6, 6) * 1.0 }
    local sx, sy = c.x + spot[1], c.y + spot[2]
    local heading = ((c.w or 0.0) + (i - 1) * 55.0) % 360.0

    local hash = joaat(d.peds[math.random(#d.peds)])
    lib.requestModel(hash, 10000)
    local ped = CreatePed(4, hash, sx, sy, c.z, heading, true, true)
    SetModelAsNoLongerNeeded(hash)
    SetEntityAsMissionEntity(ped, true, true)
    SetEntityHealth(ped, 150)
    forceDownAnim(ped)
    ctx.patients[#ctx.patients + 1] = ped

    local netId = NetworkGetNetworkIdFromEntity(ped)
    SetNetworkIdCanMigrate(netId, true)
    TriggerServerEvent('ws_ems:registerPatient', callout.uid, netId)

    if d.wreck then
        local wh = joaat('blista')
        lib.requestModel(wh, 8000)
        local wveh = CreateVehicle(wh, sx + 3.0, sy + 2.0, c.z, (heading + 40.0) % 360.0, true, true)
        SetModelAsNoLongerNeeded(wh)
        SetEntityAsMissionEntity(wveh, true, true)
        SetVehicleTyreBurst(wveh, 0, true, 1000.0)
        SmashVehicleWindow(wveh, 0)
        SetVehicleEngineOn(wveh, false, true, true)
        SetVehicleDoorOpen(wveh, 0, false, false)
        ctx.wrecks[#ctx.wrecks + 1] = wveh
    end
end

local function startScene(callout)
    local ctx = { uid = callout.uid, stopped = false, patients = {}, wrecks = {} }
    activeScene = ctx

    CreateThread(function()
        -- Szene erst aufbauen, wenn der Sanitaeter sich naehert
        while not ctx.stopped do
            local dist = #(GetEntityCoords(cache.ped) - vector3(callout.coords.x, callout.coords.y, callout.coords.z))
            if dist < WSEms.Callout.spawnDistance then break end
            Wait(1000)
        end
        if ctx.stopped then return end

        local d = WSEms.Emergencies[callout.id]

        -- Anzahl Verletzter: Standard 1; Verkehrsunfaelle zufaellig bis maxPatients
        local count = 1
        if d.maxPatients and d.maxPatients > 1 then count = math.random(1, d.maxPatients) end

        for i = 1, count do
            if ctx.stopped then return end
            spawnAccidentPatient(ctx, callout, d, i)
        end
        -- erst NACH dem Spawnen melden: jetzt sind alle Patienten registriert
        TriggerServerEvent('ws_ems:sceneSpawned', callout.uid)

        enotify('scene_ready', 'inform')

        -- Alle noch nicht stabilisierten Patienten in Down-Pose halten
        while not ctx.stopped do
            Wait(1000)
            for _, ped in ipairs(ctx.patients) do
                if DoesEntityExist(ped) and not IsEntityDead(ped)
                    and Entity(ped).state['ws:patient_state'] ~= 'stable'
                    and NetworkHasControlOfEntity(ped)
                    and not IsEntityPlayingAnim(ped, 'dead', 'dead_a', 3) then
                    forceDownAnim(ped)
                end
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Zuweisung / Abschluss
-- ---------------------------------------------------------------------------

RegisterNetEvent('ws_ems:assigned', function(callout)
    currentAssignment = callout
    if lastOffer and lastOffer.uid == callout.uid then lastOffer = nil end

    removeBlip()
    currentBlip = AddBlipForCoord(callout.coords.x, callout.coords.y, callout.coords.z)
    SetBlipSprite(currentBlip, 1) -- runder Punkt wie beim LSPD-Einsatz
    SetBlipColour(currentBlip, 1) -- rot
    SetBlipScale(currentBlip, 1.0)
    SetBlipRoute(currentBlip, true)
    SetBlipRouteColour(currentBlip, 1)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(('%s – %s'):format(callout.code, callout.label))
    EndTextCommandSetBlipName(currentBlip)

    enotify('assigned_msg', 'success', callout.label)
    -- Menschenrettung: der Patient ist ein echter Spieler, es wird also
    -- keine Szene gespawnt - nur Blip und Route zum Fundort.
    if callout.id ~= 'player_rescue' then
        startScene(callout)
    end
end)

RegisterNetEvent('ws_ems:ended', function(uid, reason)
    if currentAssignment and currentAssignment.uid == uid then
        currentAssignment = nil
        removeBlip()
    end
    if activeScene and activeScene.uid == uid then
        activeScene.stopped = true
        -- Bei Abbruch (nicht abgeschlossen) noch nicht eingelieferte Patienten entfernen
        if reason ~= 'completed' then
            for _, ped in ipairs(activeScene.patients or {}) do
                if DoesEntityExist(ped) then DeleteEntity(ped) end
            end
        end
        for _, wveh in ipairs(activeScene.wrecks or {}) do
            if DoesEntityExist(wveh) then DeleteEntity(wveh) end
        end
        activeScene = nil
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= cache.resource then return end
    if activeScene then
        for _, ped in ipairs(activeScene.patients or {}) do
            if DoesEntityExist(ped) then DeleteEntity(ped) end
        end
        for _, wveh in ipairs(activeScene.wrecks or {}) do
            if DoesEntityExist(wveh) then DeleteEntity(wveh) end
        end
    end
end)
