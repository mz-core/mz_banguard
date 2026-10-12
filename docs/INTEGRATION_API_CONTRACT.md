# Contrato de integração do MZ BanGuard

## Autoridade e disponibilidade

`mz_banguard` é a única autoridade de banimentos, identifiers, tokens, enforcement de conexão, auditoria própria, webhooks e sincronização cloud.

`Config.Database.AutoCreateMissingTables = true` cria somente tabelas totalmente ausentes com o schema atual. `CREATE TABLE IF NOT EXISTS` não altera nem apaga tabelas existentes.

`Config.Database.AutoMigrateExistingTables = false` impede `ALTER` automático. Se uma tabela existente estiver sem coluna ou índice obrigatório, `IsReady` informa `missing_column:<tabela>.<coluna>` ou `missing_index:<tabela>.<indice>` e o upgrade deve ser revisado manualmente.

O enforcement falha fechado: se criação ou validação falhar, novas conexões recebem a mensagem de indisponibilidade e não entram sem verificação.

`IsReady` retorna `true` somente quando as seis tabelas, todas as colunas e todos os índices obrigatórios existem e o `mz_core` está iniciado. O resultado é armazenado por 30 segundos para evitar dezenas de consultas de metadados a cada menu ou conexão:

```lua
local ready, reason = exports['mz_banguard']:IsReady()
```

Os demais exports aceitam chamadas apenas dos resources declarados em `Config.Integration.TrustedResources`. O padrão autoriza `mz_admin` e o caller interno `mz_banguard`, usado exclusivamente pelos comandos históricos encaminhados à mesma API. Não existem eventos de rede públicos para mutações.

## Permissões globais

| Operação | Permissão `mz_core` |
| --- | --- |
| consultar/listar | `staff.bans.view` |
| banir player online | `staff.players.ban` |
| revogar | `staff.bans.revoke` |

As permissões ACE `mzban.*` continuam disponíveis como barreira adicional opcional dos comandos históricos, mas vêm desativadas para Staff comum. Para jogadores, a autoridade padrão é a permissão global correspondente no `mz_core`. Console e `group.mz_owner` permanecem como autoridades explícitas.

## Envelope

Todos os exports de integração retornam:

```lua
{
  ok = true|false,
  data = table|nil,
  error = string|nil
}
```

Falhas de resource, schema, permissão, alvo, hierarquia, duração, motivo ou persistência retornam `ok=false`. Consumidores não devem inferir sucesso pela ausência de exceção. Depois do commit, `data.disconnectRequested=false` informa que o ban foi confirmado, mas a desconexão foi cancelada/falhou; `data.disconnectReason` preserva a causa real.

## Criar ban online

```lua
local response = exports['mz_banguard']:CreateOnlineBan(
  actorSource,
  targetSource,
  '7d', -- perm, Nm, Nh ou Nd
  'motivo com 3 a 256 caracteres',
  expectedCitizenid
)
```

O BanGuard revalida no servidor:

- resource chamador confiável;
- schema e `mz_core`;
- ator e alvo online;
- `staff.players.ban`;
- self-target;
- `mz_core:CanStaffActOnPlayer`;
- duração máxima de 3650 dias;
- motivo;
- license obrigatória;
- `expectedCitizenid` obrigatório para o caller `mz_admin`;
- CitizenID e identifiers estáveis antes da transação e antes da desconexão;
- existência de ban local ativo.

Ban, identifiers, tokens e auditoria `ban.created.integration` são gravados na mesma transação. Somente depois do commit são disparados webhook/cloud e, se a identidade ainda corresponder, `DropPlayer`. Falha transacional não remove o alvo; source reutilizado após o commit preserva o ban verdadeiro e registra que a desconexão não foi concluída.

## Revogar

```lua
local response = exports['mz_banguard']:RevokeBan(
  actorSource,
  'MBG-ABC234',
  'motivo da revogacao'
)
```

Exige `staff.bans.revoke`, Public ID válido e motivo. Ban, vínculos ativos e auditoria `ban.revoked.integration` são atualizados na mesma transação. Não há guard de alvo Staff porque a revogação usa um registro possivelmente offline e reduz uma punição; a autorização é exclusiva e separada.

O campo `active` aceita os formatos numérico, textual e booleano retornados por diferentes versões/configurações do `oxmysql`. Falhas distinguem `not_found`, `already_revoked` e `expired`.

## Consultar

```lua
local one = exports['mz_banguard']:GetBan(actorSource, 'MBG-ABC234')
local page = exports['mz_banguard']:ListBans(actorSource, {
  active = true, -- true, false ou ausente
  search = 'MBG- ou nome',
  page = 1,
  pageSize = 25
})
```

Os DTOs públicos contêm apenas Public ID, nome, motivo, Staff, estado e timestamps. Identifiers, tokens, IP, evidence, identificador do ator e IDs internos nunca são retornados.

`pageSize` é limitado pelo BanGuard mesmo quando o consumidor envia valor arbitrário. Campos desconhecidos são descartados.

## Compatibilidade

Os exports existentes `FlagPlayer`, `RegisterTrustedAction` e `GetRiskScore` permanecem. Os comandos públicos seguem o padrão `/ban`, `/unban`, `/baninfo`, `/banflags` e `/banlookup`.

Compatibilidade de nome e assinatura não significa acesso implícito. Os três exports de risco usam allowlists independentes em `Config.Risk.ExportAccess`; mutações começam sem consumer autorizado. Consulte [RISK_EXPORT_SECURITY_CONTRACT.md](RISK_EXPORT_SECURITY_CONTRACT.md).

Quando executados por jogador, `/ban` e `/unban` usam `CreateOnlineBan` e `RevokeBan`, respectivamente. `/baninfo` e `/banflags` exigem `staff.bans.view` e respeitam `CanStaffActOnPlayer`. `/banlookup`, que recebe identifier bruto, fica reservado a console e Owner por padrão. `RequireLegacyAceForPlayers = true` pode impor ACE como segunda barreira, sem substituir nenhuma permissão global.

O `mz_banguard` é o único registrador desses comandos. O `mz_admin` reutiliza a mesma API nos menus e não mantém handlers concorrentes de `/ban` ou `/unban`.

`mz_admin` não acessa tabelas, globals internos ou comandos por string. Quando `IsReady` falha, ban/unban não aparecem no menu.

## Coordenação opcional da whitelist

Quando `mz_whitelist` está iniciado, o mesmo handler `playerConnecting` consulta `CheckConnection` depois de recusar ban local e antes da consulta cloud. O BanGuard não acessa tabelas da whitelist. Resource ausente mantém o comportamento anterior; resource iniciado com contrato indisponível falha fechado conforme `Config.Whitelist.FailClosedWhenStarted`.
# Identidade MZ contextual

Para bans online, o client continua enviando apenas o `source`. O BanGuard revalida o alvo e resolve `source -> citizenid` por `mz_core:ResolvePlayerIdentity`.

O CitizenID e armazenado como contexto local da evidencia e retornado ao Staff no campo `citizenId`. A aplicacao do ban continua baseada em identifiers e tokens da conta; CitizenID sozinho nunca e usado para bloquear conexao. A integracao cloud remove `target_citizenid` da evidencia antes do envio.
