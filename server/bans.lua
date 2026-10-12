MZBan = MZBan or {}
MZBan.Bans = {}

local function isExpired(ban)
    return ban and ban.expires_at and tonumber(ban.expires_at) and tonumber(ban.expires_at) <= MZBan.Now()
end

local function isActiveValue(value)
    if value == true then return true end
    if value == false or value == nil then return false end
    if tonumber(value) == 1 then return true end
    local normalized = tostring(value):lower()
    return normalized == 'true' or normalized == 'yes'
end

function MZBan.Bans.IsActive(ban)
    return type(ban) == 'table' and isActiveValue(ban.active)
end

function MZBan.Bans.GetByPublicId(publicId)
    return MySQL.single.await(
        'SELECT * FROM mz_bans WHERE public_id = ? LIMIT 1',
        { publicId }
    )
end

function MZBan.Bans.FindActiveByIncidentId(incidentId)
    incidentId = tostring(incidentId or ''):gsub('[^%w%-]', ''):sub(1, 64)
    if incidentId == '' then return nil end
    return MySQL.single.await([[
        SELECT * FROM mz_bans
        WHERE active = 1 AND evidence LIKE ?
        ORDER BY created_at DESC LIMIT 1
    ]], { '%"incident_id":"' .. incidentId .. '"%' })
end

function MZBan.Bans.ToPublicDto(ban)
    if type(ban) ~= 'table' then return nil end
    local evidence = ban.evidence
    if type(evidence) ~= 'table' then
        evidence = type(MZBan.JsonDecode) == 'function'
            and MZBan.JsonDecode(evidence, {})
            or {}
    end
    return {
        publicId = ban.public_id,
        playerName = ban.player_name,
        citizenId = type(evidence) == 'table' and evidence.target_citizenid or nil,
        reason = ban.reason,
        bannedBy = ban.banned_by,
        expiresAt = tonumber(ban.expires_at),
        active = MZBan.Bans.IsActive(ban),
        createdAt = tonumber(ban.created_at),
        updatedAt = tonumber(ban.updated_at),
        revokedAt = tonumber(ban.revoked_at),
        revokedBy = ban.revoked_by,
        revokeReason = ban.revoke_reason
    }
end

