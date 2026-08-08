MZBan = MZBan or {}
MZBan.SecurityLifecycle = MZBan.SecurityLifecycle or {}

local sessionsByPlayer = {}
local deniedAuditAt = {}
local sequence = 0

local CONTEXT_FIELDS = {
    model = true, bucket = true, x = true, y = true, z = true,
    returnX = true, returnY = true, returnZ = true, models = true,
    reason = true, correlationId = true, houseCode = true
}

local function config()
    return type(Config.SecurityLifecycle) == 'table' and Config.SecurityLifecycle or {}
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

local function normalizeHash(value)
    if type(value) == 'string' and not tonumber(value) then
        local ok, result = pcall(joaat, value)
        value = ok and result or nil
    end
    value = tonumber(value)
    if not value then return nil end
    value = math.floor(value)
    if value < 0 then value = value + 4294967296 end
    return value >= 0 and value <= 4294967295 and value or nil
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
            if key == 'models' and type(value) == 'table' then
                local models = {}
                for _, candidate in pairs(value) do
                    local hash = normalizeHash(candidate)
                    if hash then models[#models + 1] = hash end
                    if #models >= 8 then break end
                end
                if #models > 0 then output.models = models end
            elseif key == 'model' then
                output.model = normalizeHash(value)
            elseif type(value) == 'string' then
                output[key] = value:gsub('%c', ' '):sub(1, 96)
            elseif type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge then
                output[key] = math.max(-4294967295, math.min(4294967295, value))
            end
        end
    end
    return output
end

local function definition(kind)
    local types = type(config().types) == 'table' and config().types or {}
    return type(types[kind]) == 'table' and types[kind] or nil
end

local function audit(action, session, reason)
    if type(session) ~= 'table' then return end
    reason = tostring(reason or session.reason or action):gsub('%c', ''):sub(1, 96)
    if MZBan.Correlation then
        MZBan.Correlation.Record(session.source, 'security_lifecycle.' .. action, {
            sessionId = session.id, lifecycle = session.kind, resource = session.issuer,
            reason = reason, confirmed = session.confirmed == true
        })
    end
    pcall(function()
        if not MZBan.DB or MZBan.DB.IsReady() ~= true then return end
        MZBan.DB.Audit('security.lifecycle.' .. action, {
            target_source = session.source,
            target_name = GetPlayerName(session.source),
            meta = {
                session_id = session.id, lifecycle = session.kind,
                issuer = session.issuer, reason = reason
            }
        })
    end)
end

local function auditDenied(sourceId, kind, issuer, reason)
    issuer = tostring(issuer or 'unknown'):gsub('%c', ''):sub(1, 64)
    kind = tostring(kind or 'unknown'):gsub('%c', ''):sub(1, 64)
    reason = tostring(reason or 'denied'):gsub('%c', ''):sub(1, 64)
    local key = table.concat({ issuer, kind, reason }, ':')
    local currentMs = nowMs()
    if currentMs - (deniedAuditAt[key] or -10000) < 10000 then return end
    deniedAuditAt[key] = currentMs
    if sourceId and MZBan.Correlation then
        MZBan.Correlation.Record(sourceId, 'security_lifecycle.denied', {
            lifecycle = kind, resource = issuer, reason = reason
        })
    end
end

local function prune(sourceId, currentMs)
    local sessions = sessionsByPlayer[sourceId]
    if not sessions then return end
    for index = #sessions, 1, -1 do
        local session = sessions[index]
        if session.expiresAtMs <= currentMs then
            audit('expired', session)
            table.remove(sessions, index)
        end
    end
    if #sessions == 0 then sessionsByPlayer[sourceId] = nil end
end

local function serverContext(sourceId)
    local context = { bucket = tonumber(GetPlayerRoutingBucket(sourceId)) or 0 }
    local ped = GetPlayerPed(sourceId)
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        context.model = normalizeHash(GetEntityModel(ped))
        local coords = GetEntityCoords(ped)
        if coords then context.x, context.y, context.z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z) end
    end
    return context
end

