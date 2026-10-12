# mz_banguard 1.4

Resource FiveM para ban/unban local, integração com cloud central, flags de risco, webhooks e auditoria.

## Dependência

```cfg
ensure oxmysql
ensure mz_core
ensure mz_banguard
ensure mz_admin
```

Em instalação nova, tabelas totalmente ausentes são criadas automaticamente com `CREATE TABLE IF NOT EXISTS`. Tabelas existentes nunca recebem `ALTER` por padrão: schema antigo incompleto exige revisão e upgrade manual em staging. Retenção, cloud, webhook e autoban permanecem desligados.

## Permissões ACE

```cfg
add_ace group.mz_owner mzban.admin allow
add_ace group.mz_owner mzban.ban allow
add_ace group.mz_owner mzban.unban allow
add_ace group.mz_owner mzban.lookup allow
```

Para jogadores que não são Owner, as permissões globais do `mz_core` são a autoridade padrão. `/ban`, `/unban`, `/baninfo` e `/banflags` usam essas permissões; ban e consultas sobre player respeitam a hierarquia Staff. `/banlookup` fica reservado a console e Owner por padrão.

Os ACEs `mzban.*` são preservados para instalações antigas, mas não são exigidos de Staff comum. Para adotá-los como segunda barreira, sem substituir as permissões globais:

```lua
Config.LegacyCommands.RequireLegacyAceForPlayers = true
```

## Política de atuação unificada

Durante staging, mantenha:

```lua
Config.Enforcement.DefaultMode = 'passive'
Config.Enforcement.AutomaticKickEnabled = false
Config.Enforcement.AutomaticBanEnabled = false
Config.DetectorActions = {}

Config.Risk.AutoKick = false
Config.Risk.AutoBan = false
Config.WeaponGuard.mode = 'observe'
Config.WeaponGuard.cancelHighConfidence = false
Config.WeaponGuard.runtimeValidated = false
```

Os modos por detector são `passive`, `mitigate`, `kick` e `ban`. `kick` e `ban` exigem suas chaves globais, evidência confirmada, persistência e identidade estável; continuam desligados por padrão. O score legado permanece informativo e não contorna o motor unificado. Veja [docs/WAVE2A_ENFORCEMENT.md](docs/WAVE2A_ENFORCEMENT.md).

## Comandos

```txt
/ban [id] [tempo|perm] [motivo]
/unban [public_id] [motivo]
/baninfo [id]
/banflags [id]
/banlookup [tipo] [valor]
```

Os comandos públicos são registrados uma única vez pelo `mz_banguard`. O `mz_admin` mantém os fluxos de menu, mas não registra handlers concorrentes para `/ban` ou `/unban`.

## Exports

Os exports de risco começam fechados por operação. Antes de usar os exemplos, habilite somente o resource revisado:

```lua
Config.Risk.ExportAccess.FlagPlayer.mz_detector = true
Config.Risk.ExportAccess.RegisterTrustedAction.mz_admin = true
Config.Risk.ExportAccess.RegisterSecurityLease.mz_admin = true
```

Não autorize um consumer apenas porque ele já usa outro export. Pontos, janela confiável e evidência têm limites server-side. Veja [docs/RISK_EXPORT_SECURITY_CONTRACT.md](docs/RISK_EXPORT_SECURITY_CONTRACT.md).

### Marcar jogador suspeito

```lua
exports['mz_banguard']:FlagPlayer(source, 'event_injection', 100, {
  event = 'mz_core:addMoney',
  detail = 'Tentativa de chamar evento protegido'
})
```

### Registrar ação autorizada

```lua
exports['mz_banguard']:RegisterTrustedAction(source, 'teleport', 10000)
```

O export legado acima continua compatível, mas novas integrações devem usar uma
capacidade curta, consumível e contextualizada:

```lua
exports['mz_banguard']:RegisterSecurityLease(source, 'movement.teleport', 10000, {
  x = destination.x,
  y = destination.y,
  z = destination.z,
  quantity = 1,
  reason = 'garage_exit'
})
```

O emissor é obtido por `GetInvokingResource()`; cliente, wildcard e resource não
autorizado não conseguem criar lease.

### Sessao de lifecycle

A versao 1.4 adiciona sessoes server-side para spawn, criacao de personagem,
edicao cosmetica, respawn e transicao de interior. O tipo define as transicoes
permitidas e o cliente nao escolhe escopo nem amplia TTL. `mz_core`, `mz_creator`,
`mz_clothing`, `mz_tatto` e `mz_houses` ja possuem integracoes revisadas.

O Entity Guard separa populacao ambiente/system de entidades scripted/unknown.
Ambiente continua gerando metrica, mas ownership proximo nao vira incidente de
spawn por si so. O Weapon Guard v2 consulta apenas o snapshot oficial do Core e
registra cadencia por arma, alvo, distancia e revisoes como evidencia.

### Consultar score

```lua
local score = exports['mz_banguard']:GetRiskScore(source)
```

### Integração administrativa

O `mz_admin` usa exports server-side protegidos para prontidão, criação, revogação, consulta e listagem. Esses exports aceitam somente resources confiáveis, revalidam permissões globais no `mz_core` e nunca retornam identifiers, tokens ou IP.

Veja [docs/INTEGRATION_API_CONTRACT.md](docs/INTEGRATION_API_CONTRACT.md) e [docs/RUNTIME_CHECKLIST.md](docs/RUNTIME_CHECKLIST.md).

O roteiro dos proximos detectores (spawn de entidades, movement/freecam/noclip, troca de skin, godmode, eventos e analise de mira) esta em [docs/GUARD_ENTITY_MOVEMENT_AIM_IMPLEMENTATION_PLAN.md](docs/GUARD_ENTITY_MOVEMENT_AIM_IMPLEMENTATION_PLAN.md). Todos os lotes comecam em modo somente-alerta.

Os observadores desses lotes estao ativos em `observe`. Use [docs/SECURITY_OBSERVERS_STAGING_CHECKLIST.md](docs/SECURITY_OBSERVERS_STAGING_CHECKLIST.md) para validar peds/veiculos/objetos, movimento, camera, estado do jogador, eventos e mira sem habilitar punicao automatica. A migracao gradual dos fluxos legitimos esta registrada em [docs/RESOURCE_SECURITY_INTEGRATION_MATRIX.md](docs/RESOURCE_SECURITY_INTEGRATION_MATRIX.md).

O escopo, o que foi implantado e os passos que ainda exigem staging estao em [docs/BANGUARD_PHASE_2_HARDENING_PLAN.md](docs/BANGUARD_PHASE_2_HARDENING_PLAN.md).

## Cloud

```lua
Config.Cloud.Enabled = true
Config.Cloud.BaseUrl = 'https://sua-api.com'
Config.Cloud.ApiKey = 'mzbg_live_xxxxx'
```

O resource usa timeout, cache e cooldown para a cloud não travar a conexão do jogador.

## Privacidade

IP local e IP cloud vêm desligados por padrão.

```lua
Config.Privacy.StoreIpLocal = false
Config.Cloud.SendIpToCloud = false
```
