local models = { 'g_m_y_ballaeast_01', 'g_m_y_ballaorig_01', 'g_m_y_mexgang_01', 'g_m_y_salvagoon_01' }

RegisterCalloutHandler('armed_robbery', {
    onStart = function(ctx)
        local c = ctx.coords
        local slots = { { 0.0, 0.0 }, { 1.5, 1.0 }, { -1.5, 1.5 } }

        -- 1-3 bewaffnete Taeter, 25% Chance auf Schrotflinte statt Pistole
        local robbers = {}
        for i = 1, math.random(1, #slots) do
            local s = slots[i]
            local weapon = math.random() < 0.25 and 'WEAPON_SAWNOFFSHOTGUN' or 'WEAPON_PISTOL'
            local ped, netId = ctx.spawnPed(PickRandom(models), vector3(c.x + s[1], c.y + s[2], c.z), c.w, {
                suspect = true, hostile = true, weapon = weapon, accuracy = 10,
                surrender = { onStun = true, lowHealth = 0.4 },
            })
            robbers[#robbers + 1] = { ped = ped, netId = netId }
        end

        local engaged = false
        ctx.onTick(function()
            if engaged then return end
            for _, r in ipairs(robbers) do
                if DoesEntityExist(r.ped) and not IsEntityDead(r.ped)
                    and #(GetEntityCoords(r.ped) - GetEntityCoords(cache.ped)) < 40.0 then
                    engaged = true
                    break
                end
            end
            if not engaged then return end

            -- Jeder Taeter entscheidet einzeln: 60% Widerstand, 40% Fussflucht
            for _, r in ipairs(robbers) do
                if DoesEntityExist(r.ped) and not IsEntityDead(r.ped) and EnsureControl(r.ped) then
                    if math.random() < 0.4 then
                        local meta = ctx.suspects[r.netId]
                        if meta and meta.opts.surrender then
                            meta.opts.surrender.proximity = 8
                        end
                        TaskSmartFleePed(r.ped, cache.ped, 150.0, -1, false, false)
                    else
                        SetPedCombatAttributes(r.ped, 46, true)
                        TaskCombatPed(r.ped, cache.ped, 0, 16)
                    end
                end
            end
        end)
    end,
})
