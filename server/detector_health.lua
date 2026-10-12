MZBan = MZBan or {}
MZBan.DetectorHealth = MZBan.DetectorHealth or {}

local modules = {}
local heartbeats = {}
local resourceHeartbeats = {}
local missingEpisodes = {}
local onlineSeenAt = {}
local HEARTBEAT_EVENT = 'mz_banguard:server:sensorHeartbeat'
local RESOURCE_HEARTBEAT_EVENT = 'mz_banguard:server:resourceHeartbeat'
local RESOURCE_STOP_EVENT = 'mz_banguard:server:resourceStopObserved'

local function config()
    return type(Config.DetectorHealth) == 'table' and Config.DetectorHealth or {}
end

local function nowMs()
    return math.max(0, math.floor(tonumber(GetGameTimer()) or 0))
end

local function moduleState(name)
    name = tostring(name or 'unknown'):gsub('%c', ''):sub(1, 48)
    local state = modules[name]
    if not state then
        state = { events = 0, discarded = 0, errors = 0, lastEventMs = 0, lastError = nil }
        modules[name] = state
    end
    return state
end

function MZBan.DetectorHealth.Seen(name, amount)
    if config().enabled ~= true then return end
    local state = moduleState(name)
    state.events = state.events + math.max(1, math.floor(tonumber(amount) or 1))
    state.lastEventMs = nowMs()
end

function MZBan.DetectorHealth.Discard(name, reason)
    if config().enabled ~= true then return end
    local state = moduleState(name)
    state.discarded = state.discarded + 1
    state.lastDiscardReason = tostring(reason or 'discarded'):gsub('%c', ''):sub(1, 96)
end

function MZBan.DetectorHealth.Error(name, reason)
    if config().enabled ~= true then return end
    local state = moduleState(name)
    state.errors = state.errors + 1
    state.lastError = tostring(reason or 'error'):gsub('%c', ''):sub(1, 160)
    state.lastErrorMs = nowMs()
end

local function online(sourceId)
    sourceId = tonumber(sourceId)
    return sourceId and sourceId > 0 and GetPlayerPing(math.floor(sourceId)) > 0
end

local function watchedResource(value)
    value = type(value) == 'string' and value:gsub('%c', ''):sub(1, 48) or ''
    local watched = type(config().watchedResources) == 'table' and config().watchedResources or {}
    return watched[value] == true and value or nil
end

local function recordPresence(sourceId, code, resourceName, status, confidence)
    if not MZBan.Incidents or type(MZBan.Incidents.Record) ~= 'function' then return end
    local incident = MZBan.Incidents.Record({
        source = sourceId,
        playerName = GetPlayerName(sourceId),
        code = code,
        origin = 'client_telemetry',
        confidence = confidence or 'low',
        culpability = 'none',
        subject = resourceName,
        reason = status,
        evidence = { resourceName = resourceName, presenceStatus = status }
    })
    if incident then MZBan.Incidents.NotifyStaff(incident) end
end

RegisterNetEvent(HEARTBEAT_EVENT, function(version, sequence)
    local sourceId = tonumber(source)
    version = type(version) == 'string' and version:gsub('%c', ''):sub(1, 32) or ''
    sequence = tonumber(sequence)
    if not online(sourceId) or version == '' or not sequence or sequence < 0 or sequence > 2147483647 then
        MZBan.DetectorHealth.Discard('client_sensor', 'invalid_heartbeat')
        return
    end
    sourceId = math.floor(sourceId)
    local previous = heartbeats[sourceId]
    local currentMs = nowMs()
    local minimumInterval = math.max(1000, math.floor((tonumber(config().heartbeatIntervalMs) or 15000) / 3))
    if previous and currentMs - previous.atMs < minimumInterval then
        MZBan.DetectorHealth.Discard('client_sensor', 'heartbeat_rate_limited')
        return
    end
    local sequenceValue = math.floor(sequence)
    local wrapped = previous and previous.sequence > 2147483000 and sequenceValue < 1000
    if previous and not wrapped and sequenceValue <= previous.sequence then
        MZBan.DetectorHealth.Discard('client_sensor', 'heartbeat_replayed')
        return
    end
    heartbeats[sourceId] = {
        atMs = currentMs,
        firstSeenAt = previous and previous.firstSeenAt or currentMs,
        version = version,
        sequence = sequenceValue
    }
    MZBan.DetectorHealth.Seen('client_sensor')
end)

