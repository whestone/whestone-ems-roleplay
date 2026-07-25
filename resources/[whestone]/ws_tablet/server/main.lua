lib.locale()

local function isAdmin(src)
    return IsPlayerAceAllowed(src, 'ws.admin')
end

-- Tablet ist job-abhaengig: Polizisten sehen Callouts (ws_dispatch),
-- Sanitaeter ihre Notfaelle (ws_ems) - gleiche Datenstruktur
local function buildData(src)
    if not exports.ws_core:IsOnDuty(src) then return nil end
    local job = exports.ws_core:GetJob(src)
    local ems = job == 'ambulance'
    return {
        isAdmin = isAdmin(src),
        job = job,
        ranks = exports.ws_core:GetRankList(job),
        rankLists = {
            police = exports.ws_core:GetRankList('police'),
            ambulance = exports.ws_core:GetRankList('ambulance'),
        },
        players = exports.ws_core:GetOnlinePlayersInfo(),
        callouts = ems and exports.ws_ems:GetActiveEmergencies() or exports.ws_dispatch:GetActiveCallouts(),
        types = ems and exports.ws_ems:GetEmergencyTypes() or exports.ws_dispatch:GetCalloutTypes(),
        canGenerate = exports.ws_core:GetRank(src) >= WSTablet.GenerateMinRank,
        myCalloutUid = ems and exports.ws_ems:GetPlayerEmergencyUid(src) or exports.ws_dispatch:GetPlayerCalloutUid(src),
        skills = exports.ws_core:GetSkillInfo(src),
        progress = exports.ws_core:GetRankProgress(src),
    }
end

lib.callback.register('ws_tablet:getData', function(src)
    return buildData(src)
end)

lib.callback.register('ws_tablet:adminUpdate', function(src, target, changes, job)
    if not isAdmin(src) then
        print(('[ws_tablet] Abgelehnter Admin-Zugriff von %s (ID %s)'):format(GetPlayerName(src) or '?', src))
        return false
    end
    target = tonumber(target)
    if not target or type(changes) ~= 'table' then return false end

    local ok = exports.ws_core:AdminSetPlayerData(target, changes, job)
    if ok then
        print(('[ws_tablet] %s hat Spielerdaten von %s angepasst (%s)'):format(GetPlayerName(src) or src, GetPlayerName(target) or target, job or 'aktiv'))
    end
    return ok == true
end)

lib.callback.register('ws_tablet:upgradeSkill', function(src, branch)
    if not exports.ws_core:IsOnDuty(src) then return false end
    return exports.ws_core:UpgradeSkill(src, branch) == true
end)

lib.callback.register('ws_tablet:abort', function(src)
    if not exports.ws_core:IsOnDuty(src) then return false end
    if exports.ws_core:GetJob(src) == 'ambulance' then
        return exports.ws_ems:AbortEmergency(src) == true
    end
    return exports.ws_dispatch:AbortAssignment(src) == true
end)

lib.callback.register('ws_tablet:generate', function(src, calloutId)
    if not exports.ws_core:IsOnDuty(src) then
        return false, locale('not_on_duty')
    end
    if exports.ws_core:GetRank(src) < WSTablet.GenerateMinRank then
        return false, locale('rank_too_low')
    end

    if calloutId == '' then calloutId = nil end
    local ok, err
    if exports.ws_core:GetJob(src) == 'ambulance' then
        ok, err = exports.ws_ems:CreateEmergency(calloutId)
    else
        ok, err = exports.ws_dispatch:CreateCallout(calloutId)
    end
    if not ok then
        return false, err
    end

    print(('[ws_tablet] %s hat einen Einsatz generiert (%s)'):format(GetPlayerName(src), calloutId or 'zufällig'))
    return true
end)
