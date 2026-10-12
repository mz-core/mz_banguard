MZBan = MZBan or {}
MZBan.DB = {}

local requiredTables = {
    'mz_bans',
    'mz_ban_identifiers',
    'mz_ban_tokens',
    'mz_ban_seen',
    'mz_ban_audit',
    'mz_ban_flags',
    'mz_security_incidents',
    'mz_security_signals',
    'mz_security_incident_actions',
    'mz_security_lab_subjects'
}

local requiredSchema = {
    mz_bans = {
        columns = {
            'id', 'public_id', 'player_name', 'reason', 'banned_by', 'banned_by_identifier',
            'identifiers', 'tokens', 'expires_at', 'active', 'cloud_ban_id', 'evidence',
            'created_at', 'updated_at', 'revoked_at', 'revoked_by', 'revoke_reason'
        },
        indexes = {
            'PRIMARY', 'uniq_mz_bans_public_id', 'idx_mz_bans_active',
            'idx_mz_bans_expires_at', 'idx_mz_bans_cloud_ban_id'
        }
    },
    mz_ban_identifiers = {
        columns = {
            'id', 'ban_id', 'identifier_type', 'identifier_value', 'active', 'created_at'
        },
        indexes = {
            'PRIMARY', 'uniq_mz_ban_identifier', 'idx_mz_ban_identifier_lookup',
            'idx_mz_ban_identifier_ban'
        }
    },
    mz_ban_tokens = {
        columns = {
            'id', 'ban_id', 'token_value', 'active', 'created_at'
        },
        indexes = {
            'PRIMARY', 'uniq_mz_ban_token', 'idx_mz_ban_token_lookup', 'idx_mz_ban_token_ban'
        }
    },
    mz_ban_seen = {
        columns = {
            'id', 'player_name', 'primary_identifier', 'identifiers', 'tokens',
            'first_seen_at', 'last_seen_at', 'last_source'
        },
        indexes = {
            'PRIMARY', 'uniq_mz_ban_seen_primary', 'idx_mz_ban_seen_primary', 'idx_mz_ban_seen_last_seen'
        }
    },
    mz_ban_audit = {
        columns = {
            'id', 'action', 'actor_source', 'actor_name', 'target_source', 'target_name',
            'ban_public_id', 'meta', 'created_at'
        },
        indexes = {
            'PRIMARY', 'idx_mz_ban_audit_action', 'idx_mz_ban_audit_created',
            'idx_mz_ban_audit_public_id'
        }
    },
    mz_ban_flags = {
        columns = {
            'id', 'player_name', 'primary_identifier', 'reason', 'points', 'score_after',
            'evidence', 'created_by_resource', 'created_at'
        },
        indexes = {
            'PRIMARY', 'idx_mz_ban_flags_primary', 'idx_mz_ban_flags_reason',
            'idx_mz_ban_flags_created', 'idx_mz_ban_flags_score'
        }
    },
    mz_security_incidents = {
        columns = {
            'incident_id', 'code', 'category', 'status', 'severity', 'confidence', 'risk_score',
            'player_name', 'citizenid', 'account_id', 'session_id', 'first_seen_at', 'last_seen_at',
            'count', 'suppressed_count', 'source_at_first_seen', 'source_at_last_seen', 'summary_json',
            'evidence_json', 'timeline_snapshot_json', 'mitigation_json', 'lab', 'created_at', 'updated_at',
            'resolved_at', 'resolved_by', 'false_positive_at', 'false_positive_by'
        },
        indexes = {
            'PRIMARY', 'idx_mz_security_incidents_status_updated', 'idx_mz_security_incidents_citizen',
            'idx_mz_security_incidents_account', 'idx_mz_security_incidents_code_last_seen',
            'idx_mz_security_incidents_severity'
        }
    },
    mz_security_signals = {
        columns = {
            'id', 'signal_id', 'incident_id', 'code', 'origin', 'confidence', 'culpability',
            'citizenid', 'account_id', 'session_id', 'source_id', 'occurred_at', 'evidence_json'
        },
        indexes = {
            'PRIMARY', 'uniq_mz_security_signal_id', 'idx_mz_security_signals_incident',
            'idx_mz_security_signals_session', 'idx_mz_security_signals_citizen',
            'idx_mz_security_signals_account', 'idx_mz_security_signals_code_time'
        }
    },
    mz_security_incident_actions = {
        columns = {
            'id', 'incident_id', 'action', 'actor_citizenid', 'actor_name', 'note', 'meta_json', 'created_at'
        },
        indexes = { 'PRIMARY', 'idx_mz_security_actions_incident', 'idx_mz_security_actions_created' }
    },
    mz_security_lab_subjects = {
        columns = {
            'id', 'citizenid', 'account_id', 'session_id', 'enabled', 'started_at', 'expires_at',
            'reason', 'authorized_by', 'created_at', 'updated_at'
        },
        indexes = {
            'PRIMARY', 'uniq_mz_security_lab_session', 'idx_mz_security_lab_citizen',
            'idx_mz_security_lab_account', 'idx_mz_security_lab_active_expiry'
        }
    }
}

