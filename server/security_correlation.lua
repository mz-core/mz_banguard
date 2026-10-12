MZBan = MZBan or {}
MZBan.Correlation = MZBan.Correlation or {}

local timelines = {}
local recentCrashes = {}
local sequence = 0
local persistEntry

local function config()
    return type(Config.SecurityCorrelation) == 'table' and Config.SecurityCorrelation or {}
end

local function nowMs()
    return math.max(0, math.floor(tonumber(GetGameTimer()) or 0))
end

local function normalizeSource(value)
    value = tonumber(value)
    if not value or value <= 0 then return nil end
    return math.floor(value)
end

local function safeString(value, maximum)
    value = tostring(value or ''):gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return value:sub(1, math.max(1, tonumber(maximum) or 128))
end

local function safeData(input)
    input = type(input) == 'table' and input or {}
    local output, count = {}, 0
    local maximum = math.max(1, math.floor(tonumber(config().maxDataKeys) or 16))
    for key, value in pairs(input) do
        if count >= maximum then break end
        local safeKey = safeString(key, 48)
        if safeKey ~= '' then
            if type(value) == 'string' then
                output[safeKey] = safeString(value, config().maxString)
                count = count + 1
            elseif type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge then
                output[safeKey] = math.max(-4294967295, math.min(4294967295, value))
                count = count + 1
            elseif type(value) == 'boolean' then
                output[safeKey] = value
                count = count + 1
            end
        end
    end
    return output
end

local function prune(sourceId, currentMs)
    local entries = timelines[sourceId]
    if not entries then return end
    local lab = MZBan.Lab and type(MZBan.Lab.IsSubject) == 'function' and MZBan.Lab.IsSubject(sourceId) == true
    local ttl = lab and config().labTtlMs or config().ttlMs
    ttl = math.max(10000, math.floor(tonumber(ttl) or 30000))
    while entries[1] and currentMs - entries[1].atMs > ttl do table.remove(entries, 1) end
    if #entries == 0 then timelines[sourceId] = nil end
end

