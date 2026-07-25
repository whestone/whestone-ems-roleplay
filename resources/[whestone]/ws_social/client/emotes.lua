lib.locale()

-- Emote-System: selbstbestimmte Animationen an der Wache und unterwegs.
-- Reines Rollenspiel-Flavor, keine XP. Jede Bewegung beendet das Emote.

local emoting = false

local function stopEmote()
    if not emoting then return end
    emoting = false
    ClearPedTasks(cache.ped)
end

-- Bricht das Emote ab, sobald der Spieler sich bewegt, springt, angreift
-- oder in ein Fahrzeug steigt.
local function watchForMovement()
    CreateThread(function()
        Wait(300) -- kurze Schonfrist, sonst bricht das Startframe sofort ab
        while emoting do
            if IsPedInAnyVehicle(cache.ped, false)
                or IsControlPressed(0, 32) or IsControlPressed(0, 33)   -- W / S
                or IsControlPressed(0, 34) or IsControlPressed(0, 35)   -- A / D
                or IsControlPressed(0, 22) or IsControlPressed(0, 24)   -- Springen / Angriff
                or IsControlPressed(0, 21) then                          -- Sprinten
                stopEmote()
                break
            end
            Wait(100)
        end
    end)
end

local function playEmote(emote)
    if IsPedInAnyVehicle(cache.ped, false) then
        lib.notify({ title = locale('emote_title'), description = locale('emote_no_vehicle'), type = 'error' })
        return
    end
    stopEmote()
    local ped = cache.ped

    if emote.scenario then
        TaskStartScenarioInPlace(ped, emote.scenario, 0, true)
    elseif emote.anim then
        if not lib.requestAnimDict(emote.anim.dict, 3000) then return end
        TaskPlayAnim(ped, emote.anim.dict, emote.anim.clip, 8.0, -8.0, -1, emote.anim.flag or 1, 0.0, false, false, false)
    else
        return
    end

    emoting = true
    watchForMovement()
    lib.notify({ title = locale('emote_title'), description = locale('emote_started', emote.label), type = 'inform' })
end

-- ---------------------------------------------------------------------------
-- Menue
-- ---------------------------------------------------------------------------

local function buildOptions(list)
    local opts = {}
    for _, e in ipairs(list) do
        opts[#opts + 1] = {
            title = e.label,
            icon = 'person',
            onSelect = function() playEmote(e) end,
        }
    end
    return opts
end

local function openEmoteMenu()
    local job = LocalPlayer.state['ws:job']
    local options = buildOptions(WSSocial.Emotes.general)

    local jobEmotes = WSSocial.Emotes[job]
    if jobEmotes then
        for _, o in ipairs(buildOptions(jobEmotes)) do options[#options + 1] = o end
    end

    options[#options + 1] = {
        title = locale('emote_stop'),
        icon = 'ban',
        onSelect = stopEmote,
    }

    lib.registerContext({ id = 'ws_social_emotes', title = locale('emote_menu_title'), options = options })
    lib.showContext('ws_social_emotes')
end

RegisterCommand('emotes', openEmoteMenu, false)
RegisterKeyMapping('emotes', 'Emote-Menü öffnen', 'keyboard', 'F3')

RegisterCommand('stopemote', stopEmote, false)

AddEventHandler('onResourceStop', function(res)
    if res == cache.resource then stopEmote() end
end)
