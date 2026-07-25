local models = { 'a_m_y_mexthug_01', 'a_m_m_skater_01', 'a_m_y_downtown_01', 'a_m_y_salton_01', 'a_m_m_socenlat_01' }

RegisterCalloutHandler('brawl', {
    onStart = function(ctx)
        local c = ctx.coords
        local surrender = { onStun = true, lowHealth = 0.5, proximity = 10 }

        -- 2-4 Schlaeger im Kreis, jeder prueglet auf seinen Nachbarn ein
        local count = math.random(2, 4)
        local peds = {}
        for i = 1, count do
            local angle = (i - 1) * (2 * math.pi / count)
            local x = c.x + math.cos(angle) * 1.4
            local y = c.y + math.sin(angle) * 1.4
            local heading = (math.deg(angle) + 180.0) % 360.0
            peds[i] = ctx.spawnPed(PickRandom(models), vector3(x, y, c.z), heading, { suspect = true, surrender = surrender })
            SetPedCombatAttributes(peds[i], 46, true)
        end
        for i = 1, count do
            TaskCombatPed(peds[i], peds[(i % count) + 1], 0, 16)
        end
    end,
})
