lib.locale()

local character
local firstSpawn = true
local spawning = false

local function jobSpawn(job)
    local j = WSConfig.Jobs[job]
    return (j and j.spawn) or WSConfig.DefaultSpawn
end

-- Fraktions-Auswahl (LSPD / EMS): Vollbild-NUI mit Laufbahn-Anzeige.
-- Blockiert per Promise, bis der Spieler eine Karte anklickt.
local jobSelectPromise

RegisterNUICallback('jobSelected', function(body, cb)
    cb({})
    SetNuiFocus(false, false)
    if jobSelectPromise then
        local p = jobSelectPromise
        jobSelectPromise = nil
        p:resolve((body and body.job) or WSConfig.DefaultJob)
    end
end)

-- Grafische Fahrzeugauswahl (Garage/Helipad), genutzt von ws_police/ws_ems.
-- Liefert das gewaehlte Modell, '__return' (Rueckgabe) oder nil (Abbruch).
local vehicleSelectPromise

RegisterNUICallback('vehicleSelected', function(body, cb)
    cb({})
    SetNuiFocus(false, false)
    if vehicleSelectPromise then
        local p = vehicleSelectPromise
        vehicleSelectPromise = nil
        p:resolve(body and body.model or nil)
    end
end)

exports('OpenVehicleSelect', function(data)
    if vehicleSelectPromise or jobSelectPromise then return nil end
    vehicleSelectPromise = promise.new()
    SendNUIMessage({
        action = 'openVehicleSelect',
        title = data.title,
        accent = data.accent,
        fallback = data.fallback,
        imageBase = data.imageBase, -- 'vehicles' (Standard) oder 'peds'
        returnLabel = data.returnLabel,
        vehicles = data.vehicles,
    })
    SetNuiFocus(true, true)
    return Citizen.Await(vehicleSelectPromise)
end)

-- Auswahl-Lobby auf dem Maze-Bank-Tower-Dach: eingefroren, unverwundbar und
-- (per Routing-Bucket, serverseitig) fuer alle anderen Spieler unsichtbar.
local inSelectionLobby = false

-- Sperren setzen, ohne zu teleportieren - beim Beitritt spawnt man bereits
-- direkt in der Lobby, dann waere ein zweiter Teleport nur eine Extra-Blende.
local function applyLobbyState()
    local ped = cache.ped
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetPlayerInvincible(cache.playerId, true)
    ClearPedTasksImmediately(ped)
    inSelectionLobby = true
end

local function enterSelectionLobby()
    local lobby = WSConfig.JobSelectLobby
    if not lobby or inSelectionLobby then return end

    DoScreenFadeOut(400)
    local t = GetGameTimer() + 1500
    while not IsScreenFadedOut() and GetGameTimer() < t do Wait(25) end

    lib.callback.await('ws_core:enterSelection', false)

    local ped = cache.ped
    SetEntityCoords(ped, lobby.x, lobby.y, lobby.z, false, false, false, false)
    SetEntityHeading(ped, lobby.w)

    -- Kollision abwarten, sonst faellt man durch das Dach
    RequestCollisionAtCoord(lobby.x, lobby.y, lobby.z)
    t = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < t do Wait(25) end

    applyLobbyState()
    Wait(250)
    DoScreenFadeIn(700)
end

local function leaveSelectionLobby()
    inSelectionLobby = false
    if not WSConfig.JobSelectLobby then return end
    local ped = cache.ped
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    SetPlayerInvincible(cache.playerId, false)
end

local function chooseJob(defaultJob)
    local careers = lib.callback.await('ws_core:getCareers', false)
    enterSelectionLobby()
    jobSelectPromise = promise.new()

    SendNUIMessage({ action = 'openJobSelect', careers = careers })
    SetNuiFocus(true, true)

    -- Sicherheitsnetz: nach 2 Minuten ohne Wahl automatisch Standard-Job
    SetTimeout(120000, function()
        if jobSelectPromise then
            local p = jobSelectPromise
            jobSelectPromise = nil
            SendNUIMessage({ action = 'closeJobSelect' })
            SetNuiFocus(false, false)
            p:resolve(defaultJob or WSConfig.DefaultJob)
        end
    end)

    local job = Citizen.Await(jobSelectPromise)
    -- setJob holt den Spieler serverseitig auch aus dem Auswahl-Bucket zurueck
    lib.callback.await('ws_core:setJob', false, job)
    leaveSelectionLobby()
    return job
end

-- Fraktions-Auswahl NACH dem ersten Spawn (ein Dialog waehrend des
-- Ladebildschirms blockiert den Beitritt bei "Awaiting Scripts"!)
local joinJobSelectPending = WSConfig.JobSelectOnJoin

