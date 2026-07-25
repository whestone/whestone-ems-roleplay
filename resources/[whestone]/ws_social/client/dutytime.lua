lib.locale()

-- Dienstzeit-Rangliste (/dienstzeit): eigene Gesamt-Dienstzeit + Top-Liste.

local function fmt(secs)
    secs = math.floor(secs or 0)
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then return ('%dh %dm'):format(h, m) end
    return ('%dm'):format(m)
end

RegisterCommand('dienstzeit', function()
    local data = lib.callback.await('ws_social:getDutyTime', false)
    if not data then return end

    local options = {
        {
            title = locale('duty_own'),
            description = fmt(data.own),
            icon = 'stopwatch',
            readOnly = true,
        },
    }

    local medals = { '🥇', '🥈', '🥉' }
    for i, entry in ipairs(data.board) do
        options[#options + 1] = {
            title = ('%s %d. %s'):format(medals[i] or '  ', i, entry.name),
            description = fmt(entry.secs),
            readOnly = true,
        }
    end

    if #data.board == 0 then
        options[#options + 1] = { title = locale('duty_board_empty'), readOnly = true }
    end

    lib.registerContext({ id = 'ws_social_dutytime', title = locale('duty_board_title'), options = options })
    lib.showContext('ws_social_dutytime')
end, false)
