Config = {}

Config.Version = '1.2.0'
Config.Debug = false

Config.Permissions = {
    Admin = 'mzban.admin',
    Ban = 'mzban.ban',
    Unban = 'mzban.unban',
    Lookup = 'mzban.lookup'
}

Config.Commands = {
    Ban = 'ban',
    Unban = 'unban',
    Info = 'baninfo',
    Lookup = 'banlookup',
    Flags = 'banflags'
}

Config.Database = {
    -- Instalação nova: cria somente tabelas totalmente ausentes com
    -- CREATE TABLE IF NOT EXISTS.
    AutoCreateMissingTables = true,

    -- Tabelas existentes nunca recebem ALTER por padrão. Schemas antigos
    -- incompletos falham em IsReady e exigem upgrade manual revisado.
    AutoMigrateExistingTables = false,
    ReadyCacheSeconds = 30,

    -- Limpeza automática para evitar banco infinito.
    Retention = {
        Enabled = false,
        SeenDays = 90,
        AuditDays = 180,
        FlagsDays = 180,
        RunEveryHours = 12
    }
}

Config.Integration = {
    CoreResource = 'mz_core',
    TrustedResources = {
        mz_admin = true,
        mz_banguard = true
    },
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

Config.Whitelist = {
    Resource = 'mz_whitelist',
    -- O resource ausente nao ativa whitelist. Se estiver iniciado, falhas no
    -- contrato sao negadas para evitar bypass quando o modo enforce estiver ativo.
    FailClosedWhenStarted = true
}

Config.Local = {
    Enabled = true,
    UsePlayerTokens = true,
    TokenMatchAutoBan = true,
    CleanExpiredOnCheck = true
}

Config.Privacy = {
    -- Recomendado false. IP é útil em investigação, mas aumenta risco LGPD.
    StoreIpLocal = false,

    -- Tokens ficam no banco local do cliente para detectar evasão.
    -- Não são enviados para cloud nesta versão.
    StoreTokensLocal = true,

    -- Evita mostrar identifier completo em logs/chat.
    RedactIdentifiersInOutput = true
}

Config.Cloud = {
    Enabled = false,

    -- Exemplo: 'https://banguard.seudominio.com'
    BaseUrl = 'http://127.0.0.1:8089',

    -- Gerada pela sua API no endpoint /v1/admin/servers
    ApiKey = 'COLOQUE_A_API_KEY_DO_SERVIDOR_AQUI',

    -- Proteções para não travar playerConnecting quando a cloud cair.
    TimeoutMs = 5000,
    CacheTtlSec = 300,
    FailureCooldownSec = 60,

    -- Se false, bans cloud só geram log/flag.
    -- Se true, bloqueia quando a API retornar deny ou risco >= RiskDenyThreshold com ban ativo.
    AutoBlock = false,
    RiskDenyThreshold = 90,

    -- Não envie IP para cloud por padrão. Deixe false para reduzir risco LGPD.
    SendIpToCloud = false,

    ReportLocalBans = true,
    ReportUnbans = true,
    ReportFlags = true
}

Config.Identifiers = {
    Include = {
        license = true,
        license2 = true,
        discord = true,
        fivem = true,
        steam = true,
        xbl = true,
        live = true,
        ip = true
    },

    RequiredForJoin = {
        license = true
    }
}

Config.Risk = {
    Enabled = true,

    -- Exports entre resources começam fechados. Adicione somente resources
    -- revisados que realmente produzam detecções ou ações legítimas.
    ExportAccess = {
        FlagPlayer = {},
        RegisterTrustedAction = {},
        GetRiskScore = {
            mz_admin = true
        }
    },

    ExportLimits = {
        MaxPointsPerFlag = 100,
        MaxTrustedActionMs = 30000,
        MaxEvidenceKeys = 20,
        MaxEvidenceDepth = 2,
        MaxEvidenceString = 256,
        DeniedAuditCooldownMs = 10000
    },

    -- Decaimento simples para não punir eternamente por um alerta antigo.
    DecayPointsEveryMinute = 4,
    MaxScore = 200,

    AlertAt = 40,
    ReviewAt = 70,
    KickAt = 110,

    -- Ban automático fica desligado por segurança. Use apenas depois de testar muito.
    AutoBan = false,
    BanAt = 150,

    DefaultPoints = {
        event_injection = 100,
        money_injection = 100,
        item_injection = 90,
        explosion_spam = 90,
        entity_spam = 80,
        teleport = 45,
        noclip = 45,
        speedhack = 40,
        godmode = 60,
        weapon_abuse = 45,
        generic = 25
    },

    TrustedActions = {
        Enabled = true,
        DefaultDurationMs = 8000
    }
}

Config.Webhook = {
    Enabled = false,
    Url = '',
    Username = 'MZ BanGuard',
    AvatarUrl = '',

    Events = {
        BanCreated = true,
        BanRevoked = true,
        CloudDenied = true,
        CloudFlagged = true,
        RiskAlert = true,
        RiskReview = true,
        RiskKick = true,
        AutoBan = true
    }
}

Config.Messages = {
    Checking = 'Verificando informações de banimento...',
    NoLicense = 'Não foi possível identificar sua license FiveM. Reinicie o FiveM e tente novamente.',
    LocalBan = 'Você está banido deste servidor. Código: %s\nMotivo: %s\nExpira: %s',
    CloudBan = 'Você possui banimento ativo na rede. Código: %s\nMotivo: %s',
    DatabaseUnavailable = 'O sistema de segurança está temporariamente indisponível. Tente novamente mais tarde.',
    WhitelistUnavailable = 'O sistema de whitelist esta temporariamente indisponivel. Tente novamente mais tarde.',
    StaffNoPerm = 'Você não tem permissão para usar este comando.',
    InvalidTarget = 'Jogador inválido.',
    InvalidUsageBan = 'Uso: /ban [id] [tempo|perm] [motivo]',
    InvalidUsageUnban = 'Uso: /unban [public_id] [motivo]',
    InvalidUsageLookup = 'Uso: /banlookup [tipo] [valor]',
    InvalidUsageFlags = 'Uso: /banflags [id]',
    BanCreated = 'Ban criado. Código: %s',
    BanRevoked = 'Ban revogado: %s',
    BanNotFound = 'Ban não encontrado.',
    BanAlreadyRevoked = 'Este ban já foi revogado.',
    BanExpired = 'Este ban temporário já expirou.'
}

Config.LegacyCommands = {
    OwnerAce = 'group.mz_owner',
    -- Staff comum usa as permissoes globais do mz_core. Ative somente se
    -- desejar uma segunda barreira ACE para os comandos historicos.
    RequireLegacyAceForPlayers = false,
    IdentifierLookupOwnerOnly = true
}

Config.Audit = {
    PrintToConsole = true
}
