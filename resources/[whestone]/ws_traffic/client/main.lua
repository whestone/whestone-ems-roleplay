lib.locale()

-- Aktive Verkehrskontrolle (eine gleichzeitig): { veh, driver, netId, record }
local stop = nil

local function ensureControl(entity)
    if not DoesEntityExist(entity) then return false end
    if NetworkHasControlOfEntity(entity) then return true end
    NetworkRequestControlOfEntity(entity)
    local tries = 0
    while not NetworkHasControlOfEntity(entity) and tries < 50 do
        Wait(20)
        tries = tries + 1
    end
    return NetworkHasControlOfEntity(entity)
end

local function tnotify(key, ntype, ...)
    lib.notify({ title = locale('traffic_title'), description = locale(key, ...), type = ntype or 'inform' })
end

-- ---------------------------------------------------------------------------
-- Kontrolle beenden
-- ---------------------------------------------------------------------------

local function releaseDriver(letDriveOff)
    if not stop then return end
    local veh, driver, netId = stop.veh, stop.driver, stop.netId
    stop = nil -- stoppt den Halte-Thread

    if DoesEntityExist(driver) then
        Entity(driver).state:set('ws:trafficstop', nil, true)
    end
    if DoesEntityExist(veh) and ensureControl(veh) then
        FreezeEntityPosition(veh, false)
        SetVehicleHandbrake(veh, false)
    end
    if letDriveOff and DoesEntityExist(driver) and ensureControl(driver) then
        SetBlockingOfNonTemporaryEvents(driver, false)
        -- WICHTIG: bei sitzendem Fahrer NICHT ClearPedTasksImmediately verwenden -
        -- das wuerde ihn aus dem Auto werfen. Nur zu Fuss darf hart geleert werden.
        if DoesEntityExist(veh) and IsPedInVehicle(driver, veh, false) then
            ClearPedTasks(driver)
            TaskVehicleDriveWander(driver, veh, 12.0, 786603)
        else
            ClearPedTasksImmediately(driver)
            TaskWanderStandard(driver, 10.0, 10)
        end
    end
    if DoesEntityExist(driver) then SetEntityAsNoLongerNeeded(driver) end
    if DoesEntityExist(veh) then SetEntityAsNoLongerNeeded(veh) end

    TriggerServerEvent('ws_traffic:release', netId)
end

-- Abschluss bei Festnahme: Fahrzeug freigeben, Fahrer bleibt Verdaechtiger
local function endForArrest()
    if not stop then return end
    local veh, driver = stop.veh, stop.driver
    stop = nil

    if DoesEntityExist(driver) then
        Entity(driver).state:set('ws:trafficstop', nil, true)
    end
    if DoesEntityExist(veh) then
        if ensureControl(veh) then
            FreezeEntityPosition(veh, false)
            SetVehicleHandbrake(veh, false)
        end
        SetEntityAsNoLongerNeeded(veh)
    end
end

-- ---------------------------------------------------------------------------
-- Einzelaktionen (Menue wird danach neu geoeffnet)
-- ---------------------------------------------------------------------------

local openStopMenu -- forward declaration

local function checkPapers()
    if lib.progressBar({ duration = WSTraffic.Durations.papers, label = locale('papers_running'),
        canCancel = true, disable = { move = true, combat = true } }) then
        local r = stop.record
        local licTxt = locale('license_' .. r.license)
        local regTxt = r.registration == 'valid' and locale('reg_valid') or locale('reg_missing')
        lib.alertDialog({
            header = locale('papers_header'),
            content = locale('papers_content', r.name, r.plate, licTxt, regTxt),
            centered = true,
        })
    end
    openStopMenu()
end

local function breathTest()
    if lib.progressBar({ duration = WSTraffic.Durations.breath, label = locale('breath_running'),
        canCancel = true, disable = { move = true, combat = true },
        anim = { dict = 'mp_common', clip = 'givetake1_a', flag = 49 } }) then
        local r = stop.record
        local text = ('%.2f'):format(r.promille):gsub('%.', ',')
        if r.drunk then
            tnotify('breath_pos', 'error', text)
        else
            tnotify('breath_neg', 'success', text)
        end
    end
    openStopMenu()
