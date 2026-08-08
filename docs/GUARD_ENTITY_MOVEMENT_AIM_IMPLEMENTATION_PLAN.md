# Plano de implementacao - Entity, Movement, Event e Aim Guard

Este documento define a implementacao das proximas protecoes do MZ Security. O objetivo inicial e observar, registrar e permitir investigacao pela Central de Alertas, sem kick, ban ou cancelamento automatico.

## 1. Decisoes fixas de seguranca

- `Config.Risk.AutoKick = false` e `Config.Risk.AutoBan = false` durante todo o primeiro ciclo.
- Todo detector novo inicia em `mode = 'observe'`.
- Nenhum relato exclusivamente client-side pode banir, remover ou cancelar uma acao.
- Toda entrada vinda do cliente e nao confiavel: validar tipo, tamanho, faixa, sessao, frequencia e motivo no servidor.
- Recursos legitimos recebem autorizacoes curtas e especificas; nao existe whitelist global para Staff.
- Incidentes ficam na Central de Alertas existente. Nao criar uma segunda NUI, banlist ou tabela SQL.
- Nenhuma migration ou `ALTER TABLE` automatico sera executado por estes lotes.
- Identifiers nao aparecem em notificacoes ou listas; acesso continua separado e auditado.

## 2. Referencias auditadas e regra de uso

Foram revisadas as copias locais de GoblinAC, Icarus Advanced Anticheat, Valkyrie e FIREAC. A analise detalhada, os arquivos centrais e a matriz de decisao estao em `docs/REFERENCE_ANTICHEATS_AUDIT.md`.

| Referencia | Licenca | Ideia util | Limite que o BanGuard deve evitar |
|---|---|---|---|
| GoblinAC | MIT | inventario/gateway de eventos e estado por jogador | chave no cliente nao autentica um cliente comprometido nem impede replay |
| Icarus | GPL-3.0 | modulos OneSync, eventos nativos e excecao temporaria | ban por regra isolada, bypass global e screenshot externo |
| Valkyrie | GPL-3.0 | server authority, entity lockdown, lifecycle e log | blacklist universal, health probing e permissao total |
| FIREAC | AGPL-3.0 | grace, amostras, cooldown e limites | punicao padrao, whitelist ampla e dependencia excessiva do cliente |

Estas referencias nao devem ser iniciadas como resources nem adicionadas como dependencias. A implementacao do MZ deve ser propria. Nao copiar funcoes, tabelas, listas ou NUI de projetos GPL/AGPL. Mesmo o codigo MIT nao deve ser importado sem uma decisao explicita de licenciamento e preservacao dos avisos.

Decisoes derivadas da auditoria:

- priorizar autoridade server-side e contratos de evento, nao nomes/chaves secretas no cliente;
- usar `entityCreating` para observacao preventiva e preparar migracao gradual para criacao server-side/entity lockdown;
- transformar excecoes genericas em leases curtas, consumiveis e contextualizadas;
- observar owner, alvo, distancia, bucket, modelo e frequencia nos eventos nativos;
- separar deteccao, prevencao reversivel e punicao; nenhum detector chama ban/kick diretamente;
- manter screenshot, OCR, AntiVPN, banlist paralela e telemetria externa fora deste ciclo;
- nao importar blacklists genericas de eventos, modelos ou armas; corrigir os contratos reais dos recursos MZ.

## 3. Modos operacionais

Todos os modulos novos devem expor o mesmo modelo:

| Estado | Configuracao | Comportamento |
|---|---|---|
| Desligado | `enabled = false` | Nao observa, nao registra e nao cancela |
| Observacao | `enabled = true`, `mode = 'observe'` | Registra/agrega incidentes e notifica Staff; nunca cancela |
| Protecao | `enabled = true`, `mode = 'enforce'` | Pode cancelar somente a acao server-side classificada como bloqueavel, se `runtimeValidated = true` e a trava especifica estiver ligada |

