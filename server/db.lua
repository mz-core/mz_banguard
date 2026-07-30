MZBan = MZBan or {}
MZBan.DB = {}

local requiredTables = {
    'mz_bans',
    'mz_ban_identifiers',
    'mz_ban_tokens',
    'mz_ban_seen',
    'mz_ban_audit',
    'mz_ban_flags'
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

    MySQL.update.await('DELETE FROM mz_ban_seen WHERE last_seen_at < ?', { seenCut })
    MySQL.update.await('DELETE FROM mz_ban_audit WHERE created_at < ?', { auditCut })
    MySQL.update.await('DELETE FROM mz_ban_flags WHERE created_at < ?', { flagsCut })
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

function MZBan.DB.Audit(action, data)
    data = data or {}

    MySQL.insert.await(
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
end
