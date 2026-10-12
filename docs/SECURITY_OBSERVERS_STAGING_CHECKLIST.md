# Checklist de staging - observadores de seguranca

## Politica obrigatoria

Confirmar antes de iniciar os testes:

```lua
Config.Risk.AutoKick = false
Config.Risk.AutoBan = false
Config.WeaponGuard.mode = 'observe'
Config.EntityGuard.mode = 'observe'
Config.MovementGuard.mode = 'observe'
Config.PlayerStateGuard.mode = 'observe'
Config.EventGuard.mode = 'observe'
Config.AimGuard.mode = 'observe'
```

Entity Guard e Weapon Guard possuem caminho de mitigacao cercado por modo, flag especifica e `runtimeValidated`; todas as travas permanecem desligadas por padrao. Movement, Player State, Event e Aim continuam detect-only. `ptFxEvent` e `startProjectileEvent` nao sao cancelados sem validacao especifica do artifact.

`Config.SecurityAlerts.notifyMinimumSeverity = 'medium'` faz sinais medium/high/critical enviarem popup para Staff autorizado durante staging. `info` e `low` permanecem apenas na Central. O cooldown evita uma notificacao por amostra.

## Observadores ativos

| Categoria | Verificacao minima | Origem/confianca inicial |
|---|---|---|
| Armas | Arma oficial equipada, hash e taxa de dano | servidor / alta |
| Entidades | Modelo, bucket, owner, lease, burst e volume sustentado de peds/veiculos/objetos | servidor / media-alta |
| Movimento | Salto de coordenadas server-side | servidor / media |
| Movimento | Teleporte, noclip e retorno ao veiculo a distancia | cliente validado / baixa-media |
| Camera | Freecam e spectate nao autorizado | cliente validado / baixa-media |
| Player | Troca de ped/modelo, godmode e invisibilidade | cliente validado / baixa-media |
| Eventos | Explosao, clear tasks, tazer, PTFX, projetil, fogo, arma remota e modificadores | servidor / media-alta |
| Mira | Headshots por arma/distancia/latencia em duas janelas qualificadas | servidor / media |
| Infraestrutura | Leases, contratos, correlacao, heartbeat e versao das regras | servidor / saude |

Sinal client-side pode ser ocultado ou adulterado por executor. Ele serve para investigacao e correlacao, nunca como prova unica.

## Preparacao

- [ ] Confirmar ordem: `mz_core`, `mz_menu`, `mz_banguard`, `mz_admin`.
- [ ] Confirmar que `mz_starter/cfg/resources.cfg` contem `ensure mz_banguard` antes de `ensure mz_admin`.
- [ ] Abrir a Central e confirmar politica `somente alertas`.
- [ ] Confirmar todos os modulos como `observe` no resumo.
- [ ] Confirmar `Cancelamento de dano`, `Autokick` e `Autoban` como desligados.
- [ ] Limpar/reconhecer incidentes antigos para separar o ciclo de teste.

## Entidades

- [ ] Spawn normal de garagem e concessionaria nao ultrapassa a quota.
- [ ] Spawn de mais de 6 NPCs em 10 segundos cria incidente agregado.
- [ ] Spawn de mais de 12 veiculos em 10 segundos cria incidente agregado.
- [ ] Spawn de mais de 20 objetos em 10 segundos cria incidente agregado.
- [ ] O incidente mostra tipo, modelo, quantidade, population type e bucket.
- [ ] Nenhum ped, veiculo ou objeto e apagado pelo Guard.

## Movimento e estado

- [ ] Teleport administrativo `/tp`, `/tpm`, `/goto` e `/bring` nao gera alerta durante a janela autorizada.
- [ ] Noclip administrativo nao gera godmode, invisibilidade, freecam ou noclip contra o Staff.
- [ ] Spectate administrativo nao gera alerta contra o Staff nem bypass no alvo.
- [ ] Movimento normal, queda, paraquedas, natacao e veiculo rapido nao geram alerta recorrente.
- [ ] Teleporte nao autorizado aparece como `movement_teleport_suspect`.
- [ ] Noclip repetido aparece como `movement_noclip_suspect`.
- [ ] Sair e retornar ao veiculo a mais de 80 metros dentro de 15 segundos gera sinal.
- [ ] Troca de modelo fora de spawn/troca de personagem gera sinal.
- [ ] Spawn, morte, revive e troca de personagem respeitam a janela de 20 segundos.
- [ ] Godmode e invisibilidade persistentes aparecem apos varias amostras, nunca na primeira leitura.

