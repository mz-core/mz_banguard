MZBan = MZBan or {}
MZBan.Incidents = MZBan.Incidents or {}

local incidentsById = {}
local incidentOrder = {}
local aggregateByKey = {}
local sequence = 0

local CODE_CATEGORIES = {
    weapon_damage_no_equipped_weapon = 'weapon',
    weapon_damage_hash_mismatch = 'weapon',
    weapon_damage_unknown_hash = 'weapon',
    weapon_damage_session_not_ready = 'weapon',
    weapon_damage_transition_window = 'weapon',
    weapon_damage_payload_invalid = 'weapon',
    weapon_damage_rate_suspect = 'weapon',
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
    event_fire_rate_suspect = 'event',
    event_fire_remote_suspect = 'event',
    event_remote_weapon_action_suspect = 'event',
    event_damage_modifier_suspect = 'event',
    aim_headshot_pattern_suspect = 'aim'
}

local VALID_CONFIDENCE = { low = true, medium = true, high = true, critical = true }

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
    return {
        citizenid = safeString(identity.citizenid, 64),
        name = safeString(identity.name or GetPlayerName(source), 64)
    }
end

local function actorPayload(source)
    local identity = resolveCoreIdentity(source) or {}
    return {
        type = 'player',
        id = identity.citizenid ~= '' and identity.citizenid or ('source:%s'):format(tostring(source)),
        source = normalizeSource(source),
        citizenid = identity.citizenid ~= '' and identity.citizenid or nil,
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
    if safeString(input.citizenid, 64) ~= '' then return 'citizen:' .. safeString(input.citizenid, 64) end
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
    rateCount = true, rateThreshold = true, rateWindowMs = true
}

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
    if aggregateByKey[incident.aggregateKey] == id then aggregateByKey[incident.aggregateKey] = nil end
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
        reason = safeString(input.reason, 96)
    }
    for key, value in pairs(sanitizeEvidenceData(input)) do evidence[key] = value end
    return evidence
end

