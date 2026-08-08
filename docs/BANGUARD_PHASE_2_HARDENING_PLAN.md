# BanGuard - Plano de hardening da Fase 2

Este documento organiza as melhorias do BanGuard para reduzir falsos positivos e
aumentar a confianca dos alertas. A base tecnica dos lotes 1 a 6 foi implantada
na versao 1.4 em modo somente-alerta. O Lote 0 continua sendo uma atividade de
staging e o Lote 7 nao foi ativado porque exige aprovacao separada.

## Estado da implantacao 1.4

| Lote | Estado | Entrega |
|---:|---|---|
| 0 | pendente em staging | baseline, classificacao de falsos positivos e custo runtime |
| 1 | implantado | `SecurityLifecycle` server-side, confirmacao e cleanup |
| 2 | implantado, mapeamento a validar | classificacao de population type e quotas por classe |
| 3 | parcial controlado | Core, Creator, Clothing, Tatto e Houses integrados |
| 4 | parcial controlado | contratos nos handlers de lifecycle; economia/inventario permanecem para auditoria dedicada |
| 5 | implantado | revisao oficial, cadencia por arma e contexto do alvo |
| 6 | implantado tecnicamente | timeline/evidencia; calibracao depende do Lote 0 |
| 7 | nao iniciado | nenhuma prevencao, kick ou ban automatico ativado |

## 1. Politica fixa

- `Config.Risk.AutoKick = false` e `Config.Risk.AutoBan = false` durante toda a fase.
- Todos os detectores permanecem em `mode = 'observe'`.
- Sinal exclusivamente client-side nunca autoriza punicao ou bloqueio.
- Ausencia de heartbeat e tratada como saude do sensor, nao como cheat.
- Network owner nao e prova isolada de que o jogador criou uma entidade.
- Nao liberar resources inteiros, Staff ou `mz_settings` por whitelist global.
- Toda excecao legitima usa lease server-only, curta, consumivel e contextual.
- Aim Analytics permanece somente informativa, inclusive depois do staging.
- Nenhum codigo de referencia em `ref/` sera copiado ou iniciado como dependencia.

## 2. Estado de partida

A versao 1.3 ja possui Weapon, Entity, Movement, Player State, Event e Aim Guards,
Central de Alertas, correlacao, detector health, Event Contract Registry e Security
Leases v2. `mz_admin` e `mz_core` ja emitem leases para os fluxos revisados.

Problemas conhecidos que motivam esta fase:

- populacao ambiente pode ser atribuida pelo OneSync ao cliente mais proximo;
- uma janela fixa de spawn pode terminar antes de colisao/aparencia estabilizarem;
- resources de skin, interiores, veiculos e objetos ainda nao emitem leases;
- o Event Contract Registry ainda precisa ser chamado dentro dos handlers reais;
- limites precisam de baseline representativa da cidade antes de calibracao;
- um alerta isolado ainda pode ter contexto insuficiente para alta confianca.

## 3. Ordem de execucao

| Ordem | Lote | Dependencia | Resultado esperado |
|---:|---|---|---|
| 0 | Baseline 1.3 | servidor atual | exemplos reais e taxa de falso positivo |
| 1 | Lifecycle/Spawn Session | `mz_core` | spawn sem alertas indevidos e sem bypass amplo |
| 2 | Entity Classification | baseline + lifecycle | ambiente separado de mission/scripted |
| 3 | Integracao de leases | lotes 1 e 2 | fluxos legitimos reconhecidos individualmente |
| 4 | Event Contracts reais | inventario de handlers | payload/replay/ownership validados na origem |
| 5 | Weapon Guard v2 | autoridade do `mz_core` | dano correlacionado com estado oficial |
| 6 | Correlacao e calibracao | dados dos lotes anteriores | alertas explicaveis e menos duplicados |
| 7 | Prevencao canario | aprovacao separada | bloqueio reversivel de poucas acoes, sem punir player |

Nao iniciar o Lote 7 junto com qualquer outro lote.

## 4. Lote 0 - Baseline da versao 1.3

