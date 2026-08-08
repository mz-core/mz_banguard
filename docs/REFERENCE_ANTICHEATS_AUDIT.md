# Auditoria defensiva das referencias de anticheat

Data da revisao: 2026-08-02.

Este documento registra uma revisao defensiva focada nos mecanismos que podem orientar o `mz_banguard`. As referencias nao devem ser iniciadas no servidor. A conclusao nao e copiar detectores, e escolher principios que continuem validos quando o cliente estiver totalmente comprometido.

## 1. Escopo e licencas

| Referencia local | Licenca encontrada | Foco observado | Regra para o MZ |
|---|---|---|---|
| `ref/GoblinAC-master` | MIT | proxy e codificacao de eventos client/server | ideia arquitetural apenas; qualquer reaproveitamento exigiria preservar os avisos da MIT |
| `ref/IcarusAdvancedAnticheat-master` | GPL-3.0 | modulos server-side baseados em eventos OneSync | nao copiar codigo, tabelas ou listas para o MZ |
| `ref/Valkyrie-main` | GPL-3.0 | hardening server-side, modulos e permissoes | nao copiar codigo, tabelas ou listas para o MZ |
| `ref/FIREAC-main` | AGPL-3.0 | detectores client/server, grace e administracao | nao copiar codigo, tabelas, NUI ou banco para o MZ |

As implementacoes do BanGuard devem ser proprias. As referencias servem para levantar ameacas, invariantes, falhas comuns e casos de teste.

## 2. GoblinAC

Arquivos centrais revisados:

- `src/Client/Modules/EventProxy/EventProxy.cs`;
- `src/Client/Modules/KeyManager/KeyManager.cs`;
- `src/Server/Modules/EventProxy/EventInterpreter.cs`;
- `src/Server/Modules/KeyManager/KeyManager.cs`.

### O que e util

- centralizar a passagem client/server facilita inventariar e auditar eventos;
- usar identidade por jogador evita que todos compartilhem exatamente o mesmo estado;
- rotacao de estado reduz a vida util de capturas antigas;
- a migracao obriga o desenvolvedor a rever cada evento exposto.

### Limite de seguranca

As chaves e o proxy existem no cliente. Um executor que controla o cliente pode observar o fluxo legitimo, chamar o proxy ou repetir uma mensagem dentro da janela da chave. A codificacao nao adiciona, por si so, autorizacao de gameplay, limite de valor, posse do alvo, nonce de uso unico ou protecao contra repeticao.

Decisao: nao criar um "evento secreto universal" como fronteira de seguranca. O BanGuard deve criar um registro de contratos por evento, com schema, estado oficial, rate limit, idempotencia e autorizacao server-side. Um token vindo do cliente pode ser telemetria complementar, nunca a prova principal.

## 3. Icarus Advanced Anticheat

Arquivos centrais revisados:

- `src/server/core/Module.ts`, `ModuleLoader.ts` e `Violation.ts`;
- `src/server/core/handler/ExcuseHandler.ts`, `PermissionHandler.ts` e `EventHandler.ts`;
- modulos de entidade, explosao, mira, noclip, projetil, arma, tazer, particula e fogo.

### O que e util

- modulos independentes com ativacao e desativacao em runtime;
- uso de `entityCreating` para agir antes da replicacao;
- observacao de `explosionEvent`, `ptFxEvent`, `startProjectileEvent`, `fireEvent`, `giveWeaponEvent`, `removeWeaponEvent`, `clearPedTasksEvent` e `weaponDamageEvent`;
- verificacao de owner/alvo em acoes remotas;
- excecao temporaria por modulo para acomodar gameplay legitimo;
- separacao entre o detector e a integracao final de ban.

### O que nao deve ser reproduzido

- uma deteccao isolada chama ban diretamente em muitos modulos;
- existe bypass global, alem dos bypasses por modulo;
- a API oferece a excecao `*`, mas a verificacao por igualdade exata nao a aplica aos modulos nomeados como esperado; alem disso, o timeout pode apagar todas as excecoes do jogador;
- o detector de aimbot decide a partir de um unico evento e de geometria suscetivel a desync;
- a telemetria pode enviar screenshot a um servico externo; isso nao entra no escopo atual do MZ;
- medias globais de modificador podem ser contaminadas pelos proprios outliers;
- callbacks ligados com `bind` e removidos por comparacao textual tornam unload/reload fragil;
- ha trechos com premissas ou variaveis questionaveis, portanto a existencia de um modulo nao valida sua precisao.

Decisao: aproveitar o catalogo de eventos e o isolamento modular. Substituir "excuse" por lease consumivel e especifica. Nenhum detector pode chamar ban/kick diretamente.

## 4. Valkyrie

Arquivos centrais revisados:

- `server/modules/sv_entities.lua`, `sv_clearTasks.lua`, `sv_explosion.lua`, `sv_ptfx.lua` e `sv_playerIntegrity.lua`;
- `server/classes/sv_permissionManager.lua`, `sv_cache.lua`, `sv_player.lua`, `sv_playerManager.lua` e `sv_logger.lua`;
- `client/cl_loops.lua` e `client/cl_handlers.lua`.

### O que e util

