lib.locale()

---@class WSPlayer
---@field source number
---@field license string
---@field name string
---@field job string
---@field rank number
---@field xp number
---@field stats table<string, number>
---@field position table|nil
---@field duty boolean

---@type table<number, WSPlayer>
local Players = {}

local function getLicense(src)
    return GetPlayerIdentifierByType(src, 'license')
end

local function getRankData(job, grade)
    local jobData = WSConfig.Jobs[job]
    return jobData and jobData.ranks[grade] or nil
end

-- Hoechster Rang, dessen XP-Schwelle erreicht ist (Raenge sind aufsteigend ab 0)
local function getRankForXP(job, xp)
    local ranks = WSConfig.Jobs[job].ranks
    local grade, g = 0, 0
    while ranks[g] do
        if xp >= ranks[g].xp then grade = g end
        g = g + 1
    end
    return grade
end

local SKILL_BRANCHES = { 'weapons', 'vehicles', 'stamina', 'medic', 'support', 'firefighting' }

-- Rang- und Skill-Statebags auf den aktiven Job setzen (Zweige, die der Job
-- nicht hat, stehen auf 0 - so verschwinden fremde Freischaltungen sauber)
local function syncJobStatebags(src, p)
    local state = Player(src).state
    state:set('ws:job', p.job, true)
    state:set('ws:rank', p.rank, true)
    for _, branch in ipairs(SKILL_BRANCHES) do
        state:set('ws:skill_' .. branch, p.skills[branch] or 0, true)
    end
end

-- Arbeitskopie des aktiven Jobs zurueck in jobdata schreiben
local function syncActiveJobData(p)
    local jd = p.jobdata[p.job] or {}
    p.jobdata[p.job] = jd
    jd.rank, jd.xp, jd.skillpoints, jd.skills = p.rank, p.xp, p.skillpoints, p.skills
end

local function loadPlayer(src)
    local license = getLicense(src)
    if not license then return nil end

    local name = GetPlayerName(src) or 'Unbekannt'
    local row = MySQL.single.await('SELECT * FROM players WHERE license = ?', { license })

    if not row then
        MySQL.insert.await('INSERT INTO players (license, name, job) VALUES (?, ?, ?)', { license, name, WSConfig.DefaultJob })
        row = { job = WSConfig.DefaultJob, rank = 0, xp = 0, stats = '{}', position = nil }
        print(('[ws_core] Neuer Charakter angelegt: %s (%s)'):format(name, license))
    end

    -- Progression ist je Job getrennt (jobdata = { police = {...}, ambulance = {...} });
    -- die p.rank/xp/skills/skillpoints-Felder sind die Arbeitskopie des AKTIVEN Jobs
    local jobdata = json.decode(row.jobdata or '{}') or {}
    for _, jd in pairs(jobdata) do
        if type(jd.skills) == 'string' then jd.skills = json.decode(jd.skills) or {} end
        jd.skills = jd.skills or {}
    end
    local job = row.job or WSConfig.DefaultJob
    jobdata[job] = jobdata[job] or { rank = 0, xp = 0, skillpoints = 0, skills = {} }
    local active = jobdata[job]

    local player = {
        source = src,
        license = license,
        name = name,
        job = job,
        jobdata = jobdata,
        rank = active.rank or 0,
        xp = active.xp or 0,
        stats = json.decode(row.stats or '{}') or {},
        skills = active.skills or {},
        skillpoints = active.skillpoints or 0,
        position = row.position and json.decode(row.position) or nil,
        duty = false,
    }
    Players[src] = player

    Player(src).state:set('ws:duty', false, true)
    syncJobStatebags(src, player)

    return player
end

local function savePlayer(src)
    local p = Players[src]
    if not p then return end

    local posJson = p.position and json.encode(p.position) or nil
    local ped = GetPlayerPed(src)
    if ped and ped > 0 then
        local c = GetEntityCoords(ped)
        posJson = json.encode({ x = c.x, y = c.y, z = c.z, w = GetEntityHeading(ped) })
    end

    syncActiveJobData(p)
    -- Legacy-Spalten (rank/xp/skills/skillpoints) spiegeln den aktiven Job,
    -- die eigentliche Wahrheit je Job liegt in jobdata
    MySQL.update.await('UPDATE players SET name = ?, job = ?, `rank` = ?, xp = ?, stats = ?, skills = ?, skillpoints = ?, jobdata = ?, position = ? WHERE license = ?',
        { p.name, p.job, p.rank, p.xp, json.encode(p.stats), json.encode(p.skills), p.skillpoints, json.encode(p.jobdata), posJson, p.license })
