MZBan = MZBan or {}
MZBan.DetectorCatalog = MZBan.DetectorCatalog or {}

local DEFAULT_ACTION = 'Revisar a evidencia, a timeline e o contexto recente antes de agir.'

local DEFINITIONS = {
    weapon_damage_no_equipped_weapon = { 'Dano sem arma autorizada', 'Foi observado dano sem arma equipada no estado oficial.', 'Armas' },
    weapon_damage_hash_mismatch = { 'Arma divergente do estado oficial', 'A arma reportada diverge da arma equipada no servidor.', 'Armas' },
    weapon_damage_unknown_hash = { 'Hash de arma desconhecido', 'O evento informou uma arma fora do catalogo conhecido.', 'Armas' },
    weapon_damage_session_not_ready = { 'Sessao de arma ainda indisponivel', 'A autoridade de inventario ainda nao estava pronta para validar o dano.', 'Armas' },
    weapon_damage_transition_window = { 'Dano durante transicao de arma', 'O sinal ocorreu dentro de uma transicao recente autorizada.', 'Armas' },
    weapon_damage_payload_invalid = { 'Evento de dano invalido', 'O payload do evento de dano nao passou pela validacao tecnica.', 'Armas' },
    weapon_damage_rate_suspect = { 'Cadencia anormal de dano', 'A taxa de eventos de dano excedeu o perfil configurado.', 'Armas' },
    weapon_damage_death_state_incompatible = { 'Dano em estado de morte incompatível', 'O servidor recebeu dano originado por jogador cujo estado canonico nao era alive.', 'Armas' },
    entity_spawn_rate_suspect = { 'Spawn anormal de entidades', 'Entidades de rede foram criadas acima do limite de observacao.', 'Entidades' },
    entity_model_blocked = { 'Modelo de entidade bloqueado', 'Foi criado um modelo presente na lista defensiva do servidor.', 'Entidades' },
    movement_teleport_suspect = { 'Possivel teleporte', 'O deslocamento observado excedeu o esperado para o contexto.', 'Movimento' },
    movement_noclip_suspect = { 'Possivel noclip', 'O deslocamento observado nao corresponde ao movimento esperado.', 'Movimento' },
    movement_vehicle_reentry_distance = { 'Retorno distante ao veiculo', 'O jogador voltou a um veiculo a uma distancia incomum.', 'Movimento' },
    camera_freecam_suspect = { 'Possivel freecam', 'A camera ficou distante do ped fora de um fluxo autorizado.', 'Camera' },
    camera_spectate_unapproved = { 'Spectate nao autorizado', 'O cliente reportou modo spectator sem autorizacao administrativa.', 'Camera' },
    player_model_change_unapproved = { 'Troca de modelo nao autorizada', 'O modelo do jogador mudou fora de um lifecycle permitido.', 'Estado do jogador' },
    player_godmode_suspect = { 'Possivel invencibilidade', 'Multiplas observacoes indicam estado de dano incompatível.', 'Estado do jogador' },
    player_invisible_suspect = { 'Possivel invisibilidade', 'O jogador permaneceu invisivel fora de um fluxo autorizado.', 'Estado do jogador' },
    event_explosion_rate_suspect = { 'Spam anormal de explosoes', 'Eventos de explosao excederam a janela configurada.', 'Eventos de rede' },
    event_explosion_anomaly_suspect = { 'Explosao com contexto anormal', 'Metadados ou distancia da explosao ficaram fora dos limites.', 'Eventos de rede' },
    event_clear_tasks_rate_suspect = { 'Interferencia repetida em peds', 'Eventos clear tasks excederam a frequencia esperada.', 'Eventos de rede' },
    event_remote_clear_tasks_suspect = { 'Interferencia remota em jogador', 'Clear tasks foi dirigido a outro jogador sem lease.', 'Eventos de rede' },
    event_tazer_rate_suspect = { 'Spam anormal de tazer', 'Eventos de tazer excederam a janela configurada.', 'Eventos de rede' },
    event_ptfx_rate_suspect = { 'Spam anormal de particulas', 'O jogador enviou efeitos de rede em frequencia acima do esperado.', 'Eventos de rede' },
    event_ptfx_anomaly_suspect = { 'Particula anormal ou remota', 'O efeito tinha escala anormal ou alvo remoto.', 'Eventos de rede' },
    event_projectile_rate_suspect = { 'Spam anormal de projeteis', 'Eventos de projetil excederam a janela configurada.', 'Eventos de rede' },
    projectile_weapon_unauthorized = { 'Projetil sem arma autorizada', 'O hash do projetil divergiu da arma equipada no inventario canonico.', 'Eventos de rede' },
    event_fire_rate_suspect = { 'Spam anormal de fogo', 'Eventos de fogo excederam a janela configurada.', 'Eventos de rede' },
    event_fire_remote_suspect = { 'Fogo remoto suspeito', 'Um alvo distante recebeu um evento de fogo de rede.', 'Eventos de rede' },
    event_remote_weapon_action_suspect = { 'Acao remota de arma', 'Uma arma foi alterada em outro jogador sem lease.', 'Eventos de rede' },
    event_damage_modifier_suspect = { 'Modificador de dano anormal', 'Modificadores server-side excederam os limites de observacao.', 'Eventos de rede' },
    aim_headshot_pattern_suspect = { 'Padrao estatistico de headshots', 'Janelas repetidas apresentaram proporcao anormal de headshots.', 'Mira' },
    crash_observed = { 'Jogador sofreu crash', 'A desconexao foi classificada conservadoramente como crash.', 'Crash e estabilidade' },
    crash_cluster_suspect = { 'Varios jogadores crasharam em sequencia', 'Dois ou mais crashes ocorreram dentro da janela de correlacao.', 'Crash e estabilidade' },
    client_resource_presence_missing = { 'Runtime client ausente', 'Um resource monitorado deixou de enviar telemetria de presenca.', 'Runtime client' },
    client_resource_stop_observed = { 'Parada de resource observada', 'O client informou a parada de um resource monitorado.', 'Runtime client' },
    canary_triggered = { 'Canario de seguranca acionado', 'Um endpoint inerte reservado para deteccao foi chamado.', 'Canarios' }
}