local readinessCache = {
    ready = false,
    error = 'not_checked',
    expiresAt = 0
}

local schema = {
[[
CREATE TABLE IF NOT EXISTS mz_bans (
  id VARCHAR(36) NOT NULL,
  public_id VARCHAR(32) NOT NULL,
  player_name VARCHAR(120) NULL,
  reason TEXT NOT NULL,
  banned_by VARCHAR(120) NULL,
  banned_by_identifier VARCHAR(180) NULL,
  identifiers LONGTEXT NOT NULL,
  tokens LONGTEXT NULL,
  expires_at BIGINT NULL,
  active TINYINT(1) NOT NULL DEFAULT 1,
  cloud_ban_id VARCHAR(64) NULL,
  evidence LONGTEXT NULL,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL,
  revoked_at BIGINT NULL,
  revoked_by VARCHAR(120) NULL,
  revoke_reason TEXT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_mz_bans_public_id (public_id),
  KEY idx_mz_bans_active (active),
  KEY idx_mz_bans_expires_at (expires_at),
  KEY idx_mz_bans_cloud_ban_id (cloud_ban_id)
)
]],
[[
CREATE TABLE IF NOT EXISTS mz_ban_identifiers (
  id BIGINT NOT NULL AUTO_INCREMENT,
  ban_id VARCHAR(36) NOT NULL,
  identifier_type VARCHAR(32) NOT NULL,
  identifier_value VARCHAR(255) NOT NULL,
  active TINYINT(1) NOT NULL DEFAULT 1,
  created_at BIGINT NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_mz_ban_identifier (ban_id, identifier_type, identifier_value),
  KEY idx_mz_ban_identifier_lookup (identifier_type, identifier_value, active),
  KEY idx_mz_ban_identifier_ban (ban_id)
)
]],
[[
CREATE TABLE IF NOT EXISTS mz_ban_tokens (
  id BIGINT NOT NULL AUTO_INCREMENT,
  ban_id VARCHAR(36) NOT NULL,
  token_value VARCHAR(255) NOT NULL,
  active TINYINT(1) NOT NULL DEFAULT 1,
  created_at BIGINT NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_mz_ban_token (ban_id, token_value),
  KEY idx_mz_ban_token_lookup (token_value, active),
  KEY idx_mz_ban_token_ban (ban_id)
)
]],
[[
CREATE TABLE IF NOT EXISTS mz_ban_seen (
  id BIGINT NOT NULL AUTO_INCREMENT,
  player_name VARCHAR(120) NULL,
  primary_identifier VARCHAR(255) NULL,
  identifiers LONGTEXT NOT NULL,
  tokens LONGTEXT NULL,
  first_seen_at BIGINT NOT NULL,
  last_seen_at BIGINT NOT NULL,
  last_source INT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_mz_ban_seen_primary (primary_identifier),
  KEY idx_mz_ban_seen_primary (primary_identifier),
  KEY idx_mz_ban_seen_last_seen (last_seen_at)
)
]],
[[
CREATE TABLE IF NOT EXISTS mz_ban_audit (
  id BIGINT NOT NULL AUTO_INCREMENT,
  action VARCHAR(80) NOT NULL,
  actor_source INT NULL,
  actor_name VARCHAR(120) NULL,
  target_source INT NULL,
  target_name VARCHAR(120) NULL,
  ban_public_id VARCHAR(32) NULL,
  meta LONGTEXT NULL,
  created_at BIGINT NOT NULL,
  PRIMARY KEY (id),
  KEY idx_mz_ban_audit_action (action),
  KEY idx_mz_ban_audit_created (created_at),
  KEY idx_mz_ban_audit_public_id (ban_public_id)
)
]],
[[
CREATE TABLE IF NOT EXISTS mz_ban_flags (
  id BIGINT NOT NULL AUTO_INCREMENT,
  player_name VARCHAR(120) NULL,
  primary_identifier VARCHAR(255) NULL,
  reason VARCHAR(80) NOT NULL,
  points INT NOT NULL DEFAULT 0,
  score_after INT NOT NULL DEFAULT 0,
  evidence LONGTEXT NULL,
  created_by_resource VARCHAR(80) NULL,
  created_at BIGINT NOT NULL,
  PRIMARY KEY (id),
  KEY idx_mz_ban_flags_primary (primary_identifier),
  KEY idx_mz_ban_flags_reason (reason),
  KEY idx_mz_ban_flags_created (created_at),
  KEY idx_mz_ban_flags_score (score_after)
)
]],
[[
CREATE TABLE IF NOT EXISTS mz_security_incidents (
  incident_id VARCHAR(64) NOT NULL,
  code VARCHAR(64) NOT NULL,
  category VARCHAR(32) NOT NULL,
  status VARCHAR(32) NOT NULL,
  severity VARCHAR(16) NOT NULL,
  confidence VARCHAR(16) NOT NULL,
  risk_score INT NOT NULL DEFAULT 0,
  player_name VARCHAR(120) NULL,
  citizenid VARCHAR(64) NULL,
  account_id BIGINT NULL,
  session_id BIGINT NULL,
  first_seen_at BIGINT NOT NULL,
  last_seen_at BIGINT NOT NULL,
  count INT NOT NULL DEFAULT 1,
  suppressed_count INT NOT NULL DEFAULT 0,
  source_at_first_seen INT NULL,
  source_at_last_seen INT NULL,
  summary_json LONGTEXT NULL,
  evidence_json LONGTEXT NULL,
  timeline_snapshot_json LONGTEXT NULL,
  mitigation_json LONGTEXT NULL,
  lab TINYINT(1) NOT NULL DEFAULT 0,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL,
  resolved_at BIGINT NULL,
  resolved_by VARCHAR(128) NULL,
  false_positive_at BIGINT NULL,
  false_positive_by VARCHAR(128) NULL,
  PRIMARY KEY (incident_id),
  KEY idx_mz_security_incidents_status_updated (status, updated_at),
  KEY idx_mz_security_incidents_citizen (citizenid, last_seen_at),
  KEY idx_mz_security_incidents_account (account_id, last_seen_at),
  KEY idx_mz_security_incidents_code_last_seen (code, last_seen_at),
  KEY idx_mz_security_incidents_severity (severity, updated_at)
)
]],
[[
CREATE TABLE IF NOT EXISTS mz_security_signals (
  id BIGINT NOT NULL AUTO_INCREMENT,
  signal_id VARCHAR(64) NOT NULL,
  incident_id VARCHAR(64) NULL,
  code VARCHAR(80) NOT NULL,
  origin VARCHAR(32) NOT NULL,
  confidence VARCHAR(16) NOT NULL,
  culpability VARCHAR(16) NOT NULL,
  citizenid VARCHAR(64) NULL,
  account_id BIGINT NULL,
  session_id BIGINT NULL,
  source_id INT NULL,
  occurred_at BIGINT NOT NULL,
  evidence_json LONGTEXT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_mz_security_signal_id (signal_id),
  KEY idx_mz_security_signals_incident (incident_id, occurred_at),
  KEY idx_mz_security_signals_session (session_id, occurred_at),
  KEY idx_mz_security_signals_citizen (citizenid, occurred_at),
  KEY idx_mz_security_signals_account (account_id, occurred_at),
  KEY idx_mz_security_signals_code_time (code, occurred_at)
)
]],
[[
CREATE TABLE IF NOT EXISTS mz_security_incident_actions (
  id BIGINT NOT NULL AUTO_INCREMENT,
  incident_id VARCHAR(64) NOT NULL,
  action VARCHAR(80) NOT NULL,
  actor_citizenid VARCHAR(64) NULL,
  actor_name VARCHAR(120) NULL,
  note TEXT NULL,
  meta_json LONGTEXT NULL,
  created_at BIGINT NOT NULL,
  PRIMARY KEY (id),
  KEY idx_mz_security_actions_incident (incident_id, created_at),
  KEY idx_mz_security_actions_created (created_at)
)
]],
[[
CREATE TABLE IF NOT EXISTS mz_security_lab_subjects (
  id BIGINT NOT NULL AUTO_INCREMENT,
  citizenid VARCHAR(64) NULL,
  account_id BIGINT NULL,
  session_id BIGINT NULL,
  enabled TINYINT(1) NOT NULL DEFAULT 1,
  started_at BIGINT NOT NULL,
  expires_at BIGINT NULL,
  reason VARCHAR(256) NULL,
  authorized_by VARCHAR(128) NULL,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_mz_security_lab_session (session_id),
  KEY idx_mz_security_lab_citizen (citizenid, enabled),
  KEY idx_mz_security_lab_account (account_id, enabled),
  KEY idx_mz_security_lab_active_expiry (enabled, expires_at)
)
]]
}


