MZBan = MZBan or {}
MZBan.AlertsAPI = MZBan.AlertsAPI or {}

local function result(ok, data, err)
    return {
        ok = ok == true,
        data = ok == true and data or nil,
        error = ok == true and nil or tostring(err or 'unknown_error')
    }
end

local function validate(actorSource, invokingResource, permissionKey)
    if not MZBan.Incidents.IsTrustedConsumer(invokingResource) then
        return false, 'untrusted_resource'
    end
    actorSource = tonumber(actorSource)
    if not actorSource or actorSource <= 0 or GetPlayerPing(math.floor(actorSource)) <= 0 then
        return false, 'invalid_actor'
    end
    actorSource = math.floor(actorSource)
    if not MZBan.Incidents.HasPermission(actorSource, permissionKey) then
        return false, 'permission_denied'
    end
    return true, actorSource
end

local function guardStatus()
    if MZBan.Security and type(MZBan.Security.Status) == 'function' then
        return MZBan.Security.Status()
    end
    return MZBan.WeaponGuard.Status()
end

function MZBan.AlertsAPI.Summary(actorSource, invokingResource)
    local allowed, actorOrError = validate(actorSource, invokingResource, 'view')
    if not allowed then return result(false, nil, actorOrError) end
    return result(true, { summary = MZBan.Incidents.Summary(), guard = guardStatus() })
end

function MZBan.AlertsAPI.Status(actorSource, invokingResource)
    local allowed, actorOrError = validate(actorSource, invokingResource, 'view')
    if not allowed then return result(false, nil, actorOrError) end
    return result(true, { guard = guardStatus() })
end

function MZBan.AlertsAPI.List(actorSource, filters, invokingResource)
    local allowed, actorOrError = validate(actorSource, invokingResource, 'view')
    if not allowed then return result(false, nil, actorOrError) end
    return result(true, { incidents = MZBan.Incidents.List(filters, { details = false, identifiers = false }) })
end

function MZBan.AlertsAPI.Get(actorSource, id, includeIdentifiers, invokingResource)
    local allowed, actorOrError = validate(actorSource, invokingResource, 'details')
    if not allowed then return result(false, nil, actorOrError) end
    actorSource = actorOrError

    local identifiersAllowed = false
    if includeIdentifiers == true then
        identifiersAllowed = MZBan.Incidents.HasPermission(actorSource, 'identifiers')
        if not identifiersAllowed then
            MZBan.Incidents.AuditAccess(actorSource, id, 'security.incident.identifiers_denied', {
                result = 'denied', reason = 'permission_denied', invokingResource = invokingResource
            })
            return result(false, nil, 'permission_denied')
        end
    end

    local incident = MZBan.Incidents.Get(id)
    if not incident then return result(false, nil, 'incident_not_found') end
    MZBan.Incidents.AuditAccess(actorSource, id, 'security.incident.details_viewed', {
        result = 'viewed', identifiers = identifiersAllowed, invokingResource = invokingResource
    })
    return result(true, { incident = MZBan.Incidents.ToDto(incident, { details = true, identifiers = identifiersAllowed }) })
end

function MZBan.AlertsAPI.SessionTimeline(actorSource, sessionId, limit, invokingResource)
    local allowed, actorOrError = validate(actorSource, invokingResource, 'details')
    if not allowed then return result(false, nil, actorOrError) end
    local timeline, err = MZBan.Incidents.SessionTimeline(sessionId, limit)
    if not timeline then return result(false, nil, err) end
    return result(true, timeline)
end

function MZBan.AlertsAPI.Acknowledge(actorSource, id, invokingResource)
    local allowed, actorOrError = validate(actorSource, invokingResource, 'acknowledge')
    if not allowed then return result(false, nil, actorOrError) end
    local incident, err = MZBan.Incidents.Acknowledge(actorOrError, id)
    if not incident then return result(false, nil, err) end
    return result(true, { incident = MZBan.Incidents.ToDto(incident, { details = true }) })
end

function MZBan.AlertsAPI.AddNote(actorSource, id, note, invokingResource)
    local allowed, actorOrError = validate(actorSource, invokingResource, 'note')
    if not allowed then return result(false, nil, actorOrError) end
    local incident, err = MZBan.Incidents.AddNote(actorOrError, id, note)
    if not incident then return result(false, nil, err) end
    return result(true, { incident = MZBan.Incidents.ToDto(incident, { details = true }) })
end

function MZBan.AlertsAPI.SetStatus(actorSource, id, status, invokingResource)
    local allowed, actorOrError = validate(actorSource, invokingResource, 'clear')
    if not allowed then return result(false, nil, actorOrError) end
    local incident, err = MZBan.Incidents.SetStatus(actorOrError, id, status)
    if not incident then return result(false, nil, err) end
    return result(true, { incident = MZBan.Incidents.ToDto(incident, { details = true }) })
