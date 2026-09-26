# Decisão Arquitetural — Marco 1.5 / Tenancy SaaS

## Status

**Gate 1 — Arquitetura consolidada / pronta para desenho de migrations.**

Esta decisão foi consolidada considerando Produto/BPF, Dados/Supabase, Segurança/Permissões, Frontend/UX, Auditoria/Governança e SaaS/Trial/Planos.

## 1. Problema

O modelo atual funciona para um usuário vinculado diretamente a uma empresa, mas a fundação SaaS exige:

- identidade que exista antes da contratação;
- trial isolado;
- conversão para cliente;
- uma pessoa com múltiplas empresas;
- RBAC por empresa;
- tenant ativo;
- planos e limites por empresa;
- assinatura/provisionamento;
- compatibilidade com o Marco 1 já remoto.

A estrutura atual contém `usuarios.empresa_id`, `usuarios.unidade_id` e `usuario_perfis`, e `v_meu_contexto` deriva autorização diretamente desses campos. Eles não podem ser removidos imediatamente.

## 2. Decisão principal

Adotar progressivamente o modelo:

```text
auth.users
   ↓
usuarios                    identidade global
   ↓
usuario_empresas            membership empresarial
   ↓
usuario_empresa_perfis      RBAC contextual ao membership
   ↓
perfis → perfil_permissoes → permissoes
```

O tenant ativo será um contexto validado pelo backend, não um `empresa_id` confiado ao cliente.

## 3. Tabelas novas propostas

### 3.1 `usuario_empresas`

Campos alvo:

- `id uuid primary key`;
- `usuario_id uuid not null`;
- `empresa_id uuid not null`;
- `unidade_id uuid null`;
- `status text not null` — inicialmente `pendente | ativo | inativo | bloqueado`;
- `is_owner boolean not null default false`;
- `created_at`;
- `updated_at`;
- `created_by`;
- `origem text` opcional — `legacy | trial | convite | provisionamento`.

Constraints:

- `unique(usuario_id, empresa_id)`;
- unidade deve pertencer à mesma empresa;
- owner deve possuir membership ativo para operar;
- membership não pode autorizar acesso se identidade global estiver inativa/bloqueada.

### 3.2 `usuario_empresa_perfis`

Campos:

- `usuario_empresa_id uuid`;
- `perfil_id uuid`;
- `created_at`;
- `created_by`;
- PK composta `(usuario_empresa_id, perfil_id)`.

Regras:

- perfil customizado deve pertencer à mesma empresa do membership;
- perfil de sistema pode ser global;
- perfil deve estar ativo;
- teto de delegação continua obrigatório;
- proteção do último administrador deve migrar para membership, não identidade global.

### 3.3 `workspaces_trial`

O trial será associado a uma empresa/workspace real isolado, não a um ambiente compartilhado mutável.

Campos conceituais:

- `id`;
- `empresa_id`;
- `owner_membership_id`;
- `status` — `ativo | expirado | convertido | cancelado`;
- `iniciado_em`;
- `expira_em`;
- `convertido_em`;
- `template_versao`;
- `readonly_em`;
- timestamps.

A duração de 14 dias deve vir de configuração, não de constraint fixa.

### 3.4 `planos`

Campos conceituais:

- `id`;
- `codigo` estável;
- `nome`;
- `descricao`;
- `ativo`;
- `ordem_exibicao`;
- `metadata jsonb` opcional.

Nomes Basic/Professional/Business/Enterprise são seed inicial, não lógica estrutural.

### 3.5 `plano_entitlements`

Modelo chave/valor tipado ou equivalente, com suporte mínimo a:

- boolean;
- inteiro;
- texto quando necessário.

Exemplos:

- `usuarios_ativos.max = 10`;
- `unidades.max = 1`;
- `producao.enabled = false`.

Constraints devem impedir duplicidade por `(plano_id, chave)`.

### 3.6 `assinaturas`

Campos conceituais:

- `id`;
- `empresa_id`;
- `plano_id`;
- `status`;
- `provider`;
- `provider_customer_id`;
- `provider_subscription_id`;
- `periodo_inicio`;
- `periodo_fim`;
- `grace_until`;
- `cancelada_em`;
- timestamps.