local function columnExists(tableName, columnName)
    local row = MySQL.single.await(('SHOW COLUMNS FROM `%s` LIKE ?'):format(tableName), { columnName })
    return row ~= nil
end

local function tableExists(tableName)
    local row = MySQL.single.await('SHOW TABLES LIKE ?', { tableName })
    return row ~= nil
end

local function indexExists(tableName, indexName)
    local row = MySQL.single.await(('SHOW INDEX FROM `%s` WHERE Key_name = ?'):format(tableName), { indexName })
    return row ~= nil
end

local function invalidateReadiness()
    readinessCache.ready = false
    readinessCache.error = 'not_checked'
    readinessCache.expiresAt = 0
end

local function createMissingTables()
    for index, tableName in ipairs(requiredTables) do
        if not tableExists(tableName) then
            MySQL.query.await(schema[index])
            print(('[mz_banguard] created missing table %s'):format(tableName))
        end
    end
    invalidateReadiness()
end

local function runMigrations()
    if not columnExists('mz_bans', 'evidence') then
        MySQL.query.await('ALTER TABLE mz_bans ADD COLUMN evidence LONGTEXT NULL')
    end

    if not indexExists('mz_bans', 'idx_mz_bans_cloud_ban_id') then
        MySQL.query.await('ALTER TABLE mz_bans ADD KEY idx_mz_bans_cloud_ban_id (cloud_ban_id)')
    end

    if not indexExists('mz_ban_seen', 'uniq_mz_ban_seen_primary') then
        -- Pode falhar se já existirem duplicados antigos. Nesse caso, o sistema continua funcionando.
        pcall(function()
            MySQL.query.await('ALTER TABLE mz_ban_seen ADD UNIQUE KEY uniq_mz_ban_seen_primary (primary_identifier)')
        end)
    end
