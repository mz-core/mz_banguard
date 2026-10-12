local REPORT_EVENT = 'mz_banguard:server:securityTelemetry'
local evidence = {}
local heartbeatSequence = 0
local cooldowns = {}
local lastCoords = nil
local lastPed = 0
local baselineModel = nil
local graceUntil = 0
local lastVehicle = 0
local lastVehicleExit = nil

local function nowMs()
    return math.max(0, math.floor(tonumber(GetGameTimer()) or 0))
end

local function distance(left, right)
    local x, y, z = left.x - right.x, left.y - right.y, left.z - right.z
    return math.sqrt(x * x + y * y + z * z)
end

local function markSpawn()
    local grace = math.max(
        tonumber(Config.MovementGuard and Config.MovementGuard.spawnGraceMs) or 20000,
        tonumber(Config.PlayerStateGuard and Config.PlayerStateGuard.spawnGraceMs) or 20000
    )
    graceUntil = nowMs() + math.floor(grace)
    lastCoords, baselineModel, lastPed, lastVehicle, lastVehicleExit = nil, nil, 0, 0, nil
    evidence = {}
end

local function report(code, payload)
    local currentMs = nowMs()
    if currentMs - (cooldowns[code] or 0) < 8000 then return end
    cooldowns[code] = currentMs
    TriggerServerEvent(REPORT_EVENT, code, type(payload) == 'table' and payload or {})
end

local function sample(code, active, required, payload)
    if not active then
        evidence[code] = nil
        return
    end
    local count = (evidence[code] or 0) + 1
    evidence[code] = count
    if count >= math.max(1, tonumber(required) or 3) then
        evidence[code] = nil
        report(code, payload)
    end
end

local function validPed()
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    if IsEntityDead(ped) or IsPedFatallyInjured(ped) then return nil end
    return ped
end

AddEventHandler('playerSpawned', markSpawn)
RegisterNetEvent('mz_core:client:playerLoaded', markSpawn)
RegisterNetEvent('mz_core:client:playerSpawned', markSpawn)
RegisterNetEvent('mz_core:client:characterChanged', markSpawn)

CreateThread(function()
    markSpawn()
    while true do
        local cfg = type(Config.PlayerStateGuard) == 'table' and Config.PlayerStateGuard or {}
        Wait(math.max(750, math.floor(tonumber(cfg.sampleIntervalMs) or 1500)))
        if cfg.enabled ~= true or nowMs() < graceUntil then goto continue end
        local ped = validPed()
        if not ped or not IsPlayerControlOn(PlayerId()) or not HasCollisionLoadedAroundEntity(ped) then goto continue end

        local model = GetEntityModel(ped)
        if not baselineModel then
            baselineModel = model
        else
            local changed = model ~= baselineModel
            sample('player_model_change_unapproved', changed, cfg.samples and cfg.samples.modelChange or 3, { model = model })
            if changed and evidence.player_model_change_unapproved == nil then baselineModel = model end
        end
        lastPed = ped

        local spectator = NetworkIsInSpectatorMode() == true
        sample('camera_spectate_unapproved', spectator, cfg.samples and cfg.samples.spectate or 3, { spectator = spectator })

        local camDistance = distance(GetEntityCoords(ped), GetFinalRenderedCamCoord())
        local freecam = camDistance > (tonumber(cfg.freecamDistance) or 70.0)
            and not IsCinematicCamRendering() and not IsNuiFocused()
        sample('camera_freecam_suspect', freecam, cfg.samples and cfg.samples.freecam or 4, { cameraDistance = camDistance })

        local invincible = GetPlayerInvincible(PlayerId()) == true
        local damageDisabled = not GetEntityCanBeDamaged(ped)
        -- GET_ENTITY_PROOFS returns the native result first, followed by its
        -- eight output booleans. Treating the result itself as bulletProof
        -- shifts every proof and can create a persistent false positive.
        local proofsKnown, bullet, fire, explosion, collision, melee, _, _, drown = GetEntityProofs(ped)
        local fullProofs = proofsKnown == true and bullet == true and fire == true
            and explosion == true and collision == true and melee == true and drown == true
        local gameplaySafe = not IsEntityPositionFrozen(ped) and not IsPedRagdoll(ped)
            and not IsPedFalling(ped) and not IsPedInParachuteFreeFall(ped)
            and not IsCutsceneActive() and not IsNuiFocused()
        sample('player_godmode_suspect', gameplaySafe and (invincible or damageDisabled or fullProofs),
            cfg.samples and cfg.samples.godmode or 5, {
                invincible = invincible, damageDisabled = damageDisabled, fullProofs = fullProofs,
                health = GetEntityHealth(ped), armour = GetPedArmour(ped)
            })

        local alpha = GetEntityAlpha(ped)
        local invisible = (not IsEntityVisible(ped) and not IsEntityVisibleToScript(ped))
            or alpha < (tonumber(cfg.maxInvisibleAlpha) or 120)
        sample('player_invisible_suspect', invisible, cfg.samples and cfg.samples.invisible or 5, { alpha = alpha })
        ::continue::
    end
end)

