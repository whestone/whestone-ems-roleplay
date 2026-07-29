lib.locale()

local isOpen = false

local function closeTablet()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

-- Server-Daten holen und die clientseitige Verstaerkungs-Auswahl (nur Polizei)
-- einmischen - die liegt als lokaler Statebag/Export in ws_police.
local function getData()
    local data = lib.callback.await('ws_tablet:getData', false)
    if not data then return nil end
    if LocalPlayer.state['ws:job'] == 'police' then
        data.backup = exports.ws_police:GetBackupInfo()
    end
    return data
end

local function openTablet()
    if isOpen then return end
    -- Tablet fuer Polizei, Rettungsdienst UND Feuerwehr (jeweils im Dienst)
    local job = LocalPlayer.state['ws:job']
    if (job ~= 'police' and job ~= 'ambulance' and job ~= 'fire') or LocalPlayer.state['ws:duty'] ~= true then
        lib.notify({ title = locale('tablet_title'), description = locale('not_on_duty'), type = 'error' })
        return
    end

    local data = getData()
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
    local data = getData()
    cb(data or {})
end)

RegisterNUICallback('accept', function(body, cb)
    cb({})
    if body and body.uid then
        -- Tablet schliessen, damit es direkt losgehen kann;
        -- Zuweisung/Fehler melden sich per Notification
        closeTablet()
        local j = LocalPlayer.state['ws:job']
        if j == 'ambulance' then
            TriggerServerEvent('ws_ems:accept', body.uid)
        elseif j == 'fire' then
            TriggerServerEvent('ws_fire:accept', body.uid)
        else
            TriggerServerEvent('ws_dispatch:accept', body.uid)
        end
    end
end)

RegisterNUICallback('adminUpdate', function(body, cb)
    local ok = lib.callback.await('ws_tablet:adminUpdate', false,
        body and body.target, body and body.changes, body and body.job)
    local data = getData()
    cb({ ok = ok == true, data = data })
end)

RegisterNUICallback('upgradeSkill', function(body, cb)
    local ok = lib.callback.await('ws_tablet:upgradeSkill', false, body and body.branch or '')
    local data = getData()
    cb({ ok = ok == true, data = data })
end)

RegisterNUICallback('abort', function(_, cb)
    local ok = lib.callback.await('ws_tablet:abort', false)
    local data = getData()
    cb({ ok = ok == true, data = data })
end)

RegisterNUICallback('setBackupTier', function(body, cb)
    if body and body.tier and LocalPlayer.state['ws:job'] == 'police' then
        exports.ws_police:SetBackupTier(body.tier)
    end
    cb({ data = getData() or {} })
end)

RegisterNUICallback('generate', function(body, cb)
    local ok, err = lib.callback.await('ws_tablet:generate', false, body and body.id or '')
    local data = getData()
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
