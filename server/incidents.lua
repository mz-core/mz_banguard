MZBan = MZBan or {}
MZBan.Incidents = MZBan.Incidents or {}

local incidentsById = {}
local incidentOrder = {}
local aggregateByKey = {}
local pendingPersistence = {}
local pendingSignals = {}
local pendingSignalCount = 0
local rawSignalStates = {}
local executionLedger = {}
local persistenceRate = { startedAt = 0, writes = 0 }
local sequence = 0

local CODE_CATEGORIES = {
    weapon_damage_no_equipped_weapon = 'weapon',
    weapon_damage_hash_mismatch = 'weapon',
    weapon_damage_unknown_hash = 'weapon',
    weapon_damage_session_not_ready = 'weapon',
    weapon_damage_transition_window = 'weapon',
    weapon_damage_payload_invalid = 'weapon',
    weapon_damage_rate_suspect = 'weapon',
    weapon_damage_death_state_incompatible = 'weapon',
    entity_spawn_rate_suspect = 'entity',
    entity_model_blocked = 'entity',
    movement_teleport_suspect = 'movement',
    movement_noclip_suspect = 'movement',
    movement_vehicle_reentry_distance = 'movement',
    camera_freecam_suspect = 'camera',
    camera_spectate_unapproved = 'camera',
    player_model_change_unapproved = 'player_state',
    player_godmode_suspect = 'player_state',
    player_invisible_suspect = 'player_state',
    event_explosion_rate_suspect = 'event',
    event_explosion_anomaly_suspect = 'event',
    event_clear_tasks_rate_suspect = 'event',
    event_remote_clear_tasks_suspect = 'event',
    event_tazer_rate_suspect = 'event',
    event_ptfx_rate_suspect = 'event',
    event_ptfx_anomaly_suspect = 'event',
    event_projectile_rate_suspect = 'event',
    projectile_weapon_unauthorized = 'event',
    event_fire_rate_suspect = 'event',
    event_fire_remote_suspect = 'event',
    event_remote_weapon_action_suspect = 'event',
    event_damage_modifier_suspect = 'event',
    aim_headshot_pattern_suspect = 'aim',
    crash_observed = 'crash',
    crash_cluster_suspect = 'crash',
    client_resource_presence_missing = 'runtime',
    client_resource_stop_observed = 'runtime',
    canary_triggered = 'canary'
}

local VALID_CONFIDENCE = { low = true, medium = true, high = true, critical = true }
local VALID_CULPABILITY = { none = true, contextual = true, suspected = true, supported = true }

local VALID_STATUSES = {
    open = true,
    acknowledged = true,
    resolved = true,
    false_positive = true
}

local ACTION_PERMISSIONS = {
    spectate = 'spectate',
    ['goto'] = 'gotoPlayer',
    kick = 'kick',
    ban = 'ban'
}

local function guardConfig()
    if type(Config.SecurityAlerts) == 'table' then return Config.SecurityAlerts end
    return type(Config.WeaponGuard) == 'table' and Config.WeaponGuard or {}
end

local function normalizeSource(value)
    value = tonumber(value)
    if not value or value <= 0 then return nil end
    return math.floor(value)
end

local function safeString(value, maxLength)
    value = tostring(value or ''):gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #value > (tonumber(maxLength) or 128) then
        value = value:sub(1, tonumber(maxLength) or 128)
    end
    return value
end

local function safeInteger(value, minValue, maxValue)
    value = tonumber(value)
    if not value then return nil end
    value = math.floor(value)
    if minValue and value < minValue then value = minValue end
    if maxValue and value > maxValue then value = maxValue end
    return value
end

local function normalizeHash(value)
    value = tonumber(value)
    if not value then return nil end
    value = math.floor(value)
    if value < 0 then value = value + 4294967296 end
    if value < 0 or value > 4294967295 then return nil end
    return value
end

local function nowMs()
    return math.max(0, math.floor(tonumber(GetGameTimer()) or 0))
end

local function permissions()
    return type(guardConfig().permissions) == 'table' and guardConfig().permissions or {}
end

local function coreResource()
    return tostring(Config.Integration and Config.Integration.CoreResource or 'mz_core')
end

local function hasPermission(source, permissionKey)
    source = normalizeSource(source)
    local permission = permissions()[permissionKey]
    if not source or type(permission) ~= 'string' or permission == '' then return false end
    local resource = coreResource()
    if GetResourceState(resource) ~= 'started' then return false end

    local ok, allowed = pcall(function()
        return exports[resource]:HasGlobalPermission(source, permission)
    end)
    return ok and allowed == true
end

local function resolveCoreIdentity(source)
    source = normalizeSource(source)
    local resource = coreResource()
    if not source or GetResourceState(resource) ~= 'started' then return nil end

    local ok, identity = pcall(function()
        return exports[resource]:ResolvePlayerIdentity(source)
    end)
    if not ok or type(identity) ~= 'table' or identity.ok ~= true then return nil end
    local name = safeString(identity.name, 64)
    if name == '' then
        name = safeString(('%s %s'):format(tostring(identity.firstname or ''), tostring(identity.lastname or '')), 64)
    end
    if name == '' then name = safeString(GetPlayerName(source), 64) end
    return {
        citizenid = safeString(identity.citizenid, 64),
        accountId = safeInteger(identity.accountId, 1),
        sessionId = safeInteger(identity.sessionId, 1),
        characterId = safeInteger(identity.characterId, 1),
        active = identity.active == true,
        name = name
    }
end

local function actorPayload(source)
    local identity = resolveCoreIdentity(source) or {}
    return {
        type = 'player',
        id = identity.citizenid ~= '' and identity.citizenid or ('source:%s'):format(tostring(source)),
        source = normalizeSource(source),
        citizenid = identity.citizenid ~= '' and identity.citizenid or nil,
        accountId = identity.accountId,
        sessionId = identity.sessionId,
        name = identity.name ~= '' and identity.name or safeString(GetPlayerName(source), 64)
    }
end

local function audit(action, actorSource, incident, meta)
    meta = type(meta) == 'table' and meta or {}
    local payload = {
        actor = actorSource and actorPayload(actorSource) or { type = 'system', id = 'mz_banguard' },
        target = {
            type = 'security_incident',
            id = incident and incident.id or safeString(meta.incidentId, 64),
            source = incident and incident.source or nil,
            citizenid = incident and incident.citizenid or nil,
            name = incident and incident.playerName or nil
        },
        context = {
            resource = GetCurrentResourceName(),
            category = incident and incident.category or 'weapon',
            code = incident and incident.code or nil,
            status = incident and incident.status or nil
        },
        meta = meta
    }

    local resource = coreResource()
    local persisted = false
    if meta.persist ~= false and GetResourceState(resource) == 'started' then
        local ok, auditId = pcall(function()
            return exports[resource]:CreateDetailedLog('security', action, payload)
        end)
        persisted = ok and auditId ~= nil and auditId ~= false
    end

    MZBan.AuditPrint(action, MZBan.JsonEncode({
        incident_id = incident and incident.id or meta.incidentId,
        actor_source = actorSource,
        target_source = incident and incident.source or nil,
        code = incident and incident.code or nil,
        status = incident and incident.status or nil,
        persisted = persisted,
        result = meta.result,
        reason = meta.reason,
        evidence = meta.evidence
    }))
    return persisted
end

local function buildIdentifierContext(source)
    local identifiers = MZBan.GetIdentifiers(source, { includeIp = false })
    local byType = type(identifiers) == 'table' and identifiers.byType or {}
    return {
        license = safeString(byType and byType.license, 160),
        fivem = safeString(byType and byType.fivem, 160)
    }
end

local function identityKey(input)
    local identifiers = type(input.identifiers) == 'table' and input.identifiers or {}
    if safeString(input.aggregateIdentity, 96) ~= '' then return safeString(input.aggregateIdentity, 96) end
    if safeInteger(input.sessionId, 1) then return 'session:' .. tostring(safeInteger(input.sessionId, 1)) end
    if safeString(input.citizenid, 64) ~= '' then return 'citizen:' .. safeString(input.citizenid, 64) end
    if safeInteger(input.accountId, 1) then return 'account:' .. tostring(safeInteger(input.accountId, 1)) end
    if safeString(identifiers.license, 160) ~= '' then return 'license:' .. safeString(identifiers.license, 160) end
    if safeString(identifiers.fivem, 160) ~= '' then return 'fivem:' .. safeString(identifiers.fivem, 160) end
    return 'source:' .. tostring(normalizeSource(input.source) or 0)
end

local function aggregationKey(input)
    return table.concat({
        identityKey(input),
        safeString(input.code, 64),
        safeString(input.subject, 96),
        tostring(normalizeHash(input.reportedWeaponHash) or 0),
        tostring(normalizeHash(input.authorizedWeaponHash) or 0)
    }, ':')
end

local function calculateRisk(code, count)
    local score
    local configs = {
        guardConfig(), Config.WeaponGuard, Config.EntityGuard, Config.MovementGuard,
        Config.PlayerStateGuard, Config.EventGuard, Config.AimGuard
    }
    for _, section in ipairs(configs) do
        local points = type(section) == 'table' and section.riskPoints or nil
        if type(points) == 'table' and points[code] ~= nil then
            score = safeInteger(points[code], 0, 100)
            break
        end
    end
    score = math.max(0, score or 0)
    count = math.max(1, safeInteger(count, 1, 1000000) or 1)
    if count > 1 then score = score + 10 end
    if count > 5 then score = score + 20 end
    return math.min(100, score)
