# Administração de usuários — escrita segura e auditoria

Data: 18/09/2026. Estado: implementação de backend preparada no GitHub; validação local e aplicação remota pendentes.

## 1. Decisão do Orquestrador

A escrita administrativa será liberada em etapas. Primeiro entram comandos transacionais seguros no banco com auditoria atômica; somente depois o frontend habilitará ações de edição.

A etapa atual cobre usuários já vinculados a uma empresa. O fluxo de aprovação de usuários `pendente` permanece fora do escopo porque exige uma origem segura para o vínculo (convite ou solicitação) e não deve ser improvisado por enumeração global de cadastros sem empresa.

## 2. Agentes envolvidos

- **Dados / Supabase:** tabela de auditoria append-only, funções privadas, roles restritas, RLS e integridade organizacional.
- **Segurança / Permissões:** autorização derivada da sessão, nenhuma empresa informada pelo cliente, sem escrita direta em tabelas, prevenção de autoelevação e proteção do último administrador efetivo.
- **Auditoria / Governança:** toda alteração bem-sucedida registra ator, empresa/unidade, ação, alvo, antes/depois, justificativa e horário do servidor na mesma transação.
- **QA:** testes de empresa A/B, self-elevation, último administrador, status, unidade, perfil, usuário pendente e bloqueio de escrita direta.
- **Frontend / UX:** não participa desta primeira subetapa; a interface continuará somente leitura até o backend ser validado e aplicado.

## 3. Escopo preparado

Migration: `supabase/migrations/20260918112000_admin_user_commands.sql`.

Estruturas previstas:

- `public.auditoria_eventos` com RLS e sem leitura/escrita direta por `authenticated`;
- role `bpf_admin_writer`, sem login, sem superuser e sem `BYPASSRLS`;
- `private.empresa_gestao_perfis()` para exigir `configuracoes.visualizar`, `usuarios.gerenciar` e `perfis.gerenciar`;
- funções privadas de escrita pertencentes à role restrita;
- wrappers públicos `SECURITY INVOKER` para uso futuro via `supabase.rpc()`.

Comandos preparados:

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

Se a auditoria falhar, a alteração inteira deve falhar.

## 7. O que ainda não foi implementado

- aprovação/vinculação de usuário pendente;
- convite por e-mail;
- solicitação de vínculo;
- transferência de usuário entre empresas;
- edição de permissões de perfil;
- leitura da trilha de auditoria pela interface;
- botões/formulários de escrita no frontend.

Esses fluxos dependem da validação desta fundação e de decisões próprias de segurança e UX.

## 8. Testes preparados

`supabase/tests/admin_user_commands.sql` cobre:

- alteração de status com auditoria;
- reativação;
- bloqueio do próprio usuário;
- tentativa de ativar `pendente` fora do fluxo dedicado;
- alteração de usuário de outra empresa;
- proteção do último administrador efetivo;
- alteração de unidade dentro da empresa;
- rejeição de unidade de outra empresa;
- atribuição e remoção de perfil;
- rejeição de autoelevação;
- rejeição de perfil de outra empresa;
- ausência de escrita direta para `authenticated`;
- ausência de acesso direto à auditoria.

`scripts/test-db.mjs` foi atualizado para aplicar toda a cadeia de migrations administrativas e executar tanto os testes de leitura quanto os novos testes de escrita em PostgreSQL efêmero.

## 9. Critérios para aplicação remota

Antes de aplicar a nova migration ao Supabase remoto:

1. `npm.cmd run test:db` deve passar integralmente;
2. `npm.cmd run build` deve passar;
3. `npm.cmd run lint` deve passar;
4. `npm.cmd run test:e2e` deve permanecer verde;
5. a migration deve ser revisada após qualquer falha encontrada no teste local;
6. somente então a alteração persistente será aplicada e validada no Supabase remoto.

## 10. Próxima subetapa após validação

Conectar os comandos validados à tela `Configurações → Usuários`, com formulários explícitos, justificativa obrigatória, confirmação das ações sensíveis e atualização do contexto após mudanças que afetem acesso.