### Coleta

Executar pelo menos um ciclo representativo em staging contendo:

- login, respawn, morte/revive e troca de personagem;
- `mz_creator`, roupas e tatuagens;
- interiores, casas, elevadores, garagem e concessionaria;
- areas vazias e areas com alta densidade de NPC/trafego;
- teleports, noclip e spectate Staff;
- combate com cada classe de arma usada pelo servidor;
- routing buckets e instancias;
- testes controlados sem comandos para NPC, veiculo, evento remoto e mira.

Para cada incidente registrar: codigo, `population type`, modelo, primeiro owner,
owner atual, bucket, burst, janela, gameplay, resource envolvido, latencia e se foi
verdadeiro ou falso positivo.

### Saida obrigatoria

- tabela de volume normal por categoria;
- exemplos confirmados de falso positivo;
- exemplos controlados de ataque detectado;
- custo aproximado dos detectores em horario representativo;
- nenhuma alteracao automatica de limite baseada apenas em uma amostra.

## 5. Lote 1 - Lifecycle e Spawn Session

### Objetivo

Substituir a tolerancia baseada somente em 20 segundos por uma sessao server-side
com estado esperado, escopo e teto de tempo.

### Contrato proposto

O servidor inicia uma sessao com:

```text
source, citizenid, sessionId, kind, issuer
expectedModel, destination, bucket
startedAt, expiresAt, allowedTransitions
```

Tipos iniciais: `character_spawn`, `respawn`, `character_switch`, `appearance_edit`,
`interior_transition` e `staff_teleport`.

Regras:

- somente resource server-side autorizado inicia a sessao;
- TTL possui teto absoluto e nao e renovado pelo cliente;
- o cliente pode sinalizar carregamento concluido, mas o servidor confirma modelo,
  coordenadas, bucket e estabilidade antes de encerrar;
- expiracao encerra a tolerancia mesmo se o cliente nunca responder;
- cada detector consulta apenas as transicoes relacionadas ao seu escopo;
- spawn nao concede passe para eventos, entidades, armas ou dano;
- troca de CitizenID, drop e stop do emissor revogam a sessao;
- inicio, confirmacao, expiracao e divergencia aparecem na timeline de correlacao.

### Criterios de aceite

- spawn lento nao gera freecam/modelo/godmode/teleporte indevido;
- modelo ou destino diferente do esperado nao e silenciado;
- cliente nao amplia TTL ou `allowedTransitions`;
- sessao de appearance nao autoriza teleport;
- sessao expirada nao pode ser reutilizada;
- reconexao/source reutilizada nao herda estado anterior.

## 6. Lote 2 - Entity Classification

### Objetivo

Diferenciar populacao criada pelo motor do GTA de entidade mission/scripted sem
tratar ownership de rede como autoria comprovada.

### Implementacao

- validar no artifact de staging os valores reais de `GetEntityPopulationType`;
- manter nomes legiveis e a versao do mapeamento na evidencia;
- separar quotas para `ambient`, `scenario`, `mission/scripted` e `unknown`;
- contar ped, veiculo e objeto em janelas independentes;
- aplicar grace de streaming somente a ambiente/scenario durante spawn/transicao;
- manter mission/scripted sem lease sob limites curtos e rigorosos;
- elevar confianca quando houver burst, modelos repetidos, lease ausente, primeiro
  owner consistente e repeticao sustentada;
- manter modelo bloqueado como sinal separado;
- owner ausente ou migrado continua sendo telemetria, nao atribuicao aproximada;
- exibir na Central tipo de populacao, classificacao, primeiro owner e owner atual;
- nao emitir lease para `mz_settings`: ele ajusta densidade, mas nao chama `CreatePed`.

### Criterios de aceite

- caminhar por area populada nao cria incidente de alta confianca;
- streaming apos spawn/teleport nao acusa o player;
- burst controlado de peds mission/scripted sem lease gera incidente agregado;
- tentativa de variar modelo nao escapa da quota sustentada;
- buckets nao compartilham contadores;
- veiculos de trafego e veiculos criados por script ficam em classes distintas;
- nenhum ped/veiculo/objeto e apagado em `observe`.