function MZBan.Correlation.Record(sourceId, kind, data)
    if config().enabled ~= true then return nil end
    sourceId = normalizeSource(sourceId)
    kind = safeString(kind, 64)
    if not sourceId or kind == '' then return nil end

    local currentMs = nowMs()
    prune(sourceId, currentMs)
    sequence = sequence + 1
    local entry = {
        id = ('MZCOR-%d-%d-%06d'):format(sourceId, currentMs, sequence % 1000000),
        at = os.time(),
        atMs = currentMs,
        kind = kind,
        data = safeData(data)
    }
    local entries = timelines[sourceId] or {}
    timelines[sourceId] = entries
    entries[#entries + 1] = entry
    if persistEntry then persistEntry(sourceId, entry) end
    local lab = MZBan.Lab and type(MZBan.Lab.IsSubject) == 'function' and MZBan.Lab.IsSubject(sourceId) == true
    local maximum = lab and config().labMaxEntriesPerPlayer or config().maxEntriesPerPlayer
    maximum = math.max(4, math.min(128, math.floor(tonumber(maximum) or 32)))
    while #entries > maximum do table.remove(entries, 1) end
    return entry.id
end

function MZBan.Correlation.Snapshot(sourceId, limit)
    sourceId = normalizeSource(sourceId)
    if not sourceId then return {} end
    prune(sourceId, nowMs())
    local entries = timelines[sourceId] or {}
    limit = math.max(1, math.min(128, math.floor(tonumber(limit) or tonumber(config().snapshotEntries) or 16)))
    local output = {}
    local first = math.max(1, #entries - limit + 1)
    for index = first, #entries do
        local entry = entries[index]
        local data = {}
        for key, value in pairs(entry.data or {}) do data[key] = value end
        output[#output + 1] = { id = entry.id, at = entry.at, kind = entry.kind, data = data }
    end
    return output
end

function MZBan.Correlation.Clear(sourceId)
    sourceId = normalizeSource(sourceId)
    if sourceId then timelines[sourceId] = nil end
end

function MZBan.Correlation.Status()
    local players, entries = 0, 0
    local currentMs = nowMs()
    for sourceId, timeline in pairs(timelines) do
        prune(sourceId, currentMs)
        if timelines[sourceId] then
            players = players + 1
            entries = entries + #timeline
        end
    end
    return { enabled = config().enabled == true, players = players, entries = entries }
end

local function classifyDropReason(reason)
    local value = safeString(reason, 512):lower()
    if value:find('ban', 1, true) then return 'ban' end
    if value:find('kick', 1, true) then return 'kick' end
    if value:find('resource stop', 1, true) or value:find('server shutting down', 1, true) then return 'resource_stop' end
    if value:find('timed out', 1, true) or value:find('timeout', 1, true) then return 'timeout' end
    local crashPatterns = {
        'game crashed', 'rage error', 'crash', 'gta5%.exe', 'five[mM]%.exe',
        'exception code', 'offset 0x', 'executable:'
    }
    for _, pattern in ipairs(crashPatterns) do
        if value:find(pattern) then return 'crash' end
    end
    return 'disconnect'
end

local function coreIdentity(sourceId)
    local resource = tostring(Config.Integration and Config.Integration.CoreResource or 'mz_core')
    if GetResourceState(resource) ~= 'started' then return {} end
    local ok, identity = pcall(function() return exports[resource]:ResolvePlayerIdentity(sourceId) end)
    return ok and type(identity) == 'table' and identity or {}
end

local function incidentBacked(kind)
    if config().persistIncidentBacked ~= false then return false end
    kind = tostring(kind or '')
    return kind:sub(1, 13) == 'server_event.'
        or kind:sub(1, 17) == 'client_telemetry.'
        or kind == 'weapon.damage_suspect'
        or kind == 'entity.suspicious'
        or kind == 'server_state.teleport'
        or kind == 'aim.qualified_window'
end

persistEntry = function(sourceId, entry)
    if not MZBan.DB or type(MZBan.DB.SaveSecuritySignal) ~= 'function' then return end
    if incidentBacked(entry.kind) then return end
    if type(MZBan.DB.IsReady) == 'function' then
        local readyOk, ready = pcall(MZBan.DB.IsReady)
        if not readyOk or ready ~= true then return end
    end
    local identity = coreIdentity(sourceId)
    local ok, result = pcall(MZBan.DB.SaveSecuritySignal, {
        signal_id = entry.id,
        code = entry.kind,
        origin = 'correlation',
        confidence = 'contextual',
        culpability = 'contextual',
        citizenid = identity.citizenid,
        account_id = identity.accountId,
        session_id = identity.sessionId,
        source_id = sourceId,
        occurred_at = entry.at,
        evidence = entry.data
    })
    if not ok or result == nil or result == false then
        MZBan.AuditPrint('security.correlation.persistence_failed', entry.id, tostring(result))
    end
end

local function lastPosition(sourceId)
    local okPed, ped = pcall(GetPlayerPed, sourceId)
    if not okPed or not ped or ped == 0 then return nil, tonumber(GetPlayerRoutingBucket(sourceId)) or 0 end
    local okExists, exists = pcall(DoesEntityExist, ped)
    if not okExists or exists ~= true then return nil, tonumber(GetPlayerRoutingBucket(sourceId)) or 0 end
    local okCoords, coords = pcall(GetEntityCoords, ped)
    if not okCoords or not coords then return nil, tonumber(GetPlayerRoutingBucket(sourceId)) or 0 end
    return { x = tonumber(coords.x) or 0, y = tonumber(coords.y) or 0, z = tonumber(coords.z) or 0 },
        tonumber(GetPlayerRoutingBucket(sourceId)) or 0
end

local function kindsFor(timeline)
    local out = {}
    for _, entry in ipairs(timeline or {}) do out[tostring(entry.kind or '')] = true end
    return out
end

local function commonSignals(crashes)
    local counts, output = {}, {}
    for _, crash in ipairs(crashes) do
        for kind in pairs(kindsFor(crash.timeline)) do counts[kind] = (counts[kind] or 0) + 1 end
    end
    for kind, count in pairs(counts) do
        if kind ~= '' and count >= #crashes then output[#output + 1] = { kind = kind, victimCount = count } end
    end
    table.sort(output, function(left, right) return left.kind < right.kind end)
    return output
end

local function candidateActors(crashes)
    local candidates = {}
    for _, crash in ipairs(crashes) do
        local seenForVictim = {}
        for _, entry in ipairs(crash.timeline or {}) do
            for _, field in ipairs({ 'owner', 'firstOwner', 'targetOwner', 'target' }) do
                local actorSource = tonumber(entry.data and entry.data[field])
                if actorSource and actorSource > 0 and actorSource ~= crash.source then
                    seenForVictim[math.floor(actorSource)] = seenForVictim[math.floor(actorSource)] or {}
                    seenForVictim[math.floor(actorSource)][#seenForVictim[math.floor(actorSource)] + 1] =
                        ('%s.%s'):format(tostring(entry.kind), field)
                end
            end
        end
        for actorSource, evidence in pairs(seenForVictim) do
            local current = candidates[actorSource] or { source = actorSource, victims = 0, supporting_evidence = {} }
            current.victims = current.victims + 1
            for _, item in ipairs(evidence) do current.supporting_evidence[#current.supporting_evidence + 1] = item end
            candidates[actorSource] = current
        end
    end
    local output = {}
    for actorSource, candidate in pairs(candidates) do
        if candidate.victims >= 2 then
            local identity = coreIdentity(actorSource)
            candidate.citizenid = identity.ok == true and identity.citizenid or nil
            candidate.confidence = candidate.victims / #crashes
            output[#output + 1] = candidate
        end
    end
    table.sort(output, function(left, right) return left.confidence > right.confidence end)
    return output
end

local function correlateCrash(crash)
    local currentMs = nowMs()
    local history = math.max(5000, math.floor(tonumber(config().crashHistoryMs) or 15000))
    for index = #recentCrashes, 1, -1 do
        if currentMs - recentCrashes[index].atMs > history then table.remove(recentCrashes, index) end
    end
    recentCrashes[#recentCrashes + 1] = crash
    local window = math.max(1000, math.floor(tonumber(config().crashClusterWindowMs) or 5000))
    local victims = {}
    for _, item in ipairs(recentCrashes) do
        if currentMs - item.atMs <= window then victims[#victims + 1] = item end
    end
    if #victims < math.max(2, math.floor(tonumber(config().crashMinimumVictims) or 2)) then return nil end
    local firstAt = victims[1].atMs
    local victimRows = {}
    for _, victim in ipairs(victims) do
        victimRows[#victimRows + 1] = {
            citizenid = victim.citizenid, account_id = victim.accountId,
            session_id = victim.sessionId, source = victim.source,
            player_name = victim.playerName, at = victim.at, difference_ms = victim.atMs - firstAt
        }
    end
    local common = commonSignals(victims)
    local candidates = candidateActors(victims)
    local incident = MZBan.Incidents.Record({
        source = crash.source,
        citizenid = crash.citizenid,
        accountId = crash.accountId,
        sessionId = crash.sessionId,
        playerName = ('Crash cluster (%d vitimas)'):format(#victims),
        aggregateIdentity = 'system:crash_cluster',
        code = 'crash_cluster_suspect',
        origin = 'playerDropped', confidence = #common > 0 and 'medium' or 'low',
        subject = ('cluster:%d'):format(math.floor(firstAt / window)),
        reason = 'multiple_crashes_inside_configured_window',
        context = { victims = victimRows, window_ms = window, common_signals = common, candidate_actors = candidates },
        samples = { victims = victimRows },
        evidence = { victimCount = #victims, commonSignalCount = #common, candidateCount = #candidates, windowMs = window },
        timelineSnapshot = crash.timeline,
        mitigation = { attempted = false, applied = false, result = 'observe_only' },
        linkedIncidentIds = crash.incidentId and { crash.incidentId } or {}
    })
    return incident
end

function MZBan.Correlation.HandlePlayerDropped(sourceId, reason)
    sourceId = normalizeSource(sourceId)
    if not sourceId then return 'disconnect', nil end
    local classification = classifyDropReason(reason)
    MZBan.Correlation.Record(sourceId, 'session.disconnect', {
        classification = classification,
        reason = safeString(reason, 128)
    })
    local timeline = MZBan.Correlation.Snapshot(sourceId,
        math.max(1, math.floor(tonumber(config().labSnapshotEntries) or 64)))
    local identity = coreIdentity(sourceId)
    local coords, bucket = lastPosition(sourceId)
    local incident
    if classification == 'crash' and MZBan.Incidents and type(MZBan.Incidents.Record) == 'function' then
        incident = MZBan.Incidents.Record({
            source = sourceId,
            citizenid = identity.citizenid,
            accountId = identity.accountId,
            sessionId = identity.sessionId,
            playerName = GetPlayerName(sourceId),
            code = 'crash_observed', origin = 'playerDropped', confidence = 'high',
            subject = tostring(identity.sessionId or identity.citizenid or sourceId),
            reason = 'drop_reason_classified_as_crash',
            context = {
                drop_reason = safeString(reason, 512), drop_classification = classification,
                last_known_coords = coords, bucket = bucket, timeline = timeline
            },
            samples = { correlation = timeline },
            evidence = {
                dropReason = safeString(reason, 512), dropClassification = classification,
                sourceAtDrop = sourceId, playerName = GetPlayerName(sourceId), bucket = bucket,
                lastKnownX = coords and coords.x, lastKnownY = coords and coords.y, lastKnownZ = coords and coords.z
            },
            timelineSnapshot = timeline,
            mitigation = { attempted = false, applied = false, result = 'observe_only' }
        })
        local crash = {
            at = os.time(), atMs = nowMs(), source = sourceId, citizenid = identity.citizenid,
            accountId = identity.accountId, sessionId = identity.sessionId,
            playerName = GetPlayerName(sourceId), timeline = timeline,
            incidentId = incident and incident.id or nil
        }
        local cluster = correlateCrash(crash)
        if incident then MZBan.Incidents.NotifyStaff(incident) end
        if cluster then MZBan.Incidents.NotifyStaff(cluster) end
    end
    MZBan.Correlation.Clear(sourceId)
    return classification, incident
end

MZBan.Correlation.ClassifyDropReason = classifyDropReason

AddEventHandler('playerDropped', function(reason)
    MZBan.Correlation.HandlePlayerDropped(source, reason)
end)

CreateThread(function()
    while true do
        Wait(30000)
        local currentMs = nowMs()
        for sourceId in pairs(timelines) do prune(sourceId, currentMs) end
    end
end)
