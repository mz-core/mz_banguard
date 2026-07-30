local tables = {}
local columns = {}
local indexes = {}
local createCount = 0
local alterCount = 0
local deleteCount = 0

local expected = {
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
        columns = { 'id', 'ban_id', 'identifier_type', 'identifier_value', 'active', 'created_at' },
        indexes = {
            'PRIMARY', 'uniq_mz_ban_identifier', 'idx_mz_ban_identifier_lookup',
            'idx_mz_ban_identifier_ban'
        }
    },
    mz_ban_tokens = {
        columns = { 'id', 'ban_id', 'token_value', 'active', 'created_at' },
        indexes = { 'PRIMARY', 'uniq_mz_ban_token', 'idx_mz_ban_token_lookup', 'idx_mz_ban_token_ban' }
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

local function expect(condition, message)
    if not condition then error(message, 2) end
end

local function asSet(values)
    local result = {}
    for _, value in ipairs(values or {}) do result[value] = true end
    return result
end

local function installTable(tableName)
    tables[tableName] = true
    columns[tableName] = asSet(expected[tableName].columns)
    indexes[tableName] = asSet(expected[tableName].indexes)
end

Config = {
    Database = {
        AutoCreateMissingTables = true,
        AutoMigrateExistingTables = false,
        ReadyCacheSeconds = 30,
        Retention = { Enabled = false }
    },
    Privacy = { StoreTokensLocal = true }
}

MZBan = {
    Now = function() return 1700000000 end,
    JsonEncode = function() return '{}' end,
    AuditPrint = function() end
}

MySQL = {
    single = {
        await = function(query, parameters)
            local tableName = query:match('SHOW TABLES LIKE')
                and parameters[1]
                or query:match('SHOW COLUMNS FROM `([%w_]+)`')
                or query:match('SHOW INDEX FROM `([%w_]+)`')

            if query:find('SHOW TABLES LIKE', 1, true) then
                return tables[tableName] and { name = tableName } or nil
            end
            if query:find('SHOW COLUMNS FROM', 1, true) then
                return columns[tableName] and columns[tableName][parameters[1]]
                    and { Field = parameters[1] }
                    or nil
            end
            if query:find('SHOW INDEX FROM', 1, true) then
                return indexes[tableName] and indexes[tableName][parameters[1]]
                    and { Key_name = parameters[1] }
                    or nil
            end
            return nil
        end
    },
    query = {
        await = function(query)
            if query:find('CREATE TABLE IF NOT EXISTS', 1, true) then
                local tableName = query:match('CREATE TABLE IF NOT EXISTS%s+([%w_]+)')
                expect(expected[tableName] ~= nil, 'CREATE inesperado: ' .. tostring(tableName))
                createCount = createCount + 1
                installTable(tableName)
                return true
            end
            if query:find('ALTER TABLE', 1, true) then
                alterCount = alterCount + 1
                return true
            end
            return {}
        end
    },
    update = {
        await = function(query)
            if query:find('DELETE FROM', 1, true) then deleteCount = deleteCount + 1 end
            return 0
        end
    },
    insert = { await = function() return 1 end }
}

function CreateThread(callback) callback() end
function Wait() end

dofile('mz_banguard/server/db.lua')

MZBan.DB.Init()
expect(createCount == 6, 'banco vazio nao criou exatamente as seis tabelas')
expect(alterCount == 0, 'bootstrap de banco vazio executou ALTER')
expect(deleteCount == 0, 'bootstrap executou retencao/descarte')

local ready, readyError = MZBan.DB.IsReady(true)
expect(ready == true and readyError == nil, 'schema recem-criado nao ficou pronto')

createCount = 0
columns.mz_bans.evidence = nil
MZBan.DB.Init()
expect(createCount == 0, 'tabela existente incompleta foi recriada')
expect(alterCount == 0, 'tabela existente incompleta recebeu ALTER automatico')
ready, readyError = MZBan.DB.IsReady(true)
expect(ready == false and readyError == 'missing_column:mz_bans.evidence', 'coluna ausente nao foi diagnosticada')

columns.mz_bans.evidence = true
indexes.mz_bans.idx_mz_bans_cloud_ban_id = nil
MZBan.DB.Init()
expect(createCount == 0 and alterCount == 0, 'indice ausente causou mutacao automatica')
ready, readyError = MZBan.DB.IsReady(true)
expect(
    ready == false and readyError == 'missing_index:mz_bans.idx_mz_bans_cloud_ban_id',
    'indice ausente nao foi diagnosticado'
)

print('mz_banguard database bootstrap harness: PASS')
