lib.locale()

local ActiveVehicles = {}

local function isFire(src)
    return exports.ws_core:GetJob(src) == 'fire'
end

local function deleteVehicle(src)
    local veh = ActiveVehicles[src]
    if veh and DoesEntityExist(veh) then DeleteEntity(veh) end
    ActiveVehicles[src] = nil
end

lib.callback.register('ws_fire:isAdmin', function(src)
    return IsPlayerAceAllowed(src, 'ws.admin')
end)

lib.callback.register('ws_fire:setDuty', function(src, onDuty)
    if not isFire(src) then return false end
    return exports.ws_core:SetDuty(src, onDuty)
end)

lib.callback.register('ws_fire:spawnVehicle', function(src, model)
    if not isFire(src) or not exports.ws_core:IsOnDuty(src) then return nil end

    local entry
    for _, v in ipairs(WSFire.Vehicles) do
        if v.model == model then entry = v break end
    end
    if not entry or exports.ws_core:GetRank(src) < (entry.minRank or 0) then return nil end

    deleteVehicle(src)

    local sp = WSFire.Station.garageSpawn
    local veh = CreateVehicle(joaat(model), sp.x, sp.y, sp.z, sp.w, true, true)
    if not veh or veh == 0 then return false, 'model' end

    local tries = 0
    while not DoesEntityExist(veh) and tries < 100 do Wait(25) tries = tries + 1 end
    if not DoesEntityExist(veh) then return false, 'model' end

    ActiveVehicles[src] = veh
    return NetworkGetNetworkIdFromEntity(veh)
end)

lib.callback.register('ws_fire:returnVehicle', function(src)
    local veh = ActiveVehicles[src]
    if not veh or not DoesEntityExist(veh) then
        ActiveVehicles[src] = nil
        return false
    end
    if #(GetEntityCoords(veh) - WSFire.Station.garage) > 60.0 then return false end
    deleteVehicle(src)
    return true
end)

AddEventHandler('ws_core:dutyChanged', function(src, onDuty)
    if not onDuty then deleteVehicle(src) end
end)

AddEventHandler('playerDropped', function()
    deleteVehicle(source)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= cache.resource then return end
    for src in pairs(ActiveVehicles) do deleteVehicle(src) end
end)