local function jobSelectAfterJoin()
    CreateThread(function()
        while GetIsLoadingScreenActive() do Wait(250) end
        while not IsScreenFadedIn() do Wait(250) end
        Wait(1000)

        local prevJob = (character and character.job) or WSConfig.DefaultJob
        local job = chooseJob(prevJob)

        -- Aus der Auswahl-Lobby (Maze Bank Tower) muss IMMER zur Station
        -- zurueckgesetzt werden - auch wenn dieselbe Fraktion gewaehlt wurde.
        if WSConfig.JobSelectLobby or job ~= prevJob then
            DoScreenFadeOut(400)
            Wait(450)
            local s = jobSpawn(job)
            SetEntityCoords(cache.ped, s.x, s.y, s.z, false, false, false, false)
            SetEntityHeading(cache.ped, s.w)
            RequestCollisionAtCoord(s.x, s.y, s.z)
            local t = GetGameTimer() + 3000
            while not HasCollisionLoadedAroundEntity(cache.ped) and GetGameTimer() < t do Wait(25) end
            Wait(200)
            DoScreenFadeIn(400)
        end
        if character then character.job = job end
    end)
end

local function spawnCharacter(afterDeath)
    character = lib.callback.await('ws_core:requestCharacter', false)

    local spawn
    local toLobby = false
    if afterDeath then
        spawn = WSConfig.DeathSpawn
    elseif joinJobSelectPending and WSConfig.JobSelectLobby then
        -- Direkt in der Auswahl-Lobby spawnen. Sonst steht man beim Beitritt
        -- kurz sichtbar an der Station der zuletzt gespielten Fraktion,
        -- bevor der Auswahlbildschirm aufgeht.
        spawn = WSConfig.JobSelectLobby
        toLobby = true
        lib.callback.await('ws_core:enterSelection', false) -- Bucket vor dem Spawn
    elseif not WSConfig.AlwaysSpawnAtStation and character and character.position then
        local p = character.position
        spawn = vector4(p.x, p.y, p.z, p.w or 0.0)
    else
        spawn = jobSpawn(character and character.job)
    end

    exports.spawnmanager:spawnPlayer({
        x = spawn.x, y = spawn.y, z = spawn.z,
        heading = spawn.w,
        model = `mp_m_freemode_01`,
    }, function()
        SetPedDefaultComponentVariation(cache.ped)
        SetEntityHealth(cache.ped, GetEntityMaxHealth(cache.ped))
        if toLobby then applyLobbyState() end
        if afterDeath then
            RemoveAllPedWeapons(cache.ped, true)
            lib.notify({
                title = locale('respawn_title'),
                description = locale('respawn_desc'),
                type = 'inform',
            })
        end
        if not IsScreenFadedIn() then DoScreenFadeIn(800) end
        spawning = false

        -- Fraktions-Auswahl erst nach abgeschlossenem Beitritt anzeigen
        if joinJobSelectPending and not afterDeath then
            joinJobSelectPending = false
            jobSelectAfterJoin()
        end
    end)
end

-- Der Autospawn-Callback feuert mehrfach, solange der Spieler als tot gilt.
-- Ohne Guard + Totencheck wird man daher nach dem Respawn wiederholt
-- ins Krankenhaus zurueckgesetzt.
exports.spawnmanager:setAutoSpawnCallback(function()
    if spawning then return end

    if firstSpawn then
        firstSpawn = false
        spawning = true
        spawnCharacter(false)
    elseif IsEntityDead(cache.ped) then
        -- Zuerst das Downed-System: geht der Spieler zu Boden, wird er an Ort
        -- und Stelle wiederbelebt und es findet (noch) kein Respawn statt.
        -- Erst wenn er ausblutet oder aufgibt, laeuft dieser Pfad weiter.
        if WSDowned and WSDowned.handleDeath() then return end

        spawning = true
        -- Sicherheitsnetz, falls der Spawn-Abschluss nie gemeldet wird
        SetTimeout(20000, function() spawning = false end)

        -- Weder WASTED-Overlay noch Schwarzblende/Wartezeit: der
        -- Handlungsunfaehig-Screen hatte bereits seinen eigenen Countdown.
        spawnCharacter(true)
    end
end)
exports.spawnmanager:setAutoSpawn(true)
exports.spawnmanager:forceRespawn()

RegisterNetEvent('ws_core:client:dutyChanged', function(onDuty)
    lib.notify({
        title = locale('duty_title'),
        description = onDuty and locale('duty_on') or locale('duty_off'),
        type = onDuty and 'success' or 'inform',
    })
end)

AddEventHandler('onResourceStop', function(res)
    if res == cache.resource then
        SetNuiFocus(false, false)
    end
end)

-- Ausdauer-Skill: regeneriert die Sprint-Stamina je nach Stufe
CreateThread(function()
    while true do
        Wait(1000)
        local regen = WSConfig.StaminaRegen[LocalPlayer.state['ws:skill_stamina'] or 0]
        if regen then
            RestorePlayerStamina(cache.playerId, regen)
        end
    end
end)

-- Fraktion wechseln (respawnt an der neuen Station)
RegisterCommand('dienst', function()
    if spawning then return end
    character = lib.callback.await('ws_core:requestCharacter', false)
    chooseJob(character and character.job)
    spawning = true
    DoScreenFadeOut(400)
    Wait(450)
    spawnCharacter(false)
end, false)

-- Charakteruebersicht
RegisterCommand('charinfo', function()
    character = lib.callback.await('ws_core:requestCharacter', false)
    if not character then return end
    lib.notify({
        title = character.name,
        description = locale('char_info', character.rankLabel, character.xp),
        type = 'inform',
        duration = 8000,
    })
end, false)
