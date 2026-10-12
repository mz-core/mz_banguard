local failures, checks = {}, 0
local function check(condition, label)
    checks = checks + 1
    if not condition then failures[#failures + 1] = label end
end

local timer = 100000
local handlers = {}
local players = {
    [1] = { name = 'Target', citizenid = 'CID-1', license = 'license:one', fivem = 'fivem:one' },
    [90] = { name = 'Staff', citizenid = 'STAFF-90', license = 'license:staff', fivem = 'fivem:staff' }
}
local permissions = { [90] = { ['alerts.view'] = true } }
local entities = {}
local playerCoords = { [1] = { x = 0.0, y = 0.0, z = 0.0 } }
local cancelCount, deleteCount, dropCount, notifications = 0, 0, 0, 0
local projectileAuthorized = true
local adminNoClip = false

Config = {
    Integration = { CoreResource = 'mz_core', InventoryResource = 'mz_inventory' },
    Risk = { AutoKick = false, AutoBan = false, TrustedActions = { Enabled = true } },
    Enforcement = { DefaultMode = 'passive', AutomaticKickEnabled = false, AutomaticBanEnabled = false },
    DetectorActions = {},
    SecurityAlerts = {
        notifyStaff = true,
        aggregateWindowMs = 15000,
        duplicateCooldownMs = 100,
        notificationCooldownMs = 1000,
        incidentTtlMs = 180000,
        maxIncidents = 100,
        maxEvidencePerIncident = 10,
        maxNotesPerIncident = 5,
        clientReportWindowMs = 10000,
        clientReportLimit = 8,
        clientReasonCooldownMs = 100,
        permissions = { view = 'alerts.view' },
        riskPoints = {
            entity_spawn_rate_suspect = 45,
            movement_teleport_suspect = 35,
            player_godmode_suspect = 30,
            event_explosion_rate_suspect = 40,
            aim_headshot_pattern_suspect = 30
        }
    },
    WeaponGuard = { enabled = true, mode = 'observe', riskPoints = {} },
    EntityGuard = {
        enabled = true, mode = 'observe', cancelHighConfidence = false,
        runtimeValidated = false, windowMs = 10000, inspectDelayMs = 0,
        limits = { ped = 2, vehicle = 2, object = 2 },
        blockedModels = { ped = { [999999] = true }, vehicle = {}, object = {} }
    },
    EntityClassification = {
        enabled = true, mappingVersion = 'test-map', mappingValidated = true,
        populationTypes = {
            [5] = { name = 'random_ambient', class = 'ambient' },
            [7] = { name = 'mission', class = 'scripted' }
        },
        classes = {
            ambient = { alertOnRate = false, confidence = 'low' },
            scripted = { alertOnRate = true, confidence = 'high' },
            unknown = { alertOnRate = true, confidence = 'medium' }
        }
    },
    MovementGuard = {
        enabled = true, mode = 'observe', runtimeValidated = false,
        sampleIntervalMs = 1000, spawnGraceMs = 0, serverFallbackGraceMs = 0,
        serverFootDistance = 100.0, serverVehicleDistance = 200.0
    },
    PlayerStateGuard = { enabled = true, mode = 'observe', runtimeValidated = false },
    EventGuard = {
        enabled = true, mode = 'observe', cancelHighConfidence = false, runtimeValidated = false,
        windows = { explosionMs = 10000, clearTasksMs = 10000, tazerMs = 10000 },
        limits = { explosion = 2, clearTasks = 2, tazer = 2 }
    },
    AimGuard = {
        enabled = true, mode = 'observe', runtimeValidated = false, windowMs = 60000,
        minimumHits = 5, minimumHeadshots = 4, headshotRatio = 0.8,
        requiredQualifiedWindows = 2,
        headComponents = { 31086 }, weaponNames = { 'WEAPON_PISTOL' }
    }
}

function GetGameTimer() return timer end
function GetCurrentResourceName() return 'mz_banguard' end
function GetInvokingResource() return nil end
function GetResourceState(name)
    return (name == 'mz_core' or name == 'mz_notify' or name == 'mz_inventory' or name == 'mz_admin')
        and 'started' or 'missing'
end
function GetPlayerPing(source) return players[tonumber(source)] and 50 or 0 end
function GetPlayerName(source) return players[tonumber(source)] and players[tonumber(source)].name or nil end
function GetPlayers() return { '1', '90' } end
function GetPlayerIdentifiers(source)
    local player = players[tonumber(source)]
    return player and { player.license, player.fivem } or {}
end
function GetPlayerPed(source) return tonumber(source) == 1 and 1001 or 1090 end
function GetPlayerRoutingBucket(_) return 0 end
function GetEntityCoords(entity)
    if entity == 1001 then return playerCoords[1] end
    return entities[entity] and entities[entity].coords or { x = 0, y = 0, z = 0 }
end
function GetVehiclePedIsIn(_, _) return 0 end
function DoesEntityExist(entity) return entity == 1001 or entity == 1090 or entities[entity] ~= nil end
function GetEntityType(entity) return entities[entity] and entities[entity].type or 1 end
function IsPedAPlayer(entity) return entity == 1001 or entity == 1090 end
function NetworkGetFirstEntityOwner(entity) return entities[entity] and entities[entity].owner or 0 end
function NetworkGetEntityOwner(entity) return NetworkGetFirstEntityOwner(entity) end
function GetEntityModel(entity) return entities[entity] and entities[entity].model or 0 end
function GetEntityPopulationType(entity) return entities[entity] and entities[entity].population or 7 end
function GetEntityRoutingBucket(_) return 0 end
function joaat(name) return name == 'WEAPON_PISTOL' and 1001 or (name == 'WEAPON_STUNGUN' and 1002 or 9999) end
function CancelEvent() cancelCount = cancelCount + 1 end
function DeleteEntity(_) deleteCount = deleteCount + 1 end
function DropPlayer(_, _) dropCount = dropCount + 1 end
function TriggerClientEvent(_, _, _) notifications = notifications + 1 end
function Wait(_) end
function CreateThread(_) end
function SetTimeout(_, callback) callback() end
function RegisterNetEvent(name, callback)
    if callback then
        handlers[name] = handlers[name] or {}
        handlers[name][#handlers[name] + 1] = callback
    end
end
function AddEventHandler(name, callback)
    handlers[name] = handlers[name] or {}
    handlers[name][#handlers[name] + 1] = callback
end

MZBan = {
    IsoUtc = function(value) return 'iso:' .. tostring(value) end,
    JsonEncode = function(_) return '{}' end,
    AuditPrint = function(_, _) end,
    GetIdentifiers = function(source)
        local player = players[tonumber(source)] or {}
        return { byType = { license = player.license, fivem = player.fivem } }
    end,
    Flags = { IsTrusted = function() return false end }
}

local resources = {
    mz_core = {
        HasGlobalPermission = function(_, source, permission)
            return permissions[tonumber(source)] and permissions[tonumber(source)][permission] == true
        end,
        ResolvePlayerIdentity = function(_, source)
            local player = players[tonumber(source)]
            return player and {
                ok = player.characterActive ~= false,
                active = player.characterActive ~= false,
                characterId = player.characterActive ~= false and tonumber(source) or nil,
                citizenid = player.citizenid,
                name = player.name
            } or { ok = false }
        end,
        CreateDetailedLog = function() return 1 end
    },
    mz_notify = { Notify = function() notifications = notifications + 1 return true end },
    mz_inventory = {
        IsWeaponAuthorized = function(_, _, weaponHash)
            if projectileAuthorized then return true, 'weapon_authorized', { weaponHash = weaponHash } end
            return false, 'weapon_hash_mismatch', { weaponHash = 1001 }
        end
    },
    mz_admin = { IsNoClipEnabled = function() return adminNoClip end }
}

exports = setmetatable({}, {
    __call = function() end,
    __index = function(_, resource) return resources[resource] end
})

assert(loadfile('../server/incidents.lua'))()
assert(loadfile('../server/enforcement.lua'))()
assert(loadfile('../server/entity_classification.lua'))()
assert(loadfile('../server/entity_guard.lua'))()
assert(loadfile('../server/telemetry_guard.lua'))()
assert(loadfile('../server/event_guard.lua'))()
assert(loadfile('../server/aim_guard.lua'))()
assert(loadfile('../server/security_status.lua'))()

for entity = 2001, 2003 do
    entities[entity] = { type = 1, owner = 1, model = 5000 + entity, population = 7, coords = { x = 1, y = 1, z = 1 } }
    for _, callback in ipairs(handlers.entityCreated or {}) do callback(entity) end
end
check(#MZBan.Incidents.List({ filter = 'entity' }) == 1, 'entity rate creates one aggregated entity incident')

for entity = 2010, 2015 do
    entities[entity] = { type = 1, owner = 1, model = 6000 + entity, population = 5, coords = { x = 1, y = 1, z = 1 } }
    for _, callback in ipairs(handlers.entityCreated or {}) do callback(entity) end
end
check(#MZBan.Incidents.List({ filter = 'entity' }) == 1, 'ambient population created a rate incident')
check(MZBan.EntityClassification.Status().counters['ped:ambient'] == 6, 'ambient population metrics missing')

timer = timer + 1000
MZBan.TelemetryGuard.AcceptReport(1, 'player_godmode_suspect', {
    invincible = true, damageDisabled = true, fullProofs = false, health = 200, armour = 100
})
check(#MZBan.Incidents.List({ filter = 'player_state' }) == 1, 'validated client telemetry creates player-state incident')
players[1].characterActive = false
check(MZBan.TelemetryGuard.AcceptReport(1, 'player_invisible_suspect', { alpha = 0 }) == false,
    'selection lifecycle telemetry was not rejected')
players[1].characterActive = true
check(MZBan.TelemetryGuard.AcceptReport(1, 'forged_code', {}) == false, 'unknown client code is rejected')

MZBan.TelemetryGuard.SampleMovement(1, timer)
timer = timer + 1000
playerCoords[1] = { x = 500.0, y = 0.0, z = 0.0 }
MZBan.TelemetryGuard.SampleMovement(1, timer)
check(#MZBan.Incidents.List({ filter = 'movement' }) == 1, 'server position delta creates movement incident')
local movementIncident = MZBan.Incidents.List({ filter = 'movement' })[1]
adminNoClip = true
timer = timer + 1000
playerCoords[1] = { x = 1000.0, y = 0.0, z = 0.0 }
MZBan.TelemetryGuard.SampleMovement(1, timer)
check(MZBan.Incidents.Get(movementIncident.id).count == 1,
    'authorized admin noclip was scored before context resolution')
adminNoClip = false

MZBan.EventGuard.Observe(1, 'explosion', 2, {})
MZBan.EventGuard.Observe(1, 'explosion', 2, {})
MZBan.EventGuard.Observe(1, 'explosion', 2, {})
check(#MZBan.Incidents.List({ filter = 'event' }) == 1, 'event rate creates event incident')

for _, callback in ipairs(handlers.startProjectileEvent or {}) do
    callback(1, { weaponHash = 1001, projectileHash = 7001 })
end
local eventCountBeforeUnauthorized = #MZBan.Incidents.List({ filter = 'event' })
projectileAuthorized = false
for _, callback in ipairs(handlers.startProjectileEvent or {}) do
    callback(1, { weaponHash = 2002, projectileHash = 7002 })
end
local projectileIncident = MZBan.Incidents.List({ filter = 'event' })[1]
check(#MZBan.Incidents.List({ filter = 'event' }) == eventCountBeforeUnauthorized + 1
    and projectileIncident.code == 'projectile_weapon_unauthorized',
    'projectile authority did not distinguish authorized from unauthorized state')

for index = 1, 5 do
    MZBan.AimGuard.Observe(1, { weaponType = 1001, hitComponent = index <= 4 and 31086 or 0 })
end
check(#MZBan.Incidents.List({ filter = 'aim' }) == 0, 'single aim window does not create incident')
timer = timer + 60001
for index = 1, 5 do
    MZBan.AimGuard.Observe(1, { weaponType = 1001, hitComponent = index <= 4 and 31086 or 0 })
end
local aimList = MZBan.Incidents.List({ filter = 'aim' })
check(#aimList == 1 and aimList[1].confidence == 'medium', 'repeated aim windows create medium-confidence incident')

local summary = MZBan.Incidents.Summary()
check(summary.categories.entity == 1 and summary.categories.aim == 1, 'summary counts generic categories')
local status = MZBan.Security.Status()
check(status.alertOnly == true and status.autoKick == false and status.autoBan == false, 'combined status remains alert-only')
check(status.modules.entity.mode == 'observe' and status.modules.aim.mode == 'observe', 'new modules expose observe mode')
check(cancelCount == 0 and deleteCount == 0 and dropCount == 0, 'observers never cancel delete kick or ban')

Config.EntityGuard.mode = 'mitigate'
Config.DetectorActions.entity_model_blocked = 'mitigate'
Config.EntityGuard.cancelHighConfidence = true
entities[3000] = { type = 1, owner = 1, model = 999999, population = 7, coords = { x = 1, y = 1, z = 1 } }
for _, callback in ipairs(handlers.entityCreating or {}) do callback(3000) end
check(cancelCount == 0, 'entityCreating canceled without runtime validation')
Config.EntityGuard.runtimeValidated = true
entities[3001] = { type = 1, owner = 1, model = 999999, population = 7, coords = { x = 1, y = 1, z = 1 } }
for _, callback in ipairs(handlers.entityCreating or {}) do callback(3001) end
check(cancelCount == 1 and deleteCount == 0 and dropCount == 0,
    'validated mitigate mode did not cancel blocked entity creation')
Config.EntityGuard.mode = 'observe'
Config.DetectorActions.entity_model_blocked = nil

local clientFile = assert(io.open('../client/security_telemetry.lua', 'rb'))
local clientSource = clientFile:read('*a')
clientFile:close()
check(clientSource:find('local proofsKnown, bullet, fire, explosion, collision, melee, _, _, drown = GetEntityProofs(ped)', 1, true) ~= nil,
    'godmode observer shifts GET_ENTITY_PROOFS return/out parameters')
check(clientSource:find('local fullProofs = proofsKnown == true', 1, true) ~= nil,
    'godmode observer accepts proofs when native read failed')
check(clientSource:find('local bullet, fire, explosion, collision, melee, _, _, drown = GetEntityProofs(ped)', 1, true) == nil,
    'legacy shifted GET_ENTITY_PROOFS read remains active')

if #failures > 0 then
    io.stderr:write(('security_observers_harness: %d/%d checks failed\n'):format(#failures, checks))
    for _, failure in ipairs(failures) do io.stderr:write(' - ' .. failure .. '\n') end
    os.exit(1)
end

print(('security_observers_harness: ok (%d checks)'):format(checks))
