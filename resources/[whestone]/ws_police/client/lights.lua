-- Blaulichtsystem: Blaulicht und Sirene getrennt schaltbar.
-- Sync ueber Entity-Statebag 'ws:sirenMuted' (Fahrer besitzt sein Fahrzeug,
-- darf also replizierte Statebags setzen; alle Clients wenden den Ton lokal an).

local function currentEmergencyVehicle()
    local veh = cache.vehicle
    if not veh then return nil end
    if GetPedInVehicleSeat(veh, -1) ~= cache.ped then return nil end
    if GetVehicleClass(veh) ~= 18 then return nil end -- nur Einsatzfahrzeuge
    return veh
end

-- Blaulicht an/aus (ohne Ton)
RegisterCommand('blaulicht', function()
    local veh = currentEmergencyVehicle()
    if not veh then return end

    local turnOn = not IsVehicleSirenOn(veh)
    SetVehicleSiren(veh, turnOn)
    -- Beim Einschalten startet das Blaulicht immer stumm
    Entity(veh).state:set('ws:sirenMuted', turnOn, true)
end, false)
RegisterKeyMapping('blaulicht', 'Polizei: Blaulicht an/aus', 'keyboard', 'L')

-- Sirene an/aus (nur bei aktivem Blaulicht)
RegisterCommand('sirene', function()
    local veh = currentEmergencyVehicle()
    if not veh or not IsVehicleSirenOn(veh) then return end

    -- nil (Zustand nie gesetzt, z. B. Vanilla-Blaulicht) zaehlt als "nicht stumm",
    -- damit der erste Tastendruck sofort schaltet
    local muted = Entity(veh).state['ws:sirenMuted'] == true
    Entity(veh).state:set('ws:sirenMuted', not muted, true)
end, false)
RegisterKeyMapping('sirene', 'Polizei: Sirene an/aus', 'keyboard', 'K')

-- Jeder Client wendet den Stumm-Zustand lokal an
AddStateBagChangeHandler('ws:sirenMuted', nil, function(bagName, _, value)
    local ent = GetEntityFromStateBagName(bagName)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end
    SetVehicleHasMutedSirens(ent, value == true)
end)
