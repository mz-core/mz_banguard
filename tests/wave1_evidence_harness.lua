local failures, checks = {}, 0
local function check(condition, label)
    checks = checks + 1
    if not condition then failures[#failures + 1] = label end
end

local timer = 100000
local handlers = {}
local writes, actions, labWrites, signalWrites = 0, 0, 0, 0
local lastPersisted
local players = {
    [1] = { name = 'Victim One', citizenid = 'CID-1', accountId = 11, sessionId = 101 },
    [2] = { name = 'Victim Two', citizenid = 'CID-2', accountId = 12, sessionId = 102 },
    [3] = { name = 'Victim Three', citizenid = 'CID-3', accountId = 13, sessionId = 103 },
    [4] = { name = 'Reusable Source', citizenid = 'CID-4', accountId = 14, sessionId = 104 },
    [90] = { name = 'Staff', citizenid = 'STAFF', accountId = 90, sessionId = 190 }
}

Config = {
    Integration = { CoreResource = 'mz_core' },
    Privacy = { RedactIdentifiersInOutput = true },
    SecurityAlerts = {
        notifyStaff = false, aggregateWindowMs = 15000, duplicateCooldownMs = 100,
        incidentTtlMs = 3600000, maxIncidents = 1000, maxEvidencePerIncident = 20,
        maxNotesPerIncident = 25, trustedConsumers = { mz_admin = true },
        permissions = { view = 'view', details = 'details', lab = 'lab' },
        riskPoints = {
            event_ptfx_rate_suspect = 35, crash_observed = 20, crash_cluster_suspect = 45
        }
    },
    WeaponGuard = { riskPoints = {} }, EntityGuard = {}, MovementGuard = {},
    PlayerStateGuard = {}, EventGuard = {}, AimGuard = {},
    SecurityCorrelation = {
        enabled = true, ttlMs = 30000, maxEntriesPerPlayer = 32, snapshotEntries = 16,
        labTtlMs = 120000, labMaxEntriesPerPlayer = 96, labSnapshotEntries = 64,
        maxDataKeys = 16, maxString = 128, crashClusterWindowMs = 5000,
        crashHistoryMs = 15000, crashMinimumVictims = 2
    },
    IncidentPersistence = { enabled = true, updateDebounceMs = 5000, flushIntervalMs = 2000 },
    LabMode = { enabled = true, defaultDurationSeconds = 3600, maximumDurationSeconds = 86400 },
    SecurityCanaries = { enabled = true, owners = { mz_inventory = 'inventory' } }
}

function GetGameTimer() return timer end
function GetCurrentResourceName() return 'mz_banguard' end
local invokingResource = 'mz_inventory'
function GetInvokingResource() return invokingResource end
function GetResourceState(name) return name == 'mz_core' and 'started' or 'missing' end
function GetPlayerName(source) return players[tonumber(source)] and players[tonumber(source)].name or nil end
function GetPlayerPing(source) return players[tonumber(source)] and 50 or 0 end
function GetPlayers() return {} end
function GetPlayerIdentifiers(source)
    return players[tonumber(source)] and { 'license:secret-' .. tostring(source), 'fivem:' .. tostring(source) } or {}
end
function GetPlayerPed(source) return players[tonumber(source)] and (1000 + tonumber(source)) or 0 end
function DoesEntityExist(entity) return entity >= 1001 and entity <= 1090 end
function GetEntityCoords(entity) return { x = entity, y = 2.0, z = 3.0 } end
function GetPlayerRoutingBucket(_) return 7 end
function AddEventHandler(name, callback)
    handlers[name] = handlers[name] or {}
    handlers[name][#handlers[name] + 1] = callback
end
function CreateThread(_) end
function Wait(_) end

local function escape(value)
    return tostring(value):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n')
end
local function encode(value)
    local kind = type(value)
    if kind == 'nil' then return 'null' end
    if kind == 'boolean' or kind == 'number' then return tostring(value) end
    if kind == 'string' then return '"' .. escape(value) .. '"' end
    local array, maximum = true, 0
    for key in pairs(value) do
        if type(key) ~= 'number' then array = false break end
        if key > maximum then maximum = key end
    end
    local out = {}
    if array then
        for index = 1, maximum do out[#out + 1] = encode(value[index]) end
        return '[' .. table.concat(out, ',') .. ']'
    end
    for key, item in pairs(value) do out[#out + 1] = encode(tostring(key)) .. ':' .. encode(item) end
    table.sort(out)
    return '{' .. table.concat(out, ',') .. '}'
end

local packed = {}
local function pack(name, value) packed[name] = value return '@@' .. name end

MZBan = {
    IsoUtc = function(value) return 'iso:' .. tostring(value) end,
    JsonEncode = encode,
    JsonDecode = function(value, fallback) return packed[tostring(value):gsub('^@@', '')] or fallback or {} end,
    AuditPrint = function() end,
    SafePlayerName = function(source) return GetPlayerName(source) or 'system' end,
    Redact = function(value) value = tostring(value or '') return value:sub(1, 8) .. '...' end,
    GetIdentifiers = function(source)
        return { byType = { license = 'license:secret-' .. tostring(source), fivem = 'fivem:' .. tostring(source) } }
    end,
    DB = {
        SaveIncident = function(data) writes = writes + 1 lastPersisted = data return true end,
        SaveSecuritySignal = function(_) signalWrites = signalWrites + 1 return true end,
        LoadSessionSignals = function(sessionId)
            return {{
                signal_id = 'SIG-SESSION', code = 'security_lease.issued', origin = 'correlation',
                confidence = 'contextual', culpability = 'contextual', source_id = 1,
                occurred_at = 1700000000, evidence_json = pack('session_signal', { capability = 'movement.teleport' })
            }}
        end,
        LoadSessionIncidents = function(sessionId)
            return {{
                incident_id = 'INC-SESSION', code = 'movement_teleport_suspect', status = 'open',
                severity = 'high', confidence = 'medium', first_seen_at = 1700000001,
                last_seen_at = 1700000001, count = 1, suppressed_count = 0, summary_json = '{}'
            }}
        end,
        SaveIncidentAction = function(_) actions = actions + 1 return true end,
        LoadIncidentActions = function() return {} end,
        SaveLabSubject = function(_) labWrites = labWrites + 1 return true end,
        Audit = function() return true end
    }
}

local registeredExports = {}
local resources = {
    mz_core = {
        ResolvePlayerIdentity = function(_, source)
            local player = players[tonumber(source)]
            return player and {
                ok = true, active = true, citizenid = player.citizenid,
                accountId = player.accountId, sessionId = player.sessionId,
                firstname = player.name, lastname = ''
            } or { ok = false }
        end,
        HasGlobalPermission = function() return true end,
        CreateDetailedLog = function() return 1 end
    }
}
exports = setmetatable({}, {
    __call = function(_, name, callback) registeredExports[name] = callback end,
    __index = function(_, name) return resources[name] end
})

dofile('../server/detector_catalog.lua')
dofile('../server/lab_mode.lua')
dofile('../server/security_correlation.lua')
dofile('../server/incidents.lua')

local canaryId, canaryError = registeredExports.RecordSecurityCanary(3, 'inventory', 'fixture_probe', {})
local canary = canaryId and MZBan.Incidents.Get(canaryId) or nil
check(canaryError == nil and canary ~= nil, 'canario do owner nao gerou incidente: ' .. tostring(canaryError))
check(canary and canary.code == 'canary_triggered' and canary.riskScore == 0,
    'canario do owner nao permaneceu observacional')
check(canary and canary.source == 3 and canary.subject == 'inventory:fixture_probe',
    'canario do owner nao preservou atribuicao de source/dominio')
invokingResource = 'mz_admin'
local deniedCanary, deniedReason = registeredExports.RecordSecurityCanary(3, 'inventory', 'fixture_probe', {})
check(deniedCanary == nil and deniedReason == 'canary_contract_denied',
    'canario aceitou caller fora do owner configurado')
invokingResource = 'mz_inventory'

for index = 1, 100 do
    timer = timer + 10
    MZBan.Incidents.Record({
        source = 3, code = 'event_ptfx_rate_suspect', subject = 'ptfx:1',
        confidence = 'medium', evidence = { effectHash = 123, amount = index, windowMs = 10000 }
    })
end
local aggregate = MZBan.Incidents.List({ player = 'CID-3' })[1]
check(aggregate and aggregate.count == 100, '100 sinais nao agregaram em um incidente')
check(writes <= 5, 'agregacao gerou writes demais antes do flush')
MZBan.Incidents.FlushPersistence(true)
check(writes <= 6, 'flush debounced gerou writes demais')
check(signalWrites >= 8 and signalWrites <= 10, 'amostragem de sinais brutos nao aplicou burst e representante')
check(MZBan.Incidents.Get(aggregate.id).rawSignalDroppedCount >= 90,
    'ocorrencias brutas descartadas nao foram contabilizadas no incidente')

MZBan.Incidents.Record({ source = 3, code = 'client_resource_presence_missing', subject = 'mz_inventory' })
MZBan.Incidents.Record({ source = 3, code = 'canary_triggered', subject = 'mz_inventory' })
check(#MZBan.Incidents.List({ filter = 'runtime' }) == 1, 'filtro da categoria runtime nao funcionou')
check(#MZBan.Incidents.List({ filter = 'canary' }) >= 1, 'filtro da categoria canary nao funcionou')

Config.SecurityAlerts.maxEvidencePerIncident = 2
for index = 1, 4 do
    timer = timer + 200
    MZBan.Incidents.Record({
        source = 3, code = 'event_ptfx_rate_suspect', subject = 'sampling-v3',
        confidence = 'medium', evidence = { effectHash = 456, amount = index }
    })
end
local sampled = MZBan.Incidents.List({ player = 'CID-3' }, { details = true })
local sampledDto
for _, item in ipairs(sampled) do if item.subject == 'sampling-v3' then sampledDto = item end end
check(sampledDto and sampledDto.occurrenceCount == 4 and sampledDto.retainedSampleCount == 2
    and sampledDto.droppedSampleCount == 2 and sampledDto.suppressedSampleCount == 0,
    'accounting de evidence sampling ficou incoerente')
Config.SecurityAlerts.maxEvidencePerIncident = 20

local saved = lastPersisted
local row = {
    incident_id = saved.incident_id, code = saved.code, category = saved.category, status = saved.status,
    severity = saved.severity, confidence = saved.confidence, risk_score = saved.risk_score,
    player_name = saved.player_name, citizenid = saved.citizenid, account_id = saved.account_id,
    session_id = saved.session_id, first_seen_at = saved.first_seen_at, last_seen_at = saved.last_seen_at,
    count = saved.count, suppressed_count = saved.suppressed_count,
    source_at_first_seen = saved.source_at_first_seen, source_at_last_seen = saved.source_at_last_seen,
    summary_json = pack('summary', saved.summary), evidence_json = pack('evidence', saved.evidence),
    timeline_snapshot_json = pack('timeline', saved.timeline_snapshot), mitigation_json = pack('mitigation', saved.mitigation),
    lab = saved.lab and 1 or 0, created_at = saved.created_at, updated_at = saved.updated_at,
    resolved_at = saved.resolved_at, resolved_by = saved.resolved_by,
    false_positive_at = saved.false_positive_at, false_positive_by = saved.false_positive_by
}
check(MZBan.Incidents.Hydrate({ row }) == 1 and MZBan.Incidents.Get(saved.incident_id) ~= nil,
    'incidente persistido nao sobreviveu a reload simulado')

check(MZBan.Correlation.HandlePlayerDropped(1, 'Disconnected by user') == 'disconnect',
    'drop normal foi classificado como crash')
check(#MZBan.Incidents.List({ filter = 'crash' }) == 0, 'drop normal criou crash_observed')

MZBan.Correlation.Record(1, 'server_event.ptfx', { effectHash = 55 })
local classOne, crashOne = MZBan.Correlation.HandlePlayerDropped(1, 'Game crashed: GTA5.exe offset 0x123')
check(classOne == 'crash' and crashOne and crashOne.code == 'crash_observed', 'crash nao criou crash_observed')
check(#(crashOne.timelineSnapshot or {}) >= 2
    and crashOne.timelineSnapshot[#crashOne.timelineSnapshot].kind == 'session.disconnect',
    'timeline retroativa/disconnect nao foi preservada antes da limpeza')
check(MZBan.Incidents.ToDto(crashOne, {}).culpability == 'none',
    'confidence de crash foi confundida com culpabilidade')

timer = timer + 3000
MZBan.Correlation.Record(2, 'server_event.explosion', { eventType = 1 })
local _, crashTwo = MZBan.Correlation.HandlePlayerDropped(2, 'RAGE error: exception code 0xc0000005')
check(crashTwo ~= nil, 'segundo crash nao foi observado')
local crashList = MZBan.Incidents.List({ filter = 'crash' })
local cluster
for _, item in ipairs(crashList) do if item.code == 'crash_cluster_suspect' then cluster = MZBan.Incidents.Get(item.id) end end
check(cluster ~= nil, 'dois crashes na janela nao criaram cluster')
check(cluster and cluster.evidence[1].context and #((cluster.evidence[1].context.candidate_actors) or {}) == 0,
    'cluster acusou candidate actor sem evidencia comum')

local lab = MZBan.Lab.Set(90, 1, true, 3600, 'teste adversarial controlado')
local labIncident = MZBan.Incidents.Record({
    source = 1, code = 'event_ptfx_rate_suspect', subject = 'lab-signal',
    evidence = { effectHash = 999 }, mitigation = { attempted = false, applied = false, result = 'lab_observe_only' }
})
check(lab and labIncident and labIncident.lab == true and labIncident.mitigation.result == 'lab_observe_only',
    'LAB nao marcou incidente como observe-only')
check(labWrites >= 1, 'LAB nao foi persistido')

local jsonExport = MZBan.Incidents.Export(crashOne.id, 'json')
check(type(jsonExport) == 'string' and jsonExport:sub(1, 1) == '{', 'export JSON nao e estruturado')
check(not jsonExport:lower():find('api_key', 1, true) and not jsonExport:find('license:secret', 1, true),
    'export JSON vazou secrets ou identifier cru')
local markdown = MZBan.Incidents.Export(crashOne.id, 'markdown')
check(type(markdown) == 'string' and markdown:find('# Evidencia MZ BanGuard', 1, true), 'export Markdown ilegivel')
local dto = MZBan.Incidents.ToDto(crashOne, { details = true })
check(dto.human and dto.human.title == 'Jogador sofreu crash' and dto.technical and dto.technical.code == 'crash_observed',
    'DTO nao separou apresentacao humana de detalhes tecnicos')

MZBan.Correlation.Record(4, 'lifecycle.spawn', { sessionId = 104 })
local _, priorSessionCrash = MZBan.Correlation.HandlePlayerDropped(4, 'Game crashed: first signature')
timer = timer + 6000
players[4].sessionId = 404
MZBan.Correlation.Record(4, 'security_lease.issued', { capability = 'movement.teleport' })
local _, nextSessionCrash = MZBan.Correlation.HandlePlayerDropped(4, 'Game crashed: different signature')
check(priorSessionCrash and nextSessionCrash and priorSessionCrash.id ~= nextSessionCrash.id,
    'crashes cross-session foram agregados indevidamente')
check(nextSessionCrash and nextSessionCrash.linkedIncidentIds[1] == priorSessionCrash.id,
    'crashes cross-session nao foram linked por identidade canonica')

local sessionTimeline = MZBan.Incidents.SessionTimeline(101, 10)
check(sessionTimeline and #sessionTimeline.timeline == 2
    and sessionTimeline.timeline[1].code == 'security_lease.issued'
    and sessionTimeline.timeline[2].type == 'incident',
    'timeline forense de sessao nao preservou a ordem')

local reuse = MZBan.Incidents.Record({ source = 4, code = 'event_ptfx_rate_suspect', subject = 'reuse' })
players[4].citizenid, players[4].accountId, players[4].sessionId = 'CID-NEW', 44, 404
local reuseDto = MZBan.Incidents.ToDto(reuse, {})
check(reuseDto.online == false and reuseDto.source == nil, 'source reutilizado confundiu identidades')

if #failures > 0 then
    io.stderr:write(('wave1_evidence_harness: %d/%d checks failed\n'):format(#failures, checks))
    for _, failure in ipairs(failures) do io.stderr:write(' - ' .. failure .. '\n') end
    os.exit(1)
end
print(('wave1_evidence_harness: ok (%d checks)'):format(checks))