- recomenda explicitamente `sv_entityLockdown` e criacao server-side de entidades;
- diferencia filtragem de modelo de uma politica de autoridade real;
- permite recarga de configuracao/modulos e possui niveis de log;
- mantem cache por jogador e limpa estado no ciclo de conexao;
- valida o alvo de `clearPedTasksEvent` e reconhece o abuso de expulsar outro jogador do veiculo;
- usa permissoes mais especificas que uma unica flag em parte dos modulos;
- mostra o valor de zonas protegidas e contexto espacial para explosoes.

### O que nao deve ser reproduzido

- existe uma permissao de bypass total;
- ACE dinamico nao possui TTL intrinseco e depende de remocao correta;
- `clearPedTasksEvent` e cancelado sempre, sem modo de observacao uniforme;
- blacklists genericas de eventos e modelos envelhecem, conflitam com recursos legitimos e nao corrigem o evento vulneravel;
- parte dos detectores depende de relato e estado alteravel no cliente;
- o teste client-side de godmode altera a vida do jogador, o que pode interferir no gameplay;
- contadores de strikes precisam de janela/decay explicitos para nao acumular indefinidamente;
- ha mistura de codigo antigo e novo, com nomes internos inconsistentes, entao runtime reload nao deve ser assumido como seguro sem teste.

Decisao: adotar o principio de server authority, lifecycle cache, log estruturado e configuracao recarregavel. Nao adotar health probing, blacklist universal ou bypass total.

## 5. FIREAC

Pontos ja confirmados na revisao anterior:

### O que e util

- grace period de spawn e transicoes;
- varias amostras antes do relato;
- cooldown por motivo e limite de relatos;
- separacao de contadores por tipo de entidade;
- combinacao de sinais para estados como godmode;
- grace para acoes administrativas legitimas.

### O que nao deve ser reproduzido

- foco excessivo em telemetria controlada pelo cliente;
- punicao automatica como resposta comum;
- whitelist ampla de administrador;
- monitoramento de entidade tarde demais quando usa apenas `entityCreated`;
- NUI, banlist, AntiVPN, screenshots e alteracoes de banco fora do escopo do BanGuard;
- listas prontas de eventos, armas e modelos sem validacao contra o gameplay do MZ.

## 6. Matriz de decisoes para o BanGuard

| Mecanismo | Valor defensivo | Decisao |
|---|---|---|
| contrato server-side por evento | muito alto | implementar antes de tentar esconder eventos |
| lease curta e consumivel | muito alto | implementar com escopo de acao, recurso, alvo, modelo, quantidade e bucket |
| criacao server-side de entidades | muito alto | migrar recursos por etapas e testar `sv_entityLockdown` em canario |
| `entityCreating` | alto | observar agora; cancelar apenas depois de autoridade e artifact validados |
| owner/alvo/distancia em eventos nativos | alto | correlacionar e registrar na Central |
| rate limit por jogador, tipo e bucket | alto | manter, calibrar e separar burst de volume sustentado |
| configuracao/modulo recarregavel | medio/alto | implementar com status efetivo e auditoria de mudanca |
| chaves/eventos secretos no cliente | baixo como barreira principal | nao tratar como autenticacao |
| blacklist generica de eventos | baixo | corrigir os handlers reais do MZ |
| blacklist de modelos | complementar | usar somente como aumento de severidade, nao como autoridade unica |
| screenshot/OCR | baixo para este ciclo | fora do escopo por privacidade, custo e facilidade de bypass |
| ban por uma unica regra | risco alto | proibido |
| bypass total de Staff | risco alto | proibido |

## 7. Melhorias obrigatorias no plano

1. Criar `Security Leases v2`: server-only, sem curinga, TTL maximo, uso unico ou quantidade limitada, vinculo ao recurso emissor, contexto e trilha de consumo.
2. Criar `Event Contract Registry`: schema, faixa, estado, ownership, destino, rate, idempotencia e motivo de rejeicao para cada evento sensivel do MZ.
3. Planejar migracao gradual de spawn para o servidor e piloto de entity lockdown, em vez de depender apenas de detectar spam depois que ocorreu.
4. Expandir Event Guard para particulas, projeteis, fogo, give/remove weapon, modificadores e acoes remotas, todos inicialmente em `observe`.
5. Separar `sensor_missing` de `cheat_detected`: heartbeat ausente ou resource client parado e sinal de saude, nao prova para punicao.
6. Adicionar correlacao temporal: manter uma timeline curta por jogador para juntar lease, spawn, owner, bucket, movimento, evento e dano.
7. Tornar Aim Guard permanentemente analitico: nenhuma conclusao por tiro isolado; baselines por arma, distancia, latencia e tamanho minimo.
8. Adicionar observabilidade do proprio guard: versao de configuracao, modulo efetivo, ultimo evento, volume, descartes, cooldowns, erros e custo por tick.
9. Adicionar fluxo de falso positivo na Central: marcar causa legitima, recurso envolvido, regra, versao e resultado da recalibracao.
10. Testar ataques sem comandos. O harness deve emitir entradas equivalentes aos eventos/rede usados por um executor, pois permissao de comando nao protege um handler vulneravel.

## 8. Conclusao

O desenho recomendado e um sistema em duas camadas:

- prevencao: autoridade server-side, contratos, leases, ownership, limites e, onde for viavel, entity lockdown;
- deteccao: sensores client/server correlacionados, incidentes explicaveis e Central de Alertas em modo somente-observacao.

Esse desenho e mais resistente que ocultar eventos ou acumular blacklists. Ele tambem permite ativar bloqueios reversiveis no futuro sem ligar auto kick ou auto ban.
