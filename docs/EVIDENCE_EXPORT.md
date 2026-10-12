# Export de evidencia

O export server-side `ExportSecurityIncidentEvidence(actorSource, incidentId, format)` exige consumer confiavel e a permissao de detalhes. O `mz_admin` oferece JSON e Markdown e copia o conteudo sanitizado para a area de transferencia.

## Conteudo

- metadata, status, severidade, confidence e **incident risk score**;
- player, account e sessao;
- resumo humano e detector;
- thresholds, samples, timeline, mitigacao e source history;
- incidentes relacionados, correlacao de crash, LAB e acoes Staff.

## Sanitizacao

O export nao inclui credenciais de banco, password, API key, bearer, cookies, webhook secret, IP ou tokens crus. Identifiers aparecem somente mascarados. A mesma sanitizacao profunda aplicada na persistencia e reutilizada no pacote externo.

Formatos aceitos: `json`, `markdown`, `md` e `txt`. Cada export gera uma acao persistida e um audit de acesso.

