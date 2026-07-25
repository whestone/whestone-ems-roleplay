lib.locale()

-- ---------------------------------------------------------------------------
-- Rollenspiel-Texte (/me, /do)
-- ---------------------------------------------------------------------------

local COLORS = {
    me = { 178, 120, 240 }, -- lila: eigene Handlung
    ['do'] = { 90, 180, 235 }, -- blau: Umstand/Zustand
}

RegisterNetEvent('ws_social:rpText', function(kind, text)
    local src = source
    if kind ~= 'me' and kind ~= 'do' then return end
    if type(text) ~= 'string' then return end

    -- '~' entfernen (sonst koennte man Farb-/Steuercodes in die Text-Native
    -- einschleusen), Laenge begrenzen, Leerraum kappen
    text = text:gsub('~', ''):gsub('%s+', ' '):sub(1, 120)
    text = text:match('^%s*(.-)%s*$')
    if text == '' then return end

    TriggerClientEvent('ws_social:rpText', -1, src, text, COLORS[kind])
end)

-- ---------------------------------------------------------------------------
-- Dienstzeit-Erfassung + Rangliste
-- ---------------------------------------------------------------------------

-- Laufendes Dienstintervall je Spieler (Start-Zeitstempel). Wird periodisch
-- und bei Dienstende in die persistente Statistik 'dutyseconds' committet.
local onDutySince = {}

local function commit(src)
    local since = onDutySince[src]
    if not since then return end
    local delta = os.time() - since
    if delta > 0 then exports.ws_core:AddStat(src, 'dutyseconds', delta) end
    onDutySince[src] = os.time()
end

AddEventHandler('ws_core:dutyChanged', function(src, onDuty)
    if onDuty then
        onDutySince[src] = os.time()
    else
        commit(src)
        onDutySince[src] = nil
    end
end)

AddEventHandler('playerDropped', function()
    commit(source)
    onDutySince[source] = nil
end)

-- Regelmaessig sichern, damit auch lange Dauerdienste in der DB landen
CreateThread(function()
    while true do
        Wait(120000)
        for src in pairs(onDutySince) do commit(src) end
    end
end)

lib.callback.register('ws_social:getDutyTime', function(src)
    -- Eigener Wert: persistierte Sekunden (In-Memory, sofort aktuell) plus die
    -- noch nicht committete Zeit des laufenden Intervalls
    local own = exports.ws_core:GetStat(src, 'dutyseconds')
    if onDutySince[src] then own = own + (os.time() - onDutySince[src]) end

    -- Rangliste ueber alle je gespeicherten Spieler
    local rows = MySQL.query.await(
        "SELECT `name`, CAST(JSON_VALUE(`stats`, '$.dutyseconds') AS UNSIGNED) AS secs " ..
        "FROM `players` WHERE JSON_VALUE(`stats`, '$.dutyseconds') IS NOT NULL " ..
        "ORDER BY secs DESC LIMIT ?", { WSSocial.BoardSize }) or {}

    local board = {}
    for _, r in ipairs(rows) do
        board[#board + 1] = { name = r.name, secs = r.secs or 0 }
    end
    return { own = own, board = board }
end)
