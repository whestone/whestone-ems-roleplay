-- Ambient-Gang-Gruppen (Ballas, Vagos, Families etc.). Genutzt fuer On-sight-
-- Frieden UND die gezielte Pazifizierung, damit Gangs auch bei Feuerwehr-
-- Einsaetzen in ihrem Gebiet nicht aggressiv werden.
local AMBIENT_GANGS = {
    'AMBIENT_GANG_BALLAS', 'AMBIENT_GANG_MEXICAN', 'AMBIENT_GANG_FAMILY',
    'AMBIENT_GANG_MARABUNTE', 'AMBIENT_GANG_SALVA', 'AMBIENT_GANG_LOST',
    'AMBIENT_GANG_HILLBILLY', 'AMBIENT_GANG_CULT', 'AMBIENT_GANG_WEICHENG',
}
local gangGroupHashes = {}
for _, g in ipairs(AMBIENT_GANGS) do gangGroupHashes[joaat(g)] = true end

-- PvE-Grundregeln: keine KI-Polizei, kein Wanted-Level, kein Spielerschaden untereinander
CreateThread(function()
    NetworkSetFriendlyFireAllowed(false)
    SetMaxWantedLevel(0)
    SetWantedLevelMultiplier(0.0)
    for i = 1, 15 do
        EnableDispatchService(i, false)
    end

    -- GTA-Flug-Score beim Heli-/Flugzeugfliegen abschalten
    SetAudioFlag('DisableFlightMusic', true)

    -- Ambient-Gangs greifen Spieler nicht mehr an (On-sight)
    local playerGroup = joaat('PLAYER')
    for hash in pairs(gangGroupHashes) do
        SetRelationshipBetweenGroups(1, hash, playerGroup)
        SetRelationshipBetweenGroups(1, playerGroup, hash)
    end
end)

CreateThread(function()
    while true do
        SetCreateRandomCops(false)
        SetCreateRandomCopsNotOnScenarios(false)
        SetCreateRandomCopsOnScenarios(false)
        SetPedDropsWeaponsWhenDead(cache.ped, false) -- eigene Waffe faellt beim Tod nicht
        -- Wanted-System komplett aus: KI-Polizei ignoriert den Spieler, kein
        -- Cop-Dispatch fuer ihn (setzt sich nach Respawn zurueck -> auffrischen)
        SetPoliceIgnorePlayer(cache.playerId, true)
        SetDispatchCopsForPlayer(cache.playerId, false)
        SetMaxWantedLevel(0)
        SetWantedLevelMultiplier(0.0)
        SetAudioFlag('DisableFlightMusic', true) -- Flug-Score aus (nach Respawn erneut)
        Wait(5000)
    end
end)

-- Ambient-Peds befrieden: KEINE Waffendrops (alle NPCs) und keine Aggression
-- bei ALLEN Ambient-Peds -- auch wenn man in ihrer Naehe Feuer loescht und sie
-- dabei Feuer/Schaden abbekommen. Script-Peds (Dispatch-Taeter, EMS-Patienten)
-- sind Mission-Entities und bleiben bewusst unberuehrt.
CreateThread(function()
    while true do
        for _, ped in ipairs(GetGamePool('CPed')) do
            if not IsPedAPlayer(ped) then
                SetPedDropsWeaponsWhenDead(ped, false)
                -- alle Ambient-Peds ignorieren Spieler/Feuer/Schaden -> nicht feindlich
                if not IsEntityAMissionEntity(ped) then
                    SetBlockingOfNonTemporaryEvents(ped, true)
                end
            end
        end
        Wait(1000)
    end
end)

-- Sicherheitsnetz: verbliebene Sterne loeschen. Da SetMaxWantedLevel(0) +
-- Multiplikator 0 + SetPoliceIgnorePlayer das Aufkommen bereits verhindern,
-- reicht ein kurzes Intervall - ein Frame-genauer Check waere Verschwendung.
CreateThread(function()
    while true do
        Wait(500)
        if GetPlayerWantedLevel(cache.playerId) > 0 then
            ClearPlayerWantedLevel(cache.playerId)
            SetPlayerWantedLevel(cache.playerId, 0, false)
            SetPlayerWantedLevelNow(cache.playerId, false)
        end
    end
end)
