# Marco 01 — Administração completa

Data: 18/09/2026. Estado: implementação preparada no GitHub; validação local e aplicação remota pendentes.

## Objetivo

Fechar a fundação administrativa do BPF Manager antes de avançar para os módulos operacionais. O marco reúne usuários, perfis, estrutura organizacional e auditoria em um único ciclo do Orquestrador, preservando isolamento multiempresa e trilha de auditoria.

## Agentes envolvidos

- **Produto/BPF:** delimitou a administração como fundação transversal dos demais módulos.
- **Dados/Supabase:** migrations, RPCs, RLS, índices e Edge Function de convite.
- **Segurança/Permissões:** menor privilégio, isolamento por empresa, limite de delegação e proteção dos perfis de sistema.
- **Frontend/UX:** fluxos de convite, perfis customizados, estrutura e auditoria, mantendo a identidade visual existente.
- **QA:** regressão do backend anterior, testes do novo marco, tenant isolation e escalada indireta de privilégios.
- **Auditoria/Governança:** justificativa e histórico atômico para operações administrativas persistentes.

## Funcionalidades preparadas

### Usuários

- mantém administração auditada de status, unidade e perfil;
- adiciona `usuarios.convidar`;
- botão **Convidar usuário** para administradores autorizados;
- convite por Edge Function autenticada usando Supabase Auth;
- vínculo do usuário convidado à empresa derivada da sessão, unidade e perfis escolhidos;
- não existe enumeração global de usuários pendentes sem empresa;
- em falha de vínculo após criação do convite, a Edge Function tenta remover a identidade criada para não deixar acesso órfão.

### Perfis e permissões

- perfis de sistema continuam somente leitura;
- perfis customizados pertencem à empresa;
- criação, edição e inativação de perfis da empresa;
- seleção de permissões por módulo;
- um ator não pode delegar perfil ou permissão superior às permissões que ele próprio possui;
- perfis atribuídos a usuários ativos precisam ser desvinculados antes de ter seu conjunto de permissões alterado, evitando mudança silenciosa de privilégios e contorno da proteção do último administrador.

### Estrutura organizacional

- nova permissão `estrutura.gerenciar`;
- edição dos dados da empresa atual;
- criação e edição/inativação de unidades;
- criação e edição/inativação de setores;
- nenhuma RPC recebe `empresa_id` como autoridade: a empresa é resolvida pela sessão autenticada;
- unidade com usuário ativo não pode ser inativada enquanto o vínculo estiver em uso.

### Auditoria

- nova permissão `auditoria.visualizar`;
- consulta somente leitura da trilha da própria empresa;
- filtros por texto e entidade;
- visualização de ator, ação, data/hora, justificativa, registro e estados antes/depois;
- o cliente segue sem `INSERT`, `UPDATE` ou `DELETE` direto na auditoria.

## Novas migrations

- `20260918134500_complete_administration_foundation.sql`;
- `20260918134600_expand_admin_audit_writer_policy.sql`;
- `20260918134700_harden_profile_delegation.sql`.

Estas migrations ainda **não devem ser consideradas aplicadas no Supabase remoto** até o checkpoint local ser aprovado.

## Edge Function

`supabase/functions/admin-invite-user` está versionada no GitHub, mas ainda não implantada remotamente neste checkpoint.

A função exige JWT válido e revalida no banco:

- `configuracoes.visualizar`;
- `usuarios.gerenciar`;
- `usuarios.convidar`.

A `service_role` existe somente no runtime seguro da Edge Function para chamar a API administrativa do Supabase Auth; nunca é enviada ao frontend.

## Testes adicionados

- `supabase/tests/complete_administration_foundation.sql`;
- `supabase/tests/profile_delegation_security.sql`;
- `tests/configuracoes-admin.spec.ts`.

`scripts/test-db.mjs` aplica toda a cadeia de migrations administrativas e executa os testes anteriores e os novos testes de segurança.

## Critério do checkpoint

Antes de aplicar as três migrations e implantar a Edge Function remotamente, devem passar integralmente:

```text
npm.cmd run test:db
npm.cmd run build
npm.cmd run lint
npm.cmd run test:e2e
```

Depois desse checkpoint, o Orquestrador poderá aplicar o backend remoto, implantar `admin-invite-user` com verificação JWT habilitada, revisar advisors e liberar a validação visual integrada.

## Fora deste marco

- criação de uma nova empresa por administrador de tenant;
- transferência de usuário entre empresas;
- edição de identidade/e-mail de usuários existentes;
- exclusão física de registros administrativos;
- módulos operacionais de BPF.

Esses pontos permanecem separados para preservar governança e isolamento multiempresa.
