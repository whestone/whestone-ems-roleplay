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

    -- Ambient-Gangs (Ballas, Vagos, Families etc.) greifen Spieler nicht mehr an
    local playerGroup = joaat('PLAYER')
    local gangs = {
        'AMBIENT_GANG_BALLAS', 'AMBIENT_GANG_MEXICAN', 'AMBIENT_GANG_FAMILY',
        'AMBIENT_GANG_MARABUNTE', 'AMBIENT_GANG_SALVA', 'AMBIENT_GANG_LOST',
        'AMBIENT_GANG_HILLBILLY', 'AMBIENT_GANG_CULT', 'AMBIENT_GANG_WEICHENG',
    }
    for _, gang in ipairs(gangs) do
        local gangGroup = joaat(gang)
        SetRelationshipBetweenGroups(1, gangGroup, playerGroup)
        SetRelationshipBetweenGroups(1, playerGroup, gangGroup)
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