end

local function severityFor(code, count, riskScore)
    if code == 'weapon_damage_session_not_ready' then return 'info' end
    if code == 'weapon_damage_transition_window' then return 'low' end
    if code == 'weapon_damage_payload_invalid' or code == 'weapon_damage_rate_suspect' then return 'medium' end
    if code == 'weapon_damage_no_equipped_weapon' and count >= 3 then return 'critical' end
    if riskScore >= 75 then return 'critical' end
    if riskScore >= 35 then return 'high' end
    if riskScore >= 20 then return 'medium' end
    if riskScore > 0 then return 'low' end
    return 'info'
end

local function culpabilityFor(code, requested)
    if VALID_CULPABILITY[requested] then return requested end
    if code == 'crash_observed' or code == 'weapon_damage_session_not_ready'
        or code == 'weapon_damage_transition_window' or code == 'client_resource_presence_missing'
        or code == 'client_resource_stop_observed' then return 'none' end
    if code == 'crash_cluster_suspect' then return 'contextual' end
    if code == 'weapon_damage_no_equipped_weapon' or code == 'weapon_damage_hash_mismatch'
        or code == 'weapon_damage_death_state_incompatible' or code == 'entity_model_blocked' then
        return 'supported'
    end
    return 'suspected'
end

local EVIDENCE_FIELDS = {
    origin = true, entityType = true, model = true, amount = true, windowMs = true,
    distance = true, height = true, cameraDistance = true, alpha = true, health = true,
    armour = true, invincible = true, damageDisabled = true, fullProofs = true,
    inVehicle = true, spectator = true, vehicleNetId = true, hitComponent = true,
    weaponHash = true, hits = true, headshots = true, ratio = true, eventType = true,
    bucket = true, targetNetId = true, x = true, y = true, z = true,
    burstAmount = true, burstWindowMs = true, owner = true, firstOwner = true,
    target = true, targetOwner = true, ownerNetId = true, correlationId = true,
    phase = true, leaseId = true, resource = true, capability = true,
    remainingUses = true, damageScale = true, isInvisible = true, isAudible = true,
    distanceFromSender = true, immediately = true, effectHash = true, scale = true,
    projectileHash = true, weaponModifier = true, meleeModifier = true,
    defenseModifier = true, action = true, ruleVersion = true,
    distanceBand = true, pingBand = true, ping = true, averageDistance = true,
    qualifiedWindows = true, populationName = true, populationClass = true,
    mappingVersion = true, mappingValidated = true, lifecycle = true,
    sessionId = true, transition = true, targetType = true, targetDistance = true,
    ammoRevision = true, transitionRevision = true, rateProfile = true,
    rateCount = true, rateThreshold = true, rateWindowMs = true,
    dropReason = true, dropClassification = true, playerName = true,
    sourceAtDrop = true, victimCount = true, commonSignalCount = true,
    candidateCount = true, lastKnownX = true, lastKnownY = true, lastKnownZ = true,
    deathState = true, stateRevision = true, resourceName = true, presenceStatus = true
}

local SENSITIVE_KEYS = {
    password = true, api_key = true, apikey = true, authorization = true, bearer = true,
    cookie = true, cookies = true, token = true, tokens = true, token_value = true,
    webhook = true, webhook_url = true, database_url = true, connection_string = true,
    ip = true, endpoint = true
}

local function isSensitiveKey(key)
    if SENSITIVE_KEYS[key] == true then return true end
    for _, fragment in ipairs({ 'password', 'secret', 'api_key', 'apikey', 'bearer', 'cookie', 'webhook', 'token' }) do
        if key:find(fragment, 1, true) then return true end
    end
    return key == 'ip_address' or key == 'player_ip' or key == 'remote_ip'
end

local function sanitizeStructured(value, depth, state)
    local valueType = type(value)
    if valueType == 'string' then return safeString(value, 256) end
    if valueType == 'boolean' then return value end
    if valueType == 'number' and value == value and value ~= math.huge and value ~= -math.huge then
        return math.max(-4294967295, math.min(4294967295, value))
    end
    if valueType ~= 'table' or depth >= 5 or state.count >= 128 then return nil end
    local out = {}
    for key, item in pairs(value) do
        if state.count >= 128 then break end
        local safeKey = safeString(key, 64)
        local lowered = safeKey:lower():gsub('[^a-z0-9_]', '_')
        if safeKey ~= '' and not isSensitiveKey(lowered) then
            local safeValue = sanitizeStructured(item, depth + 1, state)
            if safeValue ~= nil then
                out[type(key) == 'number' and key or safeKey] = safeValue
                state.count = state.count + 1
            end
        end
    end
    return out
end

local function sanitizeEvidenceData(input)
    local source = type(input.evidence) == 'table' and input.evidence or {}
    local out = {}
    for key, value in pairs(source) do
        if EVIDENCE_FIELDS[key] == true then
            if type(value) == 'string' then
                out[key] = safeString(value, 128)
            elseif type(value) == 'boolean' then
                out[key] = value
            elseif type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge then
                out[key] = math.max(-4294967295, math.min(4294967295, value))
            end
        end
    end
    return out
end

local function newIncidentId()
    sequence = sequence + 1
    return ('MZSEC-%d-%06d'):format(os.time(), sequence % 1000000)
end

local function removeIncident(id)
    local incident = incidentsById[id]
    if not incident then return end
    incidentsById[id] = nil
    if incident.category ~= 'crash' and incident.lab ~= true
        and incident.severity ~= 'high' and incident.severity ~= 'critical' then
        pendingPersistence[id] = nil
    end
    if aggregateByKey[incident.aggregateKey] == id then aggregateByKey[incident.aggregateKey] = nil end
    rawSignalStates[incident.aggregateKey] = nil
    executionLedger[id] = nil
    for index, orderedId in ipairs(incidentOrder) do
        if orderedId == id then
            table.remove(incidentOrder, index)
            break
        end
    end
end

