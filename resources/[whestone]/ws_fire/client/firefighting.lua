lib.locale()

-- Loeschmechanik: Feuerloescher (zu Fuss) + Wasserwerfer (im Loeschfahrzeug).
-- Beide loeschen die Brandherde der aktiven Szene ueber WSFire.spray.
-- Ausgeloest wird per RECHTSKLICK (Zielen); Linksklick loescht bewusst NICHT.

local CFG = WSFire.Firefighting
local EXT_WEAPON = joaat(CFG.extinguisher.weapon)
local FIRETRUCK = joaat('firetruk')

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

CreateThread(function()
    while true do
        local sleep = 500
        if isOnDuty() and WSFire.hasActiveFire and WSFire.hasActiveFire() then
            sleep = 0
            local veh = cache.vehicle
            local inTruck = veh and veh ~= 0 and GetEntityModel(veh) == FIRETRUCK
            local cam = GetGameplayCamCoord()
            local dir = rotationToDirection(GetGameplayCamRot(2))

            -- Nur RECHTSKLICK (25 = Zielen) loescht. Linksklick macht bewusst nichts.
            local spraying = IsControlPressed(0, 25)

            if inTruck then
                -- Wasserwerfer: Zielen (Rechtsklick) halten
                if spraying then
                    WSFire.spray(cam, dir, CFG.cannon.range, CFG.cannon.power * skillMult() * GetFrameTime())
                end
            elseif not IsPedInAnyVehicle(cache.ped, false) then
                -- Feuerloescher: Waffe gezogen + Rechtsklick halten
                local _, wpn = GetCurrentPedWeapon(cache.ped, true)
                if wpn == EXT_WEAPON and spraying then
                    WSFire.spray(cam, dir, CFG.extinguisher.range, CFG.extinguisher.power * skillMult() * GetFrameTime())
                end
            end
        end
        Wait(sleep)
    end
end)
