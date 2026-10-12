MZBan = MZBan or {}
MZBan.Lab = MZBan.Lab or {}

local subjects = {}

local function safeString(value, maximum)
    value = tostring(value or ''):gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return value:sub(1, math.max(1, tonumber(maximum) or 128))
end

local function resolveIdentity(sourceId)
    sourceId = tonumber(sourceId)
    local resource = tostring(Config.Integration and Config.Integration.CoreResource or 'mz_core')
    if not sourceId or sourceId <= 0 or GetResourceState(resource) ~= 'started' then return nil end
    local ok, identity = pcall(function() return exports[resource]:ResolvePlayerIdentity(sourceId) end)
    if not ok or type(identity) ~= 'table' or identity.ok ~= true then return nil end
    return {
        source = math.floor(sourceId),
        citizenid = safeString(identity.citizenid, 64),
        accountId = tonumber(identity.accountId),
        sessionId = tonumber(identity.sessionId),
        playerName = safeString(GetPlayerName(sourceId), 64)
    }
end

local function subjectKey(subject)
    if tonumber(subject.sessionId) then return 'session:' .. tostring(math.floor(tonumber(subject.sessionId))) end
    if safeString(subject.citizenid, 64) ~= '' then return 'citizen:' .. safeString(subject.citizenid, 64) end
    if tonumber(subject.accountId) then return 'account:' .. tostring(math.floor(tonumber(subject.accountId))) end
    return nil
end

local function expired(subject, currentTime)
    return tonumber(subject and subject.expiresAt) and tonumber(subject.expiresAt) <= currentTime
end

local function audit(action, actorSource, subject, reason)
    if MZBan.DB and type(MZBan.DB.Audit) == 'function' then
        pcall(MZBan.DB.Audit, action, {
            actor_source = tonumber(actorSource),
            actor_name = actorSource and MZBan.SafePlayerName(actorSource) or 'system',
            target_source = subject and subject.source or nil,
            target_name = subject and subject.playerName or nil,
            meta = {
                citizenid = subject and subject.citizenid or nil,
                account_id = subject and subject.accountId or nil,
                session_id = subject and subject.sessionId or nil,
                expires_at = subject and subject.expiresAt or nil,
                reason = safeString(reason, 256)
            }
        })
    end
end

function MZBan.Lab.Set(actorSource, targetSource, enabled, durationSeconds, reason)
    local identity = resolveIdentity(targetSource)
    if not identity then return nil, 'identity_unavailable' end
    local key = subjectKey(identity)
    if not key then return nil, 'identity_unavailable' end
    local now = os.time()
    local subject = subjects[key] or identity
    subject.source = identity.source
    subject.playerName = identity.playerName
    subject.citizenid = identity.citizenid
    subject.accountId = identity.accountId
    subject.sessionId = identity.sessionId
    subject.enabled = enabled == true
    subject.startedAt = subject.enabled and now or (subject.startedAt or now)
    subject.expiresAt = subject.enabled and tonumber(durationSeconds) and (now + math.max(60, math.floor(tonumber(durationSeconds)))) or nil
    subject.reason = safeString(reason, 256)
    subject.authorizedBy = tonumber(actorSource) and MZBan.SafePlayerName(actorSource) or 'system'
    subject.updatedAt = now
    subjects[key] = subject
    if MZBan.DB and type(MZBan.DB.SaveLabSubject) == 'function' then MZBan.DB.SaveLabSubject(subject) end
    audit(subject.enabled and 'security.lab.enabled' or 'security.lab.disabled', actorSource, subject, reason)
    return subject
end

function MZBan.Lab.IsSubject(sourceId, identity)
    identity = type(identity) == 'table' and identity or resolveIdentity(sourceId)
    if not identity then return false end
    local keys = {
        identity.sessionId and ('session:' .. tostring(math.floor(tonumber(identity.sessionId)))) or nil,
        safeString(identity.citizenid, 64) ~= '' and ('citizen:' .. safeString(identity.citizenid, 64)) or nil,
        identity.accountId and ('account:' .. tostring(math.floor(tonumber(identity.accountId)))) or nil
    }
    local now = os.time()
    for _, key in ipairs(keys) do
        local subject = key and subjects[key] or nil
        if subject and subject.enabled == true then
            if expired(subject, now) then
                subject.enabled = false
                subject.updatedAt = now
                if MZBan.DB and type(MZBan.DB.SaveLabSubject) == 'function' then MZBan.DB.SaveLabSubject(subject) end
                audit('security.lab.expired', nil, subject, 'expired')
            else
                return true, subject
            end
        end
    end
    return false
end

function MZBan.Lab.Hydrate(rows)
    for _, row in ipairs(type(rows) == 'table' and rows or {}) do
        local subject = {
            source = nil,
            citizenid = safeString(row.citizenid, 64),
            accountId = tonumber(row.account_id),
            sessionId = tonumber(row.session_id),
            enabled = tonumber(row.enabled) == 1 or row.enabled == true,
            startedAt = tonumber(row.started_at),
            expiresAt = tonumber(row.expires_at),
            reason = safeString(row.reason, 256),
            authorizedBy = safeString(row.authorized_by, 128),
            updatedAt = tonumber(row.updated_at)
        }
        local key = subjectKey(subject)
        if key then subjects[key] = subject end
    end
end

function MZBan.Lab.Status()
    local active = 0
    for _, subject in pairs(subjects) do
        if subject.enabled == true and not expired(subject, os.time()) then active = active + 1 end
    end
    return { active = active }
end

