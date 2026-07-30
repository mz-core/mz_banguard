local function expect(condition, message)
    if not condition then error(message, 2) end
end

local function read(path)
    local file, err = io.open(path, 'rb')
    if not file then error(err, 2) end
    local content = file:read('*a')
    file:close()
    return content
end

local commands = read('mz_banguard/server/commands.lua')
local config = read('mz_banguard/config.lua')

local banCommand = commands:match(
    'RegisterCommand%(Config%.Commands%.Ban,.-\nend, false%)\n\nRegisterCommand%(Config%.Commands%.Unban'
)
local unbanCommand = commands:match(
    'RegisterCommand%(Config%.Commands%.Unban,.-\nend, false%)\n\nRegisterCommand%(Config%.Commands%.Info'
)
local infoCommand = commands:match(
    'RegisterCommand%(Config%.Commands%.Info,.-\nend, false%)\n\nRegisterCommand%(Config%.Commands%.Flags'
)
local flagsCommand = commands:match(
    'RegisterCommand%(Config%.Commands%.Flags,.-\nend, false%)\n\nRegisterCommand%(Config%.Commands%.Lookup'
)
local lookupCommand = commands:match(
    'RegisterCommand%(Config%.Commands%.Lookup,.-\nend, false%)'
)

expect(type(banCommand) == 'string', 'bloco do comando ban nao localizado')
expect(type(unbanCommand) == 'string', 'bloco do comando unban nao localizado')
expect(type(infoCommand) == 'string', 'bloco do comando baninfo nao localizado')
expect(type(flagsCommand) == 'string', 'bloco do comando banflags nao localizado')
expect(type(lookupCommand) == 'string', 'bloco do comando banlookup nao localizado')

expect(
    banCommand:find("MZBan.API.CreateOnlineBan(src, target, durationArg, reason, 'mz_banguard')", 1, true) ~= nil,
    'ban de jogador nao usa API oficial'
)
expect(
    banCommand:find('MZBan.Bans.Create', 1, true) == nil,
    'ban de jogador acessa repositorio diretamente'
)
expect(
    unbanCommand:find("MZBan.API.RevokeBan(src, publicId, reason, 'mz_banguard')", 1, true) ~= nil,
    'unban de jogador nao usa API oficial'
)
expect(
    unbanCommand:find('MZBan.Bans.Revoke', 1, true) == nil,
    'unban de jogador acessa repositorio diretamente'
)
expect(
    commands:find("action = 'ban.created.legacy_console'", 1, true) ~= nil,
    'ban via console nao possui auditoria transacional'
)
expect(
    commands:find("action = 'ban.revoked.legacy_console'", 1, true) ~= nil,
    'unban via console nao possui auditoria transacional'
)
expect(
    commands:find('MZBan.DB.Audit%(\'ban%.revoked\'') == nil,
    'comando legado manteve auditoria separada da revogacao'
)

expect(
    infoCommand:find('legacyStaffAllowed', 1, true) ~= nil
        and flagsCommand:find('legacyStaffAllowed', 1, true) ~= nil,
    'consultas legadas nao exigem permissao global'
)
expect(
    infoCommand:find('readHierarchyAllowed', 1, true) ~= nil
        and flagsCommand:find('readHierarchyAllowed', 1, true) ~= nil,
    'consultas legadas nao revalidam hierarquia'
)
expect(
    lookupCommand:find('IdentifierLookupOwnerOnly', 1, true) ~= nil
        and lookupCommand:find('not isOwner(src)', 1, true) ~= nil,
    'lookup por identifier nao esta reservado ao Owner por padrao'
)
expect(
    lookupCommand:find("identifierType:match('^[a-z0-9_]+$')", 1, true) ~= nil,
    'tipo de identifier nao e validado'
)
expect(
    config:find('RequireLegacyAceForPlayers = false', 1, true) ~= nil,
    'comandos historicos ainda exigem ACE para Staff comum'
)
expect(
    config:find('IdentifierLookupOwnerOnly = true', 1, true) ~= nil,
    'lookup por identifier nao esta fechado para Owner'
)
expect(
    config:find('mz_banguard = true', 1, true) ~= nil,
    'caller interno mz_banguard nao foi declarado na API oficial'
)
expect(config:find("Ban = 'ban'", 1, true) ~= nil, 'nome canonico /ban ausente')
expect(config:find("Unban = 'unban'", 1, true) ~= nil, 'nome canonico /unban ausente')
expect(config:find("Info = 'baninfo'", 1, true) ~= nil, 'nome canonico /baninfo ausente')
expect(config:find("Lookup = 'banlookup'", 1, true) ~= nil, 'nome canonico /banlookup ausente')
expect(config:find("Flags = 'banflags'", 1, true) ~= nil, 'nome canonico /banflags ausente')
expect(config:find("Ban = 'mzban'", 1, true) == nil, 'alias antigo /mzban continua ativo')
expect(config:find("Unban = 'mzunban'", 1, true) == nil, 'alias antigo /mzunban continua ativo')
expect(
    commands:find('if legacyConfig().RequireLegacyAceForPlayers ~= true then return true end', 1, true) ~= nil,
    'barreira ACE opcional dos comandos historicos nao foi localizada'
)
expect(
    commands:find('local allowed, permissionError = corePermission(src, globalPermission)', 1, true) ~= nil,
    'Staff comum nao usa a permissao global como autoridade primaria'
)
expect(
    commands:find('RequireGlobalPermissions == false', 1, true) == nil,
    'foi preservado fallback que desliga permissoes globais'
)

print('mz_banguard legacy commands contract harness: PASS')