## Eventos e mira

- [ ] Oito explosoes ou menos em 10 segundos nao ultrapassam a quota default.
- [ ] Spam acima da quota agrega em um incidente, sem um log por explosao.
- [ ] `clearPedTasksEvent` contra varios alvos usa uma quota global por emissor.
- [ ] Tazer repetido acima da quota gera sinal sem cancelar dano.
- [ ] Menos de 12 acertos nao produz analise de mira.
- [ ] Headshots abaixo da proporcao configurada nao produzem incidente.
- [ ] Padrao acima da amostra aparece com acertos, headshots, proporcao, arma e janela.
- [ ] Nenhum sinal de mira cancela dano, kicka ou bane.

## Testes sem comandos

Permissao de comando nao protege um evento de rede vulneravel. Estes testes devem ser executados por harness controlado em staging, emitindo a mesma classe de entrada que chegaria do cliente, sem depender de `/comando` Staff e sem instalar um menu de cheat.

| Cenario controlado | Resultado esperado no estado atual | Criterio para o proximo lote |
|---|---|---|
| burst de peds/veiculos/objetos sem lease | incidente agregado, nada apagado | Entity Guard correlaciona modelo, bucket, owner e lease ausente |
| repeticao de evento MZ com payload alterado | handler real nao concede dinheiro/item/arma | Event Contract rejeita schema, estado, ownership ou replay e audita o motivo |
| `clearPedTasksEvent` contra outro jogador (P1) | alerta agregado, sem cancelamento | futura prevencao exige alvo remoto confirmado e ausencia de lease legitima |
| troca de ped/modelo sem fluxo de skin | alerta apos amostras | lease `player.model.change` permite somente a transicao prevista |
| freecam/spectate/noclip sem autorizacao | telemetria investigavel | correlacao server-side eleva confianca; sinal client-side isolado nunca pune |
| sair e reaparecer/reentrar no veiculo a distancia | timeline do sinal na Central | excluir teleport, bucket e transicao legitima por lease |
| perfil sintetico de muitos headshots | somente alerta estatistico | baseline por arma/distancia/latencia e repeticao em janelas independentes |
| heartbeat/sensor client ausente | estado de saude, nao acusacao | Central mostra `sensor_missing` e versao sem somar risco punitivo |

- [ ] Repetir cada cenario com `AutoKick = false` e `AutoBan = false` comprovados antes e depois.
- [ ] Confirmar que o harness nao consegue escolher severidade, confianca, score ou acao final.
- [ ] Confirmar que replay de uma lease consumida nao silencia o segundo evento.
- [ ] Confirmar que uma lease de outro modelo, bucket, alvo ou resource nao concede bypass.
- [ ] Registrar falso positivo com gameplay/resource/versao da regra, sem recalibracao automatica.

## Central e seguranca

- [ ] Filtros Armas, Entidades, Movimento, Camera, Estado do jogador, Eventos e Mira funcionam.
- [ ] Detalhes mostram origem e confianca da evidencia.
- [ ] Payload client-side desconhecido e rejeitado.
- [ ] Flood client-side respeita limite global e cooldown por codigo.
- [ ] Reuso de source nao herda contadores ou estado do jogador anterior.
- [ ] Identifiers continuam protegidos por permissao separada.
- [ ] Incidentes repetidos agregam e respeitam TTL/limite de memoria.

## Automacao local

```powershell
cd mz_banguard/tests
lua security_observers_harness.lua
lua weapon_guard_alert_center_harness.lua
lua security_lifecycle_harness.lua
lua entity_classification_harness.lua

cd ..\..
lua mz_banguard/tests/security_leases_harness.lua
lua mz_banguard/tests/security_lease_integration_contract_harness.lua
lua mz_banguard/tests/event_contracts_harness.lua
lua mz_banguard/tests/detector_health_harness.lua

cd mz_admin
lua tests/security_alert_center_contract_harness.lua
```

O harness de observadores comprova registro por categoria, rejeicao de codigo client-side desconhecido, status somente-alerta e ausencia de cancelamento, delete, kick ou ban.

## Rollback

Cada modulo pode ser parado isoladamente:

```lua
Config.EntityGuard.enabled = false
Config.MovementGuard.enabled = false
Config.PlayerStateGuard.enabled = false
Config.EventGuard.enabled = false
Config.AimGuard.enabled = false
```

Desabilitar um observador nao altera banco, inventario, banlist nem os demais modulos.
