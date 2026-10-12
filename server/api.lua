MZBan = MZBan or {}
MZBan.API = MZBan.API or {}

local function result(ok, data, err)
    return {
        ok = ok == true,
        data = ok == true and data or nil,
        error = ok == true and nil or tostring(err or 'unknown_error')
    }
end

local function integrationConfig()
    return type(Config.Integration) == 'table' and Config.Integration or {}
end

local function limits()
    local configured = integrationConfig().Limits
    return type(configured) == 'table' and configured or {}
end

local function normalizeSource(value)
    value = tonumber(value)
    if not value or value <= 0 then return nil end
    value = math.floor(value)
    if not GetPlayerName(value) or GetPlayerPing(value) <= 0 then return nil end
    return value
end

local function sanitizeText(value, maxLength)
    if type(value) ~= 'string' then return '' end
    value = value:gsub('%c', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    maxLength = math.max(1, tonumber(maxLength) or 256)
    if #value > maxLength then value = value:sub(1, maxLength) end
    return value
end

local function sanitizePublicId(value)
    if type(value) ~= 'string' then return nil end
    value = value:upper():gsub('%s+', '')
    if not value:match('^MBG%-[A-HJ-NP-Z2-9][A-HJ-NP-Z2-9][A-HJ-NP-Z2-9][A-HJ-NP-Z2-9][A-HJ-NP-Z2-9][A-HJ-NP-Z2-9]$') then
        return nil
    end
    return value
end

local function trustedInvocation(invokingResource)
    local trusted = integrationConfig().TrustedResources
    return type(invokingResource) == 'string'
        and type(trusted) == 'table'
        and trusted[invokingResource] == true
end

local function coreResource()
    return tostring(integrationConfig().CoreResource or 'mz_core')
end

local function resolveCitizenId(sourceId)
    if GetResourceState(coreResource()) ~= 'started' then return nil end
    local ok, identity = pcall(function()
        return exports[coreResource()]:ResolvePlayerIdentity(sourceId)
    end)
    if not ok or type(identity) ~= 'table' or identity.ok ~= true then return nil end
    local citizenid = sanitizeText(identity.citizenid, 64)
    return citizenid ~= '' and citizenid or nil
end

local function identityMatchesSnapshot(sourceId, expectedCitizenId, expectedIdentifiers)
    if resolveCitizenId(sourceId) ~= expectedCitizenId then return false, 'stale_target' end
    local current = MZBan.GetIdentifiers(sourceId, { includeIp = false })
    local currentByType = type(current) == 'table' and current.byType or {}
    local expectedByType = type(expectedIdentifiers) == 'table' and expectedIdentifiers.byType or {}
    local expectedLicense = sanitizeText(expectedByType.license, 160)
    local expectedFivem = sanitizeText(expectedByType.fivem, 160)
    if expectedLicense ~= '' and sanitizeText(currentByType.license, 160) ~= expectedLicense then
        return false, 'stale_target'
    end
    if expectedFivem ~= '' and sanitizeText(currentByType.fivem, 160) ~= expectedFivem then
        return false, 'stale_target'
    end
    return true
end

local function databaseReady()
    local ok, ready, err = pcall(MZBan.DB.IsReady)
    if not ok then return false, 'database_unavailable' end
    if ready ~= true then return false, err or 'schema_not_ready' end
    return true
end

local function authorize(actorSource, permission)
    actorSource = normalizeSource(actorSource)
    if not actorSource then return false, 'invalid_actor' end

    local resourceName = coreResource()
    if GetResourceState(resourceName) ~= 'started' then
        return false, 'core_unavailable'
    end

    local ok, allowed = pcall(function()
        return exports[resourceName]:HasGlobalPermission(actorSource, permission)
    end)
    if not ok then return false, 'authorization_unavailable' end
    if allowed ~= true then return false, 'permission_denied' end
    return true, actorSource
end

local function authorizeHierarchy(actorSource, targetSource)
    local resourceName = coreResource()
    local ok, allowed, reason, context = pcall(function()
        return exports[resourceName]:CanStaffActOnPlayer(actorSource, targetSource)
    end)
    if not ok then return false, 'hierarchy_unavailable' end
    if allowed ~= true then return false, reason or 'hierarchy_denied', context end
    return true, reason or 'authorized', context
end

local function parseDuration(value)
    value = sanitizeText(tostring(value or 'perm'), 16):lower()
    if value == 'perm' or value == 'perma' or value == 'permanent' then
        return nil, 'perm'
    end

    if not value:match('^%d+[mhd]$') then return false, 'invalid_duration' end
    local expiresAt, label = MZBan.ParseDuration(value)
    if expiresAt == false then return false, 'invalid_duration' end

    local maxSeconds = math.max(1, tonumber(limits().MaxDurationDays) or 3650) * 86400
    if tonumber(expiresAt) - MZBan.Now() > maxSeconds then
        return false, 'duration_too_long'
    end
    return expiresAt, label
end

local function auditDenied(action, actorSource, targetSource, targetName, reason, publicId)
    pcall(function()
        local ready = MZBan.DB.IsReady()
        if ready ~= true then return end
        MZBan.DB.Audit('integration.' .. action .. '.denied', {
            actor_source = tonumber(actorSource),
            actor_name = MZBan.SafePlayerName(tonumber(actorSource) or 0),
            target_source = tonumber(targetSource),
            target_name = targetName,
            ban_public_id = publicId,
            meta = { reason = tostring(reason or 'denied') }
        })
    end)
end

local function validateInvocation(invokingResource)
    if not trustedInvocation(invokingResource) then
        return false, 'untrusted_resource'
    end
    return databaseReady()
end

function MZBan.API.IsReady()
    local ready, err = databaseReady()
    if not ready then return false, err end
    if GetResourceState(coreResource()) ~= 'started' then return false, 'core_unavailable' end
    return true
end

function MZBan.API.CreateOnlineBan(actorSource, targetSource, duration, reason, invokingResource, expectedCitizenId)
    local ready, readyError = validateInvocation(invokingResource)
    if not ready then return result(false, nil, readyError) end

    local permission = integrationConfig().Permissions and integrationConfig().Permissions.Create
    local allowed, actorOrError = authorize(actorSource, permission)
    if not allowed then
        auditDenied('ban.create', actorSource, targetSource, nil, actorOrError)
        return result(false, nil, actorOrError)
    end
    actorSource = actorOrError

    targetSource = normalizeSource(targetSource)
    if not targetSource then
        auditDenied('ban.create', actorSource, targetSource, nil, 'invalid_target')
        return result(false, nil, 'invalid_target')
    end
    if targetSource == actorSource then
        auditDenied('ban.create', actorSource, targetSource, GetPlayerName(targetSource), 'self_target')
        return result(false, nil, 'self_target')
    end

    expectedCitizenId = sanitizeText(expectedCitizenId, 64)
    if invokingResource == 'mz_admin' and expectedCitizenId == '' then
        auditDenied('ban.create', actorSource, targetSource, GetPlayerName(targetSource), 'expected_identity_required')
        return result(false, nil, 'expected_identity_required')
    end

    local hierarchyAllowed, hierarchyReason, hierarchy = authorizeHierarchy(actorSource, targetSource)
    if not hierarchyAllowed then
        auditDenied('ban.create', actorSource, targetSource, GetPlayerName(targetSource), hierarchyReason)
        return result(false, nil, hierarchyReason)
    end

    local reasonLimits = limits()
    reason = sanitizeText(reason, reasonLimits.ReasonMax or 256)
    if #reason < math.max(1, tonumber(reasonLimits.ReasonMin) or 3) then
        auditDenied('ban.create', actorSource, targetSource, GetPlayerName(targetSource), 'invalid_reason')
        return result(false, nil, 'invalid_reason')
    end

    local expiresAt, durationLabel = parseDuration(duration)
    if expiresAt == false then
        auditDenied('ban.create', actorSource, targetSource, GetPlayerName(targetSource), durationLabel)
        return result(false, nil, durationLabel)
    end

    local targetName = GetPlayerName(targetSource)
    local actorName = MZBan.SafePlayerName(actorSource)
    local targetCitizenId = resolveCitizenId(targetSource)
    if expectedCitizenId ~= '' and targetCitizenId ~= expectedCitizenId then
        auditDenied('ban.create', actorSource, targetSource, targetName, 'stale_target')
        return result(false, nil, 'stale_target')
    end
    local actorCitizenId = resolveCitizenId(actorSource)
    local identifiers = MZBan.GetIdentifiers(targetSource, {
        includeIp = Config.Privacy.StoreIpLocal == true
    })
    local requiredOk, missingType = MZBan.HasRequiredIdentifiers(identifiers)
    if not requiredOk then
        auditDenied('ban.create', actorSource, targetSource, targetName, 'missing_identifier:' .. tostring(missingType))
        return result(false, nil, 'missing_required_identifier')
    end
    local identityStable, identityReason = identityMatchesSnapshot(targetSource, targetCitizenId, identifiers)
    if not identityStable then
        auditDenied('ban.create', actorSource, targetSource, targetName, identityReason)
        return result(false, nil, identityReason)
    end

    local tokens = MZBan.GetPlayerTokensSafe(targetSource)
    local activeBan = MZBan.Bans.CheckLocal(identifiers, tokens)
    if activeBan then
        auditDenied('ban.create', actorSource, targetSource, targetName, 'already_banned', activeBan.public_id)
        return result(false, nil, 'already_banned')
    end

    local score = MZBan.Flags.GetScore(targetSource)
    local flags = MZBan.DB.GetRecentFlags(MZBan.GetPrimaryIdentifier(identifiers), 8)
    local evidence = {
        risk_score = score,
        recent_flags = flags,
        target_citizenid = targetCitizenId
    }
    local ban, createError = MZBan.Bans.Create({
        player_name = targetName,
        reason = reason,
        evidence = MZBan.JsonEncode(evidence),
        banned_by = actorName,
        banned_by_identifier = MZBan.GetActorIdentifier(actorSource),
        identifiers = identifiers,
        tokens = tokens,
        expires_at = expiresAt
    }, {
        action = 'ban.created.integration',
        actor_source = actorSource,
        actor_name = actorName,
        target_source = targetSource,
        target_name = targetName,
        meta = {
            reason = reason,
            duration = durationLabel,
            risk_score = score,
            relationship = type(hierarchy) == 'table' and hierarchy.relationship or nil,
            actor_citizenid = actorCitizenId,
            target_citizenid = targetCitizenId,
            invoking_resource = invokingResource
        }
    })
    if not ban then return result(false, nil, createError or 'persistence_failed') end

    MZBan.Webhook.Send('BanCreated', '⛔ Ban criado', ('Código: `%s`'):format(ban.public_id), {
        MZBan.Webhook.Field('Player', ('%s [%s]'):format(targetName, targetSource), true),
        MZBan.Webhook.Field('CitizenID', targetCitizenId or 'Indisponivel', true),
        MZBan.Webhook.Field('Staff', actorName, true),
        MZBan.Webhook.Field('Duração', durationLabel, true),
        MZBan.Webhook.Field('Motivo', reason, false),
        MZBan.Webhook.Field('Score', tostring(score), true)
    }, 'danger')

    CreateThread(function()
        MZBan.Cloud.ReportBan(ban)
    end)

    local disconnectRequested = false
    local disconnectReason = 'identity_mismatch_after_persistence'
    local stillSameIdentity = identityMatchesSnapshot(targetSource, targetCitizenId, identifiers)
    if stillSameIdentity then
        local dropOk, dropError = pcall(DropPlayer, targetSource, MZBan.Bans.FormatKickMessage(ban))
        disconnectRequested = dropOk
        disconnectReason = dropOk and 'drop_requested' or ('drop_failed:' .. sanitizeText(dropError, 96))
    end
    if not disconnectRequested then
        pcall(MZBan.DB.Audit, 'integration.ban.disconnect_not_completed', {
            actor_source = actorSource,
            actor_name = actorName,
            target_source = targetSource,
            target_name = targetName,
            ban_public_id = ban.public_id,
            meta = {
                reason = disconnectReason,
                expected_citizenid = targetCitizenId,
                current_citizenid = resolveCitizenId(targetSource)
            }
        })
    end
    return result(true, {
        ban = MZBan.Bans.ToPublicDto(ban),
        disconnectRequested = disconnectRequested,
        disconnectReason = disconnectReason
    })
end

function MZBan.API.RevokeBan(actorSource, publicId, reason, invokingResource)
    local ready, readyError = validateInvocation(invokingResource)
    if not ready then return result(false, nil, readyError) end

    local permission = integrationConfig().Permissions and integrationConfig().Permissions.Revoke
    local allowed, actorOrError = authorize(actorSource, permission)
    if not allowed then
        auditDenied('ban.revoke', actorSource, nil, nil, actorOrError, publicId)
        return result(false, nil, actorOrError)
    end
    actorSource = actorOrError

    publicId = sanitizePublicId(publicId)
    if not publicId then
        auditDenied('ban.revoke', actorSource, nil, nil, 'invalid_public_id')
        return result(false, nil, 'invalid_public_id')
    end

    reason = sanitizeText(reason, limits().ReasonMax or 256)
    if #reason < math.max(1, tonumber(limits().ReasonMin) or 3) then
        auditDenied('ban.revoke', actorSource, nil, nil, 'invalid_reason', publicId)
        return result(false, nil, 'invalid_reason')
    end

    local actorName = MZBan.SafePlayerName(actorSource)
    local ok, banOrError = MZBan.Bans.Revoke(publicId, actorName, reason, {
        action = 'ban.revoked.integration',
        actor_source = actorSource,
        actor_name = actorName,
        target_name = nil,
        meta = {
            reason = reason,
            invoking_resource = invokingResource
        }
    })
    if not ok then return result(false, nil, banOrError) end
    local ban = banOrError

    MZBan.Webhook.Send('BanRevoked', '✅ Ban revogado', ('Código local: `%s`'):format(publicId), {
        MZBan.Webhook.Field('Staff', actorName, true),
        MZBan.Webhook.Field('Cloud ID', ban.cloud_ban_id or 'N/A', true),
        MZBan.Webhook.Field('Motivo', reason, false)
    }, 'success')

    CreateThread(function()
        MZBan.Cloud.ReportUnban(ban.cloud_ban_id or publicId, actorName, reason)
    end)

    return result(true, { ban = MZBan.Bans.ToPublicDto(MZBan.Bans.GetByPublicId(publicId)) })
end

function MZBan.API.GetBan(actorSource, publicId, invokingResource)
    local ready, readyError = validateInvocation(invokingResource)
    if not ready then return result(false, nil, readyError) end

    local permission = integrationConfig().Permissions and integrationConfig().Permissions.View
    local allowed, actorOrError = authorize(actorSource, permission)
    if not allowed then return result(false, nil, actorOrError) end

    publicId = sanitizePublicId(publicId)
    if not publicId then return result(false, nil, 'invalid_public_id') end
    local ban = MZBan.Bans.GetByPublicId(publicId)
    if not ban then return result(false, nil, 'not_found') end
    return result(true, { ban = MZBan.Bans.ToPublicDto(ban) })
end

function MZBan.API.ListBans(actorSource, filters, invokingResource)
    local ready, readyError = validateInvocation(invokingResource)
    if not ready then return result(false, nil, readyError) end

    local permission = integrationConfig().Permissions and integrationConfig().Permissions.View
    local allowed, actorOrError = authorize(actorSource, permission)
    if not allowed then return result(false, nil, actorOrError) end

    filters = type(filters) == 'table' and filters or {}
    return result(true, MZBan.Bans.ListPublic({
        active = filters.active == true and true or (filters.active == false and false or nil),
        search = type(filters.search) == 'string' and filters.search or '',
        page = tonumber(filters.page),
        pageSize = tonumber(filters.pageSize)
    }))
end

exports('IsReady', function()
    return MZBan.API.IsReady()
end)

exports('CreateOnlineBan', function(actorSource, targetSource, duration, reason, expectedCitizenId)
    return MZBan.API.CreateOnlineBan(
        actorSource, targetSource, duration, reason, GetInvokingResource(), expectedCitizenId
    )
end)

exports('RevokeBan', function(actorSource, publicId, reason)
    return MZBan.API.RevokeBan(actorSource, publicId, reason, GetInvokingResource())
end)

exports('GetBan', function(actorSource, publicId)
    return MZBan.API.GetBan(actorSource, publicId, GetInvokingResource())
end)

exports('ListBans', function(actorSource, filters)
    return MZBan.API.ListBans(actorSource, filters, GetInvokingResource())
end)