function MZBan.Bans.ListPublic(filters)
    filters = type(filters) == 'table' and filters or {}
    local limits = Config.Integration and Config.Integration.Limits or {}
    local maxPageSize = math.max(1, tonumber(limits.MaxPageSize) or 50)
    local defaultPageSize = math.max(1, tonumber(limits.PageSize) or 25)
    local page = math.max(1, math.floor(tonumber(filters.page) or 1))
    local pageSize = math.min(maxPageSize, math.max(1, math.floor(tonumber(filters.pageSize) or defaultPageSize)))
    local offset = (page - 1) * pageSize
    local clauses = {}
    local parameters = {}

    if filters.active == true or filters.active == false then
        clauses[#clauses + 1] = 'active = ?'
        parameters[#parameters + 1] = filters.active and 1 or 0
    end

    local search = type(filters.search) == 'string' and filters.search:gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '') or ''
    if search ~= '' then
        search = MZBan.Truncate(search, 80)
        clauses[#clauses + 1] = '(public_id LIKE ? OR player_name LIKE ? OR evidence LIKE ?)'
        parameters[#parameters + 1] = '%' .. search .. '%'
        parameters[#parameters + 1] = '%' .. search .. '%'
        parameters[#parameters + 1] = '%' .. search .. '%'
    end

    local where = #clauses > 0 and (' WHERE ' .. table.concat(clauses, ' AND ')) or ''
    local countRow = MySQL.single.await('SELECT COUNT(1) AS total FROM mz_bans' .. where, parameters)
    local queryParameters = {}
    for i = 1, #parameters do queryParameters[i] = parameters[i] end
    queryParameters[#queryParameters + 1] = pageSize
    queryParameters[#queryParameters + 1] = offset

    local rows = MySQL.query.await([[
        SELECT public_id, player_name, reason, evidence, banned_by, expires_at, active,
               created_at, updated_at, revoked_at, revoked_by, revoke_reason
        FROM mz_bans
    ]] .. where .. [[
        ORDER BY created_at DESC, public_id DESC
        LIMIT ? OFFSET ?
    ]], queryParameters) or {}

    local items = {}
    for _, row in ipairs(rows) do
        items[#items + 1] = MZBan.Bans.ToPublicDto(row)
    end

    return {
        items = items,
        total = tonumber(countRow and countRow.total) or 0,
        page = page,
        pageSize = pageSize
    }
end

function MZBan.Bans.Revoke(publicId, revokedBy, reason, audit)
    local ban = MZBan.Bans.GetByPublicId(publicId)
    if not ban then return false, 'not_found' end
    if not MZBan.Bans.IsActive(ban) then
        if tostring(ban.revoke_reason or ''):lower() == 'expired' or isExpired(ban) then
            return false, 'expired', ban
        end
        return false, 'already_revoked', ban
    end

    local now = MZBan.Now()
    local statements = {
        {
            query = [[UPDATE mz_bans
                SET active = 0, revoked_at = ?, revoked_by = ?, revoke_reason = ?, updated_at = ?
                WHERE id = ? AND active = 1]],
            parameters = { now, revokedBy, reason, now, ban.id }
        },
        {
            query = 'UPDATE mz_ban_identifiers SET active = 0 WHERE ban_id = ?',
            parameters = { ban.id }
        },
        {
            query = 'UPDATE mz_ban_tokens SET active = 0 WHERE ban_id = ?',
            parameters = { ban.id }
        }
    }

    if type(audit) == 'table' then
        statements[#statements + 1] = {
            query = [[INSERT INTO mz_ban_audit
                (action, actor_source, actor_name, target_source, target_name, ban_public_id, meta, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)]],
            parameters = {
                audit.action or 'ban.revoked',
                audit.actor_source,
                audit.actor_name,
                audit.target_source,
                audit.target_name or ban.player_name,
                publicId,
                MZBan.JsonEncode(audit.meta or {}),
                now
            }
        }
    end

    if MySQL.transaction.await(statements) ~= true then
        return false, 'persistence_failed'
    end

    if type(audit) == 'table' then
        MZBan.AuditPrint(audit.action or 'ban.revoked', publicId, ban.player_name or '')
    end

    return true, ban
end

function MZBan.Bans.ExpireIfNeeded(ban)
    if not isExpired(ban) then return false end

    if Config.Local.CleanExpiredOnCheck then
        MZBan.Bans.Revoke(ban.public_id, 'system', 'expired')
    end

    return true
end

function MZBan.Bans.Create(data, audit)
    local id = MZBan.Uuid()
    local publicId = MZBan.PublicId()
    local now = MZBan.Now()
    local tokens = Config.Privacy.StoreTokensLocal and (data.tokens or {}) or {}

    local ban = {
        id = id,
        public_id = publicId,
        player_name = data.player_name,
        reason = MZBan.Truncate(data.reason, 2000),
        evidence = data.evidence and MZBan.Truncate(data.evidence, 5000) or nil,
        banned_by = data.banned_by,
        banned_by_identifier = data.banned_by_identifier,
        identifiers = data.identifiers.byType or {},
        tokens = tokens,
        expires_at = data.expires_at,
        active = 1,
        created_at = now,
        updated_at = now
    }

    local statements = {
        {
            query = [[INSERT INTO mz_bans
                (id, public_id, player_name, reason, evidence, banned_by, banned_by_identifier, identifiers, tokens,
                 expires_at, active, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)]],
            parameters = {
                id,
                publicId,
                ban.player_name,
                ban.reason,
                ban.evidence,
                ban.banned_by,
                ban.banned_by_identifier,
                MZBan.JsonEncode(ban.identifiers),
                MZBan.JsonEncode(ban.tokens),
                ban.expires_at,
                now,
                now
            }
        }
    }

    for identifierType, value in pairs(ban.identifiers) do
        statements[#statements + 1] = {
            query = [[INSERT IGNORE INTO mz_ban_identifiers
                (ban_id, identifier_type, identifier_value, active, created_at)
                VALUES (?, ?, ?, 1, ?)]],
            parameters = { id, identifierType, value, now }
        }
    end

    for _, token in ipairs(ban.tokens) do
        statements[#statements + 1] = {
            query = [[INSERT IGNORE INTO mz_ban_tokens
                (ban_id, token_value, active, created_at)
                VALUES (?, ?, 1, ?)]],
            parameters = { id, token, now }
        }
    end

    if type(audit) == 'table' then
        statements[#statements + 1] = {
            query = [[INSERT INTO mz_ban_audit
                (action, actor_source, actor_name, target_source, target_name, ban_public_id, meta, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)]],
            parameters = {
                audit.action or 'ban.created',
                audit.actor_source,
                audit.actor_name,
                audit.target_source,
                audit.target_name or ban.player_name,
                publicId,
                MZBan.JsonEncode(audit.meta or {}),
                now
            }
        }
    end

    if MySQL.transaction.await(statements) ~= true then
        return nil, 'persistence_failed'
    end

    if type(audit) == 'table' then
        MZBan.AuditPrint(audit.action or 'ban.created', publicId, ban.player_name or '')
    end

    return ban
end

function MZBan.Bans.CheckLocal(identifiers, tokens)
    if not Config.Local.Enabled then return nil end

    for identifierType, value in pairs(identifiers.byType or {}) do
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

        if ban then
            if not MZBan.Bans.ExpireIfNeeded(ban) then
                ban.match_type = identifierType
                ban.match_value = value
                return ban
            end
        end
    end

    if Config.Local.UsePlayerTokens and Config.Local.TokenMatchAutoBan and Config.Privacy.StoreTokensLocal then
        for _, token in ipairs(tokens or {}) do
            local ban = MySQL.single.await(
                [[SELECT b.*
                  FROM mz_ban_tokens bt
                  INNER JOIN mz_bans b ON b.id = bt.ban_id
                  WHERE bt.token_value = ?
                    AND bt.active = 1
                    AND b.active = 1
                  ORDER BY b.created_at DESC
                  LIMIT 1]],
                { token }
            )

            if ban then
                if not MZBan.Bans.ExpireIfNeeded(ban) then
                    ban.match_type = 'token'
                    ban.match_value = token
                    return ban
                end
            end
        end
    end

    return nil
end

function MZBan.Bans.FormatKickMessage(ban)
    return string.format(
        Config.Messages.LocalBan,
        ban.public_id or 'N/A',
        ban.reason or 'Sem motivo informado',
        MZBan.FormatExpiry(ban.expires_at)
    )
end
