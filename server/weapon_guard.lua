MZBan = MZBan or {}
MZBan.WeaponGuard = MZBan.WeaponGuard or {}

local rateBySource = {}
local knownWeaponByHash = {}
local unarmedWeaponByHash = {}

local function config()
    return type(Config.WeaponGuard) == 'table' and Config.WeaponGuard or {}
end

local function normalizeHash(value)
    value = tonumber(value)
    if not value then return nil end
    value = math.floor(value)
    if value < 0 then value = value + 4294967296 end
    if value < 0 or value > 4294967295 then return nil end
    return value
end

local function normalizeSource(value)
    value = tonumber(value)
    if not value or value <= 0 then return nil end
    return math.floor(value)
end

local function safeNumber(value, minimum, maximum)
    value = tonumber(value)
    if not value then return nil end
    if minimum and value < minimum then value = minimum end
    if maximum and value > maximum then value = maximum end
    return value
end

local function buildKnownWeapons()
    knownWeaponByHash = {}
    unarmedWeaponByHash = {}
    for _, weaponName in ipairs(config().knownWeaponNames or {}) do
        if type(weaponName) == 'string' and weaponName ~= '' then
            local hash = normalizeHash(joaat(weaponName))
            if hash then knownWeaponByHash[hash] = weaponName end
        end
    end
    for _, weaponName in ipairs(config().unarmedWeaponNames or { 'WEAPON_UNARMED' }) do
        if type(weaponName) == 'string' and weaponName ~= '' then
            local hash = normalizeHash(joaat(weaponName))
            if hash then unarmedWeaponByHash[hash] = weaponName end
        end
    end
end

local function rateProfile(reportedHash)
    local guard = config()
    local profiles = type(guard.rateProfiles) == 'table' and guard.rateProfiles or {}
    local weaponName = knownWeaponByHash[reportedHash]
    local selected = weaponName and profiles[weaponName] or nil
    local profileName = type(selected) == 'table' and weaponName or 'default'
    if type(selected) ~= 'table' then selected = profiles.default end
    selected = type(selected) == 'table' and selected or {}
    return profileName,
        math.max(250, math.floor(tonumber(selected.windowMs) or tonumber(guard.rateWindowMs) or 1000)),
        math.max(1, math.floor(tonumber(selected.threshold) or tonumber(guard.rateEventThreshold) or 25))
end

local function rateState(source, reportedHash, currentMs)
    local profileName, window, threshold = rateProfile(reportedHash)
    local key = tostring(source) .. ':' .. tostring(reportedHash)
    local current = rateBySource[key]
    if not current or currentMs - current.startedAt >= window then
        current = { startedAt = currentMs, count = 0 }
        rateBySource[key] = current
    end
    current.count = current.count + 1
    return current.count, window, threshold, profileName
end

local function nativeResult(callback)
    local ok, value = pcall(callback)
    if not ok then return nil end
    return value
end

local function firstTargetNetId(data)
    local direct = tonumber(data.hitGlobalId)
    if direct and direct >= 1 and direct <= 2147483647 then return math.floor(direct) end
    if type(data.hitGlobalIds) == 'table' then
        for _, value in pairs(data.hitGlobalIds) do
            local normalized = tonumber(value)
            if normalized and normalized >= 1 and normalized <= 2147483647 then
                return math.floor(normalized)
            end
        end
    end
    return nil
end

local function coordinate(value, key, index)
    if value == nil then return nil end
    local ok, result = pcall(function() return value[key] or value[index] end)
    return ok and tonumber(result) or nil
end

local function targetContext(source, data)
    local evidence = {
        ping = safeNumber(GetPlayerPing(source), 0, 10000),
        hitComponent = safeNumber(data.hitComponent, 0, 65535)
    }
    local targetNetId = firstTargetNetId(data)
    if not targetNetId then return evidence, nil end
    evidence.targetNetId = targetNetId

    if type(NetworkGetEntityFromNetworkId) ~= 'function' then return evidence, targetNetId end
    local entity = nativeResult(function() return NetworkGetEntityFromNetworkId(targetNetId) end)
    if not entity or entity == 0 then return evidence, targetNetId end
    if type(DoesEntityExist) == 'function'
        and nativeResult(function() return DoesEntityExist(entity) end) ~= true then
        return evidence, targetNetId
    end

    local entityType = type(GetEntityType) == 'function'
        and tonumber(nativeResult(function() return GetEntityType(entity) end)) or nil
    if entityType == 1 then
        local playerPed = type(IsPedAPlayer) == 'function'
            and nativeResult(function() return IsPedAPlayer(entity) end) == true
        evidence.targetType = playerPed and 'player' or 'ped'
    elseif entityType == 2 then
        evidence.targetType = 'vehicle'
    elseif entityType == 3 then
        evidence.targetType = 'object'
    else
        evidence.targetType = 'unknown'
    end

    if type(NetworkGetEntityOwner) == 'function' then
        evidence.targetOwner = safeNumber(
            nativeResult(function() return NetworkGetEntityOwner(entity) end), 0, 65535)
    end

    if type(GetPlayerPed) == 'function' and type(GetEntityCoords) == 'function' then
        local attackerPed = nativeResult(function() return GetPlayerPed(source) end)
        if attackerPed and attackerPed ~= 0 then
            local from = nativeResult(function() return GetEntityCoords(attackerPed) end)
            local target = nativeResult(function() return GetEntityCoords(entity) end)
            local fx, fy, fz = coordinate(from, 'x', 1), coordinate(from, 'y', 2), coordinate(from, 'z', 3)
            local tx, ty, tz = coordinate(target, 'x', 1), coordinate(target, 'y', 2), coordinate(target, 'z', 3)
            if fx and fy and fz and tx and ty and tz then
                local dx, dy, dz = fx - tx, fy - ty, fz - tz
                evidence.targetDistance = math.floor(math.sqrt(dx * dx + dy * dy + dz * dz) * 10 + 0.5) / 10
            end
        end
    end
    return evidence, targetNetId