local function severityExplanation(severity)
    local messages = {
        info = 'Informativo; preserve o contexto sem presumir abuso.',
        low = 'Sinal fraco; requer contexto adicional.',
        medium = 'Sinal relevante; recomenda revisao manual.',
        high = 'Evidencia forte ou impacto alto; priorize a investigacao.',
        critical = 'Evidencia repetida ou impacto critico; investigue imediatamente.'
    }
    return messages[tostring(severity or '')] or messages.info
end

local function confidenceExplanation(confidence)
    local messages = {
        low = 'Baixa: depende de telemetria ou heuristica com falsos positivos conhecidos.',
        medium = 'Media: ha sinais repetidos, mas ainda exige validacao humana.',
        high = 'Alta: o servidor observou divergencia tecnica direta.',
        critical = 'Critica: multiplas evidencias independentes sustentam o sinal.'
    }
    return messages[tostring(confidence or '')] or messages.medium
end

function MZBan.DetectorCatalog.Get(code, severity, confidence)
    code = tostring(code or '')
    local definition = DEFINITIONS[code] or { code, 'Incidente de seguranca registrado pelo servidor.', 'Seguranca' }
    return {
        code = code,
        label = definition[1],
        short_description = definition[2],
        category_label = definition[3],
        severity_explanation = severityExplanation(severity),
        confidence_explanation = confidenceExplanation(confidence),
        mitigation_explanation = 'Observe only por padrao; mitigacoes defensivas sao registradas separadamente.',
        recommended_action = DEFAULT_ACTION
    }
end

function MZBan.DetectorCatalog.All()
    local out = {}
    for code in pairs(DEFINITIONS) do out[code] = MZBan.DetectorCatalog.Get(code) end
    return out
end