end

local function runRetentionOnce()
    if not Config.Database.Retention or not Config.Database.Retention.Enabled then return end
    local now = MZBan.Now()
    local seenCut = now - ((Config.Database.Retention.SeenDays or 90) * 86400)
    local auditCut = now - ((Config.Database.Retention.AuditDays or 180) * 86400)
    local flagsCut = now - ((Config.Database.Retention.FlagsDays or 180) * 86400)
    local incidentsCut = now - ((Config.Database.Retention.IncidentsDays or 365) * 86400)
    local signalsCut = now - ((Config.Database.Retention.SignalsDays or 90) * 86400)

    MySQL.update.await('DELETE FROM mz_ban_seen WHERE last_seen_at < ?', { seenCut })
    MySQL.update.await('DELETE FROM mz_ban_audit WHERE created_at < ?', { auditCut })
    MySQL.update.await('DELETE FROM mz_ban_flags WHERE created_at < ?', { flagsCut })
    MySQL.update.await('DELETE FROM mz_security_signals WHERE occurred_at < ?', { signalsCut })
    MySQL.update.await([[DELETE FROM mz_security_incident_actions
        WHERE incident_id IN (
          SELECT incident_id FROM mz_security_incidents
          WHERE status IN ('resolved', 'false_positive') AND updated_at < ?
        )]], { incidentsCut })
    MySQL.update.await([[DELETE FROM mz_security_incidents
        WHERE status IN ('resolved', 'false_positive') AND updated_at < ?]], { incidentsCut })
