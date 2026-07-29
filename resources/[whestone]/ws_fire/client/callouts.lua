lib.locale()

-- Feuerwehr-Einsaetze: Angebot/Annahme (wie EMS), Szene mit grossen Flammen
-- (Feuer-Partikel + echtes Skriptfeuer). Jeder Brandherd hat "Leben"; die
-- Loeschmechanik (firefighting.lua) ruft WSFire.spray, bis er aus ist.

local currentAssignment
local currentBlip
local lastOffer
local activeScene

local function isFireOnDuty()
    return LocalPlayer.state['ws:job'] == 'fire' and LocalPlayer.state['ws:duty'] == true
end

local function removeBlip()
    if currentBlip then RemoveBlip(currentBlip) currentBlip = nil end
end

local function fnotify(key, ntype, ...)
    lib.notify({ title = locale('fire_title'), description = locale(key, ...), type = ntype or 'inform' })
end

-- ---------------------------------------------------------------------------
-- Angebote
-- ---------------------------------------------------------------------------

RegisterNetEvent('ws_fire:offer', function(offer)
    lastOffer = offer
    local street = GetStreetNameFromHashKey(GetStreetNameAtCoord(offer.coords.x, offer.coords.y, offer.coords.z))
    lib.notify({
        id = 'ws_fire_offer',
        title = ('%s – %s'):format(offer.code, offer.label),
        description = locale('offer_desc', street),
        type = 'warning', icon = 'fire', duration = 15000,
    })
    PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', false)
end)

RegisterNetEvent('ws_fire:offerTaken', function(uid, byName)
    if lastOffer and lastOffer.uid == uid then fnotify('offer_taken', 'inform', byName) end
end)

RegisterNetEvent('ws_fire:offerExpired', function(uid)
    if lastOffer and lastOffer.uid == uid then
        lastOffer = nil
        fnotify('offer_expired', 'error')
    end
end)

-- Gleiche Taste wie Polizei/EMS (Y auf QWERTZ = physisches Z); die Job-Pruefung
-- laesst immer nur das passende System reagieren.
RegisterCommand('brand_annehmen', function()
    if not isFireOnDuty() then return end
    if not lastOffer then return fnotify('no_offer', 'error') end
    TriggerServerEvent('ws_fire:accept', lastOffer.uid)
end, false)
RegisterKeyMapping('brand_annehmen', 'Feuerwehr: Einsatz annehmen', 'keyboard', 'Z')

-- ---------------------------------------------------------------------------
-- Szene (echtes Feuer)
-- ---------------------------------------------------------------------------

-- Grosse, DAUERHAFTE Flammen ueber Partikel (StartScriptFire ist klein, brennt
-- von selbst aus und hat ein globales Limit). Zusaetzlich ein echtes Skript-
-- feuer je Herd fuer Hitze/Rauch. Beides wird beim Loeschen entfernt.
local FIRE_ASSET = 'core'
local FIRE_EFFECT = 'fire_wrecked_car'

local function ensureFireAsset()
    if HasNamedPtfxAssetLoaded(FIRE_ASSET) then return true end
    RequestNamedPtfxAsset(FIRE_ASSET)
    local t = GetGameTimer() + 3000
    while not HasNamedPtfxAssetLoaded(FIRE_ASSET) and GetGameTimer() < t do Wait(50) end
    return HasNamedPtfxAssetLoaded(FIRE_ASSET)
end

local function spawnFireFx(x, y, z, scale)
    UseParticleFxAsset(FIRE_ASSET)
    return StartParticleFxLoopedAtCoord(FIRE_EFFECT, x, y, z, 0.0, 0.0, 0.0, scale, false, false, false, false)
end

local function startScene(callout)
    local ctx = { uid = callout.uid, stopped = false, points = {}, veh = nil }
    activeScene = ctx

    CreateThread(function()
        while not ctx.stopped do
            local dist = #(GetEntityCoords(cache.ped) - vector3(callout.coords.x, callout.coords.y, callout.coords.z))
            if dist < WSFire.Callout.spawnDistance then break end
            Wait(1000)
        end
        if ctx.stopped then return end

        local d = WSFire.Fires[callout.id]
        local c = callout.coords

        -- Ausbrennendes Fahrzeug beim Fahrzeugbrand
        if d.vehicle then
            local vh = joaat('blista')
            lib.requestModel(vh, 8000)
            local veh = CreateVehicle(vh, c.x, c.y, c.z, c.w or 0.0, true, true)
            SetModelAsNoLongerNeeded(vh)
            SetEntityAsMissionEntity(veh, true, true)
            SetVehicleEngineHealth(veh, 0.0)
            SetVehiclePetrolTankHealth(veh, -100.0)
            SmashVehicleWindow(veh, 0)
            ctx.veh = veh
        end

        -- Brandherde entzuenden. Jeder Herd = grosse, DAUERHAFTE Flammen (Partikel,
        -- intensity Stueck) + EIN echtes Skriptfeuer fuer Hitze. So sind die Feuer
        -- gross und gehen nicht von selbst aus.
        local count = math.random(d.points[1], d.points[2])
        local intensity = math.max(1, d.intensity or 4)
        ensureFireAsset()
        for _ = 1, count do
            local ox = math.random(-45, 45) / 10.0
            local oy = math.random(-45, 45) / 10.0
            local px, py, pz = c.x + ox, c.y + oy, c.z
            local ok, gz = GetGroundZFor_3dCoord(px, py, pz + 2.0, false)
            if ok then pz = gz + 0.2 end

            local fx = {}
            for i = 1, intensity do
                local jx = px + math.random(-14, 14) / 10.0
                local jy = py + math.random(-14, 14) / 10.0
                fx[i] = spawnFireFx(jx, jy, pz, 1.6 + math.random() * 0.9)
            end
            local scriptFire = StartScriptFire(px, py, pz, d.spread or 1, d.gas == true)
            ctx.points[#ctx.points + 1] = {
                x = px, y = py, z = pz, fx = fx, fire = scriptFire,
                health = WSFire.Firefighting.pointHealth, out = false,
            }
        end

        TriggerServerEvent('ws_fire:sceneSpawned', callout.uid, count)
        fnotify('scene_ready', 'inform')
    end)
