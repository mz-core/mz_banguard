local checks, failures = 0, {}
local function check(condition, label)
    checks = checks + 1
    if not condition then failures[#failures + 1] = label end
end

local timer = 1000
local events, handlers = {}, {}
local presenceIncidents = {}

Config = {
    DetectorHealth = {
        enabled = true,
        ruleVersion = 'test-1',
        heartbeatIntervalMs = 15000,
        heartbeatMissingMs = 10000,
        cleanupIntervalMs = 10000,
        watchedResources = { mz_banguard = true, mz_inventory = true }
    }
}
MZBan = {
    Incidents = {
        Record = function(input) presenceIncidents[#presenceIncidents + 1] = input return input end,
        NotifyStaff = function() end
    }
}

function GetGameTimer() return timer end
function GetPlayerPing(sourceId) return tonumber(sourceId) == 7 and 42 or 0 end
function GetPlayerName(sourceId) return tonumber(sourceId) == 7 and 'Player Seven' or nil end
function GetPlayers() return { '7' } end
function RegisterNetEvent(name, callback) events[name] = callback end
function AddEventHandler(name, callback) handlers[name] = callback end
function CreateThread(_) end
function Wait(_) end

dofile('mz_banguard/server/detector_health.lua')

source = 7
events['mz_banguard:server:sensorHeartbeat']('test-1', 1)
events['mz_banguard:server:resourceHeartbeat']('mz_inventory', 'inventory-1', 1)
local status = MZBan.DetectorHealth.Status()
check(status.ruleVersion == 'test-1', 'rule version missing')
check(status.sensors.present == 1 and status.sensors.missing == 0, 'valid heartbeat not present')
check(status.sensors.resources.mz_inventory.present == 1,
    'resource-specific presence heartbeat was not tracked')

events['mz_banguard:server:resourceStopObserved']('mz_inventory')
check(#presenceIncidents == 1 and presenceIncidents[1].code == 'client_resource_stop_observed'
    and presenceIncidents[1].culpability == 'none',
    'client resource stop telemetry became authority or was not recorded')

events['mz_banguard:server:sensorHeartbeat']('test-1', 1)
status = MZBan.DetectorHealth.Status()
check(status.modules.client_sensor.discarded == 1, 'heartbeat flood was not rate limited')

timer = 6001
events['mz_banguard:server:sensorHeartbeat']('test-1', 1)
status = MZBan.DetectorHealth.Status()
check(status.modules.client_sensor.discarded == 2, 'replayed sequence was accepted')

events['mz_banguard:server:sensorHeartbeat']('test-1', 2)
status = MZBan.DetectorHealth.Status()
check(status.sensors.present == 1, 'monotonic heartbeat was rejected')

timer = 17002
status = MZBan.DetectorHealth.Status()
check(status.sensors.missing == 1 and #status.sensors.missingSources == 1,
    'missing sensor was not exposed as health state')

if #failures > 0 then
    io.stderr:write(('detector_health_harness: %d/%d checks failed\n'):format(#failures, checks))
    for _, failure in ipairs(failures) do io.stderr:write(' - ' .. failure .. '\n') end
    os.exit(1)
end
print(('detector_health_harness: ok (%d checks)'):format(checks))
