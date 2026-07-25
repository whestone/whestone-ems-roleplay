local carModels = { 'sultan', 'buffalo', 'dominator', 'futo', 'penumbra', 'felon' }
local pedModels = { 'g_m_y_lost_03', 'g_m_y_mexgoon_01', 'g_m_y_stgoon_02', 'a_m_y_mexthug_01' }

RegisterCalloutHandler('vehicle_theft', {
    onStart = function(ctx)
        local c = ctx.coords
        local surrender = { onStun = true, lowHealth = 0.5, proximity = 6 }
        local veh = ctx.spawnVehicle(PickRandom(carModels), vector3(c.x, c.y, c.z), c.w)

        -- Fahrer immer, 40% Chance auf einen Komplizen als Beifahrer
        local occupants = {}
        local driverPed, driverNetId = ctx.spawnPed(PickRandom(pedModels), vector3(c.x + 2.0, c.y, c.z), c.w, {
            suspect = true, surrender = surrender,
        })
        EnsureControl(driverPed)
        SetPedIntoVehicle(driverPed, veh, -1)
        SetPedKeepTask(driverPed, true)
        SetDriverAbility(driverPed, 1.0)
        SetDriverAggressiveness(driverPed, 1.0)
        occupants[1] = { ped = driverPed, netId = driverNetId }

        if math.random() < 0.4 then
            local passPed, passNetId = ctx.spawnPed(PickRandom(pedModels), vector3(c.x - 2.0, c.y, c.z), c.w, {
                suspect = true, surrender = surrender,
            })
            EnsureControl(passPed)
            SetPedIntoVehicle(passPed, veh, 0)
            occupants[2] = { ped = passPed, netId = passNetId }
        end

        TaskVehicleDriveWander(driverPed, veh, 15.0, 786603)

        local fleeing, fleeStart, stopped = false, 0, false
        ctx.onTick(function()
            if stopped or not DoesEntityExist(driverPed) or IsEntityDead(driverPed) then return end
            if Entity(driverPed).state['ws:surrendered'] then return end

            -- Verfolgungsjagd beginnt, sobald ein Officer nahe kommt.
            -- Fluchtstart nur bei voller Kontrolle ueber Ped UND Fahrzeug -
            -- sonst im naechsten Tick erneut versuchen.
            if not fleeing and #(GetEntityCoords(driverPed) - GetEntityCoords(cache.ped)) < 40.0 then
                if EnsureControl(driverPed) and EnsureControl(veh) then
                    fleeing = true
                    fleeStart = GetGameTimer()
                    SetVehicleEngineOn(veh, true, true, false)
                    ClearPedTasks(driverPed)
                    TaskVehicleMissionPedTarget(driverPed, veh, cache.ped, 8, 80.0, 786468, 20.0, 20.0, true)
                    SetPedKeepTask(driverPed, true)
                end
            end

            if not fleeing or not IsPedInVehicle(driverPed, veh, false) then return end

            -- Aufgabe-Bedingungen: Motor kaputt, 2+ Reifen platt oder 2 Minuten Flucht
            local burst = 0
            for _, w in ipairs({ 0, 1, 4, 5 }) do
                if IsVehicleTyreBurst(veh, w, false) then burst = burst + 1 end
            end
            if GetVehicleEngineHealth(veh) < 300.0 or burst >= 2 or (GetGameTimer() - fleeStart) > 120000 then
                stopped = true
                if EnsureControl(driverPed) then
                    TaskVehicleTempAction(driverPed, veh, 27, 4000) -- anhalten
                end
                SetTimeout(4500, function()
                    for _, o in ipairs(occupants) do
                        if DoesEntityExist(o.ped) and not IsEntityDead(o.ped) and EnsureControl(o.ped) then
                            TaskLeaveVehicle(o.ped, veh, 256)
                        end
                    end
                    SetTimeout(2000, function()
                        -- Jeder Insasse entscheidet einzeln: Fussflucht oder Aufgabe
                        for _, o in ipairs(occupants) do
                            if DoesEntityExist(o.ped) and not IsEntityDead(o.ped) then
                                if math.random() < 0.5 then
                                    if EnsureControl(o.ped) then
                                        TaskSmartFleePed(o.ped, cache.ped, 120.0, -1, false, false)
                                    end
                                else
                                    local meta = ctx.suspects[o.netId]
                                    if meta then ctx.setSurrendered(meta) end
                                end
                            end
                        end
                    end)
                end)
            end
        end)
    end,
})