end

local function notify(src, data)
    TriggerClientEvent('ox_lib:notify', src, data)
end

local function setDuty(src, onDuty)
    local p = Players[src]
    if not p then return false end

    onDuty = onDuty == true
    if p.duty == onDuty then return true end

    p.duty = onDuty
    Player(src).state:set('ws:duty', onDuty, true)
    TriggerEvent('ws_core:dutyChanged', src, onDuty, p.job)
    TriggerClientEvent('ws_core:client:dutyChanged', src, onDuty)
    return true
end

-- /dienst nimmt den Spieler aus dem aktuellen Dienst (Off-Duty), bevor neu gewaehlt wird
RegisterNetEvent('ws_core:leaveDuty', function()
    setDuty(source, false)
end)

-- Fraktion wechseln (LSPD/EMS). Jede Laufbahn hat eigene Progression
-- (Rang/XP/Skillpunkte/Skills) - beim Wechsel wird die Arbeitskopie
-- gesichert und die des neuen Jobs geladen. Beim Wechsel Dienstende.
local function changeJob(src, job)
    if not WSConfig.Jobs[job] then return false end
    local p = Players[src]
    if not p then return false end
    if p.job ~= job then
        syncActiveJobData(p)
        p.job = job

        local active = p.jobdata[job] or { rank = 0, xp = 0, skillpoints = 0, skills = {} }
        p.jobdata[job] = active
        active.skills = active.skills or {}
        p.rank = active.rank or 0
        p.xp = active.xp or 0
        p.skillpoints = active.skillpoints or 0
        p.skills = active.skills

        if p.duty then
            p.duty = false
            Player(src).state:set('ws:duty', false, true)
            TriggerEvent('ws_core:dutyChanged', src, false, job)
        end
        syncJobStatebags(src, p)
        savePlayer(src)
    end
    return true
end

-- Waehrend der Fraktionsauswahl bekommt jeder Spieler einen eigenen
-- Routing-Bucket. Dort ist er fuer alle anderen komplett unsichtbar - das ist
-- zuverlaessiger als lokale Sichtbarkeits-Natives, die nur auf dem eigenen
-- Client wirken. Bucket 0 ist die normale Spielwelt.
local SELECTION_BUCKET_OFFSET = 1000

lib.callback.register('ws_core:enterSelection', function(src)
    SetPlayerRoutingBucket(src, SELECTION_BUCKET_OFFSET + src)
    return true
end)

lib.callback.register('ws_core:setJob', function(src, job)
    SetPlayerRoutingBucket(src, 0)
    return changeJob(src, job)
end)

-- Sicherheitsnetz: Nach einem Ressourcen-Neustart darf niemand in einem
-- Auswahl-Bucket haengen bleiben (er waere sonst dauerhaft unsichtbar).
AddEventHandler('onResourceStart', function(res)
    if res ~= cache.resource then return end
    for _, id in ipairs(GetPlayers()) do
        SetPlayerRoutingBucket(tonumber(id), 0)
    end
end)

-- Laufbahn-Uebersicht fuer den Fraktions-Auswahlbildschirm
lib.callback.register('ws_core:getCareers', function(src)
    local p = Players[src]
    if not p then return {} end
    syncActiveJobData(p)

    local out = {}
    for jobId, j in pairs(WSConfig.Jobs) do
        local jd = p.jobdata[jobId] or {}
        local rank = jd.rank or 0
        local rd = j.ranks[rank]
        out[jobId] = {
            label = j.label,
            short = j.short,
            rankLabel = rd and rd.label or '',
            xp = jd.xp or 0,
        }
    end
    return out
end)
exports('ChangeJob', changeJob)
exports('GetJob', function(src)
    local p = Players[src]
    return p and p.job or nil
end)

local function addXP(src, amount, reason)
    local p = Players[src]
    if not p or amount <= 0 then return end

    p.xp = p.xp + math.floor(amount)
    notify(src, {
        title = locale('xp_title'),
        description = locale('xp_gained', math.floor(amount), reason or locale('xp_reason_generic')),
        type = 'success',
    })

    local newRank = getRankForXP(p.job, p.xp)
    if newRank > p.rank then
        -- Jede Befoerderungsstufe bringt einen Skillpunkt
        p.skillpoints = p.skillpoints + (newRank - p.rank)
        p.rank = newRank
        Player(src).state:set('ws:rank', newRank, true)
        local rankData = getRankData(p.job, newRank)
        notify(src, {
            title = locale('promotion_title'),
            description = locale('promotion_desc', rankData and rankData.label or tostring(newRank)),
            type = 'success',
            duration = 10000,
        })
        notify(src, {
            title = locale('skill_title'),
            description = locale('skillpoint_gained'),
            type = 'inform',
            duration = 10000,
        })
        TriggerEvent('ws_core:rankChanged', src, newRank, p.job)
    end