## 7. Lote 3 - Integracao gradual de leases

Usar `RESOURCE_SECURITY_INTEGRATION_MATRIX.md` como inventario. Migrar apenas um
fluxo por alteracao e liberar o emissor somente depois do teste.

| Grupo | Resources iniciais | Capacidades esperadas |
|---|---|---|
| Aparencia | `mz_creator`, `mz_clothing`, `mz_tatto` | modelo e invencibilidade temporaria |
| Interiores | `mz_doors`, `mz_houses`, `mz_interiors`, `mz_props` | teleport e, quando necessario, objeto |
| Veiculos | `mz_core`, `mz_vehicles` | spawn de veiculo com modelo/bucket/quantidade |
| Objetos | `mz_furniture`, `mz_phone`, `mz_progress`, `mz_target`, `mz_world_editor` | objeto de rede somente quando comprovadamente necessario |

Antes de emitir lease, o handler servidor valida permissao, estado, ownership,
distancia, bucket e limites. Objetos puramente locais nao precisam de lease de
entidade de rede.

Teste obrigatorio por integracao:

- fluxo oficial funciona sem alerta indevido;
- chamada direta do cliente nao emite lease;
- contexto/modelo/alvo divergente nao consome a lease;
- segunda utilizacao excedente volta a ser observada;
- stop do resource revoga suas leases;
- nenhum emissor adicional permanece no config sem consumer implementado.

## 8. Lote 4 - Event Contracts nos handlers reais

O registry nao intercepta um evento sozinho. Cada handler sensivel precisa chamar
o contrato antes de qualquer mutacao.

Inventariar e priorizar:

- dinheiro e contas;
- inventario, uso e transferencia de itens;
- equipar, guardar, dar e remover armas;
- garagem, compra e spawn de veiculos;
- criacao/aparencia;
- empregos, organizacoes e recompensas;
- acoes Staff e qualquer evento com alvo remoto.

Cada contrato declara schema, estado oficial, permissao, ownership, distancia,
quantidade, rate limit, chave de idempotencia/replay e motivo de auditoria. A
validacao ocorre antes de banco, inventario, native ou `TriggerClientEvent` de
sucesso.

Criterios de aceite:

- payload extra, tipo incorreto e valor fora de faixa falham fechados;
- replay nao repete dinheiro/item/arma;
- alvo remoto exige ownership/permissao explicitos;
- falha de dependencia nao executa mutacao parcial;
- contrato rejeitado gera auditoria limitada, sem flood da Central;
- caminho legitimo possui teste positivo e testes negativos.

## 9. Lote 5 - Weapon Guard v2

O `mz_core` continua sendo a fonte oficial; o BanGuard apenas confere e correlaciona.

Melhorias:

- expor snapshot server-side minimo da arma equipada e geracao da transicao;
- correlacionar `weaponDamageEvent` com arma oficial e janela de equipagem;
- manter taxas diferentes por classe/arma, nunca uma cadencia universal;
- observar distancia, tipo/owner do alvo, componente atingido e dano informado;
- detectar give/remove remoto sem capacidade especifica;
- registrar divergencia de municao apenas como evidencia complementar enquanto
  nao houver autoridade server-side suficiente;
- separar dano invalido, cadencia, hash divergente e transicao em codigos claros;
- Aim Analytics usa os acertos validados, mas nunca decide punicao.

Criterios de aceite:

- troca legitima de arma nao gera divergencia durante a janela oficial;
- hash diferente da arma equipada gera alerta agregado;
- flood de dano respeita limite e memoria;
- latencia e arma automatica nao sao tratadas como a mesma cadencia;
- BanGuard nao concede/remove arma e nao substitui a autoridade do Core;
- dano nao e cancelado durante a Fase 2.

## 10. Lote 6 - Correlacao, confianca e calibracao

Criar regras explicaveis, sem transformar a soma em autoban. Exemplos:

```text
mission/scripted + burst + lease ausente + primeiro owner consistente
  => entity spawn de alta confianca

spawn session ativa + modelo/destino/bucket esperados
  => transicao legitima, registrada como saude/correlacao

arma divergente + cadencia anormal + give remoto sem lease
  => incidente correlacionado para revisao manual
```

Regras:

- sinais derivados da mesma causa nao somam como evidencias independentes;
- client telemetry isolada permanece low/medium;
- duas janelas independentes sao exigidas para Aim Analytics;
- cada regra mostra versao, entradas, exclusoes e motivo da confianca;
- falso positivo e classificado por gameplay/resource, sem ajuste automatico;
- limites finais sao aprovados por percentile/baseline, nao por intuicao.

## 11. Lote 7 - Prevencao canario futura

Este lote exige solicitacao e aprovacao separadas. Nao inclui autokick ou autoban.

Primeiros candidatos, depois de todos os criterios anteriores:

- cancelar em `entityCreating` apenas entidade mission/scripted de alta confianca;
- negar no proprio handler evento sensivel com schema/replay/ownership invalido;
- impedir give/remove weapon remoto sem autoridade server-side.

Travas obrigatorias:

```text
enabled = true
mode = enforce
runtimeValidated = true
cancelHighConfidence = true
```

Uma unica trava falsa mantem o detector em observacao. Rollout por detector,
bucket/canario e janela definida, com rollback por configuracao e sem delete tardio.

## 12. Testes e evidencias

Cada lote entrega:

- sintaxe Lua e `git diff --check`;
- harness unitario e contrato de integracao;
- teste de source/CitizenID reutilizado;
- payload invalido, flood, replay e cleanup;
- teste legitimo e ataque controlado sem comandos;
- Central indisponivel sem quebrar gameplay;
- comparacao de volume antes/depois;
- registro de falsos positivos;
- confirmacao estatica e runtime de `AutoKick/AutoBan = false`;
- rollback exercitado.

O checklist operacional continua em `SECURITY_OBSERVERS_STAGING_CHECKLIST.md`.

## 13. Arquivos previstos

Arquivos novos ou modulos dedicados podem incluir:

```text
mz_banguard/server/security_lifecycle.lua
mz_banguard/server/entity_classification.lua
mz_banguard/tests/security_lifecycle_harness.lua
mz_banguard/tests/entity_classification_harness.lua
mz_banguard/tests/weapon_guard_v2_harness.lua
```

Arquivos provaveis de integracao:

```text
mz_banguard/config.lua
mz_banguard/fxmanifest.lua
mz_banguard/server/security_leases.lua
mz_banguard/server/entity_guard.lua
mz_banguard/server/telemetry_guard.lua
mz_banguard/server/event_contracts.lua
mz_banguard/server/weapon_guard.lua
mz_banguard/server/incidents.lua
mz_admin/client/security_alerts.lua
mz_core/server/main.lua
resources listados na matriz, um por alteracao
```

Os nomes sao propostos; a auditoria do codigo atual deve confirmar a menor mudanca
antes de criar novos modulos.

## 14. Definicao de pronto

- spawn e troca de personagem legitimos nao geram alertas recorrentes;
- NPCs/trafego ambientes nao sao atribuidos como cheat apenas por ownership;
- burst de entidade mission/scripted sem lease continua detectado;
- resources legitimos usam leases especificas e testadas;
- eventos sensiveis validam contrato antes da mutacao;
- arma usada no dano corresponde ao estado oficial do Core ou gera evidencia;
- alertas correlacionados explicam por que receberam a confianca apresentada;
- saude, memoria e volume dos detectores ficam dentro da baseline aprovada;
- nenhum lote ativa autokick ou autoban;
- prevencao, se aprovada depois, e canario, reversivel e separada de punicao.

## 15. Como retomar

Ao voltar para esta tarefa, iniciar pelo Lote 0 e anexar exemplos reais dos alertas
de spawn e NPC ambiente. Depois implementar somente o Lote 1, executar sua regressao
e validar em staging antes de iniciar Entity Classification.
