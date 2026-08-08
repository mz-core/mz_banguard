MZBan = MZBan or {}
MZBan.AimGuard = MZBan.AimGuard or {}

local weaponHashes = {}
local samples = {}

local function config()
    return type(Config.AimGuard) == 'table' and Config.AimGuard or {}
end

local function nowMs()
    return math.max(0, math.floor(tonumber(GetGameTimer()) or 0))
end

local function normalizeHash(value)
    value = tonumber(value)
    if not value then return nil end
    value = math.floor(value)
    if value < 0 then value = value + 4294967296 end
    return value >= 0 and value <= 4294967295 and value or nil
end

local function safeNative(native, fallback, ...)
    local ok, value = pcall(native, ...)
    if not ok or value == nil then return fallback end
    return value
end

local function buildWeapons()
    weaponHashes = {}
    for _, name in ipairs(config().weaponNames or {}) do
        local hash = normalizeHash(joaat(name))
        if hash then weaponHashes[hash] = tostring(name) end
    end
end

local function isHeadComponent(value)
    value = tonumber(value)
    for _, component in ipairs(config().headComponents or {}) do
        if value == tonumber(component) then return true end
    end
    return false
end

local function band(value, thresholds, prefix)
    value = tonumber(value) or 0
    for index, maximum in ipairs(type(thresholds) == 'table' and thresholds or {}) do
        if value <= tonumber(maximum) then return prefix .. tostring(index) end
    end
    return prefix .. 'max'
end

local function coords(entity)
    if not entity or entity == 0 or safeNative(DoesEntityExist, false, entity) ~= true then return nil end
    local value = safeNative(GetEntityCoords, nil, entity)
    if not value then return nil end
    return { x = tonumber(value.x) or 0, y = tonumber(value.y) or 0, z = tonumber(value.z) or 0 }
end

local function entityDistance(left, right)
    local a, b = coords(left), coords(right)
    if not a or not b then return nil end
    local x, y, z = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(x * x + y * y + z * z)
end

local function hitEntity(data)
    local netId = tonumber(data.hitGlobalId)
    if (not netId or netId <= 0) and type(data.hitGlobalIds) == 'table' then netId = tonumber(data.hitGlobalIds[1]) end
    if not netId or netId <= 0 then return 0 end
    return tonumber(safeNative(NetworkGetEntityFromNetworkId, 0, netId)) or 0
end

local function rollover(state, currentMs, window)
    if currentMs - state.startedAt < window then return end
    if state.qualified == true then
        state.qualifiedWindows = state.qualifiedWindows + 1
    else
        state.qualifiedWindows = math.max(0, state.qualifiedWindows - math.max(1, math.floor(tonumber(config().candidateDecayWindows) or 1)))
    end
    state.startedAt = currentMs
    state.hits, state.headshots, state.distanceTotal = 0, 0, 0
    state.qualified, state.alerted = false, false
end

local function observe(sender, data)
    local sourceId = tonumber(sender)
    if config().enabled ~= true or not sourceId or sourceId <= 0 or GetPlayerPing(sourceId) <= 0
        or type(data) ~= 'table' then return false end
    sourceId = math.floor(sourceId)
    local weapon = normalizeHash(data.weaponType)
    if not weapon or not weaponHashes[weapon] then return false end

    local attacker = safeNative(GetPlayerPed, 0, sourceId)
    local victim = hitEntity(data)
    local shotDistance = entityDistance(attacker, victim)
    local distanceBand = band(shotDistance or 0, config().distanceBands, 'd')
    local ping = math.max(0, math.floor(tonumber(GetPlayerPing(sourceId)) or 0))
    local pingBand = band(ping, config().pingBands, 'p')
    local key = ('%d:%u:%s:%s'):format(sourceId, weapon, distanceBand, pingBand)
    local currentMs = nowMs()
    local window = math.max(10000, math.floor(tonumber(config().windowMs) or 60000))
    local state = samples[key]
    if not state then
        state = {
            startedAt = currentMs, hits = 0, headshots = 0, distanceTotal = 0,
            qualified = false, qualifiedWindows = 0, alerted = false
        }
        samples[key] = state
    end
    rollover(state, currentMs, window)
    state.hits = state.hits + 1
    if isHeadComponent(data.hitComponent) then state.headshots = state.headshots + 1 end
    state.distanceTotal = state.distanceTotal + (shotDistance or 0)

    local minimumHits = math.max(5, math.floor(tonumber(config().minimumHits) or 12))
    local minimumHeadshots = math.max(3, math.floor(tonumber(config().minimumHeadshots) or 10))
    local ratioLimit = math.max(0.5, math.min(1.0, tonumber(config().headshotRatio) or 0.85))
    local ratio = state.hits > 0 and state.headshots / state.hits or 0
    state.qualified = state.hits >= minimumHits and state.headshots >= minimumHeadshots and ratio >= ratioLimit
    local requiredWindows = math.max(2, math.floor(tonumber(config().requiredQualifiedWindows) or 2))
    if not state.qualified or state.qualifiedWindows + 1 < requiredWindows or state.alerted then return false end
    state.alerted = true

    local evidence = {
        origin = 'server_event', weaponHash = weapon, hitComponent = tonumber(data.hitComponent),
        hits = state.hits, headshots = state.headshots, ratio = ratio, windowMs = window,
        distanceBand = distanceBand, pingBand = pingBand, ping = ping,
        averageDistance = state.hits > 0 and state.distanceTotal / state.hits or 0,
        qualifiedWindows = state.qualifiedWindows + 1,
        ruleVersion = Config.DetectorHealth and Config.DetectorHealth.ruleVersion or 'unknown'
    }
    evidence.correlationId = MZBan.Correlation and MZBan.Correlation.Record(sourceId, 'aim.qualified_window', evidence) or nil
    local incident = MZBan.Incidents.Record({
        source = sourceId,
        playerName = GetPlayerName(sourceId),
        code = 'aim_headshot_pattern_suspect',
        origin = 'server_event',
        confidence = 'medium',
        subject = ('%s:%s:%s'):format(tostring(weapon), distanceBand, pingBand),
        reason = 'headshot_ratio_repeated_across_context_windows',
        evidence = evidence
    })
    if incident then MZBan.Incidents.NotifyStaff(incident) end
    if MZBan.DetectorHealth then MZBan.DetectorHealth.Seen('aim_guard') end
    return incident ~= nil
end

buildWeapons()
AddEventHandler('weaponDamageEvent', observe)

AddEventHandler('playerDropped', function()
    local prefix = tostring(math.floor(tonumber(source) or 0)) .. ':'
    for key in pairs(samples) do if key:sub(1, #prefix) == prefix then samples[key] = nil end end
end)

function MZBan.AimGuard.Status()
    local contexts, qualified = 0, 0
    for _, state in pairs(samples) do
        contexts = contexts + 1
        if state.qualified or state.qualifiedWindows > 0 then qualified = qualified + 1 end
    end
    return { contexts = contexts, qualifiedContexts = qualified, requiredQualifiedWindows = math.max(2, tonumber(config().requiredQualifiedWindows) or 2) }
end

MZBan.AimGuard.Observe = observe
MZBan.AimGuard.RebuildWeapons = buildWeapons
