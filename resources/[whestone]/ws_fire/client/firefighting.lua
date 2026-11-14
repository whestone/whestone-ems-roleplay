lib.locale()

-- Loeschmechanik: Feuerloescher (zu Fuss) + Wasserwerfer (im Loeschfahrzeug).
-- Beide loeschen die Brandherde der aktiven Szene ueber WSFire.spray.
-- Zu Fuss: RECHTSKLICK (Zielen). Im LF: Angriff/Zielen -- Maustasten sind im
-- Fahrzeug anders belegt / teils "disabled", daher breite Control-Abfrage.

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

-- Taste gedrueckt? Auch "disabled" pruefen: im Fahrzeug sind viele on-foot-
-- Controls deaktiviert und schlagen ueber IsControlPressed sonst nicht an.
local function held(control)
    return IsControlPressed(0, control) or IsDisabledControlPressed(0, control)
end

CreateThread(function()
    while true do
        local sleep = 500
        if isOnDuty() and WSFire.hasActiveFire and WSFire.hasActiveFire() then
            sleep = 0
            local veh = GetVehiclePedIsIn(cache.ped, false)
            local inTruck = veh ~= 0 and GetEntityModel(veh) == FIRETRUCK
            local cam = GetGameplayCamCoord()
            local dir = rotationToDirection(GetGameplayCamRot(2))
            local sprayed = false

            if inTruck then
                -- Wasserwerfer: Angriff/Zielen -- on-foot- (24/25) UND Fahrzeug-
                -- Attack-Controls (69/70) abdecken, jeweils auch "disabled".
                if held(24) or held(25) or held(69) or held(70) then
                    WSFire.spray(cam, dir, CFG.cannon.range, CFG.cannon.power * skillMult() * GetFrameTime(), CFG.cannonRadius, CFG.cannonArea)
                    sprayed = true
                end
            elseif not IsPedInAnyVehicle(cache.ped, false) then
                -- Feuerloescher zu Fuss: nur RECHTSKLICK (25 = Zielen), Linksklick nichts.
                local _, wpn = GetCurrentPedWeapon(cache.ped, true)
                if wpn == EXT_WEAPON and held(25) then
                    WSFire.spray(cam, dir, CFG.extinguisher.range, CFG.extinguisher.power * skillMult() * GetFrameTime(), CFG.hitRadius, false)
                    sprayed = true
                end
            end

            -- Nicht mehr geloescht -> Dampf sofort entfernen
            if not sprayed and WSFire.stopSpray then WSFire.stopSpray() end
        end
        Wait(sleep)
    end
end)
