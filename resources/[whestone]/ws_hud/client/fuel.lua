lib.locale()

-- Tanksystem. Der Sprit haengt als Entity-Statebag 'ws:fuel' am Fahrzeug und
-- wird vom Fahrer (= Besitzer, darf replizierte Statebags setzen) gepflegt;
-- Mitfahrer sehen den Wert dadurch synchron. Nicht persistent - beim naechsten
-- Spawn ist das Fahrzeug wieder voll.
--
-- Stellt die globale Tabelle WSFuel bereit (von hud.lua genutzt).

local CFG = WSHud.Fuel

WSFuel = { enabled = CFG.enabled == true }

function WSFuel.get(veh)
    if not veh or veh == 0 then return nil end
    return Entity(veh).state['ws:fuel']
end

-- Fuellstand erst erfassen, wenn der lokale Spieler das Fahrzeug besitzt -
-- sonst schlaegt das replizierte Statebag-Set fehl.
function WSFuel.ensure(veh)
    if WSFuel.get(veh) == nil and NetworkGetEntityOwner(veh) == PlayerId() then
        Entity(veh).state:set('ws:fuel', CFG.default, true)
    end
end

function WSFuel.set(veh, value)
    if not veh or veh == 0 then return end
    value = math.max(0.0, math.min(100.0, value))
    Entity(veh).state:set('ws:fuel', value, true)
end

if not WSFuel.enabled then return end

-- ---------------------------------------------------------------------------
-- Betankung an Zapfsaeulen (ox_target auf die Weltobjekte)
-- ---------------------------------------------------------------------------

local refueling = false

local function nearestVehicle()
    local veh = cache.vehicle or lib.getClosestVehicle(GetEntityCoords(cache.ped), CFG.refuelDistance, false)
    return veh
end

local function refuel()
    if refueling then return end
    local veh = nearestVehicle()
    if not veh or veh == 0 then
        lib.notify({ title = locale('fuel_title'), description = locale('fuel_no_vehicle'), type = 'error' })
        return
    end
    if (WSFuel.get(veh) or 0) >= 99.5 then
        lib.notify({ title = locale('fuel_title'), description = locale('fuel_full'), type = 'inform' })
        return
    end

    refueling = true
    local ok = lib.progressBar({
        duration = CFG.refuelTime,
        label = locale('fuel_refueling'),
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'timetable@gardener@filling_can', clip = 'gar_ig_5_filling_can', flag = 49 },
    })
    refueling = false
    if not ok then return end

    -- Kontrolle uebernehmen, damit das Statebag-Set repliziert
    NetworkRequestControlOfEntity(veh)
    local tries = 0
    while not NetworkHasControlOfEntity(veh) and tries < 20 do Wait(25) tries = tries + 1 end
    WSFuel.set(veh, 100.0)
    lib.notify({ title = locale('fuel_title'), description = locale('fuel_done'), type = 'success' })
end

local pumpOption = {
    name = 'ws_hud_refuel',
    label = locale('fuel_option'),
    icon = 'fa-solid fa-gas-pump',
    distance = 2.0,
    onSelect = refuel,
}

if CFG.pumpProps and #CFG.pumpProps > 0 then
    exports.ox_target:addModel(CFG.pumpProps, { pumpOption })
end