end

local function queryAuthority(source)
    local inventory = tostring(Config.Integration and Config.Integration.InventoryResource or 'mz_inventory')
    if GetResourceState(inventory) ~= 'started' then return nil, 'inventory_unavailable' end
    local ok, state, reason = pcall(function()
        return exports[inventory]:GetEquippedWeaponState(source)
    end)
    if not ok then return nil, 'authority_export_error' end
    if type(state) ~= 'table' then return nil, tostring(reason or 'authority_state_unavailable') end
    return state, tostring(reason or (state.equipped and 'weapon_equipped' or 'weapon_not_equipped'))
end

local function queryDeathState(source)
    local core = tostring(Config.Integration and Config.Integration.CoreResource or 'mz_core')
    if GetResourceState(core) ~= 'started' then return nil end
    local ok, available, state = pcall(function()
        return exports[core]:GetDeathState(source)
    end)
    if not ok or available ~= true or type(state) ~= 'table' then return nil end
    local deathState = tostring(state.deathState or '')
    if deathState ~= 'alive' and deathState ~= 'downed' and deathState ~= 'dead'
        and deathState ~= 'respawning' then return nil end
    return deathState, safeNumber(state.revision, 0, 2147483647)
end

local function isTransitionWindow(state, currentMs)
    local lastTransitionAt = type(state) == 'table' and tonumber(state.lastTransitionAt) or nil
    if not lastTransitionAt or lastTransitionAt <= 0 then return false end
    local window = math.max(0, math.floor(tonumber(config().transitionWindowMs) or 2500))
    local elapsed = currentMs - lastTransitionAt
    return elapsed >= 0 and elapsed <= window
end

local function classify(source, data, currentMs)
    if type(data) ~= 'table' then
        return 'weapon_damage_payload_invalid', nil, nil, 'payload_not_table'
    end

    local reportedHash = normalizeHash(data.weaponType)
    if not reportedHash or reportedHash == 0 then
        return 'weapon_damage_payload_invalid', nil, nil, 'invalid_weapon_hash'
    end

    local deathState, stateRevision = queryDeathState(source)
    if deathState and deathState ~= 'alive' then
        return 'weapon_damage_death_state_incompatible', reportedHash, nil,
            'canonical_death_state_blocks_damage', { deathState = deathState, stateRevision = stateRevision }
    end

    if unarmedWeaponByHash[reportedHash] then
        return nil, reportedHash, nil, 'authorized_unarmed'
    end

    local state, authorityReason = queryAuthority(source)
    if not state then
        return 'weapon_damage_session_not_ready', reportedHash, nil, authorityReason
    end

    local authorizedHash = normalizeHash(state.weaponHash)
    local transition = isTransitionWindow(state, currentMs)
    if state.equipped ~= true or not authorizedHash then
        if transition then
            return 'weapon_damage_transition_window', reportedHash, state, 'recent_server_weapon_transition'
        end
        return 'weapon_damage_no_equipped_weapon', reportedHash, state, authorityReason
    end

    if authorizedHash ~= reportedHash then
        if transition then
            return 'weapon_damage_transition_window', reportedHash, state, 'recent_server_weapon_transition'
        end
        if not knownWeaponByHash[reportedHash] then
            return 'weapon_damage_unknown_hash', reportedHash, state, 'reported_hash_not_in_catalog'
        end
        return 'weapon_damage_hash_mismatch', reportedHash, state, 'reported_hash_differs_from_server_state'
    end

    local count, window, threshold, profileName = rateState(source, reportedHash, currentMs)
    if count > threshold then
        return 'weapon_damage_rate_suspect', reportedHash, state, 'server_event_rate_above_threshold', {
            rateCount = count,
            rateWindowMs = window,
            rateThreshold = threshold,
            rateProfile = profileName
        }
    end
    return nil, reportedHash, state, 'authorized'
end

