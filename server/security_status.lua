MZBan = MZBan or {}
MZBan.Security = MZBan.Security or {}

local MODULES = {
    weapon = 'WeaponGuard',
    entity = 'EntityGuard',
    movement = 'MovementGuard',
    playerState = 'PlayerStateGuard',
    event = 'EventGuard',
    aim = 'AimGuard'
}

function MZBan.Security.Status()
    local modules = {}
    for name, configName in pairs(MODULES) do
        local section = type(Config[configName]) == 'table' and Config[configName] or {}
        modules[name] = {
            enabled = section.enabled == true,
            mode = tostring(section.mode or 'observe'),
            runtimeValidated = section.runtimeValidated == true
        }
    end

    local weapon = MZBan.WeaponGuard and MZBan.WeaponGuard.Status and MZBan.WeaponGuard.Status() or {}
    local risk = type(Config.Risk) == 'table' and Config.Risk or {}
    local enforcementActive = weapon.enforcementActive == true
    local health = MZBan.DetectorHealth and type(MZBan.DetectorHealth.Status) == 'function'
        and MZBan.DetectorHealth.Status() or { enabled = false }
    local leases = MZBan.SecurityLeases and type(MZBan.SecurityLeases.Status) == 'function'
        and MZBan.SecurityLeases.Status() or { enabled = false }
    local lifecycle = MZBan.SecurityLifecycle and type(MZBan.SecurityLifecycle.Status) == 'function'
        and MZBan.SecurityLifecycle.Status() or { enabled = false }
    local entityClassification = MZBan.EntityClassification and type(MZBan.EntityClassification.Status) == 'function'
        and MZBan.EntityClassification.Status() or { enabled = false }
    local contracts = MZBan.EventContracts and type(MZBan.EventContracts.Status) == 'function'
        and MZBan.EventContracts.Status() or { enabled = false }
    local correlation = MZBan.Correlation and type(MZBan.Correlation.Status) == 'function'
        and MZBan.Correlation.Status() or { enabled = false }
    local aim = MZBan.AimGuard and type(MZBan.AimGuard.Status) == 'function'
        and MZBan.AimGuard.Status() or {}
    return {
        enabled = true,
        mode = enforcementActive and 'enforce' or 'observe',
        cancelHighConfidence = weapon.cancelHighConfidence == true,
        runtimeValidated = weapon.runtimeValidated == true,
        enforcementActive = enforcementActive,
        autoKick = risk.AutoKick == true,
        autoBan = risk.AutoBan == true,
        alertOnly = not enforcementActive and risk.AutoKick ~= true and risk.AutoBan ~= true,
        ruleVersion = health.ruleVersion,
        modules = modules,
        infrastructure = {
            leases = leases,
            lifecycle = lifecycle,
            entityClassification = entityClassification,
            eventContracts = contracts,
            correlation = correlation,
            detectorHealth = health,
            aimAnalytics = aim
        }
    }
end
