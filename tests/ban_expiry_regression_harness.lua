local failures, checks = {}, 0
local function check(condition, label)
    checks = checks + 1
    if not condition then failures[#failures + 1] = label end
end

Config = {
    Local = { Enabled = true, UsePlayerTokens = true, TokenMatchAutoBan = true, CleanExpiredOnCheck = false },
    Privacy = { StoreTokensLocal = true },
    Integration = { Limits = {} }
}

MZBan = {
    Now = function() return 1000 end,
    JsonDecode = function(_, fallback) return fallback end,
    Truncate = function(value) return tostring(value) end
}

local bansByIdentifier, bansByToken = {}, {}
MySQL = {
    single = {
        await = function(query, parameters)
            if query:find('mz_ban_identifiers', 1, true) then return bansByIdentifier[parameters[2]] end
            if query:find('mz_ban_tokens', 1, true) then return bansByToken[parameters[1]] end
            return nil
        end
    }
}

dofile('../server/bans.lua')

local function ban(id, expiresAt)
    return { id = id, public_id = id, active = 1, created_at = 900, expires_at = expiresAt }
end

local function reset()
    bansByIdentifier, bansByToken = {}, {}
end

reset()
bansByIdentifier['license:expired'] = ban('EXPIRED-A', 999)
bansByToken['token-active'] = ban('ACTIVE-B', 2000)
local found = MZBan.Bans.CheckLocal({ byType = { license = 'license:expired' } }, { 'token-active' })
check(found and found.public_id == 'ACTIVE-B' and found.match_type == 'token',
    'identifier expirado interrompeu a busca antes do token ativo')

reset()
bansByIdentifier['license:expired'] = ban('EXPIRED-A', 999)
bansByToken['token-expired'] = ban('EXPIRED-B', 999)
check(MZBan.Bans.CheckLocal({ byType = { license = 'license:expired' } }, { 'token-expired' }) == nil,
    'todos os bans expirados deveriam permitir')

reset()
bansByIdentifier['license:active'] = ban('ACTIVE-A', 2000)
found = MZBan.Bans.CheckLocal({ byType = { license = 'license:active' } }, { 'unused' })
check(found and found.public_id == 'ACTIVE-A', 'primeiro ban ativo nao bloqueou')

reset()
bansByIdentifier['license:expired'] = ban('EXPIRED-A', 999)
bansByToken['token-active'] = ban('ACTIVE-B', 2000)
found = MZBan.Bans.CheckLocal({ byType = { license = 'license:expired' } }, { 'token-active' })
check(found and found.public_id == 'ACTIVE-B', 'token ativo apos identifier expirado nao bloqueou')

reset()
bansByIdentifier['license:active'] = ban('ACTIVE-A', 2000)
bansByToken['token-expired'] = ban('EXPIRED-B', 999)
found = MZBan.Bans.CheckLocal({ byType = { license = 'license:active' } }, { 'token-expired' })
check(found and found.public_id == 'ACTIVE-A', 'identifier ativo com token expirado nao bloqueou')

if #failures > 0 then
    io.stderr:write(('ban_expiry_regression_harness: %d/%d checks failed\n'):format(#failures, checks))
    for _, failure in ipairs(failures) do io.stderr:write(' - ' .. failure .. '\n') end
    os.exit(1)
end

print(('ban_expiry_regression_harness: ok (%d checks)'):format(checks))
