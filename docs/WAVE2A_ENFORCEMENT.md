# Wave 2A — atuação unificada

Status: implementado estaticamente; validação runtime em staging ainda obrigatória.

## Política

`server/enforcement.lua` é o único decisor de atuação automática originada por incidentes. A política fica em `config.lua`:

```lua
Config.Enforcement = {
    DefaultMode = 'passive',
    AutomaticKickEnabled = false,
    AutomaticBanEnabled = false,
    RequireStableIdentity = true,
    RequireConfirmedEvidence = true,
    OnMitigationFailure = 'log_only'
}

Config.DetectorActions = {}
```

Os valores aceitos são `passive`, `mitigate`, `kick` e `ban`. Um valor inválido resolve para `passive` e produz auditoria `security.enforcement.policy_invalid`. Mudanças observadas na política produzem `security.enforcement.policy_loaded` ou `security.enforcement.policy_changed`. Alterar a política não altera incidentes já persistidos.

`kick` e `ban` exigem, além do modo por detector, a chave global correspondente. As duas chaves permanecem `false` por padrão. `Config.Risk.AutoKick` e `Config.Risk.AutoBan` são legados informativos e não executam punição.

## Fluxo e resultados

O detector cria ou agrega o incidente antes de chamar o motor. O motor registra `configured_mode`, `resolved_mode`, `requested_action`, `executed_action`, `execution_result`, `reason`, `incident_id`, `account_id`, `session_id`, sources de detecção/execução e timestamp.

- `passive`: registra e preserva evidência, sem chamar a capability de mitigação.
- `mitigate`: chama somente a capability server-side fornecida pelo guard e registra `blocked`, `reverted`, `observed_only`, `failed` ou `not_supported`.
- `kick`: herda mitigação e só desconecta após evidência confirmada, persistência do incidente/solicitação e revalidação de identidade.
- `ban`: herda mitigação, persiste no sistema local existente (`mz_bans` + `mz_ban_audit`) e somente depois solicita a desconexão.

Uma solicitação de kick/ban persistida funciona como chave de idempotência de execução. Em dúvida após falha ou restart, a política é at-most-once: não repetir automaticamente. Para ban, a busca adicional pelo `incident_id` no ban ativo evita duplicação caso o ban tenha sido confirmado antes de uma falha posterior.

## Mitigação real

Os únicos bloqueios conectados nesta Wave são hooks já existentes e tecnicamente controláveis:

| Guard | Detectores | Condições adicionais |
|---|---|---|
| `weaponDamageEvent` | `weapon_damage_no_equipped_weapon`, `weapon_damage_hash_mismatch`, `weapon_damage_death_state_incompatible` | `cancelHighConfidence=true` e `runtimeValidated=true` |
| `entityCreating` | `entity_model_blocked`; rate de entidade somente com confiança alta | fase `creating`, `cancelHighConfidence=true` e `runtimeValidated=true` |

PTFX, projectile, explosão, heartbeat, presença/stop de resource, crash, godmode/invisibility, câmera, aim e canários continuam observacionais quando não existe bloqueio/reversão validado. `mitigate` nesses casos registra `not_supported`; não simula sucesso.

Crash, heartbeat/resource presence, telemetria client-side de godmode/invisibility/câmera/aim e canários são excluídos de punição automática mesmo que um override seja configurado como `kick` ou `ban`.

## Identidade e persistência

Antes de kick/ban, o motor compara novamente `account_id`, `session_id`, `citizenid` e identificador `license`/`fivem` com o snapshot do incidente. Source é apenas endereço efêmero. Offline, identidade ausente ou source reutilizado cancela a atuação e registra a razão.

`false`, `nil` e erro/timeout do adapter SQL não são confirmação. Ban local continua transacional. Falha ao persistir ban impede a desconexão por ban; falha de desconexão depois de um ban confirmado mantém o ban verdadeiro e registra `ban_persisted_disconnect_failed`.

As tabelas V3 existentes suportam esta Wave; não há migration nova. A instalação/upgrade V3 anterior continua sendo requisito operacional.

## Flood e munição

Sinais que já produzem incidente não são duplicados pela correlação SQL por padrão. O agregado preserva os primeiros sinais brutos e uma amostra representativa, contabiliza descartes/falhas/backpressure e usa fila limitada com retry exponencial. O incidente continua contando todas as ocorrências.

`mz_inventory:server:syncWeaponAmmo` não possui mais bypass de frequência. Nonce, revisão, ownership, slot/equipamento, metadata e bloqueio de aumento client-side permanecem no serviço. Aumento legítimo continua pertencendo ao fluxo server-side de reload.

## Validação local

Os harnesses relevantes são:

```text
mz_banguard/tests/wave2a_enforcement_harness.lua
mz_banguard/tests/wave2a_flood_harness.lua
mz_inventory/tests/weapon_ammo_rate_limit_contract_harness.lua
mz_admin/tests/security_contract_harness.lua
```

Eles usam mocks; não conectam ao banco, não executam punições reais e não substituem validação runtime/FiveM em staging.
