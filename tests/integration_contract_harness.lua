local exported = {}
local invokingResource = 'mz_admin'
local permissions = {
    ['staff.players.ban'] = true,
    ['staff.bans.view'] = true,
    ['staff.bans.revoke'] = true
}
local hierarchyAllowed = true
local hierarchyReason = 'target_not_staff'
local createdBan
local revokedPublicId
local droppedPlayer

local function expect(condition, message)
    if not condition then error(message, 2) end
end

Config = {
    Privacy = { StoreIpLocal = false },
    Integration = {
        CoreResource = 'mz_core',
        TrustedResources = { mz_admin = true },
        Permissions = {
            View = 'staff.bans.view',
            Create = 'staff.players.ban',
            Revoke = 'staff.bans.revoke'
        },
        Limits = {
            ReasonMin = 3,
            ReasonMax = 256,
            MaxDurationDays = 3650,
            PageSize = 25,
            MaxPageSize = 50
        }
    }
}

MZBan = {
    DB = {
        IsReady = function() return true end,
        Audit = function() return true end,
        GetRecentFlags = function() return {} end
    },
    Bans = {
        CheckLocal = function() return nil end,
        Create = function(data)
            createdBan = {
                public_id = 'MBG-ABC234',
                player_name = data.player_name,
                reason = data.reason,
                evidence = data.evidence,
                banned_by = data.banned_by,
                expires_at = data.expires_at,
                active = 1,
                created_at = 1700000000,
                updated_at = 1700000000
            }
            return createdBan
        end,
        Revoke = function(publicId)
            revokedPublicId = publicId
            return true, {
                public_id = publicId,
                player_name = 'Target',
                active = 0
            }
        end,
        GetByPublicId = function(publicId)
            return {
                public_id = publicId,
                player_name = 'Target',
                reason = 'Teste',
                active = revokedPublicId == publicId and 0 or 1,
                created_at = 1700000000
            }
        end,
        ListPublic = function(filters)
            return {
                items = {
                    {
                        publicId = 'MBG-ABC234',
                        playerName = 'Target',
                        reason = 'Teste',
                        active = filters.active ~= false
                    }
                },
                total = 1,
                page = filters.page or 1,
                pageSize = 25
            }
        end,
        ToPublicDto = function(ban)
            local evidence = type(ban.evidence) == 'table' and ban.evidence or {}
            return {
                publicId = ban.public_id,
                playerName = ban.player_name,
                citizenId = evidence.target_citizenid,
                reason = ban.reason,
                active = tonumber(ban.active) == 1
            }
        end,
        FormatKickMessage = function(ban)
            return 'Ban ' .. tostring(ban.public_id)
        end
    },
    Flags = {
        GetScore = function() return 0 end
    },
    Webhook = {
        Send = function() end,
        Field = function(name, value) return { name = name, value = value } end
    },
    Cloud = {
        ReportBan = function() end,
        ReportUnban = function() end
    },
    Truncate = function(value, maxLength)
        value = tostring(value or '')
        return #value > maxLength and value:sub(1, maxLength) or value
    end,
    ParseDuration = function(value)
        local amount, unit = tostring(value):match('^(%d+)([mhd])$')
        amount = tonumber(amount)
        if not amount then return false, 'invalid' end
        local seconds = unit == 'm' and amount * 60 or (unit == 'h' and amount * 3600 or amount * 86400)
        return 1700000000 + seconds, value
    end,
    Now = function() return 1700000000 end,
    SafePlayerName = function(sourceId) return sourceId == 1 and 'Staff' or 'Target' end,
    GetIdentifiers = function()
        return { byType = { license = 'license:test' }, raw = { 'license:test' } }
    end,
    HasRequiredIdentifiers = function() return true end,
    GetPlayerTokensSafe = function() return { 'token:test' } end,
    GetPrimaryIdentifier = function() return 'license:test' end,
    GetActorIdentifier = function() return 'license:staff' end,
    JsonEncode = function(value) return value end
}

local core = {
    HasGlobalPermission = function(_, sourceId, permission)
        return sourceId == 1 and permissions[permission] == true
    end,
    CanStaffActOnPlayer = function(_, actorSource, targetSource)
        if actorSource ~= 1 or targetSource ~= 2 then return false, 'invalid_test_target' end
        return hierarchyAllowed, hierarchyReason, { relationship = hierarchyReason }
    end,
    ResolvePlayerIdentity = function(_, sourceId)
        if sourceId == 1 then return { ok = true, citizenid = 'STAFF001' } end
        if sourceId == 2 then return { ok = true, citizenid = 'PLAYER002' } end
        return { ok = false, error = 'not_found' }
    end
}

