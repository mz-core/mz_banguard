# Observador server-side de `weaponDamageEvent`

## Politica de runtime

O observador e registrado exclusivamente no servidor. Seu padrao e:

```lua
mode = 'observe'
cancelHighConfidence = false
runtimeValidated = false
```

Nesse estado nenhum dano e cancelado e nenhuma rotina de kick, ban ou flag de risco punitiva e chamada. O handler consulta somente o export em memoria do `mz_core`; nao existe query por tiro.

A assinatura usada e a oficial da Cfx: `weaponDamageEvent(sender, data)`, com `weaponType`, `weaponDamage`, `hitGlobalId`, `overrideDefaultDamage` e `willKill` no payload. Referencia: https://docs.fivem.net/docs/scripting-reference/events/server-events/

O cancelamento so pode ocorrer para `weapon_damage_no_equipped_weapon` e `weapon_damage_hash_mismatch` quando as tres condicoes forem explicitamente verdadeiras: `mode == 'enforce'`, `cancelHighConfidence == true` e `runtimeValidated == true`. Transicao, sessao nao pronta, payload invalido, hash desconhecido e taxa suspeita nunca sao cancelados por esse caminho.

## Classificacoes

- `weapon_damage_no_equipped_weapon`: dano sem arma oficial equipada e fora da janela de transicao.
- `weapon_damage_hash_mismatch`: arma conhecida diferente da oficial.
- `weapon_damage_unknown_hash`: divergencia cujo hash reportado nao esta no catalogo de nomes.
- `weapon_damage_session_not_ready`: core ou sessao autoritativa indisponivel.
- `weapon_damage_transition_window`: evento proximo de equip/desequip oficial; risco zero por padrao.
- `weapon_damage_payload_invalid`: payload ou hash sem formato valido.
- `weapon_damage_rate_suspect`: arma autorizada, mas taxa server-side acima do limiar configurado.

## Agregacao, risco e retencao

A chave de agregacao combina identidade, classificacao e hashes reportado/oficial. Ocorrencias dentro de `aggregateWindowMs` incrementam contador; evidencias repetidas dentro de `duplicateCooldownMs` sao contabilizadas como suprimidas. Evidencias, notas e incidentes possuem limites configuraveis. A retencao e somente em memoria, por TTL, e nao requer tabela nova.

O risco e explicito e auditavel: pontos base em `riskPoints`, `+10` apos a primeira repeticao e `+20` apos a quinta, limitado a 100. Ele serve para ordenacao e severidade, nao para punicao.

## Limitacoes conhecidas

- `weaponDamageEvent` depende da semantica do artifact/OneSync em staging; por isso enforce exige `runtimeValidated`.
- A documentacao descreve o evento quando um client tenta aplicar dano a entidade com ownership remoto; ele nao deve ser tratado como telemetria completa de todo disparo.
- O catalogo nomeia hashes conhecidos, mas a autoridade real continua sendo o hash do `mz_core`.
- A taxa de eventos deve ser calibrada com armas automaticas e recursos que alterem a cadencia.
- Reiniciar `mz_banguard` descarta incidentes em memoria por design.

## Rollback

O desligamento logico nao exige remover codigo:

```lua
Config.WeaponGuard.enabled = false
Config.WeaponGuard.notifyStaff = false
```

O `mz_core` continua operando sem o BanGuard. Se o resource for parado, o `mz_admin` mantem o restante do menu e apresenta a Central como indisponivel.

## Teste automatizado

A partir de `mz_banguard/tests`, execute `lua weapon_guard_alert_center_harness.lua`. O harness e isolado, nao registra dano real e nao conecta ao banco.
