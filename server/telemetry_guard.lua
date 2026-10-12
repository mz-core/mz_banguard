MZBan = MZBan or {}
MZBan.TelemetryGuard = MZBan.TelemetryGuard or {}

local REPORT_EVENT = 'mz_banguard:server:securityTelemetry'
local reportStates = {}
local movementStates = {}
local spawnGraceUntil = {}

local CLIENT_CODES = {
    movement_teleport_suspect = { section = 'movement', confidence = 'medium' },
    movement_noclip_suspect = { section = 'movement', confidence = 'medium' },
    movement_vehicle_reentry_distance = { section = 'movement', confidence = 'low' },
    camera_freecam_suspect = { section = 'player', confidence = 'low' },
    camera_spectate_unapproved = { section = 'player', confidence = 'medium' },
    player_model_change_unapproved = { section = 'player', confidence = 'medium' },
    player_godmode_suspect = { section = 'player', confidence = 'medium' },
    player_invisible_suspect = { section = 'player', confidence = 'low' }
}

local function alertsConfig()
    return type(Config.SecurityAlerts) == 'table' and Config.SecurityAlerts or {}
end

local function movementConfig()
    return type(Config.MovementGuard) == 'table' and Config.MovementGuard or {}
end

local function playerConfig()
    return type(Config.PlayerStateGuard) == 'table' and Config.PlayerStateGuard or {}
end

local function nowMs()
    return math.max(0, math.floor(tonumber(GetGameTimer()) or 0))
end

local function online(sourceId)
    sourceId = tonumber(sourceId)
    return sourceId and sourceId > 0 and GetPlayerPing(math.floor(sourceId)) > 0
end

local function sectionEnabled(name)
    if name == 'movement' then return movementConfig().enabled == true end
    return playerConfig().enabled == true
end

local function hasActiveCharacter(sourceId)
    local resource = tostring(Config.Integration and Config.Integration.CoreResource or 'mz_core')
    if GetResourceState(resource) ~= 'started' then return false end
    local ok, identity = pcall(function()
        local coreExports = exports[resource]
        return coreExports.ResolvePlayerIdentity(coreExports, sourceId)
    end)
    return ok and type(identity) == 'table' and identity.ok == true
        and identity.active == true and identity.characterId ~= nil
end

local function finiteNumber(value, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    if minimum and value < minimum then return nil end
    if maximum and value > maximum then return nil end
    return value
end

local function isTrusted(sourceId, action, context, consume)
    if not MZBan.Flags then return false end
    if consume == true and type(MZBan.Flags.ConsumeTrusted) == 'function' then
        return MZBan.Flags.ConsumeTrusted(sourceId, action, context or {}) == true
    end
    return type(MZBan.Flags.IsTrusted) == 'function' and MZBan.Flags.IsTrusted(sourceId, action) == true
end

local function adminState(sourceId, exportName)
    if GetResourceState('mz_admin') ~= 'started' then return false end
    local ok, active = pcall(function()
        local adminExports = exports['mz_admin']
        return adminExports[exportName](adminExports, sourceId)
    end)
    return ok and active == true
end

local function leaseContext(sourceId, extra)
    local context = type(extra) == 'table' and extra or {}
    local ped = GetPlayerPed(sourceId)
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        local coords = GetEntityCoords(ped)
        if coords then context.x, context.y, context.z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z) end
        context.model = tonumber(GetEntityModel(ped))
    end
    context.bucket = tonumber(GetPlayerRoutingBucket(sourceId)) or 0
    return context
end

local function lifecycleTransition(code)
    if code == 'movement_teleport_suspect' or code == 'movement_vehicle_reentry_distance'
        or code == 'movement_noclip_suspect' then return 'movement' end
    if code == 'player_model_change_unapproved' then return 'model' end
    if code == 'player_godmode_suspect' then return 'invincibility' end
    if code == 'player_invisible_suspect' then return 'invisibility' end
    if code == 'camera_freecam_suspect' or code == 'camera_spectate_unapproved' then return 'camera' end
    return nil
end

local function lifecycleAllows(sourceId, code, context)
    local transition = lifecycleTransition(code)
    if not transition or not MZBan.SecurityLifecycle
        or type(MZBan.SecurityLifecycle.IsAllowed) ~= 'function' then return false end
    local allowed, session = MZBan.SecurityLifecycle.IsAllowed(
        sourceId, transition, leaseContext(sourceId, context)
    )
    if allowed and MZBan.Correlation then
        MZBan.Correlation.Record(sourceId, 'lifecycle.authorized_transition', {
            lifecycle = session and session.kind, sessionId = session and session.id,
            resource = session and session.issuer, transition = transition
        })
    end
    return allowed == true
end