CreateThread(function()
    while true do
        local health = type(Config.DetectorHealth) == 'table' and Config.DetectorHealth or {}
        Wait(math.max(5000, math.floor(tonumber(health.heartbeatIntervalMs) or 15000)))
        if health.enabled == true then
            heartbeatSequence = (heartbeatSequence + 1) % 2147483647
            TriggerServerEvent(
                'mz_banguard:server:sensorHeartbeat',
                tostring(health.ruleVersion or 'unknown'):sub(1, 32),
                heartbeatSequence
            )
            TriggerServerEvent(
                'mz_banguard:server:resourceHeartbeat',
                GetCurrentResourceName(),
                tostring(health.ruleVersion or 'unknown'):sub(1, 32),
                heartbeatSequence
            )
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    local watched = type(Config.DetectorHealth) == 'table' and Config.DetectorHealth.watchedResources or {}
    if type(watched) == 'table' and watched[resourceName] == true then
        TriggerServerEvent('mz_banguard:server:resourceStopObserved', resourceName)
    end
end)

CreateThread(function()
    while true do
        local cfg = type(Config.MovementGuard) == 'table' and Config.MovementGuard or {}
        Wait(math.max(500, math.floor(tonumber(cfg.sampleIntervalMs) or 1000)))
        if cfg.enabled ~= true or nowMs() < graceUntil then
            lastCoords = nil
            goto continue
        end
        local ped = validPed()
        if not ped or not IsPlayerControlOn(PlayerId()) then
            lastCoords = nil
            goto continue
        end
        local coords = GetEntityCoords(ped)
        local inVehicle = IsPedInAnyVehicle(ped, false)
        local vehicle = inVehicle and GetVehiclePedIsIn(ped, false) or 0

        if lastCoords then
            local moved = distance(coords, lastCoords)
            local exempt = IsPedFalling(ped) or IsPedRagdoll(ped) or IsPedClimbing(ped)
                or IsPedVaulting(ped) or IsPedInParachuteFreeFall(ped)
                or IsPedSwimming(ped) or IsPedSwimmingUnderWater(ped)
            local teleportLimit = inVehicle and (tonumber(cfg.clientVehicleDistance) or 500.0)
                or (tonumber(cfg.clientFootDistance) or 160.0)
            sample('movement_teleport_suspect', not exempt and moved > teleportLimit, 2, {
                distance = moved, inVehicle = inVehicle,
                vehicleNetId = vehicle ~= 0 and VehToNet(vehicle) or 0
            })
            sample('movement_noclip_suspect', not inVehicle and not exempt
                and moved > (tonumber(cfg.noclipDistance) or 12.0)
                and GetEntityHeightAboveGround(ped) > (tonumber(cfg.noclipHeight) or 5.0), 3, {
                    distance = moved, height = GetEntityHeightAboveGround(ped), inVehicle = false
                })
        end

        if lastVehicle ~= 0 and not inVehicle then
            lastVehicleExit = { coords = coords, at = nowMs(), vehicle = lastVehicle }
        elseif inVehicle and lastVehicleExit and nowMs() - lastVehicleExit.at <= (tonumber(cfg.vehicleReentryWindowMs) or 15000) then
            local reentryDistance = distance(coords, lastVehicleExit.coords)
            if reentryDistance > (tonumber(cfg.vehicleReentryDistance) or 80.0) then
                report('movement_vehicle_reentry_distance', {
                    distance = reentryDistance, inVehicle = true,
                    vehicleNetId = vehicle ~= 0 and VehToNet(vehicle) or 0
                })
            end
            lastVehicleExit = nil
        elseif lastVehicleExit and nowMs() - lastVehicleExit.at > (tonumber(cfg.vehicleReentryWindowMs) or 15000) then
            lastVehicleExit = nil
        end

        lastVehicle = vehicle
        lastCoords = coords
        ::continue::
    end
end)
