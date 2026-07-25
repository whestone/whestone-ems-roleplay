lib.locale()

-- Handlungsunfaehig ("am Boden"): Statt sofort zu sterben, geht der Spieler zu
-- Boden und blutet aus. Ein Sanitaeter kann ihn wiederbeleben.
--
-- Ablauf: Tod erkannt -> Spieler an Ort und Stelle wiederbelebt (damit der
-- spawnmanager NICHT den Respawn ausloest) -> Downed-Zustand mit Countdown.
-- Laeuft die Zeit ab oder gibt der Spieler auf, wird der Tod echt vollzogen
-- und der normale Respawn-Pfad in main.lua uebernimmt.

local CFG = WSConfig.Downed or { enabled = false }

-- Von main.lua (autoSpawnCallback) genutzt, damit der Respawn nicht
-- losrennt, waehrend wir den Spieler zu Boden schicken.
WSDowned = { active = false }

local downedSince = 0
local reviving = false

-- Nach Ausbluten/Aufgeben wird der Tod echt vollzogen (Gesundheit 0). Der
-- darauf folgende Spawn-Callback darf den Spieler NICHT erneut zu Boden
-- schicken - sonst haengt man in einer Endlosschleife fest. Das Flag laesst
-- genau einen Todesfall zum normalen Respawn durch.
local finalDeath = false

local ANIM_DICT = 'combat@damage@writhe'
local ANIM_CLIP = 'writhe_loop'

local function clearVisuals()
    ClearTimecycleModifier()
    AnimpostfxStop('DeathFailOut')
    SetPedMinGroundTimeForStungun(cache.ped, 0)
end

-- Grafische Oberflaeche (NUI in html/jobselect.html): Countdown + Auswahl
-- "Auf Hilfe warten" / "Aufgeben". Nach "Warten" wird der Mausfokus wieder
-- freigegeben, damit der Spieler sich umsehen kann - das Overlay bleibt.
local function openDownedUi()
    SendNUIMessage({
        action = 'openDowned',
        bleedout = CFG.bleedoutTime,
        giveUpAfter = CFG.giveUpAfter or 0,
    })
    SetNuiFocus(true, true)
end

local function closeDownedUi()
    SendNUIMessage({ action = 'closeDowned' })
    SetNuiFocus(false, false)
end

-- Bewegung/Waffen sperren, Ped am Boden halten
local function holdDownedPed()
    CreateThread(function()
        local animOk = pcall(lib.requestAnimDict, ANIM_DICT, 2000)
        while WSDowned.active do
            local ped = cache.ped
            if animOk and not IsEntityPlayingAnim(ped, ANIM_DICT, ANIM_CLIP, 3) then
                TaskPlayAnim(ped, ANIM_DICT, ANIM_CLIP, 8.0, -8.0, -1, 1, 0.0, false, false, false)
            elseif not animOk and not IsPedRagdoll(ped) then
                SetPedToRagdoll(ped, 60000, 60000, 0, false, false, false)
            end

            DisableAllControlActions(0)
            -- Umsehen, Chat und Menues bleiben erlaubt
            EnableControlAction(0, 1, true)   -- Kamera X
            EnableControlAction(0, 2, true)   -- Kamera Y
            EnableControlAction(0, 245, true) -- Chat
            EnableControlAction(0, 249, true) -- Push-to-Talk

            -- G holt die Auswahl zurueck. Ueber IsDisabledControlJustPressed,
            -- weil ein normaler Keybind durch DisableAllControlActions
            -- geschluckt wuerde.
            if IsDisabledControlJustPressed(0, 47) then
                SendNUIMessage({ action = 'focusDowned' })
                SetNuiFocus(true, true)
            end
            Wait(0)
        end
    end)
end

-- Endgueltiger Tod: normaler Respawn-Pfad (main.lua) uebernimmt
local function finishDeath()
    if not WSDowned.active then return end
    WSDowned.active = false
    finalDeath = true
    LocalPlayer.state:set('ws:downed', false, true)
    TriggerServerEvent('ws_core:downedEnded')
    closeDownedUi()
    clearVisuals()
    ClearPedTasksImmediately(cache.ped)
    SetEntityInvincible(cache.ped, false)
    SetEntityHealth(cache.ped, 0)