local function isExempt(sourceId, code, context)
    if lifecycleAllows(sourceId, code, context) then return true end
    if code == 'camera_spectate_unapproved' then
        return adminState(sourceId, 'IsSpectating')
    end
    if code == 'movement_noclip_suspect' or code == 'player_godmode_suspect'
        or code == 'player_invisible_suspect' or code == 'camera_freecam_suspect' then
        if code == 'player_godmode_suspect' and adminState(sourceId, 'IsGodModeEnabled') then return true end
        return adminState(sourceId, 'IsNoClipEnabled') or adminState(sourceId, 'IsSpectating')
    end
    if code == 'movement_teleport_suspect' or code == 'movement_vehicle_reentry_distance' then
        return adminState(sourceId, 'IsNoClipEnabled')
            or isTrusted(sourceId, 'movement.noclip.staff', leaseContext(sourceId, context), true)
            or isTrusted(sourceId, 'movement.teleport', leaseContext(sourceId, context), true)
            or adminState(sourceId, 'IsSpectating')
    end
    if code == 'player_model_change_unapproved' then
        return isTrusted(sourceId, 'player.model.change', leaseContext(sourceId, context), true)
    end
    return false
end

local function normalizeEvidence(code, payload)
    payload = type(payload) == 'table' and payload or {}
    local evidence = { origin = 'client_telemetry' }
    if code == 'movement_teleport_suspect' or code == 'movement_noclip_suspect'
        or code == 'movement_vehicle_reentry_distance' then
        evidence.distance = finiteNumber(payload.distance, 0, 100000)
        evidence.height = finiteNumber(payload.height, -1000, 10000)
        evidence.inVehicle = payload.inVehicle == true
        evidence.vehicleNetId = finiteNumber(payload.vehicleNetId, 0, 2147483647)
    elseif code == 'camera_freecam_suspect' then
        evidence.cameraDistance = finiteNumber(payload.cameraDistance, 0, 100000)
    elseif code == 'camera_spectate_unapproved' then
        evidence.spectator = payload.spectator == true
    elseif code == 'player_model_change_unapproved' then
        evidence.model = finiteNumber(payload.model, -2147483648, 4294967295)
    elseif code == 'player_godmode_suspect' then
        evidence.invincible = payload.invincible == true
        evidence.damageDisabled = payload.damageDisabled == true
        evidence.fullProofs = payload.fullProofs == true
        evidence.health = finiteNumber(payload.health, 0, 10000)
        evidence.armour = finiteNumber(payload.armour, 0, 10000)
    elseif code == 'player_invisible_suspect' then
        evidence.alpha = finiteNumber(payload.alpha, 0, 255)
    end
    return evidence
end

local function acceptReport(sourceId, code, payload)
    sourceId = tonumber(sourceId)
    code = type(code) == 'string' and code or ''
    local definition = CLIENT_CODES[code]
    if MZBan.EventContracts and type(MZBan.EventContracts.Validate) == 'function' then
        local valid = MZBan.EventContracts.Validate('security.telemetry', sourceId, { code = code, payload = payload })
        if valid ~= true then return false end
    end
    if not online(sourceId) or not definition or not sectionEnabled(definition.section) then
        if MZBan.DetectorHealth then MZBan.DetectorHealth.Discard('telemetry_guard', 'unknown_or_disabled_code') end
        return false
    end
    sourceId = math.floor(sourceId)
    if not hasActiveCharacter(sourceId) then
        if MZBan.DetectorHealth then MZBan.DetectorHealth.Discard('telemetry_guard', 'character_not_active') end
        return false
    end
    local evidence = normalizeEvidence(code, payload)
    if isExempt(sourceId, code, evidence) then
        if MZBan.DetectorHealth then MZBan.DetectorHealth.Discard('telemetry_guard', 'authorized_action') end
        return false
    end

    local currentMs = nowMs()
    local current = reportStates[sourceId]
    local window = math.max(1000, math.floor(tonumber(alertsConfig().clientReportWindowMs) or 10000))
    if not current or currentMs - current.startedAt >= window then
        current = { startedAt = currentMs, count = 0, reasons = {} }
        reportStates[sourceId] = current
    end
    current.count = current.count + 1
    if current.count > math.max(1, math.floor(tonumber(alertsConfig().clientReportLimit) or 8)) then return false end

    local reasonCooldown = math.max(1000, math.floor(tonumber(alertsConfig().clientReasonCooldownMs) or 8000))
    if currentMs - (current.reasons[code] or 0) < reasonCooldown then return false end
    current.reasons[code] = currentMs

    local subject = code == 'player_model_change_unapproved' and tostring(evidence.model or 'unknown') or code
    local correlationId = MZBan.Correlation and MZBan.Correlation.Record(sourceId, 'client_telemetry.' .. code, evidence) or nil
    evidence.correlationId = correlationId
    local incident = MZBan.Incidents.Record({
        source = sourceId,
        playerName = GetPlayerName(sourceId),
        code = code,
        origin = 'client_telemetry',
        confidence = definition.confidence,
        subject = subject,
        reason = 'repeated_client_signal',
        evidence = evidence
    })
    if incident then MZBan.Incidents.NotifyStaff(incident) end
    if MZBan.DetectorHealth then MZBan.DetectorHealth.Seen('telemetry_guard') end
    return incident ~= nil