end

-- ---------------------------------------------------------------------------
-- Loesch-Schnittstelle (von firefighting.lua genutzt)
-- ---------------------------------------------------------------------------

local function extinguishPoint(p)
    p.out = true
    for _, h in ipairs(p.fx or {}) do StopParticleFxLooped(h, false) end
    p.fx = {}
    if p.fire then RemoveScriptFire(p.fire) p.fire = nil end
    StopFireInRange(p.x, p.y, p.z, 6.0) -- Restflammen (auch Ausbreitung) loeschen
    TriggerServerEvent('ws_fire:pointExtinguished', activeScene.uid)
end

-- Wasser entlang der Blickrichtung: alle brennenden Herde im Kegel (oder ganz
-- nah dran) werden geloescht. Grosszuegig, damit Treffer zuverlaessig zaehlen.
function WSFire.spray(origin, dir, range, power)
    if not activeScene then return false end
    local hit = false
    for _, p in ipairs(activeScene.points) do
        if not p.out then
            local dx, dy, dz = p.x - origin.x, p.y - origin.y, p.z - origin.z
            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            if dist <= range then
                local aligned = dist < 4.5
                if not aligned and dist > 0.1 then
                    -- Kosinus zwischen Blickrichtung und Richtung zum Herd
                    local d = (dx / dist) * dir.x + (dy / dist) * dir.y + (dz / dist) * dir.z
                    aligned = d > 0.78
                end
                if aligned then
                    hit = true
                    p.health = p.health - power
                    if p.health <= 0 then extinguishPoint(p) end
                end
            end
        end
    end
    return hit
end

function WSFire.hasActiveFire()
    if not activeScene then return false end
    for _, p in ipairs(activeScene.points) do
        if not p.out then return true end
    end
    return false
end

-- Naechster noch brennender Herd (fuer Ziel-/Trefferpruefung)
function WSFire.nearestBurning(pos, maxDist)
    if not activeScene then return nil end
    local best, bd
    for _, p in ipairs(activeScene.points) do
        if not p.out then
            local dist = #(pos - vector3(p.x, p.y, p.z))
            if dist <= maxDist and (not bd or dist < bd) then best, bd = p, dist end
        end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- Zuweisung / Abschluss
-- ---------------------------------------------------------------------------

RegisterNetEvent('ws_fire:assigned', function(callout)
    currentAssignment = callout
    if lastOffer and lastOffer.uid == callout.uid then lastOffer = nil end

    removeBlip()
    currentBlip = AddBlipForCoord(callout.coords.x, callout.coords.y, callout.coords.z)
    SetBlipSprite(currentBlip, 1)
    SetBlipColour(currentBlip, 47) -- orange
    SetBlipScale(currentBlip, 1.0)
    SetBlipRoute(currentBlip, true)
    SetBlipRouteColour(currentBlip, 47)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(('%s – %s'):format(callout.code, callout.label))
    EndTextCommandSetBlipName(currentBlip)

    fnotify('assigned_msg', 'success', callout.label)
    startScene(callout)
end)

local function cleanupScene(sc)
    if not sc then return end
    for _, p in ipairs(sc.points) do
        for _, h in ipairs(p.fx or {}) do StopParticleFxLooped(h, false) end
        if p.fire then RemoveScriptFire(p.fire) p.fire = nil end
        StopFireInRange(p.x, p.y, p.z, 6.0)
    end
    -- verbliebene ausgebreitete Flammen im Szenenbereich loeschen
    local c = sc.points[1]
    if c then StopFireInRange(c.x, c.y, c.z, 40.0) end
    if sc.veh and DoesEntityExist(sc.veh) then DeleteEntity(sc.veh) end
end

RegisterNetEvent('ws_fire:ended', function(uid, reason)
    if currentAssignment and currentAssignment.uid == uid then
        currentAssignment = nil
        removeBlip()
    end
    if activeScene and activeScene.uid == uid then
        activeScene.stopped = true
        cleanupScene(activeScene)
        activeScene = nil
    end
    if reason == 'cancelled' then fnotify('fire_cancelled', 'error') end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= cache.resource then return end
    if activeScene then cleanupScene(activeScene) end
end)
