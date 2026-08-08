MZBan = MZBan or {}
MZBan.SecurityLeases = MZBan.SecurityLeases or {}

local leasesByPlayer = {}
local sequence = 0
local deniedAuditAt = {}

local CONTEXT_FIELDS = {
    model = true, bucket = true, target = true, targetNetId = true, vehicleNetId = true,
    quantity = true, x = true, y = true, z = true, reason = true, correlationId = true,
    eventType = true, weaponHash = true, effectHash = true, projectileHash = true
}

local function config()
    return type(Config.SecurityLeases) == 'table' and Config.SecurityLeases or {}
end

local function nowMs()
    return math.max(0, math.floor(tonumber(GetGameTimer()) or 0))
end

local function token(value, maximum)
    value = tostring(value or ''):lower():gsub('%c', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' or #value > (maximum or 64) or not value:match('^[a-z0-9_.:%-]+$') then return nil end
    return value
end

local function normalizeSource(value)
    value = tonumber(value)
    if not value or value <= 0 then return nil end
    value = math.floor(value)
    return GetPlayerName(value) and value or nil
end

local function currentIdentity(sourceId)
    if type(GetResourceState) ~= 'function' or GetResourceState('mz_core') ~= 'started' then return nil end
    local ok, identity = pcall(function()
        return exports['mz_core']:ResolvePlayerIdentity(sourceId)
    end)
    if not ok or type(identity) ~= 'table' or identity.ok ~= true then return nil end
    local citizenid = tostring(identity.citizenid or ''):gsub('%c', ''):sub(1, 64)
    return citizenid ~= '' and citizenid or nil
end

local function safeContext(input)
    input = type(input) == 'table' and input or {}
    local output = {}
    for key, value in pairs(input) do
        if CONTEXT_FIELDS[key] then
            if type(value) == 'string' then output[key] = value:gsub('%c', ' '):sub(1, 128)
            elseif type(value) == 'boolean' then output[key] = value
            elseif type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge then
                output[key] = math.max(-4294967295, math.min(4294967295, value))
            end
        end
    end
    return output
end

local function capabilityDefinition(capability)
    local definitions = type(config().capabilities) == 'table' and config().capabilities or {}
    return type(definitions[capability]) == 'table' and definitions[capability] or nil
end

local function audit(action, lease, reason)
    if config().audit ~= true or type(lease) ~= 'table' then return end
    reason = reason or lease.reason
    if MZBan.Correlation and type(MZBan.Correlation.Record) == 'function' then
        MZBan.Correlation.Record(lease.source, 'security_lease.' .. action, {
            leaseId = lease.id, capability = lease.capability, resource = lease.issuer,
            remainingUses = lease.remainingUses, reason = reason
        })
    end
    pcall(function()
        if not MZBan.DB or MZBan.DB.IsReady() ~= true then return end
        MZBan.DB.Audit('security.lease.' .. action, {
            target_source = lease.source,
            target_name = GetPlayerName(lease.source),
            meta = {
                lease_id = lease.id, capability = lease.capability, issuer = lease.issuer,
                remaining_uses = lease.remainingUses, reason = reason,
                correlation_id = lease.correlationId
            }
        })
    end)
end

local function auditDenied(sourceId, capability, issuer, reason)
    if config().audit ~= true then return end
    sourceId = tonumber(sourceId)
    issuer = tostring(issuer or 'unknown'):gsub('%c', ''):sub(1, 64)
    capability = tostring(capability or 'unknown'):gsub('%c', ''):sub(1, 64)
    reason = tostring(reason or 'denied'):gsub('%c', ''):sub(1, 64)
    local key = table.concat({ issuer, capability, reason }, ':')
    local currentMs = nowMs()
    local cooldown = math.max(1000, tonumber(Config.Risk and Config.Risk.ExportLimits
        and Config.Risk.ExportLimits.DeniedAuditCooldownMs) or 10000)
    if currentMs - (deniedAuditAt[key] or -cooldown) < cooldown then return end
    deniedAuditAt[key] = currentMs
    if sourceId and MZBan.Correlation then
        MZBan.Correlation.Record(sourceId, 'security_lease.denied', {
            capability = capability, resource = issuer, reason = reason
        })
    end
    pcall(function()
        if not MZBan.DB or MZBan.DB.IsReady() ~= true then return end
        MZBan.DB.Audit('security.lease.denied', {
            target_source = sourceId,
            target_name = sourceId and GetPlayerName(sourceId) or nil,
            meta = { capability = capability, issuer = issuer, reason = reason }
        })
    end)
end

local function prune(sourceId, currentMs)
    local leases = leasesByPlayer[sourceId]
    if not leases then return end
    for index = #leases, 1, -1 do
        local lease = leases[index]
        if lease.expiresAtMs <= currentMs or lease.remainingUses <= 0 then
            audit(lease.remainingUses <= 0 and 'consumed' or 'expired', lease)
            table.remove(leases, index)
        end
    end
    if #leases == 0 then leasesByPlayer[sourceId] = nil end
end

local function contextMatches(expected, actual)
    actual = safeContext(actual)
    for key, value in pairs(expected or {}) do
        local candidate = actual[key]
        if candidate == nil then return false end
        if key == 'x' or key == 'y' or key == 'z' then
            if math.abs((tonumber(candidate) or 0) - (tonumber(value) or 0)) > 8.0 then return false end
        elseif tonumber(value) and tonumber(candidate) then
            if tonumber(value) ~= tonumber(candidate) then return false end
        elseif tostring(value) ~= tostring(candidate) then
            return false
        end
    end
    return true
end

function MZBan.SecurityLeases.Issue(sourceId, capability, durationMs, context, issuer)
    if config().enabled ~= true then return nil, 'leases_disabled' end
    sourceId = normalizeSource(sourceId)
    capability = token(capability, 64)
    issuer = token(issuer, 64)
    local definition = capability and capabilityDefinition(capability) or nil
    if not sourceId or not definition or not issuer then return nil, 'invalid_request' end
    if type(definition.issuers) ~= 'table' or definition.issuers[issuer] ~= true then
        return nil, 'issuer_not_allowed'
    end

    local defaultTtl = tonumber(definition.ttlMs) or tonumber(config().defaultTtlMs) or 8000
    local duration = math.floor(tonumber(durationMs) or defaultTtl)
    local maximum = math.min(
        math.max(250, tonumber(config().maxTtlMs) or 30000),
        math.max(250, tonumber(definition.maxTtlMs) or tonumber(config().maxTtlMs) or 30000)
    )
    if duration < 250 or duration > maximum then return nil, 'invalid_duration' end

    local rawContext = type(context) == 'table' and context or {}
    local requestedUses = tonumber(rawContext.quantity)
    local storedContext = safeContext(rawContext)
    storedContext.quantity = nil
    -- Metadados de auditoria nao fazem parte do contrato de correspondencia.
    -- Assim, o detector nao precisa conhecer a descricao interna do emissor.
    local issueReason = storedContext.reason
    local correlationId = storedContext.correlationId
    storedContext.reason = nil
    storedContext.correlationId = nil
    local currentMs = nowMs()
    prune(sourceId, currentMs)
    local leases = leasesByPlayer[sourceId] or {}
    leasesByPlayer[sourceId] = leases
    local maxActive = math.max(1, math.floor(tonumber(config().maxActivePerPlayer) or 32))
    if #leases >= maxActive then return nil, 'too_many_active_leases' end

    sequence = sequence + 1
    local lease = {
        id = ('MZLEASE-%d-%d-%06d'):format(sourceId, currentMs, sequence % 1000000),
        source = sourceId,
        capability = capability,
        issuer = issuer,
        issuedAtMs = currentMs,
        expiresAtMs = currentMs + duration,
        remainingUses = math.max(1, math.min(
            math.floor(tonumber(definition.uses) or 1),
            requestedUses and math.floor(requestedUses) or math.floor(tonumber(definition.uses) or 1)
        )),
        context = storedContext,
        reason = issueReason,
        correlationId = correlationId,
        citizenid = currentIdentity(sourceId)
    }
    leases[#leases + 1] = lease
    audit('issued', lease)
    return lease.id, nil
end

local function find(sourceId, capability, context, consume)
    sourceId = normalizeSource(sourceId)
    capability = token(capability, 64)
    if not sourceId or not capability then return false, nil, 'invalid_request' end
    prune(sourceId, nowMs())
    local leases = leasesByPlayer[sourceId] or {}
    local resolvedIdentity, identityChecked
    for index = #leases, 1, -1 do
        local lease = leases[index]
        if lease.citizenid ~= nil and identityChecked ~= true then
            resolvedIdentity, identityChecked = currentIdentity(sourceId), true
        end
        local identityValid = lease.citizenid == nil or resolvedIdentity == lease.citizenid
        if not identityValid then
            audit('revoked', lease, 'identity_changed')
            table.remove(leases, index)
        elseif lease.capability == capability and contextMatches(lease.context, context) then
            if consume == true then
                lease.remainingUses = lease.remainingUses - 1
                audit('used', lease)
                if lease.remainingUses <= 0 then table.remove(leases, index) end
                if #leases == 0 then leasesByPlayer[sourceId] = nil end
            end
            return true, {
                id = lease.id, capability = lease.capability, issuer = lease.issuer,
                expiresAtMs = lease.expiresAtMs, remainingUses = lease.remainingUses
            }
        end
    end
    return false, nil, 'lease_not_found'
end

function MZBan.SecurityLeases.Check(sourceId, capability, context)
    return find(sourceId, capability, context, false)
end

function MZBan.SecurityLeases.Consume(sourceId, capability, context)
    return find(sourceId, capability, context, true)
end

function MZBan.SecurityLeases.RevokePlayer(sourceId, reason)
    sourceId = tonumber(sourceId)
    if not sourceId then return 0 end
    local leases = leasesByPlayer[sourceId] or {}
    for _, lease in ipairs(leases) do audit('revoked', lease, reason or 'player_cleanup') end
    leasesByPlayer[sourceId] = nil
    return #leases
end

function MZBan.SecurityLeases.RevokeResource(resource, reason)
    resource = token(resource, 64)
    if not resource then return 0 end
    local removed = 0
    for sourceId, leases in pairs(leasesByPlayer) do
        for index = #leases, 1, -1 do
            if leases[index].issuer == resource then
                audit('revoked', leases[index], reason or 'resource_stop')
                table.remove(leases, index)
                removed = removed + 1
            end
        end
        if #leases == 0 then leasesByPlayer[sourceId] = nil end
    end
    return removed
end

function MZBan.SecurityLeases.Status()
    local players, active = 0, 0
    local currentMs = nowMs()
    for sourceId, leases in pairs(leasesByPlayer) do
        prune(sourceId, currentMs)
        if leasesByPlayer[sourceId] then players, active = players + 1, active + #leases end
    end
    return { enabled = config().enabled == true, players = players, active = active }
end

local function exportAllowed(operation, resource)
    local access = Config.Risk and type(Config.Risk.ExportAccess) == 'table' and Config.Risk.ExportAccess or {}
    return type(resource) == 'string' and type(access[operation]) == 'table' and access[operation][resource] == true
end

exports('RegisterSecurityLease', function(sourceId, capability, durationMs, context)
    local issuer = GetInvokingResource()
    if not exportAllowed('RegisterSecurityLease', issuer) then
        auditDenied(sourceId, capability, issuer, 'untrusted_resource')
        return nil, 'untrusted_resource'
    end
    local id, reason = MZBan.SecurityLeases.Issue(sourceId, capability, durationMs, context, issuer)
    if not id then auditDenied(sourceId, capability, issuer, reason) end
    return id, reason
end)

AddEventHandler('playerDropped', function() MZBan.SecurityLeases.RevokePlayer(source, 'player_dropped') end)
AddEventHandler('onResourceStop', function(resource) MZBan.SecurityLeases.RevokeResource(resource, 'resource_stopped') end)

CreateThread(function()
    while true do
        Wait(math.max(1000, math.floor(tonumber(config().cleanupIntervalMs) or 5000)))
        local currentMs = nowMs()
        for sourceId in pairs(leasesByPlayer) do prune(sourceId, currentMs) end
    end
end)
