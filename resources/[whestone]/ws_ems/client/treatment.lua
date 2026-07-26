lib.locale()

-- Behandlungs-Gameplay: wirkt auf Peds mit Statebag ws:patient. Der Zustand
-- (ws:patient_state) bestimmt die noetige Behandlung. Wird von der EMS-Notfall-
-- Engine (callouts.lua) gespawnt, ist aber davon entkoppelt.

-- Abgabepunkte: Notaufnahme (Erdgeschoss) + Helipad (Dach)
local dropoffs = {
    vector3(WSEms.Station.dropoff.x, WSEms.Station.dropoff.y, WSEms.Station.dropoff.z),
    vector3(WSEms.Helipad.dropoff.x, WSEms.Helipad.dropoff.y, WSEms.Helipad.dropoff.z),
}

local function nearestDropoff()
    local pos = GetEntityCoords(cache.ped)
    local best, bestDist
    for _, d in ipairs(dropoffs) do
        local dist = #(pos - d)
        if not bestDist or dist < bestDist then best, bestDist = d, dist end
    end
    return best, bestDist
end

-- Rettungsfahrzeuge: RTW & Co (Klasse 18) sowie Helikopter (Klasse 15)
local function isEmsVehicle(veh)
    local cls = GetVehicleClass(veh)
    return cls == 18 or cls == 15
end

local function isOnDuty()
    return LocalPlayer.state['ws:job'] == 'ambulance' and LocalPlayer.state['ws:duty'] == true
end

local function pState(entity)
    return Entity(entity).state
end

local function ensureControl(entity)
    if not DoesEntityExist(entity) then return false end
    if NetworkHasControlOfEntity(entity) then return true end
    NetworkRequestControlOfEntity(entity)
    local tries = 0
    while not NetworkHasControlOfEntity(entity) and tries < 50 do Wait(20) tries = tries + 1 end
    return NetworkHasControlOfEntity(entity)
end

local function enotify(key, ntype, ...)
    lib.notify({ title = locale('med_title'), description = locale(key, ...), type = ntype or 'inform' })
end

-- Sperre gegen Doppelbehandlung, bis das Statebag-Update repliziert ist
local pending = {}

-- Medizin-Skill: 15% schnellere Behandlungen je Stufe,
-- ab Stufe 2 ein zusaetzlicher Reanimationsversuch
local function medLevel()
    return LocalPlayer.state['ws:skill_medic'] or 0
end
local function medDuration(ms)
    return math.floor(ms * (1.0 - 0.15 * medLevel()))
end

-- Sichtbarer Bodenmarker an der Notaufnahme-Uebergabe: erscheint nur, wenn
-- tatsaechlich ein Patient zum Abgeben dabei ist (im Fahrzeug oder gestuetzt)
local hasDeliverablePatient -- Definition weiter unten (braucht findPatientInVehicle)