function MZBan.Incidents.Cleanup(currentMs)
    currentMs = safeInteger(currentMs, 0) or nowMs()
    local ttl = math.max(60000, safeInteger(guardConfig().incidentTtlMs, 60000) or 3600000)
    local expired = {}
    for _, id in ipairs(incidentOrder) do
        local incident = incidentsById[id]
        if not incident or currentMs - (tonumber(incident.lastSeenMs) or currentMs) > ttl then
            expired[#expired + 1] = id
        end
    end
    for _, id in ipairs(expired) do removeIncident(id) end
    return #expired
end

local function enforceLimit()
    MZBan.Incidents.Cleanup()
    local maximum = math.max(10, safeInteger(guardConfig().maxIncidents, 10, 10000) or 1000)
    while #incidentOrder >= maximum do removeIncident(incidentOrder[1]) end
end

local function evidenceFrom(input, currentTime)
    local detector = MZBan.DetectorCatalog and MZBan.DetectorCatalog.Get(input.code, nil, input.confidence) or {}
    local evidence = {
        at = currentTime,
        origin = safeString(input.origin or 'server_event', 32),
        confidence = VALID_CONFIDENCE[input.confidence] and input.confidence or 'high',
        subject = safeString(input.subject, 96),
        reportedWeaponHash = normalizeHash(input.reportedWeaponHash),
        authorizedWeaponHash = normalizeHash(input.authorizedWeaponHash),
        targetNetId = safeInteger(input.targetNetId, 0, 2147483647),
        damage = tonumber(input.damage) and math.max(0, math.min(10000, tonumber(input.damage))) or nil,
        willKill = input.willKill == true,
        overrideDefaultDamage = input.overrideDefaultDamage == true,
        reason = safeString(input.reason, 96),
        detector = {
            code = safeString(input.code, 64),
            version = safeInteger(input.detectorVersion, 1, 1000) or 1,
            threshold = sanitizeStructured(input.threshold or {}, 0, { count = 0 }) or {},
            window_ms = safeInteger(input.windowMs or (input.evidence and input.evidence.windowMs), 0, 86400000),
            label = detector.label
        },
        subject_context = {
            citizenid = safeString(input.citizenid, 64),
            account_id = safeInteger(input.accountId, 1),
            session_id = safeInteger(input.sessionId, 1),
            source = normalizeSource(input.source)
        },
        observation = {
            first_seen_at = currentTime,
            last_seen_at = currentTime,
            count = 1,
            peak_rate = tonumber(input.peakRate)
        },
        context = sanitizeStructured(input.context or input.evidence or {}, 0, { count = 0 }) or {},
        samples = sanitizeStructured(input.samples or {}, 0, { count = 0 }) or {},
        mitigation = sanitizeStructured(input.mitigation or {
            attempted = false, applied = false, result = 'observe_only'
        }, 0, { count = 0 }) or {}
    }
    for key, value in pairs(sanitizeEvidenceData(input)) do evidence[key] = value end
    evidence.canonical = {
        detector = evidence.detector,
        subject = evidence.subject_context,
        observation = evidence.observation,
        context = evidence.context,
        samples = evidence.samples,
        mitigation = evidence.mitigation
    }
    return evidence
end

local function persistenceConfig()
    return type(Config.IncidentPersistence) == 'table' and Config.IncidentPersistence or {}
end

local function incidentSummary(incident)
    return {
        subject = incident.subject,
        origin = incident.origin,
        reportedWeaponHash = incident.reportedWeaponHash,
        reportedWeaponName = incident.reportedWeaponName,
        authorizedWeaponHash = incident.authorizedWeaponHash,
        authorizedWeaponName = incident.authorizedWeaponName,
        authorizedAmmo = incident.authorizedAmmo,
        targetNetId = incident.targetNetId,
        damage = incident.damage,
        acknowledgedBy = incident.acknowledgedBy,
        acknowledgedAt = incident.acknowledgedAt,
        culpability = incident.culpability,
        droppedSampleCount = incident.droppedSampleCount or 0,
        rawSignalDroppedCount = incident.rawSignalDroppedCount or 0,
        rawSignalPersistenceFailed = incident.rawSignalPersistenceFailed or 0,
        rawSignalBackpressureCount = incident.rawSignalBackpressureCount or 0,
        persistenceBackpressureCount = incident.persistenceBackpressureCount or 0,
        notes = sanitizeStructured(incident.notes or {}, 0, { count = 0 }) or {},
        linkedIncidentIds = incident.linkedIncidentIds or {},
        labInfo = incident.labInfo,
        pinned = incident.pinned == true,
        aggregateKey = incident.aggregateKey
    }
end

local function persistencePayload(incident)
    return {
        incident_id = incident.id,
        code = incident.code,
        category = incident.category,
        status = incident.status,
        severity = incident.severity,
        confidence = incident.confidence,
        culpability = incident.culpability,
        risk_score = incident.riskScore,
        player_name = incident.playerName,
        citizenid = incident.citizenid ~= '' and incident.citizenid or nil,
        account_id = incident.accountId,
        session_id = incident.sessionId,
        first_seen_at = incident.firstSeenAt,
        last_seen_at = incident.lastSeenAt,
        count = incident.count,
        suppressed_count = incident.suppressedCount,
        source_at_first_seen = incident.sourceAtFirstSeen,
        source_at_last_seen = incident.sourceAtLastSeen,
        summary = incidentSummary(incident),
        evidence = sanitizeStructured(incident.evidence or {}, 0, { count = 0 }) or {},
        timeline_snapshot = sanitizeStructured(incident.timelineSnapshot or {}, 0, { count = 0 }) or {},
        mitigation = sanitizeStructured(incident.mitigation or {}, 0, { count = 0 }) or {},
        lab = incident.lab == true,
        created_at = incident.createdAt,
        updated_at = incident.updatedAt,
        resolved_at = incident.resolvedAt,
        resolved_by = incident.resolvedBy,
        false_positive_at = incident.falsePositiveAt,
        false_positive_by = incident.falsePositiveBy
    }
end

local function captureTimeline(incident, requestedLimit)
    if not incident.source or not MZBan.Correlation or type(MZBan.Correlation.Snapshot) ~= 'function' then
        return incident.timelineSnapshot or {}
    end
    local correlation = type(Config.SecurityCorrelation) == 'table' and Config.SecurityCorrelation or {}
    local limit = requestedLimit or (incident.lab and correlation.labSnapshotEntries or correlation.snapshotEntries) or 16
    incident.timelineSnapshot = MZBan.Correlation.Snapshot(incident.source, limit)
    return incident.timelineSnapshot
end

local function shouldSnapshot(incident)
    return incident.lab == true or incident.category == 'crash'
        or incident.severity == 'high' or incident.severity == 'critical'
        or incident.pinned == true
end

local function scheduleIncidentRetry(incident, reason, failedAttempt)
    local pending = pendingPersistence[incident.id]
    if not pending then
        local count = 0
        for _ in pairs(pendingPersistence) do count = count + 1 end
        local maximum = math.max(1, safeInteger(persistenceConfig().maxPendingIncidents, 1) or 500)
        if count >= maximum then
            incident.persistenceBackpressureCount = (incident.persistenceBackpressureCount or 0) + 1
            return false
        end
        pending = { attempts = 0, nextAttemptMs = nowMs() }
    end
    pending.incident = incident
    pending.reason = reason
    if failedAttempt == true then
        pending.attempts = (pending.attempts or 0) + 1
        local baseDelay = math.max(100, safeInteger(persistenceConfig().retryBaseMs, 100) or 1000)
        pending.nextAttemptMs = nowMs() + math.min(30000, baseDelay * (2 ^ math.min(5, pending.attempts)))
    end
    pendingPersistence[incident.id] = pending
    return true
end

local function persistNow(incident, reason)
    if persistenceConfig().enabled == false or not MZBan.DB or type(MZBan.DB.SaveIncident) ~= 'function' then return false end
    local currentMs = nowMs()
    if currentMs - persistenceRate.startedAt >= 60000 then
        persistenceRate.startedAt, persistenceRate.writes = currentMs, 0
    end
    local maximum = math.max(1, safeInteger(persistenceConfig().maxWritesPerMinute, 1) or 120)
    if persistenceRate.writes >= maximum then
        incident.persistenceConfirmed = false
        incident.persistenceError = 'persistence_rate_limited'
        scheduleIncidentRetry(incident, reason or 'rate_limited', true)
        return false
    end
    if shouldSnapshot(incident) then captureTimeline(incident) end
    local ok, result = pcall(MZBan.DB.SaveIncident, persistencePayload(incident))
    if ok and result ~= nil and result ~= false then
        persistenceRate.writes = persistenceRate.writes + 1
        incident.lastPersistMs = nowMs()
        incident.lastPersistReason = safeString(reason, 64)
        incident.persistenceConfirmed = true
        incident.persistenceError = nil
        pendingPersistence[incident.id] = nil
        return true
    end
    incident.persistenceConfirmed = false
    incident.persistenceError = ok and 'unconfirmed_result' or safeString(result, 128)
    MZBan.AuditPrint('security.incident.persistence_failed', incident.id, incident.persistenceError)
    scheduleIncidentRetry(incident, reason or 'retry_after_failure', true)
    return false
end

local function queuePersistence(incident, reason)
    if persistenceConfig().enabled == false then return end
    return scheduleIncidentRetry(incident, reason, false)
end

local function persistAction(incident, action, actor, note, meta)
    if not MZBan.DB or type(MZBan.DB.SaveIncidentAction) ~= 'function' then return false end
    local ok, result = pcall(MZBan.DB.SaveIncidentAction, {
        incident_id = incident.id,
        action = safeString(action, 80),
        actor_citizenid = actor and actor.citizenid or nil,
        actor_name = actor and actor.name or nil,
        note = note and safeString(note, 500) or nil,
        meta = sanitizeStructured(meta or {}, 0, { count = 0 }) or {},
        created_at = os.time()
    })
    return ok and result ~= nil and result ~= false
end

local function queueSignal(payload, incident)
    local id = payload.signal_id
    if pendingSignals[id] then return true end
    local maximum = math.max(1, safeInteger(persistenceConfig().maxPendingSignals, 1) or 256)
    if pendingSignalCount >= maximum then
        incident.rawSignalBackpressureCount = (incident.rawSignalBackpressureCount or 0) + 1
        return false
    end
    pendingSignals[id] = { payload = payload, incident = incident, attempts = 0, nextAttemptMs = nowMs() }
    pendingSignalCount = pendingSignalCount + 1
    return true
end

local function saveSignal(payload)
    local ok, result = pcall(MZBan.DB.SaveSecuritySignal, payload)
    return ok and result ~= nil and result ~= false
end

local function shouldPersistRawSignal(incident, currentMs)
    local window = math.max(1000, safeInteger(persistenceConfig().rawSignalWindowMs, 1000) or 10000)
    local burst = math.max(1, safeInteger(persistenceConfig().rawSignalBurst, 1) or 8)
    local representativeEvery = math.max(1,
        safeInteger(persistenceConfig().rawSignalRepresentativeEvery, 1) or 100)
    local key = incident.aggregateKey or incident.id
    local state = rawSignalStates[key]
    if not state or currentMs - state.startedAt >= window then
        state = { startedAt = currentMs, seen = 0, persisted = 0, dropped = 0 }
        rawSignalStates[key] = state
    end
    state.seen = state.seen + 1
    if state.seen <= burst or state.seen % representativeEvery == 0 then
        state.persisted = state.persisted + 1
        return true
    end
    state.dropped = state.dropped + 1
    incident.rawSignalDroppedCount = (incident.rawSignalDroppedCount or 0) + 1
    return false
end

local function persistRawSignal(incident, input, currentTime)
    if not MZBan.DB or type(MZBan.DB.SaveSecuritySignal) ~= 'function' then return false end
    if not shouldPersistRawSignal(incident, nowMs()) then return false, 'sampled' end
    if type(MZBan.DB.IsReady) == 'function' then
        local readyOk, ready = pcall(MZBan.DB.IsReady)
        if not readyOk or ready ~= true then
            incident.rawSignalPersistenceFailed = (incident.rawSignalPersistenceFailed or 0) + 1
        end
    end
    local sample = evidenceFrom(input, currentTime)
    local payload = {
        signal_id = ('MZSIG-%s-%d'):format(incident.id, incident.count),
        incident_id = incident.id,
        code = incident.code,
        origin = incident.origin,
        confidence = incident.confidence,
        culpability = incident.culpability,
        citizenid = incident.citizenid ~= '' and incident.citizenid or nil,
        account_id = incident.accountId,
        session_id = incident.sessionId,
        source_id = incident.sourceAtLastSeen,
        occurred_at = currentTime,
        evidence = sample
    }
    if saveSignal(payload) then return true end
    incident.rawSignalPersistenceFailed = (incident.rawSignalPersistenceFailed or 0) + 1
    queueSignal(payload, incident)
    return false, 'queued'
end

local function addLinkedIncident(incident, linkedId)
    if not incident or not linkedId or linkedId == incident.id then return false end
    incident.linkedIncidentIds = type(incident.linkedIncidentIds) == 'table' and incident.linkedIncidentIds or {}
    for _, current in ipairs(incident.linkedIncidentIds) do
        if current == linkedId then return false end
    end
    incident.linkedIncidentIds[#incident.linkedIncidentIds + 1] = linkedId
    return true
end

local function linkCrossSessionCrashes(incident)
    if incident.code ~= 'crash_observed' or (not incident.accountId and incident.citizenid == '') then return end
    local correlation = type(Config.SecurityCorrelation) == 'table' and Config.SecurityCorrelation or {}
    local window = math.max(60, safeInteger(correlation.crossSessionLinkWindowSeconds, 60) or 86400)
    for index = #incidentOrder - 1, 1, -1 do
        local candidate = incidentsById[incidentOrder[index]]
        if candidate and incident.firstSeenAt - (candidate.lastSeenAt or 0) > window then break end
        if candidate and candidate.category == 'crash' and candidate.sessionId ~= incident.sessionId
            and ((incident.accountId and candidate.accountId == incident.accountId)
                or (incident.citizenid ~= '' and candidate.citizenid == incident.citizenid)) then
            if addLinkedIncident(incident, candidate.id) and addLinkedIncident(candidate, incident.id) then
                queuePersistence(candidate, 'cross_session_link')
            end
        end
    end
end

local function processEnforcement(incident, input, created)
    if not MZBan.Enforcement or type(MZBan.Enforcement.Process) ~= 'function' then return nil end
    local ok, execution = pcall(MZBan.Enforcement.Process, incident, {
        created = created == true,
        detectionSource = normalizeSource(input.source),
        mitigation = type(input.enforcement) == 'table' and input.enforcement or nil
    })
    if ok then return execution end
    MZBan.AuditPrint('security.enforcement.failed', incident.id, safeString(execution, 160))
    return nil
end

function MZBan.Incidents.Record(input)
    input = type(input) == 'table' and input or {}
    local code = safeString(input.code, 64)
    local category = CODE_CATEGORIES[code]
    if not category then return nil, false, 'invalid_incident_code' end

    local source = normalizeSource(input.source)
    if not source then return nil, false, 'invalid_source' end

    local identity = resolveCoreIdentity(source) or {}
    input.citizenid = safeString(input.citizenid or identity.citizenid, 64)
    input.accountId = safeInteger(input.accountId or identity.accountId, 1)
    input.sessionId = safeInteger(input.sessionId or identity.sessionId, 1)
    local lab, labInfo = false, nil
    if MZBan.Lab and type(MZBan.Lab.IsSubject) == 'function' then
        lab, labInfo = MZBan.Lab.IsSubject(source, input)
    end

    local currentMs = nowMs()
    local currentTime = os.time()
    local key = aggregationKey(input)
    local aggregateWindow = math.max(1000, safeInteger(guardConfig().aggregateWindowMs, 1000) or 10000)
    local duplicateCooldown = math.max(100, safeInteger(guardConfig().duplicateCooldownMs, 100) or 1500)
    local id = aggregateByKey[key]
    local incident = id and incidentsById[id] or nil

    if incident and (currentMs - (incident.lastSeenMs or 0) <= aggregateWindow)
        and incident.status ~= 'resolved' and incident.status ~= 'false_positive' then
        local previousSeverity = incident.severity
        local previousConfidence = incident.confidence
        incident.count = incident.count + 1
        incident.updatedAt = currentTime
        incident.lastSeenAt = currentTime
        incident.lastSeenMs = currentMs
        incident.source = source
        incident.sourceAtLastSeen = source
        incident.accountId = input.accountId or incident.accountId
        incident.sessionId = input.sessionId or incident.sessionId
        incident.lab = incident.lab == true or lab == true
        incident.labInfo = incident.labInfo or labInfo
        incident.online = GetPlayerPing(source) > 0
        incident.playerName = safeString(input.playerName or GetPlayerName(source), 64)
        incident.subject = safeString(input.subject, 96) ~= '' and safeString(input.subject, 96) or incident.subject
        incident.damage = tonumber(input.damage) and math.max(0, math.min(10000, tonumber(input.damage))) or incident.damage
        incident.targetNetId = safeInteger(input.targetNetId, 0, 2147483647) or incident.targetNetId
        incident.riskScore = calculateRisk(code, incident.count)
        incident.severity = severityFor(code, incident.count, incident.riskScore)
        incident.culpability = culpabilityFor(code, input.culpability or incident.culpability)

        local evidenceAdded = false
        if currentMs - (incident.lastEvidenceMs or 0) >= duplicateCooldown then
            local maxEvidence = math.max(1, safeInteger(guardConfig().maxEvidencePerIncident, 1, 100) or 20)
            if #incident.evidence >= maxEvidence then
                table.remove(incident.evidence, 1)
                incident.droppedSampleCount = (incident.droppedSampleCount or 0) + 1
            end
            local sample = evidenceFrom(input, currentTime)
            sample.observation.first_seen_at = incident.firstSeenAt
            sample.observation.last_seen_at = currentTime
            sample.observation.count = incident.count
            sample.canonical.observation = sample.observation
            incident.evidence[#incident.evidence + 1] = sample
            incident.lastEvidenceMs = currentMs
            evidenceAdded = true
        else
            incident.suppressedCount = (incident.suppressedCount or 0) + 1
        end
        if type(input.timelineSnapshot) == 'table' and #input.timelineSnapshot > 0 then
            incident.timelineSnapshot = sanitizeStructured(input.timelineSnapshot, 0, { count = 0 }) or {}
        end
        local mitigationChanged = type(input.mitigation) == 'table'
        if mitigationChanged then
            incident.mitigation = sanitizeStructured(input.mitigation, 0, { count = 0 }) or incident.mitigation
        end
        if previousSeverity ~= incident.severity or previousConfidence ~= incident.confidence
            or incident.category == 'crash' or incident.lab == true or mitigationChanged then
            persistNow(incident, 'meaningful_change')
        elseif evidenceAdded then
            queuePersistence(incident, 'evidence_debounce')
        end
        persistRawSignal(incident, input, currentTime)
        local recordReason = evidenceAdded and 'aggregated' or 'duplicate_suppressed'
        local execution = processEnforcement(incident, input, false)
        return incident, false, recordReason, execution
    end

    enforceLimit()
    local identifiers = type(input.identifiers) == 'table' and input.identifiers or buildIdentifierContext(source)
    local riskScore = calculateRisk(code, 1)
    incident = {
        id = newIncidentId(),
        createdAt = currentTime,
        updatedAt = currentTime,
        firstSeenAt = currentTime,
        lastSeenAt = currentTime,
        createdMs = currentMs,
        lastSeenMs = currentMs,
        lastEvidenceMs = currentMs,
        source = source,
        sourceAtFirstSeen = source,
        sourceAtLastSeen = source,
        citizenid = input.citizenid,
        accountId = input.accountId,
        sessionId = input.sessionId,
        playerName = safeString(input.playerName or identity.name or GetPlayerName(source), 64),
        identifiers = {
            license = safeString(identifiers.license, 160),
            fivem = safeString(identifiers.fivem, 160)
        },
        category = category,
        code = code,
        origin = safeString(input.origin or 'server_event', 32),
        confidence = VALID_CONFIDENCE[input.confidence] and input.confidence or 'high',
        culpability = culpabilityFor(code, input.culpability),
        subject = safeString(input.subject, 96),
        severity = severityFor(code, 1, riskScore),
        riskScore = riskScore,
        count = 1,
        suppressedCount = 0,
        droppedSampleCount = 0,
        rawSignalDroppedCount = 0,
        rawSignalPersistenceFailed = 0,
        rawSignalBackpressureCount = 0,
        persistenceBackpressureCount = 0,
        reportedWeaponHash = normalizeHash(input.reportedWeaponHash),
        reportedWeaponName = safeString(input.reportedWeaponName, 64),
        authorizedWeaponHash = normalizeHash(input.authorizedWeaponHash),
        authorizedWeaponName = safeString(input.authorizedWeaponName, 64),
        authorizedAmmo = safeInteger(input.authorizedAmmo, 0, 1000000),
        targetNetId = safeInteger(input.targetNetId, 0, 2147483647),
        damage = tonumber(input.damage) and math.max(0, math.min(10000, tonumber(input.damage))) or nil,
        status = 'open',
        lab = lab == true,
        labInfo = labInfo,
        acknowledgedBy = nil,
        acknowledgedAt = nil,
        resolvedBy = nil,
        resolvedAt = nil,
        online = GetPlayerPing(source) > 0,
        notes = {},
        evidence = { evidenceFrom(input, currentTime) },
        timelineSnapshot = sanitizeStructured(input.timelineSnapshot or {}, 0, { count = 0 }) or {},
        mitigation = sanitizeStructured(input.mitigation or {
            attempted = false, applied = false, result = 'observe_only'
        }, 0, { count = 0 }) or {},
        linkedIncidentIds = sanitizeStructured(input.linkedIncidentIds or {}, 0, { count = 0 }) or {},
        aggregateKey = key,
        lastNotificationMs = 0
    }
    incidentsById[incident.id] = incident
    incidentOrder[#incidentOrder + 1] = incident.id
    aggregateByKey[key] = incident.id
    linkCrossSessionCrashes(incident)
    persistRawSignal(incident, input, currentTime)
    persistNow(incident, 'created')
    persistAction(incident, 'created', nil, nil, { code = code })
    audit('security.incident.created', nil, incident, {
        result = 'created',
        persist = false,
        evidence = code == 'player_godmode_suspect' and {
            invincible = incident.evidence[1] and incident.evidence[1].invincible == true,
            damageDisabled = incident.evidence[1] and incident.evidence[1].damageDisabled == true,
            fullProofs = incident.evidence[1] and incident.evidence[1].fullProofs == true
        } or nil
    })
    local execution = processEnforcement(incident, input, true)
    return incident, true, 'created', execution
end

local function refreshOnline(incident)
    local source = normalizeSource(incident and incident.source)
    if not source or GetPlayerPing(source) <= 0 then
        incident.online = false
        incident.source = nil
        return false
    end

    local currentIdentity = resolveCoreIdentity(source)
    local identityMismatch = incident.sessionId and (not currentIdentity or currentIdentity.sessionId ~= incident.sessionId)
        or (incident.citizenid ~= '' and (not currentIdentity or currentIdentity.citizenid ~= incident.citizenid))
    if not incident.sessionId and incident.citizenid == '' then
        local current = buildIdentifierContext(source)
        local expected = incident.identifiers or {}
        if expected.license and expected.license ~= '' then
            identityMismatch = current.license ~= expected.license
        elseif expected.fivem and expected.fivem ~= '' then
            identityMismatch = current.fivem ~= expected.fivem
        end
    end
    if identityMismatch then
        incident.online = false
        incident.source = nil
        return false
    end
    incident.online = true
    return true
end

local function copyNotes(notes)
    local out = {}
    for _, note in ipairs(notes or {}) do
        out[#out + 1] = {
            at = note.at,
            authorCitizenid = note.authorCitizenid,
            authorName = note.authorName,
            text = note.text
        }
    end
    return out
end

local function copyEvidence(evidence)
    return sanitizeStructured(evidence or {}, 0, { count = 0 }) or {}
end

local loadActions

local function maskedIdentifiers(incident)
    local identifiers = incident.identifiers or {}
    local function mask(value)
        value = safeString(value, 160)
        if value == '' then return nil end
        if type(MZBan.Redact) == 'function' then return MZBan.Redact(value) end
        return value:sub(1, math.min(8, #value)) .. '...'
    end
    local types, values = {}, {}
    for _, kind in ipairs({ 'license', 'fivem' }) do
        if safeString(identifiers[kind], 160) ~= '' then
            types[#types + 1] = kind
            values[kind] = mask(identifiers[kind])
        end
    end
    return { types = types, masked = values }
end

local function toDto(incident, options)
    options = type(options) == 'table' and options or {}
    refreshOnline(incident)
    local dto = {
        id = incident.id,
        createdAt = incident.createdAt,
        updatedAt = incident.updatedAt,
        firstSeenAt = incident.firstSeenAt,
        lastSeenAt = incident.lastSeenAt,
        firstSeenIso = MZBan.IsoUtc(incident.firstSeenAt),
        lastSeenIso = MZBan.IsoUtc(incident.lastSeenAt),
        source = incident.source,
        sourceAtFirstSeen = incident.sourceAtFirstSeen,
        sourceAtLastSeen = incident.sourceAtLastSeen,
        citizenid = incident.citizenid,
        accountId = incident.accountId,
        sessionId = incident.sessionId,
        playerName = incident.playerName,
        online = incident.online == true,
        category = incident.category,
        code = incident.code,
        origin = incident.origin,
        confidence = incident.confidence,
        culpability = incident.culpability,
        subject = incident.subject,
        severity = incident.severity,
        riskScore = incident.riskScore,
        count = incident.count,
        suppressedCount = incident.suppressedCount,
        occurrenceCount = incident.count,
        retainedSampleCount = #(incident.evidence or {}),
        droppedSampleCount = incident.droppedSampleCount or 0,
        suppressedSampleCount = incident.suppressedCount or 0,
        rawSignalDroppedCount = incident.rawSignalDroppedCount or 0,
        rawSignalPersistenceFailed = incident.rawSignalPersistenceFailed or 0,
        rawSignalBackpressureCount = incident.rawSignalBackpressureCount or 0,
        reportedWeaponHash = incident.reportedWeaponHash,
        reportedWeaponName = incident.reportedWeaponName,
        authorizedWeaponHash = incident.authorizedWeaponHash,
        authorizedWeaponName = incident.authorizedWeaponName,
        authorizedAmmo = incident.authorizedAmmo,
        targetNetId = incident.targetNetId,
        damage = incident.damage,
        status = incident.status,
        acknowledgedBy = incident.acknowledgedBy,
        acknowledgedAt = incident.acknowledgedAt,
        resolvedBy = incident.resolvedBy,
        resolvedAt = incident.resolvedAt,
        falsePositiveBy = incident.falsePositiveBy,
        falsePositiveAt = incident.falsePositiveAt,
        lab = incident.lab == true,
        human = nil,
        technical = nil
    }
    local catalog = MZBan.DetectorCatalog and MZBan.DetectorCatalog.Get(incident.code, incident.severity, incident.confidence) or {}
    dto.human = {
        title = catalog.label or incident.code,
        summary = catalog.short_description or incident.code,
        category_label = catalog.category_label or incident.category,
        severity_label = tostring(incident.severity or 'info'):upper(),
        severity_explanation = catalog.severity_explanation,
        confidence_label = tostring(incident.confidence or 'medium'):upper(),
        confidence_explanation = catalog.confidence_explanation,
        culpability = incident.culpability,
        culpability_explanation = incident.culpability == 'none'
            and 'O evento foi classificado; ele nao atribui conduta maliciosa.'
            or (incident.culpability == 'contextual'
                and 'O evento serve como contexto de investigacao, sem atribuir causalidade.'
                or 'Ha incompatibilidade investigavel; decisao humana e evidencia adicional continuam necessarias.'),
        mitigation_explanation = catalog.mitigation_explanation,
        recommended_action = catalog.recommended_action
    }
    dto.technical = {
        code = incident.code,
        hashes = {
            reported = incident.reportedWeaponHash,
            authorized = incident.authorizedWeaponHash
        },
        netIds = { target = incident.targetNetId },
        timestamps = { first = incident.firstSeenAt, last = incident.lastSeenAt, updated = incident.updatedAt },
        thresholds = incident.evidence and incident.evidence[1] and incident.evidence[1].detector
            and incident.evidence[1].detector.threshold or {},
        sourceHistory = {
            first = incident.sourceAtFirstSeen,
            last = incident.sourceAtLastSeen,
            current = incident.source
        }
    }
    if options.details == true then
        if loadActions then loadActions(incident) end
        dto.notes = copyNotes(incident.notes)
        dto.evidence = copyEvidence(incident.evidence)
        dto.timeline = incident.timelineSnapshot and copyEvidence(incident.timelineSnapshot)
            or (incident.source and MZBan.Correlation and type(MZBan.Correlation.Snapshot) == 'function'
                and MZBan.Correlation.Snapshot(incident.source, 12) or {})
        dto.mitigation = sanitizeStructured(incident.mitigation or {}, 0, { count = 0 }) or {}
        dto.labInfo = incident.labInfo and sanitizeStructured(incident.labInfo, 0, { count = 0 }) or nil
        dto.linkedIncidentIds = sanitizeStructured(incident.linkedIncidentIds or {}, 0, { count = 0 }) or {}
        dto.technical.rawEvidence = dto.evidence
    end
    if options.identifiers == true then
        dto.identifiers = maskedIdentifiers(incident)
    end
    return dto
end

local function matchesFilter(incident, filters)
    local filter = safeString(filters.filter or filters.status, 32):lower()
    if filter == 'open' and incident.status ~= 'open' then return false end
    if filter == 'acknowledged' and incident.status ~= 'acknowledged' then return false end
    if filter == 'critical' and incident.severity ~= 'critical' then return false end
    local categoryFilter = filter == 'weapons' and 'weapon' or filter
    if CODE_CATEGORIES[filter] then categoryFilter = nil end
    if categoryFilter == 'weapon' or categoryFilter == 'entity' or categoryFilter == 'movement'
        or categoryFilter == 'camera' or categoryFilter == 'player_state'
        or categoryFilter == 'event' or categoryFilter == 'aim' or categoryFilter == 'crash'
        or categoryFilter == 'runtime' or categoryFilter == 'canary' then
        if incident.category ~= categoryFilter then return false end
    end
    local player = safeString(filters.player or filters.search, 64):lower()
    if player ~= '' then
        local haystack = table.concat({
            tostring(incident.playerName or ''), tostring(incident.citizenid or ''), tostring(incident.source or '')
        }, ' '):lower()
        if not haystack:find(player, 1, true) then return false end
    end
    return true
end

function MZBan.Incidents.List(filters, options)
    MZBan.Incidents.Cleanup()
    filters = type(filters) == 'table' and filters or {}
    options = type(options) == 'table' and options or {}
    local limit = math.max(1, math.min(100, safeInteger(filters.limit, 1, 100) or 50))
    local out = {}
    for index = #incidentOrder, 1, -1 do
        local incident = incidentsById[incidentOrder[index]]
        if incident and matchesFilter(incident, filters) then
            out[#out + 1] = toDto(incident, options)
            if #out >= limit then break end
        end
    end
    return out
end

function MZBan.Incidents.Get(id)
    MZBan.Incidents.Cleanup()
    return incidentsById[safeString(id, 64)]
end

function MZBan.Incidents.ToDto(incident, options)
    if type(incident) ~= 'table' or not incident.id or incidentsById[incident.id] ~= incident then return nil end
    return toDto(incident, options)
end

function MZBan.Incidents.SessionTimeline(sessionId, limit)
    sessionId = safeInteger(sessionId, 1)
    limit = math.max(1, math.min(1000, safeInteger(limit, 1, 1000) or 250))
    if not sessionId or not MZBan.DB or type(MZBan.DB.LoadSessionSignals) ~= 'function'
        or type(MZBan.DB.LoadSessionIncidents) ~= 'function' then return nil, 'timeline_unavailable' end
    local okSignals, signals = pcall(MZBan.DB.LoadSessionSignals, sessionId, limit)
    local okIncidents, incidentRows = pcall(MZBan.DB.LoadSessionIncidents, sessionId, math.min(limit, 500))
    if not okSignals or not okIncidents then return nil, 'timeline_query_failed' end
    local timeline = {}
    for _, row in ipairs(type(signals) == 'table' and signals or {}) do
        timeline[#timeline + 1] = {
            at = tonumber(row.occurred_at), type = 'signal', id = safeString(row.signal_id, 64),
            incidentId = safeString(row.incident_id, 64), code = safeString(row.code, 80),
            origin = safeString(row.origin, 32), confidence = safeString(row.confidence, 16),
            culpability = safeString(row.culpability, 16), source = safeInteger(row.source_id, 1),
            evidence = sanitizeStructured(MZBan.JsonDecode(row.evidence_json, {}), 0, { count = 0 }) or {}
        }
    end
    for _, row in ipairs(type(incidentRows) == 'table' and incidentRows or {}) do
        timeline[#timeline + 1] = {
            at = tonumber(row.first_seen_at), type = 'incident', id = safeString(row.incident_id, 64),
            code = safeString(row.code, 64), status = safeString(row.status, 32),
            severity = safeString(row.severity, 16), confidence = safeString(row.confidence, 16),
            occurrenceCount = safeInteger(row.count, 1),
            suppressedSampleCount = safeInteger(row.suppressed_count, 0)
        }
    end
    table.sort(timeline, function(left, right)
        if (left.at or 0) == (right.at or 0) then return tostring(left.id) < tostring(right.id) end
        return (left.at or 0) < (right.at or 0)
    end)
    while #timeline > limit do table.remove(timeline) end
    return { sessionId = sessionId, timeline = timeline }, nil
end

exports('RecordSecurityCanary', function(sourceId, domain, canary, evidence)
    local cfg = type(Config.SecurityCanaries) == 'table' and Config.SecurityCanaries or {}
    local invokingResource = GetInvokingResource()
    local expectedDomain = type(cfg.owners) == 'table' and cfg.owners[invokingResource] or nil
    sourceId = normalizeSource(sourceId)
    domain = safeString(domain, 32)
    canary = safeString(canary, 64)
    if cfg.enabled ~= true or not sourceId or expectedDomain ~= domain or canary == '' then
        return nil, 'canary_contract_denied'
    end
    local incident, _, recordReason = MZBan.Incidents.Record({
        source = sourceId,
        playerName = GetPlayerName(sourceId),
        code = 'canary_triggered',
        origin = 'domain_canary',
        confidence = 'high',
        culpability = 'suspected',
        subject = domain .. ':' .. canary,
        reason = 'domain_security_canary_called',
        context = { domain = domain, canary = canary, invokingResource = invokingResource },
        evidence = type(evidence) == 'table' and evidence or {}
    })
    if incident then MZBan.Incidents.NotifyStaff(incident) end
    if incident then return incident.id, nil end
    return nil, recordReason or 'incident_rejected'
end)

function MZBan.Incidents.SetTimelineSnapshot(incident, timeline)
    if type(incident) ~= 'table' or not incident.id then return false end
    incident.timelineSnapshot = sanitizeStructured(timeline or {}, 0, { count = 0 }) or {}
    incident.updatedAt = os.time()
    persistNow(incident, 'timeline_snapshot')
    return true
end

function MZBan.Incidents.FlushPersistence(force)
    local currentMs = nowMs()
    local debounce = math.max(500, safeInteger(persistenceConfig().updateDebounceMs, 500) or 5000)
    local flushed = 0
    for id, pending in pairs(pendingPersistence) do
        local incident = pending.incident
        local retryReady = currentMs >= (pending.nextAttemptMs or 0)
        if force == true or (retryReady and currentMs - (incident.lastPersistMs or 0) >= debounce) then
            if persistNow(incident, pending.reason or 'debounced') then
                flushed = flushed + 1
                pendingPersistence[id] = nil
            end
        end
    end
    local signalFlushed = 0
    local batch = force == true and pendingSignalCount
        or math.max(1, safeInteger(persistenceConfig().signalFlushBatch, 1) or 16)
    local baseDelay = math.max(100, safeInteger(persistenceConfig().retryBaseMs, 100) or 1000)
    for id, pending in pairs(pendingSignals) do
        if signalFlushed >= batch then break end
        if force == true or currentMs >= (pending.nextAttemptMs or 0) then
            if saveSignal(pending.payload) then
                pendingSignals[id] = nil
                pendingSignalCount = math.max(0, pendingSignalCount - 1)
                signalFlushed = signalFlushed + 1
            else
                pending.attempts = (pending.attempts or 0) + 1
                pending.nextAttemptMs = currentMs + math.min(30000, baseDelay * (2 ^ math.min(5, pending.attempts)))
            end
        end
    end
    return flushed, signalFlushed
end

function MZBan.Incidents.EnsurePersisted(incident, reason)
    if type(incident) ~= 'table' or not incident.id or incidentsById[incident.id] ~= incident then
        return false, 'incident_not_found'
    end
    if incident.persistenceConfirmed == true and pendingPersistence[incident.id] == nil then return true end
    if persistNow(incident, reason or 'enforcement_precondition') then return true end
    return false, incident.persistenceError or 'incident_persistence_unconfirmed'
end

function MZBan.Incidents.RecordExecutionRequest(incident, execution)
    if type(incident) ~= 'table' or incidentsById[incident.id] ~= incident then return false end
    execution = sanitizeStructured(execution or {}, 0, { count = 0 }) or {}
    local persisted = persistAction(incident, 'enforcement_requested', nil, nil, execution)
    local requested = safeString(execution.requested_action, 32)
    if persisted and requested ~= '' then
        executionLedger[incident.id] = executionLedger[incident.id] or {}
        executionLedger[incident.id][requested] = true
    end
    return persisted
end

function MZBan.Incidents.RecordExecution(incident, execution)
    if type(incident) ~= 'table' or incidentsById[incident.id] ~= incident then return false end
    execution = sanitizeStructured(execution or {}, 0, { count = 0 }) or {}
    incident.mitigation = execution
    incident.updatedAt = os.time()
    local incidentPersisted = persistNow(incident, 'enforcement_result')
    local actionPersisted = persistAction(incident, 'enforcement_executed', nil, nil, execution)
    local requested = safeString(execution.requested_action, 32)
    if actionPersisted and execution.execution_result == 'success' and requested ~= '' then
        executionLedger[incident.id] = executionLedger[incident.id] or {}
        executionLedger[incident.id][requested] = true
    end
    return incidentPersisted and actionPersisted
end

function MZBan.Incidents.HasExecution(incident, requestedAction)
    if type(incident) ~= 'table' or incidentsById[incident.id] ~= incident then return false end
    requestedAction = safeString(requestedAction, 32)
    if executionLedger[incident.id] and executionLedger[incident.id][requestedAction] == true then return true end
    if not MZBan.DB or type(MZBan.DB.LoadIncidentActions) ~= 'function' then return false end
    local ok, rows = pcall(MZBan.DB.LoadIncidentActions, incident.id, 200)
    if not ok or type(rows) ~= 'table' then return false end
    for _, row in ipairs(rows) do
        local action = safeString(row.action, 80)
        if action == 'enforcement_requested' or action == 'enforcement_executed' then
            local meta = type(row.meta) == 'table' and row.meta or MZBan.JsonDecode(row.meta_json, {})
            local matchesRequest = safeString(meta.requested_action, 32) == requestedAction
            local terminalSuccess = action == 'enforcement_executed' and meta.execution_result == 'success'
            if matchesRequest and (action == 'enforcement_requested' or terminalSuccess) then
                executionLedger[incident.id] = executionLedger[incident.id] or {}
                executionLedger[incident.id][requestedAction] = true
                return true
            end
        end
    end
    return false
end

function MZBan.Incidents.PersistenceStatus()
    local incidents = 0
    for _ in pairs(pendingPersistence) do incidents = incidents + 1 end
    return { pendingIncidents = incidents, pendingSignals = pendingSignalCount }
end

function MZBan.Incidents.Hydrate(rows)
    rows = type(rows) == 'table' and rows or {}
    incidentsById, incidentOrder, aggregateByKey, executionLedger = {}, {}, {}, {}
    for index = #rows, 1, -1 do
        local row = rows[index]
        local summary = MZBan.JsonDecode(row.summary_json, {})
        local incident = {
            id = safeString(row.incident_id, 64),
            code = safeString(row.code, 64),
            category = safeString(row.category, 32),
            status = safeString(row.status, 32),
            severity = safeString(row.severity, 16),
            confidence = safeString(row.confidence, 16),
            culpability = culpabilityFor(row.code, summary.culpability),
            riskScore = safeInteger(row.risk_score, 0, 100) or 0,
            playerName = safeString(row.player_name, 64),
            citizenid = safeString(row.citizenid, 64),
            accountId = safeInteger(row.account_id, 1),
            sessionId = safeInteger(row.session_id, 1),
            firstSeenAt = tonumber(row.first_seen_at),
            lastSeenAt = tonumber(row.last_seen_at),
            createdAt = tonumber(row.created_at),
            updatedAt = tonumber(row.updated_at),
            createdMs = nowMs(), lastSeenMs = nowMs(), lastEvidenceMs = 0,
            count = safeInteger(row.count, 1) or 1,
            suppressedCount = safeInteger(row.suppressed_count, 0) or 0,
            droppedSampleCount = safeInteger(summary.droppedSampleCount, 0) or 0,
            rawSignalDroppedCount = safeInteger(summary.rawSignalDroppedCount, 0) or 0,
            rawSignalPersistenceFailed = safeInteger(summary.rawSignalPersistenceFailed, 0) or 0,
            rawSignalBackpressureCount = safeInteger(summary.rawSignalBackpressureCount, 0) or 0,
            persistenceBackpressureCount = safeInteger(summary.persistenceBackpressureCount, 0) or 0,
            source = nil, online = false,
            sourceAtFirstSeen = safeInteger(row.source_at_first_seen, 1),
            sourceAtLastSeen = safeInteger(row.source_at_last_seen, 1),
            subject = safeString(summary.subject, 96), origin = safeString(summary.origin, 32),
            reportedWeaponHash = normalizeHash(summary.reportedWeaponHash),
            reportedWeaponName = safeString(summary.reportedWeaponName, 64),
            authorizedWeaponHash = normalizeHash(summary.authorizedWeaponHash),
            authorizedWeaponName = safeString(summary.authorizedWeaponName, 64),
            authorizedAmmo = safeInteger(summary.authorizedAmmo, 0),
            targetNetId = safeInteger(summary.targetNetId, 0), damage = tonumber(summary.damage),
            acknowledgedBy = summary.acknowledgedBy, acknowledgedAt = tonumber(summary.acknowledgedAt),
            resolvedBy = row.resolved_by, resolvedAt = tonumber(row.resolved_at),
            falsePositiveBy = row.false_positive_by, falsePositiveAt = tonumber(row.false_positive_at),
            evidence = MZBan.JsonDecode(row.evidence_json, {}),
            timelineSnapshot = MZBan.JsonDecode(row.timeline_snapshot_json, {}),
            mitigation = MZBan.JsonDecode(row.mitigation_json, {}),
            linkedIncidentIds = type(summary.linkedIncidentIds) == 'table' and summary.linkedIncidentIds or {},
            lab = tonumber(row.lab) == 1 or row.lab == true,
            labInfo = type(summary.labInfo) == 'table' and summary.labInfo or nil,
            pinned = summary.pinned == true,
            identifiers = {},
            notes = type(summary.notes) == 'table' and summary.notes or {},
            actions = {}, actionsLoaded = false,
            aggregateKey = safeString(summary.aggregateKey, 512), lastNotificationMs = 0,
            lastPersistMs = nowMs(), lastPersistReason = 'hydrated'
        }
        incident.persistenceConfirmed = true
        if incident.id ~= '' and CODE_CATEGORIES[incident.code] then
            incidentsById[incident.id] = incident
            incidentOrder[#incidentOrder + 1] = incident.id
            if incident.aggregateKey ~= '' and incident.status ~= 'resolved' and incident.status ~= 'false_positive' then
                aggregateByKey[incident.aggregateKey] = incident.id
            end
        end
    end
    return #incidentOrder
end

loadActions = function(incident)
    if incident.actionsLoaded == true then return incident.actions or {} end
    incident.actionsLoaded = true
    incident.actions = {}
    local seenNotes = {}
    for _, note in ipairs(incident.notes or {}) do
        seenNotes[('%s:%s:%s'):format(tostring(note.at), tostring(note.authorCitizenid), tostring(note.text))] = true
    end
    if MZBan.DB and type(MZBan.DB.LoadIncidentActions) == 'function' then
        local ok, rows = pcall(MZBan.DB.LoadIncidentActions, incident.id, 100)
        if ok then
            for _, row in ipairs(type(rows) == 'table' and rows or {}) do
                local action = {
                    action = safeString(row.action, 80),
                    actorCitizenid = safeString(row.actor_citizenid, 64),
                    actorName = safeString(row.actor_name, 120),
                    note = safeString(row.note, 500),
                    meta = MZBan.JsonDecode(row.meta_json, {}),
                    at = tonumber(row.created_at)
                }
                incident.actions[#incident.actions + 1] = action
                if action.action == 'note_added' and action.note ~= '' then
                    local noteKey = ('%s:%s:%s'):format(tostring(action.at), tostring(action.actorCitizenid), tostring(action.note))
                    if not seenNotes[noteKey] then
                        incident.notes[#incident.notes + 1] = {
                            at = action.at, authorCitizenid = action.actorCitizenid,
                            authorName = action.actorName, text = action.note
                        }
                        seenNotes[noteKey] = true
                    end
                end
            end
        end
    end
    return incident.actions
end

function MZBan.Incidents.Export(id, format)
    local incident = MZBan.Incidents.Get(id)
    if not incident then return nil, 'incident_not_found' end
    incident.pinned = true
    incident.updatedAt = os.time()
    captureTimeline(incident)
    persistNow(incident, 'manual_preserve_export')
    local dto = toDto(incident, { details = true, identifiers = true })
    dto.actions = sanitizeStructured(loadActions(incident), 0, { count = 0 }) or {}
    local payload = {
        schema = 'mz_banguard.evidence.v1',
        exportedAt = MZBan.IsoUtc(os.time()),
        metadata = {
            incidentId = dto.id, status = dto.status, severity = dto.severity,
            confidence = dto.confidence, incidentRiskScore = dto.riskScore,
            firstSeenAt = dto.firstSeenAt, lastSeenAt = dto.lastSeenAt,
            count = dto.count, suppressedCount = dto.suppressedCount, lab = dto.lab,
            occurrenceCount = dto.occurrenceCount, retainedSampleCount = dto.retainedSampleCount,
            droppedSampleCount = dto.droppedSampleCount, suppressedSampleCount = dto.suppressedSampleCount,
            culpability = dto.culpability
        },
        player = {
            name = dto.playerName, citizenid = dto.citizenid, accountId = dto.accountId,
            sessionId = dto.sessionId, identifiers = dto.identifiers
        },
        human = dto.human,
        technical = dto.technical,
        evidence = dto.evidence,
        timeline = dto.timeline,
        mitigation = dto.mitigation,
        sourceHistory = dto.technical.sourceHistory,
        linkedIncidents = dto.linkedIncidentIds,
        lab = dto.labInfo,
        staffActions = dto.actions
    }
    format = safeString(format, 16):lower()
    if format == 'markdown' or format == 'md' or format == 'txt' then
        local lines = {
            '# Evidencia MZ BanGuard', '',
            ('- Incidente: `%s`'):format(dto.id),
            ('- Detector: `%s` — %s'):format(dto.code, dto.human.title),
            ('- Jogador: %s (`%s`)'):format(dto.playerName or '-', dto.citizenid or '-'),
            ('- Severidade: %s | Confianca: %s | Status: %s'):format(dto.severity, dto.confidence, dto.status),
            ('- Primeira/ultima observacao: %s / %s'):format(dto.firstSeenIso or '-', dto.lastSeenIso or '-'),
            ('- Ocorrencias: %d (%d suprimidas)'):format(dto.count or 1, dto.suppressedCount or 0),
            ('- LAB: %s'):format(dto.lab and 'sim' or 'nao'), '',
            '## Resumo', '', dto.human.summary or '-', '',
            '## Acao recomendada', '', dto.human.recommended_action or '-', '',
            '## Evidencia tecnica sanitizada', '', '```json', MZBan.JsonEncode(payload), '```'
        }
        return table.concat(lines, '\n'), 'text/markdown', dto.id .. '.md'
    end
    return MZBan.JsonEncode(payload), 'application/json', dto.id .. '.json'
end

function MZBan.Incidents.AuditAccess(actorSource, id, action, meta)
    local incident = incidentsById[safeString(id, 64)]
    meta = type(meta) == 'table' and meta or {}
    meta.result = safeString(meta.result or 'accessed', 32)
    audit(safeString(action, 96), actorSource, incident, meta)
    if incident then persistAction(incident, safeString(action, 80), actorPayload(actorSource), nil, meta) end
    return incident ~= nil
end

function MZBan.Incidents.Summary()
    MZBan.Incidents.Cleanup()
    local summary = { total = 0, open = 0, critical = 0, unacknowledged = 0, players = {}, categories = {} }
    local players = {}
    for _, id in ipairs(incidentOrder) do
        local incident = incidentsById[id]
        if incident then
            summary.total = summary.total + 1
            summary.categories[incident.category] = (summary.categories[incident.category] or 0) + 1
            if incident.status == 'open' then summary.open = summary.open + 1 end
            if incident.severity == 'critical' and incident.status ~= 'resolved' and incident.status ~= 'false_positive' then
                summary.critical = summary.critical + 1
            end
            if incident.status == 'open' then summary.unacknowledged = summary.unacknowledged + 1 end

            local key = incident.citizenid ~= '' and incident.citizenid or (incident.identifiers.license ~= '' and incident.identifiers.license or incident.playerName)
            local player = players[key]
            if not player then
                player = { citizenid = incident.citizenid, playerName = incident.playerName, source = incident.source, riskScore = 0, incidents = 0, occurrences = 0 }
                players[key] = player
            end
            player.riskScore = math.max(player.riskScore, incident.riskScore or 0)
            player.incidents = player.incidents + 1
            player.occurrences = player.occurrences + (incident.count or 1)
            if incident.source then player.source = incident.source end
        end
    end
    for _, player in pairs(players) do summary.players[#summary.players + 1] = player end
    table.sort(summary.players, function(left, right)
        if left.riskScore == right.riskScore then return left.occurrences > right.occurrences end
        return left.riskScore > right.riskScore
    end)
    summary.topPlayer = summary.players[1]
    return summary
end

function MZBan.Incidents.Acknowledge(actorSource, id)
    local incident = MZBan.Incidents.Get(id)
    if not incident then return nil, 'incident_not_found' end
    if incident.status == 'resolved' or incident.status == 'false_positive' then return nil, 'incident_closed' end
    local actor = actorPayload(actorSource)
    incident.status = 'acknowledged'
    incident.acknowledgedBy = actor.citizenid or actor.id
    incident.acknowledgedAt = os.time()
    incident.updatedAt = incident.acknowledgedAt
    persistNow(incident, 'acknowledged')
    persistAction(incident, 'acknowledged', actor)
    audit('security.incident.acknowledged', actorSource, incident, { result = 'acknowledged' })
    return incident
end

function MZBan.Incidents.AddNote(actorSource, id, text)
    local incident = MZBan.Incidents.Get(id)
    if not incident then return nil, 'incident_not_found' end
    text = safeString(text, 500)
    if #text < 3 then return nil, 'invalid_note' end
    local actor = actorPayload(actorSource)
    local maximum = math.max(1, math.min(100, safeInteger(guardConfig().maxNotesPerIncident, 1, 100) or 25))
    if #incident.notes >= maximum then table.remove(incident.notes, 1) end
    incident.notes[#incident.notes + 1] = {
        at = os.time(),
        authorCitizenid = actor.citizenid,
        authorName = actor.name,
        text = text
    }
    incident.updatedAt = os.time()
    persistNow(incident, 'note_added')
    persistAction(incident, 'note_added', actor, text)
    audit('security.incident.note_added', actorSource, incident, { result = 'note_added' })
    return incident
end

function MZBan.Incidents.SetStatus(actorSource, id, status)
    local incident = MZBan.Incidents.Get(id)
    if not incident then return nil, 'incident_not_found' end
    status = safeString(status, 32):lower()
    if not VALID_STATUSES[status] then return nil, 'invalid_status' end

    local actor = actorPayload(actorSource)
    incident.status = status
    incident.updatedAt = os.time()
    if status == 'acknowledged' then
        incident.acknowledgedBy = actor.citizenid or actor.id
        incident.acknowledgedAt = incident.updatedAt
    elseif status == 'resolved' or status == 'false_positive' then
        incident.resolvedBy = actor.citizenid or actor.id
        incident.resolvedAt = incident.updatedAt
        if status == 'false_positive' then
            incident.falsePositiveBy = actor.citizenid or actor.id
            incident.falsePositiveAt = incident.updatedAt
        end
    elseif status == 'open' then
        incident.resolvedBy = nil
        incident.resolvedAt = nil
        incident.falsePositiveBy = nil
        incident.falsePositiveAt = nil
    end
    persistNow(incident, 'status_changed')
    persistAction(incident, 'status_changed', actor, nil, { status = status })
    audit('security.incident.status_changed', actorSource, incident, { result = status })
    return incident
end

function MZBan.Incidents.MarkSourceDisconnected(source)
    source = normalizeSource(source)
    if not source then return 0 end
    local changed = 0
    for _, incident in pairs(incidentsById) do
        if incident.source == source then
            incident.source = nil
            incident.online = false
            changed = changed + 1
        end
    end
    return changed
end

function MZBan.Incidents.HasPermission(source, permissionKey)
    return hasPermission(source, permissionKey)
end

function MZBan.Incidents.IsTrustedConsumer(resource)
    local trusted = type(guardConfig().trustedConsumers) == 'table' and guardConfig().trustedConsumers or {}
    return type(resource) == 'string' and trusted[resource] == true
end

function MZBan.Incidents.CanNotify(incident)
    if type(incident) ~= 'table' or guardConfig().notifyStaff ~= true then return false end
    local ranks = { info = 0, low = 1, medium = 2, high = 3, critical = 4 }
    local minimum = safeString(guardConfig().notifyMinimumSeverity or 'high', 16):lower()
    if (ranks[incident.severity] or 0) < (ranks[minimum] or ranks.high) then return false end
    local currentMs = nowMs()
    local cooldown = math.max(1000, safeInteger(guardConfig().notificationCooldownMs, 1000) or 10000)
    if (incident.lastNotificationMs or 0) > 0
        and currentMs - incident.lastNotificationMs < cooldown then return false end
    incident.lastNotificationMs = currentMs
    return true
end

function MZBan.Incidents.NotifyStaff(incident)
    if not MZBan.Incidents.CanNotify(incident) then return 0 end
    local notified = 0
    for _, playerId in ipairs(GetPlayers()) do
        local staffSource = normalizeSource(playerId)
        if staffSource and hasPermission(staffSource, 'view') then
            local catalog = MZBan.DetectorCatalog and MZBan.DetectorCatalog.Get(
                incident.code, incident.severity, incident.confidence
            ) or {}
            local payload = {
                type = incident.severity == 'critical' and 'error' or 'warning',
                title = 'MZ Security',
                message = ('%s - %s | %s | ocorrencias: %d'):format(
                    incident.playerName, catalog.category_label or incident.category,
                    catalog.label or incident.code, incident.count
                ),
                duration = 7000,
                id = 'mz_security:' .. incident.id,
                icon = 'shield-exclamation'
            }
            if GetResourceState('mz_notify') == 'started' then
                pcall(function() exports['mz_notify']:Notify(staffSource, payload) end)
            else
                TriggerClientEvent('mz_menu:client:notify', staffSource, payload)
            end
            notified = notified + 1
        end
    end
    return notified
end

CreateThread(function()
    while true do
        Wait(math.max(500, safeInteger(persistenceConfig().flushIntervalMs, 500) or 2000))
        MZBan.Incidents.FlushPersistence(false)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then MZBan.Incidents.FlushPersistence(true) end
end)

function MZBan.Incidents.ResolveActionTarget(actorSource, id, action)
    action = safeString(action, 32):lower()
    local permissionKey = ACTION_PERMISSIONS[action]
    if not permissionKey then return nil, 'action_not_implemented' end
    if action == 'kick' or action == 'ban' then return nil, 'action_not_implemented' end
    if not hasPermission(actorSource, permissionKey) then
        audit('security.incident.action_denied', actorSource, incidentsById[safeString(id, 64)], {
            result = 'denied', reason = 'permission_denied', action = action
        })
        return nil, 'permission_denied'
    end

    local incident = MZBan.Incidents.Get(id)
    if not incident then return nil, 'incident_not_found' end
    if not refreshOnline(incident) or not incident.source then
        audit('security.incident.action_denied', actorSource, incident, { result = 'denied', reason = 'target_offline', action = action })
        return nil, 'target_offline'
    end

    local resource = coreResource()
    local ok, allowed, hierarchyReason = pcall(function()
        return exports[resource]:CanStaffActOnPlayer(actorSource, incident.source)
    end)
    if not ok or allowed ~= true then
        audit('security.incident.action_denied', actorSource, incident, { result = 'denied', reason = hierarchyReason or 'hierarchy_denied', action = action })
        return nil, hierarchyReason or 'hierarchy_denied'
    end

    audit('security.incident.action_authorized', actorSource, incident, { result = 'authorized', action = action })
    persistAction(incident, 'action_authorized', actorPayload(actorSource), nil, { action = action })
    return incident.source, nil, incident
end