end

function MZBan.DB.Init()
    CreateThread(function()
        Wait(500)

        local databaseConfig = type(Config.Database) == 'table' and Config.Database or {}
        local autoCreateMissing = databaseConfig.AutoCreateMissingTables == true
            or (databaseConfig.AutoCreateMissingTables == nil and databaseConfig.AutoCreate == true)

        if autoCreateMissing then
            local createOk, createError = pcall(createMissingTables)
            if not createOk then
                print('[mz_banguard] missing table creation warning:', createError)
            end
        end

        if databaseConfig.AutoMigrateExistingTables == true then
            local migrationOk, migrationError = pcall(runMigrations)
            if not migrationOk then
                print('[mz_banguard] explicit migration warning:', migrationError)
            end
            invalidateReadiness()
        end

        local checkOk, ready, readinessError = pcall(MZBan.DB.IsReady, true)
        if checkOk and ready == true then
            print('[mz_banguard] database ready')
            runRetentionOnce()
            if MZBan.Incidents and type(MZBan.Incidents.Hydrate) == 'function' then
                local persistence = type(Config.IncidentPersistence) == 'table' and Config.IncidentPersistence or {}
                MZBan.Incidents.Hydrate(MZBan.DB.LoadIncidents(persistence.hydrateLimit))
            end
            if MZBan.Lab and type(MZBan.Lab.Hydrate) == 'function' then
                MZBan.Lab.Hydrate(MZBan.DB.LoadLabSubjects())
            end
        else
            print(('[mz_banguard] database not ready; integration disabled and joins fail closed (%s)'):format(
                tostring(checkOk and readinessError or ready)
            ))
        end
    end)

    if Config.Database.Retention and Config.Database.Retention.Enabled then
        CreateThread(function()
            local hours = tonumber(Config.Database.Retention.RunEveryHours or 12) or 12
            while true do
                Wait(math.max(1, hours) * 60 * 60 * 1000)
                local ok, err = pcall(runRetentionOnce)
                if not ok then print('[mz_banguard] retention error:', err) end
            end
        end)
    end
end

function MZBan.DB.IsReady(force)
    local now = MZBan.Now()
    if force ~= true and readinessCache.expiresAt > now then
        return readinessCache.ready, readinessCache.error
    end

    for _, tableName in ipairs(requiredTables) do
        if not tableExists(tableName) then
            readinessCache.ready = false
            readinessCache.error = 'missing_table:' .. tableName
            readinessCache.expiresAt = now + math.max(1, tonumber(Config.Database.ReadyCacheSeconds) or 30)
            return false, readinessCache.error
        end

        local definition = requiredSchema[tableName]
        for _, columnName in ipairs(definition.columns) do
            if not columnExists(tableName, columnName) then
                readinessCache.ready = false
                readinessCache.error = ('missing_column:%s.%s'):format(tableName, columnName)
                readinessCache.expiresAt = now + math.max(1, tonumber(Config.Database.ReadyCacheSeconds) or 30)
                return false, readinessCache.error
            end
        end

        for _, indexName in ipairs(definition.indexes) do
            if not indexExists(tableName, indexName) then
                readinessCache.ready = false
                readinessCache.error = ('missing_index:%s.%s'):format(tableName, indexName)
                readinessCache.expiresAt = now + math.max(1, tonumber(Config.Database.ReadyCacheSeconds) or 30)
                return false, readinessCache.error
            end
        end
    end

    readinessCache.ready = true
    readinessCache.error = nil
    readinessCache.expiresAt = now + math.max(1, tonumber(Config.Database.ReadyCacheSeconds) or 30)
    return true
end

