# Wave 1 — Evidence / Forensics / Incident Persistence

## Estado anterior

Incidentes, agregacao e correlation existiam em RAM. `playerDropped` limpava a timeline imediatamente; a Central montava detalhes tecnicos do estado vivo e nao havia snapshot SQL, crash correlation, LAB ou export forense. `CheckLocal()` liberava cedo ao encontrar um ban expirado.

## Alteracoes

- Persistencia canonica de incidentes agregados e acoes Staff no banco do `mz_banguard`.
- Hydration apos restart sem restaurar `source` como identidade persistente.
- Evidence model canônico adicionado sem remover campos legados.
- Timeline capturada antes da limpeza; `crash_observed` e `crash_cluster_suspect` implementados.
- Candidate actors exigem evidencia comum em duas ou mais vitimas.
- LAB auditavel, expiravel, sem punicao automatica e com retencao ampliada.
- Catalogo humano central e DTO `human` + `technical`.
- Export JSON/Markdown sanitizado e autorizado.
- `CheckLocal()` continua procurando bans ativos apos expirar um match.
- UI diferencia explicitamente **risco do incidente** do score de flags.

## Dois sistemas de score

`incident.riskScore` e escrito por `incidents.lua`, recalculado a partir de `SecurityAlerts/WeaponGuard.riskPoints` e contagem, persistido/hidratado em `mz_security_incidents` e consumido pela Central para severidade/ordenacao. Nao pune.

`MZBan.Flags score` e escrito por `flags.lua`, usa `Config.Risk.DefaultPoints`, decaimento em memoria e persiste cada flag em `mz_ban_flags`. E consumido por `GetRiskScore`, webhooks e pelas travas AutoKick/AutoBan (ambas continuam false). O acumulador em memoria nao e reidratado de `mz_ban_flags` apos restart; este limite foi documentado, nao redesenhado nesta Wave.

## Migrations

`sql/upgrade_1_5_wave1_mysql.sql` cria `mz_security_incidents`, `mz_security_incident_actions` e `mz_security_lab_subjects` de forma idempotente. Nenhuma tabela existente e renomeada ou destruida.

## Testes

`wave1_evidence_harness.lua` cobre agregacao de 100 sinais, writes controlados, hydration, drop normal/crash, cluster, candidatos sem evidencia, LAB, exports, DTO e source reuse. `ban_expiry_regression_harness.lua` cobre matches expirados/ativos em identifiers e tokens. Os harnesses anteriores continuam sendo executados como regressao.

## Performance

O fluxo e event-driven. Nao existe SQL por tick nem insert por sample. Estimativa normal: `0-5` inserts/min e `0-12` updates/min em servidor estavel. Agregados comuns escrevem no maximo uma vez por debounce. Em ataque, o writer aceita ate `120` upserts/min e enfileira o restante; cardinalidade em RAM, samples, timeline e estrutura JSON permanecem limitadas. Defaults: timeline persistida 16 entradas, 64 em LAB/crash; evidence 20 samples em RAM e snapshot estrutural com ate 128 entradas sanitizadas.

## Riscos restantes

- Classificacao de crash depende das mensagens entregues pelo artifact FiveM e precisa de calibracao runtime.
- Candidate actor e apenas hipotese investigativa, nunca culpado automatico.
- Flags score continua sem hydration do acumulador em memoria.
- Validacao runtime/FiveM, volume SQL real e UX de clipboard ainda exigem staging.

## Nao ativado

Nenhum AutoBan, AutoKick, auto-warn, entity lockdown, cancelamento global, API externa, VPN/proxy block ou mudanca de ownership foi ativado. `mz_warns` e `mz_whitelist` nao foram alterados.

## Wave 2

Calibrar motivos de crash com dados de staging, medir write rate real, validar clusters com incidentes controlados e decidir separadamente se o score de flags merece hydration. A Wave 2 nao deve iniciar sem aprovacao.
