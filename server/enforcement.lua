MZBan = MZBan or {}
MZBan.Enforcement = MZBan.Enforcement or {}

local MODES = { passive = 1, mitigate = 2, kick = 3, ban = 4 }
local MITIGATION_RESULTS = {
    blocked = true, reverted = true, observed_only = true, failed = true, not_supported = true
}
local HARD_AUTOMATION_EXCLUSIONS = {
    crash_observed = true,
    crash_cluster_suspect = true,
    client_resource_presence_missing = true,
    client_resource_stop_observed = true,
    player_godmode_suspect = true,
    player_invisible_suspect = true,
    camera_freecam_suspect = true,
    camera_spectate_unapproved = true,
    aim_headshot_pattern_suspect = true,
    canary_triggered = true
}
local CONFIRMED_SERVER_EVIDENCE = {
    weapon_damage_no_equipped_weapon = true,
    weapon_damage_hash_mismatch = true,
    weapon_damage_death_state_incompatible = true,
    entity_model_blocked = true,
    event_remote_clear_tasks_suspect = true,
    event_remote_weapon_action_suspect = true,
    event_damage_modifier_suspect = true
}

local policyFingerprint
local invalidReported = {}
local lastExecution = {}
local stats = {}

local function config()
    return type(Config.Enforcement) == 'table' and Config.Enforcement or {}
end

local function safeString(value, maximum)
    value = tostring(value or ''):gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return value:sub(1, math.max(1, tonumber(maximum) or 128))
end

local function normalizeMode(value)
    value = safeString(value, 16):lower()
    return MODES[value] and value or nil
end

local function audit(action, meta)
    meta = type(meta) == 'table' and meta or {}
    MZBan.AuditPrint(action, MZBan.JsonEncode(meta))
    if MZBan.DB and type(MZBan.DB.Audit) == 'function' then
        pcall(MZBan.DB.Audit, action, { actor_name = 'mz_banguard', meta = meta })
    end
end

