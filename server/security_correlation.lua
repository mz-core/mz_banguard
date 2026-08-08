MZBan = MZBan or {}
MZBan.Correlation = MZBan.Correlation or {}

local timelines = {}
local sequence = 0

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
    local ttl = math.max(10000, math.floor(tonumber(config().ttlMs) or 120000))
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
    local maximum = math.max(4, math.floor(tonumber(config().maxEntriesPerPlayer) or 32))
    while #entries > maximum do table.remove(entries, 1) end
    return entry.id
end

function MZBan.Correlation.Snapshot(sourceId, limit)
    sourceId = normalizeSource(sourceId)
    if not sourceId then return {} end
    prune(sourceId, nowMs())
    local entries = timelines[sourceId] or {}
    limit = math.max(1, math.min(32, math.floor(tonumber(limit) or 12)))
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

AddEventHandler('playerDropped', function() MZBan.Correlation.Clear(source) end)

CreateThread(function()
    while true do
        Wait(30000)
        local currentMs = nowMs()
        for sourceId in pairs(timelines) do prune(sourceId, currentMs) end
    end
end)
