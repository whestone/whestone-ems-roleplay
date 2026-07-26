lib.locale()

-- Selbst gebautes Defibrillator-Minispiel, UNABHAENGIG von lib.skillCheck
-- (das auf manchen Setups die NUI nicht rendert). Reines In-Game-Rendering
-- (DrawRect/DrawText) -> funktioniert immer.
--
-- Ablauf: Fuer eine erfolgreiche Reanimation muessen MEHRERE Timing-Runden in
-- Folge getroffen werden (WSEms.Defi.rounds, Standard 3). Pro Runde zaehlt die
-- ERSTE E-Eingabe: im gruenen Feld = Treffer, sonst Runde (und Versuch) verloren.
-- Jede Runde wird etwas schneller. Ein Fehlschlag zaehlt aussen als Fehlversuch.

local function medLevel()
    return LocalPlayer.state['ws:skill_medic'] or 0
end

-- Eine einzelne Timing-Runde. Rueckgabe: true = getroffen, false = daneben/Timeout.
local function defiRound(round, total, cfg)
    local half = (cfg.hitZone or 0.10) + (cfg.hitZonePerSkill or 0.03) * medLevel()
    if half > 0.45 then half = 0.45 end
    -- jede weitere Runde schneller -> steigende Spannung
    local speed = (cfg.speed or 1.6) * (1.0 + 0.15 * (round - 1))

    local barW, barH, barX, barY = 0.26, 0.045, 0.5, 0.82
    local startT = GetGameTimer()
    local timeout = startT + 8000
    local result
    local hint = locale('defi_shock_hint', round, total)

    while result == nil and GetGameTimer() < timeout do
        -- Dreieckswelle: Marker pendelt 0 -> 1 -> 0
        local phase = ((GetGameTimer() - startT) / 1000.0 * speed) % 2.0
        local pos = phase <= 1.0 and phase or (2.0 - phase)

        DrawRect(barX, barY, barW + 0.012, barH + 0.012, 0, 0, 0, 190)          -- Rahmen
        DrawRect(barX, barY, barW * half * 2.0, barH, 46, 204, 113, 210)        -- Trefferfeld
        DrawRect(barX - barW / 2.0 + pos * barW, barY, 0.005, barH + 0.022, 255, 255, 255, 255) -- Marker

        SetTextFont(4)
        SetTextScale(0.5, 0.5)
        SetTextCentre(true)
        SetTextColour(255, 255, 255, 230)
        SetTextDropShadow()
        SetTextEntry('STRING')
        AddTextComponentSubstringPlayerName(hint)
        DrawText(barX, barY - 0.07)

        DisableControlAction(0, 38, true) -- E blocken (ox_target)
        if IsDisabledControlJustPressed(0, 38) then
            result = math.abs(pos - 0.5) <= half -- erste Eingabe zaehlt
        end
        Wait(0)
    end

    return result == true
end

-- Mehrere Treffer in Folge noetig; ein Fehlschlag beendet den Versuch.
function WSDefiMinigame()
    local cfg = WSEms.Defi or {}
    local total = cfg.rounds or 3
    for round = 1, total do
        if not defiRound(round, total, cfg) then
            return false
        end
        Wait(150) -- kurze Pause zwischen den Schocks
    end
    return true
end
