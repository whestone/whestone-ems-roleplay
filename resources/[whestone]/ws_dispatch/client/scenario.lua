-- Szenario-Runner: fuehrt Callout-Szenarien auf dem Primary-Client aus.
-- Callout-Handler registrieren sich ueber RegisterCalloutHandler(id, { onStart = fn }).

lib.locale()

local handlers = {}
local active ---@type table|nil  aktueller Szenario-Kontext

Scenario = {}

function RegisterCalloutHandler(id, handler)
    handlers[id] = handler
end

-- Zufallshelfer fuer Szenarien (Modelle, Varianten)
function PickRandom(list)
    return list[math.random(#list)]
end

local SUSPECT_GROUP = joaat('WS_SUSPECT')
local HOSTILE_GROUP = joaat('WS_HOSTILE')
local PLAYER_GROUP = joaat('PLAYER')
-- Neutrale Gruppe fuer Ergebene/Gefesselte: sie greifen niemanden an und
-- werden von der KI-Verstaerkung (WS_BACKUP) nicht mehr beschossen.
local PRISONER_GROUP = joaat('WS_PRISONER')

CreateThread(function()
    AddRelationshipGroup('WS_SUSPECT')
    AddRelationshipGroup('WS_HOSTILE')
    AddRelationshipGroup('WS_PRISONER')
    SetRelationshipBetweenGroups(4, SUSPECT_GROUP, PLAYER_GROUP)
    SetRelationshipBetweenGroups(5, HOSTILE_GROUP, PLAYER_GROUP)
    SetRelationshipBetweenGroups(1, PRISONER_GROUP, PLAYER_GROUP)
    SetRelationshipBetweenGroups(1, PLAYER_GROUP, PRISONER_GROUP)
end)

function EnsureControl(entity)
    if not DoesEntityExist(entity) then return false end
    if NetworkHasControlOfEntity(entity) then return true end
    NetworkRequestControlOfEntity(entity)
    local tries = 0
    while not NetworkHasControlOfEntity(entity) and tries < 50 do
        Wait(20)
        tries = tries + 1
    end
    return NetworkHasControlOfEntity(entity)
end

-- ---------------------------------------------------------------------------
-- Kontext-API fuer Szenarien
-- ---------------------------------------------------------------------------

local function buildContext(callout)
    local ctx = {
        uid = callout.uid,
        id = callout.id,
        coords = callout.coords,
        suspects = {},   -- netId -> { ped, netId, opts, resolved, proxTime, fleeing }
        objectives = {}, -- netId -> { kind, resolved }
        tickFns = {},
        extraComplete = nil,
        stopped = false,
    }

    local function register(entity, kind)
        local netId = NetworkGetNetworkIdFromEntity(entity)
        SetNetworkIdCanMigrate(netId, true)
        TriggerServerEvent('ws_dispatch:registerEntity', ctx.uid, netId, kind)
        return netId
    end

    ---@param opts? { suspect?: boolean, injured?: boolean, weapon?: string, armour?: number, accuracy?: number, hostile?: boolean, surrender?: table }
    function ctx.spawnPed(model, coords, heading, opts)
        opts = opts or {}
        local hash = joaat(model)
        lib.requestModel(hash, 10000)
        local ped = CreatePed(4, hash, coords.x, coords.y, coords.z, heading or 0.0, true, true)
        SetModelAsNoLongerNeeded(hash)
        SetEntityAsMissionEntity(ped, true, true)
        SetPedRelationshipGroupHash(ped, opts.hostile and HOSTILE_GROUP or SUSPECT_GROUP)
        SetPedFleeAttributes(ped, 0, false)
        SetPedDropsWeaponsWhenDead(ped, false) -- keine Waffe faellt auf den Boden

        if opts.weapon then
            GiveWeaponToPed(ped, joaat(opts.weapon), 120, false, true)
            SetPedAccuracy(ped, opts.accuracy or 15)
        end
        if opts.armour then SetPedArmour(ped, opts.armour) end

        local kind = 'prop'
        if opts.suspect then kind = 'suspect' elseif opts.injured then kind = 'injured' end
        local netId = register(ped, kind)

        if opts.suspect then
            -- Roter Blip, damit fluechtende Verdaechtige verfolgbar bleiben
            local blip = AddBlipForEntity(ped)
            SetBlipSprite(blip, 1)
            SetBlipColour(blip, 1)
            SetBlipScale(blip, 0.85)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(locale('suspect_blip'))
            EndTextCommandSetBlipName(blip)

            ctx.suspects[netId] = {
                ped = ped,
                netId = netId,
                opts = opts,
                resolved = false,
                proxTime = 0,
                blip = blip,
            }
        elseif opts.injured then
            ctx.objectives[netId] = { kind = 'injured', resolved = false, ped = ped }
            lib.requestAnimDict('dead')
            TaskPlayAnim(ped, 'dead', 'dead_a', 8.0, -8.0, -1, 1, 0.0, false, false, false)
            SetBlockingOfNonTemporaryEvents(ped, true)
        end

        return ped, netId
    end

    ---@param opts? { wreck?: boolean }
    function ctx.spawnVehicle(model, coords, heading, opts)
        opts = opts or {}
        local hash = joaat(model)
        lib.requestModel(hash, 10000)
        local veh = CreateVehicle(hash, coords.x, coords.y, coords.z, heading or 0.0, true, true)
        SetModelAsNoLongerNeeded(hash)
        SetEntityAsMissionEntity(veh, true, true)

        local kind = 'prop'
        if opts.wreck then
            kind = 'wreck'
            SetVehicleEngineHealth(veh, 100.0)
            SetVehicleBodyHealth(veh, 200.0)
            SetVehicleTyreBurst(veh, 0, true, 1000.0)
            SetVehicleDoorOpen(veh, 4, false, false)
            SmashVehicleWindow(veh, 0)
            SetVehicleEngineOn(veh, false, true, true)
        end

        local netId = register(veh, kind)
        if opts.wreck then
            ctx.objectives[netId] = { kind = 'wreck', resolved = false, ent = veh }
        end
        return veh, netId
    end

    function ctx.setSurrendered(suspect)
        if suspect.surrendered or suspect.resolved then return end
        suspect.surrendered = true
        local ped = suspect.ped
        if EnsureControl(ped) then
            ClearPedTasksImmediately(ped)
            RemoveAllPedWeapons(ped, true)
            -- In die neutrale Gruppe: Verstaerkung schiesst nicht mehr auf ihn
            SetPedRelationshipGroupHash(ped, PRISONER_GROUP)
            SetBlockingOfNonTemporaryEvents(ped, true)
            TaskHandsUp(ped, -1, 0, -1, false)
        end
        TriggerServerEvent('ws_dispatch:updateSuspect', suspect.netId, 'surrendered', true)
    end

    function ctx.onTick(fn)
        ctx.tickFns[#ctx.tickFns + 1] = fn
    end

    return ctx
end

-- ---------------------------------------------------------------------------
-- Automatisches Verhalten: Kapitulation, Tod, Abschlusspruefung
-- ---------------------------------------------------------------------------

local function distToLocalPlayer(entity)
    return #(GetEntityCoords(entity) - GetEntityCoords(cache.ped))
end

local function removeSuspectBlip(s)
    if s.blip then
        RemoveBlip(s.blip)
        s.blip = nil
    end
end

local function suspectTick(ctx, s)
    if s.resolved or s.surrendered then return end
    local ped = s.ped

    if not DoesEntityExist(ped) or IsEntityDead(ped) then
        s.resolved = true
        removeSuspectBlip(s)
        TriggerServerEvent('ws_dispatch:suspectDown', ctx.uid, s.netId)
        return
    end

    local rules = s.opts.surrender or { onStun = true }

    if rules.onStun ~= false and IsPedBeingStunned(ped, 0) then
        return ctx.setSurrendered(s)
    end

    if rules.lowHealth then
        local health = GetEntityHealth(ped)
        local maxHealth = GetEntityMaxHealth(ped)
        if maxHealth > 0 and (health / maxHealth) < rules.lowHealth then
            return ctx.setSurrendered(s)
        end
    end

    if rules.proximity then
        if distToLocalPlayer(ped) < 10.0 and not IsPedInAnyVehicle(ped, false) then
            s.proxTime = s.proxTime + 1
            if s.proxTime >= rules.proximity then
                return ctx.setSurrendered(s)
            end
        else
            -- Langsam abbauen statt hart zuruecksetzen (fairere Fussverfolgung)
            s.proxTime = math.max(0, s.proxTime - 1)
        end
    end
end

local function objectiveTick(ctx, o)
    if o.resolved then return end

    -- Wracks: haengt es am Abschlepphaken, wurde es zerstoert oder ist es
    -- verschwunden, gibt es nichts mehr zu tun -> Ziel gilt als erledigt.
    -- (Selbstheilung, falls die Server-Aufloesung nicht durchkam.)
    if o.kind == 'wreck' then
        if not o.ent or not DoesEntityExist(o.ent) or IsEntityAttached(o.ent) then
            o.resolved = true
        end
        return
    end

    if o.kind ~= 'injured' then return end

    -- Verletzte muessen liegen bleiben: Animation laufend erzwingen (geht bei
    -- Besitzerwechsel oder Task-Ende sonst verloren -> Ped steht auf)
    local ped = o.ped

    if not ped or not DoesEntityExist(ped) or IsEntityDead(ped) then
        -- verschwunden oder verstorben: nicht mehr versorgbar, Ziel freigeben
        o.resolved = true
        return
    end

    -- Von der Einsatzstelle weggelaufen (z. B. nach Besitzerwechsel
    -- aufgestanden): nicht mehr Teil der Szene, Ziel freigeben
    if #(GetEntityCoords(ped) - vector3(ctx.coords.x, ctx.coords.y, ctx.coords.z)) > 60.0 then
        o.resolved = true
        return
    end

    if NetworkHasControlOfEntity(ped) and not IsEntityPlayingAnim(ped, 'dead', 'dead_a', 3) then
        lib.requestAnimDict('dead')
        ClearPedTasksImmediately(ped)
        TaskPlayAnim(ped, 'dead', 'dead_a', 8.0, -8.0, -1, 1, 0.0, false, false, false)
        SetBlockingOfNonTemporaryEvents(ped, true)
    end
end

local function isComplete(ctx)
    for _, s in pairs(ctx.suspects) do
        if not s.resolved then return false end
    end
    for _, o in pairs(ctx.objectives) do
        if not o.resolved then return false end
    end
    if ctx.extraComplete and not ctx.extraComplete() then return false end
    return true
end

-- ---------------------------------------------------------------------------
-- Runner
-- ---------------------------------------------------------------------------

function Scenario.start(callout)
    local handler = handlers[callout.id]
    if not handler then
        print(('[ws_dispatch] Kein Handler fuer Callout "%s" registriert!'):format(callout.id))
        return
    end

    local ctx = buildContext(callout)
    active = ctx

    CreateThread(function()
        -- Szene erst aufbauen, wenn der Officer sich naehert
        while not ctx.stopped do
            local dist = #(GetEntityCoords(cache.ped) - vector3(ctx.coords.x, ctx.coords.y, ctx.coords.z))
            if dist < WSDispatch.SpawnDistance then break end
            Wait(1000)
        end
        if ctx.stopped then return end

        handler.onStart(ctx)
        TriggerServerEvent('ws_dispatch:sceneReady', ctx.uid)
        lib.notify({
            title = locale('dispatch_title'),
            description = locale('scene_ready'),
            type = 'inform',
        })

        -- Hauptschleife: Verhalten + Abschlusspruefung
        while not ctx.stopped do
            Wait(1000)
            for _, s in pairs(ctx.suspects) do
                suspectTick(ctx, s)
            end
            for _, o in pairs(ctx.objectives) do
                objectiveTick(ctx, o)
            end
            for _, fn in ipairs(ctx.tickFns) do
                fn(ctx)
            end
            if isComplete(ctx) then
                ctx.stopped = true
                TriggerServerEvent('ws_dispatch:complete', ctx.uid)
                break
            end
        end
    end)
end

function Scenario.stop(uid)
    if active and active.uid == uid then
        active.stopped = true
        for _, s in pairs(active.suspects) do
            removeSuspectBlip(s)
        end
        active = nil
    end
end

function Scenario.suspectResolved(uid, netId)
    if not active or active.uid ~= uid then return end
    local s = active.suspects[netId]
    if s then
        s.resolved = true
        removeSuspectBlip(s)
    end
end

function Scenario.objectiveResolved(uid, netId, kind)
    if not active or active.uid ~= uid then return end
    local o = active.objectives[netId]
    if not o then return end
    o.resolved = true

    -- Versorgte Verletzte stehen auf und gehen weg
    if kind == 'injured' then
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent and ent ~= 0 and DoesEntityExist(ent) and EnsureControl(ent) then
            ClearPedTasksImmediately(ent)
            TaskWanderStandard(ent, 10.0, 10)
        end
    end
end
