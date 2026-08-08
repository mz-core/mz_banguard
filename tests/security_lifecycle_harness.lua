local checks, failures = 0, {}
local function check(condition, label)
    checks = checks + 1
    if not condition then failures[#failures + 1] = label end
end

local timer = 1000
local invokingResource = 'evil_resource'
local currentCitizenid = 'MZ000007'
local playerContext = { model = 111, bucket = 0, x = 100.0, y = 200.0, z = 30.0 }
local exported, netEvents, handlers = {}, {}, {}

Config = {
    Risk = {
        ExportAccess = {
            BeginSecurityLifecycle = { mz_core = true, mz_creator = true },
            EndSecurityLifecycle = { mz_core = true, mz_creator = true }
        }
    },
    SecurityLifecycle = {
        enabled = true, maxTtlMs = 60000, maxActivePerPlayer = 4,
        cleanupIntervalMs = 5000, postConfirmGraceMs = 5000,
        coordinateTolerance = 15.0, confirmationTolerance = 25.0,
        types = {
            character_spawn = {
                ttlMs = 45000, issuers = { mz_core = true },
                transitions = { movement = true, model = true, camera = true, invincibility = true }
            },
            appearance_edit = {
                ttlMs = 30000, issuers = { mz_creator = true },
                transitions = { model = true, camera = true, invincibility = true }
            },
            respawn = {
                ttlMs = 20000, issuers = { mz_banguard = true },
                transitions = { movement = true, model = true }
            }
        }
    }
}

MZBan = { Correlation = { Record = function() return 'cor-1' end } }
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
function GetPlayerName(sourceId) return tonumber(sourceId) == 7 and 'Lifecycle Target' or nil end
function GetPlayerPing(sourceId) return tonumber(sourceId) == 7 and 42 or 0 end
function GetInvokingResource() return invokingResource end
function GetResourceState(resource) return resource == 'mz_core' and 'started' or 'missing' end
function GetPlayerRoutingBucket(_) return playerContext.bucket end
function GetPlayerPed(sourceId) return tonumber(sourceId) == 7 and 700 or 0 end
function DoesEntityExist(entity) return entity == 700 end
function GetEntityModel(_) return playerContext.model end
function GetEntityCoords(_) return { x = playerContext.x, y = playerContext.y, z = playerContext.z } end
function joaat(value) return value == 'model_a' and 111 or 999 end
function RegisterNetEvent(name, callback) netEvents[name] = callback end
function AddEventHandler(name, callback)
    handlers[name] = handlers[name] or {}
    handlers[name][#handlers[name] + 1] = callback
end
function CreateThread(_) end
function Wait(_) end

dofile('mz_banguard/server/security_lifecycle.lua')

local id, err = exported.BeginSecurityLifecycle(7, 'character_spawn', 45000, {
    model = 111, bucket = 0, x = 100, y = 200, z = 30
})
check(id == nil and err == 'untrusted_resource', 'untrusted resource started lifecycle')

invokingResource = 'mz_core'
id, err = exported.BeginSecurityLifecycle(7, 'character_spawn', 45000, {
    model = 111, bucket = 0, x = 100, y = 200, z = 30, reason = 'core_spawn'
})
check(type(id) == 'string' and err == nil, 'valid spawn lifecycle not started')

local allowed, session = MZBan.SecurityLifecycle.IsAllowed(7, 'movement', playerContext)
check(allowed == true and session.kind == 'character_spawn', 'matching movement was not authorized')
allowed = MZBan.SecurityLifecycle.IsAllowed(7, 'model', { model = 999, bucket = 0 })
check(allowed == false, 'wrong model was authorized')
allowed = MZBan.SecurityLifecycle.IsAllowed(7, 'weapon', playerContext)
check(allowed == false, 'undeclared transition was authorized')

source = 7
netEvents['mz_banguard:server:lifecycleReady'](id)
check(MZBan.SecurityLifecycle.Status().confirmed == 1, 'server-validated confirmation failed')
timer = timer + 5001
allowed = MZBan.SecurityLifecycle.IsAllowed(7, 'movement', playerContext)
check(allowed == false, 'confirmed lifecycle exceeded post-confirm grace')

timer = timer + 1
id = exported.BeginSecurityLifecycle(7, 'character_spawn', 45000, {
    model = 111, bucket = 0, x = 100, y = 200, z = 30
})
currentCitizenid = 'MZ999999'
allowed = MZBan.SecurityLifecycle.IsAllowed(7, 'movement', playerContext)
check(allowed == false and MZBan.SecurityLifecycle.Status().active == 0,
    'lifecycle survived identity change')

invokingResource = 'mz_creator'
id = exported.BeginSecurityLifecycle(7, 'appearance_edit', 30000, { model = 111, bucket = 0 })
check(type(id) == 'string', 'appearance lifecycle not started')
allowed = MZBan.SecurityLifecycle.IsAllowed(7, 'camera', playerContext)
check(allowed == true, 'appearance camera transition not authorized')
local ended = exported.EndSecurityLifecycle(7, id, 'appearance_closed')
check(ended == true and MZBan.SecurityLifecycle.Status().active == 0, 'issuer could not end lifecycle')

for _, callback in ipairs(handlers.respawnPlayerPedEvent or {}) do callback(7) end
allowed, session = MZBan.SecurityLifecycle.IsAllowed(7, 'movement', playerContext)
check(allowed == true and session.kind == 'respawn', 'trusted respawn event did not start lifecycle')
for _, callback in ipairs(handlers.playerDropped or {}) do callback() end
check(MZBan.SecurityLifecycle.Status().active == 0, 'player drop retained lifecycle')

if #failures > 0 then
    io.stderr:write(('security_lifecycle_harness: %d/%d checks failed\n'):format(#failures, checks))
    for _, failure in ipairs(failures) do io.stderr:write(' - ' .. failure .. '\n') end
    os.exit(1)
end
print(('security_lifecycle_harness: ok (%d checks)'):format(checks))
