# Checklist de staging - Weapon Guard e Central de Alertas

Mantenha `mode = 'observe'`, `cancelHighConfidence = false` e `runtimeValidated = false` durante todo o primeiro ciclo.

## Preparacao

- [ ] Confirmar ordem de start: `mz_core`, `mz_menu`, `mz_notify`, `mz_banguard`, `mz_admin`.
- [ ] Confirmar que nenhuma migration/SQL foi aplicada por este lote.
- [ ] Conceder somente `view/details/acknowledge/note` ao grupo de teste.
- [ ] Confirmar que Staff sem `identifiers` nao ve license/fivem.
- [ ] Confirmar que Staff sem permissoes de acao nao ve botoes de spectate/goto.

## Matriz funcional

- [ ] Tiro legitimo com pistola, SMG, shotgun, rifle, sniper, MG e RPG nao cria incidente de divergencia.
- [ ] Equip e tiro imediato entram em transicao sem risco punitivo.
- [ ] Desequip, troca rapida e troca de slot respeitam `transitionWindowMs`.
- [ ] Recarregar atualiza a municao oficial sem criar divergencia de arma.
- [ ] Morte, revive e respawn nao reutilizam autoridade antiga.
- [ ] Troca de personagem nao herda estado, source ou citizenid anterior.
- [ ] Entrada/saida de routing bucket nao altera a autoridade de arma.
- [ ] Spectate e noclip Staff nao produzem incidente nem concedem bypass ao alvo.
- [ ] Armas legitimas de job seguem o mesmo contrato oficial do inventario.
- [ ] Latencia alta permanece agregada e dentro da janela de transicao calibrada.
- [ ] Reconnect com reuso de source nao herda arma nem permite acao no incidente antigo.
- [ ] Arma custom autorizada pelo core funciona mesmo sem nome no catalogo.
- [ ] Hash divergente conhecido e desconhecido aparecem com classificacao correta.
- [ ] Source invalida, sessao nao carregada e core reiniciando falham de modo controlado.
- [ ] Rajadas de armas automaticas calibram `rateEventThreshold` sem inundar a central.
- [ ] Eventos duplicados agregam contagem e respeitam cooldown de evidencia/notificacao.
- [ ] Limite de incidentes e TTL removem apenas dados antigos em memoria.
- [ ] Desconexao preserva incidente e desabilita acoes online.

## Menu e seguranca

- [ ] Contagem aparece no titulo/badge e o resumo bate com a lista.
- [ ] Filtros aberto, reconhecido, critico, armas e jogador funcionam.
- [ ] Detalhes, identifiers, reconhecer, nota e status exigem permissoes separadas.
- [ ] Nota e status preservam evidencias e produzem auditoria com ID do incidente.
- [ ] Spectate/goto revalidam identidade, alvo online e hierarquia nos dois resources.
- [ ] Kick/ban da central retornam nao implementado.
- [ ] Notificacao high/critical chega apenas a Staff autorizado e sem identifiers.
- [ ] `mz_banguard` parado produz tela/erro controlado, sem quebrar o menu Staff.

## Criterio para qualquer enforce futuro

- [ ] Registrar volume e falsos positivos por pelo menos um ciclo representativo.
- [ ] Validar comportamento real do `weaponDamageEvent` no artifact de producao.
- [ ] Revisar armas custom, recursos de dano e cadencias automaticas.
- [ ] Aprovar formalmente as classificacoes de alta confianca.
- [ ] Alterar as tres chaves de enforce em mudanca separada, revisada e reversivel.

Automacao local:

```powershell
cd mz_core
lua tests/weapon_authority_contract_harness.lua
cd ../mz_banguard/tests
lua weapon_guard_alert_center_harness.lua
cd ../../mz_admin
lua tests/security_alert_center_contract_harness.lua
```
