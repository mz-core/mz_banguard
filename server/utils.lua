MZBan = MZBan or {}

function MZBan.Log(...)
    if Config.Debug then
        print('[mz_banguard]', ...)
    end
end

function MZBan.AuditPrint(...)
    if Config.Audit and Config.Audit.PrintToConsole then
        print('[mz_banguard:audit]', ...)
    end
end

function MZBan.JsonEncode(data)
    return json.encode(data or {})
end

function MZBan.JsonDecode(data, fallback)
    if not data or data == '' then return fallback or {} end
    local ok, decoded = pcall(json.decode, data)
    if ok and decoded then return decoded end
    return fallback or {}
end

function MZBan.Now()
    return os.time()
end

function MZBan.Uuid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 15) or math.random(8, 11)
        return string.format('%x', v)
    end)
end

function MZBan.PublicId()
    local chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    local out = 'MBG-'
    for i = 1, 6 do
        local idx = math.random(1, #chars)
        out = out .. chars:sub(idx, idx)
    end
    return out
end

function MZBan.HasPermission(src, perm)
    if src == 0 then return true end
    if IsPlayerAceAllowed(src, Config.Permissions.Admin) then return true end
    return IsPlayerAceAllowed(src, perm)
end

function MZBan.Notify(src, message)
    if src == 0 then
        print(message)
        return
    end

    TriggerClientEvent('chat:addMessage', src, {
        color = { 255, 80, 100 },
        multiline = true,
        args = { 'MZ BanGuard', message }
    })
end

function MZBan.ParseDuration(input)
    if not input or input == '' then
        return nil, 'perm'
    end

    input = string.lower(tostring(input))

    if input == 'perm' or input == 'perma' or input == 'permanent' then
        return nil, 'perm'
    end

    local amount, unit = input:match('^(%d+)([mhd])$')
    amount = tonumber(amount)

    if not amount or not unit then
        return false, 'invalid'
    end

    local seconds = 0
    if unit == 'm' then seconds = amount * 60 end
    if unit == 'h' then seconds = amount * 60 * 60 end
    if unit == 'd' then seconds = amount * 60 * 60 * 24 end

    return MZBan.Now() + seconds, input
end

function MZBan.FormatExpiry(expiresAt)
    if not expiresAt then return 'Nunca' end
    local remaining = tonumber(expiresAt) - MZBan.Now()
    if remaining <= 0 then return 'Expirado' end
    local days = math.floor(remaining / 86400)
    local hours = math.floor((remaining % 86400) / 3600)
    local minutes = math.floor((remaining % 3600) / 60)

    if days > 0 then
        return string.format('%dd %dh', days, hours)
    end

    if hours > 0 then
        return string.format('%dh %dm', hours, minutes)
    end

    return string.format('%dm', minutes)
end

function MZBan.TableCount(t)
    local c = 0
    for _ in pairs(t or {}) do c = c + 1 end
    return c
end

function MZBan.Truncate(value, maxLen)
    value = tostring(value or '')
    maxLen = tonumber(maxLen) or 255
    if #value <= maxLen then return value end
    return value:sub(1, maxLen)
end

function MZBan.Redact(value)
    value = tostring(value or '')
    if value == '' then return '' end
    if not Config.Privacy or not Config.Privacy.RedactIdentifiersInOutput then return value end
    if #value <= 14 then return value:sub(1, 4) .. '***' end
    return value:sub(1, 10) .. '...' .. value:sub(-4)
end

function MZBan.IsoUtc(timestamp)
    if not timestamp then return nil end
    return os.date('!%Y-%m-%dT%H:%M:%SZ', tonumber(timestamp))
end

function MZBan.CopyTable(input)
    local out = {}
    for k, v in pairs(input or {}) do
        if type(v) == 'table' then out[k] = MZBan.CopyTable(v) else out[k] = v end
    end
    return out
end

function MZBan.SafePlayerName(src)
    if src == 0 then return 'console' end
    return GetPlayerName(src) or ('source:' .. tostring(src))
end

math.randomseed(os.time() + GetGameTimer())
