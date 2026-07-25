lib.locale()

-- Rollenspiel-Befehle /me und /do: schwebender Text ueber dem Kopf, fuer alle
-- Spieler in der Naehe sichtbar. /me = eigene Handlung, /do = Umstand/Zustand.

local active = {} -- serverId -> { text, color, until }

local function draw3dText(coords, text, color)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z + 1.0)
    if not onScreen then return end

    -- Skalierung nach Entfernung zur Kamera
    local cam = GetGameplayCamCoord()
    local dist = #(cam - coords)
    local scale = math.max(0.28, (1.0 / dist) * 4.0 * (1.0 / GetGameplayCamFov()) * 90.0)

    SetTextScale(0.0, scale)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(color[1], color[2], color[3], 220)
    SetTextDropShadow()
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentSubstringPlayerName(text)
    DrawText(x, y)
end

CreateThread(function()
    while true do
        local wait = 500
        if next(active) then
            wait = 0
            local now = GetGameTimer()
            local myPos = GetEntityCoords(cache.ped)
            for serverId, entry in pairs(active) do
                if now > entry.expires then
                    active[serverId] = nil
                else
                    local ped = (serverId == GetPlayerServerId(PlayerId()))
                        and cache.ped
                        or GetPlayerPed(GetPlayerFromServerId(serverId))
                    if ped and ped ~= 0 and DoesEntityExist(ped) then
                        local pos = GetEntityCoords(ped)
                        if #(myPos - pos) <= WSSocial.RpRange then
                            draw3dText(pos, entry.text, entry.color)
                        end
                    end
                end
            end
        end
        Wait(wait)
    end
end)

RegisterNetEvent('ws_social:rpText', function(serverId, text, color)
    active[serverId] = {
        text = text,
        color = color,
        expires = GetGameTimer() + WSSocial.RpDuration,
    }
end)

local function sendRp(kind, args)
    local text = table.concat(args, ' ')
    if text == '' then
        lib.notify({ title = locale('rp_title'), description = locale('rp_empty'), type = 'error' })
        return
    end
    TriggerServerEvent('ws_social:rpText', kind, text)
end

RegisterCommand('me', function(_, args) sendRp('me', args) end, false)
RegisterCommand('do', function(_, args) sendRp('do', args) end, false)
