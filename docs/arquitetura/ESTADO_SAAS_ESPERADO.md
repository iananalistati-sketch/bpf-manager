# Estado Esperado — Fundação SaaS

Este documento define o contrato arquitetural alvo do Marco 1.5. Ele descreve o estado esperado; não substitui migrations nem scripts de backfill.

## 1. Identidade

`public.usuarios` deve representar a identidade global da pessoa dentro do BPF Manager.

Direção de longo prazo:

- `id` vinculado a `auth.users.id`;
- nome/e-mail/status global;
- sem depender de uma única empresa para existir;
- sem atribuir privilégio global por `user_metadata`.

As colunas legadas de empresa/unidade podem permanecer temporariamente durante a transição, mas não devem ser a fonte final de autorização.

## 2. Membership empresarial

Nova entidade esperada: `usuario_empresas`.

Campos conceituais mínimos:

- `id`;
- `usuario_id`;
- `empresa_id`;
- `unidade_id` opcional/padrão;
- `status`;
- `is_owner`;
- timestamps;
- origem/provisionamento quando aplicável.

Invariantes:

- um vínculo pertence a exatamente uma empresa;
- somente vínculos ativos podem autorizar acesso;
- unidade, se informada, deve pertencer à mesma empresa;
- identidade pode possuir múltiplos vínculos;
- exclusividade/constraints devem impedir memberships duplicados equivalentes.

## 3. RBAC por membership

O vínculo de perfil deve evoluir de `usuario_perfis` para um modelo contextual, por exemplo `usuario_empresa_perfis`.

Permissões efetivas devem resultar da combinação:

**identidade ativa + membership ativo + tenant ativo + perfil ativo/compatível + permissão**.

Perfil de sistema pode ser global, mas sua atribuição sempre ocorre dentro do contexto de uma empresa/membership.

## 4. Tenant ativo

A aplicação deve suportar seleção explícita do contexto empresarial atual.

Regras:

- o frontend pode solicitar mudança de tenant;
- o backend valida se o usuário possui membership ativo naquele tenant;
- empresa ativa nunca deve ser aceita cegamente de um `empresa_id` manipulável;
- helpers/RPCs/RLS críticos devem derivar e validar o escopo autorizado;
- troca de tenant deve invalidar/recarregar contexto e permissões.

Na Fase 2, a estratégia adotada é **contexto por request validado pelo backend**, sem persistir autorização em `user_metadata`. Os contratos novos são:

- `public.meus_vinculos()` — lista somente memberships operacionais da identidade autenticada;
- `public.meu_contexto_empresa(p_empresa_id)` — resolve identidade, membership, empresa, unidade, owner, perfis e permissões apenas quando o JWT atual possui membership ativo para a empresa solicitada.

Esses contratos coexistem com `v_meu_contexto` durante a transição e não substituem ainda o runtime legado.

## 5. Trial/workspace

A empresa/workspace deve possuir estado capaz de distinguir pelo menos:

- trial;
- cliente ativo;
- restrito/expirado;
- cancelado/inativo.

O trial deve possuir:

- início;
- expiração;
- template/versionamento de seed demo;
- indicação de dados demonstrativos;
- política de readonly após expiração;
- conversão idempotente para cliente.

## 6. Planos

Nova entidade esperada: `planos`.

Características:

- código estável;
- nome comercial editável;
- ativo/inativo;
- periodicidade/preço opcionais nesta fase;
- sem hardcode de autorização por nome do plano.

## 7. Entitlements e limites

Entidade esperada: `plano_entitlements` ou estrutura equivalente.

Deve permitir recursos booleanos e limites quantitativos, por exemplo:

- `usuarios_ativos.max`;
- `unidades.max`;
- `armazenamento_mb.max`;
- `producao.enabled`;
- `rastreabilidade.enabled`;
- `api.enabled`.

O backend deve validar limites antes de mutações que aumentem consumo.

## 8. Assinaturas

Entidade esperada: `assinaturas`.

Campos conceituais:

- empresa/workspace;
- plano;
- status;
- período;
- provider opcional;
- customer/subscription IDs externos opcionais;
- datas de início, renovação, cancelamento e grace period quando aplicável.

Nunca usar retorno do frontend como prova de pagamento.

## 9. Provisionamento

Rotina server-side idempotente deve suportar:

- criar/converter workspace;
- criar assinatura;
- ativar membership owner;
- atribuir perfil administrativo inicial;
- instalar configurações/entitlements;
- registrar auditoria.

Reprocessar o mesmo evento de pagamento não pode duplicar empresa, assinatura ou owner.

## 10. Onboarding

Estado de onboarding deve ser persistido por workspace/empresa e permitir retomada.

Etapas mínimas previstas:

- dados da empresa;
- unidade principal;
- responsável técnico;
- estrutura/setores;
- usuários iniciais;
- configurações BPF.

## 11. Auditoria

Eventos mínimos futuros:

- trial criado;
- trial expirado;
- workspace convertido;
- assinatura criada/alterada/cancelada;
- plano alterado;
- limite atingido/bloqueio relevante;
- membership criado/inativado;
- owner alterado;
- onboarding concluído.

## 12. Segurança

- RLS em todas as novas tabelas expostas;
- `service_role` somente server-side;
- webhook com validação de assinatura do provedor;
- nenhuma promoção administrativa baseada em resposta do checkout no cliente;
- anti-cross-tenant em todos os novos fluxos;
- limites/entitlements validados no backend;
- trial não pode acessar tenant real de outro cliente;
- owner não pode ser removido sem regra de continuidade administrativa;
- não confiar em `user_metadata` para plano, empresa, perfil ou membership.

## 13. Compatibilidade com o Marco 1

As migrations já remotas do Marco 1 são imutáveis.

A migração para memberships deve usar novas migrations e preservar temporariamente compatibilidade com:

- `usuarios.empresa_id`;
- `usuarios.unidade_id`;
- `usuario_perfis`;
- helpers/RPCs administrativos existentes.

A remoção das estruturas legadas só pode ocorrer após backfill, dupla validação, migração dos contratos e testes completos.

### Estado de implementação em 23/09/2026

- Fase 1 — `usuario_empresas` e `usuario_empresa_perfis`: implementada e aplicada remotamente, com backfill validado;
- Fase 2 — contrato de tenant/contexto: implementado em fonte e em validação local antes de deploy remoto;
- frontend continua usando o contrato legado nesta etapa;
- nenhum dado legado foi removido;
- nenhuma autorização depende de `user_metadata` ou de `empresa_id` informado sem validação de membership.

## 14. Critérios de estado final

- uma identidade pode participar de múltiplas empresas;
- a autorização é contextual ao membership e tenant ativo;
- plano/entitlement é separado de RBAC;
- trial é isolado;
- limites são impostos no backend;
- provisionamento é idempotente;
- contratos suportam web e futuro mobile;
- nenhuma regressão no isolamento multiempresa;
- cadeia de migrations local e remota permanece coerente.

---

**Status:** Arquitetura alvo do Marco 1.5 / Fases 1 e 2 em evolução  
**Última atualização:** 23/09/2026
