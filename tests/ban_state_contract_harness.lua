local currentBan
local transactionCount = 0

local function expect(condition, message)
    if not condition then error(message, 2) end
end

MZBan = {
    Now = function() return 1700000000 end,
    JsonEncode = function() return '{}' end,
    JsonDecode = function(value)
        return type(value) == 'table' and value or {}
    end,
    AuditPrint = function() end,
    Truncate = function(value) return tostring(value or '') end
}

Config = {
    Integration = {
        Limits = {
            PageSize = 25,
            MaxPageSize = 50
        }
    },
    Privacy = {
        StoreTokensLocal = true
    },
    Local = {
        CleanExpiredOnCheck = true,
        Enabled = true,
        UsePlayerTokens = false
    }
}

MySQL = {
    single = {
        await = function(query)
            if query:find('FROM mz_bans WHERE public_id', 1, true) then return currentBan end
            if query:find('COUNT(1)', 1, true) then return { total = 0 } end
            return nil
        end
    },
    query = {
        await = function() return {} end
    },
    transaction = {
        await = function()
            transactionCount = transactionCount + 1
            return true
        end
    }
}

dofile('mz_banguard/server/bans.lua')

for _, activeValue in ipairs({ 1, '1', true }) do
    currentBan = {
        id = 'internal-id',
        public_id = 'MBG-ABC234',
        player_name = 'Target',
        reason = 'Teste',
        active = activeValue,
        created_at = 1699990000,
        evidence = { target_citizenid = 'PLAYER002' }
    }
    local before = transactionCount
    local ok, ban = MZBan.Bans.Revoke('MBG-ABC234', 'Staff', 'revisao')
    expect(ok == true and ban == currentBan, 'active=' .. tostring(activeValue) .. ' nao foi reconhecido')
    expect(transactionCount == before + 1, 'revogacao ativa nao executou transacao')
    expect(MZBan.Bans.ToPublicDto(currentBan).active == true, 'DTO alterou active=' .. tostring(activeValue))
    expect(MZBan.Bans.ToPublicDto(currentBan).citizenId == 'PLAYER002', 'DTO perdeu CitizenID contextual')
end

currentBan = {
    id = 'internal-id',
    public_id = 'MBG-ABC234',
    active = false,
    revoked_at = 1699995000,
    revoke_reason = 'revisao'
}
local before = transactionCount
local ok, err = MZBan.Bans.Revoke('MBG-ABC234', 'Staff', 'segunda tentativa')
expect(ok == false and err == 'already_revoked', 'ban revogado nao foi distinguido')
expect(transactionCount == before, 'ban revogado executou nova transacao')
expect(MZBan.Bans.ToPublicDto(currentBan).active == false, 'DTO marcou boolean false como ativo')

currentBan = {
    id = 'internal-id',
    public_id = 'MBG-ABC234',
    active = 0,
    expires_at = 1699999000,
    revoke_reason = 'expired'
}
ok, err = MZBan.Bans.Revoke('MBG-ABC234', 'Staff', 'segunda tentativa')
expect(ok == false and err == 'expired', 'ban expirado nao foi distinguido')

currentBan = nil
ok, err = MZBan.Bans.Revoke('MBG-ZZZ999', 'Staff', 'teste')
expect(ok == false and err == 'not_found', 'Public ID inexistente nao foi distinguido')

print('mz_banguard ban state contract harness: PASS')
