# Marco 1.5 — Fundação SaaS

## Objetivo

Evoluir a fundação atual do BPF Manager para suportar trial demonstrativo, contratação por plano, identidade global, múltiplos vínculos empresariais, provisionamento seguro e futura experiência mobile, antes da expansão dos grandes módulos operacionais.

## Motivação

A arquitetura atual associa diretamente o usuário a uma empresa/unidade. Isso funciona para o estágio administrativo inicial, mas limita:

- trial sem empresa contratante definitiva;
- conversão de prospect em cliente;
- uma identidade com acesso a múltiplas empresas;
- consultorias/auditorias multiempresa;
- cobrança por empresa;
- planos e limites;
- mudança de tenant ativo;
- futuro app mobile.

O Marco 1.5 deve corrigir essa base antes do Marco 2.

## Escopo funcional

### Bloco A — Identidade e membership

- separar identidade global de vínculo empresarial;
- introduzir membership usuário ↔ empresa;
- mover unidade/status/perfis de acesso para o contexto do membership quando aplicável;
- permitir tenant ativo;
- preservar compatibilidade com os usuários/empresas já existentes;
- preparar uma identidade para possuir múltiplos vínculos.

### Bloco B — Trial e demonstração

- cadastro público controlado;
- provisionamento de workspace trial individual;
- template de dados demonstrativos;
- duração inicial de 14 dias configurável;
- estado de trial;
- expiração com modo restrito/readonly;
- fluxo “Começar com minha empresa”;
- preservação controlada de dados próprios na conversão.

### Bloco C — Planos, limites e entitlements

- catálogo de planos configurável;
- limites por plano;
- recursos habilitados por plano;
- validação backend de usuários ativos e unidades;
- modelo inicial Basic / Professional / Business / Enterprise;
- não hardcodar nomes de plano em RLS ou regras estruturais.

### Bloco D — Assinatura e provisionamento

- assinatura vinculada à empresa/workspace;
- estados de assinatura;
- provedor de pagamento abstrato;
- rotina idempotente de provisionamento/conversão;
- owner/administrador inicial por empresa;
- trilha de auditoria;
- estrutura pronta para webhook, sem exigir gateway real neste marco.

### Bloco E — Onboarding

- onboarding inicial da empresa;
- dados organizacionais mínimos;
- unidade principal;
- estrutura/setores;
- responsável técnico;
- usuários iniciais;
- estado de conclusão do onboarding.

## Fora do escopo inicial

- cobrança real em produção;
- definição final de preços;
- emissão fiscal;
- prorrata financeira;
- app mobile nativo;
- SSO Enterprise;
- integrações comerciais específicas.

## Decisões de produto aprovadas

- trial inicial de 14 dias, configurável;
- prospect deve conseguir explorar um ambiente funcional antes de contratar;
- workspace trial isolado por prospect;
- dados demonstrativos devem ser claramente identificados;
- dados próprios podem ser preservados na conversão;
- limite comercial principal por usuários ativos, não sessões simultâneas;
- sessões simultâneas ficam como possível controle técnico de segurança;
- plano e perfil são conceitos diferentes;
- assinatura pertence à empresa/workspace;
- confirmação de pagamento e provisionamento futuro serão server-side;
- frontend nunca concede privilégio por retorno visual de checkout.

## Modelo comercial inicial para arquitetura

| Plano | Usuários ativos | Unidades |
| --- | ---: | ---: |
| Basic | 10 | 1 |
| Professional | 30 | 3 |
| Business | 75 | 10 |
| Enterprise | configurável | configurável |

Os valores são parâmetros iniciais para modelagem e testes, não contrato comercial definitivo.

## Sequência técnica proposta

1. documentar estado atual e estratégia de migração;
2. criar novo modelo de memberships sem remover colunas legadas imediatamente;
3. backfill dos vínculos atuais;
4. adaptar helpers de autorização/RLS para tenant ativo + membership;
5. migrar RBAC para vínculo empresarial;
6. criar catálogo de planos/entitlements;
7. criar trial/workspace/provisionamento;
8. adaptar frontend para seleção de contexto e onboarding;
9. adicionar testes adversariais multi-tenant/multi-membership;
10. só depois retirar dependências legadas de `usuarios.empresa_id`/`unidade_id`.

## Estratégia de migração

A transição deve ser incremental e reversível por novas migrations.

Não remover imediatamente `usuarios.empresa_id` e `usuarios.unidade_id` porque o Marco 1 já está aplicado remotamente e depende delas.

Fases previstas:

- **compatibilidade:** criar memberships e espelhar/backfill do estado atual;
- **dupla leitura controlada:** novos helpers passam a usar membership, mantendo compatibilidade;
- **migração funcional:** frontend/RPCs passam a operar pelo vínculo;
- **descontinuação:** somente após testes e deploy estável, remover dependências legadas por migration futura.

## Critérios de aceite

- usuário atual continua acessando sua empresa sem regressão;
- identidade pode possuir dois vínculos empresariais sem vazamento de dados;
- tenant ativo é validado no backend;
- perfil/permissão é específico do vínculo empresarial;
- trial não recebe privilégios fora de seu workspace;
- conversão trial → cliente é idempotente;
- limites do plano são impostos no backend;
- plano não substitui RBAC;
- nenhuma `service_role` aparece no frontend;
- auditoria registra provisionamento, conversão, assinatura e mudanças críticas;
- migrations acumuladas passam pelo Agente 08;
- cenários de bypass passam pelo Agente 09;
- contratos frontend/backend passam pelo Agente 07;
- `npm.cmd run validate` passa antes de checkpoint.

## Agentes obrigatórios neste marco

- Agente 00 — Orquestração;
- Agente 01 — Produto/BPF;
- Agente 02 — Dados/Supabase;
- Agente 03 — Segurança/Permissões;
- Agente 04 — Frontend/UX;
- Agente 05 — QA;
- Agente 06 — Auditoria/Governança;
- Agente 07 — Validação de Fontes;
- Agente 08 — Banco/Migrations;
- Agente 09 — Segurança Adversarial;
- Agente 10 — SaaS/Trial/Planos/Provisionamento.

## Gate 1 — Arquitetura

Concluído em 18/09/2026 e registrado em `docs/arquitetura/DECISAO-MARCO-01-5-TENANCY-SAAS.md`.

A implementação foi dividida em cinco fases. A primeira é **Membership compatibility**, criando `usuario_empresas` e `usuario_empresa_perfis`, realizando backfill seguro e mantendo os contratos do Marco 1 operacionais.

## Próximo passo de implementação

Iniciar a **Fase 1 — Membership compatibility**:

- desenhar migration aditiva;
- criar backfill idempotente a partir de `usuarios` e `usuario_perfis`;
- criar constraints e RLS sem trocar ainda a fonte principal de autorização;
- criar testes de consistência e isolamento;
- revisar estado acumulado com Agentes 08 e 09 antes de qualquer deploy.

---

**Status:** Gate 1 concluído / Fase 1 pronta para implementação  
**Data:** 18/09/2026
