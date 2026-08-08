# Central de Alertas no menu Staff

## Escopo

O `mz_admin` usa os componentes existentes do `mz_menu`; nenhuma segunda NUI foi criada. A entrada `Seguranca - Central de Alertas (N)` mostra resumo, modo do guard, incidentes, filtros por aberto/reconhecido/critico/arma/jogador e detalhes com evidencias. Quando badge por item nao existe, a contagem permanece no titulo e o submenu usa o badge de cabecalho.

O resumo operacional tambem mostra o estado efetivo de cancelamento de dano, autokick e autoban. Com a configuracao padrao, a politica exibida e `somente alertas`.

Incidentes guardam ID rastreavel, categoria, origem, confianca, player/source atual, citizenid, classificacao, severidade, risco, contadores, evidencias e notas. Incidentes de arma preservam tambem hashes, nomes, municao oficial, dano e alvo de rede. Desconexao marca o alvo offline sem apagar o registro. Antes de uma acao, a source atual e comparada ao identificador retido para evitar reuso de source.

## Permissoes

- `mz_banguard.alerts.view`
- `mz_banguard.alerts.details`
- `mz_banguard.alerts.acknowledge`
- `mz_banguard.alerts.note`
- `mz_banguard.alerts.clear`
- `mz_banguard.alerts.identifiers`
- `mz_banguard.actions.spectate`
- `mz_banguard.actions.goto`
- reservadas, nao implementadas na central: `mz_banguard.actions.kick` e `mz_banguard.actions.ban`

Cada callback e revalidado no `mz_admin` e novamente no `mz_banguard`. O resource consumidor tambem deve constar em `trustedConsumers`. Acesso a detalhes/identificadores, reconhecimento, nota, mudanca de status e preparacao de acao geram auditoria estruturada. Identificadores nao aparecem em listas, notificacoes ou detalhes comuns.

Os cargos default recebem apenas capacidades conservadoras: administrador visualiza/reconhece/anota e pode preparar spectate/goto; manager tambem pode alterar status e consultar identificadores. Kick/ban nao sao concedidos. Em instalacoes existentes, cargos ja persistidos devem receber as novas permissoes pelo gerenciamento Staff ou ACE.

## Estados e acoes

Estados aceitos: `open`, `acknowledged`, `resolved`, `false_positive`. Alterar estado nunca remove evidencias. A central permite copiar ID, reconhecer, anotar, resolver, marcar falso positivo e reabrir.

Spectate/goto sao preparados no servidor do BanGuard, com permissao, alvo online, identidade e hierarquia. Depois, o cliente chama o fluxo ja existente do `mz_admin`, que revalida novamente a permissao operacional e a hierarquia. Kick/ban retornam `action_not_implemented`; nao existe punicao automatica.

Alertas high/critical usam `mz_notify` para Staff com permissao de visualizacao, com cooldown por incidente e fallback ao notify do menu. A mensagem nao contem identifiers.

## Contratos server-only

Exports do `mz_banguard`: `GetSecurityAlertSummary`, `ListSecurityIncidents`, `GetSecurityIncident`, `AcknowledgeSecurityIncident`, `AddSecurityIncidentNote`, `SetSecurityIncidentStatus`, `PrepareSecurityIncidentAction` e `GetWeaponGuardStatus`.

Todos exigem `actorSource`; o chamador e obtido com `GetInvokingResource`. Nao ha net event que aceite um incidente pronto, severidade, score ou acao escolhidos pelo cliente. O endpoint de telemetria aceita apenas codigos predefinidos, limita frequencia, sanitiza campos e classifica esses sinais como evidencia client-side de baixa/media confianca.

## Rollback e indisponibilidade

Desative `Config.WeaponGuard.enabled` e `Config.WeaponGuard.notifyStaff` para interromper observacao/notificacoes sem alterar inventario. Com `mz_banguard` parado, o modulo do `mz_admin` nao chama os exports e registra uma tela controlada de indisponibilidade; as demais areas do menu continuam independentes.
