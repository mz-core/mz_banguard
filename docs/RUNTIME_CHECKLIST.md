# Checklist runtime do MZ BanGuard 1.2

Testes não executados não podem ser marcados como aprovados.

## Preparação segura

- [ ] Usar staging descartável, sem produção ou VPS.
- [ ] Criar backup verificável do banco de staging.
- [ ] Confirmar `AutoCreateMissingTables = true` e `AutoMigrateExistingTables = false`.
- [ ] Em banco vazio, permitir que o resource crie somente as seis tabelas ausentes.
- [ ] Em schema antigo, revisar manualmente `sql/upgrade_1_1_mysql.sql`; não habilitar migration automática.
- [ ] Confirmar retenção, cloud, webhook e autoban desativados.
- [ ] Iniciar `oxmysql`, `mz_core`, `mz_menu`, `mz_banguard` e `mz_admin` nessa ordem.
- [ ] Confirmar no console que não houve warning de schema.

## Prontidão

- [ ] Em banco vazio, as seis tabelas são criadas e `IsReady()` retorna `true`.
- [ ] Falha de permissão SQL durante a criação mantém `IsReady() = false`, oculta o menu e nega conexão sem erro Lua.
- [ ] Tabela existente sem coluna obrigatória não é alterada e retorna `missing_column:*`.
- [ ] Tabela existente sem índice obrigatório não é alterada e retorna `missing_index:*`.
- [ ] Com schema completo, `IsReady()` retorna `true`.
- [ ] Resource não confiável recebe `untrusted_resource` nos exports de mutação e leitura.
- [ ] Parar `mz_core` faz a integração falhar fechada.

## Ban

- [ ] Staff sem `staff.players.ban` não vê a opção e chamada direta é negada.
- [ ] Administrador com permissão bane player comum online por `/ban ID 7d motivo`.
- [ ] O menu do player online cria ban permanente e temporário.
- [ ] Self-target, Owner, Staff igual e Staff superior são negados.
- [ ] Staff inferior é elegível.
- [ ] Duração inválida, acima de 3650 dias e motivo menor que 3 são negados.
- [ ] Player desconectado entre seleção e confirmação é negado.
- [ ] Ban já ativo é recusado com o Public ID preservado.
- [ ] Falha transacional não cria ban parcial e não executa `DropPlayer`.
- [x] Sucesso retorna Public ID, remove o alvo e impede sua reconexão.
- [ ] Auditorias `ban.created.integration` e `admin.ban.create.completed` existem sem identifiers/tokens.

## Consulta e revogação

- [ ] Staff sem `staff.bans.view` não lista nem consulta por chamada direta.
- [ ] Lista filtra ativos/revogados e busca Public ID/nome.
- [ ] Paginação usa 25 itens e preserva filtros.
- [ ] DTO não contém identifiers, tokens, IP, evidence ou IDs internos.
- [ ] Administrador sem `staff.bans.revoke` não vê revogação e chamada direta é negada.
- [ ] Gerente Staff com `staff.bans.revoke` revoga com motivo.
- [ ] Public ID inválido, inexistente ou já revogado é negado.
- [ ] Mensagens distinguem Public ID inexistente, ban já revogado e ban expirado.
- [ ] Falha transacional mantém ban e vínculos ativos.
- [x] Player revogado consegue conectar novamente.
- [ ] Auditorias `ban.revoked.integration` e `admin.ban.revoke.completed` existem.

## Compatibilidade

- [ ] Resource não listado recebe `untrusted_resource` nos três exports de risco e não altera score/janela.
- [ ] Consumer listado somente em `FlagPlayer` não consegue chamar `RegisterTrustedAction` ou `GetRiskScore`.
- [ ] `FlagPlayer` autorizado limita pontos, tamanho/profundidade da evidência e registra `created_by_resource`.
- [ ] `RegisterTrustedAction` autorizado limita duração e preserva o wildcard histórico somente dentro da janela.
- [ ] `GetRiskScore` autorizado recusa source offline.
- [ ] Negação por resource gera `risk.export.denied` sem identifier ou evidência sensível.
- [ ] `FlagPlayer`, `RegisterTrustedAction` e `GetRiskScore` preservam assinatura para consumers explicitamente autorizados.
- [ ] Comandos ACE históricos continuam registrados.
- [ ] Staff sem ACE usa `/ban` quando possui `staff.players.ban`.
- [ ] Staff sem ACE usa `/unban` quando possui `staff.bans.revoke`.
- [ ] ACE `mzban.ban` isolada não permite `/ban` sem `staff.players.ban`.
- [ ] ACE `mzban.unban` isolada não permite `/unban` sem `staff.bans.revoke`.
- [ ] `/baninfo` e `/banflags` exigem `staff.bans.view` e negam alvo Staff superior.
- [ ] `/banlookup` é aceito somente por console ou `group.mz_owner`.
- [x] `/ban` e `/unban` executam uma única vez, sem notificações ou mutações duplicadas. Aprovado pelo operador em 2026-07-28.
- [ ] Console continua criando/revogando com auditoria na mesma transação.
- [ ] ACE `mzban.*` não concede permissões `staff.*` no `/admin`.
- [ ] Cloud, webhook, retenção e autoban permanecem desligados durante os testes.

## Evidência

Registrar identidade, cargo, permissões, sources, Public ID, duração, resultado observado, registros de auditoria e trecho relevante do console. Nenhum item runtime foi aprovado apenas pela validação estática.

Fluxo principal de ban e unban aprovado em runtime em 2026-07-28 conforme confirmação do usuário: Public ID gerado, alvo removido/bloqueado, revogação pelo `/admin` e reconexão liberada. Casos negativos, hierarquia, auditoria e falha de banco continuam independentes.

Os nomes canônicos `/ban` e `/unban`, registrados somente pelo BanGuard, foram aprovados pelo operador em 2026-07-28. As negativas de permissão/hierarquia e falhas transacionais permanecem pendentes.
# CitizenID contextual

- [ ] Criar ban online e confirmar o CitizenID correto no detalhe e na listagem.
- [ ] Buscar o ban pelo CitizenID no menu administrativo.
- [ ] Confirmar que o ban continua bloqueando por identifiers/tokens, mesmo antes da selecao de personagem.
- [ ] Com cloud habilitada em ambiente de teste, confirmar que `target_citizenid` nao e enviado na evidencia.
