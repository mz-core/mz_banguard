MZBan = MZBan or {}
MZBan.EventContracts = MZBan.EventContracts or {}

local contracts = {}
local replayKeys = {}
local stats = { accepted = 0, rejected = 0, replayed = 0 }

local function config()
    return type(Config.EventContracts) == 'table' and Config.EventContracts or {}
end

local function nowMs()
    return math.max(0, math.floor(tonumber(GetGameTimer()) or 0))
end

local function safeName(value)
    value = tostring(value or ''):lower():gsub('%c', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' or #value > 96 or not value:match('^[a-z0-9_.:%-]+$') then return nil end
    return value
end

local function validateValue(value, rule, depth, seen)
    rule = type(rule) == 'table' and rule or {}
    local expected = rule.type
    if value == nil then return rule.required ~= true, rule.required == true and 'required' or nil end
    if expected and type(value) ~= expected then return false, 'invalid_type' end
    if type(value) == 'string' then
        if #value > math.min(tonumber(rule.maxLength) or config().maxString or 256, config().maxString or 256) then return false, 'string_too_long' end
        if rule.pattern and not value:match(rule.pattern) then return false, 'pattern_mismatch' end
    elseif type(value) == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then return false, 'invalid_number' end
        if rule.min and value < rule.min then return false, 'below_minimum' end
        if rule.max and value > rule.max then return false, 'above_maximum' end
    elseif type(value) == 'table' then
        if seen[value] then return false, 'cyclic_payload' end
        if depth >= math.max(1, tonumber(config().maxDepth) or 2) then return false, 'payload_too_deep' end
        seen[value] = true
        local count = 0
        for key in pairs(value) do
            count = count + 1
            if count > math.max(1, tonumber(rule.maxKeys) or tonumber(config().maxPayloadKeys) or 24) then
                seen[value] = nil
                return false, 'too_many_keys'
            end
            if type(key) ~= 'string' and type(key) ~= 'number' then
                seen[value] = nil
                return false, 'invalid_key'
            end
        end
        if type(rule.fields) == 'table' then
            for key, childRule in pairs(rule.fields) do
                local ok, reason = validateValue(value[key], childRule, depth + 1, seen)
                if not ok then seen[value] = nil; return false, tostring(key) .. ':' .. tostring(reason) end
            end
            if rule.allowExtra == false then
                for key in pairs(value) do
                    if rule.fields[key] == nil then seen[value] = nil; return false, 'unexpected_field:' .. tostring(key) end
                end
            end
        end
        seen[value] = nil
    end
    return true
end

function MZBan.EventContracts.Register(name, definition)
    name = safeName(name)
    if not name or type(definition) ~= 'table' then return false, 'invalid_contract' end
    contracts[name] = definition
    return true
end

local function reject(sourceId, name, reason)
    stats.rejected = stats.rejected + 1
    if MZBan.DetectorHealth then MZBan.DetectorHealth.Discard('event_contracts', reason) end
    if MZBan.Correlation then
        MZBan.Correlation.Record(sourceId, 'event_contract.rejected', { contract = name, reason = reason })
    end
    return false, reason
end

function MZBan.EventContracts.Validate(name, sourceId, payload, context)
    if config().enabled ~= true then return true end
    name = safeName(name)
    sourceId = tonumber(sourceId)
    local definition = name and contracts[name] or nil
    if not definition then return reject(sourceId, name or 'invalid', 'contract_not_found') end
    if definition.sourceOnline == true and (not sourceId or sourceId <= 0 or GetPlayerPing(math.floor(sourceId)) <= 0) then
        return reject(sourceId, name, 'source_not_online')
    end
    local ok, reason = validateValue(payload, definition.schema or { type = 'table' }, 0, {})
    if not ok then return reject(sourceId, name, reason) end

    if definition.replayField then
        local replayValue = type(payload) == 'table' and payload[definition.replayField] or nil
        if replayValue == nil then return reject(sourceId, name, 'missing_replay_key') end
        local key = table.concat({ tostring(context and context.resource or 'internal'), tostring(sourceId), name, tostring(replayValue) }, ':')
        local currentMs = nowMs()
        if replayKeys[key] and replayKeys[key] > currentMs then
            stats.replayed = stats.replayed + 1
            return reject(sourceId, name, 'replay_detected')
        end
        replayKeys[key] = currentMs + math.max(1000, tonumber(definition.replayTtlMs) or tonumber(config().replayTtlMs) or 60000)
    end

    stats.accepted = stats.accepted + 1
    if MZBan.DetectorHealth then MZBan.DetectorHealth.Seen('event_contracts') end
    return true
end

function MZBan.EventContracts.Status()
    local count = 0
    for _ in pairs(contracts) do count = count + 1 end
    return { enabled = config().enabled == true, contracts = count, accepted = stats.accepted, rejected = stats.rejected, replayed = stats.replayed }
end

MZBan.EventContracts.Register('security.telemetry', {
    sourceOnline = true,
    schema = {
        type = 'table', allowExtra = false,
        fields = {
            code = { type = 'string', required = true, maxLength = 64, pattern = '^[a-z0-9_]+$' },
            payload = { type = 'table', required = false, maxKeys = 12 }
        }
    }
})

for name, definition in pairs(type(config().contracts) == 'table' and config().contracts or {}) do
    MZBan.EventContracts.Register(name, definition)
end

exports('ValidateEventContract', function(sourceId, name, payload)
    local resource = GetInvokingResource()
    local trusted = type(config().trustedResources) == 'table' and config().trustedResources or {}
    if type(resource) ~= 'string' or trusted[resource] ~= true then return false, 'untrusted_resource' end
    return MZBan.EventContracts.Validate(name, sourceId, payload, { resource = resource })
end)

CreateThread(function()
    while true do
        Wait(math.max(1000, math.floor(tonumber(config().cleanupIntervalMs) or 10000)))
        local currentMs = nowMs()
        for key, expiresAt in pairs(replayKeys) do if expiresAt <= currentMs then replayKeys[key] = nil end end
    end
end)