function MZBan.Incidents.Record(input)
    input = type(input) == 'table' and input or {}
    local code = safeString(input.code, 64)
    local category = CODE_CATEGORIES[code]
    if not category then return nil, false, 'invalid_incident_code' end

    local source = normalizeSource(input.source)
    if not source then return nil, false, 'invalid_source' end

    local currentMs = nowMs()
    local currentTime = os.time()
    local key = aggregationKey(input)
    local aggregateWindow = math.max(1000, safeInteger(guardConfig().aggregateWindowMs, 1000) or 10000)
    local duplicateCooldown = math.max(100, safeInteger(guardConfig().duplicateCooldownMs, 100) or 1500)
    local id = aggregateByKey[key]
    local incident = id and incidentsById[id] or nil

    if incident and (currentMs - (incident.lastSeenMs or 0) <= aggregateWindow)
        and incident.status ~= 'resolved' and incident.status ~= 'false_positive' then
        incident.count = incident.count + 1
        incident.updatedAt = currentTime
        incident.lastSeenAt = currentTime
        incident.lastSeenMs = currentMs
        incident.source = source
        incident.online = GetPlayerPing(source) > 0
        incident.playerName = safeString(input.playerName or GetPlayerName(source), 64)
        incident.subject = safeString(input.subject, 96) ~= '' and safeString(input.subject, 96) or incident.subject
        incident.damage = tonumber(input.damage) and math.max(0, math.min(10000, tonumber(input.damage))) or incident.damage
        incident.targetNetId = safeInteger(input.targetNetId, 0, 2147483647) or incident.targetNetId
        incident.riskScore = calculateRisk(code, incident.count)
        incident.severity = severityFor(code, incident.count, incident.riskScore)

        local evidenceAdded = false
        if currentMs - (incident.lastEvidenceMs or 0) >= duplicateCooldown then
            local maxEvidence = math.max(1, safeInteger(guardConfig().maxEvidencePerIncident, 1, 100) or 20)
            if #incident.evidence >= maxEvidence then table.remove(incident.evidence, 1) end
            incident.evidence[#incident.evidence + 1] = evidenceFrom(input, currentTime)
            incident.lastEvidenceMs = currentMs
            evidenceAdded = true
        else
            incident.suppressedCount = (incident.suppressedCount or 0) + 1
        end
        return incident, false, evidenceAdded and 'aggregated' or 'duplicate_suppressed'
    end

    enforceLimit()
    local identifiers = type(input.identifiers) == 'table' and input.identifiers or buildIdentifierContext(source)
    local identity = resolveCoreIdentity(source) or {}
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
        citizenid = safeString(input.citizenid or identity.citizenid, 64),
        playerName = safeString(input.playerName or identity.name or GetPlayerName(source), 64),
        identifiers = {
            license = safeString(identifiers.license, 160),
            fivem = safeString(identifiers.fivem, 160)
        },
        category = category,
        code = code,
        origin = safeString(input.origin or 'server_event', 32),
        confidence = VALID_CONFIDENCE[input.confidence] and input.confidence or 'high',
        subject = safeString(input.subject, 96),
        severity = severityFor(code, 1, riskScore),
        riskScore = riskScore,
        count = 1,
        suppressedCount = 0,
        reportedWeaponHash = normalizeHash(input.reportedWeaponHash),
        reportedWeaponName = safeString(input.reportedWeaponName, 64),
        authorizedWeaponHash = normalizeHash(input.authorizedWeaponHash),
        authorizedWeaponName = safeString(input.authorizedWeaponName, 64),
        authorizedAmmo = safeInteger(input.authorizedAmmo, 0, 1000000),
        targetNetId = safeInteger(input.targetNetId, 0, 2147483647),
        damage = tonumber(input.damage) and math.max(0, math.min(10000, tonumber(input.damage))) or nil,
        status = 'open',
        acknowledgedBy = nil,
        acknowledgedAt = nil,
        resolvedBy = nil,
        resolvedAt = nil,
        online = GetPlayerPing(source) > 0,
        notes = {},
        evidence = { evidenceFrom(input, currentTime) },
        aggregateKey = key,
        lastNotificationMs = 0
    }
    incidentsById[incident.id] = incident
    incidentOrder[#incidentOrder + 1] = incident.id
    aggregateByKey[key] = incident.id
    audit('security.incident.created', nil, incident, {
        result = 'created',
        persist = false,
        evidence = code == 'player_godmode_suspect' and {
            invincible = incident.evidence[1] and incident.evidence[1].invincible == true,
            damageDisabled = incident.evidence[1] and incident.evidence[1].damageDisabled == true,
            fullProofs = incident.evidence[1] and incident.evidence[1].fullProofs == true
        } or nil
    })
    return incident, true, 'created'
end

local function refreshOnline(incident)
    local source = normalizeSource(incident and incident.source)
    if not source or GetPlayerPing(source) <= 0 then
        incident.online = false
        incident.source = nil
        return false
    end

    local current = buildIdentifierContext(source)
    local expected = incident.identifiers or {}
    local identityMismatch = false
    if expected.license ~= '' then
        identityMismatch = current.license ~= expected.license
    elseif expected.fivem ~= '' then
        identityMismatch = current.fivem ~= expected.fivem
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
    local out = {}
    for _, item in ipairs(evidence or {}) do
        local copy = {}
        for key, value in pairs(item) do copy[key] = value end
        out[#out + 1] = copy
    end
    return out
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
        citizenid = incident.citizenid,
        playerName = incident.playerName,
        online = incident.online == true,
        category = incident.category,
        code = incident.code,
        origin = incident.origin,
        confidence = incident.confidence,
        subject = incident.subject,
        severity = incident.severity,
        riskScore = incident.riskScore,
        count = incident.count,
        suppressedCount = incident.suppressedCount,
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
        resolvedAt = incident.resolvedAt
    }
    if options.details == true then
        dto.notes = copyNotes(incident.notes)
        dto.evidence = copyEvidence(incident.evidence)
        dto.timeline = incident.source and MZBan.Correlation
            and type(MZBan.Correlation.Snapshot) == 'function'
            and MZBan.Correlation.Snapshot(incident.source, 12) or {}
    end
    if options.identifiers == true then
        dto.identifiers = {
            license = incident.identifiers.license ~= '' and incident.identifiers.license or nil,
            fivem = incident.identifiers.fivem ~= '' and incident.identifiers.fivem or nil
        }
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
        or categoryFilter == 'event' or categoryFilter == 'aim' then
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

function MZBan.Incidents.AuditAccess(actorSource, id, action, meta)
    local incident = incidentsById[safeString(id, 64)]
    meta = type(meta) == 'table' and meta or {}
    meta.result = safeString(meta.result or 'accessed', 32)
    audit(safeString(action, 96), actorSource, incident, meta)
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
    elseif status == 'open' then
        incident.resolvedBy = nil
        incident.resolvedAt = nil
    end
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
            local payload = {
                type = incident.severity == 'critical' and 'error' or 'warning',
                title = 'MZ Security',
                message = ('%s - %s | %s | ocorrencias: %d'):format(
                    incident.playerName, incident.category, incident.code, incident.count
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
    return incident.source, nil, incident
end