end

local function addStat(src, key, n)
    local p = Players[src]
    if not p then return end
    p.stats[key] = (p.stats[key] or 0) + (n or 1)
end

-- Client fordert seinen Charakter an (beim Spawn / Resource-Neustart)
lib.callback.register('ws_core:requestCharacter', function(src)
    local p = Players[src] or loadPlayer(src)
    if not p then return nil end

    local rankData = getRankData(p.job, p.rank)
    return {
        name = p.name,
        job = p.job,
        rank = p.rank,
        rankLabel = rankData and rankData.label or '',
        xp = p.xp,
        stats = p.stats,
        position = p.position,
    }
end)

-- Exports fuer ws_police / ws_dispatch
exports('GetPlayer', function(src) return Players[src] end)
exports('IsOnDuty', function(src)
    local p = Players[src]
    return p ~= nil and p.duty
end)
exports('GetRank', function(src)
    local p = Players[src]
    return p and p.rank or 0
end)
exports('SetDuty', setDuty)
exports('AddXP', addXP)
exports('AddStat', addStat)
exports('GetStat', function(src, key)
    local p = Players[src]
    return (p and p.stats[key]) or 0
end)
-- Direkter Setter (nicht additiv wie AddStat) - auch fuer persistente
-- Praeferenzen im stats-Blob nutzbar (z.B. gewaehlte Verstaerkungs-Stufe)
exports('SetStat', function(src, key, value)
    local p = Players[src]
    if p then p.stats[key] = value end
end)
exports('GetOnDutyPlayers', function(job)
    local result = {}
    for src, p in pairs(Players) do
        if p.duty and (not job or p.job == job) then
            result[#result + 1] = src
        end
    end
    return result
end)
exports('GetRankList', function(job)
    local jobData = WSConfig.Jobs[job or WSConfig.DefaultJob]
    if not jobData then return {} end
    local list = {}
    local g = 0
    while jobData.ranks[g] do
        list[#list + 1] = { grade = g, label = jobData.ranks[g].label, xp = jobData.ranks[g].xp }
        g = g + 1
    end
    return list
end)
-- Admin-Eingriff: XP/Rang/Skills einer BELIEBIGEN Laufbahn des Spielers setzen
-- (job optional, Standard = aktive Laufbahn). XP-Aenderung leitet den Rang ab,
-- Rang-Aenderung setzt die XP auf die Rang-Schwelle; XP-Eingabe gewinnt.
exports('AdminSetPlayerData', function(target, changes, job)
    local p = Players[target]
    if not p or type(changes) ~= 'table' then return false end

    job = job or p.job
    local jobCfg = WSConfig.Jobs[job]
    if not jobCfg then return false end

    syncActiveJobData(p)
    local jd = p.jobdata[job] or { rank = 0, xp = 0, skillpoints = 0, skills = {} }
    p.jobdata[job] = jd
    jd.skills = jd.skills or {}

    local ranks = jobCfg.ranks
    local maxRank = 0
    while ranks[maxRank + 1] do maxRank = maxRank + 1 end

    local newXp, newRank
    if changes.xp ~= nil then
        newXp = math.max(0, math.floor(tonumber(changes.xp) or jd.xp or 0))
    end
    if changes.rank ~= nil then
        newRank = math.min(maxRank, math.max(0, math.floor(tonumber(changes.rank) or jd.rank or 0)))
    end

    if newXp ~= nil and newXp ~= (jd.xp or 0) then
        jd.xp = newXp
        jd.rank = getRankForXP(job, jd.xp)
    elseif newRank ~= nil and newRank ~= (jd.rank or 0) then
        jd.rank = newRank
        jd.xp = ranks[newRank] and ranks[newRank].xp or jd.xp or 0
    end

    if changes.skillpoints ~= nil then
        jd.skillpoints = math.max(0, math.floor(tonumber(changes.skillpoints) or jd.skillpoints or 0))
    end
    for _, branch in ipairs(SKILL_BRANCHES) do
        if changes[branch] ~= nil then
            jd.skills[branch] = math.min(WSConfig.MaxSkillLevel, math.max(0, math.floor(tonumber(changes[branch]) or 0)))
        end
    end

    -- Bearbeitete Laufbahn ist gerade aktiv? Arbeitskopie + Statebags anpassen
    if job == p.job then
        p.rank = jd.rank or 0
        p.xp = jd.xp or 0
        p.skillpoints = jd.skillpoints or 0
        p.skills = jd.skills
        syncJobStatebags(target, p)
    end

    savePlayer(target)
    notify(target, {
        title = locale('admin_title'),
        description = locale('admin_adjusted'),
        type = 'inform',
    })
    return true
end)
exports('GetRankProgress', function(src)
    local p = Players[src]
    if not p then return nil end
    local ranks = WSConfig.Jobs[p.job].ranks
    local current = ranks[p.rank]
    local nextRank = ranks[p.rank + 1]
    return {
        xp = p.xp,
        rank = p.rank,
        rankLabel = current and current.label or '',
        currentThreshold = current and current.xp or 0,
        nextThreshold = nextRank and nextRank.xp or nil,
        nextRankLabel = nextRank and nextRank.label or nil,
    }
end)
exports('GetSkill', function(src, branch)
    local p = Players[src]
    return p and (p.skills[branch] or 0) or 0
end)
exports('GetSkillInfo', function(src)
    local p = Players[src]
    if not p then return nil end
    local info = {
        points = p.skillpoints,
        maxLevel = WSConfig.MaxSkillLevel,
        branches = WSConfig.Jobs[p.job].skills,
    }
    -- Alle Zweige generisch mitgeben (nicht hart codiert), sonst fehlt ein neu
    -- hinzugefuegter Zweig wie 'support' und laesst sich im Tablet nicht leveln
    for _, branch in ipairs(SKILL_BRANCHES) do
        info[branch] = p.skills[branch] or 0
    end
    return info
end)
exports('UpgradeSkill', function(src, branch)
    local p = Players[src]
    if not p then return false end
    -- Nur Zweige des eigenen Jobs sind skillbar
    local allowed = false
    for _, b in ipairs(WSConfig.Jobs[p.job].skills or {}) do
        if b == branch then allowed = true break end
    end
    if not allowed then return false end

    local level = p.skills[branch] or 0
    if level >= WSConfig.MaxSkillLevel then return false end
    if p.skillpoints < 1 then return false end

    p.skillpoints = p.skillpoints - 1
    p.skills[branch] = level + 1
    Player(src).state:set('ws:skill_' .. branch, level + 1, true)
    savePlayer(src)
    return true
end)
exports('GetOnlinePlayersInfo', function()
    local list = {}
    for src, p in pairs(Players) do
        syncActiveJobData(p)
        local rankData = getRankData(p.job, p.rank)

        -- Alle Laufbahnen fuer den Admin-Tab (auch nie gestartete, mit 0-Werten)
        local careers = {}
        for jobId, jcfg in pairs(WSConfig.Jobs) do
            local jd = p.jobdata[jobId] or {}
            local skills = jd.skills or {}
            local rd = jcfg.ranks[jd.rank or 0]
            local career = {
                rank = jd.rank or 0,
                rankLabel = rd and rd.label or '',
                xp = jd.xp or 0,
                skillpoints = jd.skillpoints or 0,
            }
            -- Skill-Zweige generisch (sonst fehlt ein neuer Zweig wie 'support')
            for _, branch in ipairs(SKILL_BRANCHES) do
                career[branch] = skills[branch] or 0
            end
            careers[jobId] = career
        end

        list[#list + 1] = {
            source = src,
            name = p.name,
            job = p.job,
            rank = p.rank,
            rankLabel = rankData and rankData.label or '',
            xp = p.xp,
            duty = p.duty,
            arrests = p.stats.arrests or 0,
            callouts = p.stats.callouts or 0,
            skillpoints = p.skillpoints,
            careers = careers,
        }
    end
    return list
end)

AddEventHandler('playerDropped', function()
    local src = source
    if not Players[src] then return end
    savePlayer(src)
    Players[src] = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= cache.resource then return end
    for src in pairs(Players) do
        savePlayer(src)
    end
end)

CreateThread(function()
    while true do
        Wait(WSConfig.SaveInterval * 60000)
        for src in pairs(Players) do
            savePlayer(src)
        end
    end
end)
