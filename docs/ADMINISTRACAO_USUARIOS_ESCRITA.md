# Administração de usuários — escrita segura e auditoria

Data: 18/09/2026. Estado: backend validado localmente e aplicado no Supabase remoto.

## 1. Decisão do Orquestrador

A escrita administrativa será liberada em etapas. Primeiro entram comandos transacionais seguros no banco com auditoria atômica; somente depois o frontend habilitará ações de edição.

A etapa atual cobre usuários já vinculados a uma empresa. O fluxo de aprovação de usuários `pendente` permanece fora do escopo porque exige uma origem segura para o vínculo (convite ou solicitação) e não deve ser improvisado por enumeração global de cadastros sem empresa.

## 2. Agentes envolvidos

- **Dados / Supabase:** tabela de auditoria append-only, funções privadas, roles restritas, RLS e integridade organizacional.
- **Segurança / Permissões:** autorização derivada da sessão, nenhuma empresa informada pelo cliente, sem escrita direta em tabelas, prevenção de autoelevação e proteção do último administrador efetivo.
- **Auditoria / Governança:** toda alteração bem-sucedida registra ator, empresa/unidade, ação, alvo, antes/depois, justificativa e horário do servidor na mesma transação.
- **QA:** testes de empresa A/B, self-elevation, último administrador, status, unidade, perfil, usuário pendente e bloqueio de escrita direta.
- **Frontend / UX:** não participou desta primeira subetapa; a interface permanece somente leitura até a integração dos comandos RPC.

## 3. Escopo implementado

Migrations:

- `supabase/migrations/20260918112000_admin_user_commands.sql`;
- `supabase/migrations/20260918120500_fix_admin_writer_select_grants.sql`.

Estruturas implementadas:

- `public.auditoria_eventos` com RLS e sem leitura/escrita direta por `authenticated`;
- role `bpf_admin_writer`, sem login, sem superuser e sem `BYPASSRLS`;
- `private.empresa_gestao_perfis()` para exigir `configuracoes.visualizar`, `usuarios.gerenciar` e `perfis.gerenciar`;
- funções privadas de escrita pertencentes à role restrita;
- wrappers públicos `SECURITY INVOKER` para uso futuro via `supabase.rpc()`.

Comandos disponíveis:

- `admin_usuario_alterar_status` — ativo, inativo e bloqueado;
- `admin_usuario_alterar_unidade` — somente unidade ativa da mesma empresa ou `NULL`;
- `admin_usuario_alterar_perfil` — atribuir/remover perfil compatível, exigindo permissão adicional de gestão de perfis.

## 4. Barreiras de segurança

- a empresa é derivada do ator autenticado no banco;
- usuário de outra empresa não pode ser alterado;
- `pendente` não pode ser ativado por esses comandos;
- mudança do próprio perfil administrativo é bloqueada;
- inativar/bloquear o próprio usuário é bloqueado;
- perfil de outra empresa não pode ser atribuído;
- perfil inativo não pode ser atribuído;
- alterações de perfil exigem `perfis.gerenciar` além de `usuarios.gerenciar`;
- a operação não pode remover o último administrador efetivo da empresa;
- `authenticated` continua sem `UPDATE` direto em `usuarios` e sem `INSERT/DELETE` direto em `usuario_perfis`;
- a tabela de auditoria não é acessível diretamente pelo cliente nesta etapa.

## 5. Administrador efetivo

Para a proteção contra perda do último administrador, a implementação não depende do nome do perfil. É considerado administrador efetivo um usuário ativo da empresa cujos perfis ativos e compatíveis concedam simultaneamente:

- `configuracoes.gerenciar`;
- `usuarios.gerenciar`;
- `perfis.gerenciar`.

Isso preserva a proteção mesmo quando perfis customizados forem introduzidos.

## 6. Auditoria

Cada comando bem-sucedido grava, na mesma transação:

- `empresa_id`;
- `unidade_id` aplicável;
- `ator_id` derivado da sessão;
- entidade e registro alvo;
- ação;
- estado anterior;
- estado posterior;
- justificativa obrigatória com ao menos 5 caracteres;
- contexto de origem;
- data/hora do servidor.

Se a auditoria falhar, a alteração inteira falha.

## 7. O que ainda não foi implementado

- aprovação/vinculação de usuário pendente;
- convite por e-mail;
- solicitação de vínculo;
- transferência de usuário entre empresas;
- edição de permissões de perfil;
- leitura da trilha de auditoria pela interface;
- botões/formulários de escrita no frontend.

## 8. Validação local concluída

Em 18/09/2026:

- `npm.cmd run test:db`: aprovado; todas as migrations aplicadas no PostgreSQL efêmero, leitura administrativa preservada, comandos auditados aprovados, isolamento multiempresa, anti-self-elevation, proteção do último administrador e ausência de escrita direta confirmados;
- `npm.cmd run build`: aprovado; permanece apenas o aviso não bloqueante de chunk principal acima de 500 kB;
- `npm.cmd run lint`: aprovado;
- `npm.cmd run test:e2e`: **21/21 aprovados**.

A fixture local foi alinhada ao schema remoto durante a validação, e a migration complementar `fix_admin_writer_select_grants` preserva o princípio de menor privilégio ao liberar apenas as colunas necessárias aos `%ROWTYPE` internos.

## 9. Aplicação e validação remota

As duas migrations desta etapa foram aplicadas com sucesso no projeto Supabase em 18/09/2026.

Validações pós-migration confirmaram:

- `bpf_admin_writer`: `NOLOGIN`, `NOSUPERUSER`, `NOINHERIT`, `NOBYPASSRLS`;
- RLS habilitada em `auditoria_eventos`;
- `authenticated` sem `UPDATE` direto em `usuarios`;
- `authenticated` sem `INSERT/DELETE` direto em `usuario_perfis`;
- `authenticated` sem acesso direto à tabela de auditoria;
- `authenticated` pode executar as três RPCs administrativas;
- `anon` não pode executar a RPC de alteração de status;
- teste remoto transacional de auto-bloqueio foi recusado e não gerou auditoria residual;
- histórico remoto registra `admin_user_commands` e `fix_admin_writer_select_grants`.

O advisor de segurança não apontou nova vulnerabilidade desta etapa; permanece o aviso já conhecido de proteção contra senhas vazadas desabilitada. Os advisors de performance apontaram FKs sem índices de cobertura e oportunidades de otimização de initplan em RLS; esses itens serão tratados separadamente para não misturar otimização com a fundação funcional.

## 10. Próxima subetapa

Conectar os comandos validados à tela `Configurações → Usuários`, com:

- formulários explícitos;
- justificativa obrigatória;
- confirmação de ações sensíveis;
- feedback de sucesso/erro;
- atualização da listagem após a operação;
- atualização do contexto quando mudanças afetarem acesso;
- testes E2E específicos das novas ações.
