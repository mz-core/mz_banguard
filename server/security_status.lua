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
    local entityConfig = type(Config.EntityGuard) == 'table' and Config.EntityGuard or {}
    local entityMitigationActive = (entityConfig.mode == 'mitigate' or entityConfig.mode == 'enforce')
        and entityConfig.cancelHighConfidence == true and entityConfig.runtimeValidated == true
    local mitigationActive = weapon.mitigationActive == true or entityMitigationActive
    local enforcementActive = weapon.enforcementActive == true
        or (entityMitigationActive and entityConfig.mode == 'enforce')
    local restricted = false
    for _, module in pairs(modules) do
        if module.enabled and module.mode == 'restricted' then restricted = true break end
    end
    local activeMode = enforcementActive and 'enforce'
        or (mitigationActive and 'mitigate' or (restricted and 'restricted' or 'detect-only'))
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
    local lab = MZBan.Lab and type(MZBan.Lab.Status) == 'function'
        and MZBan.Lab.Status() or { active = 0 }
    local enforcement = MZBan.Enforcement and type(MZBan.Enforcement.Status) == 'function'
        and MZBan.Enforcement.Status() or {
            resolvedDefaultMode = 'passive', automaticKickEnabled = false, automaticBanEnabled = false
        }
    local persistence = MZBan.Incidents and type(MZBan.Incidents.PersistenceStatus) == 'function'
        and MZBan.Incidents.PersistenceStatus() or { pendingIncidents = 0, pendingSignals = 0 }
    local policyMitigationActive = enforcement.resolvedDefaultMode ~= 'passive'
    local policyPunishmentActive = enforcement.resolvedDefaultMode == 'kick'
        or enforcement.resolvedDefaultMode == 'ban'
    for _, detector in pairs(type(enforcement.detectors) == 'table' and enforcement.detectors or {}) do
        if detector.resolvedMode ~= 'passive' then policyMitigationActive = true end
        if detector.resolvedMode == 'kick' or detector.resolvedMode == 'ban' then policyPunishmentActive = true end
    end
    mitigationActive = mitigationActive or policyMitigationActive
    enforcementActive = enforcementActive or (policyPunishmentActive
        and (enforcement.automaticKickEnabled == true or enforcement.automaticBanEnabled == true))
    return {
        enabled = true,
        mode = enforcement.resolvedDefaultMode or activeMode,
        cancelHighConfidence = weapon.cancelHighConfidence == true,
        runtimeValidated = weapon.runtimeValidated == true,
        enforcementActive = enforcementActive,
        mitigationActive = mitigationActive,
        autoKick = enforcement.automaticKickEnabled == true,
        autoBan = enforcement.automaticBanEnabled == true,
        alertOnly = enforcement.resolvedDefaultMode == 'passive'
            and enforcement.automaticKickEnabled ~= true and enforcement.automaticBanEnabled ~= true,
        ruleVersion = health.ruleVersion,
        modules = modules,
        infrastructure = {
            leases = leases,
            lifecycle = lifecycle,
            entityClassification = entityClassification,
            eventContracts = contracts,
            correlation = correlation,
            detectorHealth = health,
            aimAnalytics = aim,
            lab = lab,
            incidentPersistence = {
                enabled = Config.IncidentPersistence and Config.IncidentPersistence.enabled ~= false,
                pendingIncidents = persistence.pendingIncidents,
                pendingSignals = persistence.pendingSignals
            }
        },
        enforcement = enforcement
    }
end
