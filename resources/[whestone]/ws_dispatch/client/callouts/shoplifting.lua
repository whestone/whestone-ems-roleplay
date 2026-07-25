local models = { 'a_m_y_skater_01', 'a_m_y_downtown_01', 'a_f_y_skater_01', 'a_m_y_salton_01', 'a_m_y_mexthug_01' }

RegisterCalloutHandler('shoplifting', {
    onStart = function(ctx)
        local c = ctx.coords
        local slots = { { 0.0, 0.0 }, { 1.5, 1.0 } }

        -- 1-2 Ladendiebe
        local thieves = {}
        for i = 1, math.random(1, #slots) do
            local s = slots[i]
            local ped = ctx.spawnPed(PickRandom(models), vector3(c.x + s[1], c.y + s[2], c.z), c.w, {
                suspect = true,
                surrender = { onStun = true, proximity = 6 },
            })
            thieves[#thieves + 1] = { ped = ped, fleeing = false }
        end

        ctx.onTick(function()
            for _, t in ipairs(thieves) do
                if not t.fleeing and DoesEntityExist(t.ped) and not IsEntityDead(t.ped)
                    and not Entity(t.ped).state['ws:surrendered']
                    and #(GetEntityCoords(t.ped) - GetEntityCoords(cache.ped)) < 20.0 then
                    -- Flieht zu Fuss, sobald ein Officer nahe kommt
                    t.fleeing = true
                    if EnsureControl(t.ped) then
                        TaskSmartFleePed(t.ped, cache.ped, 150.0, -1, false, false)
                    end
                end
            end
        end)
    end,
})
