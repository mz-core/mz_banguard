# Correlation black box

`security_correlation.lua` permanece como ring buffer em RAM. A retencao padrao e 30 segundos, configuravel, com 32 entradas por jogador; LAB pode usar 120 segundos e 96 entradas.

## Ordem de `playerDropped`

1. Captura `reason`, nome e identidade server-side.
2. Copia a timeline e ultima posicao/bucket ainda disponiveis.
3. Classifica a saida como `disconnect`, `timeout`, `kick`, `ban`, `resource_stop` ou `crash`.
4. Em crash, cria `crash_observed` e persiste o snapshot.
5. Correlaciona crashes recentes e, quando aplicavel, cria/atualiza `crash_cluster_suspect`.
6. Somente depois limpa o ring buffer.

O classificador e conservador e cobre mensagens observaveis como `Game crashed`, `RAGE error`, executavel, exception code e offset. Timeout, kick e ban sao avaliados antes dos padroes de crash.

## Cluster e candidatos

O default exige duas vitimas em cinco segundos. `common_signals` contem somente tipos de evento presentes nas timelines correlacionadas. Um candidate actor so aparece quando o mesmo source e sustentado por campos explicitos (`owner`, `firstOwner`, `targetOwner` ou `target`) em pelo menos duas vitimas. A confidence e a proporcao de vitimas que sustentam o candidato; nao existe score oculto. `crash_observed` nunca acusa outro jogador.

