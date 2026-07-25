lib.locale()

-- Kaffeeautomat: an jedem Kaffeeautomaten (Weltobjekt) einen Kaffee ziehen.
-- Zieht kurz an der Maschine, dann steht man mit Becher da und trinkt.
-- Reines Flavor - stellt hoechstens die Sprint-Ausdauer wieder her.

local drinking = false

local function stopDrinking()
    if not drinking then return end
    drinking = false
    ClearPedTasks(cache.ped)
end

-- Bewegung beendet das Trinken (wie bei den Emotes)
local function watchForMovement()
    CreateThread(function()
        Wait(500)
        while drinking do
            if IsPedInAnyVehicle(cache.ped, false)
                or IsControlPressed(0, 32) or IsControlPressed(0, 33)
                or IsControlPressed(0, 34) or IsControlPressed(0, 35)
                or IsControlPressed(0, 22) or IsControlPressed(0, 24) then
                stopDrinking()
                break
            end
            Wait(100)
        end
    end)
end

local function drinkCoffee()
    if drinking then return end
    if IsPedInAnyVehicle(cache.ped, false) then
        lib.notify({ title = locale('coffee_title'), description = locale('emote_no_vehicle'), type = 'error' })
        return
    end

    drinking = true
    -- Kaffee wird gezogen
    local ok = lib.progressBar({
        duration = 3000,
        label = locale('coffee_pull'),
        canCancel = true,
        disable = { move = true, car = true, combat = true },
    })
    if not ok then
        drinking = false
        return
    end

    if WSSocial.CoffeeRestoreStamina then
        RestorePlayerStamina(cache.playerId, 1.0)
    end

    -- Becher-Szenario (bringt eigenen Kaffeebecher + Trink-Animation mit)
    TaskStartScenarioInPlace(cache.ped, 'WORLD_HUMAN_AA_COFFEE', 0, true)
    watchForMovement()
    lib.notify({ title = locale('coffee_title'), description = locale('coffee_done'), type = 'success' })
end

-- ---------------------------------------------------------------------------
-- ox_target: Weltobjekte + optionale feste Standorte
-- ---------------------------------------------------------------------------

local coffeeOption = {
    name = 'ws_social_coffee',
    label = locale('coffee_option'),
    icon = 'fa-solid fa-mug-hot',
    distance = 1.8,
    onSelect = drinkCoffee,
}

if WSSocial.CoffeeProps and #WSSocial.CoffeeProps > 0 then
    exports.ox_target:addModel(WSSocial.CoffeeProps, { coffeeOption })
end

for _, pos in ipairs(WSSocial.CoffeeMachines or {}) do
    exports.ox_target:addSphereZone({
        coords = pos, radius = 1.2,
        options = { coffeeOption },
    })
end

AddEventHandler('onResourceStop', function(res)
    if res == cache.resource then stopDrinking() end
end)