`mode = 'enforce'` nao significa kick ou ban. Punicao automatica continua dependendo separadamente de `Config.Risk.AutoKick` e `Config.Risk.AutoBan`. A primeira entrega deve permanecer assim:

```lua
Config.Risk.AutoKick = false
Config.Risk.AutoBan = false

Config.EntityGuard.mode = 'observe'
Config.EntityGuard.cancelHighConfidence = false
Config.EntityGuard.runtimeValidated = false

Config.MovementGuard.mode = 'observe'
Config.MovementGuard.runtimeValidated = false

Config.EventGuard.mode = 'observe'
Config.EventGuard.cancelHighConfidence = false
Config.EventGuard.runtimeValidated = false

Config.AimGuard.mode = 'observe'
Config.AimGuard.runtimeValidated = false
```

## 4. Arquitetura comum

### 4.1 Fontes de evidencia

Cada evidencia deve declarar uma origem:

- `server_event`: evento recebido diretamente pelo servidor;
- `server_state`: estado medido pelo servidor/OneSync;
- `client_telemetry`: relato do proprio cliente suspeito;
- `correlated`: conclusao produzida pela combinacao de duas ou mais fontes.

Confianca recomendada:

- `low`: um unico sinal client-side;
- `medium`: sinal client-side repetido ou sinal server-side ainda ambiguo;
- `high`: evento server-side incompatível com autoridade registrada;
- `critical`: repeticao de evidencias independentes de alta confianca.

Um incidente pode ter severidade alta para triagem sem autorizar punicao automatica. `riskScore` da Central e prioridade operacional; nao deve chamar `FlagPlayer` automaticamente durante staging.

### 4.2 Ciclo de vida do jogador

Ignorar ou rebaixar evidencias durante:

- conexao e carregamento do personagem;
- spawn, morte, revive e troca de personagem;
- troca de routing bucket;
- carregamento de colisao;
- troca legitima de skin;
- teleport, noclip ou spectate Staff autorizados;
- entrada/saida de interiores e instancias registradas.

Estado por `source` deve ser descartado em `playerDropped`. Todo uso posterior da source deve revalidar `citizenid`/license para evitar reuso de source.

### 4.3 Autorizacoes temporarias por capacidade

Expandir o contrato de `RegisterTrustedAction` para autorizacoes granulares, curtas e server-only:

- `entity.spawn.ped`
- `entity.spawn.vehicle`
- `entity.spawn.object`
- `movement.teleport`
- `movement.noclip.staff`
- `camera.spectate.staff`
- `player.model.change`
- `player.invincibility`
- `event.clear_tasks.remote`
- `weapon.give.remote`
- `weapon.remove.remote`
- `event.explosion.scripted`

Cada autorizacao deve conter `source`, capacidade, recurso emissor, inicio, expiracao, identificador de correlacao e contexto minimo. Quando aplicavel, adicionar alvo, modelo, quantidade, origem/destino ou routing bucket. Regras obrigatorias:

- nenhum curinga (`*`) e aceito;
- o emissor e obtido no servidor por `GetInvokingResource()` e precisa estar autorizado para a capacidade;
- TTL possui teto global e teto menor por capacidade;
- a lease e de uso unico ou possui `remainingUses` limitado;
- o evento correspondente consome a lease; apenas consultar nao renova sua validade;
- `playerDropped`, `onResourceStop` e troca de identidade revogam o estado relacionado;
- emissao, consumo, expiracao e tentativa invalida entram em auditoria com dados limitados;
- o cliente nunca cria, amplia, transfere ou renova sua propria autorizacao.

### 4.4 Contrato de incidentes

Generalizar o armazenamento atual, hoje orientado a armas, sem quebrar os incidentes existentes. Campos comuns:

```text
id, category, code, source, citizenid, playerName
status, severity, confidence, riskScore, count
firstSeenAt, lastSeenAt, aggregateKey
evidence[], notes[], identifiers, online
```

