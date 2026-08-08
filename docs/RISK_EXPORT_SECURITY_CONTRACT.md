# Contrato de segurança dos exports de risco

## Escopo

`FlagPlayer`, `RegisterTrustedAction` e `GetRiskScore` preservam os nomes e assinaturas históricas. `RegisterSecurityLease` é o contrato recomendado para novas integrações. Cada operação possui allowlist server-side própria:

```lua
Config.Risk.ExportAccess = {
    FlagPlayer = {},
    RegisterTrustedAction = {},
    RegisterSecurityLease = {
        mz_admin = true,
        mz_core = true
    },
    GetRiskScore = {
        mz_admin = true
    }
}
```

O valor comparado é o nome exato retornado por `GetInvokingResource()`. Não há wildcard, inferência por prefixo nem fallback permissivo. Chamadas diretas internas a `MZBan.Flags.*` continuam privadas ao resource e não passam por essa fronteira.

## Habilitação de consumer

Um resource somente deve ser autorizado depois de revisar:

- origem e validação dos eventos que produzem a detecção;
- possibilidade de o cliente escolher alvo, motivo, pontos ou evidência;
- rate limit do consumer;
- política de falsos positivos;
- uso de `RegisterSecurityLease` somente ao redor de ações legítimas controladas pelo servidor.

Exemplo explícito:

```lua
Config.Risk.ExportAccess.FlagPlayer.mz_detector = true
Config.Risk.ExportAccess.RegisterTrustedAction.mz_admin = true
Config.Risk.ExportAccess.RegisterSecurityLease.mz_admin = true
```

Autorizar `FlagPlayer` não autoriza `RegisterTrustedAction`, `RegisterSecurityLease` ou `GetRiskScore`.

## Validação

`FlagPlayer` exige:

- player online;
- motivo normalizado com até 64 caracteres e conjunto seguro;
- pontos inteiros entre `1` e `MaxPointsPerFlag`;
- evidência limitada por número de chaves, profundidade e tamanho de strings;
- ausência de janela confiável ativa;
- player sem ACE administrativa ignorada pelo risco.

`RegisterTrustedAction` exige player online, ação legada conhecida e duração entre 250 ms e `MaxTrustedActionMs`. Ele traduz a ação para uma capability v2 e rejeita `*`.

`RegisterSecurityLease` exige player online, capability declarada, resource autorizado para a operação e para a capability, TTL dentro do teto e contexto sanitizado. A lease possui usos limitados, é consumida pelo detector e é revogada no `playerDropped` ou no stop do emissor. `reason` e `correlationId` são somente metadados de auditoria; modelo, bucket, alvo e coordenadas participam da correspondência quando informados.

`GetRiskScore` exige consumer autorizado e player online.

## Politica de punicao automatica

O padrao de staging e somente alerta:

```lua
Config.Risk.AutoKick = false
Config.Risk.AutoBan = false
```

Com `AutoKick = false`, ultrapassar `KickAt` nao chama `DropPlayer`; o fluxo segue para alerta/revisao. `AutoKick = true` deve ser habilitado somente em mudanca separada, depois de validar todos os detectores autorizados em `FlagPlayer`. `AutoBan` e independente e permanece desligado por padrao.

## Falhas e auditoria

Resource ausente ou não autorizado recebe `untrusted_resource` sem mutação. Quando o banco está pronto, a tentativa gera `risk.export.denied` com operação, resource chamador e motivo, sem evidência ou identifier. Auditorias repetidas da mesma operação/resource são limitadas pelo cooldown para não permitir spam de banco.

Os limites padrão são:

| Campo | Limite |
| --- | ---: |
| pontos por flag | 100 |
| janela confiável | 30000 ms |
| chaves da evidência | 20 |
| profundidade da evidência | 2 |
| string da evidência | 256 caracteres |
| cooldown de auditoria negada | 10000 ms |

Alterações nesses limites e allowlists exigem teste runtime em staging. Autoban permanece desligado até validação específica de falsos positivos.
