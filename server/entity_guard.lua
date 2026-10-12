MZBan = MZBan or {}
MZBan.EntityGuard = MZBan.EntityGuard or {}

local rates = {}
local observedEntities = {}
local scheduled = {}
local blockedModels = { ped = {}, vehicle = {}, object = {} }

local function config()
    return type(Config.EntityGuard) == 'table' and Config.EntityGuard or {}
end

local function nowMs()
    return math.max(0, math.floor(tonumber(GetGameTimer()) or 0))
end

local function online(sourceId)
    sourceId = tonumber(sourceId)
    return sourceId and sourceId > 0 and GetPlayerPing(math.floor(sourceId)) > 0
end

local function safeNative(native, fallback, ...)
    local ok, value = pcall(native, ...)
    if not ok or value == nil then return fallback end
    return value
end

local function normalizeHash(value)
    if type(value) == 'string' and not tonumber(value) then value = joaat(value) end
    value = tonumber(value)
    if not value then return nil end
    value = math.floor(value)
    if value < 0 then value = value + 4294967296 end
    return value >= 0 and value <= 4294967295 and value or nil
end

local function rebuildBlockedModels()
    blockedModels = { ped = {}, vehicle = {}, object = {} }
    local configured = type(config().blockedModels) == 'table' and config().blockedModels or {}
    for kind in pairs(blockedModels) do
        for key, value in pairs(type(configured[kind]) == 'table' and configured[kind] or {}) do
            local candidate
            if type(value) == 'boolean' and value == true then candidate = key else candidate = value end
            local hash = normalizeHash(candidate)
            if hash then blockedModels[kind][hash] = true end
        end
    end
end

local function entityKind(entity)
    local entityType = tonumber(safeNative(GetEntityType, 0, entity))
    if entityType == 1 then return 'ped' end
    if entityType == 2 then return 'vehicle' end
    if entityType == 3 then return 'object' end
    return nil
end

local function resolveOwners(entity)
    local first = tonumber(safeNative(NetworkGetFirstEntityOwner, 0, entity))
    local current = tonumber(safeNative(NetworkGetEntityOwner, 0, entity))
    if not online(first) then first = nil else first = math.floor(first) end
    if not online(current) then current = nil else current = math.floor(current) end
    return first, current, first or current
end