Campos especificos ficam dentro de `evidence.data`, com limites de profundidade, quantidade e tamanho. Nunca aceitar uma tabela arbitraria do cliente diretamente no armazenamento.

Codigos iniciais:

```text
entity_spawn_unapproved
entity_model_blocked
entity_spawn_rate_suspect
entity_owner_unresolved
movement_teleport_suspect
movement_noclip_suspect
movement_vehicle_reentry_distance
camera_freecam_suspect
camera_spectate_unapproved
player_model_change_unapproved
player_godmode_suspect
event_explosion_rate_suspect
event_clear_tasks_rate_suspect
event_tazer_rate_suspect
aim_accuracy_outlier
aim_snap_pattern_suspect
aim_headshot_pattern_suspect
```

### 4.5 Registro de contratos de eventos

O aprendizado util do GoblinAC e centralizar o inventario, nao esconder o nome do evento. Criar um registro server-side para eventos sensiveis dos recursos MZ. Cada contrato deve declarar:

- schema e limite de tamanho dos argumentos;
- estado oficial exigido do personagem/jogador;
- permissao/capacidade e recurso responsavel;
- ownership do alvo e distancia maxima quando aplicavel;
- limites de quantidade, valor e frequencia;
- chave de idempotencia ou sequencia para operacoes economicas;
- politica para repeticao, payload invalido e falha de dependencia;
- codigo de auditoria e evidencia permitida.

Uma chave, token ou nome ofuscado recebido do cliente nao substitui essas regras. Eventos vulneraveis devem ser corrigidos no proprio handler. Blacklist de nomes conhecidos de outros frameworks nao protege um evento real do MZ.

### 4.6 Correlacao, saude e privacidade

- Manter uma timeline curta e limitada por jogador para correlacionar lease, spawn, owner, bucket, movimento, evento e dano.
- Nao somar score indefinidamente por copias do mesmo sinal; deduplicar por causa, janela e sujeito.
- Registrar `sensor_missing` e incompatibilidade de versao como saude do detector, nao como prova de cheat.
- Expor versao de configuracao, ultimo evento, descartes por rate limit, erros e tempo de processamento de cada modulo.
- Nao coletar screenshot, audio, OCR ou enviar evidencia a servico externo neste ciclo.
- Manter detalhes tecnicos sanitizados e com TTL; identifiers continuam em permissao separada.

## 5. Lote C - Entity Guard

### 5.1 Objetivo

Observar spawn de peds, veiculos e objetos, identificar proprietario e contexto, agregar abuso e preparar bloqueio preventivo futuro.

### 5.2 Implementacao

- Criar `mz_banguard/server/entity_guard.lua`.
- Escutar `entityCreating` para capturar a tentativa antes da replicacao.
- Usar `entityCreated` somente para confirmacao, enriquecimento e reconciliacao.
- Capturar tipo, modelo, owner atual/primeiro owner, population type, coordenadas, routing bucket e horario monotônico.
- Manter janelas separadas por identidade, tipo e bucket.
- Consultar autorizacao de spawn emitida pelo recurso legitimo.
- Consumir a lease apenas quando tipo, modelo, quantidade, jogador e bucket coincidirem.
- Permitir quotas diferentes para ped, veiculo e objeto.
- Separar burst curto de volume sustentado e manter reconciliacao de owner com tentativas limitadas.
- Registrar owner ausente como telemetria; nunca atribuir culpa a uma source por aproximacao.
- Nao alegar qual resource criou uma entidade apenas pelo evento nativo; atribuir recurso somente quando houver lease/correlacao server-side.
- Listas de modelos sao configuracao do servidor, revisadas para os recursos realmente instalados.
- Em `observe`, nunca chamar `CancelEvent()` nem `DeleteEntity()`.
- Em futuro `enforce`, cancelar somente em `entityCreating`, com alta confianca e as tres travas de protecao ativas.
- Criar uma matriz dos resources que ainda fazem spawn client-side e migrar um por vez para criacao server-side.
- Executar piloto de `sv_entityLockdown` em ambiente/canario separado; nao ativar globalmente antes de a matriz ficar compativel.