end

local function searchVehicle()
    if lib.progressBar({ duration = WSTraffic.Durations.search, label = locale('search_running'),
        canCancel = true, disable = { move = true, combat = true } }) then
        if stop.record.contraband then
            tnotify('search_found', 'error')
        else
            tnotify('search_clean', 'success')
        end
    end
    openStopMenu()
end

local function askExit()
    local veh, driver = stop.veh, stop.driver
    -- Zum Aussteigen kurz entfrieren (der Halte-Thread friert danach nicht
    -- wieder ein, weil der Fahrer dann nicht mehr im Auto sitzt)
    if DoesEntityExist(veh) and ensureControl(veh) then FreezeEntityPosition(veh, false) end
    if DoesEntityExist(driver) and ensureControl(driver) then
        TaskLeaveVehicle(driver, veh, 0)
        Wait(1500)
        if DoesEntityExist(driver) then
            SetBlockingOfNonTemporaryEvents(driver, true)
            ClearPedTasks(driver)
        end
    end
    openStopMenu()
end

local function issueOutcome(kind)
    local res = lib.callback.await('ws_traffic:issueOutcome', false, stop.netId, kind)
    if type(res) == 'table' and res.ok then
        tnotify(kind == 'warn' and 'warn_issued' or 'ticket_issued', 'success')
        releaseDriver(true)
    elseif type(res) == 'table' and res.reason == 'no_violation' then
        tnotify('ticket_no_violation', 'error')
        openStopMenu()
    else
        openStopMenu()
    end
end

-- ---------------------------------------------------------------------------
-- Festnahme (kooperativ oder Flucht)
-- ---------------------------------------------------------------------------

local function surrenderAndArrest(driver, veh)
    if ensureControl(driver) then
        if IsPedInVehicle(driver, veh, false) then
            TaskLeaveVehicle(driver, veh, 0)
            Wait(1200)
        end
        ClearPedTasksImmediately(driver)
        RemoveAllPedWeapons(driver, true)
        lib.requestAnimDict('random@arrests')
        TaskHandsUp(driver, -1, 0, -1, false)
        SetBlockingOfNonTemporaryEvents(driver, true)
    end
    tnotify('arrest_ready', 'inform')
end

