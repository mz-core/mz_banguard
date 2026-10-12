local failures, checks = {}, 0
local function check(condition, label)
    checks = checks + 1
    if not condition then failures[#failures + 1] = label end
end

local timer = 100000
local incidentWrites, signalAttempts = 0, 0
local signalsAvailable = false

Config = {
    Integration = { CoreResource = 'mz_core' },
    SecurityAlerts = {
        notifyStaff = false, aggregateWindowMs = 30000, duplicateCooldownMs = 100,
        incidentTtlMs = 3600000, maxIncidents = 100, maxEvidencePerIncident = 20,
        maxNotesPerIncident = 5, permissions = {},
        riskPoints = { event_ptfx_rate_suspect = 35 }
    },
    WeaponGuard = { riskPoints = {} }, EntityGuard = {}, MovementGuard = {},
    PlayerStateGuard = {}, EventGuard = {}, AimGuard = {},
    IncidentPersistence = {
        enabled = true, updateDebounceMs = 5000, flushIntervalMs = 2000,
        maxWritesPerMinute = 120, maxPendingIncidents = 32, maxPendingSignals = 64,
        signalFlushBatch = 16, retryBaseMs = 100,
        rawSignalWindowMs = 10000, rawSignalBurst = 8,
        rawSignalRepresentativeEvery = 100
    }
}

function GetGameTimer() return timer end
function GetCurrentResourceName() return 'mz_banguard' end
function GetResourceState(name) return name == 'mz_core' and 'started' or 'missing' end
function GetPlayerPing(source) return tonumber(source) == 3 and 50 or 0 end
function GetPlayerName(_) return 'Flood Fixture' end
function GetPlayers() return {} end
function GetPlayerIdentifiers(_) return { 'license:flood', 'fivem:flood' } end
function GetPlayerPed(_) return 1003 end
function DoesEntityExist(entity) return entity == 1003 end
function GetEntityCoords(_) return { x = 0, y = 0, z = 0 } end
function GetPlayerRoutingBucket(_) return 0 end
function AddEventHandler(_, _) end
function CreateThread(_) end
function Wait(_) end

MZBan = {
    IsoUtc = function(value) return 'iso:' .. tostring(value) end,
    JsonEncode = function(_) return '{}' end,
    JsonDecode = function(_, fallback) return fallback or {} end,
    AuditPrint = function() end,
    GetIdentifiers = function() return { byType = { license = 'license:flood', fivem = 'fivem:flood' } } end,
    DB = {
        IsReady = function() return true end,
        SaveIncident = function(_) incidentWrites = incidentWrites + 1 return true end,
        SaveIncidentAction = function(_) return 1 end,
        LoadIncidentActions = function() return {} end,
        SaveSecuritySignal = function(_)
            signalAttempts = signalAttempts + 1
            return signalsAvailable and signalAttempts or false
        end
    }
}
local resources = {
    mz_core = {
        ResolvePlayerIdentity = function()
            return {
                ok = true, active = true, citizenid = 'CID-FLOOD', accountId = 33,
                sessionId = 303, characterId = 333, name = 'Flood Fixture'
            }
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

local incident
for index = 1, 2000 do
    timer = timer + 1
    incident = MZBan.Incidents.Record({
        source = 3, code = 'event_ptfx_rate_suspect', subject = 'ptfx:fixture',
        origin = 'server_event', confidence = 'medium', culpability = 'suspected',
        evidence = { effectHash = 123, amount = index, windowMs = 10000 }
    })
    if index == 500 then
        local checkpoint = MZBan.Incidents.PersistenceStatus()
        check(incident.count == 500, 'flood de 500 sinais nao agregou corretamente')
        check(signalAttempts <= 16 and checkpoint.pendingSignals <= 16,
            'flood de 500 sinais amplificou writes ou fila')
    end
end

local status = MZBan.Incidents.PersistenceStatus()
check(incident and incident.count == 2000, 'flood de 2000 sinais nao agregou em um incidente')
check(signalAttempts <= 32, 'flood gerou tentativas SQL de sinais fora do limite amostrado')
check(status.pendingSignals <= 32, 'fila de sinais cresceu sem limite durante indisponibilidade')
check(incident.rawSignalDroppedCount >= 1900, 'sinais amostrados/descartados nao foram contabilizados')
check(incidentWrites <= 10, 'flood gerou writes excessivos do incidente agregado')

signalsAvailable = true
local _, flushedSignals = MZBan.Incidents.FlushPersistence(true)
status = MZBan.Incidents.PersistenceStatus()
check(flushedSignals > 0 and status.pendingSignals == 0, 'retry/flush nao drenou sinais pendentes')
check(incident.rawSignalPersistenceFailed > 0, 'falhas temporarias de persistencia nao foram registradas')

if #failures > 0 then
    for _, failure in ipairs(failures) do io.stderr:write(' - ' .. failure .. '\n') end
    io.stderr:write(('wave2a_flood_harness: %d/%d checks failed\n'):format(#failures, checks))
    os.exit(1)
end
print(('wave2a_flood_harness: ok (%d checks)'):format(checks))
