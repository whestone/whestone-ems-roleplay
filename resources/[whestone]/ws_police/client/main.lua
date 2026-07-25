lib.locale()

local function isPolice()
    return LocalPlayer.state['ws:job'] == 'police'
end

local function isOnDuty()
    return isPolice() and LocalPlayer.state['ws:duty'] == true
end

local function myRank()
    return LocalPlayer.state['ws:rank'] or 0
end

-- ---------------------------------------------------------------------------
-- Dienst / Umkleide
-- ---------------------------------------------------------------------------

local function applyModel(modelName, randomOutfit)
    local model = joaat(modelName)
    lib.requestModel(model, 10000)
    SetPlayerModel(cache.playerId, model)
    SetModelAsNoLongerNeeded(model)
    Wait(150)

    local ped = PlayerPedId()
    if randomOutfit then
        -- Zufaellige Variante (Gesicht/Textur) fuer optische Abwechslung
        SetPedRandomComponentVariation(ped, 0)
    else
        SetPedDefaultComponentVariation(ped)
    end
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    return ped
end

local function startDuty(model)
    if not lib.callback.await('ws_police:setDuty', false, true) then return end
    applyModel(model, true)
end

local function endDuty()
    if not lib.callback.await('ws_police:setDuty', false, false) then return end
    local ped = applyModel(WSPolice.CivilianModel)
    RemoveAllPedWeapons(ped, true)
    SetPedArmour(ped, 0)
end

local function openCloakroom()
    if isOnDuty() then
        lib.registerContext({ id = 'ws_cloakroom', title = locale('cloakroom_title'), options = {
            { title = locale('duty_end'), icon = 'right-from-bracket', onSelect = endDuty },
        } })
        lib.showContext('ws_cloakroom')
        return
    end

    -- Grafische Auswahl (NUI in ws_core): Ped-Bild, Modellcode, Freischaltrang
    local rank = myRank()
    local skins = {}
    for _, uniform in ipairs(WSPolice.Uniforms) do
        skins[#skins + 1] = {
            model = uniform.model,
            label = uniform.label,
            minRank = uniform.minRank or 0,
            locked = rank < (uniform.minRank or 0),
        }
    end
    local choice = exports.ws_core:OpenVehicleSelect({
        title = locale('cloakroom_title'),
        accent = 'lspd',
        fallback = '👮',
        imageBase = 'peds',
        vehicles = skins,
    })
    if choice then startDuty(choice) end
end

-- ---------------------------------------------------------------------------
-- Waffenkammer
-- ---------------------------------------------------------------------------

local function equipWeapons(weapons, silent)
    if not weapons then
        if not silent then
            lib.notify({ title = locale('armory_title'), description = locale('armory_denied'), type = 'error' })
        end
        return false
    end

    local ped = PlayerPedId()
    for _, w in ipairs(weapons) do
        local hash = joaat(w[1])
        GiveWeaponToPed(ped, hash, w[2], false, false)
        if w[2] > 0 then
            SetPedAmmo(ped, hash, w[2])
        end
    end
    if not silent then
        lib.notify({ title = locale('armory_title'), description = locale('armory_received'), type = 'success' })
    end
    return true
end

local function giveLoadout(kind)
    equipWeapons(lib.callback.await('ws_police:getLoadout', false, kind))
end

local function giveSkillLoadout(level)
    equipWeapons(lib.callback.await('ws_police:getSkillLoadout', false, level))
end

-- Alles verfuegbare auf einmal: alle freigeschalteten Loadouts + Skill-Waffen
-- + Weste. Der Server prueft Rang/Skill je Loadout, wir nehmen was zurueckkommt.
local function equipAll()
    local got = false
    if equipWeapons(lib.callback.await('ws_police:getLoadout', false, 'standard'), true) then got = true end
    if equipWeapons(lib.callback.await('ws_police:getLoadout', false, 'rifle'), true) then got = true end

    local weaponSkill = LocalPlayer.state['ws:skill_weapons'] or 0
    for level = 1, weaponSkill do
        if equipWeapons(lib.callback.await('ws_police:getSkillLoadout', false, level), true) then got = true end
    end

    local ped = PlayerPedId()
    SetPedArmour(ped, 100)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))

    lib.notify({
        title = locale('armory_title'),
        description = got and locale('armory_all') or locale('armory_denied'),
        type = got and 'success' or 'error',
    })
end

local function takeVest()
    local ped = PlayerPedId()
    SetPedArmour(ped, 100)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    lib.notify({ title = locale('armory_title'), description = locale('armory_vest'), type = 'success' })
end

local function openArmory()
    local options = {
        { title = locale('armory_all_title'), description = locale('armory_all_desc'), icon = 'boxes-stacked',
          onSelect = equipAll },
        { title = WSPolice.Loadouts.standard.label, description = locale('armory_standard_desc'), icon = 'gun',
          onSelect = function() giveLoadout('standard') end },
        { title = locale('armory_vest_title'), description = locale('armory_vest_desc'), icon = 'shield-halved',
          onSelect = takeVest },
    }
    if myRank() >= WSPolice.Loadouts.rifle.minRank then
        options[#options + 1] = { title = WSPolice.Loadouts.rifle.label, description = locale('armory_rifle_desc'),
            icon = 'person-rifle', onSelect = function() giveLoadout('rifle') end }
    end

    -- Ueber das Skillsystem freigeschaltete Waffen
    local weaponSkill = LocalPlayer.state['ws:skill_weapons'] or 0
    for level, entry in ipairs(WSPolice.SkillWeapons) do
        if weaponSkill >= level then
            options[#options + 1] = {
                title = entry.label,
                description = locale('armory_skill_desc', level),
                icon = 'unlock',
                onSelect = function() giveSkillLoadout(level) end,
            }
        end
    end

    lib.registerContext({ id = 'ws_armory', title = locale('armory_title'), options = options })
    lib.showContext('ws_armory')
