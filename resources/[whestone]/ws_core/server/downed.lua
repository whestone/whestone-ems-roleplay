lib.locale()

-- Serverseite des Downed-Systems: meldet den Zustand an die Notfall-Engine
-- (ws_ems erzeugt daraus einen regulaeren Notruf), validiert die
-- Wiederbelebung und vergibt XP.

local CFG = WSConfig.Downed or { enabled = false }

local Downed = {} -- src -> true

local function isMedicOnDuty(src)
    return exports.ws_core:GetJob(src) == 'ambulance' and exports.ws_core:IsOnDuty(src)
end

-- Zustandsende an die Notfall-Engine melden (revived = true/false)
local function finish(src, revived)
    if not Downed[src] then return end
    Downed[src] = nil
    TriggerEvent('ws_core:downedFinished', src, revived)
end

RegisterNetEvent('ws_core:playerDowned', function()
    local src = source
    if not CFG.enabled or Downed[src] then return end
    Downed[src] = true
    -- ws_ems haengt sich hier ein und erzeugt einen echten Notruf
    if CFG.alertEms then TriggerEvent('ws_core:downedStarted', src) end
end)

RegisterNetEvent('ws_core:downedEnded', function()
    finish(source, false)
end)

-- Sanitaeter beginnt/bricht die Behandlung ab (nur Anzeige beim Patienten)
RegisterNetEvent('ws_core:reviveProgress', function(target, state)
    local src = source
    target = tonumber(target)
    if not target or not Downed[target] or not isMedicOnDuty(src) then return end
    TriggerClientEvent('ws_core:reviveProgress', target, state == true)
end)

-- Wiederbelebung abschliessen (serverseitig validiert)
RegisterNetEvent('ws_core:requestRevive', function(target)
    local src = source
    target = tonumber(target)
    if not target or not Downed[target] then return end
    if not isMedicOnDuty(src) then return end

    local medicPed, targetPed = GetPlayerPed(src), GetPlayerPed(target)
    if not medicPed or medicPed == 0 or not targetPed or targetPed == 0 then return end
    if #(GetEntityCoords(medicPed) - GetEntityCoords(targetPed)) > 8.0 then return end

    TriggerClientEvent('ws_core:revived', target)
    exports.ws_core:AddStat(src, 'revives', 1)
    exports.ws_core:AddXP(src, CFG.reviveXP or 100, locale('xp_revive'))
    finish(target, true)
end)

AddEventHandler('playerDropped', function()
    finish(source, false)
end)

exports('IsPlayerDowned', function(src)
    return Downed[src] == true
end)
