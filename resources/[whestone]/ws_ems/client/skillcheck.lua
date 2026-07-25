-- Robuster Wrapper um lib.skillCheck.
--
-- ox_lib haelt den laufenden Check in einer eigenen Promise. Bleibt die
-- haengen - die NUI loest nie auf, z.B. weil ein Ressourcen-Neustart
-- dazwischenkam oder ihr der Fokus entzogen wurde -, liefert JEDER weitere
-- lib.skillCheck sofort nil zurueck und das Minispiel erscheint nie wieder.
-- Da die Promise in ox_lib liegt, hilft ein Neustart von ws_ems nicht.
--
-- Ohne diese Unterscheidung wird nil wie "verpatzt" gewertet: bei der
-- Reanimation zaehlt das als Fehlversuch und der Patient stirbt nach drei
-- Fehlschlaegen, die es nie gab.
--
---@param difficulty string|table Schwierigkeit(en) fuer lib.skillCheck
---@return boolean|nil true = bestanden, false = verpatzt, nil = nicht startbar
function WSSkillCheck(difficulty)
    local t = type(difficulty)
    if t ~= 'table' and t ~= 'string' then
        print('^1[ws_ems] Ungueltige Skillcheck-Konfiguration (WSEms.DefiChecks)^7')
        return nil
    end

    -- Haengengebliebenen Check aufloesen, damit ein einmaliger Fehler das
    -- Minispiel nicht bis zum naechsten ox_lib-Neustart blockiert
    if lib.skillCheckActive() then
        pcall(lib.cancelSkillCheck)
        local deadline = GetGameTimer() + 1000
        while lib.skillCheckActive() and GetGameTimer() < deadline do Wait(50) end
        if lib.skillCheckActive() then
            print('^3[ws_ems] Skillcheck haengt fest - konnte nicht zurueckgesetzt werden^7')
            return nil
        end
    end

    return lib.skillCheck(difficulty)
end
