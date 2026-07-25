lib.locale()

-- Wiederbelebung handlungsunfaehiger Spieler ("am Boden"). Der Zustand selbst
-- wird von ws_core verwaltet (client/downed.lua) - hier ist die Sanitaeter-
-- Seite: Notruf-Blip, Zieloption und Behandlung.

local CFG = WSConfig.Downed or { enabled = false }

local function isOnDuty()
    return LocalPlayer.state['ws:job'] == 'ambulance' and LocalPlayer.state['ws:duty'] == true
end

local function medLevel()
    return LocalPlayer.state['ws:skill_medic'] or 0
end

-- Der Notruf selbst laeuft ueber die regulaere Notfall-Engine
-- (ws_ems/server/callouts.lua, Typ 'player_rescue'): Angebot an alle
-- Sanitaeter, Annahme mit Y, Blip + Route wie bei jedem anderen Einsatz.
-- Hier bleibt nur die Behandlung am Spieler.

local function isDowned(serverId)
    return Player(serverId).state['ws:downed'] == true
end

local function revive(ped)
    local playerIdx = NetworkGetPlayerIndexFromPed(ped)
    if playerIdx == -1 then return end
    local serverId = GetPlayerServerId(playerIdx)
    if not isDowned(serverId) then return end

    TriggerServerEvent('ws_core:reviveProgress', serverId, true)

    -- Medizin-Skill verkuerzt die Behandlung (wie bei NPC-Patienten)
    local duration = math.floor((CFG.reviveDuration or 10000) * (1.0 - 0.15 * medLevel()))
    local ok = lib.progressBar({
        duration = duration,
        label = locale('revive_running'),
        canCancel = true,
        disable = { move = true, combat = true, car = true },
        anim = { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest', flag = 1 },
    })

    if not ok then
        TriggerServerEvent('ws_core:reviveProgress', serverId, false)
        return
    end

    -- Abschluss wie bei der Reanimation: Defibrillator-Minispiel
    local success = WSSkillCheck(WSEms.DefiChecks)
    if success == nil then
        TriggerServerEvent('ws_core:reviveProgress', serverId, false)
        lib.notify({ title = locale('revive_title'), description = locale('defi_unavailable'), type = 'error' })
        return
    end
    if not success then
        TriggerServerEvent('ws_core:reviveProgress', serverId, false)
        lib.notify({ title = locale('revive_title'), description = locale('revive_failed'), type = 'error' })
        return
    end

    -- Zwischenzeitlich verstorben/wiederbelebt? Dann nichts mehr tun
    if not isDowned(serverId) then
        lib.notify({ title = locale('revive_title'), description = locale('revive_gone'), type = 'error' })
        return
    end

    TriggerServerEvent('ws_core:requestRevive', serverId)
    lib.notify({ title = locale('revive_title'), description = locale('revive_done'), type = 'success' })
end

exports.ox_target:addGlobalPlayer({
    {
        name = 'ws_ems_revive',
        label = locale('revive_option'),
        icon = 'fa-solid fa-heart-circle-plus',
        distance = 2.0,
        canInteract = function(entity)
            if not CFG.enabled or not isOnDuty() then return false end
            local idx = NetworkGetPlayerIndexFromPed(entity)
            if idx == -1 then return false end
            return isDowned(GetPlayerServerId(idx))
        end,
        onSelect = function(data) revive(data.entity) end,
    },
})
