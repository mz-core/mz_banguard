MZBan = MZBan or {}

local function joinArgs(args, startIndex)
    local parts = {}
    for i = startIndex, #args do
        parts[#parts + 1] = args[i]
    end
    return table.concat(parts, ' ')
end

local function legacyConfig()
    return type(Config.LegacyCommands) == 'table' and Config.LegacyCommands or {}
end

local function isOwner(src)
    if src == 0 then return true end
    local allowed = IsPlayerAceAllowed(src, tostring(legacyConfig().OwnerAce or 'group.mz_owner'))
    return allowed == true or allowed == 1 or tostring(allowed):lower() == 'true'
end

local function legacyEntryAllowed(src, permission)
    if src == 0 or isOwner(src) then return true end
    if legacyConfig().RequireLegacyAceForPlayers ~= true then return true end
    return MZBan.HasPermission(src, permission)
end

local function sanitizePublicId(value)
    if type(value) ~= 'string' then return nil end
    value = value:upper():gsub('%s+', '')
    if not value:match('^MBG%-[A-HJ-NP-Z2-9][A-HJ-NP-Z2-9][A-HJ-NP-Z2-9][A-HJ-NP-Z2-9][A-HJ-NP-Z2-9][A-HJ-NP-Z2-9]$') then
        return nil
    end
    return value
end

local function corePermission(src, permission)
    if src == 0 then return true end
    local coreResource = tostring(Config.Integration and Config.Integration.CoreResource or 'mz_core')
    if GetResourceState(coreResource) ~= 'started' then return false, 'core_unavailable' end
    local ok, allowed = pcall(function()
        return exports[coreResource]:HasGlobalPermission(src, permission)
    end)
    if not ok then return false, 'authorization_unavailable' end
    return allowed == true, allowed == true and nil or 'permission_denied'
end

local function resolveCitizenId(sourceId)
    local coreResource = tostring(Config.Integration and Config.Integration.CoreResource or 'mz_core')
    if GetResourceState(coreResource) ~= 'started' then return nil end
    local ok, identity = pcall(function()
        return exports[coreResource]:ResolvePlayerIdentity(sourceId)
    end)
    if not ok or type(identity) ~= 'table' or identity.ok ~= true then return nil end
    local citizenid = tostring(identity.citizenid or ''):gsub('%c', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if citizenid == '' then return nil end
    return citizenid:sub(1, 64)
end

local function hierarchyAllowed(src, target)
    if src == 0 then return true end
    if tonumber(src) == tonumber(target) then return false, 'self_target' end
    local coreResource = tostring(Config.Integration and Config.Integration.CoreResource or 'mz_core')
    if GetResourceState(coreResource) ~= 'started' then return false, 'core_unavailable' end
    local ok, allowed, reason = pcall(function()
        return exports[coreResource]:CanStaffActOnPlayer(src, target)
    end)
    if not ok then return false, 'hierarchy_unavailable' end
    return allowed == true, allowed == true and nil or (reason or 'hierarchy_denied')
end

local function legacyStaffAllowed(src, acePermission, globalPermission)
    if src == 0 or isOwner(src) then return true end
    local allowed, permissionError = corePermission(src, globalPermission)
    if not allowed then return false, permissionError end
    if not legacyEntryAllowed(src, acePermission) then return false, 'legacy_ace_denied' end
    return true
end

local function readHierarchyAllowed(src, target)
    if src == 0 or isOwner(src) or tonumber(src) == tonumber(target) then return true end
    return hierarchyAllowed(src, target)
end

local function integrationErrorMessage(err)
    local messages = {
        legacy_ace_denied = Config.Messages.StaffNoPerm,
        permission_denied = 'Permissão Staff global ausente.',
        core_unavailable = 'MZ Core indisponível.',
        authorization_unavailable = 'Autorização Staff indisponível.',
        hierarchy_unavailable = 'Hierarquia Staff indisponível.',
        hierarchy_denied = 'Ação negada pela hierarquia Staff.',
        target_owner = 'O Staff Supremo está protegido.',
        target_higher_or_equal = 'Você não pode agir sobre Staff igual ou superior.',
        self_target = 'Você não pode agir sobre si mesmo.',
        invalid_target = Config.Messages.InvalidTarget,
        invalid_duration = 'Duração inválida. Use perm, Nm, Nh ou Nd.',
        duration_too_long = 'Duração acima do limite permitido.',
        invalid_reason = 'Informe um motivo com pelo menos 3 caracteres.',
        invalid_public_id = 'Public ID inválido.',
        not_found = Config.Messages.BanNotFound,
        already_revoked = Config.Messages.BanAlreadyRevoked,
        expired = Config.Messages.BanExpired,
        persistence_failed = 'Falha de persistência. Ação cancelada.'
    }
    return messages[tostring(err or '')] or ('Ação negada: ' .. tostring(err or 'erro desconhecido'))
end

local function createConsoleBan(target, durationArg, reason)
    local expiresAt, parsed = MZBan.ParseDuration(durationArg)
    if expiresAt == false then return nil, 'invalid_duration' end
    if #reason < 3 then return nil, 'invalid_reason' end

    local targetName = GetPlayerName(target)
    local identifiers = MZBan.GetIdentifiers(target, { includeIp = Config.Privacy.StoreIpLocal == true })
    local tokens = MZBan.GetPlayerTokensSafe(target)
    local requiredOk, missingType = MZBan.HasRequiredIdentifiers(identifiers)
    if not requiredOk then return nil, 'missing_identifier:' .. tostring(missingType) end

    local score = MZBan.Flags.GetScore(target)
    local flags = MZBan.DB.GetRecentFlags(MZBan.GetPrimaryIdentifier(identifiers), 8)
    local targetCitizenId = resolveCitizenId(target)
    local ban, createError = MZBan.Bans.Create({
        player_name = targetName,
        reason = reason,
        evidence = MZBan.JsonEncode({
            risk_score = score,
            recent_flags = flags,
            target_citizenid = targetCitizenId
        }),
        banned_by = 'console',
        banned_by_identifier = 'console',
        identifiers = identifiers,
        tokens = tokens,
        expires_at = expiresAt
    }, {
        action = 'ban.created.legacy_console',
        actor_source = 0,
        actor_name = 'console',
        target_source = target,
        target_name = targetName,
        meta = {
            reason = reason,
            duration = parsed,
            risk_score = score,
            target_citizenid = targetCitizenId
        }
    })
    if not ban then return nil, createError or 'persistence_failed' end

    MZBan.Webhook.Send('BanCreated', '⛔ Ban criado', ('Código: `%s`'):format(ban.public_id), {
        MZBan.Webhook.Field('Player', ('%s [%s]'):format(targetName, target), true),
        MZBan.Webhook.Field('CitizenID', targetCitizenId or 'Indisponivel', true),
        MZBan.Webhook.Field('Staff', 'console', true),
        MZBan.Webhook.Field('Duração', parsed, true),
        MZBan.Webhook.Field('Motivo', reason, false),
        MZBan.Webhook.Field('Score', tostring(score), true)
    }, 'danger')
    CreateThread(function() MZBan.Cloud.ReportBan(ban) end)
    DropPlayer(target, MZBan.Bans.FormatKickMessage(ban))
    return ban
end

local function revokeConsoleBan(publicId, reason)
    publicId = sanitizePublicId(publicId)
    if not publicId then return nil, 'invalid_public_id' end
    if #reason < 3 then return nil, 'invalid_reason' end

    local actorName = 'console'
    local ok, banOrError = MZBan.Bans.Revoke(publicId, actorName, reason, {
        action = 'ban.revoked.legacy_console',
        actor_source = 0,
        actor_name = actorName,
        meta = {
            reason = reason
        }
    })
    if not ok then return nil, banOrError end
    local ban = banOrError

    MZBan.Webhook.Send('BanRevoked', 'Ban revogado', ('Codigo local: `%s`'):format(publicId), {
        MZBan.Webhook.Field('Staff', actorName, true),
        MZBan.Webhook.Field('Cloud ID', ban.cloud_ban_id or 'N/A', true),
        MZBan.Webhook.Field('Motivo', reason, false)
    }, 'success')

    CreateThread(function()
        MZBan.Cloud.ReportUnban(ban.cloud_ban_id or publicId, actorName, reason)
    end)

    return ban
end

RegisterCommand(Config.Commands.Ban, function(src, args)
    if not legacyEntryAllowed(src, Config.Permissions.Ban) then
        return MZBan.Notify(src, Config.Messages.StaffNoPerm)
    end

    local target = tonumber(args[1] or '')
    if not target or not GetPlayerName(target) then
        return MZBan.Notify(src, Config.Messages.InvalidTarget)
    end

    local durationArg = args[2] or ''
    local reason = joinArgs(args, 3)
    if durationArg == '' or #reason < 3 then
        return MZBan.Notify(src, Config.Messages.InvalidUsageBan)
    end

    if src == 0 then
        local ban, err = createConsoleBan(target, durationArg, reason)
        if not ban then return MZBan.Notify(src, integrationErrorMessage(err)) end
        return MZBan.Notify(src, string.format(Config.Messages.BanCreated, ban.public_id))
    end

    local response = MZBan.API.CreateOnlineBan(src, target, durationArg, reason, 'mz_banguard')
    if type(response) ~= 'table' or response.ok ~= true then
        return MZBan.Notify(src, integrationErrorMessage(response and response.error))
    end
    MZBan.Notify(src, string.format(Config.Messages.BanCreated, response.data.ban.publicId))
end, false)

RegisterCommand(Config.Commands.Unban, function(src, args)
    if not legacyEntryAllowed(src, Config.Permissions.Unban) then
        return MZBan.Notify(src, Config.Messages.StaffNoPerm)
    end

    local publicId = sanitizePublicId(args[1])
    if not publicId then
        return MZBan.Notify(src, Config.Messages.InvalidUsageUnban)
    end

    local reason = joinArgs(args, 2)
    if #reason < 3 then return MZBan.Notify(src, Config.Messages.InvalidUsageUnban) end

    if src == 0 then
        local ban, err = revokeConsoleBan(publicId, reason)
        if not ban then return MZBan.Notify(src, integrationErrorMessage(err)) end
        return MZBan.Notify(src, string.format(Config.Messages.BanRevoked, publicId))
    end

    local response = MZBan.API.RevokeBan(src, publicId, reason, 'mz_banguard')
    if type(response) ~= 'table' or response.ok ~= true then
        return MZBan.Notify(src, integrationErrorMessage(response and response.error))
    end
    MZBan.Notify(src, string.format(Config.Messages.BanRevoked, publicId))
end, false)

RegisterCommand(Config.Commands.Info, function(src, args)
    local allowed, permissionError = legacyStaffAllowed(
        src,
        Config.Permissions.Lookup,
        Config.Integration.Permissions.View
    )
    if not allowed then return MZBan.Notify(src, integrationErrorMessage(permissionError)) end

    local target = tonumber(args[1] or '')
    if not target or not GetPlayerName(target) then
        return MZBan.Notify(src, Config.Messages.InvalidTarget)
    end

    local hierarchyOk, hierarchyError = readHierarchyAllowed(src, target)
    if not hierarchyOk then return MZBan.Notify(src, integrationErrorMessage(hierarchyError)) end

    local identifiers = MZBan.GetIdentifiers(target, { includeIp = Config.Privacy.StoreIpLocal == true })
    local tokens = MZBan.GetPlayerTokensSafe(target)
    local localBan = MZBan.Bans.CheckLocal(identifiers, tokens)
    local score = MZBan.Flags.GetScore(target)
    local targetCitizenId = resolveCitizenId(target)

    if localBan then
        MZBan.Notify(src, ('Ban local encontrado: %s | CID: %s | Motivo: %s | Match: %s | Score: %s'):format(
            localBan.public_id,
            targetCitizenId or 'indisponivel',
            localBan.reason or 'N/A',
            localBan.match_type or 'N/A',
            tostring(score)
        ))
    else
        MZBan.Notify(src, 'Nenhum ban local ativo encontrado. Score atual: ' .. tostring(score))
    end

    if Config.Cloud.Enabled then
        CreateThread(function()
            local cloud = MZBan.Cloud.CheckPlayer(target, GetPlayerName(target), identifiers)
            if cloud then
                MZBan.Notify(src, ('Cloud: action=%s risk=%s profile=%s'):format(
                    tostring(cloud.action),
                    tostring(cloud.risk_score),
                    tostring(cloud.profile_id)
                ))
            else
                MZBan.Notify(src, 'Cloud: consulta falhou, cache/cooldown ativo ou desativada.')
            end
        end)
    end
end, false)

RegisterCommand(Config.Commands.Flags, function(src, args)
    local allowed, permissionError = legacyStaffAllowed(
        src,
        Config.Permissions.Lookup,
        Config.Integration.Permissions.View
    )
    if not allowed then return MZBan.Notify(src, integrationErrorMessage(permissionError)) end

    local target = tonumber(args[1] or '')
    if not target or not GetPlayerName(target) then
        return MZBan.Notify(src, Config.Messages.InvalidTarget)
    end

    local hierarchyOk, hierarchyError = readHierarchyAllowed(src, target)
    if not hierarchyOk then return MZBan.Notify(src, integrationErrorMessage(hierarchyError)) end

    local identifiers = MZBan.GetIdentifiers(target, { includeIp = false })
    local primary = MZBan.GetPrimaryIdentifier(identifiers)
    if not primary then return MZBan.Notify(src, 'Identifier principal não encontrado.') end

    local flags = MZBan.DB.GetRecentFlags(primary, 8)
    local msg = ('Flags recentes de %s | CID: %s | Score atual: %s'):format(
        GetPlayerName(target),
        resolveCitizenId(target) or 'indisponivel',
        MZBan.Flags.GetScore(target)
    )

    for _, flag in ipairs(flags) do
        msg = msg .. ('\n- %s | +%s | score %s | %s'):format(
            flag.reason or 'N/A',
            tostring(flag.points or 0),
            tostring(flag.score_after or 0),
            os.date('%d/%m %H:%M', tonumber(flag.created_at or 0) or 0)
        )
    end

    MZBan.Notify(src, msg)
end, false)

RegisterCommand(Config.Commands.Lookup, function(src, args)
    if not legacyEntryAllowed(src, Config.Permissions.Lookup) then
        return MZBan.Notify(src, Config.Messages.StaffNoPerm)
    end
    if src > 0 and legacyConfig().IdentifierLookupOwnerOnly ~= false and not isOwner(src) then
        return MZBan.Notify(src, Config.Messages.StaffNoPerm)
    end
    if src > 0 and legacyConfig().IdentifierLookupOwnerOnly == false then
        local allowed, permissionError = legacyStaffAllowed(
            src,
            Config.Permissions.Lookup,
            Config.Integration.Permissions.View
        )
        if not allowed then return MZBan.Notify(src, integrationErrorMessage(permissionError)) end
    end

    local identifierType = type(args[1]) == 'string' and args[1]:lower() or nil
    local value = type(args[2]) == 'string' and args[2]:lower() or nil

    if not identifierType or not value
        or not identifierType:match('^[a-z0-9_]+$')
        or #identifierType > 24
        or #value > 256
    then
        return MZBan.Notify(src, Config.Messages.InvalidUsageLookup)
    end

    local ban = MySQL.single.await(
        [[SELECT b.*
          FROM mz_ban_identifiers bi
          INNER JOIN mz_bans b ON b.id = bi.ban_id
          WHERE bi.identifier_type = ?
            AND bi.identifier_value = ?
            AND bi.active = 1
            AND b.active = 1
          ORDER BY b.created_at DESC
          LIMIT 1]],
        { identifierType, value }
    )

    if not ban then
        return MZBan.Notify(src, 'Nenhum ban local ativo encontrado para esse identifier.')
    end

    local dto = MZBan.Bans.ToPublicDto(ban)
    MZBan.Notify(src, ('Ban local: %s | Player: %s | CID: %s | Motivo: %s | Expira: %s'):format(
        ban.public_id,
        ban.player_name or 'N/A',
        dto and dto.citizenId or 'indisponivel',
        ban.reason or 'N/A',
        MZBan.FormatExpiry(ban.expires_at)
    ))
end, false)