### 5.3 Configuracao proposta

```lua
Config.EntityGuard = {
    enabled = true,
    mode = 'observe',
    cancelHighConfidence = false,
    runtimeValidated = false,

    windowMs = 10000,
    aggregateWindowMs = 15000,
    duplicateCooldownMs = 1000,
    notificationCooldownMs = 10000,

    limits = {
        ped = 6,
        vehicle = 12,
        object = 20
    },

    blockedModels = {
        ped = {},
        vehicle = {},
        object = {}
    },

    leaseGraceMs = 1500,
    unresolvedOwnerSeverity = 'info'
}
```

Os valores sao pontos de partida para staging, nao limites finais de producao.

### 5.4 Criterios de aceite

- Spawn legitimo de garagem, concessionaria, job e script de mapa nao gera alerta indevido.
- Um jogador criando varios NPCs gera um unico incidente agregado com contagem e evidencias limitadas.
- Veiculos e objetos nao compartilham quota.
- Routing buckets diferentes nao contaminam a mesma janela.
- Owner nao resolvido nao acusa o jogador mais proximo.
- Reinicio do resource limpa contadores sem apagar ou modificar banco.
- `observe` nao cancela nem apaga nenhuma entidade.
- Repeticao/migracao de owner nao cria duas acusacoes para a mesma entidade.
- Lease com modelo, bucket ou quantidade divergente nao silencia o alerta.

## 6. Lote D - Movement e Player State Guard

### 6.1 Telemetria client-side

Criar `mz_banguard/client/security_telemetry.lua` com amostragem moderada e sem loops a cada frame. O cliente pode relatar somente codigos predefinidos. O servidor deve:

- confirmar sessao pronta;
- validar tipos, tamanhos e faixas numericas;
- aplicar limite por janela e cooldown por codigo;
- ignorar detalhes extras nao previstos;
- marcar a origem como `client_telemetry`;
- correlacionar com coordenadas/estado observados no servidor quando possivel.

### 6.2 Detectores

**Teleport e saida/retorno de veiculo**

- Manter amostras server-side de coordenadas, veiculo, assento, velocidade e bucket.
- Calcular distancia em funcao do tempo, velocidade e tipo de movimento.
- Suspender durante spawn, teleport autorizado, troca de bucket e transicoes registradas.
- `movement_vehicle_reentry_distance` exige sequencia temporal: estava no veiculo, saiu e reapareceu/reentrou a distancia incompatível.

**Noclip**

- Combinar deslocamento, altura, colisao, queda/ragdoll/parachute, veiculo e autorizacao Staff.
- Relato client-side isolado permanece `low`.
- Repeticao mais deslocamento server-side incompatível pode subir para `medium/high`.

**Freecam e spectate**

- Medir distancia câmera/ped e modo spectate no cliente.
- Excluir NUI, camera cinematica, cutscene e `camera.spectate.staff`.
- Nunca classificar freecam isolado acima de `medium`.

**Troca de skin/ped**

- O servidor registra o modelo esperado depois de uma mudanca autorizada.
- Mudanca sem `player.model.change` gera incidente, mesmo que o novo modelo nao esteja em blacklist.
- Blacklist aumenta severidade, mas nao substitui a autoridade do modelo esperado.
- Respawn e troca de personagem renovam o modelo-base de forma controlada.

**Godmode/invisibilidade**

- Combinar invencibilidade, capacidade de receber dano, proofs, visibilidade e alpha.
- Excluir morte, revive, spawn, cutscene, ragdoll e `player.invincibility` autorizado.
- Nao causar dano artificial no jogador para testar godmode.
- Sinal local repetido continua sendo evidencia para investigacao, nao prova punitiva.

### 6.3 Criterios de aceite