function MZBan.DB.SaveSeen(src, playerName, identifiers, tokens)
    local primary = MZBan.GetPrimaryIdentifier(identifiers)
    if not primary then return end

    local now = MZBan.Now()
    local tokenPayload = Config.Privacy.StoreTokensLocal and MZBan.JsonEncode(tokens or {}) or MZBan.JsonEncode({})

    MySQL.insert.await(
        [[INSERT INTO mz_ban_seen
          (player_name, primary_identifier, identifiers, tokens, first_seen_at, last_seen_at, last_source)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          ON DUPLICATE KEY UPDATE
            player_name = VALUES(player_name),
            identifiers = VALUES(identifiers),
            tokens = VALUES(tokens),
            last_seen_at = VALUES(last_seen_at),
            last_source = VALUES(last_source)]],
        {
            playerName,
            primary,
            MZBan.JsonEncode(identifiers.byType),
            tokenPayload,
            now,
            now,
            src
        }
    )
end

function MZBan.DB.SaveFlag(data)
    data = data or {}
    MySQL.insert.await(
        [[INSERT INTO mz_ban_flags
          (player_name, primary_identifier, reason, points, score_after, evidence, created_by_resource, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)]],
        {
            data.player_name,
            data.primary_identifier,
            data.reason,
            tonumber(data.points or 0) or 0,
            tonumber(data.score_after or 0) or 0,
            MZBan.JsonEncode(data.evidence or {}),
            data.created_by_resource,
            MZBan.Now()
        }
    )
end

function MZBan.DB.GetRecentFlags(primaryIdentifier, limit)
    return MySQL.query.await(
        [[SELECT * FROM mz_ban_flags
          WHERE primary_identifier = ?
          ORDER BY created_at DESC
          LIMIT ?]],
        { primaryIdentifier, tonumber(limit or 15) or 15 }
    ) or {}
end