local function startPursuit(driver, veh, netId, driverNetId)
    tnotify('driver_flees', 'error')
    -- Flucht-Flag: das Anhaltezeichen (U) ignoriert markierte Fahrer, und sie
    -- lassen sich nicht neu kontrollieren, solange sie fliehen
    Entity(driver).state:set('ws:fleeing', true, true)

    -- Roter Punkt am Fahrer (folgt ihm auch bei Fussflucht) - wie bei den
    -- Verfolgungsjagden der Callouts
    local blip = AddBlipForEntity(driver)
    SetBlipSprite(blip, 1)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 0.9)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(locale('flee_blip'))
    EndTextCommandSetBlipName(blip)

    local function cleanup()
        if DoesBlipExist(blip) then RemoveBlip(blip) end
        if DoesEntityExist(driver) then
            Entity(driver).state:set('ws:fleeing', nil, true)
        end
    end

    if ensureControl(driver) then
        SetVehicleEngineOn(veh, true, true, false)
        SetPedKeepTask(driver, true)
        SetDriverAbility(driver, 1.0)
        SetDriverAggressiveness(driver, 1.0)
        TaskVehicleMissionPedTarget(driver, veh, cache.ped, 8, 80.0, 786468, 20.0, 20.0, true)
    end

    CreateThread(function()
        local fleeStart = GetGameTimer()
        while true do
            Wait(1000)
            if not DoesEntityExist(driver) or IsEntityDead(driver) then
                cleanup()
                return
            end

            local onFoot = not IsPedInAnyVehicle(driver, false)
            local burst = 0
            if DoesEntityExist(veh) then
                for _, w in ipairs({ 0, 1, 4, 5 }) do
                    if IsVehicleTyreBurst(veh, w, false) then burst = burst + 1 end
                end
            end

            -- Gestoppt: Fahrzeug fahruntuechtig (Motor/Reifen), zu Fuss oder Zeitablauf
            local disabled = DoesEntityExist(veh) and (GetVehicleEngineHealth(veh) < 300.0 or burst >= 2)
            local stopped = onFoot or disabled or (GetGameTimer() - fleeStart) > 180000

            if stopped then
                tnotify('flee_stopped', 'inform')
                if DoesEntityExist(veh) and IsPedInVehicle(driver, veh, false) and ensureControl(driver) then
                    TaskLeaveVehicle(driver, veh, 256)
                    Wait(2500)
                end

                -- Fussflucht, bis der Officer nah dran ist (oder max. 60s)
                local footStart = GetGameTimer()
                while DoesEntityExist(driver) and not IsEntityDead(driver)
                    and #(GetEntityCoords(driver) - GetEntityCoords(cache.ped)) > 5.0
                    and (GetGameTimer() - footStart) < 60000 do
                    if ensureControl(driver) then
                        TaskSmartFleePed(driver, cache.ped, 80.0, -1, false, false)
                    end
                    Wait(1500)
                end

                cleanup()
                if DoesEntityExist(driver) and not IsEntityDead(driver) then
                    -- Fahrer-Ped-NetId neu bestimmen (kann sich nach Ausstieg geaendert haben)
                    if not NetworkGetEntityIsNetworked(driver) then
                        NetworkRegisterEntityAsNetworked(driver)
                    end
                    local caughtNetId = NetworkGetNetworkIdFromEntity(driver)
                    local res = lib.callback.await('ws_traffic:registerCaught', false, caughtNetId)
                    if res and res.uid then
                        surrenderAndArrest(driver, veh)
                    end
                end
                return
            end
        end
    end)
end

local function arrestDriver()
    local veh, driver, netId = stop.veh, stop.driver, stop.netId
    -- Fahrer-Ped muss genetzt sein, damit der Server ihn als Verdaechtigen
    -- registrieren kann (NetId des Peds, nicht des Fahrzeugs!)
    if not NetworkGetEntityIsNetworked(driver) then
        NetworkRegisterEntityAsNetworked(driver)
    end
    local driverNetId = NetworkGetNetworkIdFromEntity(driver)

    local res = lib.callback.await('ws_traffic:beginArrest', false, netId, driverNetId)
    if type(res) ~= 'table' then openStopMenu() return end

    endForArrest()
    if res.flee then
        startPursuit(driver, veh, netId, driverNetId)
    elseif res.uid then
        surrenderAndArrest(driver, veh)
    end
end

-- ---------------------------------------------------------------------------
-- Menue
-- ---------------------------------------------------------------------------

openStopMenu = function()
    if not stop then return end
    lib.registerContext({
        id = 'ws_traffic_stop',
        title = locale('traffic_title'),
        options = {
            { title = locale('opt_papers'), icon = 'id-card', onSelect = checkPapers },
            { title = locale('opt_breath'), icon = 'wine-bottle', onSelect = breathTest },
            { title = locale('opt_search'), icon = 'magnifying-glass', onSelect = searchVehicle },
            { title = locale('opt_exit'), icon = 'person-walking-arrow-right', onSelect = askExit },
            { title = locale('opt_warn'), icon = 'triangle-exclamation', onSelect = function() issueOutcome('warn') end },
            { title = locale('opt_ticket'), icon = 'file-invoice-dollar', onSelect = function() issueOutcome('ticket') end },
            { title = locale('opt_arrest'), icon = 'handcuffs', onSelect = arrestDriver },
            { title = locale('opt_release'), icon = 'car', onSelect = function() releaseDriver(true) tnotify('released', 'inform') end },
        },
    })
    lib.showContext('ws_traffic_stop')
end