RegisterNetEvent(RESOURCE_HEARTBEAT_EVENT, function(resourceName, version, sequence)
    local sourceId = tonumber(source)
    resourceName = watchedResource(resourceName)
    version = type(version) == 'string' and version:gsub('%c', ''):sub(1, 32) or ''
    sequence = tonumber(sequence)
    if not online(sourceId) or not resourceName or version == '' or not sequence
        or sequence < 0 or sequence > 2147483647 then
        MZBan.DetectorHealth.Discard('resource_presence', 'invalid_heartbeat')
        return
    end
    sourceId = math.floor(sourceId)
    local currentMs = nowMs()
    local states = resourceHeartbeats[sourceId] or {}
    resourceHeartbeats[sourceId] = states
    local previous = states[resourceName]
    local sequenceValue = math.floor(sequence)
    local wrapped = previous and previous.sequence > 2147483000 and sequenceValue < 1000
    if previous and not wrapped and sequenceValue <= previous.sequence then
        MZBan.DetectorHealth.Discard('resource_presence', 'heartbeat_replayed')
        return
    end
    states[resourceName] = { atMs = currentMs, version = version, sequence = sequenceValue }
    if missingEpisodes[sourceId] then missingEpisodes[sourceId][resourceName] = nil end
    MZBan.DetectorHealth.Seen('resource_presence.' .. resourceName)
end)

RegisterNetEvent(RESOURCE_STOP_EVENT, function(resourceName)
    local sourceId = tonumber(source)
    resourceName = watchedResource(resourceName)
    if not online(sourceId) or not resourceName then return end
    sourceId = math.floor(sourceId)
    local episodes = missingEpisodes[sourceId] or {}
    missingEpisodes[sourceId] = episodes
    if episodes[resourceName] ~= true then
        episodes[resourceName] = true
        recordPresence(sourceId, 'client_resource_stop_observed', resourceName, 'client_stop_observed', 'low')
    end
end)

function MZBan.DetectorHealth.Status()
    local output = {
        enabled = config().enabled == true,
        ruleVersion = tostring(config().ruleVersion or 'unknown'),
        modules = {},
        sensors = { online = 0, present = 0, missing = 0, missingSources = {}, resources = {} }
    }
    for name, state in pairs(modules) do
        output.modules[name] = {
            events = state.events,
            discarded = state.discarded,
            errors = state.errors,
            lastEventMs = state.lastEventMs,
            lastError = state.lastError,
            lastDiscardReason = state.lastDiscardReason
        }
    end
    local currentMs = nowMs()
    local missingAfter = math.max(10000, math.floor(tonumber(config().heartbeatMissingMs) or 45000))
    for _, playerId in ipairs(GetPlayers()) do
        local sourceId = tonumber(playerId)
        if online(sourceId) then
            output.sensors.online = output.sensors.online + 1
            local heartbeat = heartbeats[sourceId]
            if heartbeat and currentMs - heartbeat.atMs <= missingAfter then
                output.sensors.present = output.sensors.present + 1
            else
                output.sensors.missing = output.sensors.missing + 1
                output.sensors.missingSources[#output.sensors.missingSources + 1] = sourceId
            end
            local resourceStates = resourceHeartbeats[sourceId] or {}
            for resourceName in pairs(type(config().watchedResources) == 'table' and config().watchedResources or {}) do
                local resourceHeartbeat = resourceStates[resourceName]
                local present = resourceHeartbeat and currentMs - resourceHeartbeat.atMs <= missingAfter or false
                output.sensors.resources[resourceName] = output.sensors.resources[resourceName]
                    or { present = 0, missing = 0 }
                local counter = output.sensors.resources[resourceName]
                counter[present and 'present' or 'missing'] = counter[present and 'present' or 'missing'] + 1
            end
        end
    end
    return output
end

AddEventHandler('playerDropped', function()
    local sourceId = tonumber(source)
    heartbeats[sourceId], resourceHeartbeats[sourceId], missingEpisodes[sourceId], onlineSeenAt[sourceId] = nil, nil, nil, nil
end)

CreateThread(function()
    while true do
        Wait(math.max(5000, math.floor(tonumber(config().cleanupIntervalMs) or 10000)))
        local currentMs = nowMs()
        local missingAfter = math.max(10000, math.floor(tonumber(config().heartbeatMissingMs) or 45000))
        local active = {}
        for _, playerId in ipairs(GetPlayers()) do
            local sourceId = tonumber(playerId)
            if online(sourceId) then
                sourceId = math.floor(sourceId)
                active[sourceId] = true
                onlineSeenAt[sourceId] = onlineSeenAt[sourceId] or currentMs
                if currentMs - onlineSeenAt[sourceId] >= missingAfter then
                    local states = resourceHeartbeats[sourceId] or {}
                    local episodes = missingEpisodes[sourceId] or {}
                    missingEpisodes[sourceId] = episodes
                    for resourceName in pairs(type(config().watchedResources) == 'table' and config().watchedResources or {}) do
                        local state = states[resourceName]
                        if (not state or currentMs - state.atMs > missingAfter) and episodes[resourceName] ~= true then
                            episodes[resourceName] = true
                            recordPresence(sourceId, 'client_resource_presence_missing', resourceName,
                                'heartbeat_missing', 'low')
                        end
                    end
                end
            end
        end
        for sourceId in pairs(onlineSeenAt) do
            if not active[sourceId] then
                heartbeats[sourceId], resourceHeartbeats[sourceId], missingEpisodes[sourceId], onlineSeenAt[sourceId] = nil, nil, nil, nil
            end
        end
    end
end)