end

function MZBan.AlertsAPI.ExportEvidence(actorSource, id, format, invokingResource)
    local allowed, actorOrError = validate(actorSource, invokingResource, 'details')
    if not allowed then return result(false, nil, actorOrError) end
    local content, mimeType, filename = MZBan.Incidents.Export(id, format)
    if not content then return result(false, nil, mimeType) end
    MZBan.Incidents.AuditAccess(actorOrError, id, 'security.incident.evidence_exported', {
        result = 'exported', format = tostring(format or 'json'), invokingResource = invokingResource
    })
    return result(true, { content = content, mimeType = mimeType, filename = filename })
end

function MZBan.AlertsAPI.SetLabSubject(actorSource, targetSource, enabled, durationSeconds, reason, invokingResource)
    local allowed, actorOrError = validate(actorSource, invokingResource, 'lab')
    if not allowed then return result(false, nil, actorOrError) end
    if not MZBan.Lab or type(MZBan.Lab.Set) ~= 'function' then return result(false, nil, 'lab_unavailable') end
    local cfg = type(Config.LabMode) == 'table' and Config.LabMode or {}
    if cfg.enabled == false then return result(false, nil, 'lab_disabled') end
    durationSeconds = math.floor(tonumber(durationSeconds) or tonumber(cfg.defaultDurationSeconds) or 3600)
    durationSeconds = math.max(60, math.min(tonumber(cfg.maximumDurationSeconds) or 86400, durationSeconds))
    local subject, err = MZBan.Lab.Set(actorOrError, targetSource, enabled == true, durationSeconds, reason)
    if not subject then return result(false, nil, err) end
    return result(true, { subject = subject })
end

function MZBan.AlertsAPI.PrepareAction(actorSource, id, action, invokingResource)
    if not MZBan.Incidents.IsTrustedConsumer(invokingResource) then
        return result(false, nil, 'untrusted_resource')
    end
    actorSource = tonumber(actorSource)
    if not actorSource or actorSource <= 0 or GetPlayerPing(math.floor(actorSource)) <= 0 then
        return result(false, nil, 'invalid_actor')
    end
    actorSource = math.floor(actorSource)
    local targetSource, err, incident = MZBan.Incidents.ResolveActionTarget(actorSource, id, action)
    if not targetSource then return result(false, nil, err) end
    return result(true, {
        incidentId = incident.id,
        action = tostring(action),
        targetSource = targetSource,
        targetName = incident.playerName
    })
end

exports('GetSecurityAlertSummary', function(actorSource)
    return MZBan.AlertsAPI.Summary(actorSource, GetInvokingResource())
end)

exports('ListSecurityIncidents', function(actorSource, filters)
    return MZBan.AlertsAPI.List(actorSource, filters, GetInvokingResource())
end)

exports('GetSecurityIncident', function(actorSource, id, includeIdentifiers)
    return MZBan.AlertsAPI.Get(actorSource, id, includeIdentifiers, GetInvokingResource())
end)

exports('GetSecuritySessionTimeline', function(actorSource, sessionId, limit)
    return MZBan.AlertsAPI.SessionTimeline(actorSource, sessionId, limit, GetInvokingResource())
end)

exports('AcknowledgeSecurityIncident', function(actorSource, id)
    return MZBan.AlertsAPI.Acknowledge(actorSource, id, GetInvokingResource())
end)

exports('AddSecurityIncidentNote', function(actorSource, id, note)
    return MZBan.AlertsAPI.AddNote(actorSource, id, note, GetInvokingResource())
end)

exports('SetSecurityIncidentStatus', function(actorSource, id, status)
    return MZBan.AlertsAPI.SetStatus(actorSource, id, status, GetInvokingResource())
end)

exports('ExportSecurityIncidentEvidence', function(actorSource, id, format)
    return MZBan.AlertsAPI.ExportEvidence(actorSource, id, format, GetInvokingResource())
end)

exports('SetSecurityLabSubject', function(actorSource, targetSource, enabled, durationSeconds, reason)
    return MZBan.AlertsAPI.SetLabSubject(
        actorSource, targetSource, enabled, durationSeconds, reason, GetInvokingResource()
    )
end)

exports('PrepareSecurityIncidentAction', function(actorSource, id, action)
    return MZBan.AlertsAPI.PrepareAction(actorSource, id, action, GetInvokingResource())
end)

exports('GetWeaponGuardStatus', function(actorSource)
    return MZBan.AlertsAPI.Status(actorSource, GetInvokingResource())
end)