local function rateFor(sourceId, kind, classification, bucket, currentMs)
    local class = type(classification) == 'table' and classification.class or 'unknown'
    local key = ('%d:%s:%s:%d'):format(sourceId, kind, class, bucket)
    local timestamps = rates[key] or {}
    rates[key] = timestamps
    timestamps[#timestamps + 1] = currentMs

    local window = math.max(1000, math.floor(tonumber(config().windowMs) or 10000))
    local burstWindow = math.max(250, math.min(window, math.floor(tonumber(config().burstWindowMs) or 2000)))
    local cutoff = currentMs - window
    while timestamps[1] and timestamps[1] < cutoff do table.remove(timestamps, 1) end
    local burstCount = 0
    local burstCutoff = currentMs - burstWindow
    for index = #timestamps, 1, -1 do
        if timestamps[index] < burstCutoff then break end
        burstCount = burstCount + 1
    end
    return #timestamps, burstCount, window, burstWindow
end

local function leaseFor(sourceId, kind, context)
    if not MZBan.SecurityLeases or type(MZBan.SecurityLeases.Consume) ~= 'function' then return false end
    return MZBan.SecurityLeases.Consume(sourceId, 'entity.spawn.' .. kind, context)
end

local function recordIncident(sourceId, code, kind, reason, evidence, confidence, enforcement)
    local incident = MZBan.Incidents.Record({
        source = sourceId,
        playerName = GetPlayerName(sourceId),
        code = code,
        origin = 'server_event',
        confidence = confidence or 'high',
        subject = ('%s:%s:%s'):format(kind, tostring(evidence.populationClass or 'unknown'), tostring(evidence.bucket or 0)),
        reason = reason,
        evidence = evidence,
        enforcement = enforcement
    })
    if incident then MZBan.Incidents.NotifyStaff(incident) end
    return incident
end

local function mitigationCapability(sourceId, phase, blocked, rateExceeded, confidence)
    local guard = config()
    if phase ~= 'creating' then
        return { supported = false, reason = 'entity_already_created', resource = GetCurrentResourceName() }
    end
    if MZBan.Lab and type(MZBan.Lab.IsSubject) == 'function' and MZBan.Lab.IsSubject(sourceId) == true then
        return { supported = false, reason = 'lab_mode', resource = GetCurrentResourceName() }
    end
    if blocked ~= true and not (rateExceeded == true and confidence == 'high') then
        return { supported = false, reason = 'entity_evidence_not_high_confidence', resource = GetCurrentResourceName() }
    end
    if guard.cancelHighConfidence ~= true or guard.runtimeValidated ~= true then
        return { supported = false, reason = 'entity_cancel_runtime_not_validated', resource = GetCurrentResourceName() }
    end
    return {
        supported = true,
        resource = GetCurrentResourceName(),
        execute = function()
            CancelEvent()
            return true, 'blocked', 'entity_creation_cancelled'
        end
    }
end

local function inspect(entity, phase, attempt)
    scheduled[entity] = nil
    if config().enabled ~= true or not entity or entity == 0 or observedEntities[entity] then return end
    if safeNative(DoesEntityExist, false, entity) ~= true then return end

    local kind = entityKind(entity)
    if not kind then return end
    if kind == 'ped' and safeNative(IsPedAPlayer, false, entity) == true then return end

    local firstOwner, currentOwner, owner = resolveOwners(entity)
    attempt = math.max(1, math.floor(tonumber(attempt) or 1))
    local maxAttempts = math.max(1, math.min(8, math.floor(tonumber(config().ownerResolveAttempts) or 3)))
    if not owner and attempt < maxAttempts then
        scheduled[entity] = true
        SetTimeout(math.max(50, math.floor(tonumber(config().ownerResolveRetryMs) or 200)), function()
            inspect(entity, phase, attempt + 1)
        end)
        return
    end
    if not owner then
        if MZBan.DetectorHealth then MZBan.DetectorHealth.Discard('entity_guard', 'owner_unresolved') end
        return
    end

    observedEntities[entity] = nowMs()
    local model = normalizeHash(safeNative(GetEntityModel, 0, entity)) or 0
    local population = tonumber(safeNative(GetEntityPopulationType, -1, entity)) or -1
    local classification = MZBan.EntityClassification
        and type(MZBan.EntityClassification.Classify) == 'function'
        and MZBan.EntityClassification.Classify(population)
        or {
            populationType = population, name = 'unknown', class = 'unknown',
            alertOnRate = true, confidence = 'medium', mappingVersion = 'fallback', mappingValidated = false
        }
    if MZBan.EntityClassification and type(MZBan.EntityClassification.Observe) == 'function' then
        MZBan.EntityClassification.Observe(kind, classification)
    end
    local bucket = tonumber(safeNative(GetEntityRoutingBucket, 0, entity)) or 0
    local leaseContext = { model = model, bucket = bucket }
    local authorized, lease = leaseFor(owner, kind, leaseContext)
    if authorized == true then
        if MZBan.Correlation then
            MZBan.Correlation.Record(owner, 'entity.authorized', {
                entityType = kind, model = model, bucket = bucket,
                leaseId = lease and lease.id, resource = lease and lease.issuer
            })
        end
        if MZBan.DetectorHealth then MZBan.DetectorHealth.Discard('entity_guard', 'authorized_lease') end
        return
    end

    local currentMs = nowMs()
    local count, burstCount, window, burstWindow = rateFor(owner, kind, classification, bucket, currentMs)
    local limits = type(config().limits) == 'table' and config().limits or {}
    local burstLimits = type(config().burstLimits) == 'table' and config().burstLimits or {}
    local maximum = math.max(1, math.floor(tonumber(limits[kind]) or 10))
    local burstMaximum = math.max(1, math.floor(tonumber(burstLimits[kind]) or maximum))
    local blocked = blockedModels[kind][model] == true
    local rateExceeded = classification.alertOnRate == true and (count > maximum or burstCount > burstMaximum)
    local correlationId
    if (blocked or rateExceeded) and MZBan.Correlation then
        correlationId = MZBan.Correlation.Record(owner, 'entity.suspicious', {
            entityType = kind, model = model, bucket = bucket, phase = phase,
            amount = count, burst = burstCount, firstOwner = firstOwner, owner = currentOwner,
            populationClass = classification.class
        })
    end
    local evidence = {
        origin = 'server_event', entityType = kind, model = model, amount = count,
        burstAmount = burstCount, windowMs = window, burstWindowMs = burstWindow,
        eventType = population, bucket = bucket, owner = currentOwner,
        firstOwner = firstOwner, correlationId = correlationId, phase = phase,
        populationName = classification.name, populationClass = classification.class,
        mappingVersion = classification.mappingVersion,
        mappingValidated = classification.mappingValidated
    }
    local enforcement = mitigationCapability(owner, phase, blocked, rateExceeded, classification.confidence)

    if blocked then
        recordIncident(owner, 'entity_model_blocked', kind, 'entity_model_in_server_blocklist', evidence, 'high', enforcement)
    end
    if rateExceeded then
        recordIncident(owner, 'entity_spawn_rate_suspect', kind,
            burstCount > burstMaximum and 'scripted_entity_burst_above_observation_limit'
                or 'scripted_entity_rate_above_observation_limit',
            evidence, classification.confidence, enforcement)
    end
    if MZBan.DetectorHealth then MZBan.DetectorHealth.Seen('entity_guard.' .. tostring(classification.class)) end
end

AddEventHandler('entityCreating', function(entity)
    if config().enabled == true then inspect(entity, 'creating', 1) end
end)

AddEventHandler('entityCreated', function(entity)
    if config().enabled ~= true or observedEntities[entity] or scheduled[entity] then return end
    SetTimeout(math.max(0, math.min(2000, math.floor(tonumber(config().inspectDelayMs) or 250))), function()
        inspect(entity, 'created', 1)
    end)
end)

AddEventHandler('playerDropped', function()
    local prefix = tostring(math.floor(tonumber(source) or 0)) .. ':'
    for key in pairs(rates) do if key:sub(1, #prefix) == prefix then rates[key] = nil end end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then rebuildBlockedModels() end
end)

rebuildBlockedModels()
CreateThread(function()
    while true do
        Wait(30000)
        local cutoff = nowMs() - 60000
        for entity, observedAt in pairs(observedEntities) do
            if observedAt < cutoff or safeNative(DoesEntityExist, false, entity) ~= true then observedEntities[entity] = nil end
        end
    end
end)

MZBan.EntityGuard.Inspect = inspect
MZBan.EntityGuard.RebuildBlockedModels = rebuildBlockedModels
