# LAB mode

LAB marca uma sessao ativa para teste adversarial autorizado. A identidade e resolvida pelo `mz_core` e persistida em `mz_security_lab_subjects` com `citizenid`, `account_id`, `session_id`, inicio, expiracao, motivo e autorizador.

## Comportamento

- O incidente recebe `lab=true` e badge na Central.
- Timeline e snapshot usam limites ampliados.
- `FlagPlayer` continua registrando o sinal, mas ignora AutoKick/AutoBan para o subject LAB.
- O Weapon Guard nao cancela dano do subject LAB mesmo que o modo enforce seja armado.
- Mitigacoes defensivas que protegem terceiros podem continuar; nenhum novo enforcement foi habilitado nesta Wave.
- Expiracao e desativacao sao auditadas e persistidas.

O `mz_admin` usa `mz_banguard.alerts.lab` e o export `SetSecurityLabSubject`. Pela Central, Staff autorizada ativa LAB por 60 minutos ou desativa, sempre informando motivo auditavel. A marcacao e por sessao quando `session_id` existe; reconectar nao herda automaticamente um LAB antigo.