- Teleports Staff e de recursos autorizados nao geram incidente.
- Spectate/noclip Staff nao concede bypass ao alvo observado.
- Elevador, interior, respawn, queda, paraquedas e alta latencia sao cobertos no teste.
- Mudanca legitima de roupa/skin atualiza o modelo esperado uma unica vez.
- Executor nao consegue escolher codigo, severidade, score ou acao do incidente.
- Flood do endpoint client-side e descartado sem inundar Central ou logs.

## 7. Lote E - Event Guard

### 7.1 Eventos nativos

Adicionar observadores separados para:

- `explosionEvent` por tipo, distancia, owner e frequencia;
- `clearPedTasksEvent` por emissor, alvo e frequencia;
- repeticao de tazer dentro de `weaponDamageEvent` sem duplicar o Weapon Guard;
- `ptFxEvent` por owner do alvo, efeito, escala e frequencia;
- `startProjectileEvent` por arma, cadencia, origem e contexto de veiculo;
- `fireEvent` por alvo, owner e distancia;
- `giveWeaponEvent`, `removeWeaponEvent` e `removeAllWeaponsEvent` por ownership e lease;
- modificadores de dano/defesa observados no servidor, com limite oficial e sem media contaminavel como unica baseline;
- outros eventos nativos somente depois de validar a semantica no artifact usado em staging.

Nao registrar automaticamente nomes de uma blacklist generica como novos `RegisterNetEvent`. Eventos pertencentes ao MZ devem ser protegidos no proprio handler, revalidando permissao, estado oficial, alvo, quantidade e rate limit.

`clearPedTasksEvent` contra o ped remoto de outro jogador deve ganhar um codigo proprio de acao remota. No primeiro ciclo apenas alerta. Um bloqueio futuro pode ser elegivel por ser reversivel e server-side, mas exige lease para usos legitimos e validacao do artifact.

### 7.2 Criterios de aceite

- Explosoes legitimas de armas autorizadas nao geram falso positivo recorrente.
- Spam agrega por identidade e tipo, sem log por evento.
- `clearPedTasksEvent` administrativo ou de gameplay autorizado possui capacidade especifica.
- Particulas, projeteis, fogo e give/remove weapon exibem owner, alvo e motivo explicavel.
- Em `observe`, nenhum evento e cancelado.
- Qualquer cancelamento futuro exige teste do artifact e trava especifica.

## 8. Lote F - Aim Analytics

O FIREAC gratuito nao possui Anti-Aimbot. Este modulo deve ser construido como analise estatistica, nunca como detector de uma unica regra.

### 8.1 Sinais permitidos

- quantidade de disparos e acertos por arma;
- proporcao de headshots em uma amostra minima;
- sequencia de alvos e tempo entre aquisicao/acerto;
- distancia e cadencia compatíveis com a arma oficial;
- mudanca angular/snap informada por telemetria, sempre marcada como client-side;
- repeticao do padrao em varias sessoes ou janelas.

### 8.2 Regras

- Nao criar incidente antes de um tamanho minimo de amostra.
- Separar arma, distancia e contexto; shotgun, sniper e automaticas nao usam a mesma baseline.
- Separar latencia, alvo parado/movel, veiculo, sequencia de alvos e duracao da sessao.
- Nao tratar alta precisao ou headshot isolado como cheat.
- Nao usar uma unica geometria de camera, um unico tiro ou um limite universal como prova.
- Usar percentis/baseline do proprio servidor com versao e amostra conhecidas; outliers nao entram automaticamente na baseline seguinte.
- Aplicar decay entre janelas e exigir repeticao em janelas independentes antes de elevar a confianca.
- Nao capturar screenshot, audio ou dados externos neste lote.
- Manter apenas agregados necessarios, com TTL e limites.
- Aim Guard permanece permanentemente de observacao ate existir baseline real do servidor e revisao manual de falsos positivos.

### 8.3 Criterios de aceite