exports = setmetatable({ mz_core = core }, {
    __call = function(_, name, callback)
        exported[name] = callback
    end
})

function GetInvokingResource() return invokingResource end
function GetResourceState(resourceName) return resourceName == 'mz_core' and 'started' or 'missing' end
function GetPlayerName(sourceId)
    if sourceId == 1 then return 'Staff' end
    if sourceId == 2 then return 'Target' end
    return nil
end
function GetPlayerPing(sourceId) return GetPlayerName(sourceId) and 50 or 0 end
function CreateThread(callback) callback() end
function DropPlayer(sourceId, reason) droppedPlayer = { source = sourceId, reason = reason } end

dofile('mz_banguard/server/api.lua')

expect(type(exported.IsReady) == 'function', 'export IsReady ausente')
expect(type(exported.CreateOnlineBan) == 'function', 'export CreateOnlineBan ausente')
expect(type(exported.RevokeBan) == 'function', 'export RevokeBan ausente')
expect(type(exported.GetBan) == 'function', 'export GetBan ausente')
expect(type(exported.ListBans) == 'function', 'export ListBans ausente')

local ready = { exported.IsReady() }
expect(ready[1] == true, 'API pronta foi recusada')

invokingResource = 'resource_malicioso'
local untrusted = exported.CreateOnlineBan(1, 2, 'perm', 'motivo seguro')
expect(untrusted.ok == false and untrusted.error == 'untrusted_resource', 'caller nao confiavel foi aceito')
expect(createdBan == nil and droppedPlayer == nil, 'caller nao confiavel causou mutacao')

invokingResource = 'mz_admin'
permissions['staff.players.ban'] = false
local denied = exported.CreateOnlineBan(1, 2, 'perm', 'motivo seguro')
expect(denied.ok == false and denied.error == 'permission_denied', 'ban sem permissao foi aceito')
expect(createdBan == nil and droppedPlayer == nil, 'ban sem permissao causou mutacao')

permissions['staff.players.ban'] = true
hierarchyAllowed = false
hierarchyReason = 'target_higher_or_equal'
denied = exported.CreateOnlineBan(1, 2, 'perm', 'motivo seguro')
expect(denied.ok == false and denied.error == 'target_higher_or_equal', 'hierarquia igual/superior foi ignorada')
expect(createdBan == nil and droppedPlayer == nil, 'negacao hierarquica causou mutacao')

hierarchyAllowed = true
hierarchyReason = 'target_not_staff'
local invalidDuration = exported.CreateOnlineBan(1, 2, 'ontem', 'motivo seguro')
expect(invalidDuration.ok == false and invalidDuration.error == 'invalid_duration', 'duracao invalida foi aceita')

local created = exported.CreateOnlineBan(1, 2, '7d', 'motivo seguro')
expect(created.ok == true and created.data.ban.publicId == 'MBG-ABC234', 'ban autorizado nao retornou DTO')
expect(created.data.ban.citizenId == 'PLAYER002', 'ban nao retornou CitizenID resolvido no servidor')
expect(createdBan.evidence.target_citizenid == 'PLAYER002', 'ban nao persistiu CitizenID contextual')
expect(droppedPlayer and droppedPlayer.source == 2, 'alvo nao foi removido apos persistencia')
expect(droppedPlayer.reason:find('MBG-ABC234', 1, true) ~= nil, 'mensagem perdeu Public ID')

permissions['staff.bans.view'] = false
local hidden = exported.ListBans(1, { active = true })
expect(hidden.ok == false and hidden.error == 'permission_denied', 'listagem sem permissao foi aceita')

permissions['staff.bans.view'] = true
local listed = exported.ListBans(1, {
    active = true,
    page = 1,
    pageSize = 999,
    identifiers = true
})
expect(listed.ok == true and listed.data.total == 1, 'listagem autorizada falhou')
expect(listed.data.items[1].identifiers == nil, 'DTO publico expos identifiers')
expect(listed.data.items[1].tokens == nil, 'DTO publico expos tokens')

permissions['staff.bans.revoke'] = false
local revokeDenied = exported.RevokeBan(1, 'MBG-ABC234', 'revisao')
expect(revokeDenied.ok == false and revokeDenied.error == 'permission_denied', 'revogacao sem permissao foi aceita')

permissions['staff.bans.revoke'] = true
local revoked = exported.RevokeBan(1, 'MBG-ABC234', 'revisao')
expect(revoked.ok == true and revokedPublicId == 'MBG-ABC234', 'revogacao autorizada falhou')

print('mz_banguard integration contract harness: PASS')
