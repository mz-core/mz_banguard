# Matriz de integracao dos resources com o BanGuard

Esta matriz registra os fluxos legitimos que podem se parecer com cheat. Encontrar
uma native em codigo client-side nao prova vulnerabilidade; significa que o fluxo
precisa de contrato server-side antes de qualquer bloqueio preventivo.

## Integrados nesta entrega

| Resource | Fluxo | Capacidade | Contexto aplicado |
|---|---|---|---|
| `mz_admin` | `/tp`, `/tpm`, goto e bring | `movement.teleport` | destino quando conhecido, TTL e usos limitados |
| `mz_admin` | spawn de veiculo Staff | `entity.spawn.vehicle` | um uso e TTL de 5 segundos |
| `mz_core` | spawn/carregamento do personagem | `player.model.change` | hash exato do modelo e um uso |
| `mz_core` | spawn/carregamento do personagem | `movement.teleport` | coordenadas de destino e quatro amostras |
| `mz_core` | spawn/carregamento do personagem | lifecycle `character_spawn` | modelo, destino, bucket e confirmacao server-side |
| `mz_creator` | criacao/aparencia | lifecycle `character_creation` | modelos permitidos, destino, retorno e bucket |
| `mz_clothing` | loja de roupas | lifecycle `cosmetic_session` | modelo atual, bucket, loja e distancia validados |
| `mz_tatto` | loja/comando de tatuagem | lifecycle `cosmetic_session` | modelo atual, bucket, permissao ou distancia |
| `mz_houses` | entrada/saida de interior | lifecycle `interior_transition` | acesso, entrada, house code e bucket |
| `mz_houses` + `mz_clothing` | guarda-roupa da casa | lifecycle `cosmetic_session` delegado | sessao validada e encerravel pelo consumer |
| `mz_interiors` | calibracao Owner de IPL | lifecycle `interior_calibration` | convar, ACE/console, IPL catalogado, destino, retorno e bucket |

Leases de capacidade continuam restritas a `mz_admin` e `mz_core`. Os demais
resources acima emitem somente lifecycles com tipo, TTL e transicoes fixados no
BanGuard. Adicionar um emissor ao config sem integrar e revisar o handler
server-side e proibido.

## Inventario pendente

| Classe | Resources encontrados | Proxima acao segura |
|---|---|---|
| Modelo/invencibilidade | outros fluxos cosmeticos futuros | emitir lifecycle somente apos validar estado server-side |
| Teleporte/interior | `mz_doors`, `mz_hud`, `mz_props`, `mz_vehicles` | validar acesso/destino no servidor e emitir lease/lifecycle contextual |
| Objetos/animacao/camera | `mz_furniture`, `mz_phone`, `mz_progress`, `mz_target`, `mz_world_editor` | distinguir objeto local de entidade de rede e autorizar somente o necessario |
| Veiculos | `mz_core`, `mz_vehicles` | inventariar criacao server-side versus fallback client-side por fluxo |
| IPL/mapa | `mz_settings` | confirmar que entidades estaticas nao recebem owner de jogador |

## Regra para migracao

1. O servidor valida permissao, estado, ownership, distancia, bucket e limites.
2. O servidor emite a menor capacidade, TTL, quantidade e contexto possiveis.
3. O cliente apenas executa a acao ja autorizada; ele nunca escolhe a capacidade.
4. O detector consome a lease uma vez e registra a correlacao.
5. Staging confirma fluxo legitimo e tentativa sem lease antes de liberar outro emissor.

`sv_entityLockdown` continua fora de producao ate todos os spawns de rede necessarios
estarem classificados e testados em canario.
