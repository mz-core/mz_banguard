# Modelo de evidencia

Todo sinal passa por `MZBan.Incidents.Record`. O detector continua enviando seus campos historicos, e o BanGuard acrescenta `canonical` sem renomear codigos existentes:

```lua
canonical = {
  detector = { code, version, threshold, window_ms, label },
  subject = { citizenid, account_id, session_id, source },
  observation = { first_seen_at, last_seen_at, count, peak_rate },
  context = {},
  samples = {},
  mitigation = { attempted, applied, result }
}
```

Os campos planos permanecem no sample para compatibilidade. `source` e apenas contexto de sessao; a identidade persistente usa `citizenid`, `account_id` e `session_id` resolvidos server-side pelo `mz_core`.

## Limites e privacidade

- Evidencia aceita somente valores escalares e tabelas limitadas a cinco niveis e 128 entradas sanitizadas.
- Strings tecnicas sao truncadas; NaN e infinito sao descartados.
- Chaves de password, API key, bearer, cookie, webhook, token, IP e connection string sao removidas.
- Identifiers nao entram no snapshot SQL; a UI/export recebe apenas tipos e valores mascarados.
- A lista `evidence` continua limitada por `SecurityAlerts.maxEvidencePerIncident`.

Mitigacao e evidencia sao fatos separados. `observe_only` nao significa inocencia nem culpa; significa apenas que o detector nao aplicou punicao.

