lib.locale()

local currentAssignment ---@type table|nil
local currentBlip
local lastOffer ---@type table|nil
local escortedPed

local dropoff = WSDispatch.JailDropoff
local dropoffCoords = vector3(dropoff.x, dropoff.y, dropoff.z)

local function removeAssignmentBlip()
    if currentBlip then
        RemoveBlip(currentBlip)
        currentBlip = nil
    end
end

-- ---------------------------------------------------------------------------
-- Einsatz-Angebote
-- ---------------------------------------------------------------------------

RegisterNetEvent('ws_dispatch:offer', function(offer)
    lastOffer = offer
    local streetHash = GetStreetNameAtCoord(offer.coords.x, offer.coords.y, offer.coords.z)
    local street = GetStreetNameFromHashKey(streetHash)
    lib.notify({
        id = 'ws_offer',
        title = ('%s – %s'):format(offer.code, offer.label),
        description = locale('offer_desc', street),
        type = 'warning',
        icon = 'bell',
        duration = 15000,
    })
    PlaySoundFrontend(-1, 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET', false)
end)

RegisterNetEvent('ws_dispatch:offerTaken', function(uid, byName)
    -- lastOffer bleibt bestehen, damit weitere Officer als Verstaerkung beitreten koennen
    if lastOffer and lastOffer.uid == uid then
        lib.notify({ title = locale('dispatch_title'), description = locale('offer_taken', byName), type = 'inform' })
    end
end)

RegisterNetEvent('ws_dispatch:offerExpired', function(uid)
    if lastOffer and lastOffer.uid == uid then
        lastOffer = nil
        lib.notify({ title = locale('dispatch_title'), description = locale('offer_expired'), type = 'error' })
    end
end)

RegisterCommand('annehmen', function()
    -- Job-Gate: Y ist doppelt belegt (Polizei-Einsatz / EMS-Notfall)
    if LocalPlayer.state['ws:job'] ~= 'police' or LocalPlayer.state['ws:duty'] ~= true then return end
    if not lastOffer then
        lib.notify({ title = locale('dispatch_title'), description = locale('no_offer'), type = 'error' })
        return
    end
    TriggerServerEvent('ws_dispatch:accept', lastOffer.uid)
end, false)
-- 'Z' = physische US-Taste, liegt auf deutschem QWERTZ-Layout auf der Y-Taste
RegisterKeyMapping('annehmen', 'Letzten Einsatz annehmen', 'keyboard', 'Z')

-- ---------------------------------------------------------------------------
-- Zuweisung / Abschluss
-- ---------------------------------------------------------------------------

RegisterNetEvent('ws_dispatch:assigned', function(callout, isPrimary)
    currentAssignment = callout
    currentAssignment.isPrimary = isPrimary
    if lastOffer and lastOffer.uid == callout.uid then lastOffer = nil end

    removeAssignmentBlip()
    currentBlip = AddBlipForCoord(callout.coords.x, callout.coords.y, callout.coords.z)
    SetBlipSprite(currentBlip, 1)
    SetBlipColour(currentBlip, 1)
    SetBlipScale(currentBlip, 1.0)
    SetBlipRoute(currentBlip, true)
    SetBlipRouteColour(currentBlip, 1)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(('%s – %s'):format(callout.code, callout.label))
    EndTextCommandSetBlipName(currentBlip)

    lib.notify({
        title = locale('dispatch_title'),
        description = isPrimary and locale('assigned_primary', callout.label) or locale('assigned_backup', callout.label),
        type = 'success',
    })

    if isPrimary then
        Scenario.start(callout)
    end
end)

RegisterNetEvent('ws_dispatch:ended', function(uid, reason)
    if currentAssignment and currentAssignment.uid == uid then
        currentAssignment = nil
        removeAssignmentBlip()
    end
    escortedPed = nil
    Scenario.stop(uid)
end)

RegisterNetEvent('ws_dispatch:suspectResolved', function(uid, netId)
    Scenario.suspectResolved(uid, netId)
end)

RegisterNetEvent('ws_dispatch:objectiveResolved', function(uid, netId, kind)
    Scenario.objectiveResolved(uid, netId, kind)
end)

-- ---------------------------------------------------------------------------
-- Interaktionen mit Verdaechtigen (fuer ALLE Officer, via Entity-Statebags)
-- ---------------------------------------------------------------------------

local function pedState(entity)
    return Entity(entity).state
end

local function playCuffedIdle(ped)
    lib.requestAnimDict('mp_arresting')
    TaskPlayAnim(ped, 'mp_arresting', 'idle', 8.0, -8.0, -1, 49, 0.0, false, false, false)
end

-- Gefesselte Peds lokal verwalten (via Statebag auf allen Clients bekannt)
local cuffedPeds = {}

AddStateBagChangeHandler('ws:cuffed', nil, function(bagName, _, value)
    local ent = GetEntityFromStateBagName(bagName)
    if not ent or ent == 0 then return end
    cuffedPeds[ent] = value == true or nil
end)

-- Die Blockier-Flags/-Tasks wirken nur auf dem Client, der den Ped besitzt.
-- Sie werden EINMALIG beim Einsetzen gesetzt (seatPedInVehicle) und als reines
-- Flag (nicht als Task!) periodisch aufgefrischt. Der Blocker-TASK wird NICHT
-- gechurnt - jedes Neusetzen oeffnet der KI ein Ausstiegsfenster.
--
-- Ein korrekt sitzender Gefangener wird NIE angefasst: Rauswerfen+Reinsetzen
-- im fahrenden Auto laesst das Fahrzeug springen. Nur ein tatsaechlich
-- entkommener Gefangener wird auf seinen Sitz zurueckgesetzt.

local prisonerVan = {} -- Gefangener -> Fahrzeug, in das er gesetzt wurde

CreateThread(function()
    while true do
        local tracking = false
        for ped, veh in pairs(prisonerVan) do
            if not DoesEntityExist(ped) or not DoesEntityExist(veh) or not cuffedPeds[ped] then
                prisonerVan[ped] = nil
            else
                tracking = true
                -- Nur eingreifen, wenn der Gefangene das Fahrzeug wirklich
                -- verlassen hat - einen sitzenden Ped nicht anfassen (kein Sprung)
                if NetworkHasControlOfEntity(ped) and not IsPedInVehicle(ped, veh, false) then
                    for _, i in ipairs({ 1, 2, 0 }) do
                        if IsVehicleSeatFree(veh, i) then
                            ClearPedTasksImmediately(ped)
                            SetPedIntoVehicle(ped, veh, i)
                            SetBlockingOfNonTemporaryEvents(ped, true)
                            TaskSetBlockingOfNonTemporaryEvents(ped, true)
                            for door = 0, 3 do SetVehicleDoorShut(veh, door, false) end
                            break
                        end
                    end
                end
            end
        end
        Wait(tracking and 250 or 1000)
    end
end)

-- Pflege-Flags fuer alle gefesselten Peds (reine Flags -> kein Task-Churn/Sprung)
CreateThread(function()
    while true do
        Wait(500)
        for ped in pairs(cuffedPeds) do
            if not DoesEntityExist(ped) then
                cuffedPeds[ped] = nil
                prisonerVan[ped] = nil
            elseif NetworkHasControlOfEntity(ped) then
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedCanBeDraggedOut(ped, false)
                SetPedFleeAttributes(ped, 0, false)
            end
        end
    end
end)

local function arrestPed(ped)
    local ok = lib.progressBar({
        duration = 4000,
        label = locale('arresting'),
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, combat = true },
        -- Flag 1 = Ganzkoerper, damit der Officer sich zum Fesseln beugt
        anim = { dict = 'mp_arresting', clip = 'a_uncuff', flag = 1 },
    })
    if not ok then return end

    if EnsureControl(ped) then
        ClearPedTasksImmediately(ped)
        RemoveAllPedWeapons(ped, true)
        playCuffedIdle(ped)
        SetEnableHandcuffs(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedCanBeDraggedOut(ped, false)
        SetPedFleeAttributes(ped, 0, false)
    end
    TriggerServerEvent('ws_dispatch:updateSuspect', NetworkGetNetworkIdFromEntity(ped), 'cuffed', true)
    lib.notify({ title = locale('dispatch_title'), description = locale('arrested_hint'), type = 'success' })
end

local function releaseEscort()
    local ped = escortedPed
    escortedPed = nil
    if not ped or not DoesEntityExist(ped) then return end
    DetachEntity(ped, true, false)
    if EnsureControl(ped) then
        ClearPedTasksImmediately(ped)
        playCuffedIdle(ped)
    end
end

local function toggleEscort(ped)
    if escortedPed == ped then
        return releaseEscort()
    end
    if escortedPed then releaseEscort() end
    if not EnsureControl(ped) then return end
    AttachEntityToEntity(ped, cache.ped, 11816, 0.45, 0.45, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    escortedPed = ped
    lib.notify({ title = locale('dispatch_title'), description = locale('escort_hint'), type = 'inform' })
end

-- Loslassen per Taste, da der angehaengte Ped mit ox_target kaum anvisierbar ist
RegisterCommand('loslassen', releaseEscort, false)
RegisterKeyMapping('loslassen', 'Eskortierten Verdächtigen loslassen', 'keyboard', 'X')

local function seatPedInVehicle(ped, veh)
    local seat
    for _, i in ipairs({ 1, 2, 0 }) do
        if IsVehicleSeatFree(veh, i) then seat = i break end
    end
    if not seat then
        lib.notify({ title = locale('dispatch_title'), description = locale('no_seat'), type = 'error' })
        return
    end

    if escortedPed == ped then
        DetachEntity(ped, true, false)
        escortedPed = nil
    end
    if not EnsureControl(ped) then return end
    ClearPedTasksImmediately(ped)
    SetPedIntoVehicle(ped, veh, seat)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanBeDraggedOut(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetEnableHandcuffs(ped, true)
    -- Aktiver "Nichts tun"-Task: verhindert, dass die Ped-KI selbst aussteigt
    -- (einmalig setzen - periodisches Neusetzen erzeugt Task-Luecken!)
    TaskSetBlockingOfNonTemporaryEvents(ped, true)
    prisonerVan[ped] = veh -- fuer den Ausbrecher-Wächter merken
    SetNewWaypoint(dropoff.x, dropoff.y)
    lib.notify({ title = locale('dispatch_title'), description = locale('bring_to_jail'), type = 'inform' })
end

local function seatPed(ped)
    local veh = lib.getClosestVehicle(GetEntityCoords(cache.ped), 8.0, true)
    if not veh then
        lib.notify({ title = locale('dispatch_title'), description = locale('no_vehicle'), type = 'error' })
        return
    end
    seatPedInVehicle(ped, veh)
end

local function unseatPed(ped)
    prisonerVan[ped] = nil -- gewolltes Ausladen: Ausbrecher-Wächter nicht mehr aktiv
    if not EnsureControl(ped) then return end
    local coords = GetEntityCoords(cache.ped)
    ClearPedTasksImmediately(ped)
    SetEntityCoords(ped, coords.x + 0.7, coords.y + 0.7, coords.z, false, false, false, false)
    playCuffedIdle(ped)
end

local function deliverPed(ped)
    local ok = lib.progressBar({
        duration = 3000,
        label = locale('delivering'),
        canCancel = true,
        disable = { move = true, combat = true },
    })
    if not ok then return end
    TriggerServerEvent('ws_dispatch:deliverSuspect', NetworkGetNetworkIdFromEntity(ped))
end

-- Sperre gegen Doppel-Behandlung, bis das Statebag-Update repliziert ist
local pendingTreat = {}

local function treatPed(ped)
    if pendingTreat[ped] then return end
    pendingTreat[ped] = true

    local ok = lib.progressBar({
        duration = 8000,
        label = locale('treating'),
        canCancel = true,
        disable = { move = true, combat = true },
        -- Flag 1 = Ganzkoerper, damit der Officer zum Reanimieren kniet
        anim = { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest', flag = 1 },
    })
    if not ok then
        pendingTreat[ped] = nil
        return
    end

    TriggerServerEvent('ws_dispatch:objectiveDone', NetworkGetNetworkIdFromEntity(ped))
    SetTimeout(3000, function() pendingTreat[ped] = nil end)
end

function searchPed(ped)
    local ok = lib.progressBar({
        duration = 4000,
        label = locale('searching'),
        canCancel = true,
        disable = { move = true, combat = true },
        anim = { dict = 'mp_arresting', clip = 'a_uncuff', flag = 1 },
    })
    if not ok then return end

    local res = lib.callback.await('ws_dispatch:searchSuspect', false, NetworkGetNetworkIdFromEntity(ped))
    if not res then return end

    if res.already then
        lib.notify({ title = locale('search_title'), description = locale('search_done'), type = 'inform' })
    elseif res.item then
        lib.notify({ title = locale('search_title'), description = locale('search_found', res.item, res.xp), type = 'success' })
    else
        lib.notify({ title = locale('search_title'), description = locale('search_nothing'), type = 'inform' })
    end
end

exports.ox_target:addGlobalPed({
    {
        name = 'ws_arrest',
        label = locale('target_arrest'),
        icon = 'fa-solid fa-handcuffs',
        canInteract = function(entity)
            local s = pedState(entity)
            return s['ws:suspect'] and s['ws:surrendered'] and not s['ws:cuffed']
        end,
        onSelect = function(data) arrestPed(data.entity) end,
    },
    {
        name = 'ws_escort',
        label = locale('target_escort'),
        icon = 'fa-solid fa-person-walking',
        canInteract = function(entity)
            local s = pedState(entity)
            return s['ws:cuffed'] and not IsPedInAnyVehicle(entity, false)
        end,
        onSelect = function(data) toggleEscort(data.entity) end,
    },
    {
        name = 'ws_seat',
        label = locale('target_seat'),
        icon = 'fa-solid fa-car-side',
        canInteract = function(entity)
            local s = pedState(entity)
            return s['ws:cuffed'] and not IsPedInAnyVehicle(entity, false)
        end,
        onSelect = function(data) seatPed(data.entity) end,
    },
    {
        name = 'ws_unseat',
        label = locale('target_unseat'),
        icon = 'fa-solid fa-person-through-window',
        canInteract = function(entity)
            local s = pedState(entity)
            return s['ws:cuffed'] and IsPedInAnyVehicle(entity, false)
        end,
        onSelect = function(data) unseatPed(data.entity) end,
    },
    {
        name = 'ws_deliver',
        label = locale('target_deliver'),
        icon = 'fa-solid fa-building-shield',
        canInteract = function(entity)
            local s = pedState(entity)
            return s['ws:cuffed'] and #(GetEntityCoords(cache.ped) - dropoffCoords) < WSDispatch.DeliverRadius
        end,
        onSelect = function(data) deliverPed(data.entity) end,
    },
    {
        name = 'ws_treat',
        label = locale('target_treat'),
        icon = 'fa-solid fa-kit-medical',
        canInteract = function(entity)
            return pedState(entity)['ws:injured'] == true and not pendingTreat[entity]
        end,
        onSelect = function(data) treatPed(data.entity) end,
    },
    {
        name = 'ws_search',
        label = locale('target_search'),
        icon = 'fa-solid fa-magnifying-glass',
        canInteract = function(entity)
            local s = pedState(entity)
            return s['ws:suspect'] and (s['ws:cuffed'] or s['ws:surrendered'])
        end,
        onSelect = function(data) searchPed(data.entity) end,
    },
})

-- Sitzt ein Gefangener im Fahrzeug, trifft ox_target nur die Karosserie -
-- daher laufen diese Interaktionen ueber das Fahrzeug statt ueber den Ped.
local function findCuffedPassenger(veh)
    local maxSeats = GetVehicleModelNumberOfSeats(GetEntityModel(veh))
    for seat = -1, maxSeats - 2 do
        local ped = GetPedInVehicleSeat(veh, seat)
        if ped ~= 0 and DoesEntityExist(ped) and Entity(ped).state['ws:cuffed'] then
            return ped
        end
    end
end

exports.ox_target:addGlobalVehicle({
    {
        name = 'ws_vehicle_unseat',
        label = locale('target_unseat'),
        icon = 'fa-solid fa-person-through-window',
        canInteract = function(entity)
            return findCuffedPassenger(entity) ~= nil
        end,
        onSelect = function(data)
            local ped = findCuffedPassenger(data.entity)
            if ped then unseatPed(ped) end
        end,
    },
    {
        name = 'ws_vehicle_deliver',
        label = locale('target_deliver'),
        icon = 'fa-solid fa-building-shield',
        canInteract = function(entity)
            return findCuffedPassenger(entity) ~= nil
                and #(GetEntityCoords(cache.ped) - dropoffCoords) < WSDispatch.DeliverRadius
        end,
        onSelect = function(data)
            local ped = findCuffedPassenger(data.entity)
            if ped then deliverPed(ped) end
        end,
    },
    {
        name = 'ws_seat_escorted',
        label = locale('target_seat_escorted'),
        icon = 'fa-solid fa-car-side',
        canInteract = function()
            return escortedPed ~= nil and DoesEntityExist(escortedPed)
        end,
        onSelect = function(data) seatPedInVehicle(escortedPed, data.entity) end,
    },
})

-- Bodenmarker an der Gefangenenuebergabe: erscheint nur, wenn tatsaechlich
-- ein Gefangener zum Einliefern dabei ist (im Fahrzeug oder eskortiert)
local function hasDeliverablePrisoner()
    if escortedPed and DoesEntityExist(escortedPed) then return true end
    local veh = cache.vehicle or lib.getClosestVehicle(GetEntityCoords(cache.ped), 12.0, true)
    return (veh and findCuffedPassenger(veh) ~= nil) or false
end

CreateThread(function()
    local show = false
    local nextCheck = 0
    while true do
        local now = GetGameTimer()
        if now >= nextCheck then
            nextCheck = now + 500
            show = LocalPlayer.state['ws:job'] == 'police'
                and LocalPlayer.state['ws:duty'] == true
                and #(GetEntityCoords(cache.ped) - dropoffCoords) < 60.0
                and hasDeliverablePrisoner()
        end
        if show then
            DrawMarker(1, dropoff.x, dropoff.y, dropoff.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                4.0, 4.0, 1.0, 45, 110, 220, 110, false, false, 2, false, nil, nil, false)
            Wait(0)
        else
            Wait(500)
        end
    end
end)