function MZBan.DB.SaveIncident(data)
    data = type(data) == 'table' and data or {}
    return MySQL.update.await([[
        INSERT INTO mz_security_incidents (
          incident_id, code, category, status, severity, confidence, risk_score,
          player_name, citizenid, account_id, session_id, first_seen_at, last_seen_at,
          count, suppressed_count, source_at_first_seen, source_at_last_seen,
          summary_json, evidence_json, timeline_snapshot_json, mitigation_json, lab,
          created_at, updated_at, resolved_at, resolved_by, false_positive_at, false_positive_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
          status = VALUES(status), severity = VALUES(severity), confidence = VALUES(confidence),
          risk_score = VALUES(risk_score), player_name = VALUES(player_name), citizenid = VALUES(citizenid),
          account_id = VALUES(account_id), session_id = VALUES(session_id), last_seen_at = VALUES(last_seen_at),
          count = VALUES(count), suppressed_count = VALUES(suppressed_count),
          source_at_last_seen = VALUES(source_at_last_seen), summary_json = VALUES(summary_json),
          evidence_json = VALUES(evidence_json), timeline_snapshot_json = VALUES(timeline_snapshot_json),
          mitigation_json = VALUES(mitigation_json), lab = VALUES(lab), updated_at = VALUES(updated_at),
          resolved_at = VALUES(resolved_at), resolved_by = VALUES(resolved_by),
          false_positive_at = VALUES(false_positive_at), false_positive_by = VALUES(false_positive_by)
    ]], {
        data.incident_id, data.code, data.category, data.status, data.severity, data.confidence,
        tonumber(data.risk_score) or 0, data.player_name, data.citizenid, data.account_id, data.session_id,
        data.first_seen_at, data.last_seen_at, tonumber(data.count) or 1, tonumber(data.suppressed_count) or 0,
        data.source_at_first_seen, data.source_at_last_seen, MZBan.JsonEncode(data.summary or {}),
        MZBan.JsonEncode(data.evidence or {}), MZBan.JsonEncode(data.timeline_snapshot or {}),
        MZBan.JsonEncode(data.mitigation or {}), data.lab == true and 1 or 0,
        data.created_at, data.updated_at, data.resolved_at, data.resolved_by,
        data.false_positive_at, data.false_positive_by
    })
end

function MZBan.DB.SaveSecuritySignal(data)
    data = type(data) == 'table' and data or {}
    return MySQL.insert.await([[
        INSERT IGNORE INTO mz_security_signals
          (signal_id, incident_id, code, origin, confidence, culpability, citizenid,
           account_id, session_id, source_id, occurred_at, evidence_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.signal_id, data.incident_id, data.code, data.origin, data.confidence,
        data.culpability, data.citizenid, data.account_id, data.session_id,
        data.source_id, data.occurred_at or MZBan.Now(), MZBan.JsonEncode(data.evidence or {})
    })
end

function MZBan.DB.LoadSessionSignals(sessionId, limit)
    sessionId = tonumber(sessionId)
    if not sessionId or sessionId <= 0 then return {} end
    limit = math.max(1, math.min(1000, math.floor(tonumber(limit) or 250)))
    return MySQL.query.await([[
        SELECT signal_id, incident_id, code, origin, confidence, culpability,
               source_id, occurred_at, evidence_json
        FROM mz_security_signals
        WHERE session_id = ? ORDER BY occurred_at ASC, id ASC LIMIT ?
    ]], { math.floor(sessionId), limit }) or {}
end

function MZBan.DB.LoadSessionIncidents(sessionId, limit)
    sessionId = tonumber(sessionId)
    if not sessionId or sessionId <= 0 then return {} end
    limit = math.max(1, math.min(500, math.floor(tonumber(limit) or 100)))
    return MySQL.query.await([[
        SELECT incident_id, code, status, severity, confidence, first_seen_at, last_seen_at,
               count, suppressed_count, summary_json
        FROM mz_security_incidents
        WHERE session_id = ? ORDER BY first_seen_at ASC, incident_id ASC LIMIT ?
    ]], { math.floor(sessionId), limit }) or {}
end

function MZBan.DB.LoadIncidents(limit)
    limit = math.max(1, math.min(5000, math.floor(tonumber(limit) or 1000)))
    return MySQL.query.await([[
        SELECT * FROM mz_security_incidents
        ORDER BY updated_at DESC, incident_id DESC
        LIMIT ?
    ]], { limit }) or {}
end

function MZBan.DB.SaveIncidentAction(data)
    data = type(data) == 'table' and data or {}
    return MySQL.insert.await([[
        INSERT INTO mz_security_incident_actions
          (incident_id, action, actor_citizenid, actor_name, note, meta_json, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.incident_id, data.action, data.actor_citizenid, data.actor_name,
        data.note, MZBan.JsonEncode(data.meta or {}), data.created_at or MZBan.Now()
    })
end

function MZBan.DB.LoadIncidentActions(incidentId, limit)
    limit = math.max(1, math.min(200, math.floor(tonumber(limit) or 50)))
    return MySQL.query.await([[
        SELECT action, actor_citizenid, actor_name, note, meta_json, created_at
        FROM mz_security_incident_actions
        WHERE incident_id = ? ORDER BY created_at ASC, id ASC LIMIT ?
    ]], { incidentId, limit }) or {}
end

function MZBan.DB.SaveLabSubject(subject)
    subject = type(subject) == 'table' and subject or {}
    local now = MZBan.Now()
    return MySQL.update.await([[
        INSERT INTO mz_security_lab_subjects
          (citizenid, account_id, session_id, enabled, started_at, expires_at, reason, authorized_by, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
          citizenid = VALUES(citizenid), account_id = VALUES(account_id), enabled = VALUES(enabled),
          started_at = VALUES(started_at), expires_at = VALUES(expires_at), reason = VALUES(reason),
          authorized_by = VALUES(authorized_by), updated_at = VALUES(updated_at)
    ]], {
        subject.citizenid, subject.accountId, subject.sessionId, subject.enabled == true and 1 or 0,
        subject.startedAt or now, subject.expiresAt, subject.reason, subject.authorizedBy, now, subject.updatedAt or now
    })
end

function MZBan.DB.LoadLabSubjects()
    return MySQL.query.await([[
        SELECT * FROM mz_security_lab_subjects
        WHERE enabled = 1 AND (expires_at IS NULL OR expires_at > ?)
        ORDER BY updated_at DESC
    ]], { MZBan.Now() }) or {}
end

function MZBan.DB.Audit(action, data)
    data = data or {}

    local auditId = MySQL.insert.await(
        [[INSERT INTO mz_ban_audit
          (action, actor_source, actor_name, target_source, target_name, ban_public_id, meta, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)]],
        {
            action,
            data.actor_source,
            data.actor_name,
            data.target_source,
            data.target_name,
            data.ban_public_id,
            MZBan.JsonEncode(data.meta or {}),
            MZBan.Now()
        }
    )

    MZBan.AuditPrint(action, data.ban_public_id or '', data.target_name or '')
    return auditId
end