CreateThread(function()
    local show = false
    local target
    local nextCheck = 0
    while true do
        local now = GetGameTimer()
        if now >= nextCheck then
            nextCheck = now + 500
            local d, dist = nearestDropoff()
            target = d
            show = isOnDuty()
                and dist < 60.0
                and hasDeliverablePatient ~= nil and hasDeliverablePatient()
        end
        if show then
            DrawMarker(1, target.x, target.y, target.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                4.0, 4.0, 1.0, 220, 60, 60, 110, false, false, 2, false, nil, nil, false)
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Diagnose
-- ---------------------------------------------------------------------------

local function diagnose(ped)
    if pending[ped] then return end
    pending[ped] = true
    local ok = lib.progressBar({
        duration = medDuration(WSEms.Durations.diagnose),
        label = locale('diag_running'),
        canCancel = true,
        disable = { move = true, combat = true, car = true },
        anim = { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest', flag = 1 },
    })
    if ok then
        local state = pState(ped)['ws:patient_state'] or 'stable'
        TriggerServerEvent('ws_ems:updatePatient', NetworkGetNetworkIdFromEntity(ped), state, true)

        -- Vitalwerte passend zum Zustand
        local pulse, breathing
        if state == 'cardiac' then
            pulse, breathing = 0, locale('breath_none')
        elseif state == 'unconscious' then
            pulse, breathing = math.random(38, 55), locale('breath_weak')
        elseif state == 'trauma' then
            pulse, breathing = math.random(100, 132), locale('breath_fast')
        else
            pulse, breathing = math.random(62, 88), locale('breath_normal')
        end
        lib.notify({
            title = locale('med_title'),
            description = ('%s\n%s'):format(
                locale('diag_result', locale('state_' .. state)),
                locale('diag_vitals', pulse, breathing)),
            type = 'inform',
            duration = 9000,
        })
    end
    SetTimeout(2000, function() pending[ped] = nil end)
end

-- ---------------------------------------------------------------------------
-- Behandlung (Reanimation / Stabilisieren / Wundversorgung)
-- ---------------------------------------------------------------------------

local function finishTreatment(ped)
    -- Patient stabilisiert: aufwachen, hinsetzen
    if ensureControl(ped) then
        ClearPedTasksImmediately(ped)
        SetEntityHealth(ped, GetEntityMaxHealth(ped))
        TaskStartScenarioInPlace(ped, 'CODE_HUMAN_MEDIC_TEND_TO_DEAD', 0, true)
    end
    TriggerServerEvent('ws_ems:updatePatient', NetworkGetNetworkIdFromEntity(ped), 'stable', true)
    enotify('treat_done', 'success')
end

-- Fehlversuche je Patient: nach 3 gescheiterten Reanimationen ist er verloren.
-- WICHTIG: GTA vergibt Entity-Handles nach dem Despawn neu. Bleibt hier ein
-- Eintrag eines laengst geloeschten Patienten stehen, startet ein spaeterer
-- Patient mit demselben Handle bereits mit Fehlversuchen - und stirbt beim
-- ersten Fehlschlag. Daher periodisch aufraeumen.
local defiFails = {}

CreateThread(function()
    while true do
        Wait(30000)
        for ped in pairs(defiFails) do
            if not DoesEntityExist(ped) then defiFails[ped] = nil end
        end
        for ped in pairs(pending) do
            if not DoesEntityExist(ped) then pending[ped] = nil end
        end
    end
end)

local function reanimate(ped)
    if pending[ped] then return end
    pending[ped] = true

    -- Defibrillator-Minispiel (Timing per E, unabhaengig von lib.skillCheck)
    enotify('defi_charge', 'inform')
    local success = WSDefiMinigame()
    if success then
        defiFails[ped] = nil
        finishTreatment(ped)
    else
        local maxFails = medLevel() >= 2 and 4 or 3
        local fails = (defiFails[ped] or 0) + 1
        defiFails[ped] = fails
        if fails >= maxFails then
            -- Patient verloren: stirbt, Einsatz endet ohne Belohnung
            defiFails[ped] = nil
            if ensureControl(ped) then
                SetEntityHealth(ped, 0)
            end
            TriggerServerEvent('ws_ems:patientLost', NetworkGetNetworkIdFromEntity(ped))
            enotify('patient_lost', 'error')
        else
            enotify('defi_failed_count', 'error', maxFails - fails)
        end
    end
    SetTimeout(1500, function() pending[ped] = nil end)
end

local function treatWound(ped, animLabelKey)
    if pending[ped] then return end
    pending[ped] = true
    local ok = lib.progressBar({
        duration = medDuration(WSEms.Durations.treat),
        label = locale(animLabelKey),
        canCancel = true,
        disable = { move = true, combat = true, car = true },
        anim = { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest', flag = 1 },
    })
    if ok then finishTreatment(ped) end
    SetTimeout(1500, function() pending[ped] = nil end)
end

-- ---------------------------------------------------------------------------
-- Transport
-- ---------------------------------------------------------------------------

local escortedPatient

local function seatPatient(ped, veh)
    local seat
    for _, i in ipairs({ 1, 2, 0 }) do
        if IsVehicleSeatFree(veh, i) then seat = i break end
    end
    if not seat then enotify('no_seat', 'error') return end

    if escortedPatient == ped then
        DetachEntity(ped, true, false)
        escortedPatient = nil
    end
    if not ensureControl(ped) then return end
    ClearPedTasksImmediately(ped)
    SetPedIntoVehicle(ped, veh, seat)
    SetNewWaypoint(WSEms.Station.dropoff.x, WSEms.Station.dropoff.y)
    enotify('loaded', 'success')
end

local function loadIntoVehicle(ped)
    local veh = lib.getClosestVehicle(GetEntityCoords(cache.ped), 8.0, false)
    if not veh or not isEmsVehicle(veh) then
        enotify('no_ambulance', 'error')
        return
    end
    seatPatient(ped, veh)
end

-- Patient stuetzen: zum Rettungswagen bringen (Attach wie Polizei-Eskorte)
local function releasePatient()
    local ped = escortedPatient
    escortedPatient = nil
    if not ped or not DoesEntityExist(ped) then return end
    DetachEntity(ped, true, false)
    if ensureControl(ped) then
        ClearPedTasksImmediately(ped)
        TaskStartScenarioInPlace(ped, 'CODE_HUMAN_MEDIC_TEND_TO_DEAD', 0, true)
    end
end

local function toggleEscortPatient(ped)
    if escortedPatient == ped then
        return releasePatient()
    end
    if escortedPatient then releasePatient() end
    if not ensureControl(ped) then return end
    ClearPedTasksImmediately(ped)
    AttachEntityToEntity(ped, cache.ped, 11816, 0.45, 0.45, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    escortedPatient = ped
    enotify('escort_hint', 'inform')
end

RegisterCommand('patient_loslassen', releasePatient, false)
RegisterKeyMapping('patient_loslassen', 'Rettungsdienst: Patient loslassen', 'keyboard', 'X')

local function unload(ped)
    if not ensureControl(ped) then return end
    local c = GetEntityCoords(cache.ped)
    ClearPedTasksImmediately(ped)
    SetEntityCoords(ped, c.x + 0.8, c.y + 0.8, c.z, false, false, false, false)
    TaskStartScenarioInPlace(ped, 'CODE_HUMAN_MEDIC_TEND_TO_DEAD', 0, true)
end

local function deliver(ped)
    local ok = lib.progressBar({
        duration = 3000, label = locale('deliver_running'), canCancel = true,
        disable = { move = true, combat = true },
    })
    if not ok then return end
    TriggerServerEvent('ws_ems:deliverPatient', NetworkGetNetworkIdFromEntity(ped))
    -- Ped wird serverseitig geloescht -> Handle sofort freigeben
    defiFails[ped] = nil
    pending[ped] = nil
end

-- ---------------------------------------------------------------------------
-- ox_target auf Patienten
-- ---------------------------------------------------------------------------

exports.ox_target:addGlobalPed({
    {
        name = 'ws_ems_diagnose',
        label = locale('opt_diagnose'),
        icon = 'fa-solid fa-stethoscope',
        distance = 2.0,
        canInteract = function(entity)
            return isOnDuty() and pState(entity)['ws:patient'] and not pState(entity)['ws:patient_diag']
        end,
        onSelect = function(data) diagnose(data.entity) end,
    },
    {
        name = 'ws_ems_reanimate',
        label = locale('opt_reanimate'),
        icon = 'fa-solid fa-heart-pulse',
        distance = 2.0,
        canInteract = function(entity)
            local s = pState(entity)
            return isOnDuty() and s['ws:patient_diag'] and s['ws:patient_state'] == 'cardiac'
        end,
        onSelect = function(data) reanimate(data.entity) end,
    },
    {
        name = 'ws_ems_stabilize',
        label = locale('opt_stabilize'),
        icon = 'fa-solid fa-syringe',
        distance = 2.0,
        canInteract = function(entity)
            local s = pState(entity)
            return isOnDuty() and s['ws:patient_diag'] and s['ws:patient_state'] == 'unconscious'
        end,
        onSelect = function(data) treatWound(data.entity, 'stabilize_running') end,
    },
    {
        name = 'ws_ems_wound',
        label = locale('opt_wound'),
        icon = 'fa-solid fa-bandage',
        distance = 2.0,
        canInteract = function(entity)
            local s = pState(entity)
            return isOnDuty() and s['ws:patient_diag'] and s['ws:patient_state'] == 'trauma'
        end,
        onSelect = function(data) treatWound(data.entity, 'wound_running') end,
    },
    {
        name = 'ws_ems_escort',
        label = locale('opt_escort'),
        icon = 'fa-solid fa-person-walking',
        distance = 2.5,
        canInteract = function(entity)
            local s = pState(entity)
            return isOnDuty() and s['ws:patient'] and s['ws:patient_state'] == 'stable'
                and not IsPedInAnyVehicle(entity, false)
        end,
        onSelect = function(data) toggleEscortPatient(data.entity) end,
    },
    {
        name = 'ws_ems_load',
        label = locale('opt_load'),
        icon = 'fa-solid fa-truck-medical',
        distance = 3.0,
        canInteract = function(entity)
            local s = pState(entity)
            return isOnDuty() and s['ws:patient'] and s['ws:patient_state'] == 'stable'
                and not IsPedInAnyVehicle(entity, false)
        end,
        onSelect = function(data) loadIntoVehicle(data.entity) end,
    },
    {
        name = 'ws_ems_unload',
        label = locale('opt_unload'),
        icon = 'fa-solid fa-person-walking-arrow-right',
        distance = 3.0,
        canInteract = function(entity)
            return isOnDuty() and pState(entity)['ws:patient'] and IsPedInAnyVehicle(entity, false)
        end,
        onSelect = function(data) unload(data.entity) end,
    },
    {
        name = 'ws_ems_deliver',
        label = locale('opt_deliver'),
        icon = 'fa-solid fa-hospital',
        distance = 3.0,
        canInteract = function(entity)
            local s = pState(entity)
            local _, dist = nearestDropoff()
            return isOnDuty() and s['ws:patient'] and s['ws:patient_state'] == 'stable'
                and dist < WSEms.DeliverRadius
        end,
        onSelect = function(data) deliver(data.entity) end,
    },
})

-- Sitzt ein Patient im Fahrzeug, trifft ox_target nur die Karosserie -
-- Ausladen/Einliefern laufen daher (wie bei Gefangenen) ueber das Fahrzeug
local function findPatientInVehicle(veh)
    local maxSeats = GetVehicleModelNumberOfSeats(GetEntityModel(veh))
    for seat = -1, maxSeats - 2 do
        local ped = GetPedInVehicleSeat(veh, seat)
        if ped ~= 0 and DoesEntityExist(ped) and Entity(ped).state['ws:patient'] then
            return ped
        end
    end
end

-- Fuer den Uebergabe-Marker: Patient im eigenen/nahen Fahrzeug oder gestuetzt?
hasDeliverablePatient = function()
    if escortedPatient and DoesEntityExist(escortedPatient) then return true end
    local veh = cache.vehicle or lib.getClosestVehicle(GetEntityCoords(cache.ped), 12.0, true)
    return (veh and findPatientInVehicle(veh) ~= nil) or false
end

exports.ox_target:addGlobalVehicle({
    {
        name = 'ws_ems_load_escorted',
        label = locale('opt_load'),
        icon = 'fa-solid fa-truck-medical',
        distance = 4.0,
        canInteract = function(entity)
            return isOnDuty() and escortedPatient ~= nil and DoesEntityExist(escortedPatient)
                and isEmsVehicle(entity)
        end,
        onSelect = function(data) seatPatient(escortedPatient, data.entity) end,
    },
    {
        name = 'ws_ems_vehicle_unload',
        label = locale('opt_unload'),
        icon = 'fa-solid fa-person-walking-arrow-right',
        distance = 4.0,
        canInteract = function(entity)
            return isOnDuty() and findPatientInVehicle(entity) ~= nil
        end,
        onSelect = function(data)
            local ped = findPatientInVehicle(data.entity)
            if ped then unload(ped) end
        end,
    },
    {
        name = 'ws_ems_vehicle_deliver',
        label = locale('opt_deliver'),
        icon = 'fa-solid fa-hospital',
        distance = 4.0,
        canInteract = function(entity)
            local _, dist = nearestDropoff()
            return isOnDuty() and findPatientInVehicle(entity) ~= nil
                and dist < WSEms.DeliverRadius
        end,
        onSelect = function(data)
            local ped = findPatientInVehicle(data.entity)
            if ped then deliver(ped) end
        end,
    },
})
