# mz_banguard 1.2

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

### Consultar score

```lua
local score = exports['mz_banguard']:GetRiskScore(source)
```

### Integração administrativa

O `mz_admin` usa exports server-side protegidos para prontidão, criação, revogação, consulta e listagem. Esses exports aceitam somente resources confiáveis, revalidam permissões globais no `mz_core` e nunca retornam identifiers, tokens ou IP.

Veja [docs/INTEGRATION_API_CONTRACT.md](docs/INTEGRATION_API_CONTRACT.md) e [docs/RUNTIME_CHECKLIST.md](docs/RUNTIME_CHECKLIST.md).

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
