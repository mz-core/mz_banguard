MZBan = MZBan or {}
MZBan.Flags = MZBan.Flags or {}

local scores = {}
local deniedAuditUntil = {}

local function exportLimits()
    return type(Config.Risk.ExportLimits) == 'table' and Config.Risk.ExportLimits or {}
end

local function exportAllowed(operation, invokingResource)
    local access = type(Config.Risk.ExportAccess) == 'table' and Config.Risk.ExportAccess or {}
    local allowed = access[operation]
    return type(invokingResource) == 'string'
        and type(allowed) == 'table'
        and allowed[invokingResource] == true
end

local function sanitizeToken(value, fallback, allowWildcard)
    value = tostring(value or fallback or ''):lower()
    value = value:gsub('%c', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if allowWildcard == true and value == '*' then return value end
    if value == '' or #value > 64 or not value:match('^[a-z0-9_.:%-]+$') then
        return nil
    end
    return value
end

local function sanitizeEvidence(value, depth, counter)
    local valueType = type(value)
    local limits = exportLimits()
    local maxDepth = math.max(1, tonumber(limits.MaxEvidenceDepth) or 2)
    local maxKeys = math.max(1, tonumber(limits.MaxEvidenceKeys) or 20)
    local maxString = math.max(1, tonumber(limits.MaxEvidenceString) or 256)

    if valueType == 'string' then return MZBan.Truncate(value:gsub('%c', ' '), maxString) end
    if valueType == 'number' or valueType == 'boolean' then return value end
    if valueType ~= 'table' or depth >= maxDepth then return nil end

    local output = {}
    for key, item in pairs(value) do
        if counter.count >= maxKeys then break end
        local safeKey = tostring(key or ''):gsub('%c', '')
        if safeKey ~= '' and #safeKey <= 64 then
            local safeValue = sanitizeEvidence(item, depth + 1, counter)
            if safeValue ~= nil then
                output[safeKey] = safeValue
                counter.count = counter.count + 1
            end
        end
    end
    return output
end

local function auditExportDenied(operation, invokingResource, reason)
    local auditKey = tostring(operation) .. ':' .. tostring(invokingResource or 'unknown')
    local now = GetGameTimer()
    local cooldown = math.max(1000, tonumber(exportLimits().DeniedAuditCooldownMs) or 10000)
    if (deniedAuditUntil[auditKey] or 0) > now then return end
    deniedAuditUntil[auditKey] = now + cooldown

    pcall(function()
        local ready = MZBan.DB.IsReady()
        if ready ~= true then return end
        MZBan.DB.Audit('risk.export.denied', {
            meta = {
                operation = tostring(operation),
                invoking_resource = tostring(invokingResource or 'unknown'),
                reason = tostring(reason or 'untrusted_resource')
            }
        })
    end)
end

local function defaultPoints(reason)
    local points = Config.Risk.DefaultPoints[reason] or Config.Risk.DefaultPoints.generic or 25
    return tonumber(points) or 25
end

local function getState(primary)
    local state = scores[primary]
    local now = MZBan.Now()

    if not state then
        state = { score = 0, last_update = now }
        scores[primary] = state
        return state
    end

    local elapsedMinutes = math.floor((now - (state.last_update or now)) / 60)
    if elapsedMinutes > 0 then
        local decay = elapsedMinutes * (tonumber(Config.Risk.DecayPointsEveryMinute or 0) or 0)
        state.score = math.max(0, (tonumber(state.score or 0) or 0) - decay)
        state.last_update = now
    end

    return state
end

local TRUSTED_ALIASES = {
    teleport = 'movement.teleport',
    noclip = 'movement.noclip.staff',
    godmode = 'player.invincibility',
    spectate = 'camera.spectate.staff'
}

local function trustedCapability(action)
    action = sanitizeToken(action, nil, false)
    return action and (TRUSTED_ALIASES[action] or action) or nil
end

function MZBan.Flags.RegisterTrustedAction(src, action, durationMs, issuer, context)
    if not Config.Risk.TrustedActions or not Config.Risk.TrustedActions.Enabled then return false end
    src = tonumber(src)
    action = trustedCapability(action)
    if not src or src <= 0 or not GetPlayerName(src) or not action then
        return false, 'invalid_request'
    end

    local duration = tonumber(durationMs or Config.Risk.TrustedActions.DefaultDurationMs or 8000) or 8000
    duration = math.floor(duration)
    local maxDuration = math.max(250, tonumber(exportLimits().MaxTrustedActionMs) or 30000)
    if duration < 250 or duration > maxDuration then return false, 'invalid_duration' end
    if not MZBan.SecurityLeases or type(MZBan.SecurityLeases.Issue) ~= 'function' then
        return false, 'leases_unavailable'
    end
    local leaseId, err = MZBan.SecurityLeases.Issue(src, action, duration, context, issuer)
    if not leaseId then return false, err end
    return true, nil, leaseId
end

local function isTrusted(src, reason)
    if not Config.Risk.TrustedActions or not Config.Risk.TrustedActions.Enabled then return false end
    local capability = trustedCapability(reason)
    if not capability or not MZBan.SecurityLeases or type(MZBan.SecurityLeases.Check) ~= 'function' then return false end
    return MZBan.SecurityLeases.Check(src, capability, {}) == true
end

function MZBan.Flags.IsTrusted(src, reason)
    src = tonumber(src)
    reason = trustedCapability(reason)
    if not src or not reason then return false end
    return isTrusted(src, reason)
end

function MZBan.Flags.ConsumeTrusted(src, reason, context)
    src = tonumber(src)
    reason = trustedCapability(reason)
    if not src or not reason or not MZBan.SecurityLeases
        or type(MZBan.SecurityLeases.Consume) ~= 'function' then return false end
    return MZBan.SecurityLeases.Consume(src, reason, context or {}) == true
end

function MZBan.Flags.GetScore(src)
    local identifiers = MZBan.GetIdentifiers(src, { includeIp = false })
    local primary = MZBan.GetPrimaryIdentifier(identifiers)
    if not primary then return 0 end
    return getState(primary).score or 0
end

function MZBan.Flags.FlagPlayer(src, reason, points, evidence, createdByResource)
    if not Config.Risk.Enabled then return false, 'risk_disabled' end

    src = tonumber(src)
    if not src or not GetPlayerName(src) then return false, 'invalid_player' end

    reason = sanitizeToken(reason, 'generic')
    if not reason then return false, 'invalid_reason' end

    if isTrusted(src, reason) then
        return false, 'trusted_action'
    end

    if MZBan.HasPermission(src, Config.Permissions.Admin) then
        return false, 'admin_ignored'
    end

    local identifiers = MZBan.GetIdentifiers(src, { includeIp = Config.Privacy.StoreIpLocal == true })
    local primary = MZBan.GetPrimaryIdentifier(identifiers)
    if not primary then return false, 'no_primary_identifier' end

    local state = getState(primary)
    local addPoints = tonumber(points or defaultPoints(reason)) or defaultPoints(reason)
    addPoints = math.floor(addPoints)
    local maxPointsPerFlag = math.max(1, tonumber(exportLimits().MaxPointsPerFlag) or 100)
    if addPoints < 1 or addPoints > maxPointsPerFlag then return false, 'invalid_points' end
    local maxScore = tonumber(Config.Risk.MaxScore or 200) or 200
    state.score = math.min(maxScore, math.max(0, (tonumber(state.score or 0) or 0) + addPoints))
    state.last_update = MZBan.Now()

    local playerName = GetPlayerName(src)
    local evidencePayload = sanitizeEvidence(
        type(evidence) == 'table' and evidence or { detail = evidence },
        0,
        { count = 0 }
    ) or {}
    local labSubject = MZBan.Lab and type(MZBan.Lab.IsSubject) == 'function'
        and MZBan.Lab.IsSubject(src) == true
    if labSubject then evidencePayload.lab = true end

    MZBan.DB.SaveFlag({
        player_name = playerName,
        primary_identifier = primary,
        reason = reason,
        points = addPoints,
        score_after = state.score,
        evidence = evidencePayload,
        created_by_resource = createdByResource or GetCurrentResourceName()
    })

    MZBan.DB.Audit('risk.flag', {
        target_source = src,
        target_name = playerName,
        meta = {
            reason = reason,
            points = addPoints,
            score_after = state.score,
            evidence = evidencePayload,
            created_by_resource = createdByResource or GetCurrentResourceName()
        }
    })

    local flagPayload = {
        player_name = playerName,
        identifiers = { byType = identifiers.byType },
        reason = reason,
        points = addPoints,
        score_after = state.score,
        evidence = evidencePayload,
        created_by_resource = createdByResource or GetCurrentResourceName()
    }

    CreateThread(function()
        MZBan.Cloud.ReportFlag(flagPayload)
    end)

    local fields = {
        MZBan.Webhook.Field('Player', ('%s [%s]'):format(playerName, src), true),
        MZBan.Webhook.Field('Motivo', reason, true),
        MZBan.Webhook.Field('Pontos', tostring(addPoints), true),
        MZBan.Webhook.Field('Score', tostring(state.score), true),
        MZBan.Webhook.Field('Identifier', MZBan.Redact(primary), false),
        MZBan.Webhook.Field('Evidência', MZBan.JsonEncode(evidencePayload), false)
    }

    -- O score legado continua informativo, mas nao executa punicao sem um
    -- incidente validado pelo motor unificado.
    if not labSubject and ((Config.Risk.AutoBan == true and state.score >= (Config.Risk.BanAt or 150))
        or (Config.Risk.AutoKick == true and state.score >= (Config.Risk.KickAt or 110))) then
        local legacyAutomationMeta = {
            source = src, score = state.score, reason = reason,
            required_flow = 'MZBan.Enforcement.Process'
        }
        if type(MZBan.AuditPrint) == 'function' then
            MZBan.AuditPrint('security.legacy_score_automation.blocked', MZBan.JsonEncode(legacyAutomationMeta))
        end
        if MZBan.DB and type(MZBan.DB.Audit) == 'function' then
            pcall(MZBan.DB.Audit, 'security.legacy_score_automation.blocked', {
                actor_name = 'mz_banguard', target_source = src, meta = legacyAutomationMeta
            })
        end
    end

    if state.score >= (Config.Risk.ReviewAt or 70) then
        MZBan.Webhook.Send('RiskReview', '🚨 MZ BanGuard: revisão necessária', 'Jogador atingiu score alto. Recomendado spectate/revisão.', fields, 'warning')
    elseif state.score >= (Config.Risk.AlertAt or 40) then
        MZBan.Webhook.Send('RiskAlert', '⚠️ MZ BanGuard: alerta de risco', 'Jogador acumulou suspeitas.', fields, 'warning')
    end

    return true, labSubject and 'flagged_lab_no_punishment' or 'flagged', state.score
end

exports('FlagPlayer', function(src, reason, points, evidence)
    local invokingResource = GetInvokingResource()
    if not exportAllowed('FlagPlayer', invokingResource) then
        auditExportDenied('FlagPlayer', invokingResource, 'untrusted_resource')
        return false, 'untrusted_resource'
    end
    return MZBan.Flags.FlagPlayer(src, reason, points, evidence, invokingResource)
end)

exports('RegisterTrustedAction', function(src, action, durationMs)
    local invokingResource = GetInvokingResource()
    if not exportAllowed('RegisterTrustedAction', invokingResource) then
        auditExportDenied('RegisterTrustedAction', invokingResource, 'untrusted_resource')
        return false, 'untrusted_resource'
    end
    return MZBan.Flags.RegisterTrustedAction(src, action, durationMs, invokingResource)
end)

exports('GetRiskScore', function(src)
    local invokingResource = GetInvokingResource()
    if not exportAllowed('GetRiskScore', invokingResource) then
        auditExportDenied('GetRiskScore', invokingResource, 'untrusted_resource')
        return nil, 'untrusted_resource'
    end
    src = tonumber(src)
    if not src or src <= 0 or not GetPlayerName(src) then return nil, 'invalid_player' end
    return MZBan.Flags.GetScore(src)
end)
