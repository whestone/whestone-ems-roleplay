lib.locale()

-- Loeschmechanik: Feuerloescher (zu Fuss) + Wasserwerfer (im Loeschfahrzeug).
-- Beide werfen "Wasser" auf die Brandherde der aktiven Szene (WSFire.applyWater).

local CFG = WSFire.Firefighting
local EXT_WEAPON = joaat(CFG.extinguisher.weapon)
local FIRETRUCK = joaat('firetruk')
local PTFX_ASSET = 'core'
local lastFx = 0

local function isOnDuty()
    return LocalPlayer.state['ws:job'] == 'fire' and LocalPlayer.state['ws:duty'] == true
end

-- Feuerwehr-Skill macht das Loeschen schneller
local function skillMult()
    return 1.0 + (CFG.skillBonus or 0.2) * (LocalPlayer.state['ws:skill_firefighting'] or 0)
end

local function rotationToDirection(rot)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

-- Auftreffpunkt des Strahls (Kamera nach vorn); Treffer oder Endpunkt
local function aimPoint(maxDist)
    local cam = GetGameplayCamCoord()
    local dir = rotationToDirection(GetGameplayCamRot(2))
    local dest = cam + dir * maxDist
    local handle = StartShapeTestRay(cam.x, cam.y, cam.z, dest.x, dest.y, dest.z, -1, cache.ped, 0)
    local _, hit, endCoords = GetShapeTestResult(handle)
    if hit == 1 then return endCoords end
    return dest
end

local function spawnWaterFx(pos, scale)
    local now = GetGameTimer()
    if now - lastFx < 90 then return end
    lastFx = now
    if not HasNamedPtfxAssetLoaded(PTFX_ASSET) then
        RequestNamedPtfxAsset(PTFX_ASSET)
        return
    end
    UseParticleFxAsset(PTFX_ASSET)
    StartParticleFxNonLoopedAtCoord('ent_sht_water', pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, scale or 1.5, false, false, false)
end

CreateThread(function()
    RequestNamedPtfxAsset(PTFX_ASSET)
    while true do
        local sleep = 500
        if isOnDuty() and WSFire.hasActiveFire and WSFire.hasActiveFire() then
            sleep = 0
            local veh = cache.vehicle
            local inTruck = veh and veh ~= 0 and GetEntityModel(veh) == FIRETRUCK
            local cam = GetGameplayCamCoord()
            local dir = rotationToDirection(GetGameplayCamRot(2))

            -- Sprueh-Ausloeser: Linksklick (24=Angriff) ODER Rechtsklick (25=Zielen).
            -- Der Feuerloescher/Wasserwerfer wird von vielen mit Rechtsklick bedient.
            local spraying = IsControlPressed(0, 24) or IsControlPressed(0, 25)

            if inTruck then
                -- Wasserwerfer: Angriff/Zielen halten
                if spraying then
                    WSFire.spray(cam, dir, CFG.cannon.range, CFG.cannon.power * skillMult() * GetFrameTime())
                    spawnWaterFx(cam + dir * (CFG.cannon.range * 0.5), 2.2)
                end
            elseif not IsPedInAnyVehicle(cache.ped, false) then
                -- Feuerloescher: passende Waffe gezogen und spruehen
                local _, wpn = GetCurrentPedWeapon(cache.ped, true)
                if wpn == EXT_WEAPON and (IsPedShooting(cache.ped) or spraying) then
                    WSFire.spray(cam, dir, CFG.extinguisher.range, CFG.extinguisher.power * skillMult() * GetFrameTime())
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == cache.resource and HasNamedPtfxAssetLoaded(PTFX_ASSET) then
        RemoveNamedPtfxAsset(PTFX_ASSET)
    end
end)
