-- Entriegelt fortlaufend alle aktiven Tueren des GTA-Tuersystems (Bank-
-- Schaltertueren, Gebaeudetueren usw.). So sind hinter Tresen gespawnte
-- Verdaechtige erreichbar. Tueren registrieren sich, sobald sie in die Naehe
-- kommen - deshalb periodisch neu durchgehen.

if not WSConfig.UnlockAllDoors then return end

CreateThread(function()
    while true do
        local doors = DoorSystemGetActive()
        if type(doors) == 'table' then
            for doorHash in pairs(doors) do
                -- Nur schreiben, wenn die Tuer wirklich verriegelt ist. Der
                -- Lesezugriff ist billiger als der Schreibzugriff, und in der
                -- Regel ist beim zweiten Durchlauf schon alles offen - spart
                -- bei vielen aktiven Tueren fast alle Aufrufe.
                -- (Zustand 0 = entriegelt / frei schwingend)
                if DoorSystemGetDoorState(doorHash) ~= 0 then
                    DoorSystemSetDoorState(doorHash, 0, false, false)
                end
            end
        end
        Wait(4000)
    end
end)