A empresa deve ter no máximo uma assinatura operacional corrente por regra controlada.

### 3.7 `provisionamento_eventos`

Tabela interna/idempotency ledger para eventos de provisionamento/billing.

Campos conceituais:

- `id`;
- `provider`;
- `external_event_id`;
- `tipo`;
- `status`;
- `empresa_id`;
- `payload_hash` ou metadata segura;
- `processado_em`;
- `erro` sanitizado;
- timestamps.

`unique(provider, external_event_id)` impede duplicação de processamento.

## 4. Identidade global

Durante a primeira fase do Marco 1.5:

- manter `usuarios.empresa_id`, `usuarios.unidade_id`, `usuarios.status` e `usuarios.ativo` por compatibilidade;
- criar/backfill `usuario_empresas` para todo usuário atualmente vinculado;
- criar/backfill `usuario_empresa_perfis` com base em `usuario_perfis`;
- não mudar ainda o trigger de Auth para conceder empresa/perfil;
- novos cadastros públicos continuam nascendo sem privilégio empresarial até o provisionamento do trial.

Longo prazo:

- `usuarios.ativo/status` passa a representar apenas estado global da identidade;
- status empresarial passa a viver no membership;
- empresa/unidade deixam de ser atributos definitivos da identidade.

## 5. Tenant ativo

### Decisão

Não armazenar tenant ativo como autorização permanente no `user_metadata`.

Na primeira implementação, usar uma RPC/contrato backend que receba `empresa_id` desejada e valide membership ativo. O contexto resolvido deve retornar somente empresas autorizadas.

Alternativas técnicas permitidas para sessão:

- claim controlado pelo servidor com refresh de token;
- contexto por request validado por helper;
- sessão server-side futura.

A escolha específica será feita na migration/contrato seguinte, mas nenhuma opção pode confiar cegamente em parâmetro de frontend.

## 6. Contexto autenticado

`v_meu_contexto` atual é singular e não suporta múltiplas empresas. A transição prevista é:

1. manter `v_meu_contexto` compatível durante backfill;
2. criar uma nova visão/RPC de memberships disponíveis, por exemplo `v_meus_vinculos`;
3. criar um novo contexto por tenant, por exemplo `meu_contexto_empresa(p_empresa_id)`;
4. migrar frontend e serviços;
5. somente depois substituir/depreciar o contrato antigo.

A interface TypeScript atual (`MeuContexto`) continuará válida na fase de compatibilidade e será evoluída em uma mudança contratual explícita.

## 7. RBAC

A permissão efetiva será calculada por:

```text
identidade global válida
+ membership ativo para a empresa
+ perfil ativo e compatível com o membership
+ perfil_permissoes
```

`usuario_perfis` será mantido temporariamente apenas para compatibilidade.

Novas funcionalidades do Marco 1.5 devem preferir `usuario_empresa_perfis` assim que o Gate de migração confirmar o backfill.

## 8. Planos e limites

Limites iniciais:

- Basic: `usuarios_ativos.max=10`, `unidades.max=1`;
- Professional: `usuarios_ativos.max=30`, `unidades.max=3`;
- Business: `usuarios_ativos.max=75`, `unidades.max=10`;
- Enterprise: valores configuráveis.

A validação deve ocorrer no backend antes de:

- ativar/convidar membership acima do limite;
- criar unidade acima do limite;
- usar recurso desabilitado por entitlement.

O frontend apenas informa o limite e orienta upgrade.

## 9. Trial

### Provisionamento inicial

Cadastro público válido deve poder disparar provisionamento server-side de:

1. empresa/workspace trial;
2. membership owner;
3. perfil administrativo inicial limitado ao workspace;
4. assinatura lógica `trialing` ou estado equivalente;
5. entitlements do trial;
6. seed demo versionado;
7. evento de auditoria.

### Isolamento

Cada trial terá empresa própria. Nenhum dado operacional demo será compartilhado de forma mutável entre prospects.

### Expiração

Ao expirar:

