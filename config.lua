Config = {}

Config.Version = '1.6.0'
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
        IncidentsDays = 365,
        SignalsDays = 90,
        RunEveryHours = 12
    }
}

Config.Integration = {
    CoreResource = 'mz_core',
    InventoryResource = 'mz_inventory',
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
        RegisterTrustedAction = {
            -- Usado apenas para teleports administrativos autorizados.
            mz_admin = true
        },
        RegisterSecurityLease = {
            mz_admin = true,
            mz_core = true
        },
        BeginSecurityLifecycle = {
            mz_core = true,
            mz_creator = true,
            mz_clothing = true,
            mz_tatto = true,
            mz_houses = true,
            mz_interiors = true
        },
        EndSecurityLifecycle = {
            mz_core = true,
            mz_creator = true,
            mz_clothing = true,
            mz_tatto = true,
            mz_houses = true,
            mz_interiors = true
        },
        CheckSecurityLifecycle = {
            mz_core = true,
            mz_creator = true,
            mz_clothing = true,
            mz_tatto = true,
            mz_houses = true
        },
        ValidateEventContract = {
            mz_admin = true,
            mz_creator = true,
            mz_clothing = true,
            mz_tatto = true,
            mz_houses = true,
            mz_interiors = true
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
        MaxEvidenceString = 256,
        DeniedAuditCooldownMs = 10000
    },

    -- Decaimento simples para não punir eternamente por um alerta antigo.
    DecayPointsEveryMinute = 4,
    MaxScore = 200,

    AlertAt = 40,
    ReviewAt = 70,

    -- PUNICAO AUTOMATICA (DESLIGADA PARA STAGING):
    -- false = atingir KickAt gera somente alerta/revisao; nenhum DropPlayer.
    -- true  = permite kick automatico por score. Ative somente depois de validar
    --         individualmente todos os detectores que alimentam FlagPlayer.
    AutoKick = false,
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

-- Politica canonica de atuacao. Os modos de detector abaixo substituem a
-- decisao dispersa de punicao, mas preservam as travas tecnicas dos guards.
Config.Enforcement = {
    DefaultMode = 'passive',
    AutomaticKickEnabled = false,
    AutomaticBanEnabled = false,
    RequireStableIdentity = true,
    RequireConfirmedEvidence = true,
    OnMitigationFailure = 'log_only'
}

-- Overrides opcionais por codigo do DetectorCatalog. Codigos ausentes herdam
-- Enforcement.DefaultMode. Ative mitigate somente depois da validacao runtime
-- especifica do guard; kick e ban continuam bloqueados pelas chaves globais.
Config.DetectorActions = {}

-- Autorizacoes server-only, curtas e consumiveis. O export legado
-- RegisterTrustedAction e traduzido para este contrato.
Config.SecurityLeases = {
    enabled = true,
    defaultTtlMs = 8000,
    maxTtlMs = 30000,
    maxActivePerPlayer = 32,
    cleanupIntervalMs = 5000,
    audit = true,
    capabilities = {
        ['movement.teleport'] = {
            ttlMs = 10000,
            maxTtlMs = 30000,
            uses = 4,
            issuers = {
                mz_admin = true, mz_core = true
            }
        },
        ['movement.noclip.staff'] = { ttlMs = 10000, maxTtlMs = 15000, uses = 8, issuers = { mz_admin = true } },
        ['camera.spectate.staff'] = { ttlMs = 10000, maxTtlMs = 15000, uses = 8, issuers = { mz_admin = true } },
        ['player.invincibility'] = {
            ttlMs = 8000,
            maxTtlMs = 15000,
            uses = 4,
            issuers = {
                mz_admin = true
            }
        },
        ['player.model.change'] = {
            ttlMs = 8000,
            maxTtlMs = 15000,
            uses = 2,
            issuers = {
                mz_core = true
            }
        },
        ['entity.spawn.ped'] = { ttlMs = 5000, maxTtlMs = 15000, uses = 16, issuers = {} },
        ['entity.spawn.vehicle'] = {
            ttlMs = 5000,
            maxTtlMs = 15000,
            uses = 8,
            issuers = {
                mz_admin = true
            }
        },
        ['entity.spawn.object'] = { ttlMs = 5000, maxTtlMs = 15000, uses = 32, issuers = {} },
        ['event.clear_tasks.remote'] = { ttlMs = 3000, maxTtlMs = 8000, uses = 2, issuers = {} },
        ['weapon.give.remote'] = { ttlMs = 3000, maxTtlMs = 8000, uses = 2, issuers = {} },
        ['weapon.remove.remote'] = { ttlMs = 3000, maxTtlMs = 8000, uses = 2, issuers = {} },
        ['event.explosion.scripted'] = { ttlMs = 3000, maxTtlMs = 8000, uses = 4, issuers = {} }
    }
}

-- Sessoes server-side para transicoes de lifecycle. Diferente de uma whitelist,
-- cada tipo possui emissor, escopo e TTL proprios; o cliente apenas confirma uma
-- sessao que ja foi criada pelo servidor e nao consegue amplia-la.
Config.SecurityLifecycle = {
    enabled = true,
    maxTtlMs = 300000,
    maxActivePerPlayer = 4,
    cleanupIntervalMs = 5000,
    postConfirmGraceMs = 5000,
    coordinateTolerance = 15.0,
    confirmationTolerance = 25.0,
    types = {
        character_spawn = {
            ttlMs = 45000,
            issuers = { mz_core = true },
            transitions = {
                movement = true,
                model = true,
                camera = true,
                invincibility = true,
                invisibility = true
            }
        },
        respawn = {
            ttlMs = 20000,
            issuers = { mz_banguard = true },
            transitions = {
                movement = true,
                model = true,
                camera = true,
                invincibility = true,
                invisibility = true
            }
        },
        character_creation = {
            ttlMs = 300000,
            issuers = { mz_creator = true },
            transitions = {
                movement = true,
                model = true,
                camera = true,
                invincibility = true,
                invisibility = true
            }
        },
        cosmetic_session = {
            ttlMs = 180000,
            issuers = { mz_clothing = true, mz_tatto = true, mz_houses = true },
            enders = { mz_clothing = true, mz_tatto = true, mz_houses = true },
            transitions = { camera = true, invincibility = true, invisibility = true }
        },
        interior_transition = {
            ttlMs = 15000,
            issuers = { mz_houses = true },
            transitions = { movement = true, camera = true }
        },
        interior_calibration = {
            ttlMs = 30000,
            issuers = { mz_interiors = true },
            transitions = { movement = true, camera = true }
        }
    }
}

-- O mapeamento segue a classificacao observada do GTA/OneSync, mas permanece
-- explicitamente marcado para validacao no artifact de staging. Entidades de
-- populacao ambiente viram metrica; unknown/scripted continuam sob rate guard.
Config.EntityClassification = {
    enabled = true,
    mappingVersion = 'gta5-population-v1',
    mappingValidated = false,
    populationTypes = {
        [0] = { name = 'unknown_or_script_created', class = 'scripted_unknown' },
        [1] = { name = 'random_permanent', class = 'ambient' },
        [2] = { name = 'random_parked', class = 'ambient' },
        [3] = { name = 'random_patrol', class = 'ambient' },
        [4] = { name = 'random_scenario', class = 'ambient' },
        [5] = { name = 'random_ambient', class = 'ambient' },
        [6] = { name = 'permanent', class = 'scripted' },
        [7] = { name = 'mission', class = 'scripted' },
        [8] = { name = 'replay', class = 'system' },
        [9] = { name = 'cache', class = 'system' },
        [10] = { name = 'tool', class = 'system' }
    },
    classes = {
        ambient = { alertOnRate = false, confidence = 'low' },
        system = { alertOnRate = false, confidence = 'low' },
        scripted = { alertOnRate = true, confidence = 'high' },
        scripted_unknown = { alertOnRate = true, confidence = 'medium' },
        unknown = { alertOnRate = true, confidence = 'medium' }
    }
}

Config.EventContracts = {
    enabled = true,
    maxPayloadKeys = 24,
    maxDepth = 2,
    maxString = 256,
    replayTtlMs = 60000,
    cleanupIntervalMs = 10000,
    trustedResources = {
        mz_admin = true,
        mz_creator = true,
        mz_clothing = true,
        mz_tatto = true,
        mz_houses = true,
        mz_interiors = true
    },
    contracts = {
        ['lifecycle.creator.open'] = {
            sourceOnline = true,
            schema = { type = 'table', allowExtra = false, fields = {} }
        },
        ['lifecycle.clothing.open'] = {
            sourceOnline = true,
            schema = {
                type = 'table',
                allowExtra = false,
                fields = {
                    shopId = { type = 'string', required = true, maxLength = 64 },
                    securityLifecycleId = { type = 'string', required = false, maxLength = 96 }
                }
            }
        },
        ['lifecycle.tattoo.open'] = {
            sourceOnline = true,
            schema = {
                type = 'table',
                allowExtra = false,
                fields = {
                    shopId = { type = 'string', required = true, maxLength = 64 },
                    gender = { type = 'string', required = false, maxLength = 16 },
                    model = { type = 'string', required = false, maxLength = 64 },
                    securityLifecycleId = { type = 'string', required = false, maxLength = 96 }
                }
            }
        },
        ['lifecycle.house.enter'] = {
            sourceOnline = true,
            schema = {
                type = 'table',
                allowExtra = false,
                fields = {
                    houseCode = { type = 'string', required = false, maxLength = 64 },
                    code = { type = 'string', required = false, maxLength = 64 }
                }
            }
        },
        ['lifecycle.house.confirm'] = {
            sourceOnline = true,
            schema = {
                type = 'table',
                allowExtra = false,
                fields = {
                    houseCode = { type = 'string', required = false, maxLength = 64 },
                    code = { type = 'string', required = false, maxLength = 64 }
                }
            }
        },
        ['lifecycle.house.leave'] = {
            sourceOnline = true,
            schema = { type = 'table', allowExtra = false, fields = {} }
        },
        ['lifecycle.interiors.calibration.exit'] = {
            sourceOnline = true,
            schema = { type = 'table', allowExtra = false, fields = {} }
        },
        ['lifecycle.interiors.calibration.result'] = {
            sourceOnline = true,
            schema = {
                type = 'table',
                allowExtra = false,
                fields = {
                    phase = { type = 'string', required = true, maxLength = 8 },
                    lifecycleId = { type = 'string', required = false, maxLength = 96 },
                    success = { type = 'boolean', required = true },
                    error = {
                        type = 'string',
                        required = false,
                        maxLength = 64,
                        pattern = '^[a-z0-9_]+$'
                    }
                }
            }
        },
        ['lifecycle.interiors.calibration.report'] = {
            sourceOnline = true,
            schema = {
                type = 'table',
                allowExtra = false,
                fields = {
                    code = { type = 'string', required = true, maxLength = 64, pattern = '^[a-z0-9_]+$' },
                    x = { type = 'number', required = true, min = -20000, max = 20000 },
                    y = { type = 'number', required = true, min = -20000, max = 20000 },
                    z = { type = 'number', required = true, min = -2000, max = 3000 },
                    heading = { type = 'number', required = true, min = 0, max = 360 },
                    expectedInteriorId = { type = 'number', required = true, min = 1 },
                    resolvedInteriorId = { type = 'number', required = true, min = 1 },
                    interiorMatches = { type = 'boolean', required = true }
                }
            }
        }
    }
}

Config.SecurityCorrelation = {
    enabled = true,
    ttlMs = 30000,
    maxEntriesPerPlayer = 32,
    snapshotEntries = 16,
    labTtlMs = 120000,
    labMaxEntriesPerPlayer = 96,
    labSnapshotEntries = 64,
    maxDataKeys = 16,
    maxString = 128,
    crashClusterWindowMs = 5000,
    crashHistoryMs = 15000,
    crashMinimumVictims = 2,
    crossSessionLinkWindowSeconds = 86400,
    -- Sinais que ja originam incidente permanecem na timeline em memoria, mas
    -- nao sao duplicados no SQL como correlation + raw signal.
    persistIncidentBacked = false
}

Config.IncidentPersistence = {
    enabled = true,
    hydrateLimit = 1000,
    updateDebounceMs = 5000,
    flushIntervalMs = 2000,
    maxWritesPerMinute = 120,
    maxEvidenceJsonBytes = 65535,
    maxTimelineJsonBytes = 65535,
    maxSummaryJsonBytes = 16384,
    maxMitigationJsonBytes = 16384,
    exportMaxBytes = 262144,
    maxPendingIncidents = 500,
    maxPendingSignals = 256,
    signalFlushBatch = 16,
    retryBaseMs = 1000,
    rawSignalWindowMs = 10000,
    rawSignalBurst = 8,
    rawSignalRepresentativeEvery = 100
}

Config.LabMode = {
    enabled = true,
    defaultDurationSeconds = 3600,
    maximumDurationSeconds = 86400
}

Config.SecurityCanaries = {
    enabled = true,
    owners = { mz_inventory = 'inventory' }
}

Config.DetectorHealth = {
    enabled = true,
    ruleVersion = '1.6.0',
    heartbeatIntervalMs = 15000,
    heartbeatMissingMs = 45000,
    cleanupIntervalMs = 10000,
    watchedResources = { mz_banguard = true, mz_inventory = true }
}

-- Configuracao comum da Central. Estes limites controlam armazenamento,
-- notificacao e relatos client-side; nao habilitam punicao automatica.
Config.SecurityAlerts = {
    notifyStaff = true,
    -- Durante staging, medium/high/critical notificam a Staff. Incidentes info/low
    -- continuam visiveis na Central sem popup.
    notifyMinimumSeverity = 'medium',
    aggregateWindowMs = 15000,
    duplicateCooldownMs = 1500,
    notificationCooldownMs = 10000,
    incidentTtlMs = 3600000,
    cleanupIntervalMs = 60000,
    maxIncidents = 1000,
    maxEvidencePerIncident = 20,
    maxNotesPerIncident = 25,

    clientReportWindowMs = 10000,
    clientReportLimit = 8,
    clientReasonCooldownMs = 8000,

    trustedConsumers = {
        mz_admin = true
    },

    permissions = {
        view = 'mz_banguard.alerts.view',
        details = 'mz_banguard.alerts.details',
        acknowledge = 'mz_banguard.alerts.acknowledge',
        note = 'mz_banguard.alerts.note',
        clear = 'mz_banguard.alerts.clear',
        identifiers = 'mz_banguard.alerts.identifiers',
        lab = 'mz_banguard.alerts.lab',
        spectate = 'mz_banguard.actions.spectate',
        gotoPlayer = 'mz_banguard.actions.goto',
        kick = 'mz_banguard.actions.kick',
        ban = 'mz_banguard.actions.ban'
    },

    riskPoints = {
        entity_spawn_rate_suspect = 45,
        entity_model_blocked = 55,
        movement_teleport_suspect = 35,
        movement_noclip_suspect = 30,
        movement_vehicle_reentry_distance = 25,
        camera_freecam_suspect = 25,
        camera_spectate_unapproved = 30,
        player_model_change_unapproved = 25,
        player_godmode_suspect = 30,
        player_invisible_suspect = 25,
        event_explosion_rate_suspect = 40,
        event_explosion_anomaly_suspect = 55,
        event_clear_tasks_rate_suspect = 35,
        event_remote_clear_tasks_suspect = 55,
        event_tazer_rate_suspect = 35,
        event_ptfx_rate_suspect = 35,
        event_ptfx_anomaly_suspect = 45,
        event_projectile_rate_suspect = 40,
        projectile_weapon_unauthorized = 35,
        event_fire_rate_suspect = 35,
        event_fire_remote_suspect = 45,
        event_remote_weapon_action_suspect = 55,
        event_damage_modifier_suspect = 50,
        aim_headshot_pattern_suspect = 30,
        crash_observed = 20,
        crash_cluster_suspect = 45,
        client_resource_presence_missing = 0,
        client_resource_stop_observed = 0,
        canary_triggered = 0
    }
}

Config.WeaponGuard = {
    -- LIGA/DESLIGA O OBSERVADOR INTEIRO:
    -- false = ignora weaponDamageEvent, nao cria incidentes e nao notifica.
    enabled = true,

    -- MODOS DISPONIVEIS:
    -- 'observe' = recomendado. Registra, agrega e notifica, mas nunca cancela o dano.
    -- 'mitigate'/'enforce' = permite cancelar somente divergencias de alta confianca e apenas
    --             quando cancelHighConfidence e runtimeValidated tambem forem true.
    mode = 'observe',

    -- TRAVAS DO ENFORCE:
    -- Deixe ambas false ate concluir todos os testes do checklist de staging.
    -- Mesmo com mode = 'enforce', qualquer uma delas false impede o cancelamento.
    cancelHighConfidence = false,
    runtimeValidated = false,

    -- Envia alertas high/critical apenas para Staff com permissao, usando cooldown.
    notifyStaff = true,

    transitionWindowMs = 2500,
    aggregateWindowMs = 10000,
    duplicateCooldownMs = 1500,
    notificationCooldownMs = 10000,
    incidentTtlMs = 3600000,
    cleanupIntervalMs = 60000,
    maxIncidents = 1000,
    maxEvidencePerIncident = 20,
    maxNotesPerIncident = 25,

    rateWindowMs = 1000,
    rateEventThreshold = 25,
    -- Perfis conservadores por arma. O fallback preserva o limite historico.
    -- Estes limites geram somente alerta enquanto mode='observe'.
    rateProfiles = {
        default = { windowMs = 1000, threshold = 25 },
        WEAPON_PISTOL = { windowMs = 1000, threshold = 35 },
        WEAPON_SMG = { windowMs = 1000, threshold = 65 },
        WEAPON_PUMPSHOTGUN = { windowMs = 1000, threshold = 15 },
        WEAPON_CARBINERIFLE = { windowMs = 1000, threshold = 70 },
        WEAPON_SNIPERRIFLE = { windowMs = 1000, threshold = 10 },
        WEAPON_MG = { windowMs = 1000, threshold = 90 },
        WEAPON_RPG = { windowMs = 1000, threshold = 6 }
    },

    trustedConsumers = {
        mz_admin = true
    },

    permissions = {
        view = 'mz_banguard.alerts.view',
        details = 'mz_banguard.alerts.details',
        acknowledge = 'mz_banguard.alerts.acknowledge',
        note = 'mz_banguard.alerts.note',
        clear = 'mz_banguard.alerts.clear',
        identifiers = 'mz_banguard.alerts.identifiers',
        spectate = 'mz_banguard.actions.spectate',
        gotoPlayer = 'mz_banguard.actions.goto',
        kick = 'mz_banguard.actions.kick',
        ban = 'mz_banguard.actions.ban'
    },

    riskPoints = {
        weapon_damage_no_equipped_weapon = 45,
        weapon_damage_hash_mismatch = 35,
        weapon_damage_unknown_hash = 25,
        weapon_damage_payload_invalid = 20,
        weapon_damage_rate_suspect = 25,
        weapon_damage_death_state_incompatible = 55,
        weapon_damage_session_not_ready = 0,
        weapon_damage_transition_window = 0
    },

    knownWeaponNames = {
        'WEAPON_PISTOL',
        'WEAPON_SMG',
        'WEAPON_PUMPSHOTGUN',
        'WEAPON_CARBINERIFLE',
        'WEAPON_SNIPERRIFLE',
        'WEAPON_MG',
        'WEAPON_RPG'
    },
    unarmedWeaponNames = { 'WEAPON_UNARMED' }
}

Config.EntityGuard = {
    -- MODOS: observe/restricted somente registram; mitigate/enforce podem cancelar
    -- entityCreating de alta confianca somente com as duas travas abaixo.
    enabled = true,
    mode = 'observe',
    cancelHighConfidence = false,
    runtimeValidated = false,
    windowMs = 10000,
    burstWindowMs = 2000,
    inspectDelayMs = 250,
    ownerResolveAttempts = 3,
    ownerResolveRetryMs = 200,
    limits = {
        ped = 6,
        vehicle = 12,
        object = 20
    },
    burstLimits = {
        ped = 4,
        vehicle = 8,
        object = 12
    },
    blockedModels = {
        ped = {},
        vehicle = {},
        object = {}
    }
}

Config.MovementGuard = {
    -- Todas as verificacoes abaixo apenas registram na Central.
    enabled = true,
    mode = 'observe',
    runtimeValidated = false,
    sampleIntervalMs = 1000,
    spawnGraceMs = 20000,
    serverFallbackGraceMs = 3000,
    serverFootDistance = 220.0,
    serverVehicleDistance = 650.0,
    clientFootDistance = 160.0,
    clientVehicleDistance = 500.0,
    noclipDistance = 12.0,
    noclipHeight = 5.0,
    vehicleReentryDistance = 80.0,
    vehicleReentryWindowMs = 15000
}

Config.PlayerStateGuard = {
    -- Sinais client-side de baixa/media confianca; nunca punem sozinhos.
    enabled = true,
    mode = 'observe',
    runtimeValidated = false,
    sampleIntervalMs = 1500,
    spawnGraceMs = 20000,
    freecamDistance = 70.0,
    maxInvisibleAlpha = 120,
    samples = {
        freecam = 4,
        spectate = 3,
        godmode = 5,
        invisible = 5,
        modelChange = 3
    }
}

Config.EventGuard = {
    -- Observe nao cancela explosao, tazer ou clearPedTasksEvent.
    enabled = true,
    mode = 'observe',
    cancelHighConfidence = false,
    runtimeValidated = false,
    projectileAuthorityEnabled = true,
    windows = {
        explosionMs = 10000,
        clearTasksMs = 10000,
        tazerMs = 10000,
        ptfxMs = 10000,
        projectileMs = 10000,
        fireMs = 10000,
        remoteWeaponMs = 10000,
        modifierMs = 10000
    },
    limits = {
        explosion = 8,
        clearTasks = 8,
        tazer = 5,
        ptfx = 12,
        projectile = 10,
        fire = 10,
        remoteWeapon = 3,
        modifier = 2
    },
    maxParticleScale = 5.0,
    maxFireDistance = 160.0,
    maxExplosionDistance = 250.0,
    maxDamageScale = 1.0,
    maxWeaponDamageModifier = 1.05,
    maxMeleeDamageModifier = 1.05,
    maxWeaponDefenseModifier = 1.05
}

Config.AimGuard = {
    -- Analise estatistica minima. Permanece somente-alerta mesmo no futuro
    -- ate existir baseline representativa e revisao manual de falsos positivos.
    enabled = true,
    mode = 'observe',
    runtimeValidated = false,
    windowMs = 60000,
    minimumHits = 12,
    minimumHeadshots = 10,
    headshotRatio = 0.85,
    requiredQualifiedWindows = 2,
    candidateDecayWindows = 1,
    distanceBands = { 25.0, 75.0, 150.0 },
    pingBands = { 60, 120, 200 },
    headComponents = { 31086 },
    weaponNames = {
        'WEAPON_PISTOL',
        'WEAPON_COMBATPISTOL',
        'WEAPON_SMG',
        'WEAPON_CARBINERIFLE',
        'WEAPON_ASSAULTRIFLE',
        'WEAPON_SNIPERRIFLE',
        'WEAPON_HEAVYSNIPER'
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
