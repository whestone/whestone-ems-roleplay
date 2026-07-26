lib.locale()

-- Fahrzeug-HUD (Tacho): Geschwindigkeit, Motor- und Blaulichtstatus, optional
-- Tankanzeige. Motor per Taste M schaltbar. NUI-Overlay ohne Fokus.

local hudVisible = false
local lastFuelDrain = 0

local function isDriver(veh)
    return veh and veh ~= 0 and GetPedInVehicleSeat(veh, -1) == cache.ped
end

-- ---------------------------------------------------------------------------
-- Motor an/aus (Taste M) - nur als Fahrer
-- ---------------------------------------------------------------------------

RegisterCommand('engine_toggle', function()
    local veh = cache.vehicle
    if not isDriver(veh) then return end

    local running = GetIsVehicleEngineRunning(veh)
    if not running and WSFuel.enabled and (WSFuel.get(veh) or 0) <= 0 then
        lib.notify({ title = locale('hud_title'), description = locale('engine_no_fuel'), type = 'error' })
        return
    end

    NetworkRequestControlOfEntity(veh)
    -- disableAutoStart=true: Motor bleibt aus, auch wenn man Gas gibt
    SetVehicleEngineOn(veh, not running, false, true)
    lib.notify({
        title = locale('hud_title'),
        description = running and locale('engine_off') or locale('engine_on'),
        type = 'inform',
    })
end, false)
RegisterKeyMapping('engine_toggle', 'Fahrzeug: Motor an/aus', 'keyboard', 'M')

-- ---------------------------------------------------------------------------
-- HUD-Schleife
-- ---------------------------------------------------------------------------

CreateThread(function()
    while true do
        local veh = cache.vehicle
        if veh and veh ~= 0 then
            local emergency = GetVehicleClass(veh) == 18
            local driver = isDriver(veh)

            -- Tank: nur der Fahrer erfasst/verbraucht (Besitzer repliziert)
            local fuel
            if WSFuel.enabled then
                if driver then WSFuel.ensure(veh) end
                fuel = WSFuel.get(veh)

                if driver and GetIsVehicleEngineRunning(veh) and fuel and fuel > 0 then
                    local now = GetGameTimer()
                    local dt = (now - lastFuelDrain) / 1000.0
                    lastFuelDrain = now
                    -- Verbrauch skaliert mit der Motordrehzahl (Leerlauf frisst wenig)
                    local rpm = GetVehicleCurrentRpm(veh)
                    local drain = WSHud.Fuel.consumption * (0.15 + 0.85 * rpm) * (dt / 60.0)
                    fuel = fuel - drain
                    WSFuel.set(veh, fuel)
                    if fuel <= 0 then
                        SetVehicleEngineOn(veh, false, false, true) -- Tank leer -> Motor aus
                    end
                else
                    lastFuelDrain = GetGameTimer()
                end
            end

            SendNUIMessage({
                action = 'update',
                speed = GetEntitySpeed(veh) * 3.6, -- m/s -> km/h
                maxSpeed = WSHud.MaxSpeedKmh,
                engine = GetIsVehicleEngineRunning(veh),
                emergency = emergency,
                lights = emergency and IsVehicleSirenOn(veh) or false,
                fuelShown = WSFuel.enabled,
                fuel = fuel,
                lowAt = WSHud.Fuel.lowThreshold,
            })
            hudVisible = true
            Wait(WSHud.UpdateInterval)
        else
            if hudVisible then
                SendNUIMessage({ action = 'hide' })
                hudVisible = false
            end
            lastFuelDrain = GetGameTimer()
            Wait(300)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == cache.resource then
        SendNUIMessage({ action = 'hide' })
    end
end)
