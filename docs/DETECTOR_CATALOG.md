# Catalogo de detectores

`server/detector_catalog.lua` e a camada unica de apresentacao. Codigos internos permanecem estaveis; DTOs acrescentam `human` com titulo, resumo, categoria, explicacoes de severidade/confianca/mitigacao e acao recomendada.

| Codigo | Titulo humano | Categoria |
|---|---|---|
| `event_ptfx_rate_suspect` | Spam anormal de particulas | Eventos de rede |
| `player_godmode_suspect` | Possivel invencibilidade | Estado do jogador |
| `weapon_damage_no_equipped_weapon` | Dano sem arma autorizada | Armas |
| `movement_noclip_suspect` | Possivel noclip | Movimento |
| `crash_observed` | Jogador sofreu crash | Crash e estabilidade |
| `crash_cluster_suspect` | Varios jogadores crasharam em sequencia | Crash e estabilidade |

O arquivo contem tambem todos os codigos atuais de arma, entidade, movimento, camera, estado, eventos e mira. A UI mostra `human` por padrao e deixa hashes, net IDs, thresholds, timestamps, source history e raw evidence sanitizada na secao tecnica.

