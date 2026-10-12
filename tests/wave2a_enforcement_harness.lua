local failures, checks = {}, 0
local function check(condition, label)
    checks = checks + 1
    if not condition then failures[#failures + 1] = label end
end

local timer = 100000
local players = {
    [1] = {
        name = 'Target One', citizenid = 'CID-1', accountId = 11, sessionId = 101,
        license = 'license:one', fivem = 'fivem:one'
    }
}
local incidentSaveOk, actionSaveOk, banSaveOk = true, true, true
local incidentWrites, signalWrites, actionRows, auditRows = 0, 0, {}, {}
local mitigations, drops, banCreates = 0, 0, 0
local dropFails = false
local activeBans = {}

Config = {
    Integration = { CoreResource = 'mz_core' },
    Privacy = { StoreTokensLocal = true },
    SecurityAlerts = {
        notifyStaff = false, aggregateWindowMs = 15000, duplicateCooldownMs = 100,
        incidentTtlMs = 3600000, maxIncidents = 100, maxEvidencePerIncident = 10,
        maxNotesPerIncident = 5, permissions = {},
        riskPoints = {
            entity_model_blocked = 70,
            weapon_damage_no_equipped_weapon = 70,
            player_godmode_suspect = 40,
            client_resource_presence_missing = 20
        }
    },
    WeaponGuard = { riskPoints = {} }, EntityGuard = {}, MovementGuard = {},
    PlayerStateGuard = {}, EventGuard = {}, AimGuard = {},
    IncidentPersistence = {
        enabled = true, updateDebounceMs = 5000, flushIntervalMs = 2000,
        maxWritesPerMinute = 1000, maxPendingIncidents = 100,
        maxPendingSignals = 64, rawSignalWindowMs = 10000,
        rawSignalBurst = 4, rawSignalRepresentativeEvery = 100
    },
    Enforcement = {
        DefaultMode = 'passive', AutomaticKickEnabled = false, AutomaticBanEnabled = false,
        RequireStableIdentity = true, RequireConfirmedEvidence = true,
        OnMitigationFailure = 'log_only'
    },
    DetectorActions = {}
}

function GetGameTimer() return timer end
function GetCurrentResourceName() return 'mz_banguard' end
function GetResourceState(name) return name == 'mz_core' and 'started' or 'missing' end
function GetPlayerPing(source) return players[tonumber(source)] and 50 or 0 end
function GetPlayerName(source) return players[tonumber(source)] and players[tonumber(source)].name or nil end
function GetPlayers() return {} end
function GetPlayerPed(source) return players[tonumber(source)] and (1000 + tonumber(source)) or 0 end
function DoesEntityExist(entity) return entity == 1001 end
function GetEntityCoords(_) return { x = 1.0, y = 2.0, z = 3.0 } end
function GetPlayerRoutingBucket(_) return 0 end
function GetPlayerIdentifiers(source)
    local player = players[tonumber(source)]
    return player and { player.license, player.fivem } or {}
end
function DropPlayer(_, _)
    if dropFails then error('fixture_drop_failed') end
    drops = drops + 1
end
function AddEventHandler(_, _) end
function CreateThread(_) end
function Wait(_) end

local function encode(value)
    if type(value) ~= 'table' then return tostring(value or '') end
    local out = {}
    for key, item in pairs(value) do
        if type(item) ~= 'table' then out[#out + 1] = tostring(key) .. '=' .. tostring(item) end
    end
    table.sort(out)
    return table.concat(out, ';')
end

MZBan = {
    IsoUtc = function(value) return 'iso:' .. tostring(value) end,
    JsonEncode = encode,
    JsonDecode = function(value, fallback) return type(value) == 'table' and value or fallback or {} end,
    AuditPrint = function(...) auditRows[#auditRows + 1] = { ... } end,
    SafePlayerName = function(source) return GetPlayerName(source) or 'system' end,
    GetIdentifiers = function(source)
        local player = players[tonumber(source)] or {}
        return { byType = { license = player.license, fivem = player.fivem } }
    end,
    GetPlayerTokensSafe = function() return { 'token:test' } end,
    DB = {
        IsReady = function() return true end,
        SaveIncident = function(_)
            incidentWrites = incidentWrites + 1
            if incidentSaveOk == 'timeout' then error('fixture_database_timeout') end
            return incidentSaveOk
        end,
        SaveSecuritySignal = function(_) signalWrites = signalWrites + 1 return true end,
        SaveIncidentAction = function(payload)
            if actionSaveOk ~= true then return false end
            actionRows[#actionRows + 1] = {
                incident_id = payload.incident_id,
                action = payload.action,
                meta = payload.meta,
                meta_json = payload.meta,
                created_at = payload.created_at
            }
            return #actionRows
        end,
        LoadIncidentActions = function(incidentId)
            local rows = {}
            for _, row in ipairs(actionRows) do
                if row.incident_id == incidentId then rows[#rows + 1] = row end
            end
            return rows
        end,
        Audit = function(action, payload) auditRows[#auditRows + 1] = { action, payload } return true end
    },
    Bans = {
        FindActiveByIncidentId = function(incidentId) return activeBans[incidentId] end,
        Create = function(data)
            banCreates = banCreates + 1
            if banSaveOk ~= true then return nil, 'persistence_failed' end
            local incidentId = tostring(data.evidence or ''):match('incident_id=([^;]+)')
            local ban = { public_id = 'MZB-TEST-' .. tostring(banCreates), reason = data.reason }
            activeBans[incidentId] = ban
            return ban
        end,
        FormatKickMessage = function(ban) return 'ban:' .. tostring(ban.public_id) end
    }
}

local resources = {
    mz_core = {
        ResolvePlayerIdentity = function(_, source)
            local player = players[tonumber(source)]
            return player and {
                ok = true, active = true, citizenid = player.citizenid,
                accountId = player.accountId, sessionId = player.sessionId,
                characterId = player.accountId, name = player.name
            } or { ok = false }
        end,
        CreateDetailedLog = function() return 1 end,
        HasGlobalPermission = function() return false end
    }
}
exports = setmetatable({}, {
    __call = function() end,
    __index = function(_, name) return resources[name] end
})

assert(loadfile('../server/incidents.lua'))()
assert(loadfile('../server/enforcement.lua'))()

local sequence = 0
local function record(code, mode, capability)
    sequence = sequence + 1
    timer = timer + 20000
    Config.DetectorActions[code] = mode
    return MZBan.Incidents.Record({
        source = 1, code = code, subject = 'wave2a:' .. tostring(sequence),
        origin = 'server_event', confidence = 'high', culpability = 'supported',
        evidence = { fixture = sequence }, enforcement = capability
    })
end

local capability = {
    supported = true,
    execute = function()
        mitigations = mitigations + 1
        return true, 'blocked', 'fixture_blocked'
    end
}

local incident, _, _, execution = record('entity_model_blocked', 'passive', capability)
check(incident ~= nil and execution.resolved_mode == 'passive', 'PASSIVE nao foi resolvido')
check(execution.executed_action == 'record' and mitigations == 0 and drops == 0,
    'PASSIVE executou mitigacao ou punicao')

incident, _, _, execution = record('entity_model_blocked', 'mitigate', capability)
check(execution.executed_action == 'mitigate' and execution.mitigation_result == 'blocked',
    'MITIGATE nao registrou bloqueio suportado')
check(mitigations == 1 and drops == 0, 'MITIGATE nao ficou limitado a mitigacao')

incident, _, _, execution = record('entity_model_blocked', 'mitigate', {
    supported = false, reason = 'fixture_not_supported'
})
check(execution.execution_result == 'unsupported' and execution.mitigation_result == 'not_supported',
    'MITIGATE sem suporte nao registrou not_supported')

incident, _, _, execution = record('entity_model_blocked', 'kick', capability)
check(execution.execution_result == 'blocked_by_policy' and execution.reason == 'automatic_kick_disabled',
    'KICK automatico desativado nao falhou fechado')
check(drops == 0, 'KICK desativado removeu jogador')

Config.Enforcement.AutomaticKickEnabled = true
incident, _, _, execution = record('entity_model_blocked', 'kick', capability)
local kickIncidentId = incident.id
check(execution.execution_result == 'success' and execution.executed_action == 'kick_requested',
    'KICK confirmado nao executou no mock')
check(drops == 1 and execution.account_id == 11 and execution.session_id == 101,
    'KICK nao preservou identidade persistente')

MZBan.Enforcement.Process(incident, { created = false, mitigation = capability })
check(drops == 1, 'KICK foi repetido para o mesmo incidente')

local original = players[1]
local reuseCapability = {
    supported = true,
    execute = function()
        mitigations = mitigations + 1
        players[1] = {
            name = 'Reused Source', citizenid = 'CID-REUSED', accountId = 99, sessionId = 999,
            license = 'license:reused', fivem = 'fivem:reused'
        }
        return true, 'blocked', 'fixture_blocked_then_source_reused'
    end
}
incident, _, _, execution = record('entity_model_blocked', 'kick', reuseCapability)
check(execution.execution_result == 'identity_mismatch' and drops == 1,
    'source reuse nao bloqueou KICK automatico')
players[1] = original

local disconnectCapability = {
    supported = true,
    execute = function()
        mitigations = mitigations + 1
        players[1] = nil
        return true, 'blocked', 'fixture_blocked_then_disconnect'
    end
}
incident, _, _, execution = record('entity_model_blocked', 'kick', disconnectCapability)
check(execution.execution_result == 'insufficient_evidence' and drops == 1,
    'jogador desconectado foi tratado como alvo valido de KICK')
players[1] = original

Config.Enforcement.AutomaticBanEnabled = false
incident, _, _, execution = record('weapon_damage_no_equipped_weapon', 'ban', capability)
check(execution.execution_result == 'blocked_by_policy' and execution.reason == 'automatic_ban_disabled',
    'BAN automatico desativado nao falhou fechado')
check(banCreates == 0, 'BAN desativado persistiu punicao')

Config.Enforcement.AutomaticBanEnabled = true
banSaveOk = false
incident, _, _, execution = record('weapon_damage_no_equipped_weapon', 'ban', capability)
check(execution.execution_result == 'failed' and execution.reason == 'persistence_failed',
    'falha transacional do BAN nao foi exposta')
check(drops == 1, 'falha de persistencia do BAN desconectou jogador')

banSaveOk = true
incident, _, _, execution = record('weapon_damage_no_equipped_weapon', 'ban', capability)
local banIncident = incident
check(execution.execution_result == 'success' and execution.executed_action == 'ban',
    'BAN confirmado nao foi persistido no mock')
check(banCreates == 2 and drops == 2, 'BAN persistido nao solicitou exatamente uma desconexao')
MZBan.Enforcement.Process(banIncident, { created = false, mitigation = capability })
check(banCreates == 2 and drops == 2, 'BAN foi duplicado para o mesmo incidente')

dropFails = true
incident, _, _, execution = record('weapon_damage_no_equipped_weapon', 'ban', capability)
check(execution.execution_result == 'success' and execution.executed_action == 'ban'
    and execution.reason:find('disconnect_failed', 1, true) ~= nil,
    'BAN persistido com falha de desconexao nao preservou a verdade')
check(banCreates == 3 and drops == 2, 'falha de desconexao alterou confirmacao do BAN')
dropFails = false

actionSaveOk = false
incident, _, _, execution = record('entity_model_blocked', 'kick', capability)
check(execution.execution_result == 'failed' and execution.reason == 'execution_audit_persistence_failed'
    and drops == 2, 'falha da auditoria persistente nao bloqueou KICK')
actionSaveOk = true

incidentSaveOk = false
incident, _, _, execution = record('entity_model_blocked', 'kick', capability)
check(execution.execution_result == 'failed' and execution.reason ~= nil and drops == 2,
    'falha de persistencia do incidente nao bloqueou atuacao automatica')
incidentSaveOk = true

incidentSaveOk = 'timeout'
incident, _, _, execution = record('entity_model_blocked', 'kick', capability)
check(execution.execution_result == 'failed' and drops == 2,
    'timeout de banco foi tratado como confirmacao de persistencia')
incidentSaveOk = true
local retriedIncidents = MZBan.Incidents.FlushPersistence(true)
check(retriedIncidents >= 2 and MZBan.Incidents.PersistenceStatus().pendingIncidents == 0,
    'retry de incidentes nao drenou falha e timeout pendentes')

incident, _, _, execution = record('player_godmode_suspect', 'ban', capability)
check(execution.execution_result == 'insufficient_evidence'
    and execution.reason == 'detector_excluded_from_automation',
    'godmode observacional foi elegivel a BAN automatico')
check(banCreates == 3 and drops == 2, 'detector excluido executou punicao')

incident, _, _, execution = record('client_resource_presence_missing', 'ban', capability)
check(execution.execution_result == 'insufficient_evidence'
    and execution.reason == 'detector_excluded_from_automation',
    'heartbeat ausente isolado foi elegivel a BAN automatico')
check(banCreates == 3 and drops == 2, 'falso positivo de heartbeat executou punicao')

Config.DetectorActions.entity_model_blocked = 'invalid-mode'
local auditBeforeInvalid = #auditRows
local configured, resolved = MZBan.Enforcement.ResolveMode('entity_model_blocked')
check(configured == 'invalid-mode' and resolved == 'passive', 'configuracao invalida nao caiu para PASSIVE')
check(#auditRows > auditBeforeInvalid, 'configuracao invalida nao foi auditada')

local persistedBanActions = {}
for _, row in ipairs(actionRows) do
    if row.incident_id == banIncident.id then persistedBanActions[#persistedBanActions + 1] = row end
end
MZBan.Incidents.Hydrate({{
    incident_id = banIncident.id, code = banIncident.code, category = banIncident.category,
    status = 'open', severity = 'critical', confidence = 'high', risk_score = 90,
    player_name = banIncident.playerName, citizenid = banIncident.citizenid,
    account_id = banIncident.accountId, session_id = banIncident.sessionId,
    first_seen_at = os.time(), last_seen_at = os.time(), count = 1, suppressed_count = 0,
    source_at_first_seen = 1, source_at_last_seen = 1,
    summary_json = { culpability = 'supported', origin = 'server_event', aggregateKey = 'hydrated' },
    evidence_json = {}, timeline_snapshot_json = {}, mitigation_json = {}, lab = 0
}})
local hydrated = MZBan.Incidents.Get(banIncident.id)
local beforeRestartBanCreates, beforeRestartDrops = banCreates, drops
execution = MZBan.Enforcement.Process(hydrated, { created = false, mitigation = capability })
check(execution.reason == 'already_executed' and banCreates == beforeRestartBanCreates
    and drops == beforeRestartDrops, 'restart/hydration repetiu BAN ja solicitado')
check(#persistedBanActions >= 2, 'trilha de solicitacao/resultado do BAN nao foi persistida')
check(kickIncidentId ~= nil and incidentWrites > 0 and signalWrites > 0,
    'incidentes e sinais nao foram persistidos pelo harness')

if #failures > 0 then
    for _, failure in ipairs(failures) do io.stderr:write(' - ' .. failure .. '\n') end
    io.stderr:write(('wave2a_enforcement_harness: %d/%d checks failed\n'):format(#failures, checks))
    os.exit(1)
end
print(('wave2a_enforcement_harness: ok (%d checks)'):format(checks))