end

-- ---------------------------------------------------------------------------
-- Garage
-- ---------------------------------------------------------------------------

local function spawnVehicle(model)
    local netId, reason = lib.callback.await('ws_police:spawnVehicle', false, model)
    if not netId then
        local msg = (reason == 'model') and locale('garage_unavailable') or locale('garage_denied')
        lib.notify({ title = locale('garage_title'), description = msg, type = 'error' })
        return
    end

    local timeout = GetGameTimer() + 5000
    while not NetworkDoesEntityExistWithNetworkId(netId) and GetGameTimer() < timeout do
        Wait(50)
    end
    if not NetworkDoesEntityExistWithNetworkId(netId) then return end

    local veh = NetToVeh(netId)
    NetworkRequestControlOfEntity(veh)
    local tries = 0
    while not NetworkHasControlOfEntity(veh) and tries < 40 do
        Wait(25)
        tries = tries + 1
    end

    SetVehicleNumberPlateText(veh, ('WEMS%03d'):format(math.random(0, 999)))
    SetVehicleDirtLevel(veh, 0.0)
    SetVehRadioStation(veh, 'OFF')

    -- Tuning gemaess Fahrzeug-Skill anwenden
    local tuning = WSPolice.VehicleTuning[LocalPlayer.state['ws:skill_vehicles'] or 0]
    if tuning then
        SetVehicleModKit(veh, 0)
        local function applyMod(modType, index)
            local maxIndex = GetNumVehicleMods(veh, modType) - 1
            if maxIndex >= 0 then
                SetVehicleMod(veh, modType, math.min(index, maxIndex), false)
            end
        end
        if tuning.engine then applyMod(11, tuning.engine) end
        if tuning.brakes then applyMod(12, tuning.brakes) end
        if tuning.transmission then applyMod(13, tuning.transmission) end
        if tuning.suspension then applyMod(15, tuning.suspension) end
        if tuning.armor then applyMod(16, tuning.armor) end
        if tuning.turbo then ToggleVehicleMod(veh, 18, true) end
    end

    TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
    lib.notify({ title = locale('garage_title'), description = locale('garage_received'), type = 'success' })
end

local function returnVehicle()
    if lib.callback.await('ws_police:returnVehicle', false) then
        lib.notify({ title = locale('garage_title'), description = locale('garage_returned'), type = 'success' })
    else
        lib.notify({ title = locale('garage_title'), description = locale('garage_return_failed'), type = 'error' })
    end
end

-- Grafische Auswahl (NUI in ws_core): zeigt ALLE Fahrzeuge inkl. Bild,
-- Modellcode und Freischaltrang; gesperrte/fehlende Modelle ausgegraut
local function openGarage()
    local rank = myRank()
    local vehicles = {}
    for _, v in ipairs(WSPolice.Vehicles) do
        vehicles[#vehicles + 1] = {
            model = v.model,
            label = v.label,
            minRank = v.minRank,
            locked = rank < v.minRank,
            unavailable = not IsModelInCdimage(joaat(v.model)),
        }
    end
    local choice = exports.ws_core:OpenVehicleSelect({
        title = locale('garage_title'),
        accent = 'lspd',
        fallback = '🚓',
        returnLabel = locale('garage_return'),
        vehicles = vehicles,
    })
    if choice == '__return' then
        returnVehicle()
    elseif choice then
        spawnVehicle(choice)
    end
end

-- ---------------------------------------------------------------------------
-- Zonen & Blip
-- ---------------------------------------------------------------------------

CreateThread(function()
    local b = WSPolice.Station.blip
    local blip = AddBlipForCoord(b.coords.x, b.coords.y, b.coords.z)
    SetBlipSprite(blip, b.sprite)
    SetBlipColour(blip, b.color)
    SetBlipScale(blip, b.scale)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(b.label)
    EndTextCommandSetBlipName(blip)
end)

exports.ox_target:addSphereZone({
    coords = WSPolice.Station.cloakroom,
    radius = 1.5,
    options = {
        {
            name = 'ws_police_cloakroom',
            label = locale('target_cloakroom'),
            icon = 'fa-solid fa-shirt',
            canInteract = isPolice,
            onSelect = openCloakroom,
        },
    },
})

exports.ox_target:addSphereZone({
    coords = WSPolice.Station.armory,
    radius = 1.5,
    options = {
        {
            name = 'ws_police_armory',
            label = locale('target_armory'),
            icon = 'fa-solid fa-gun',
            canInteract = isOnDuty,
            onSelect = openArmory,
        },
    },
})

exports.ox_target:addSphereZone({
    coords = WSPolice.Station.garage,
    radius = 2.5,
    options = {
        {
            name = 'ws_police_garage',
            label = locale('target_garage'),
            icon = 'fa-solid fa-warehouse',
            canInteract = isOnDuty,
            onSelect = openGarage,
        },
    },
})