local function coordinatesMatch(expected, actual, tolerance)
    if expected.x == nil and expected.y == nil and expected.z == nil then return true end
    if actual.x == nil or actual.y == nil or actual.z == nil then return false end
    local x = (tonumber(actual.x) or 0) - (tonumber(expected.x) or 0)
    local y = (tonumber(actual.y) or 0) - (tonumber(expected.y) or 0)
    local z = (tonumber(actual.z) or 0) - (tonumber(expected.z) or 0)
    return math.sqrt(x * x + y * y + z * z) <= tolerance
end

local function returnCoordinatesMatch(expected, actual, tolerance)
    if expected.returnX == nil and expected.returnY == nil and expected.returnZ == nil then return false end
    return coordinatesMatch({ x = expected.returnX, y = expected.returnY, z = expected.returnZ }, actual, tolerance)
end

local function modelMatches(expected, actualModel)
    local actual = normalizeHash(actualModel)
    if expected.model ~= nil and actual == normalizeHash(expected.model) then return true end
    if type(expected.models) == 'table' then
        for _, model in ipairs(expected.models) do if actual == normalizeHash(model) then return true end end
        return false
    end
    return expected.model == nil
end

local function contextMatches(session, transition, actual, confirmation)
    actual = safeContext(actual)
    local expected = session.context or {}
    if expected.bucket ~= nil and tonumber(actual.bucket) ~= tonumber(expected.bucket) then return false, 'bucket_mismatch' end
    if transition == 'model' or confirmation == true then
        if not modelMatches(expected, actual.model) then
            return false, 'model_mismatch'
        end
    end
    if transition == 'movement' or confirmation == true then
        local tolerance = confirmation == true and (tonumber(config().confirmationTolerance) or 25.0)
            or (tonumber(config().coordinateTolerance) or 15.0)
        tolerance = math.max(1.0, tolerance)
        if not coordinatesMatch(expected, actual, tolerance)
            and not returnCoordinatesMatch(expected, actual, tolerance) then return false, 'coordinates_mismatch' end
    end
    return true
end

