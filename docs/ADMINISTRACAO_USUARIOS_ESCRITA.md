# Administração de usuários — escrita segura e auditoria

Data: 18/09/2026. Estado: backend validado e aplicado no Supabase remoto; integração frontend preparada no GitHub e aguardando validação local.

## 1. Decisão do Orquestrador

A escrita administrativa foi liberada em etapas. Primeiro entraram comandos transacionais seguros no banco com auditoria atômica; depois o frontend passou a consumir exclusivamente essas RPCs, sem escrita direta nas tabelas.

A etapa atual cobre usuários já vinculados a uma empresa. O fluxo de aprovação de usuários `pendente` permanece fora do escopo porque exige uma origem segura para o vínculo (convite ou solicitação) e não deve ser improvisado por enumeração global de cadastros sem empresa.

## 2. Agentes envolvidos

- **Dados / Supabase:** tabela de auditoria append-only, funções privadas, roles restritas, RLS e integridade organizacional.
- **Segurança / Permissões:** autorização derivada da sessão, nenhuma empresa informada pelo cliente, sem escrita direta em tabelas, prevenção de autoelevação e proteção do último administrador efetivo.
- **Auditoria / Governança:** toda alteração bem-sucedida registra ator, empresa/unidade, ação, alvo, antes/depois, justificativa e horário do servidor na mesma transação.
- **Frontend / UX:** formulário administrativo integrado ao detalhe do usuário, mantendo identidade visual, bloqueios visuais coerentes e justificativas explícitas.
- **QA:** testes de empresa A/B, self-elevation, último administrador, status, unidade, perfil, usuário pendente, bloqueio de escrita direta e chamada RPC pelo frontend.

## 3. Escopo implementado

Migrations:

- `supabase/migrations/20260918112000_admin_user_commands.sql`;
- `supabase/migrations/20260918120500_fix_admin_writer_select_grants.sql`.

Backend:

- `public.auditoria_eventos` com RLS e sem leitura/escrita direta por `authenticated`;
- role `bpf_admin_writer`, sem login, sem superuser e sem `BYPASSRLS`;
- `private.empresa_gestao_perfis()` para exigir `configuracoes.visualizar`, `usuarios.gerenciar` e `perfis.gerenciar`;
- funções privadas de escrita pertencentes à role restrita;
- wrappers públicos `SECURITY INVOKER` usados via `supabase.rpc()`.

Frontend preparado:

- `Configuracões → Usuários → Detalhes` passa a oferecer administração para usuários não pendentes;
- alteração de status com justificativa obrigatória e confirmação para inativação/bloqueio;
- alteração de unidade com confirmação e seleção limitada às unidades retornadas da própria empresa;
- atribuição/remoção de perfil somente para quem possui `perfis.gerenciar`;
- bloqueio visual de auto-inativação/auto-bloqueio e de alteração dos próprios perfis;
- mensagens de erro provenientes do backend exibidas no diálogo;
- listagem recarregada após uma operação bem-sucedida;
- usuário `pendente` continua exclusivamente em modo de consulta.

Comandos consumidos:

- `admin_usuario_alterar_status`;
- `admin_usuario_alterar_unidade`;
- `admin_usuario_alterar_perfil`.

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
- a tabela de auditoria não é acessível diretamente pelo cliente nesta etapa;
- o frontend revalida o contexto antes de chamar a RPC, mas essa validação é defesa adicional e não substitui o servidor.

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
- edição das permissões internas de um perfil;
- leitura da trilha de auditoria pela interface;
- feedback persistente fora do diálogo após a atualização da listagem.

## 8. Validação do backend concluída

Em 18/09/2026:

- `npm.cmd run test:db`: aprovado; todas as migrations aplicadas no PostgreSQL efêmero, leitura administrativa preservada, comandos auditados aprovados, isolamento multiempresa, anti-self-elevation, proteção do último administrador e ausência de escrita direta confirmados;
- `npm.cmd run build`: aprovado; permanece apenas o aviso não bloqueante de chunk principal acima de 500 kB;
- `npm.cmd run lint`: aprovado;
- `npm.cmd run test:e2e`: **21/21 aprovados** antes da integração frontend de escrita.

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

O advisor de segurança não apontou nova vulnerabilidade desta etapa; permanece o aviso já conhecido de proteção contra senhas vazadas desabilitada. Os advisors de performance apontaram FKs sem índices de cobertura e oportunidades de otimização de initplan em RLS; esses itens serão tratados separadamente.

## 10. Validação pendente da integração frontend

Após sincronizar o branch, executar:

1. `npm.cmd run build`;
2. `npm.cmd run lint`;
3. `npm.cmd run test:e2e`;
4. teste manual em `Configurações → Usuários` com um segundo usuário da mesma empresa, quando disponível.

Critérios manuais: justificativa menor que 5 caracteres não habilita ações; auto-bloqueio permanece indisponível; usuário pendente não oferece comandos administrativos; após uma alteração válida a listagem é recarregada; erros retornados pelo backend devem aparecer sem tela branca.

## 11. Próxima subetapa após aprovação

Com a interface administrativa validada, o próximo desenho será o fluxo seguro de onboarding de usuários pendentes: convite/solicitação, vínculo organizacional e aprovação sem enumeração global de cadastros.
