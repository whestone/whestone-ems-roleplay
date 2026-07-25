-- Ausruestungsmenue (Taste F6): platzierbare Absperr-Objekte fuer
-- Einsatzstellen (Leitkegel, Absperrgitter) und Reifenkrallen fuer
-- Verfolgungsjagden. Objekte sind genetzt und fuer alle sichtbar.

local placedProps = {} -- alle eigenen platzierten Objekte
local spikeStrips = {} -- Untermenge: Reifenkrallen (fuer Tire-Burst-Pruefung)

local function isOnDuty()
    return LocalPlayer.state['ws:job'] == 'police' and LocalPlayer.state['ws:duty'] == true
end

local function notifyEquip(key, ntype, ...)
    lib.notify({ title = locale('equip_title'), description = locale(key, ...), type = ntype or 'inform' })
end

local function placeProp(kind)
    if #placedProps >= WSPolice.Equipment.maxProps then
        return notifyEquip('equip_limit', 'error')
    end

    local def = WSPolice.Equipment.props[kind]
    local hash = joaat(def.model)
    lib.requestModel(hash, 5000)

    local fwd = GetEntityForwardVector(cache.ped)
    local base = GetEntityCoords(cache.ped) + fwd * def.forward
    local obj = CreateObject(hash, base.x, base.y, base.z, true, true, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityHeading(obj, GetEntityHeading(cache.ped))
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)

    placedProps[#placedProps + 1] = obj
    if kind == 'spike' then
        spikeStrips[obj] = true
    end
    notifyEquip('equip_placed', 'success')
end

local function cleanupProps()
    local n = 0
    for _, obj in ipairs(placedProps) do
        if DoesEntityExist(obj) then
            DeleteEntity(obj)
            n = n + 1
        end
    end
    placedProps = {}
    spikeStrips = {}
    notifyEquip('equip_cleaned', 'inform', n)
end

local function openEquipment()
    lib.registerContext({
        id = 'ws_equipment',
        title = locale('equip_title'),
        options = {
            { title = locale('equip_cone'), icon = 'triangle-exclamation', onSelect = function() placeProp('cone') end },
            { title = locale('equip_barrier'), icon = 'road-barrier', onSelect = function() placeProp('barrier') end },
            { title = locale('equip_spike'), icon = 'grip-lines', description = locale('equip_spike_desc'), onSelect = function() placeProp('spike') end },
            { title = locale('equip_cleanup'), icon = 'trash-can', description = locale('equip_cleanup_desc'), onSelect = cleanupProps },
        },
    })
    lib.showContext('ws_equipment')
end

RegisterCommand('ausruestung', function()
    if isOnDuty() then openEquipment() end
end, false)
RegisterKeyMapping('ausruestung', 'Polizei: Ausrüstungsmenü', 'keyboard', 'F6')

-- Reifenkrallen: Fahrzeuge, die mit Tempo darueberfahren, verlieren die Reifen
CreateThread(function()
    while true do
        if next(spikeStrips) then
            for strip in pairs(spikeStrips) do
                if not DoesEntityExist(strip) then
                    spikeStrips[strip] = nil
                else
                    local spos = GetEntityCoords(strip)
                    local veh = lib.getClosestVehicle(spos, 3.5, false)
                    if veh and #(GetEntityCoords(veh) - spos) < 3.2 and #(GetEntityVelocity(veh)) > 3.0 then
                        if NetworkHasControlOfEntity(veh) or NetworkRequestControlOfEntity(veh) then
                            for _, w in ipairs({ 0, 1, 2, 3, 4, 5 }) do
                                if not IsVehicleTyreBurst(veh, w, false) then
                                    SetVehicleTyreBurst(veh, w, true, 1000.0)
                                end
                            end
                        end
                    end
                end
            end
            Wait(50)
        else
            Wait(1000)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= cache.resource then return end
    for _, obj in ipairs(placedProps) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
end)