- Jogador habilidoso em amostra curta nao cria alerta critico.
- Padroes repetidos agregam sem gerar um incidente por tiro.
- A Central mostra tamanho da amostra, arma, distancia e motivos da classificacao.
- Nenhuma estatistica de mira aciona `DropPlayer`, ban ou cancelamento de dano.

## 9. Central de Alertas

Alteracoes previstas:

- generalizar `VALID_CODES` e a chave de agregacao em `server/incidents.lua`;
- manter compatibilidade com os campos do Weapon Guard;
- adicionar categorias `entity`, `movement`, `camera`, `player_state`, `event` e `aim`;
- incluir filtros por categoria e confianca;
- apresentar origem da evidencia (`server_event`, `server_state`, `client_telemetry`, `correlated`);
- mostrar modo efetivo de cada modulo no resumo operacional;
- mostrar saude do sensor, versao da regra, quantidade descartada e ultimo evento recebido;
- mostrar uma timeline curta das evidencias correlacionadas e das leases emitidas/consumidas;
- permitir marcar falso positivo com causa legitima e resource envolvido, sem alterar limite automaticamente;
- manter reconhecer, nota, falso positivo, resolver, spectate e goto;
- manter kick/ban automaticos desligados e fora do fluxo de triagem.

O menu nao deve exibir detalhes tecnicos recebidos do cliente sem sanitizacao server-side.

## 10. Estado atual e ordem revisada

### 10.1 Implementado na versao 1.3

- contrato generico de incidentes e Central com categorias;
- Weapon Guard em observacao;
- Security Leases v2 server-only, sem wildcard, com TTL, contexto, consumo, auditoria e revogacao;
- Event Contract Registry com schema, limites e protecao opcional contra replay;
- Entity Guard por modelo, bucket, primeiro/atual owner, burst, volume sustentado e reconciliacao;
- Movement/Player State minimo para teleporte, noclip, retorno ao veiculo, freecam, spectate, modelo, godmode e invisibilidade;
- Event Guard para explosao, clear tasks, tazer, PTFX, projeteis, fogo, give/remove weapon e modificadores;
- Aim Analytics por arma, distancia e latencia, exigindo duas janelas independentes qualificadas;
- timeline limitada de correlacao, heartbeat e saude dos detectores;
- status operacional, versao das regras e infraestrutura exibidos na Central;
- leases integradas aos teleports/spawn de veiculo Staff e ao spawn/modelo do `mz_core`;
- `AutoKick = false`, `AutoBan = false` e novos modulos em `observe`.

Nenhum desses modulos chama `CancelEvent`, apaga entidade, kicka ou bane.

### 10.2 Pendencias para staging e protecao futura

O detalhamento executavel destas pendencias foi separado em
`BANGUARD_PHASE_2_HARDENING_PLAN.md` para ser retomado depois da baseline 1.3.

1. Executar staging/red-team sem comandos e coletar baseline/falsos positivos por gameplay.
2. Migrar, um resource por vez, os fluxos client-side listados em `RESOURCE_SECURITY_INTEGRATION_MATRIX.md`.
3. Registrar contratos nos handlers reais de economia, inventario, garagem, skin e jobs; o registro sozinho nao intercepta eventos.
4. Correlacionar Movement/Player State com as transicoes server-side que forem migradas.
5. Testar entity lockdown apenas em canario depois da matriz de spawns estar compativel.
6. Calibrar Aim Analytics somente com baseline real; manter permanentemente sem enforce automatico.
7. Avaliar cancelamentos preventivos reversiveis, um detector por mudanca, mantendo auto kick/ban desligados.
8. Considerar qualquer politica de kick/ban automatico apenas em projeto separado e com aprovacao formal.

## 11. Arquivos da entrega

Modulos implementados:

```text
mz_banguard/server/security_leases.lua
mz_banguard/server/event_contracts.lua
mz_banguard/server/security_correlation.lua
mz_banguard/server/detector_health.lua
mz_banguard/server/entity_guard.lua
mz_banguard/server/telemetry_guard.lua
mz_banguard/server/event_guard.lua
mz_banguard/server/aim_guard.lua
mz_banguard/client/security_telemetry.lua
mz_banguard/tests/security_leases_harness.lua
mz_banguard/tests/security_lease_integration_contract_harness.lua
mz_banguard/tests/event_contracts_harness.lua
mz_banguard/tests/detector_health_harness.lua
mz_banguard/tests/security_observers_harness.lua
```

Integracoes e contratos atualizados:

```text
mz_banguard/fxmanifest.lua
mz_banguard/config.lua
mz_banguard/server/incidents.lua
mz_banguard/server/alerts_api.lua
mz_admin/client/security_alerts.lua
mz_admin/server/main.lua
mz_admin/server/security.lua
mz_admin/tests/security_alert_center_contract_harness.lua
mz_core/server/main.lua
```

Nao criar dependencia nem iniciar qualquer resource dentro de `ref/`.

## 12. Verificacao por lote

Cada lote deve entregar:

- teste de sintaxe Lua;
- harness unitario dos limites, janelas, agregacao e limpeza;
- teste de contrato garantindo que o cliente nao escolhe severidade/acao;
- teste de `playerDropped` e reuso de source;
- teste de permissao/autorizacao temporaria;
- teste de lease expirada, divergente, reutilizada, emitida por resource indevido e revogada em stop/drop;
- teste de replay/idempotencia e payload fora do schema nos eventos sensiveis;
- teste de ataque sem comandos, exercitando diretamente a fronteira de rede/evento usada pelo cliente;
- teste de owner ausente/migrado, bucket divergente e burst legitimo de entidades;
- teste de Central indisponivel sem quebrar menu Staff;
- checklist manual em staging com `observe` confirmado;
- medicao de volume, duplicatas e falsos positivos;
- rollback por uma unica chave `enabled = false`.

Antes de concluir qualquer lote, executar tambem os testes existentes de arma, risco e Central para evitar regressao.

## 13. Criterio para habilitar protecao futura

Um detector so pode sair de `observe` quando todos os itens abaixo estiverem aprovados:

- comportamento do evento/nativa confirmado no artifact de producao;
- pelo menos um ciclo representativo de dados de staging;
- metrica de falso positivo, volume e custo por tick registrada para a versao da regra;
- falso positivo revisado por tipo de gameplay;
- recursos legitimos integrados por capacidade, sem whitelist global;
- incidente possui evidencia server-side de alta confianca;
- cancelamento e reversivel por configuracao;
- teste prova que `AutoKick` e `AutoBan` continuam desligados;
- mudanca revisada e implantada separadamente.

Aim Analytics e sinais exclusivamente client-side nao devem habilitar cancelamento ou punicao automatica.

## 14. Definicao de pronto do projeto

- Peds, veiculos e objetos suspeitos aparecem agregados na Central.
- Godmode, invisibilidade, freecam, spectate, noclip, teleporte e troca de skin geram telemetria investigavel com origem e confianca.
- Saida/retorno de veiculo a distancia possui sequencia de evidencias legivel.
- Explosao, tazer e clear tasks possuem rate guard sem spam de logs.
- Aim Analytics apresenta apenas padroes estatisticos explicaveis.
- Toda acao legitima importante tem autorizacao curta e especifica.
- Eventos sensiveis do MZ possuem contrato server-side e teste de replay/ownership.
- Resources de spawn estao inventariados e a viabilidade de entity lockdown esta documentada.
- Saude/versao dos detectores aparece sem transformar sensor ausente em acusacao.
- Nenhum modulo novo bane, kicka, cancela ou apaga durante o primeiro ciclo.
- Central, auditoria, privacidade, TTL e limites continuam funcionando.
- Desabilitar um modulo interrompe sua observacao sem afetar os demais.
