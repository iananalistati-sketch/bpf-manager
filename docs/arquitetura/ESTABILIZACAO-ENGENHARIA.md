# Fase 0 — Estabilização da Engenharia

## Objetivo

Interromper o ciclo de correção reativa em produção/homologação funcional e criar uma esteira que encontre falhas previsíveis antes do checkpoint do usuário.

## Problema identificado

O gate local atual cobre PGlite, build, lint e Playwright, mas não reproduz integralmente:

- PostgREST hospedado;
- formato real de JWT/settings do Supabase;
- Auth hospedado;
- Edge Functions;
- `service_role`;
- grants/RLS efetivos do projeto remoto;
- redirects de convite/recuperação;
- cadeia Auth -> RPC -> membership -> auditoria.

Por isso, uma validação local verde não é suficiente para liberar fluxos que dependem desses componentes.

## Nova esteira obrigatória

```text
implementação
  -> validate:local
  -> deploy em Supabase de homologação
  -> test:integration
  -> Playwright/smoke contra homologação
  -> aprovação dos gates 07/08/09
  -> deploy principal
  -> smoke pós-deploy
```

## Comandos

### Gate local

```powershell
npm.cmd run validate:local
```

Mantém:

- validação das fontes SQL;
- reconstrução PGlite;
- aplicação automática de todas as migrations versionadas;
- testes SQL;
- build;
- lint;
- E2E local.

`npm.cmd run validate` continua apontando para esse gate por compatibilidade.

### Gate hospedado

```powershell
npm.cmd run test:integration
```

Usa `.env.integration.local` e valida em Supabase real:

- login Auth;
- `meus_vinculos`;
- `meu_contexto_empresa`;
- resumo de plano;
- entitlements;
- opcionalmente, mutation completa de convite.

### Gate de release

```powershell
npm.cmd run validate:release
```

Executa primeiro o gate local e depois o hospedado.

## Segurança do harness hospedado

O teste de integração:

- exige `BPF_INTEGRATION_ENVIRONMENT=homologation`;
- recusa por padrão o project ref principal atual;
- não executa mutation sem `BPF_INTEGRATION_ALLOW_MUTATIONS=YES`;
- exige `service_role` somente no arquivo local ignorado pelo Git;
- exige e-mail de teste dedicado para convite;
- remove o usuário criado ao fim do smoke quando possível.

Nunca versionar `.env.integration.local`.

## Migrations

A lista de migrations deixa de ser manual.

`scripts/test-db.mjs` descobre automaticamente todos os arquivos:

```text
supabase/migrations/YYYYMMDDHHMMSS_nome.sql
```

em ordem cronológica. Uma migration nova passa automaticamente a fazer parte do harness local.

O preflight também valida o padrão dos nomes e a ordenação.

## Fluxos críticos que exigem teste hospedado

Qualquer mudança que envolva um dos itens abaixo não pode ser liberada apenas com PGlite:

- Auth;
- Edge Function;
- `service_role`;
- hosted JWT/PostgREST;
- redirects/e-mail;
- mutation multi-tabela;
- RLS/grants cuja role efetiva é diferente da simulada localmente;
- Storage;
- webhook/billing futuro.

## Convite como primeiro fluxo de prova

O convite será usado como fluxo piloto do novo gate:

```text
admin autenticado
-> Edge admin-invite-user
-> Auth invite
-> RPC server-only
-> usuarios
-> usuario_empresas
-> usuario_empresa_perfis
-> auditoria_eventos
-> resposta
-> cleanup do smoke
```

O gate só é verde se a cadeia chegar ao fim.

## Observabilidade

Próxima etapa desta fase:

- padronizar códigos de erro por etapa da Edge Function;
- incluir `requestId`/correlation id em resposta e logs;
- diferenciar erro de Auth, tenant, perfil, plano, persistência e auditoria;
- evitar mensagens genéricas que escondam o ponto de falha.

## Modelo de dados

Também faz parte da estabilização reduzir o período de coexistência entre:

- legado: `usuarios` + `usuario_perfis`;
- canônico SaaS: `usuario_empresas` + `usuario_empresa_perfis`.

Enquanto houver dual-write, toda mutation deve testar atomicidade e sincronismo. A remoção gradual da dependência do legado será tratada em migration própria, sem editar migrations já aplicadas.

## Critério de saída da Fase 0

A fase termina quando:

1. migrations são auto-descobertas no harness;
2. `validate:local` está verde;
3. existe ambiente Supabase dedicado de homologação;
4. `test:integration` está verde nesse ambiente;
5. convite completo passa sem intervenção manual no banco;
6. erros da Edge têm códigos/correlação suficientes para diagnóstico;
7. Agentes 07, 08 e 09 exigem evidência hospedada para fluxos hosted-only;
8. somente então novas funcionalidades são retomadas.