- bloquear mutações operacionais não permitidas;
- manter acesso readonly quando política comercial permitir;
- preservar dados por janela de retenção configurável;
- não apagar identidade global automaticamente.

## 10. Conversão trial → cliente

A conversão deve ser idempotente e preferencialmente manter a mesma `empresa_id`.

Isso evita migrar todos os dados operacionais do trial para outro tenant.

A rotina deverá:

- marcar trial como convertido;
- criar/ativar assinatura;
- aplicar novo plano/entitlements;
- remover/arquivar dados exclusivamente demo conforme política;
- preservar dados próprios;
- confirmar owner/admin;
- iniciar onboarding real quando necessário;
- auditar a conversão.

## 11. Pagamento

Neste marco não haverá gateway obrigatório.

Será criado contrato para futuro webhook:

```text
provedor → Edge Function/webhook → valida assinatura do provedor → registra evento idempotente → provisiona/converte → audita
```

O frontend nunca chama diretamente uma função que “vira administrador porque pagou”.

## 12. Frontend

Mudanças previstas futuramente:

- fluxo público de cadastro/trial;
- identificação visual de ambiente demo;
- indicador de dias restantes;
- seletor de empresa quando houver múltiplos memberships;
- tela de planos/limites;
- estado de trial expirado/readonly;
- onboarding da empresa;
- mensagens de limite atingido com ação de upgrade.

A UI não deve misturar permissão negada com recurso não contratado; são estados diferentes.

## 13. Auditoria

Eventos obrigatórios do Marco 1.5:

- membership criado/ativado/inativado;
- tenant selecionado quando relevante à segurança;
- trial criado/expirado/convertido;
- assinatura criada/alterada/cancelada;
- plano alterado;
- provisionamento processado/falhou;
- owner/admin inicial atribuído;
- limite bloqueou operação relevante.

## 14. Segurança adversarial exigida

O Agente 09 deve testar pelo menos:

- usar `empresa_id` de membership inexistente;
- manipular tenant ativo;
- acessar tenant B mantendo token de usuário da empresa A;
- inserir perfil de outra empresa no membership;
- duplicar owner/admin por reprocessamento;
- exceder limite por chamada RPC direta;
- usar recurso sem entitlement por chamada direta;
- usuário com entitlement mas sem RBAC;
- trial expirado tentando escrever;
- trial tentando ler empresa cliente;
- manipulação de plano/assinatura pelo cliente;
- webhook repetido;
- webhook sem assinatura válida quando gateway existir.

## 15. Ordem de implementação aprovada

### Fase 1 — Membership compatibility

- tabelas `usuario_empresas` e `usuario_empresa_perfis`;
- backfill remoto seguro;
- helpers de leitura do membership;
- testes de isolamento;
- nenhum comportamento visual novo obrigatório.

### Fase 2 — Tenant/contexto

- listagem de memberships;
- novo contrato de contexto empresarial;
- adaptação gradual de auth/services;
- seletor somente quando houver múltiplos vínculos.

### Fase 3 — Planos/entitlements

- catálogo e seeds iniciais;
- resolver entitlement efetivo;
- validar limites no backend.

### Fase 4 — Trial/provisionamento

- cadastro público;
- provisionamento de workspace;
- seed demo;
- expiração/readonly;
- conversão manual/teste inicialmente.

### Fase 5 — Billing contract/onboarding

- estrutura de assinatura e idempotência;
- onboarding;
- contrato para futuro gateway de pagamento.

## 16. Bloqueadores antes da primeira migration

Nenhum bloqueador arquitetural conhecido, desde que a implementação respeite:

- compatibilidade com Marco 1;
- backfill antes de trocar fonte de autorização;
- dupla validação durante transição;
- migrations remotas imutáveis;
- plano separado de RBAC;
- tenant validado no backend;
- trial isolado.

## 17. Próxima ação

A primeira implementação do Marco 1.5 deve ser limitada à **Fase 1 — Membership compatibility**.

Ela deve criar o novo modelo e backfill sem alterar ainda a experiência do usuário nem remover contratos existentes.

Isso reduz risco e cria o alicerce para as etapas seguintes.

---

**Decisão:** aprovada para implementação incremental  
**Data:** 18/09/2026
