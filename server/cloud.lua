MZBan = MZBan or {}
MZBan.Cloud = MZBan.Cloud or {}

local checkCache = {}
local failureUntil = 0

local function cacheKeyFromIdentifiers(identifiers)
    return MZBan.GetPrimaryIdentifier(identifiers) or MZBan.JsonEncode(identifiers.byType or {})
end

local function request(method, path, payload)
    if not Config.Cloud.Enabled then
        return nil, 'cloud_disabled'
    end

    if failureUntil > MZBan.Now() then
        return nil, 'cloud_failure_cooldown'
    end

    local url = string.gsub(Config.Cloud.BaseUrl or '', '/+$', '') .. path
    local p = promise.new()
    local settled = false
    local timeoutMs = tonumber(Config.Cloud.TimeoutMs or 5000) or 5000

    SetTimeout(timeoutMs, function()
        if settled then return end
        settled = true
        p:resolve({ timeout = true })
    end)

    PerformHttpRequest(url, function(statusCode, body, headers, errorData)
        if settled then return end
        settled = true
        p:resolve({
            statusCode = statusCode or 0,
            body = body,
            headers = headers,
            errorData = errorData
        })
    end, method, payload and MZBan.JsonEncode(payload) or '', {
        ['Content-Type'] = 'application/json',
        ['x-api-key'] = Config.Cloud.ApiKey
    }, {
        followLocation = true
    })

    local response = Citizen.Await(p)

    if not response then
        return nil, 'no_response'
    end

    if response.timeout then
        failureUntil = MZBan.Now() + (tonumber(Config.Cloud.FailureCooldownSec or 60) or 60)
        return nil, 'timeout'
    end

    if response.statusCode < 200 or response.statusCode >= 300 then
        if response.statusCode == 0 or response.statusCode >= 500 then
            failureUntil = MZBan.Now() + (tonumber(Config.Cloud.FailureCooldownSec or 60) or 60)
        end
        return nil, ('http_' .. tostring(response.statusCode)), response.body
    end

    local decoded = MZBan.JsonDecode(response.body, nil)
    if not decoded then
        return nil, 'invalid_json'
    end

    return decoded, nil, response.body
end

local function identifiersForCloud(identifiers)
    local out = { byType = {} }

    for identifierType, value in pairs(identifiers.byType or {}) do
        if identifierType ~= 'ip' or Config.Cloud.SendIpToCloud then
            out.byType[identifierType] = value
        end
    end

    return out
end

function MZBan.Cloud.CheckPlayer(src, playerName, identifiers)
    if not Config.Cloud.Enabled then return nil end

    local key = cacheKeyFromIdentifiers(identifiers)
    local cached = key and checkCache[key]
    if cached and cached.expires_at > MZBan.Now() then
        return cached.data
    end

    local payload = {
        player_name = playerName,
        identifiers = identifiersForCloud(identifiers)
    }

    local response, err, raw = request('POST', '/v1/player/check', payload)
    if err then
        MZBan.Log('Cloud check failed:', err, raw or '')
        return nil, err
    end

    if key then
        checkCache[key] = {
            data = response,
            expires_at = MZBan.Now() + (tonumber(Config.Cloud.CacheTtlSec or 300) or 300)
        }
    end

    return response
end

function MZBan.Cloud.ReportSeen(src, playerName, identifiers)
    if not Config.Cloud.Enabled then return nil end

    local payload = {
        player_name = playerName,
        identifiers = identifiersForCloud(identifiers)
    }

    local response, err = request('POST', '/v1/player/seen', payload)
    if err then
        MZBan.Log('Cloud seen failed:', err)
        return nil, err
    end

    return response
end

function MZBan.Cloud.ReportBan(ban)
    if not Config.Cloud.Enabled or not Config.Cloud.ReportLocalBans then return nil end

    local cloudEvidence = MZBan.JsonDecode(ban.evidence, {})
    if type(cloudEvidence) == 'table' then
        cloudEvidence.target_citizenid = nil
    end

    local payload = {
        local_ban_id = ban.id,
        player_name = ban.player_name,
        reason = ban.reason,
        evidence = MZBan.JsonEncode(cloudEvidence),
        banned_by = ban.banned_by,
        expires_at = MZBan.IsoUtc(ban.expires_at),
        identifiers = identifiersForCloud({ byType = ban.identifiers or {} }),
        scope = 'network'
    }

    local response, err, raw = request('POST', '/v1/bans', payload)
    if err then
        MZBan.Log('Cloud ban report failed:', err, raw or '')
        return nil, err
    end

    if response and response.ban and response.ban.public_id then
        MySQL.update.await(
            'UPDATE mz_bans SET cloud_ban_id = ?, updated_at = ? WHERE id = ?',
            { response.ban.public_id, MZBan.Now(), ban.id }
        )
    end

    return response
end

function MZBan.Cloud.ReportUnban(cloudPublicId, revokedBy, reason)
    if not Config.Cloud.Enabled or not Config.Cloud.ReportUnbans then return nil end
    if not cloudPublicId or cloudPublicId == '' then return nil, 'missing_cloud_public_id' end

    local response, err, raw = request('POST', '/v1/bans/' .. tostring(cloudPublicId) .. '/revoke', {
        revoked_by = revokedBy,
        reason = reason
    })

    if err then
        MZBan.Log('Cloud unban report failed:', err, raw or '')
        return nil, err
    end

    return response
end

function MZBan.Cloud.ReportFlag(flag)
    if not Config.Cloud.Enabled or not Config.Cloud.ReportFlags then return nil end

    local response, err, raw = request('POST', '/v1/flags', flag)
    if err then
        MZBan.Log('Cloud flag report failed:', err, raw or '')
        return nil, err
    end

    return response
end

function MZBan.Cloud.AdminLookup(identifierType, value)
    -- O resource do cliente não tem admin token da cloud por segurança.
    -- Lookup cloud completo deve ser feito no painel central.
    return nil, 'cloud_admin_lookup_only_in_panel'
end
