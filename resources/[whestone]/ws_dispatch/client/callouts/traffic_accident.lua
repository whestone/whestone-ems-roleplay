local wreckModels = { 'primo', 'blista', 'asea', 'premier', 'ingot', 'asterope', 'fugitive', 'regina' }
local pedModels = { 'a_m_y_stbla_02', 'a_f_y_tourist_01', 'a_m_m_business_01', 'a_f_y_business_02', 'a_m_y_downtown_01', 'a_f_m_bevhills_01' }
local bystanderScenarios = { 'WORLD_HUMAN_MOBILE_FILM_SHOCKING', 'WORLD_HUMAN_STAND_MOBILE', 'WORLD_HUMAN_HANG_OUT_STREET' }

RegisterCalloutHandler('traffic_accident', {
    onStart = function(ctx)
        local c = ctx.coords

        -- Feste Slots, zufaellig belegt: 1-3 Wracks, 1-2 Verletzte, 0-2 Zeugen
        local wreckSlots = {
            { 2.0, 1.5, 35.0 },
            { -3.5, -2.5, 290.0 },
            { 5.0, -4.0, 150.0 },
        }
        local injuredSlots = { { 0.5, -1.0 }, { -2.0, 3.0 } }
        local bystanderSlots = { { -1.5, 2.5 }, { 3.5, 3.0 } }

        for i = 1, math.random(1, #wreckSlots) do
            local s = wreckSlots[i]
            ctx.spawnVehicle(PickRandom(wreckModels), vector3(c.x + s[1], c.y + s[2], c.z), (c.w + s[3]) % 360.0, { wreck = true })
        end

        for i = 1, math.random(1, #injuredSlots) do
            local s = injuredSlots[i]
            ctx.spawnPed(PickRandom(pedModels), vector3(c.x + s[1], c.y + s[2], c.z), 0.0, { injured = true })
        end

        for i = 1, math.random(0, #bystanderSlots) do
            local s = bystanderSlots[i]
            local bystander = ctx.spawnPed(PickRandom(pedModels), vector3(c.x + s[1], c.y + s[2], c.z), 180.0)
            TaskStartScenarioInPlace(bystander, PickRandom(bystanderScenarios), 0, true)
        end
    end,
})
