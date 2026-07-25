lib.locale()

local isOpen = false

local function closeTablet()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function openTablet()
    if isOpen then return end
    -- Tablet fuer Polizei UND Rettungsdienst (jeweils im Dienst)
    local job = LocalPlayer.state['ws:job']
    if (job ~= 'police' and job ~= 'ambulance') or LocalPlayer.state['ws:duty'] ~= true then
        lib.notify({ title = locale('tablet_title'), description = locale('not_on_duty'), type = 'error' })
        return
    end

    local data = lib.callback.await('ws_tablet:getData', false)
    if not data then return end

    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data, refreshInterval = WSTablet.RefreshInterval })
end

RegisterCommand('tablet', openTablet, false)
RegisterKeyMapping('tablet', 'Polizei-Tablet öffnen', 'keyboard', 'F5')

RegisterNUICallback('close', function(_, cb)
    closeTablet()
    cb({})
end)

RegisterNUICallback('refresh', function(_, cb)
    local data = lib.callback.await('ws_tablet:getData', false)
    cb(data or {})
end)

RegisterNUICallback('accept', function(body, cb)
    cb({})
    if body and body.uid then
        -- Tablet schliessen, damit es direkt losgehen kann;
        -- Zuweisung/Fehler melden sich per Notification
        closeTablet()
        if LocalPlayer.state['ws:job'] == 'ambulance' then
            TriggerServerEvent('ws_ems:accept', body.uid)
        else
            TriggerServerEvent('ws_dispatch:accept', body.uid)
        end
    end
end)

RegisterNUICallback('adminUpdate', function(body, cb)
    local ok = lib.callback.await('ws_tablet:adminUpdate', false,
        body and body.target, body and body.changes, body and body.job)
    local data = lib.callback.await('ws_tablet:getData', false)
    cb({ ok = ok == true, data = data })
end)

RegisterNUICallback('upgradeSkill', function(body, cb)
    local ok = lib.callback.await('ws_tablet:upgradeSkill', false, body and body.branch or '')
    local data = lib.callback.await('ws_tablet:getData', false)
    cb({ ok = ok == true, data = data })
end)

RegisterNUICallback('abort', function(_, cb)
    local ok = lib.callback.await('ws_tablet:abort', false)
    local data = lib.callback.await('ws_tablet:getData', false)
    cb({ ok = ok == true, data = data })
end)

RegisterNUICallback('generate', function(body, cb)
    local ok, err = lib.callback.await('ws_tablet:generate', false, body and body.id or '')
    local data = lib.callback.await('ws_tablet:getData', false)
    cb({ ok = ok == true, err = err, data = data })
end)

-- Tablet schliesst sich bei Dienstende automatisch
RegisterNetEvent('ws_core:client:dutyChanged', function(onDuty)
    if not onDuty then closeTablet() end
end)

AddEventHandler('onResourceStop', function(res)
    if res == cache.resource then
        SetNuiFocus(false, false)
    end
end)
