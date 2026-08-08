MZBan = MZBan or {}
MZBan.EventGuard = MZBan.EventGuard or {}

local rates = {}
local stunHashes = nil

local function config()
    return type(Config.EventGuard) == 'table' and Config.EventGuard or {}
end

local function nowMs()
    return math.max(0, math.floor(tonumber(GetGameTimer()) or 0))
end

local function online(sourceId)
    sourceId = tonumber(sourceId)
    return sourceId and sourceId > 0 and GetPlayerPing(math.floor(sourceId)) > 0
end

local function normalizeHash(value)
    value = tonumber(value)
    if not value then return nil end
    value = math.floor(value)
    if value < 0 then value = value + 4294967296 end
    return value >= 0 and value <= 4294967295 and value or nil
end

local function finite(value, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    if minimum and value < minimum then return nil end
    if maximum and value > maximum then return nil end
    return value
end

local function safeNative(native, fallback, ...)
    local ok, value = pcall(native, ...)
    if not ok or value == nil then return fallback end
    return value
end

local function coordsOfEntity(entity)
    if not entity or entity == 0 or safeNative(DoesEntityExist, false, entity) ~= true then return nil end
    local coords = safeNative(GetEntityCoords, nil, entity)
    if not coords then return nil end
    return { x = tonumber(coords.x) or 0.0, y = tonumber(coords.y) or 0.0, z = tonumber(coords.z) or 0.0 }
end

local function coordsOfPlayer(sourceId)
    return coordsOfEntity(safeNative(GetPlayerPed, 0, sourceId))
end

local function distance(left, right)
    if not left or not right then return nil end
    local x, y, z = left.x - right.x, left.y - right.y, left.z - right.z
    return math.sqrt(x * x + y * y + z * z)
end

local function countFor(sourceId, kind, discriminator, windowMs)
    local key = ('%d:%s:%s'):format(sourceId, kind, tostring(discriminator or 'all'))
    local currentMs = nowMs()
    local state = rates[key]
    if not state or currentMs - state.startedAt >= windowMs then
        state = { startedAt = currentMs, lastSeenAt = currentMs, count = 0 }
        rates[key] = state
    end
    state.lastSeenAt = currentMs
    state.count = state.count + 1
    return state.count
end

local CODES = {
    explosion = 'event_explosion_rate_suspect',
    clearTasks = 'event_clear_tasks_rate_suspect',
    tazer = 'event_tazer_rate_suspect',
    ptfx = 'event_ptfx_rate_suspect',
    projectile = 'event_projectile_rate_suspect',
    fire = 'event_fire_rate_suspect',
    remoteWeapon = 'event_remote_weapon_action_suspect',
    modifier = 'event_damage_modifier_suspect'
}

local function record(sourceId, code, subject, reason, evidence, confidence)
    local correlationId = MZBan.Correlation and MZBan.Correlation.Record(sourceId, 'server_event.' .. code, evidence) or nil
    evidence.correlationId = correlationId
    local incident = MZBan.Incidents.Record({
        source = sourceId,
        playerName = GetPlayerName(sourceId),
        code = code,
        origin = 'server_event',
        confidence = confidence or 'high',
        subject = tostring(subject or code),
        reason = reason,
        evidence = evidence
    })
    if incident then MZBan.Incidents.NotifyStaff(incident) end
    return incident
end

local function observeRate(sourceId, kind, discriminator, extra, codeOverride, reasonOverride, confidence)
    if config().enabled ~= true or not online(sourceId) then return false end
    sourceId = math.floor(tonumber(sourceId))
    local windows = type(config().windows) == 'table' and config().windows or {}
    local limits = type(config().limits) == 'table' and config().limits or {}
    local window = math.max(1000, math.floor(tonumber(windows[kind .. 'Ms']) or 10000))
    local maximum = math.max(1, math.floor(tonumber(limits[kind]) or 8))
    local count = countFor(sourceId, kind, discriminator, window)
    if count <= maximum then return false end
    extra = type(extra) == 'table' and extra or {}
    extra.origin, extra.amount, extra.windowMs = 'server_event', count, window
    if extra.eventType == nil then extra.eventType = tonumber(discriminator) end
    return record(sourceId, codeOverride or CODES[kind], discriminator or kind,
        reasonOverride or (kind .. '_rate_above_observation_limit'), extra, confidence) ~= nil
end

local function immediate(sourceId, code, subject, reason, evidence, confidence)
    if config().enabled ~= true or not online(sourceId) then return false end
    evidence = type(evidence) == 'table' and evidence or {}
    evidence.origin = 'server_event'
    return record(math.floor(tonumber(sourceId)), code, subject, reason, evidence, confidence) ~= nil
end

local function entityFromNetId(netId)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return 0 end
    return tonumber(safeNative(NetworkGetEntityFromNetworkId, 0, netId)) or 0
end

local function entityOwnerFromNetId(netId)
    local entity = entityFromNetId(netId)
    if entity == 0 or safeNative(DoesEntityExist, false, entity) ~= true then return nil, entity end
    local owner = tonumber(safeNative(NetworkGetEntityOwner, 0, entity))
    return online(owner) and math.floor(owner) or nil, entity
end

local function consumeLease(sourceId, capability, context)
    if not MZBan.SecurityLeases or type(MZBan.SecurityLeases.Consume) ~= 'function' then return false end
    return MZBan.SecurityLeases.Consume(sourceId, capability, context or {}) == true
end

AddEventHandler('explosionEvent', function(sender, data)
    if type(data) ~= 'table' then return end
    if MZBan.DetectorHealth then MZBan.DetectorHealth.Seen('event_guard.explosion') end
    local explosionType = tonumber(data.explosionType) or -1
    local weaponHash = normalizeHash(data.weaponHash or data.f164)
    local posX = finite(data.posX, -100000, 100000)
    local posY = finite(data.posY, -100000, 100000)
    local posZ = finite(data.posZ, -10000, 10000)
    local explosionCoords = posX and posY and posZ and { x = posX, y = posY, z = posZ } or nil
    local senderDistance = distance(coordsOfPlayer(sender), explosionCoords)
    local leaseContext = { eventType = explosionType, weaponHash = weaponHash }
    if consumeLease(sender, 'event.explosion.scripted', leaseContext) then return end
    local evidence = {
        eventType = explosionType, weaponHash = weaponHash,
        damageScale = finite(data.damageScale, 0, 1000),
        isInvisible = data.isInvisible == true, isAudible = data.isAudible ~= false,
        ownerNetId = tonumber(data.ownerNetId), distanceFromSender = senderDistance,
        x = explosionCoords and explosionCoords.x, y = explosionCoords and explosionCoords.y,
        z = explosionCoords and explosionCoords.z
    }
    observeRate(sender, 'explosion', explosionType, evidence)
    local anomaly = (evidence.damageScale and evidence.damageScale > (tonumber(config().maxDamageScale) or 1.0))
        or evidence.isInvisible
        or (senderDistance and senderDistance > (tonumber(config().maxExplosionDistance) or 250.0))
    if anomaly then
        immediate(sender, 'event_explosion_anomaly_suspect', explosionType,
            'explosion_metadata_or_distance_anomaly', evidence, 'high')
    end
end)

AddEventHandler('clearPedTasksEvent', function(sender, data)
    if type(data) ~= 'table' then return end
    if MZBan.DetectorHealth then MZBan.DetectorHealth.Seen('event_guard.clear_tasks') end
    local targetNetId = tonumber(data.pedId or data.networkId) or 0
    observeRate(sender, 'clearTasks', 'all', { targetNetId = targetNetId, immediately = data.immediately == true })
    local targetOwner, entity = entityOwnerFromNetId(targetNetId)
    if targetOwner and targetOwner ~= tonumber(sender) and safeNative(IsPedAPlayer, false, entity) == true then
        local context = { target = targetOwner, targetNetId = targetNetId }
        if not consumeLease(sender, 'event.clear_tasks.remote', context) then
            immediate(sender, 'event_remote_clear_tasks_suspect', targetOwner,
                'clear_tasks_against_remote_player', {
                    target = targetOwner, targetNetId = targetNetId,
                    targetOwner = targetOwner, immediately = data.immediately == true
                }, 'high')
        end
    end
end)

local function buildStunHashes()
    stunHashes = {}
    for _, name in ipairs({ 'WEAPON_STUNGUN', 'WEAPON_STUNGUN_MP' }) do
        local hash = normalizeHash(joaat(name))
        if hash then stunHashes[hash] = true end
    end
end

AddEventHandler('weaponDamageEvent', function(sender, data)
    if type(data) ~= 'table' or not online(sender) then return end
    if not stunHashes then buildStunHashes() end
    local weapon = normalizeHash(data.weaponType)
    if weapon and stunHashes[weapon] then observeRate(sender, 'tazer', weapon, { weaponHash = weapon }) end

    local sourceText = tostring(math.floor(tonumber(sender)))
    local weaponModifier = finite(safeNative(GetPlayerWeaponDamageModifier, 1.0, sourceText), 0, 100)
    local meleeModifier = finite(safeNative(GetPlayerMeleeWeaponDamageModifier, 1.0, sourceText), 0, 100)
    local defenseModifier = finite(safeNative(GetPlayerWeaponDefenseModifier, 1.0, sourceText), 0, 100)
    if (weaponModifier and weaponModifier > (tonumber(config().maxWeaponDamageModifier) or 1.05))
        or (meleeModifier and meleeModifier > (tonumber(config().maxMeleeDamageModifier) or 1.05))
        or (defenseModifier and defenseModifier > (tonumber(config().maxWeaponDefenseModifier) or 1.05)) then
        observeRate(sender, 'modifier', 'damage', {
            weaponModifier = weaponModifier, meleeModifier = meleeModifier, defenseModifier = defenseModifier
        })
    end
end)

AddEventHandler('ptFxEvent', function(sender, data)
    if type(data) ~= 'table' then return end
    if MZBan.DetectorHealth then MZBan.DetectorHealth.Seen('event_guard.ptfx') end
    local effectHash = normalizeHash(data.effectHash)
    local scale = finite(data.scale, 0, 10000)
    local targetNetId = tonumber(data.entityNetId) or 0
    observeRate(sender, 'ptfx', effectHash or 'all', { effectHash = effectHash, scale = scale, targetNetId = targetNetId })
    local targetOwner = targetNetId > 0 and entityOwnerFromNetId(targetNetId) or nil
    if (scale and scale > (tonumber(config().maxParticleScale) or 5.0))
        or (targetOwner and targetOwner ~= tonumber(sender)) then
        immediate(sender, 'event_ptfx_anomaly_suspect', effectHash or 'unknown',
            targetOwner and 'ptfx_on_remote_entity' or 'ptfx_scale_above_limit', {
                effectHash = effectHash, scale = scale, targetNetId = targetNetId, targetOwner = targetOwner
            }, targetOwner and 'high' or 'medium')
    end
end)

AddEventHandler('startProjectileEvent', function(sender, data)
    if type(data) ~= 'table' then return end
    if MZBan.DetectorHealth then MZBan.DetectorHealth.Seen('event_guard.projectile') end
    local weaponHash = normalizeHash(data.weaponHash)
    local projectileHash = normalizeHash(data.projectileHash or data.projectileHashId)
    observeRate(sender, 'projectile', weaponHash or projectileHash or 'all', {
        weaponHash = weaponHash, projectileHash = projectileHash
    })
end)

local function unwrapFireData(raw)
    local data = raw
    for _ = 1, 3 do
        if type(data) ~= 'table' then return nil end
        if data.isEntity ~= nil or data.entityGlobalId ~= nil then return data end
        data = data[1]
    end
    return type(data) == 'table' and data or nil
end

AddEventHandler('fireEvent', function(sender, rawData)
    local data = unwrapFireData(rawData)
    if not data then return end
    if MZBan.DetectorHealth then MZBan.DetectorHealth.Seen('event_guard.fire') end
    local targetNetId = tonumber(data.entityGlobalId) or 0
    observeRate(sender, 'fire', data.isEntity == true and 'entity' or 'world', { targetNetId = targetNetId })
    if data.isEntity == true and targetNetId > 0 then
        local targetOwner, entity = entityOwnerFromNetId(targetNetId)
        local targetDistance = distance(coordsOfPlayer(sender), coordsOfEntity(entity))
        if targetDistance and targetDistance > (tonumber(config().maxFireDistance) or 160.0) then
            immediate(sender, 'event_fire_remote_suspect', targetNetId, 'fire_target_distance_above_limit', {
                targetNetId = targetNetId, targetOwner = targetOwner, distanceFromSender = targetDistance
            }, 'high')
        end
    end
end)

local function remoteWeaponAction(sender, data, action)
    if type(data) ~= 'table' then return end
    if MZBan.DetectorHealth then MZBan.DetectorHealth.Seen('event_guard.remote_weapon') end
    local targetNetId = tonumber(data.pedId) or 0
    local targetOwner = entityOwnerFromNetId(targetNetId)
    if not targetOwner or targetOwner == tonumber(sender) then return end
    local weaponHash = normalizeHash(data.weaponType or data.weaponHash)
    local capability = action == 'give' and 'weapon.give.remote' or 'weapon.remove.remote'
    local context = { target = targetOwner, targetNetId = targetNetId, weaponHash = weaponHash }
    if consumeLease(sender, capability, context) then return end
    immediate(sender, 'event_remote_weapon_action_suspect', action, 'remote_weapon_action_without_lease', {
        target = targetOwner, targetNetId = targetNetId, targetOwner = targetOwner,
        weaponHash = weaponHash, action = action
    }, 'high')
end

AddEventHandler('giveWeaponEvent', function(sender, data) remoteWeaponAction(sender, data, 'give') end)
AddEventHandler('removeWeaponEvent', function(sender, data) remoteWeaponAction(sender, data, 'remove') end)
AddEventHandler('removeAllWeaponsEvent', function(sender, data) remoteWeaponAction(sender, data, 'remove_all') end)

AddEventHandler('playerDropped', function()
    local prefix = tostring(math.floor(tonumber(source) or 0)) .. ':'
    for key in pairs(rates) do if key:sub(1, #prefix) == prefix then rates[key] = nil end end
end)

CreateThread(function()
    while true do
        Wait(60000)
        local cutoff = nowMs() - 60000
        for key, state in pairs(rates) do
            if type(state) ~= 'table' or (tonumber(state.lastSeenAt) or 0) < cutoff then rates[key] = nil end
        end
    end
end)

MZBan.EventGuard.Observe = observeRate