local function mitigationCapability(code, source)
    local guard = config()
    if MZBan.Lab and type(MZBan.Lab.IsSubject) == 'function' and MZBan.Lab.IsSubject(source) == true then
        return { supported = false, reason = 'lab_mode', resource = GetCurrentResourceName() }
    end
    local supportedCode = code == 'weapon_damage_no_equipped_weapon' or code == 'weapon_damage_hash_mismatch'
        or code == 'weapon_damage_death_state_incompatible'
    if not supportedCode then
        return { supported = false, reason = 'weapon_detector_not_cancelable', resource = GetCurrentResourceName() }
    end
    if guard.cancelHighConfidence ~= true or guard.runtimeValidated ~= true then
        return { supported = false, reason = 'weapon_cancel_runtime_not_validated', resource = GetCurrentResourceName() }
    end
    return {
        supported = true,
        resource = GetCurrentResourceName(),
        execute = function()
            CancelEvent()
            return true, 'blocked', 'weapon_damage_event_cancelled'
        end
    }
end

local function recordWeaponDamage(sender, data)
    local source = normalizeSource(sender)
    if not source or GetPlayerPing(source) <= 0 or config().enabled ~= true then return end

    local currentMs = math.max(0, math.floor(tonumber(GetGameTimer()) or 0))
    local code, reportedHash, state, reason, rateEvidence = classify(source, data, currentMs)
    if not code then return end
    data = type(data) == 'table' and data or {}
    local evidence, targetNetId = targetContext(source, data)
    for key, value in pairs(rateEvidence or {}) do evidence[key] = value end
    evidence.ammoRevision = state and safeNumber(state.ammoRevision, 0, 2147483647) or nil
    evidence.transitionRevision = state and safeNumber(state.transitionRevision, 0, 2147483647) or nil
    evidence.weaponHash = reportedHash
    local correlationId = MZBan.Correlation and MZBan.Correlation.Record(source, 'weapon.damage_suspect', {
        code = code,
        weaponHash = reportedHash,
        targetNetId = targetNetId,
        targetType = evidence.targetType,
        targetDistance = evidence.targetDistance
    }) or nil
    evidence.correlationId = correlationId
    local incident, created, recordReason = MZBan.Incidents.Record({
        source = source,
        citizenid = state and state.citizenid or nil,
        playerName = GetPlayerName(source),
        code = code,
        reportedWeaponHash = reportedHash,
        reportedWeaponName = reportedHash and knownWeaponByHash[reportedHash] or nil,
        authorizedWeaponHash = state and state.weaponHash or nil,
        authorizedWeaponName = state and (state.weaponName or state.itemName) or nil,
        authorizedAmmo = state and state.ammo or nil,
        targetNetId = targetNetId,
        damage = safeNumber(data.weaponDamage, 0, 10000),
        willKill = data.willKill == true,
        overrideDefaultDamage = data.overrideDefaultDamage == true,
        reason = reason,
        origin = 'weaponDamageEvent',
        confidence = code == 'weapon_damage_rate_suspect' and 'medium' or 'high',
        evidence = evidence,
        enforcement = mitigationCapability(code, source)
    })

    if incident then
        MZBan.Incidents.NotifyStaff(incident)
        if created or recordReason == 'aggregated' then
            MZBan.AuditPrint('security.weapon_damage.observed', MZBan.JsonEncode({
                incident_id = incident.id,
                source = source,
                code = code,
                count = incident.count,
                risk_score = incident.riskScore,
                mode = config().mode
            }))
        end
    end
end

buildKnownWeapons()

AddEventHandler('weaponDamageEvent', recordWeaponDamage)

AddEventHandler('playerDropped', function()
    local source = normalizeSource(source)
    if not source then return end
    local prefix = tostring(source) .. ':'
    for key in pairs(rateBySource) do
        if key:sub(1, #prefix) == prefix then rateBySource[key] = nil end
    end
    MZBan.Incidents.MarkSourceDisconnected(source)
end)

CreateThread(function()
    while true do
        local interval = math.max(10000, math.floor(tonumber(config().cleanupIntervalMs) or 60000))
        Wait(interval)
        MZBan.Incidents.Cleanup()
    end
end)

function MZBan.WeaponGuard.Status()
    local risk = type(Config.Risk) == 'table' and Config.Risk or {}
    local mitigationActive = (config().mode == 'mitigate' or config().mode == 'enforce')
        and config().cancelHighConfidence == true
        and config().runtimeValidated == true
    return {
        enabled = config().enabled == true,
        mode = tostring(config().mode or 'observe'),
        cancelHighConfidence = config().cancelHighConfidence == true,
        runtimeValidated = config().runtimeValidated == true,
        mitigationActive = mitigationActive,
        enforcementActive = mitigationActive and config().mode == 'enforce',
        autoKick = risk.AutoKick == true,
        autoBan = risk.AutoBan == true,
        alertOnly = not mitigationActive and risk.AutoKick ~= true and risk.AutoBan ~= true,
        transitionWindowMs = math.floor(tonumber(config().transitionWindowMs) or 2500),
        rateEventThreshold = math.floor(tonumber(config().rateEventThreshold) or 25),
        rateProfiles = type(config().rateProfiles) == 'table' and config().rateProfiles or {}
    }
end

MZBan.WeaponGuard.NormalizeHash = normalizeHash
MZBan.WeaponGuard.Classify = classify
MZBan.WeaponGuard.HandleEvent = recordWeaponDamage
