local exported = {}
local invokingResource = 'untrusted_resource'
local savedFlags = {}
local audits = {}
local gameTimer = 1000
local droppedPlayers = 0

local function expect(condition, message)
    if not condition then error(message, 2) end
end

Config = {
    Permissions = {
        Admin = 'mzban.admin'
    },
    Privacy = {
        StoreIpLocal = false
    },
    Risk = {
        Enabled = true,
        ExportAccess = {
            FlagPlayer = {
                test_detector = true
            },
            RegisterTrustedAction = {
                test_controller = true
            },
            GetRiskScore = {
                mz_admin = true
            }
        },
        ExportLimits = {
            MaxPointsPerFlag = 100,
            MaxTrustedActionMs = 30000,
            MaxEvidenceKeys = 20,
            MaxEvidenceDepth = 2,
            MaxEvidenceString = 256
        },
        DecayPointsEveryMinute = 0,
        MaxScore = 200,
        AlertAt = 500,
        ReviewAt = 25,
        AutoKick = false,
        KickAt = 25,
        AutoBan = false,
        BanAt = 800,
        DefaultPoints = {
            generic = 25
        },
        TrustedActions = {
            Enabled = true,
            DefaultDurationMs = 8000
        }
    }
}

MZBan = {
    DB = {
        IsReady = function() return true end,
        SaveFlag = function(payload)
            savedFlags[#savedFlags + 1] = payload
        end,
        Audit = function(action, payload)
            audits[#audits + 1] = {
                action = action,
                payload = payload
            }
        end
    },
    Cloud = {
        ReportFlag = function() end
    },
    Webhook = {
        Field = function(name, value)
            return { name = name, value = value }
        end,
        Send = function() end
    },
    Bans = {},
    Truncate = function(value, maxLength)
        value = tostring(value or '')
        return #value > maxLength and value:sub(1, maxLength) or value
    end,
    Now = function() return 1700000000 end,
    GetIdentifiers = function()
        return {
            byType = {
                license = 'license:test'
            }
        }
    end,
    GetPrimaryIdentifier = function()
        return 'license:test'
    end,
    HasPermission = function()
        return false
    end,
    JsonEncode = function()
        return '{}'
    end,
    Redact = function(value)
        return value
    end
}

local trustedLease
MZBan.SecurityLeases = {
    Issue = function(sourceId, capability, duration, _, issuer)
        if issuer ~= 'test_controller' or capability ~= 'movement.teleport' then
            return nil, 'issuer_not_allowed'
        end
        trustedLease = { source = sourceId, capability = capability, expiresAt = gameTimer + duration }
        return 'LEASE-1'
    end,
    Check = function(sourceId, capability)
        return trustedLease ~= nil and trustedLease.source == sourceId
            and trustedLease.capability == capability and trustedLease.expiresAt > gameTimer
    end
}

exports = setmetatable({}, {
    __call = function(_, name, callback)
        exported[name] = callback
    end
})

function GetInvokingResource()
    return invokingResource
end

function GetPlayerName(sourceId)
    return tonumber(sourceId) == 2 and 'Target' or nil
end

function GetGameTimer()
    return gameTimer
end

function GetCurrentResourceName()
    return 'mz_banguard'
end

function CreateThread(callback)
    callback()
end

function DropPlayer()
    droppedPlayers = droppedPlayers + 1
end

dofile('mz_banguard/server/flags.lua')

expect(type(exported.FlagPlayer) == 'function', 'export FlagPlayer ausente')
expect(type(exported.RegisterTrustedAction) == 'function', 'export RegisterTrustedAction ausente')
expect(type(exported.GetRiskScore) == 'function', 'export GetRiskScore ausente')

local ok, err = exported.FlagPlayer(2, 'teleport', 10, { detail = 'teste' })
expect(ok == false and err == 'untrusted_resource', 'resource nao autorizado conseguiu registrar flag')
expect(#savedFlags == 0, 'resource nao autorizado causou mutacao de score')
expect(audits[1] and audits[1].action == 'risk.export.denied', 'negacao de export nao foi auditada')

ok, err = exported.FlagPlayer(2, 'teleport', 10, { detail = 'repeticao' })
expect(ok == false and err == 'untrusted_resource', 'segunda chamada nao autorizada foi aceita')
expect(#audits == 1, 'negacao repetida ignorou cooldown de auditoria')

ok, err = exported.RegisterTrustedAction(2, 'teleport', 1000)
expect(ok == false and err == 'untrusted_resource', 'resource nao autorizado criou janela confiavel')

local score
score, err = exported.GetRiskScore(2)
expect(score == nil and err == 'untrusted_resource', 'resource nao autorizado leu score')

invokingResource = 'test_detector'
local longText = string.rep('x', 400)
ok, err, score = exported.FlagPlayer(2, 'teleport', 20, {
    detail = longText,
    nested = {
        allowed = true,
        tooDeep = {
            secret = 'discard'
        }
    }
})
expect(ok == true and err == 'flagged' and score == 20, 'detector autorizado nao registrou flag')
expect(#savedFlags == 1, 'flag autorizada nao foi persistida uma unica vez')
expect(#savedFlags[1].evidence.detail == 256, 'evidencia textual nao respeitou limite')
expect(savedFlags[1].evidence.nested.allowed == true, 'evidencia valida foi removida')
expect(savedFlags[1].evidence.nested.tooDeep == nil, 'evidencia acima da profundidade foi preservada')
expect(savedFlags[1].created_by_resource == 'test_detector', 'origem da flag nao foi registrada')

ok, err = exported.FlagPlayer(2, 'teleport', 101, {})
expect(ok == false and err == 'invalid_points', 'pontuacao acima do limite foi aceita')
expect(#savedFlags == 1, 'pontuacao invalida causou persistencia')

invokingResource = 'test_controller'
ok, err = exported.RegisterTrustedAction(2, 'movement.teleport', 30001)
expect(ok == false and err == 'invalid_duration', 'janela confiavel acima do limite foi aceita')

ok, err = exported.RegisterTrustedAction(2, '*', 1000)
expect(ok == false and err == 'invalid_request', 'janela confiavel wildcard foi aceita')

ok, err = exported.RegisterTrustedAction(2, 'teleport', 1000)
expect(ok == true and err == nil, 'lease de teleport autorizada falhou')

invokingResource = 'test_detector'
ok, err, score = exported.FlagPlayer(2, 'teleport', 10, {})
expect(ok == false and err == 'trusted_action' and score == nil, 'janela confiavel nao suprimiu flag')
expect(#savedFlags == 1, 'acao confiavel causou persistencia de flag')

gameTimer = 2500
ok, err, score = exported.FlagPlayer(2, 'teleport', 10, {})
expect(ok == true and err == 'flagged' and score == 30, 'flag nao retornou apos expirar janela confiavel')
expect(droppedPlayers == 0, 'AutoKick=false removeu jogador ao atingir KickAt')

invokingResource = 'mz_admin'
score, err = exported.GetRiskScore(2)
expect(score == 30 and err == nil, 'consumer autorizado nao leu score')

Config.Risk.AutoKick = true
invokingResource = 'test_detector'
ok, err, score = exported.FlagPlayer(2, 'teleport', 10, {})
expect(ok == true and err == 'kick' and score == 40, 'AutoKick=true nao respeitou KickAt')
expect(droppedPlayers == 1, 'AutoKick=true nao executou exatamente um kick')

print('mz_banguard risk export access harness: PASS')
