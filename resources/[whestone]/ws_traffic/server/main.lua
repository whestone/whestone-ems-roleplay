lib.locale()

-- Datensatz je kontrolliertem Fahrzeug (netId). Wird beim ersten Zugriff
-- generiert, bleibt fuer die Kontrolle konsistent und wird beim Abschluss
-- (Verwarnung/Bussgeld/Festnahme/Freigabe) wieder verworfen.
local Records = {}

local function roll(chance)
    return math.random(100) <= chance
end

local function generateRecord()
    local c = WSTraffic.Chances

    local license = 'valid'
    if roll(c.licenseRevoked) then
        license = 'revoked'
    elseif roll(c.licenseExpired) then
        license = 'expired'
    end

    local registration = roll(c.noRegistration) and 'missing' or 'valid'
    local drunk = roll(c.drunk)
    local contraband = roll(c.contraband)

    local rec = {
        name = WSTraffic.Names[math.random(#WSTraffic.Names)],
        plate = ('%s%03d'):format(string.char(math.random(65, 90), math.random(65, 90)), math.random(0, 999)),
        license = license,
        registration = registration,
        drunk = drunk,
        promille = drunk and (math.random(60, 180) / 100) or (math.random(0, 40) / 100),
        contraband = contraband,
        flee = roll(c.fleeRisk),
    }
    rec.hasViolation = license ~= 'valid' or registration == 'missing' or drunk or contraband
    return rec
end

local function getRecord(netId)
    if not Records[netId] then
        Records[netId] = generateRecord()
    end
    return Records[netId]
end

lib.callback.register('ws_traffic:getRecord', function(src, netId)
    if not exports.ws_core:IsOnDuty(src) then return nil end
    return getRecord(netId)
end)

-- Abschluss: Verwarnung (immer XP) oder Bussgeld (nur bei echtem Verstoss)
lib.callback.register('ws_traffic:issueOutcome', function(src, netId, kind)
    if not exports.ws_core:IsOnDuty(src) then return false end
    local rec = getRecord(netId)

    if kind == 'warn' then
        exports.ws_core:AddXP(src, WSTraffic.WarnXP, locale('xp_warn'))
        exports.ws_core:AddStat(src, 'warnings', 1)
        Records[netId] = nil
        return { ok = true }
    elseif kind == 'ticket' then
        if not rec.hasViolation then
            return { ok = false, reason = 'no_violation' }
        end
        exports.ws_core:AddXP(src, WSTraffic.TicketXP, locale('xp_ticket'))
        exports.ws_core:AddStat(src, 'tickets', 1)
        Records[netId] = nil
        return { ok = true }
    end
    return false
end)

-- Festnahme beginnen: liefert das Fluchtverhalten. Kooperative Fahrer werden
-- direkt als externer Verdaechtiger registriert (voller Festnahme-Ablauf).
-- netId = Fahrzeug (fuer den Datensatz), driverNetId = Fahrer-Ped (wird als
-- Verdaechtiger registriert!). Registrierung muss auf dem Ped erfolgen, sonst
-- landen die Suspect-Statebags auf dem Auto und die Festnahme-Option fehlt.
lib.callback.register('ws_traffic:beginArrest', function(src, netId, driverNetId)
    if not exports.ws_core:IsOnDuty(src) then return false end
    local rec = getRecord(netId)

    if rec.flee then
        return { flee = true }
    end

    local uid = exports.ws_dispatch:RegisterExternalSuspect(src, driverNetId, { label = locale('case_label') })
    Records[netId] = nil
    return { flee = false, uid = uid }
end)

-- Gefluechteter Fahrer gestellt -> Fahrer-Ped als externer Verdaechtiger registrieren
lib.callback.register('ws_traffic:registerCaught', function(src, driverNetId)
    if not exports.ws_core:IsOnDuty(src) then return false end
    local uid = exports.ws_dispatch:RegisterExternalSuspect(src, driverNetId, { label = locale('case_label') })
    return { uid = uid }
end)

-- Fahrer weitergefahren -> Datensatz verwerfen
RegisterNetEvent('ws_traffic:release', function(netId)
    Records[netId] = nil
end)