end

-- Wiederbelebt durch einen Sanitaeter
RegisterNetEvent('ws_core:revived', function()
    if not WSDowned.active then return end
    WSDowned.active = false
    reviving = false
    LocalPlayer.state:set('ws:downed', false, true)
    closeDownedUi()
    clearVisuals()

    local ped = cache.ped
    ClearPedTasksImmediately(ped)
    SetEntityInvincible(ped, false)
    SetEntityHealth(ped, math.floor(GetEntityMaxHealth(ped) * (CFG.reviveHealth or 0.5)))
    SetPedArmour(ped, 0)
    lib.notify({ title = locale('downed_title'), description = locale('downed_revived'), type = 'success' })
end)

-- Sanitaeter hat die Behandlung begonnen/abgebrochen (nur Anzeige)
RegisterNetEvent('ws_core:reviveProgress', function(state)
    reviving = state == true
    if WSDowned.active then
        SendNUIMessage({ action = 'treatedDowned', treated = reviving })
    end
end)

-- Von main.lua aufgerufen, sobald der Spieler als tot erkannt wird.
-- Rueckgabe true = Downed-System uebernimmt, kein Respawn ausloesen.
function WSDowned.handleDeath()
    if finalDeath then
        finalDeath = false
        return false -- dieser Tod ist endgueltig: normal respawnen
    end
    if not CFG.enabled or WSDowned.active then return WSDowned.active end

    local ped = cache.ped
    local pos = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    -- An Ort und Stelle wiederbeleben, sonst greift der Auto-Respawn
    NetworkResurrectLocalPlayer(pos.x, pos.y, pos.z, heading, true, false)
    SetEntityHealth(ped, math.floor(GetEntityMaxHealth(ped) * 0.35))
    SetEntityInvincible(ped, true) -- am Boden nicht weiter verwundbar
    ClearPedBloodDamage(ped)

    WSDowned.active = true
    reviving = false
    downedSince = GetGameTimer()
    LocalPlayer.state:set('ws:downed', true, true)

    SetTimecycleModifier('REDMIST')
    AnimpostfxPlay('DeathFailOut', 0, true)
    holdDownedPed()
    openDownedUi()

    TriggerServerEvent('ws_core:playerDowned')
    lib.notify({
        title = locale('downed_title'),
        description = locale('downed_alerted'),
        type = 'error',
        duration = 10000,
    })

    -- Ausbluten-Countdown
    CreateThread(function()
        local deadline = GetGameTimer() + CFG.bleedoutTime * 1000
        while WSDowned.active and GetGameTimer() < deadline do
            Wait(500)
        end
        if WSDowned.active then finishDeath() end
    end)

    return true
end

-- Aufgeben: erst nach giveUpAfter Sekunden, damit niemand den Notruf
-- sofort wegdrueckt, bevor der Rettungsdienst ueberhaupt reagieren kann
local function giveUp()
    if not WSDowned.active then return end
    local waited = math.floor((GetGameTimer() - downedSince) / 1000)
    if waited < (CFG.giveUpAfter or 0) then
        lib.notify({
            title = locale('downed_title'),
            description = locale('downed_giveup_wait', (CFG.giveUpAfter or 0) - waited),
            type = 'error',
        })
        return
    end
    finishDeath()
end

RegisterNUICallback('downedChoice', function(body, cb)
    cb({})
    if not WSDowned.active then
        SetNuiFocus(false, false)
        return
    end
    if body and body.choice == 'giveup' then
        giveUp()
    else
        -- "Warten": Fokus abgeben, Overlay laeuft ohne Maus weiter
        SetNuiFocus(false, false)
    end
end)

-- Fallback per Chat, falls die Oberflaeche einmal nicht reagiert
RegisterCommand('aufgeben', giveUp, false)

AddEventHandler('onResourceStop', function(res)
    if res ~= cache.resource then return end
    if WSDowned.active then
        WSDowned.active = false
        clearVisuals()
        SetEntityInvincible(cache.ped, false)
    end
end)