function MZBan.SecurityLifecycle.Begin(sourceId, kind, durationMs, context, issuer)
    if config().enabled ~= true then return nil, 'lifecycle_disabled' end
    sourceId = normalizeSource(sourceId)
    kind = token(kind, 64)
    issuer = token(issuer, 64)
    local rule = kind and definition(kind) or nil
    if not sourceId or not rule or not issuer then return nil, 'invalid_request' end
    if type(rule.issuers) ~= 'table' or rule.issuers[issuer] ~= true then return nil, 'issuer_not_allowed' end

    local maximum = math.max(1000, math.floor(tonumber(config().maxTtlMs) or 60000))
    local defaultTtl = math.max(1000, math.floor(tonumber(rule.ttlMs) or 20000))
    local duration = math.floor(tonumber(durationMs) or defaultTtl)
    if duration < 1000 or duration > math.min(maximum, defaultTtl) then return nil, 'invalid_duration' end

    local safe = safeContext(context)
    local reason, correlationId = safe.reason, safe.correlationId
    safe.reason, safe.correlationId = nil, nil
    local currentMs = nowMs()
    prune(sourceId, currentMs)
    local sessions = sessionsByPlayer[sourceId] or {}
    sessionsByPlayer[sourceId] = sessions
    for index = #sessions, 1, -1 do
        if sessions[index].kind == kind and sessions[index].issuer == issuer then
            audit('replaced', sessions[index], 'new_session')
            table.remove(sessions, index)
        end
    end
    if #sessions >= math.max(1, math.floor(tonumber(config().maxActivePerPlayer) or 4)) then
        return nil, 'too_many_active_sessions'
    end

    sequence = sequence + 1
    local session = {
        id = ('mzlife-%d-%d-%06d'):format(sourceId, currentMs, sequence % 1000000),
        source = sourceId, citizenid = currentIdentity(sourceId), kind = kind, issuer = issuer,
        startedAtMs = currentMs, expiresAtMs = currentMs + duration,
        hardExpiresAtMs = currentMs + duration, context = safe,
        reason = reason, correlationId = correlationId,
        transitions = type(rule.transitions) == 'table' and rule.transitions or {},
        confirmed = false, diverged = false
    }
    sessions[#sessions + 1] = session
    audit('started', session)
    return session.id, nil
end

function MZBan.SecurityLifecycle.IsAllowed(sourceId, transition, actual)
    sourceId = normalizeSource(sourceId)
    transition = token(transition, 48)
    if not sourceId or not transition then return false, nil, 'invalid_request' end
    local currentMs = nowMs()
    prune(sourceId, currentMs)
    local sessions = sessionsByPlayer[sourceId] or {}
    local identity, checked
    for index = #sessions, 1, -1 do
        local session = sessions[index]
        if session.citizenid and not checked then identity, checked = currentIdentity(sourceId), true end
        if session.citizenid and identity ~= session.citizenid then
            audit('revoked', session, 'identity_changed')
            table.remove(sessions, index)
        elseif session.diverged ~= true and session.transitions[transition] == true then
            local matches = contextMatches(session, transition, actual or serverContext(sourceId), false)
            if matches then
                return true, {
                    id = session.id, kind = session.kind, issuer = session.issuer,
                    expiresAtMs = session.expiresAtMs, confirmed = session.confirmed == true
                }
            end
        end
    end
    if #sessions == 0 then sessionsByPlayer[sourceId] = nil end
    return false, nil, 'lifecycle_not_found'
end

function MZBan.SecurityLifecycle.Confirm(sourceId, sessionId)
    sourceId = normalizeSource(sourceId)
    sessionId = token(sessionId, 96)
    if not sourceId or not sessionId then return false, 'invalid_request' end
    prune(sourceId, nowMs())
    local sessions = sessionsByPlayer[sourceId] or {}
    for _, session in ipairs(sessions) do
        if session.id == sessionId then
            if session.confirmed == true then return true, 'already_confirmed' end
            local actual = serverContext(sourceId)
            if actual.model == nil or actual.x == nil then return false, 'player_state_not_ready' end
            local matches, reason = contextMatches(session, 'movement', actual, true)
            if not matches then
                session.diverged = true
                audit('diverged', session, reason)
                return false, reason
            end
            session.confirmed = true
            session.confirmedAtMs = nowMs()
            session.expiresAtMs = math.min(session.hardExpiresAtMs,
                session.confirmedAtMs + math.max(1000, math.floor(tonumber(config().postConfirmGraceMs) or 5000)))
            audit('confirmed', session)
            return true, nil
        end
    end
    return false, 'session_not_found'
end

function MZBan.SecurityLifecycle.End(sourceId, sessionId, issuer, reason)
    sourceId = normalizeSource(sourceId)
    sessionId = token(sessionId, 96)
    issuer = token(issuer, 64)
    if not sourceId or not sessionId or not issuer then return false, 'invalid_request' end
    local sessions = sessionsByPlayer[sourceId] or {}
    for index = #sessions, 1, -1 do
        local session = sessions[index]
        local rule = definition(session.kind) or {}
        local canEnd = session.issuer == issuer or (type(rule.enders) == 'table' and rule.enders[issuer] == true)
        if session.id == sessionId and canEnd then
            audit('ended', session, reason or 'issuer_completed')
            table.remove(sessions, index)
            if #sessions == 0 then sessionsByPlayer[sourceId] = nil end
            return true, nil
        end
    end
    return false, 'session_not_found'
end

function MZBan.SecurityLifecycle.Check(sourceId, sessionId, expectedKind)
    sourceId = normalizeSource(sourceId)
    sessionId = token(sessionId, 96)
    expectedKind = expectedKind and token(expectedKind, 64) or nil
    if not sourceId or not sessionId then return false, nil, 'invalid_request' end
    prune(sourceId, nowMs())
    local sessions = sessionsByPlayer[sourceId] or {}
    for index = #sessions, 1, -1 do
        local session = sessions[index]
        if session.id == sessionId and session.diverged ~= true
            and (not expectedKind or session.kind == expectedKind) then
            if session.citizenid and currentIdentity(sourceId) ~= session.citizenid then
                audit('revoked', session, 'identity_changed')
                table.remove(sessions, index)
                if #sessions == 0 then sessionsByPlayer[sourceId] = nil end
                return false, nil, 'identity_changed'
            end
            return true, { id = session.id, kind = session.kind, issuer = session.issuer,
                expiresAtMs = session.expiresAtMs, confirmed = session.confirmed == true }, nil
        end
    end
    return false, nil, 'session_not_found'
end

function MZBan.SecurityLifecycle.RevokePlayer(sourceId, reason)
    sourceId = tonumber(sourceId)
    if not sourceId then return 0 end
    local sessions = sessionsByPlayer[sourceId] or {}
    for _, session in ipairs(sessions) do audit('revoked', session, reason or 'player_cleanup') end
    sessionsByPlayer[sourceId] = nil
    return #sessions
end

function MZBan.SecurityLifecycle.RevokeResource(resource, reason)
    resource = token(resource, 64)
    if not resource then return 0 end
    local removed = 0
    for sourceId, sessions in pairs(sessionsByPlayer) do
        for index = #sessions, 1, -1 do
            if sessions[index].issuer == resource then
                audit('revoked', sessions[index], reason or 'resource_stopped')
                table.remove(sessions, index)
                removed = removed + 1
            end
        end
        if #sessions == 0 then sessionsByPlayer[sourceId] = nil end
    end
    return removed
end

function MZBan.SecurityLifecycle.Status()
    local players, active, confirmed, diverged = 0, 0, 0, 0
    local currentMs = nowMs()
    for sourceId, sessions in pairs(sessionsByPlayer) do
        prune(sourceId, currentMs)
        if sessionsByPlayer[sourceId] then
            players, active = players + 1, active + #sessions
            for _, session in ipairs(sessions) do
                if session.confirmed then confirmed = confirmed + 1 end
                if session.diverged then diverged = diverged + 1 end
            end
        end
    end
    return { enabled = config().enabled == true, players = players, active = active,
        confirmed = confirmed, diverged = diverged }
end

local function exportAllowed(operation, resource)
    local access = Config.Risk and type(Config.Risk.ExportAccess) == 'table' and Config.Risk.ExportAccess or {}
    return type(resource) == 'string' and type(access[operation]) == 'table' and access[operation][resource] == true
end

exports('BeginSecurityLifecycle', function(sourceId, kind, durationMs, context)
    local issuer = GetInvokingResource()
    if not exportAllowed('BeginSecurityLifecycle', issuer) then
        auditDenied(sourceId, kind, issuer, 'untrusted_resource')
        return nil, 'untrusted_resource'
    end
    local id, reason = MZBan.SecurityLifecycle.Begin(sourceId, kind, durationMs, context, issuer)
    if not id then auditDenied(sourceId, kind, issuer, reason) end
    return id, reason
end)

exports('EndSecurityLifecycle', function(sourceId, sessionId, reason)
    local issuer = GetInvokingResource()
    if not exportAllowed('EndSecurityLifecycle', issuer) then return false, 'untrusted_resource' end
    return MZBan.SecurityLifecycle.End(sourceId, sessionId, issuer, reason)
end)

exports('CheckSecurityLifecycle', function(sourceId, sessionId, expectedKind)
    local issuer = GetInvokingResource()
    if not exportAllowed('CheckSecurityLifecycle', issuer) then return false, nil, 'untrusted_resource' end
    return MZBan.SecurityLifecycle.Check(sourceId, sessionId, expectedKind)
end)

RegisterNetEvent('mz_banguard:server:lifecycleReady', function(sessionId)
    MZBan.SecurityLifecycle.Confirm(source, sessionId)
end)

AddEventHandler('respawnPlayerPedEvent', function(player)
    local sourceId = tonumber(player)
    if sourceId and GetPlayerName(sourceId) then
        MZBan.SecurityLifecycle.Begin(sourceId, 'respawn', nil, {}, 'mz_banguard')
    end
end)

AddEventHandler('playerDropped', function() MZBan.SecurityLifecycle.RevokePlayer(source, 'player_dropped') end)
AddEventHandler('onResourceStop', function(resource) MZBan.SecurityLifecycle.RevokeResource(resource, 'resource_stopped') end)

CreateThread(function()
    while true do
        Wait(math.max(1000, math.floor(tonumber(config().cleanupIntervalMs) or 5000)))
        local currentMs = nowMs()
        for sourceId in pairs(sessionsByPlayer) do prune(sourceId, currentMs) end
    end
end)
