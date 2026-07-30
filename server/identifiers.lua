MZBan = MZBan or {}

local function parseIdentifier(identifier)
    if type(identifier) ~= 'string' then return nil end
    local identifierType, value = identifier:match('^([^:]+):(.+)$')
    if not identifierType or not value then return nil end

    identifierType = string.lower(identifierType)
    if not Config.Identifiers.Include[identifierType] then return nil end

    return identifierType, string.lower(identifier)
end

function MZBan.GetIdentifiers(src, options)
    options = options or {}

    local byType = {}
    local raw = {}

    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        local identifierType, normalized = parseIdentifier(identifier)
        if identifierType and normalized then
            if identifierType ~= 'ip' or options.includeIp == true then
                byType[identifierType] = normalized
                raw[#raw + 1] = normalized
            end
        end
    end

    return {
        byType = byType,
        raw = raw
    }
end

function MZBan.HasRequiredIdentifiers(identifiers)
    for identifierType, required in pairs(Config.Identifiers.RequiredForJoin or {}) do
        if required and not identifiers.byType[identifierType] then
            return false, identifierType
        end
    end

    return true
end

function MZBan.GetPlayerTokensSafe(src)
    local tokens = {}

    if not Config.Local.UsePlayerTokens then
        return tokens
    end

    if type(GetNumPlayerTokens) ~= 'function' or type(GetPlayerToken) ~= 'function' then
        return tokens
    end

    local ok, count = pcall(GetNumPlayerTokens, src)
    if not ok or not count then
        return tokens
    end

    for i = 0, count - 1 do
        local okToken, token = pcall(GetPlayerToken, src, i)
        if okToken and token and token ~= '' then
            tokens[#tokens + 1] = token
        end
    end

    return tokens
end

function MZBan.GetPrimaryIdentifier(identifiers)
    if identifiers.byType.license then return identifiers.byType.license end
    if identifiers.byType.license2 then return identifiers.byType.license2 end
    if identifiers.byType.fivem then return identifiers.byType.fivem end
    if identifiers.byType.discord then return identifiers.byType.discord end
    return identifiers.raw[1]
end

function MZBan.GetActorIdentifier(src)
    if src == 0 then return 'console' end
    local identifiers = MZBan.GetIdentifiers(src, { includeIp = false })
    return MZBan.GetPrimaryIdentifier(identifiers) or ('source:' .. tostring(src))
end