end

RegisterNetEvent(REPORT_EVENT, function(code, payload)
    acceptReport(source, code, payload)
end)

local function coordsOfPlayer(sourceId)
    local ped = GetPlayerPed(sourceId)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local coords = GetEntityCoords(ped)
    if not coords then return nil end
    return { x = tonumber(coords.x) or 0.0, y = tonumber(coords.y) or 0.0, z = tonumber(coords.z) or 0.0 }, ped
end

local function distance(left, right)
    local x, y, z = left.x - right.x, left.y - right.y, left.z - right.z
    return math.sqrt(x * x + y * y + z * z)
end

local function sampleMovement(sourceId, currentMs)
    if not online(sourceId) then return end
    sourceId = math.floor(tonumber(sourceId))
    if not hasActiveCharacter(sourceId) then
        movementStates[sourceId], spawnGraceUntil[sourceId] = nil, nil
        return
    end
    local coords, ped = coordsOfPlayer(sourceId)
    if not coords then return end
    local bucket = tonumber(GetPlayerRoutingBucket(sourceId)) or 0
    local okVehicle, vehicle = pcall(GetVehiclePedIsIn, ped, false)
    vehicle = okVehicle and tonumber(vehicle) or 0
    local inVehicle = vehicle and vehicle ~= 0
    local state = movementStates[sourceId]
    if not state or state.bucket ~= bucket then
        movementStates[sourceId] = { coords = coords, at = currentMs, bucket = bucket, inVehicle = inVehicle }
        spawnGraceUntil[sourceId] = math.max(spawnGraceUntil[sourceId] or 0,
            currentMs + math.floor(tonumber(movementConfig().serverFallbackGraceMs) or 3000))
        return
    end

    local moved = distance(coords, state.coords)
    local limit = inVehicle and (tonumber(movementConfig().serverVehicleDistance) or 650.0)
        or (tonumber(movementConfig().serverFootDistance) or 220.0)
    if currentMs >= (spawnGraceUntil[sourceId] or 0) and moved > limit
        and not isExempt(sourceId, 'movement_teleport_suspect', {
            x = coords.x, y = coords.y, z = coords.z, bucket = bucket, inVehicle = inVehicle
        }) then
        local correlationId = MZBan.Correlation and MZBan.Correlation.Record(sourceId, 'server_state.teleport', {
            distance = moved, bucket = bucket, inVehicle = inVehicle, x = coords.x, y = coords.y, z = coords.z
        }) or nil
        local incident = MZBan.Incidents.Record({
            source = sourceId,
            playerName = GetPlayerName(sourceId),
            code = 'movement_teleport_suspect',
            origin = 'server_state',
            confidence = 'medium',
            subject = inVehicle and 'vehicle' or 'foot',
            reason = 'server_position_delta_above_limit',
            evidence = {
                origin = 'server_state', distance = moved, inVehicle = inVehicle,
                windowMs = currentMs - state.at, bucket = bucket,
                x = coords.x, y = coords.y, z = coords.z, correlationId = correlationId
            }
        })
        if incident then MZBan.Incidents.NotifyStaff(incident) end
        if MZBan.DetectorHealth then MZBan.DetectorHealth.Seen('movement_guard') end
    end
    state.coords, state.at, state.inVehicle = coords, currentMs, inVehicle
end

AddEventHandler('respawnPlayerPedEvent', function(player)
    local sourceId = tonumber(player)
    if sourceId then
        movementStates[sourceId] = nil
        spawnGraceUntil[sourceId] = nowMs() + math.floor(tonumber(movementConfig().serverFallbackGraceMs) or 3000)
    end
end)

AddEventHandler('playerDropped', function()
    local sourceId = tonumber(source)
    if not sourceId then return end
    reportStates[sourceId], movementStates[sourceId], spawnGraceUntil[sourceId] = nil, nil, nil
end)

CreateThread(function()
    while true do
        Wait(math.max(500, math.floor(tonumber(movementConfig().sampleIntervalMs) or 1000)))
        if movementConfig().enabled == true then
            local currentMs = nowMs()
            for _, playerId in ipairs(GetPlayers()) do sampleMovement(tonumber(playerId), currentMs) end
        end
    end
end)

MZBan.TelemetryGuard.AcceptReport = acceptReport
MZBan.TelemetryGuard.SampleMovement = sampleMovement
