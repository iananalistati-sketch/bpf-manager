# Fase 0 — Estabilização da Engenharia

## Objetivo

Interromper o ciclo de correção reativa no ambiente oficial e criar uma esteira que encontre falhas previsíveis antes do checkpoint manual do usuário.

## Problema identificado

O gate local cobre PGlite, build, lint e Playwright, mas não reproduz integralmente:

- PostgREST hospedado;
- formato real de JWT/settings do Supabase;
- Auth hospedado;
- Edge Functions;
- `service_role`;
- grants/RLS efetivos do projeto remoto;
- redirects de convite/recuperação;
- cadeia Auth -> RPC -> membership -> auditoria.

Por isso, uma validação local verde não é suficiente para liberar fluxos que dependem desses componentes.

## Decisão atual de ambiente

Por decisão do projeto, não será criada uma branch/projeto Supabase de homologação neste momento. O gate hospedado usará o projeto oficial com proteções adicionais.

A consequência é que o gate oficial deve operar em dois níveis:

```text
Nível 1 — read-only por padrão
Auth login -> memberships -> tenant -> plano -> entitlements

Nível 2 — mutation controlada somente quando necessária
Edge -> Auth invite -> RPC -> membership -> profile -> audit -> cleanup
```

Mutation no ambiente oficial nunca é implícita: exige flags explícitas, service_role local, e-mail dedicado e confirmação exata do project ref.

## Nova esteira obrigatória

```text
implementação
  -> validate:local
  -> test:integration read-only no Supabase oficial
  -> quando houver fluxo de escrita: mutation smoke controlada + cleanup
  -> aprovação dos gates 07/08/09
  -> deploy/ajuste oficial
  -> smoke pós-deploy
  -> checkpoint visual do usuário somente no final
```

Como o mesmo projeto é usado para integração e operação, qualquer mutation smoke deve ser pequena, identificável, auditável e removível.

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

## Segurança do harness hospedado no projeto oficial

Para executar contra o projeto oficial o teste exige:

```text
BPF_INTEGRATION_ENVIRONMENT=official
BPF_INTEGRATION_ALLOW_PRODUCTION=YES
```

Por padrão ele continua read-only.

Mutation completa exige adicionalmente:

```text
BPF_INTEGRATION_ALLOW_MUTATIONS=YES
BPF_INTEGRATION_PRODUCTION_MUTATION_CONFIRM=yequhfvcbwnxmqobgumu
BPF_INTEGRATION_SERVICE_ROLE_KEY=<somente local>
BPF_INTEGRATION_INVITE_EMAIL=<e-mail exclusivo de smoke>
```

O harness:

- não executa mutation sem todas as confirmações;
- exige `service_role` somente no arquivo local ignorado pelo Git;
- impede usar o mesmo e-mail do administrador;
- verifica Auth, membership, perfil e auditoria depois do convite;
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

A Edge Function deve retornar e registrar informação suficiente para diagnóstico sem expor detalhes sensíveis ao usuário:

- código de erro por etapa;
- `requestId`/correlation id;
- distinção entre Auth, tenant, permissão, perfil, plano, persistência e auditoria;
- mensagem funcional limpa no frontend.

## Modelo de dados

Também faz parte da estabilização reduzir o período de coexistência entre:

- legado: `usuarios` + `usuario_perfis`;
- canônico SaaS: `usuario_empresas` + `usuario_empresa_perfis`.

Enquanto houver dual-write, toda mutation deve testar atomicidade e sincronismo. A remoção gradual da dependência do legado será tratada em migration própria, sem editar migrations já aplicadas.

## Critério de saída da Fase 0

A fase termina quando:

1. migrations são auto-descobertas no harness;
2. `validate:local` está verde;
3. `test:integration` read-only está verde contra o oficial;
4. o convite completo passa em mutation smoke controlada e faz cleanup;
5. erros da Edge têm códigos/correlação suficientes para diagnóstico;
6. Agentes 07, 08 e 09 exigem evidência hospedada para fluxos hosted-only;
7. a dependência do dual-write legado está mapeada e com plano de retirada;
8. somente então novas funcionalidades são retomadas.