local function currentFingerprint()
    local cfg = config()
    local parts = {
        tostring(cfg.DefaultMode), tostring(cfg.AutomaticKickEnabled == true),
        tostring(cfg.AutomaticBanEnabled == true), tostring(cfg.RequireStableIdentity ~= false),
        tostring(cfg.RequireConfirmedEvidence ~= false), tostring(cfg.OnMitigationFailure)
    }
    local overrides = type(Config.DetectorActions) == 'table' and Config.DetectorActions or {}
    local keys = {}
    for code in pairs(overrides) do keys[#keys + 1] = tostring(code) end
    table.sort(keys)
    for _, code in ipairs(keys) do parts[#parts + 1] = code .. '=' .. tostring(overrides[code]) end
    return table.concat(parts, '|')
end

local function auditPolicyIfChanged()
    local fingerprint = currentFingerprint()
    if fingerprint == policyFingerprint then return fingerprint end
    audit(policyFingerprint and 'security.enforcement.policy_changed' or 'security.enforcement.policy_loaded', {
        previous = policyFingerprint,
        current = fingerprint
    })
    policyFingerprint = fingerprint
    return fingerprint
end

local function reportInvalid(name, value)
    local key = tostring(name) .. ':' .. tostring(value)
    if invalidReported[key] then return end
    invalidReported[key] = true
    audit('security.enforcement.policy_invalid', {
        setting = tostring(name), value = tostring(value), fallback = 'passive'
    })
end

function MZBan.Enforcement.ResolveMode(code)
    local fingerprint = auditPolicyIfChanged()
    code = safeString(code, 64)
    local overrides = type(Config.DetectorActions) == 'table' and Config.DetectorActions or {}
    local configured = overrides[code]
    local source = 'detector'
    if configured == nil then
        configured = config().DefaultMode
        source = 'default'
    end
    local resolved = normalizeMode(configured)
    if not resolved then
        reportInvalid(source == 'detector' and ('DetectorActions.' .. code) or 'Enforcement.DefaultMode', configured)
        resolved = 'passive'
    end
    return safeString(configured, 32), resolved, source, fingerprint
end

local function detectorStats(code)
    stats[code] = stats[code] or {
        incidents = 0, occurrences = 0, mitigationsSucceeded = 0,
        mitigationsUnsupported = 0, failures = 0, kicks = 0, bans = 0,
        lastOccurrenceAt = nil
    }
    return stats[code]
end

local function resolveIdentity(sourceId)
    sourceId = tonumber(sourceId)
    local resource = tostring(Config.Integration and Config.Integration.CoreResource or 'mz_core')
    if not sourceId or sourceId <= 0 or GetPlayerPing(math.floor(sourceId)) <= 0
        or GetResourceState(resource) ~= 'started' then return nil end
    local ok, identity = pcall(function() return exports[resource]:ResolvePlayerIdentity(math.floor(sourceId)) end)
    if not ok or type(identity) ~= 'table' or identity.ok ~= true or identity.active ~= true then return nil end
    return {
        source = math.floor(sourceId),
        accountId = tonumber(identity.accountId),
        sessionId = tonumber(identity.sessionId),
        citizenid = safeString(identity.citizenid, 64)
    }
end

local function stableIdentity(incident)
    local sourceId = tonumber(incident.source)
    if not sourceId or sourceId <= 0 then return nil, 'target_offline' end
    local current = resolveIdentity(sourceId)
    if not current then return nil, 'identity_unavailable' end
    if not incident.accountId or not incident.sessionId or safeString(incident.citizenid, 64) == '' then
        return nil, 'stable_identity_missing'
    end
    if tonumber(incident.accountId) ~= current.accountId
        or tonumber(incident.sessionId) ~= current.sessionId
        or safeString(incident.citizenid, 64) ~= current.citizenid then
        return nil, 'identity_mismatch'
    end
    local expected = type(incident.identifiers) == 'table' and incident.identifiers or {}
    local currentIdentifiers = MZBan.GetIdentifiers(sourceId, { includeIp = false })
    local byType = type(currentIdentifiers) == 'table' and currentIdentifiers.byType or {}
    local expectedLicense = safeString(expected.license, 160)
    local expectedFivem = safeString(expected.fivem, 160)
    if expectedLicense == '' and expectedFivem == '' then return nil, 'stable_identifier_missing' end
    if expectedLicense ~= '' and expectedLicense ~= safeString(byType.license, 160) then
        return nil, 'identity_mismatch'
    end
    if expectedFivem ~= '' and expectedFivem ~= safeString(byType.fivem, 160) then
        return nil, 'identity_mismatch'
    end
    current.identifiers = currentIdentifiers
    return current
end

local function evidenceConfirmed(incident)
    if HARD_AUTOMATION_EXCLUSIONS[incident.code] then return false, 'detector_excluded_from_automation' end
    if incident.origin == 'client_telemetry' then return false, 'client_telemetry_unconfirmed' end
    if incident.culpability == 'none' or incident.culpability == 'contextual' then
        return false, 'culpability_inconclusive'
    end
    if config().RequireConfirmedEvidence == false then return true end
    if not CONFIRMED_SERVER_EVIDENCE[incident.code] then return false, 'evidence_not_confirmed' end
    if incident.confidence ~= 'high' and incident.confidence ~= 'critical' then
        return false, 'confidence_below_policy'
    end
    return true
end

local function executionBase(incident, configuredMode, resolvedMode, requestedAction)
    return {
        configured_mode = configuredMode,
        resolved_mode = resolvedMode,
        requested_action = requestedAction,
        executed_action = 'none',
        execution_result = 'skipped',
        reason = 'not_evaluated',
        mitigation_result = 'observed_only',
        mitigation_attempted = false,
        mitigation_applied = false,
        resource = GetCurrentResourceName(),
        incident_id = incident.id,
        account_id = incident.accountId,
        session_id = incident.sessionId,
        source_at_detection = incident.sourceAtFirstSeen,
        source_at_execution = incident.source,
        timestamp = os.time()
    }
end

local function persistExecution(incident, execution, force)
    local signature = table.concat({
        tostring(execution.resolved_mode), tostring(execution.requested_action),
        tostring(execution.executed_action), tostring(execution.execution_result),
        tostring(execution.reason), tostring(execution.mitigation_result)
    }, ':')
    local previous = lastExecution[incident.id]
    local shouldPersist = force == true or not previous or previous.signature ~= signature
        or (incident.count or 1) % 100 == 0
    lastExecution[incident.id] = { signature = signature, at = execution.timestamp }
    if shouldPersist and MZBan.Incidents and type(MZBan.Incidents.RecordExecution) == 'function' then
        execution.persistence_confirmed = MZBan.Incidents.RecordExecution(incident, execution) == true
    end
    return execution
end

local function applyMitigation(incident, execution, capability, counter)
    execution.mitigation_result = 'not_supported'
    if incident.lab == true then
        execution.execution_result = 'blocked_by_policy'
        execution.reason = 'lab_mode'
        execution.mitigation_result = 'observed_only'
        return false
    end
    if type(capability) ~= 'table' or capability.supported ~= true
        or type(capability.execute) ~= 'function' then
        execution.execution_result = 'unsupported'
        execution.reason = safeString(capability and capability.reason or 'mitigation_not_supported', 128)
        counter.mitigationsUnsupported = counter.mitigationsUnsupported + 1
        return false
    end
    execution.mitigation_attempted = true
    local ok, applied, result, reason = pcall(capability.execute)
    if not ok or applied ~= true then
        execution.execution_result = 'failed'
        execution.reason = safeString(ok and (reason or result) or applied, 128)
        execution.mitigation_result = 'failed'
        counter.failures = counter.failures + 1
        return false
    end
    result = MITIGATION_RESULTS[result] and result or 'blocked'
    execution.executed_action = 'mitigate'
    execution.execution_result = 'success'
    execution.reason = safeString(reason or 'mitigation_applied', 128)
    execution.mitigation_result = result
    execution.mitigation_applied = result == 'blocked' or result == 'reverted'
    if execution.mitigation_applied then counter.mitigationsSucceeded = counter.mitigationsSucceeded + 1 end
    return true
end

local function prepareAutomaticAction(incident, execution, requestedAction)
    if incident.lab == true then return nil, 'lab_mode', 'blocked_by_policy' end
    if MZBan.Incidents.HasExecution(incident, requestedAction) then
        return nil, 'already_executed', 'skipped'
    end
    local confirmed, evidenceReason = evidenceConfirmed(incident)
    if not confirmed then return nil, evidenceReason, 'insufficient_evidence' end
    if config().RequireStableIdentity ~= false then
        local identity, identityReason = stableIdentity(incident)
        if not identity then
            return nil, identityReason, identityReason == 'identity_mismatch' and 'identity_mismatch' or 'insufficient_evidence'
        end
        execution.source_at_execution = identity.source
        local persisted, persistReason = MZBan.Incidents.EnsurePersisted(incident, 'automatic_' .. requestedAction)
        if not persisted then return nil, persistReason, 'failed' end
        if not MZBan.Incidents.RecordExecutionRequest(incident, execution) then
            return nil, 'execution_audit_persistence_failed', 'failed'
        end
        return identity
    end
    return nil, 'stable_identity_required', 'insufficient_evidence'
end

local function executeKick(incident, execution, counter)
    if config().AutomaticKickEnabled ~= true then
        execution.execution_result, execution.reason = 'blocked_by_policy', 'automatic_kick_disabled'
        return
    end
    local identity, reason, result = prepareAutomaticAction(incident, execution, 'kick')
    if not identity then execution.execution_result, execution.reason = result, reason return end
    local current, currentReason = stableIdentity(incident)
    if not current then execution.execution_result, execution.reason = 'identity_mismatch', currentReason return end
    local ok, err = pcall(DropPlayer, current.source,
        ('Removido pelo MZ BanGuard. Incidente: %s'):format(incident.id))
    execution.source_at_execution = current.source
    execution.executed_action = ok and 'kick_requested' or 'none'
    execution.execution_result = ok and 'success' or 'failed'
    execution.reason = ok and 'drop_requested' or safeString(err, 128)
    if ok then counter.kicks = counter.kicks + 1 else counter.failures = counter.failures + 1 end
end

local function executeBan(incident, execution, counter)
    if config().AutomaticBanEnabled ~= true then
        execution.execution_result, execution.reason = 'blocked_by_policy', 'automatic_ban_disabled'
        return
    end
    local identity, reason, result = prepareAutomaticAction(incident, execution, 'ban')
    if not identity then execution.execution_result, execution.reason = result, reason return end
    local existing = MZBan.Bans.FindActiveByIncidentId and MZBan.Bans.FindActiveByIncidentId(incident.id) or nil
    local ban = existing
    if not ban then
        local evidence = MZBan.JsonEncode({
            incident_id = incident.id,
            detector = incident.code,
            account_id = incident.accountId,
            session_id = incident.sessionId,
            target_citizenid = incident.citizenid
        })
        local created, createError = MZBan.Bans.Create({
            player_name = incident.playerName,
            reason = ('Automatic local ban for confirmed detector %s (incident %s)'):format(incident.code, incident.id),
            evidence = evidence,
            banned_by = 'mz_banguard',
            banned_by_identifier = 'system:mz_banguard',
            identifiers = identity.identifiers,
            tokens = MZBan.GetPlayerTokensSafe(identity.source),
            expires_at = nil
        }, {
            action = 'ban.created.automatic_enforcement',
            actor_name = 'mz_banguard',
            target_source = identity.source,
            target_name = incident.playerName,
            meta = {
                incident_id = incident.id, detector = incident.code,
                account_id = incident.accountId, session_id = incident.sessionId,
                citizenid = incident.citizenid
            }
        })
        if not created then
            execution.execution_result = 'failed'
            execution.reason = safeString(createError or 'ban_persistence_failed', 128)
            counter.failures = counter.failures + 1
            return
        end
        ban = created
    end
    execution.executed_action = 'ban'
    execution.execution_result = 'success'
    counter.bans = counter.bans + (existing and 0 or 1)
    local current, currentReason = stableIdentity(incident)
    if not current then
        execution.reason = 'ban_persisted_disconnect_' .. safeString(currentReason, 64)
        return
    end
    local dropped, dropError = pcall(DropPlayer, current.source, MZBan.Bans.FormatKickMessage(ban))
    execution.source_at_execution = current.source
    execution.reason = dropped and (existing and 'existing_ban_disconnect_requested' or 'ban_persisted_disconnect_requested')
        or ('ban_persisted_disconnect_failed:' .. safeString(dropError, 96))
end

function MZBan.Enforcement.Process(incident, options)
    if type(incident) ~= 'table' or safeString(incident.code, 64) == '' then return nil end
    options = type(options) == 'table' and options or {}
    local configuredMode, resolvedMode, _, fingerprint = MZBan.Enforcement.ResolveMode(incident.code)
    local counter = detectorStats(incident.code)
    counter.occurrences = counter.occurrences + 1
    counter.lastOccurrenceAt = os.time()
    if options.created == true then counter.incidents = counter.incidents + 1 end
    local execution = executionBase(incident, configuredMode, resolvedMode, resolvedMode == 'passive' and 'record' or resolvedMode)

    if resolvedMode == 'passive' then
        execution.executed_action = 'record'
        execution.execution_result = 'success'
        execution.reason = 'passive_policy'
        return persistExecution(incident, execution, options.created == true)
    end

    applyMitigation(incident, execution, options.mitigation, counter)
    local failurePolicy = safeString(config().OnMitigationFailure or 'log_only', 32):lower()
    if failurePolicy ~= 'log_only' and failurePolicy ~= 'block_punishment' then
        reportInvalid('Enforcement.OnMitigationFailure', failurePolicy)
        failurePolicy = 'log_only'
    end
    if resolvedMode == 'mitigate' then
        return persistExecution(incident, execution, options.created == true)
    end
    if execution.mitigation_result == 'failed' and failurePolicy == 'block_punishment' then
        execution.execution_result, execution.reason = 'blocked_by_policy', 'mitigation_failure_blocks_punishment'
        return persistExecution(incident, execution, true)
    end
    if resolvedMode == 'kick' then executeKick(incident, execution, counter) end
    if resolvedMode == 'ban' then executeBan(incident, execution, counter) end
    execution.policy_fingerprint = fingerprint
    return persistExecution(incident, execution, execution.execution_result == 'success')
end

function MZBan.Enforcement.Status()
    local configuredMode, resolvedMode = MZBan.Enforcement.ResolveMode('__default__')
    local detectors = {}
    local detectorCodes = {}
    for code in pairs(stats) do detectorCodes[code] = true end
    for code in pairs(type(Config.DetectorActions) == 'table' and Config.DetectorActions or {}) do
        detectorCodes[tostring(code)] = true
    end
    for code in pairs(detectorCodes) do
        local values = stats[code] or {}
        detectors[code] = {
            configuredMode = select(1, MZBan.Enforcement.ResolveMode(code)),
            resolvedMode = select(2, MZBan.Enforcement.ResolveMode(code)),
            incidents = values.incidents or 0,
            occurrences = values.occurrences or 0,
            lastOccurrenceAt = values.lastOccurrenceAt,
            mitigationsSucceeded = values.mitigationsSucceeded or 0,
            mitigationsUnsupported = values.mitigationsUnsupported or 0,
            failures = values.failures or 0,
            kicks = values.kicks or 0,
            bans = values.bans or 0
        }
    end
    return {
        configuredDefaultMode = configuredMode,
        resolvedDefaultMode = resolvedMode,
        automaticKickEnabled = config().AutomaticKickEnabled == true,
        automaticBanEnabled = config().AutomaticBanEnabled == true,
        requireStableIdentity = config().RequireStableIdentity ~= false,
        requireConfirmedEvidence = config().RequireConfirmedEvidence ~= false,
        policyFingerprint = policyFingerprint,
        detectors = detectors
    }
end

