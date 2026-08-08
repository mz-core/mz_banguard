local failures, checks = {}, 0
local function check(condition, label)
    checks = checks + 1
    if not condition then failures[#failures + 1] = label end
end

local timer = 1000
local invokingResource = 'untrusted'
local exported = {}

Config = {
    EventContracts = {
        enabled = true,
        maxPayloadKeys = 8,
        maxDepth = 3,
        maxString = 32,
        replayTtlMs = 5000,
        cleanupIntervalMs = 1000,
        trustedResources = { test_resource = true }
    }
}

local health = { seen = 0, discarded = 0 }
MZBan = {
    DetectorHealth = {
        Seen = function() health.seen = health.seen + 1 end,
        Discard = function() health.discarded = health.discarded + 1 end
    },
    Correlation = { Record = function() return 'COR-1' end }
}

exports = setmetatable({}, { __call = function(_, name, callback) exported[name] = callback end })
function GetGameTimer() return timer end
function GetPlayerPing(sourceId) return tonumber(sourceId) == 7 and 50 or 0 end
function GetInvokingResource() return invokingResource end
function CreateThread(_) end
function Wait(_) end

dofile('mz_banguard/server/event_contracts.lua')

local registered = MZBan.EventContracts.Register('economy.credit', {
    sourceOnline = true,
    replayField = 'transactionId',
    schema = {
        type = 'table', allowExtra = false,
        fields = {
            transactionId = { type = 'string', required = true, maxLength = 16, pattern = '^[A-Z0-9%-]+$' },
            amount = { type = 'number', required = true, min = 1, max = 1000 }
        }
    }
})
check(registered == true, 'contract registration failed')

local ok, err = MZBan.EventContracts.Validate('economy.credit', 7, { transactionId = 'TX-1', amount = 100 }, { resource = 'test_resource' })
check(ok == true and err == nil, 'valid payload rejected')
ok, err = MZBan.EventContracts.Validate('economy.credit', 7, { transactionId = 'TX-1', amount = 100 }, { resource = 'test_resource' })
check(ok == false and err == 'replay_detected', 'replay was accepted')
ok = MZBan.EventContracts.Validate('economy.credit', 7, { transactionId = 'TX-2', amount = 1001 }, { resource = 'test_resource' })
check(ok == false, 'amount above contract accepted')
ok = MZBan.EventContracts.Validate('economy.credit', 7, { transactionId = 'TX-3', amount = 10, injected = true }, { resource = 'test_resource' })
check(ok == false, 'unexpected payload field accepted')
ok = MZBan.EventContracts.Validate('economy.credit', 99, { transactionId = 'TX-4', amount = 10 }, { resource = 'test_resource' })
check(ok == false, 'offline source accepted')

ok = MZBan.EventContracts.Validate('security.telemetry', 7, { code = 'movement_noclip_suspect', payload = { distance = 20 } })
check(ok == true, 'built-in telemetry contract rejected valid report')
ok = MZBan.EventContracts.Validate('security.telemetry', 7, { code = 'INVALID CODE', payload = {} })
check(ok == false, 'telemetry code outside pattern accepted')

ok, err = exported.ValidateEventContract(7, 'economy.credit', { transactionId = 'TX-5', amount = 10 })
check(ok == false and err == 'untrusted_resource', 'untrusted resource used validation export')
invokingResource = 'test_resource'
ok = exported.ValidateEventContract(7, 'economy.credit', { transactionId = 'TX-5', amount = 10 })
check(ok == true, 'trusted resource could not validate contract')

local status = MZBan.EventContracts.Status()
check(status.contracts == 2 and status.accepted == 3 and status.replayed == 1, 'contract status counters incorrect')
check(health.seen == 3 and health.discarded >= 5, 'detector health did not receive contract outcomes')

if #failures > 0 then
    io.stderr:write(('event_contracts_harness: %d/%d checks failed\n'):format(#failures, checks))
    for _, failure in ipairs(failures) do io.stderr:write(' - ' .. failure .. '\n') end
    os.exit(1)
end
print(('event_contracts_harness: ok (%d checks)'):format(checks))
