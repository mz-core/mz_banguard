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

dofile('mz_banguard/config.lua')

check(Config.Version == '1.6.0', 'config version is not 1.6.0')
check(Config.Risk.AutoKick == false and Config.Risk.AutoBan == false, 'automatic punishment is enabled')
for _, section in ipairs({ 'WeaponGuard', 'EntityGuard', 'MovementGuard', 'PlayerStateGuard', 'EventGuard', 'AimGuard' }) do
    check(Config[section].enabled == true and Config[section].mode == 'observe', section .. ' is not observing')
end

local leaseAccess = Config.Risk.ExportAccess.RegisterSecurityLease
local accessCount = 0
for _ in pairs(leaseAccess) do accessCount = accessCount + 1 end
check(accessCount == 2 and leaseAccess.mz_admin == true and leaseAccess.mz_core == true,
    'lease export has an unreviewed issuer')

local capabilities = Config.SecurityLeases.capabilities
check(capabilities['movement.teleport'].issuers.mz_admin == true, 'admin teleport issuer missing')
check(capabilities['movement.teleport'].issuers.mz_core == true, 'core teleport issuer missing')
check(capabilities['entity.spawn.vehicle'].issuers.mz_admin == true, 'admin vehicle issuer missing')
check(capabilities['player.model.change'].issuers.mz_core == true, 'core model issuer missing')
check(next(capabilities['entity.spawn.ped'].issuers) == nil, 'ped spawn has an unintegrated issuer')
check(next(capabilities['entity.spawn.object'].issuers) == nil, 'object spawn has an unintegrated issuer')

local lifecycleAccess = Config.Risk.ExportAccess.BeginSecurityLifecycle
for _, resource in ipairs({ 'mz_core', 'mz_creator', 'mz_clothing', 'mz_tatto', 'mz_houses' }) do
    check(lifecycleAccess[resource] == true, resource .. ' lifecycle issuer missing')
end
check(lifecycleAccess.mz_interiors == true, 'interiors calibration lifecycle issuer missing')
for _, resource in ipairs({ 'mz_creator', 'mz_clothing', 'mz_tatto', 'mz_houses' }) do
    check(Config.EventContracts.trustedResources[resource] == true, resource .. ' event-contract trust missing')
end
check(Config.EventContracts.trustedResources.mz_interiors == true,
    'interiors calibration event-contract trust missing')
check(Config.SecurityLifecycle.types.character_spawn.issuers.mz_core == true, 'core spawn lifecycle missing')
check(Config.SecurityLifecycle.types.character_creation.issuers.mz_creator == true, 'creator lifecycle missing')
check(Config.SecurityLifecycle.types.interior_calibration.issuers.mz_interiors == true,
    'interiors calibration lifecycle missing')
check(Config.EntityClassification.classes.ambient.alertOnRate == false, 'ambient population still alerts on rate')
check(Config.EntityClassification.classes.scripted.alertOnRate == true, 'scripted population rate observation disabled')

local adminMain = read('mz_admin/server/main.lua')
local adminSecurity = read('mz_admin/server/security.lua')
local coreMain = read('mz_core/server/main.lua')
local coreSpawn = read('mz_core/client/spawn.lua')
local creatorEvents = read('mz_creator/server/events.lua')
local clothingServer = read('mz_clothing/server/main.lua')
local tattooCallbacks = read('mz_tatto/server/callbacks.lua')
local housesMain = read('mz_houses/server/main.lua')
local interiorsServer = read('mz_interiors/server/main.lua')
check((adminMain .. adminSecurity):find("'movement.teleport'", 1, true) ~= nil, 'goto/bring lease integration missing')
check(adminSecurity:find("'entity.spawn.vehicle'", 1, true) ~= nil, 'staff vehicle lease integration missing')
check(coreMain:find("'player.model.change'", 1, true) ~= nil, 'core model lease integration missing')
check(coreMain:find("'movement.teleport'", 1, true) ~= nil, 'core spawn teleport lease integration missing')
check(coreMain:find("'character_spawn'", 1, true) ~= nil, 'core spawn lifecycle integration missing')
check(coreSpawn:find('spawnRequestPending', 1, true) ~= nil,
    'core client permite multiplas solicitacoes concorrentes de lifecycle de spawn')
check(creatorEvents:find("'character_creation'", 1, true) ~= nil, 'creator lifecycle integration missing')
check(clothingServer:find("'cosmetic_session'", 1, true) ~= nil, 'clothing lifecycle integration missing')
check(tattooCallbacks:find("'cosmetic_session'", 1, true) ~= nil, 'tattoo lifecycle integration missing')
check(housesMain:find("'interior_transition'", 1, true) ~= nil, 'house lifecycle integration missing')
check(creatorEvents:find("'lifecycle.creator.open'", 1, true) ~= nil, 'creator contract integration missing')
check(clothingServer:find("'lifecycle.clothing.open'", 1, true) ~= nil, 'clothing contract integration missing')
check(tattooCallbacks:find("'lifecycle.tattoo.open'", 1, true) ~= nil, 'tattoo contract integration missing')
check(housesMain:find("'lifecycle.house.enter'", 1, true) ~= nil, 'house contract integration missing')
check(interiorsServer:find("'interior_calibration'", 1, true) ~= nil,
    'interiors calibration lifecycle integration missing')
check(interiorsServer:find("'lifecycle.interiors.calibration.exit'", 1, true) ~= nil,
    'interiors calibration exit contract missing')
check(interiorsServer:find("'lifecycle.interiors.calibration.report'", 1, true) ~= nil,
    'interiors calibration report contract missing')
check(Config.EventContracts.contracts['lifecycle.interiors.calibration.report'] ~= nil,
    'BanGuard calibration report schema missing')

local entityGuard = read('mz_banguard/server/entity_guard.lua')
check(entityGuard:find('CancelEvent', 1, true) ~= nil
    and entityGuard:find('enforcement = enforcement', 1, true) ~= nil
    and entityGuard:find('guard.runtimeValidated ~= true', 1, true) ~= nil,
    'entityCreating mitigation is not delegated to unified enforcement with runtime validation')

local guardFiles = {
    'mz_banguard/server/telemetry_guard.lua',
    'mz_banguard/server/event_guard.lua',
    'mz_banguard/server/aim_guard.lua'
}
for _, path in ipairs(guardFiles) do
    local source = read(path)
    local mutates = source:find('CancelEvent', 1, true) or source:find('DropPlayer', 1, true)
        or source:find('DeleteEntity', 1, true) or source:find('DeleteVehicle', 1, true)
        or source:find('DeletePed', 1, true) or source:find('DeleteObject', 1, true)
    check(mutates == nil, path .. ' contains a punitive/preventive action')
end

if #failures > 0 then
    io.stderr:write(('security_lease_integration_contract_harness: %d/%d checks failed\n'):format(#failures, checks))
    for _, failure in ipairs(failures) do io.stderr:write(' - ' .. failure .. '\n') end
    os.exit(1)
end
print(('security_lease_integration_contract_harness: ok (%d checks)'):format(checks))
