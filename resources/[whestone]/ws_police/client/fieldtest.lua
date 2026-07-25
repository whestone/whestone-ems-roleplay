-- Alkoholtest: an einer angehaltenen Person durchfuehren (ox_target).
-- Rein clientseitige Flavor-Aktion mit zufaelligem Ergebnis.

lib.locale()

local tested = {} -- ped -> Ergebnis, damit dasselbe Ergebnis bestehen bleibt

local function runBreathalyzer(ped)
    local ok = lib.progressBar({
        duration = 5000,
        label = locale('breath_running'),
        canCancel = true,
        disable = { move = true, combat = true },
        anim = { dict = 'mp_common', clip = 'givetake1_a', flag = 49 },
    })
    if not ok then return end

    -- Ergebnis je Ped einmalig festlegen (0.0 - 2.0 Promille)
    local promille = tested[ped]
    if not promille then
        promille = math.random() < 0.45 and (math.random(50, 200) / 100) or (math.random(0, 45) / 100)
        tested[ped] = promille
    end

    local text = ('%.2f'):format(promille):gsub('%.', ',')
    if promille >= 0.5 then
        lib.notify({ title = locale('breath_title'), description = locale('breath_result_pos', text), type = 'error', duration = 8000 })
    else
        lib.notify({ title = locale('breath_title'), description = locale('breath_result_neg', text), type = 'success', duration = 8000 })
    end
end

exports.ox_target:addGlobalPed({
    {
        name = 'ws_breathalyzer',
        label = locale('breath_target'),
        icon = 'fa-solid fa-wine-bottle',
        canInteract = function(entity)
            return LocalPlayer.state['ws:job'] == 'police' and LocalPlayer.state['ws:duty'] == true
                and not IsPedAPlayer(entity)
                and not IsEntityDead(entity)
                and not Entity(entity).state['ws:suspect']
                -- waehrend einer Verkehrskontrolle laeuft der Alkoholtest ueber das Kontrollmenue
                and not Entity(entity).state['ws:trafficstop']
        end,
        onSelect = function(data) runBreathalyzer(data.entity) end,
    },
})
