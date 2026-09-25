# Marco 1.5 — Fase 3 / Planos e Entitlements

## Status

**Implementação preparada para Gate local (`npm.cmd run validate`). Ainda não aplicada no Supabase remoto.**

## Decisões consolidadas

- plano comercial e RBAC continuam independentes;
- nomes comerciais de plano não participam de RLS nem de regras de autorização;
- o vínculo comercial atual da empresa é representado por `empresa_planos` nesta fase;
- `empresa_planos` não comprova pagamento e será mantido futuramente pelo fluxo de assinatura/provisionamento;
- nenhuma empresa existente recebe plano automaticamente nesta migration;
- ausência de plano/entitlement não bloqueia operações durante a transição;
- após a empresa receber um plano, limites quantitativos definidos são impostos no banco, não somente no frontend.

## Estruturas

### `planos`

Catálogo configurável com código estável, nome comercial, descrição, estado e ordem de exibição.

Seeds arquiteturais iniciais:

- `basic`;
- `professional`;
- `business`;
- `enterprise`.

### `plano_entitlements`

Entitlements tipados por chave:

- `booleano`;
- `inteiro`;
- `texto`.

A constraint garante que somente o campo de valor compatível com o tipo possa ser preenchido.

Seeds quantitativos aprovados:

| Plano | `usuarios_ativos.max` | `unidades.max` |
| --- | ---: | ---: |
| Basic | 10 | 1 |
| Professional | 30 | 3 |
| Business | 75 | 10 |
| Enterprise | configurável | configurável |

Nenhum limite fixo é inventado para Enterprise.

### `empresa_planos`

Relação atual empresa → plano. Não representa assinatura, cobrança, checkout nem confirmação de pagamento.

## Contrato de leitura

RPC pública:

`meu_plano_entitlements(p_empresa_id)`

Regras:

- somente `authenticated` executa;
- `anon` não executa;
- tabelas comerciais não ficam disponíveis para leitura direta do cliente;
- o `empresa_id` informado nunca concede acesso sozinho;
- o backend exige identidade global ativa e membership ativo no tenant solicitado.

## Enforcement de limites

Triggers internos e owner restrito `bpf_plan_enforcer` validam:

- criação/ativação de unidade;
- ativação/vinculação de usuário no modelo legado durante a transição;
- criação/ativação de membership empresarial.

O consumo de usuários usa união distinta entre o estado legado e memberships para evitar dupla contagem do mesmo usuário durante a migração.

## Segurança

Roles restritos:

- `bpf_entitlement_reader`: leitura do plano/entitlements do próprio tenant;
- `bpf_plan_enforcer`: leitura mínima necessária para enforcement, sem login e sem bypass RLS.

Nenhum desses roles recebe login, superuser, criação de banco/role ou `BYPASSRLS`.

## Gate de testes

A suíte deve comprovar:

- isolamento cross-tenant;
- `anon` sem execução;
- `authenticated` sem SELECT direto nas tabelas de plano;
- integridade dos valores tipados;
- seeds quantitativos aprovados;
- Enterprise sem limite fixo inventado;
- limite de unidades no backend;
- limite de usuários no backend, incluindo membership;
- empresa ainda sem plano sem regressão durante a transição;
- cadeia acumulada de migrations e testes verdes.

Após o Gate local, revisar novamente Banco/Migrations, segurança adversarial e estado remoto antes do deploy.