local function beginStop(veh)
    local driver = GetPedInVehicleSeat(veh, -1)
    if driver == 0 or not DoesEntityExist(driver) then
        return tnotify('no_driver', 'error')
    end

    SetEntityAsMissionEntity(veh, true, true)
    SetEntityAsMissionEntity(driver, true, true)
    ensureControl(driver)
    SetBlockingOfNonTemporaryEvents(driver, true)
    ClearPedTasks(driver)
    if ensureControl(veh) then
        SetVehicleHandbrake(veh, true)
        FreezeEntityPosition(veh, true)
    end
    Entity(driver).state:set('ws:trafficstop', true, true)

    local netId = NetworkGetNetworkIdFromEntity(veh)
    local record = lib.callback.await('ws_traffic:getRecord', false, netId)
    if not record then
        if DoesEntityExist(veh) and ensureControl(veh) then FreezeEntityPosition(veh, false) end
        if DoesEntityExist(driver) then Entity(driver).state:set('ws:trafficstop', nil, true) end
        return
    end

    stop = { veh = veh, driver = driver, netId = netId, record = record }

    -- Fahrzeug bleibt eingefroren, solange der Fahrer drinsitzt und die
    -- Kontrolle laeuft. Steigt er aus, wird freigegeben (leeres Auto faehrt
    -- ohne Fahrer ohnehin nicht weg).
    CreateThread(function()
        while stop and stop.veh == veh and DoesEntityExist(veh) and DoesEntityExist(driver) do
            if ensureControl(veh) then
                FreezeEntityPosition(veh, IsPedInVehicle(driver, veh, false))
            end
            Wait(1500)
        end
    end)

    openStopMenu()
end

-- ---------------------------------------------------------------------------
-- ox_target: Verkehrskontrolle am stehenden Fahrzeug
-- ---------------------------------------------------------------------------

exports.ox_target:addGlobalVehicle({
    {
        name = 'ws_traffic_stop',
        label = locale('opt_begin'),
        icon = 'fa-solid fa-traffic-light',
        distance = 4.0,
        canInteract = function(entity)
            if LocalPlayer.state['ws:job'] ~= 'police' or LocalPlayer.state['ws:duty'] ~= true then return false end
            if stop then return false end
            if GetVehicleClass(entity) == 18 then return false end
            if GetEntitySpeed(entity) > 1.5 then return false end
            local driver = GetPedInVehicleSeat(entity, -1)
            if driver == 0 or not DoesEntityExist(driver) then return false end
            if IsPedAPlayer(driver) or IsEntityDead(driver) then return false end
            if Entity(driver).state['ws:suspect'] or Entity(driver).state['ws:fleeing'] then return false end
            return true
        end,
        onSelect = function(data) beginStop(data.entity) end,
    },
    {
        -- Sitzt der Fahrer noch im Wagen, ist ER nicht anvisierbar (ox_target
        -- erreicht keine Peds in Fahrzeugen) - ohne diese Option waere das
        -- Menue nach einem versehentlichen ESC nicht mehr erreichbar.
        name = 'ws_traffic_continue_vehicle',
        label = locale('opt_continue'),
        icon = 'fa-solid fa-clipboard-list',
        distance = 4.0,
        canInteract = function(entity)
            if LocalPlayer.state['ws:job'] ~= 'police' or LocalPlayer.state['ws:duty'] ~= true then return false end
            return stop ~= nil and stop.driver ~= nil and DoesEntityExist(stop.driver)
                and GetPedInVehicleSeat(entity, -1) == stop.driver
        end,
        onSelect = function() openStopMenu() end,
    },
})

-- Kontrolle am Fahrer fortsetzen (z.B. nachdem er ausgestiegen ist) -
-- so bleibt das ganze Menue erreichbar, nicht nur ueber das Fahrzeug
exports.ox_target:addGlobalPed({
    {
        name = 'ws_traffic_continue',
        label = locale('opt_continue'),
        icon = 'fa-solid fa-clipboard-list',
        distance = 3.0,
        canInteract = function(entity)
            return stop ~= nil and entity == stop.driver and DoesEntityExist(entity)
        end,
        onSelect = function() openStopMenu() end,
    },
})

AddEventHandler('onResourceStop', function(res)
    if res == cache.resource then
        stop = nil
    end
end)
