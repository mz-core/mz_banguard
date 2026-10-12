# Persistencia de incidentes

O owner e writer canonico continua sendo `mz_banguard`. `mz_security_signals` guarda ocorrencias sanitizadas; `mz_security_incidents` guarda o snapshot agregado; `mz_security_incident_actions` guarda a trilha de abertura, visualizacao, notas, status, export e acoes autorizadas.

## Escritas

- Criacao: um `INSERT ... ON DUPLICATE KEY UPDATE` imediato.
- Alteracao relevante de severidade/confianca, crash, LAB, status, nota ou timeline: update imediato.
- Nova amostra comum: update debounced por `IncidentPersistence.updateDebounceMs`.
- Toda chamada aceita por `Incidents.Record` gera um raw signal; o agregado continua debounced.
- O DTO separa ocorrencias, amostras retidas, descartadas por limite e suprimidas por cooldown.
- Audit administrativo permanece separado do snapshot tecnico.

`first_seen_at` e `source_at_first_seen` nunca sao sobrescritos no upsert. `source_at_last_seen` e contexto; `source` atual nao e hidratado como identidade online depois de restart.

## Bootstrap e migration

Instalacoes novas usam `sql/install_mysql.sql`. Instalacoes 1.5 executam `sql/upgrade_1_6_incident_v3_mysql.sql` depois do upgrade Wave 1 aplicavel; os arquivos sao idempotentes. O bootstrap cria tabelas totalmente ausentes, mas nao altera silenciosamente tabelas incompletas.

Para rollback, pare o resource e restaure o backup anterior. Nao remova as novas tabelas antes de exportar evidencia que precise ser preservada.

## Retencao e desempenho

- RAM: TTL da Central continua independente da persistencia SQL.
- SQL: somente incidentes resolvidos/falso positivo mais antigos que `Retention.IncidentsDays` entram na limpeza opcional.
- Cenario normal estimado: servidor estavel, `0-5` inserts/min e `0-12` updates/min; o valor real acompanha incidentes significativos, nao ticks.
- Cem ocorrencias aceitas: cem raw signals imutaveis e um agregado com quantidade controlada de updates.
- Cenario de ataque: no maximo `120` upserts/min por padrao; excedentes ficam na fila limitada indiretamente pelos `maxIncidents` em RAM e sao drenados nas janelas seguintes.
- Timeline persistida: ate 16 entradas normais ou 64 LAB/crash por padrao; o modelo sanitizado limita o payload efetivo.
