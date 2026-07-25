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

local function startScene(callout)
    local ctx = { uid = callout.uid, stopped = false }
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
        local c = callout.coords
        local hash = joaat(d.peds[math.random(#d.peds)])
        lib.requestModel(hash, 10000)
        local ped = CreatePed(4, hash, c.x, c.y, c.z, c.w or 0.0, true, true)
        SetModelAsNoLongerNeeded(hash)
        SetEntityAsMissionEntity(ped, true, true)
        SetEntityHealth(ped, 150)
        forceDownAnim(ped)
        ctx.patient = ped

        local netId = NetworkGetNetworkIdFromEntity(ped)
        SetNetworkIdCanMigrate(netId, true)
        TriggerServerEvent('ws_ems:registerPatient', callout.uid, netId)

        if d.wreck then
            local wh = joaat('blista')
            lib.requestModel(wh, 8000)
            local wveh = CreateVehicle(wh, c.x + 3.0, c.y + 2.0, c.z, (c.w + 40.0) % 360.0, true, true)
            SetModelAsNoLongerNeeded(wh)
            SetEntityAsMissionEntity(wveh, true, true)
            SetVehicleTyreBurst(wveh, 0, true, 1000.0)
            SmashVehicleWindow(wveh, 0)
            SetVehicleEngineOn(wveh, false, true, true)
            SetVehicleDoorOpen(wveh, 0, false, false)
            ctx.wreck = wveh
        end

        enotify('scene_ready', 'inform')

        -- Patient in Down-Pose halten, bis stabilisiert (oder verstorben)
        while not ctx.stopped do
            Wait(1000)
            if not DoesEntityExist(ped) or IsEntityDead(ped) then break end
            if Entity(ped).state['ws:patient_state'] == 'stable' then break end
            if NetworkHasControlOfEntity(ped) and not IsEntityPlayingAnim(ped, 'dead', 'dead_a', 3) then
                forceDownAnim(ped)
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
        -- Bei Abbruch (nicht abgeschlossen) den nicht eingelieferten Patienten entfernen
        if reason ~= 'completed' and activeScene.patient and DoesEntityExist(activeScene.patient) then
            DeleteEntity(activeScene.patient)
        end
        if activeScene.wreck and DoesEntityExist(activeScene.wreck) then
            DeleteEntity(activeScene.wreck)
        end
        activeScene = nil
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= cache.resource then return end
    if activeScene then
        if activeScene.patient and DoesEntityExist(activeScene.patient) then DeleteEntity(activeScene.patient) end
        if activeScene.wreck and DoesEntityExist(activeScene.wreck) then DeleteEntity(activeScene.wreck) end
    end
end)
