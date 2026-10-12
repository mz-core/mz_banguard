local failures = {}
local checks = 0

local function check(condition, label)
    checks = checks + 1
    if not condition then failures[#failures + 1] = label end
end

local timer = 20000
local resourceStates = { mz_core = 'started', mz_inventory = 'started', mz_notify = 'started', mz_banguard = 'started' }
local players = {
    [1] = { name = 'Target One', citizenid = 'CID-1', license = 'license:one', fivem = 'fivem:one' },
    [2] = { name = 'Target Two', citizenid = 'CID-2', license = 'license:two', fivem = 'fivem:two' },
    [3] = { name = 'Target Three', citizenid = 'CID-3', license = 'license:three', fivem = 'fivem:three' },
    [90] = { name = 'Staff', citizenid = 'STAFF-90', license = 'license:staff', fivem = 'fivem:staff' }
}
local authority = {}
local permissions = {}
local handlers = {}
local exported = {}
local notificationCount = 0
local cancelCount = 0
local invokingResource = 'mz_admin'
local hierarchyAllowed = true
local deathStates = {}
local hashes = { WEAPON_PISTOL = 1001, WEAPON_SMG = 1002, WEAPON_RPG = 1003, WEAPON_UNARMED = 2725352035 }

Config = {
    Integration = { CoreResource = 'mz_core', InventoryResource = 'mz_inventory' },
    Enforcement = { DefaultMode = 'passive', AutomaticKickEnabled = false, AutomaticBanEnabled = false },
    DetectorActions = {},
    WeaponGuard = {
        enabled = true,
        mode = 'observe',
        cancelHighConfidence = false,
        runtimeValidated = false,
        notifyStaff = true,
        transitionWindowMs = 2500,
        aggregateWindowMs = 10000,
        duplicateCooldownMs = 1500,
        notificationCooldownMs = 10000,
        incidentTtlMs = 60000,
        cleanupIntervalMs = 60000,
        maxIncidents = 10,
        maxEvidencePerIncident = 3,
        maxNotesPerIncident = 3,
        rateWindowMs = 1000,
        rateEventThreshold = 2,
        rateProfiles = {
            default = { windowMs = 1000, threshold = 4 },
            WEAPON_PISTOL = { windowMs = 1000, threshold = 2 }
        },
        trustedConsumers = { mz_admin = true },
        permissions = {
            view = 'alerts.view', details = 'alerts.details', acknowledge = 'alerts.ack', note = 'alerts.note',
            clear = 'alerts.clear', identifiers = 'alerts.identifiers', spectate = 'alerts.spectate',
            gotoPlayer = 'alerts.goto', kick = 'alerts.kick', ban = 'alerts.ban'
        },
        riskPoints = {
            weapon_damage_no_equipped_weapon = 45, weapon_damage_hash_mismatch = 35,
            weapon_damage_unknown_hash = 25, weapon_damage_payload_invalid = 20,
            weapon_damage_rate_suspect = 25, weapon_damage_session_not_ready = 0,
            weapon_damage_transition_window = 0
        },
        knownWeaponNames = { 'WEAPON_PISTOL', 'WEAPON_SMG', 'WEAPON_RPG' },
        unarmedWeaponNames = { 'WEAPON_UNARMED' }
    }
}

function GetGameTimer() return timer end
function GetResourceState(name) return resourceStates[name] or 'missing' end
function GetCurrentResourceName() return 'mz_banguard' end
function GetInvokingResource() return invokingResource end
function GetPlayerPing(source) return players[tonumber(source)] and 50 or 0 end
function GetPlayerName(source) return players[tonumber(source)] and players[tonumber(source)].name or nil end
function GetPlayerPed(source) return 100 + tonumber(source) end
function NetworkGetEntityFromNetworkId(netId) return netId == 501 and 900 or 0 end
function DoesEntityExist(entity) return entity == 900 or (entity >= 101 and entity <= 190) end
function GetEntityType(entity) return entity == 900 and 1 or 1 end
function IsPedAPlayer(entity) return entity == 900 end
function NetworkGetEntityOwner(entity) return entity == 900 and 2 or 0 end
function GetEntityCoords(entity)
    if entity == 900 then return { x = 13, y = 14, z = 0 } end
    return { x = 0, y = 0, z = 0 }
end
function GetPlayers() return { '1', '2', '3', '90' } end
function GetPlayerIdentifiers(source)
    local player = players[tonumber(source)]
    return player and { player.license, player.fivem } or {}
end
function joaat(name) return hashes[name] or 900000 + #tostring(name) end
function AddEventHandler(name, callback) handlers[name] = callback end
function CreateThread(_) end
function Wait(_) end
function CancelEvent() cancelCount = cancelCount + 1 end
function TriggerClientEvent(_, _, _) notificationCount = notificationCount + 1 end

MZBan = {
    IsoUtc = function(value) return 'iso:' .. tostring(value) end,
    JsonEncode = function(_) return '{}' end,
    AuditPrint = function(_, _) end,
    GetIdentifiers = function(source)
        local player = players[tonumber(source)] or {}
        return { byType = { license = player.license, fivem = player.fivem } }
    end
}

local resources = {
    mz_core = {
        HasGlobalPermission = function(_, source, permission)
            return permissions[tonumber(source)] and permissions[tonumber(source)][permission] == true
        end,
        ResolvePlayerIdentity = function(_, source)
            local player = players[tonumber(source)]
            if not player then return { ok = false } end
            return { ok = true, citizenid = player.citizenid, name = player.name }
        end,
        CreateDetailedLog = function() return 123 end,
        GetDeathState = function(_, source)
            return true, { deathState = deathStates[tonumber(source)] or 'alive', revision = 7 }
        end,
        CanStaffActOnPlayer = function(_, _, _) return hierarchyAllowed, hierarchyAllowed and 'authorized' or 'hierarchy_denied' end
    },
    mz_inventory = {
        GetEquippedWeaponState = function(_, source)
            local state = authority[tonumber(source)]
            if state == false then return nil, 'player_not_loaded' end
            if type(state) == 'table' then return state, state.equipped and 'weapon_equipped' or 'weapon_not_equipped' end
            local player = players[tonumber(source)]
            return { equipped = false, citizenid = player and player.citizenid, lastTransitionAt = 0 }, 'weapon_not_equipped'
        end
    },
    mz_notify = {
        Notify = function(_, _, _) notificationCount = notificationCount + 1 return true end
    }
}

exports = setmetatable({}, {
    __call = function(_, name, callback) exported[name] = callback end,
    __index = function(_, resource) return resources[resource] end
})

assert(loadfile('../server/incidents.lua'))()
assert(loadfile('../server/enforcement.lua'))()
assert(loadfile('../server/weapon_guard.lua'))()
assert(loadfile('../server/alerts_api.lua'))()

permissions[90] = {
    ['alerts.view'] = true,
    ['alerts.details'] = true,
    ['alerts.ack'] = true,
    ['alerts.note'] = true,
    ['alerts.clear'] = true,
    ['alerts.spectate'] = true,
    ['alerts.goto'] = true
}

authority[1] = { equipped = true, citizenid = 'CID-1', weaponHash = 1001, weaponName = 'WEAPON_PISTOL', ammo = 12, lastTransitionAt = 10000 }
handlers.weaponDamageEvent(1, { weaponType = 1001, weaponDamage = 20 })
check(MZBan.Incidents.Summary().total == 0, 'authorized damage must not create incident')

authority[1] = { equipped = false, citizenid = 'CID-1', lastTransitionAt = 0 }
handlers.weaponDamageEvent(1, { weaponType = 2725352035, weaponDamage = 5 })
check(MZBan.Incidents.Summary().total == 0, 'legitimate unarmed damage created a weapon incident')

authority[1] = { equipped = false, citizenid = 'CID-1', lastTransitionAt = 0, transitionRevision = 8, ammoRevision = 3 }
handlers.weaponDamageEvent(1, { weaponType = 1001, weaponDamage = 20, hitGlobalId = 501, hitComponent = 20 })
local firstList = MZBan.Incidents.List({})
check(#firstList == 1 and firstList[1].code == 'weapon_damage_no_equipped_weapon', 'no equipped weapon classification')
local firstId = firstList[1].id
local firstEvidence = MZBan.Incidents.Get(firstId).evidence[1]
check(firstEvidence.targetType == 'player' and firstEvidence.targetOwner == 2, 'target context was not retained')
check(firstEvidence.targetDistance == 19.1 and firstEvidence.hitComponent == 20, 'target distance/component evidence incorrect')
check(firstEvidence.transitionRevision == 8 and firstEvidence.ammoRevision == 3, 'authority revisions were not retained')
handlers.weaponDamageEvent(1, { weaponType = 1001, weaponDamage = 21 })
check(MZBan.Incidents.Get(firstId).count == 2, 'same incident aggregates')
check(MZBan.Incidents.Get(firstId).suppressedCount == 1, 'duplicate evidence is suppressed inside cooldown')

timer = timer + 2000
handlers.weaponDamageEvent(1, { weaponType = 1001, weaponDamage = 22 })
check(#MZBan.Incidents.Get(firstId).evidence == 2, 'evidence is retained after duplicate cooldown')

authority[2] = { equipped = false, citizenid = 'CID-2', lastTransitionAt = timer - 100 }
handlers.weaponDamageEvent(2, { weaponType = 1001 })
check(MZBan.Incidents.List({ player = 'CID-2' })[1].code == 'weapon_damage_transition_window', 'transition window is isolated')

timer = timer + 3000
authority[2] = { equipped = true, citizenid = 'CID-2', weaponHash = 1002, weaponName = 'WEAPON_SMG', ammo = 30, lastTransitionAt = timer - 5000 }
handlers.weaponDamageEvent(2, { weaponType = 1001 })
check(MZBan.Incidents.List({ player = 'CID-2' })[1].code == 'weapon_damage_hash_mismatch', 'known hash mismatch classification')
handlers.weaponDamageEvent(2, { weaponType = 777777 })
check(MZBan.Incidents.List({ player = 'CID-2' })[1].code == 'weapon_damage_unknown_hash', 'unknown hash classification')
handlers.weaponDamageEvent(2, {})
check(MZBan.Incidents.List({ player = 'CID-2' })[1].code == 'weapon_damage_payload_invalid', 'invalid payload classification')

authority[3] = false
handlers.weaponDamageEvent(3, { weaponType = 1001 })
check(MZBan.Incidents.List({ player = 'CID-3' })[1].code == 'weapon_damage_session_not_ready', 'not-loaded session classification')

check(MZBan.WeaponGuard.NormalizeHash(-1) == 4294967295, 'signed hash normalization')
authority[3] = { equipped = true, citizenid = 'CID-3', weaponHash = 1001, weaponName = 'WEAPON_PISTOL', ammo = 10, lastTransitionAt = 0 }
timer = timer + 2000
handlers.weaponDamageEvent(3, { weaponType = 1001 })
handlers.weaponDamageEvent(3, { weaponType = 1001 })
handlers.weaponDamageEvent(3, { weaponType = 1001 })
check(MZBan.Incidents.List({ player = 'CID-3' })[1].code == 'weapon_damage_rate_suspect', 'rate suspect classification')
check(cancelCount == 0, 'observe mode never cancels damage')

Config.WeaponGuard.mode = 'enforce'
Config.DetectorActions.weapon_damage_no_equipped_weapon = 'mitigate'
Config.DetectorActions.weapon_damage_hash_mismatch = 'mitigate'
Config.DetectorActions.weapon_damage_death_state_incompatible = 'mitigate'
Config.WeaponGuard.cancelHighConfidence = true
Config.WeaponGuard.runtimeValidated = false
authority[1] = { equipped = false, citizenid = 'CID-1', lastTransitionAt = 0 }
handlers.weaponDamageEvent(1, { weaponType = 1002 })
check(cancelCount == 0, 'enforcement without runtime validation remains inert')
Config.WeaponGuard.runtimeValidated = true
handlers.weaponDamageEvent(1, { weaponType = 1003 })
check(cancelCount == 1, 'fully armed high-confidence enforcement can cancel')
Config.WeaponGuard.mode = 'mitigate'
handlers.weaponDamageEvent(1, { weaponType = 1002 })
check(cancelCount == 2, 'mitigate mode did not cancel a validated canonical mismatch')
deathStates[2] = 'dead'
authority[2] = { equipped = true, citizenid = 'CID-2', weaponHash = 1002, weaponName = 'WEAPON_SMG', lastTransitionAt = 0 }
handlers.weaponDamageEvent(2, { weaponType = 1002 })
local deadIncident = MZBan.Incidents.List({ player = 'CID-2' })[1]
check(deadIncident and deadIncident.code == 'weapon_damage_death_state_incompatible'
    and deadIncident.culpability == 'supported' and cancelCount == 3,
    'canonical dead state did not block damage in mitigate mode')
deathStates[2] = 'alive'
Config.WeaponGuard.mode = 'observe'
Config.DetectorActions.weapon_damage_no_equipped_weapon = nil
Config.DetectorActions.weapon_damage_hash_mismatch = nil
Config.DetectorActions.weapon_damage_death_state_incompatible = nil

permissions[90]['alerts.view'] = nil
check(exported.ListSecurityIncidents(90, {}).ok == false, 'list requires view permission')
permissions[90]['alerts.view'] = true
check(exported.ListSecurityIncidents(90, {}).ok == true, 'authorized list succeeds')
check(exported.ListSecurityIncidents(1, {}).error == 'permission_denied', 'swapped callback source cannot borrow staff permission')
permissions[90]['alerts.details'] = nil
check(exported.GetSecurityIncident(90, firstId, false).ok == false, 'details permission is separate')
permissions[90]['alerts.details'] = true
check(exported.GetSecurityIncident(90, firstId, false).ok == true, 'details permission succeeds')
check(exported.GetSecurityIncident(90, firstId, true).ok == false, 'identifier permission is separate')
permissions[90]['alerts.identifiers'] = true
local identified = exported.GetSecurityIncident(90, firstId, true)
check(identified.ok and identified.data.incident.identifiers.masked.license == 'license:...','authorized masked identifier access succeeds')

check(exported.AcknowledgeSecurityIncident(90, firstId).ok == true, 'acknowledge operation')
check(exported.AddSecurityIncidentNote(90, firstId, 'reviewed by harness').ok == true, 'note operation')
check(exported.SetSecurityIncidentStatus(90, firstId, 'resolved').ok == true, 'status operation preserves incident')
check(exported.SetSecurityIncidentStatus(90, firstId, 'false_positive').ok == true, 'false-positive status is server authoritative')
check(MZBan.Incidents.Get(firstId) ~= nil and #MZBan.Incidents.Get(firstId).evidence >= 1, 'closing preserves evidence')

authority[2] = { equipped = true, citizenid = 'CID-2', weaponHash = 1002, weaponName = 'WEAPON_SMG', ammo = 30, lastTransitionAt = 0 }
hierarchyAllowed = false
local actionIncident = MZBan.Incidents.List({ player = 'CID-2' })[1]
check(exported.PrepareSecurityIncidentAction(90, actionIncident.id, 'goto').ok == false, 'action enforces hierarchy')
hierarchyAllowed = true
check(exported.PrepareSecurityIncidentAction(90, actionIncident.id, 'goto').ok == true, 'authorized online action returns target')
MZBan.Incidents.MarkSourceDisconnected(2)
check(exported.PrepareSecurityIncidentAction(90, actionIncident.id, 'goto').error == 'target_offline', 'offline target action is denied')
check(MZBan.Incidents.Get(actionIncident.id) ~= nil, 'disconnect preserves incident')

invokingResource = 'evil_resource'
check(exported.ListSecurityIncidents(90, {}).error == 'untrusted_resource', 'untrusted resource is denied')
invokingResource = 'mz_admin'

local beforeNotify = notificationCount
timer = timer + 12000
local notifyIncident = MZBan.Incidents.Get(firstId)
notifyIncident.status = 'open'
notifyIncident.severity = 'high'
MZBan.Incidents.NotifyStaff(notifyIncident)
local afterNotify = notificationCount
MZBan.Incidents.NotifyStaff(notifyIncident)
check(afterNotify == beforeNotify + 1 and notificationCount == afterNotify, 'staff notification permission and cooldown')

for index = 1, 12 do
    MZBan.Incidents.Record({ source = 1, code = 'weapon_damage_hash_mismatch', reportedWeaponHash = 2000 + index, authorizedWeaponHash = 1001 })
end
check(MZBan.Incidents.Summary().total <= 10, 'maximum in-memory incident limit')
timer = timer + 70000
local expired = MZBan.Incidents.Cleanup(timer)
check(expired > 0 and MZBan.Incidents.Summary().total == 0, 'TTL cleanup removes expired in-memory incidents')

check(type(exported.GetWeaponGuardStatus) == 'function', 'guard status export exists')
local guardStatus = exported.GetWeaponGuardStatus(90)
check(guardStatus.ok == true and guardStatus.data.guard.alertOnly == true, 'default guard policy is alert-only')
check(guardStatus.data.guard.autoKick == false and guardStatus.data.guard.autoBan == false, 'automatic punishment status is disabled')
check(type(handlers.weaponDamageEvent) == 'function', 'weaponDamageEvent observer registered')

if #failures > 0 then
    io.stderr:write(('weapon_guard_alert_center_harness: %d/%d checks failed\n'):format(#failures, checks))
    for _, failure in ipairs(failures) do io.stderr:write(' - ' .. failure .. '\n') end
    os.exit(1)
end

print(('weapon_guard_alert_center_harness: ok (%d checks)'):format(checks))
