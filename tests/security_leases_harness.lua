local failures, checks = {}, 0
local function check(condition, label)
    checks = checks + 1
    if not condition then failures[#failures + 1] = label end
end

local timer = 1000
local invokingResource = 'untrusted'
local currentCitizenid = 'MZ000007'
local exported, handlers = {}, {}

Config = {
    Risk = {
        ExportAccess = { RegisterSecurityLease = { trusted_resource = true } }
    },
    SecurityLeases = {
        enabled = true,
        defaultTtlMs = 1000,
        maxTtlMs = 5000,
        maxActivePerPlayer = 4,
        cleanupIntervalMs = 1000,
        audit = false,
        capabilities = {
            ['entity.spawn.ped'] = { ttlMs = 1000, maxTtlMs = 3000, uses = 2, issuers = { trusted_resource = true } },
            ['movement.teleport'] = { ttlMs = 1000, maxTtlMs = 3000, uses = 1, issuers = { trusted_resource = true } }
        }
    }
}

MZBan = {}
exports = setmetatable({}, {
    __call = function(_, name, callback) exported[name] = callback end,
    __index = function(_, resource)
        if resource ~= 'mz_core' then return nil end
        return {
            ResolvePlayerIdentity = function(_, sourceId)
                return { ok = tonumber(sourceId) == 7, citizenid = currentCitizenid }
            end
        }
    end
})
function GetGameTimer() return timer end
function GetPlayerName(sourceId) return tonumber(sourceId) == 7 and 'LeaseTarget' or nil end
function GetInvokingResource() return invokingResource end
function GetResourceState(resource) return resource == 'mz_core' and 'started' or 'missing' end
function AddEventHandler(name, callback)
    handlers[name] = handlers[name] or {}
    handlers[name][#handlers[name] + 1] = callback
end
function CreateThread(_) end
function Wait(_) end

dofile('mz_banguard/server/security_leases.lua')

local id, err = exported.RegisterSecurityLease(7, 'entity.spawn.ped', 1000, { model = 123, bucket = 2 })
check(id == nil and err == 'untrusted_resource', 'untrusted resource issued lease')

invokingResource = 'trusted_resource'
id, err = exported.RegisterSecurityLease(7, '*', 1000, {})
check(id == nil and err == 'invalid_request', 'wildcard capability accepted')

id, err = exported.RegisterSecurityLease(7, 'entity.spawn.ped', 3001, { model = 123, bucket = 2 })
check(id == nil and err == 'invalid_duration', 'capability ttl ceiling ignored')

id, err = exported.RegisterSecurityLease(7, 'entity.spawn.ped', 1000, { model = 123, bucket = 2 })
check(type(id) == 'string' and err == nil, 'valid contextual lease not issued')

local ok, lease = MZBan.SecurityLeases.Consume(7, 'entity.spawn.ped', { model = 999, bucket = 2 })
check(ok == false and lease == nil, 'mismatched model consumed lease')

ok, lease = MZBan.SecurityLeases.Consume(7, 'entity.spawn.ped', { model = 123, bucket = 2 })
check(ok == true and lease.remainingUses == 1, 'first lease use failed')
ok, lease = MZBan.SecurityLeases.Consume(7, 'entity.spawn.ped', { model = 123, bucket = 2 })
check(ok == true and lease.remainingUses == 0, 'second lease use failed')
ok = MZBan.SecurityLeases.Consume(7, 'entity.spawn.ped', { model = 123, bucket = 2 })
check(ok == false, 'consumed lease was replayed')

id = exported.RegisterSecurityLease(7, 'movement.teleport', 1000, { reason = 'core_spawn' })
check(type(id) == 'string', 'teleport lease not issued')
ok = MZBan.SecurityLeases.Check(7, 'movement.teleport', {})
check(ok == true, 'audit reason was incorrectly required as detector context')
timer = timer + 1001
ok = MZBan.SecurityLeases.Consume(7, 'movement.teleport', {})
check(ok == false, 'expired lease remained usable')

timer = timer + 1
id = exported.RegisterSecurityLease(7, 'movement.teleport', 1000, {})
for _, callback in ipairs(handlers.onResourceStop or {}) do callback('trusted_resource') end
ok = MZBan.SecurityLeases.Consume(7, 'movement.teleport', {})
check(ok == false, 'resource stop did not revoke lease')

id = exported.RegisterSecurityLease(7, 'movement.teleport', 1000, {})
currentCitizenid = 'MZ999999'
ok = MZBan.SecurityLeases.Consume(7, 'movement.teleport', {})
check(ok == false, 'lease survived an identity change on the same source')

check(MZBan.SecurityLeases.Status().active == 0, 'lease status retained inactive entries')

if #failures > 0 then
    io.stderr:write(('security_leases_harness: %d/%d checks failed\n'):format(#failures, checks))
    for _, failure in ipairs(failures) do io.stderr:write(' - ' .. failure .. '\n') end
    os.exit(1)
end
print(('security_leases_harness: ok (%d checks)'):format(checks))
