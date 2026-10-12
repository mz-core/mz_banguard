local checks, failures = 0, {}
local function check(condition, label)
    checks = checks + 1
    if not condition then failures[#failures + 1] = label end
end

local function read(path)
    local file = assert(io.open(path, 'rb'))
    local contents = file:read('*a')
    file:close()
    return contents
end

local config = read('mz_banguard/config.lua')
local eventGuard = read('mz_banguard/server/event_guard.lua')
local entityGuard = read('mz_banguard/server/entity_guard.lua')
local inventoryEvents = read('mz_inventory/server/events.lua')
local inventoryClient = read('mz_inventory/client/main.lua')
local banguardClient = read('mz_banguard/client/security_telemetry.lua')
local incidents = read('mz_banguard/server/incidents.lua')

check(config:find("mode = 'observe'", 1, true) ~= nil,
    'default policy is not observe')
check(config:find('sv_filterRequestControl', 1, true) == nil
    and config:find('sv_entityLockdown', 1, true) == nil,
    'resource config silently changed global Cfx hardening')
check(eventGuard:find("AddEventHandler('ptFxEvent'", 1, true) ~= nil
    and eventGuard:find('CancelEvent', 1, true) == nil,
    'ptFx cancellation was assumed without artifact validation')
check(entityGuard:find("phase ~= 'creating'", 1, true) ~= nil
    and entityGuard:find('runtimeValidated ~= true', 1, true) ~= nil,
    'entityCreating cancel is not restricted to validated mitigation')

local canaryName = 'mz_inventory:server:MZ_SECURITY_CANARY'
check(inventoryEvents:find('MZ_SECURITY_CANARY', 1, true) ~= nil
    and inventoryEvents:find(canaryName, 1, true) ~= nil,
    'inventory owner does not declare the marked security canary')
check(incidents:find("exports('RecordSecurityCanary'", 1, true) ~= nil
    and incidents:find('expectedDomain ~= domain', 1, true) ~= nil,
    'BanGuard canary ingestion is not owner-scoped')

local function hasLegitimateCanaryCaller(source)
    return source:find('TriggerServerEvent', 1, true) ~= nil
        and source:find(canaryName, 1, true) ~= nil
end

check(not hasLegitimateCanaryCaller(inventoryClient)
    and not hasLegitimateCanaryCaller(banguardClient),
    'a legitimate client calls the security canary')
check(hasLegitimateCanaryCaller("TriggerServerEvent('" .. canaryName .. "')"),
    'anti-refactor canary check does not reject a fictional legitimate caller')
local canaryHandler = inventoryEvents:match('%-%- MZ_SECURITY_CANARY.*') or ''
check(canaryHandler:find('AddPlayerItem', 1, true) == nil
    and canaryHandler:find('RemovePlayerItem', 1, true) == nil
    and canaryHandler:find('SetPlayerSlot', 1, true) == nil,
    'canary handler contains a domain mutation')

if #failures > 0 then
    io.stderr:write(('incident_v3_contract_harness: %d/%d checks failed\n'):format(#failures, checks))
    for _, failure in ipairs(failures) do io.stderr:write(' - ' .. failure .. '\n') end
    os.exit(1)
end

print(('incident_v3_contract_harness: ok (%d checks)'):format(checks))
