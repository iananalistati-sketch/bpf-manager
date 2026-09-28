# Configurações — Usuários e Perfis

Data: 15/09/2026. Estado: primeira versão de consulta; escrita administrativa não habilitada.

Atualização de 16/09/2026: este documento preserva a inspeção e as evidências da primeira etapa. A evolução da leitura administrativa, correções da view/FK e validações estão em [Leitura administrativa de usuários](LEITURA_ADMINISTRATIVA_USUARIOS.md). A migration está preparada e validada localmente, mas **não foi aplicada ao Supabase remoto**: a revisão automática exigiu aprovação explícita. A mensagem da interface passou a informar o escopo da empresa e as permissões, sem prometer uma listagem completa. As limitações de banco abaixo ainda descrevem o ambiente remoto antes da aplicação.

## Escopo entregue

`/configuracoes` contém navegação interna por `?secao=geral`, `?secao=usuarios` e `?secao=perfis`. Não foram adicionadas entradas ao menu lateral. A identidade visual existente foi preservada.

- Visão geral: empresa, unidade, usuário e perfis do contexto autenticado.
- Usuários: nome, e-mail, status, empresa, unidade, situação, cadastro, vínculos visíveis e detalhes. Filtros locais por nome/e-mail (sem distinção de acentos), status, unidade e perfil.
- Perfis: registros reais de `perfis`, identificação de sistema, situação e quantidade de vínculos. Detalhes usam o catálogo real de `permissoes`, agrupado por `modulo`, com marcações a partir de `perfil_permissoes`. A contagem representa permissões atribuídas, não uma concessão efetiva ao usuário.
- Loading, erro recuperável, vazio e sucesso; cancelamento de consultas ao sair, limite de espera de 20 segundos, descarte de dados de contexto anterior e paginação de leitura para evitar truncamento pelo limite da API.
- Modais nativos com foco, Escape e retorno de foco; campos e ações de escrita desabilitados, com explicação visível.

## Autorização e fluxo

| Acesso | Permissão exigida |
| --- | --- |
| Rota e visão geral | `configuracoes.visualizar` |
| Seção de usuários | anterior + `usuarios.gerenciar` |
| Seção de perfis | anterior + `perfis.gerenciar` |
| Administração geral futura | `configuracoes.gerenciar` (não substitui as anteriores) |

`hasPermission` centraliza a checagem visual: contexto ativo, status ativo, empresa vinculada e código explícito. Não existe atalho por nome do perfil Administrador. `ProtectedRoute` e `PermissionRoute` continuam protegendo a rota. A seção também confere a autorização em acessos diretos pela query string, antes de montar os componentes que consultam dados.

Os hooks usam o cliente Supabase existente, sem chave administrativa, e os serviços reconsultam `v_meu_contexto` antes da leitura, conferindo usuário, empresa e permissões. Isso é defesa adicional do cliente; **não substitui autorização no banco**. O backend atual continua sendo responsável pela restrição definitiva das linhas.

## Inspeção do banco existente

Inspeção remota somente de leitura via MCP: colunas, constraints, grants, políticas, funções, triggers e Security Advisor. Nenhuma migration, função, política, grant, registro ou configuração do Supabase foi alterado.

| Objeto | Política atual / consequência |
| --- | --- |
| `usuarios` | `usuarios_select_proprio`: apenas `id = auth.uid()`. Administrador não lista colegas. |
| `usuario_perfis` | `usuario_perfis_select_proprio`: somente vínculos do solicitante. |
| `empresas` | Somente empresa do usuário ativo com status ativo. |
| `unidades` | Unidades da mesma empresa do usuário ativo. |
| `setores` | Setores de unidades da mesma empresa do usuário ativo. Não consultados pela nova tela. |
| `perfis` | Perfis globais de sistema ou da empresa do usuário ativo. |
| `permissoes` | Catálogo compartilhado: leitura por `authenticated`. |
| `perfil_permissoes` | Vínculos de perfis de sistema ou perfis visíveis da empresa. |
| `v_meu_contexto` | `security_invoker=true`, filtrada por `auth.uid()`, sujeita à RLS das tabelas. |

Todas as oito tabelas possuem RLS e apenas grant de SELECT para `authenticated`. Não foram encontradas políticas de escrita. A view tem grants de escrita excedentes, embora seja uma agregação sem caminho normal de atualização: recomendar reduzir a SELECT em revisão separada.

A UI deixa explícito que a listagem de usuários é **somente do próprio cadastro**, não um total da empresa. Ausência de pendentes não significa ausência de solicitações. Usuários novos sem empresa não são buscados nem expostos a administradores de empresas. A interface de pendentes está preparada e testada com fixtures, sem habilitar descoberta global de cadastros.

### O que funciona agora

Consulta do próprio cadastro, empresa/unidades autorizadas, vínculos próprios e dos sete perfis de sistema existentes (Administrador, Responsável Técnico, Qualidade, Supervisor, Operador, Auditor e Consulta). O Administrador possui 39 permissões atribuídas no catálogo inspecionado. Nenhum desses nomes ou conjunto de permissões foi usado como concessão automática no componente.

### O que depende de backend

Listagem administrativa de colegas e seus vínculos; descoberta de pendentes vinculados por convite/solicitação à empresa; aprovação, alteração de nome/status/unidade, atribuição ou remoção de perfil, edição de permissões e auditoria. Alteração de empresa exige fluxo próprio de governança, não um seletor livre.

## Alterações de banco necessárias para habilitar gravação administrativa

**Proposta para revisão; não aplicada.** Antes de liberar qualquer botão de escrita:

1. **Leitura administrativa com escopo.** Preservar leitura do próprio cadastro necessária à autenticação. Adicionar caminho de leitura administrativa, por RLS específica ou endpoint dedicado, exigindo usuário ativo, `configuracoes.visualizar`, `usuarios.gerenciar` e a mesma empresa. Cobrir `usuarios` e `usuario_perfis` juntos. Evitar política recursiva que consulte a própria tabela sem desenho revisado. Se houver view adicional, utilizar `security_invoker=true` e não tratá-la como substituta das políticas. Definir explicitamente se o administrador administra toda a empresa ou somente unidades delegadas.
2. **Onboarding de pendentes.** Criar vínculo confiável de convite/solicitação com empresa/unidade e validade, controlado no servidor. Cadastros com `empresa_id IS NULL` não devem ser liberados globalmente. Aprovação deve validar esse vínculo e não aceitar empresa/perfil vindos de `user_metadata`.
3. **Comandos transacionais específicos.** Preferir comandos separados para aprovar cadastro, editar nome, alterar unidade, alterar status, atribuir/remover perfil e ajustar permissões de perfil da empresa. Proposta de contrato: identificador do alvo, payload permitido, versão esperada e justificativa. Ator e empresa vêm da sessão validada no servidor, nunca de parâmetros confiados ao navegador. Não criar um `update_usuario` genérico que aceite qualquer coluna.
4. **Autorização de cada comando.** Revalidar `auth.uid()`, usuário ativo, empresa/unidade, perfil ativo e permissão efetiva em dados controlados. Aprovação/status/unidade/perfis exigem `usuarios.gerenciar`; alteração da composição de perfil exige `perfis.gerenciar`. Não permitir autoelevação ou autopromoção por alterações indiretas no próprio perfil. Negar atribuição de privilégios não delegáveis e preservar ao menos um administrador ativo, com bloqueio transacional para concorrência.
5. **Implementação privilegiada mínima.** Manter DML direto do cliente revogado. Caso um comando precise de privilégios, colocar a implementação em schema privado não exposto, com dono de privilégios mínimos, `search_path` fixo/vazio, nomes qualificados e EXECUTE explicitamente restrito (revogado de PUBLIC e anon). Um eventual wrapper RPC público deve ser `SECURITY INVOKER`, estreito e sem autorização implícita; a implementação privada valida toda chamada. Alternativamente, Edge Function autenticada chama comandos transacionais privados com as mesmas verificações. Nenhuma `SECURITY DEFINER` em `public` e nenhum secret no frontend.
6. **Integridade multiempresa.** O CHECK atual apenas exige empresa quando há unidade; não garante que a unidade pertença à empresa. Propor FK composta ou constraint equivalente para empresa/unidade. Validar perfil global de sistema ou perfil da mesma empresa em cada vínculo, impedindo perfis cruzados. Revisar cascatas e exclusões antes de qualquer capacidade destrutiva.
7. **Perfis de sistema.** Mantê-los imutáveis para administradores de empresas. Para personalizar, propor cópia de perfil para a empresa, com conjunto de permissões delegáveis. Alterar perfil global compartilhado não pode afetar outras empresas por ação de um administrador local.
8. **Trilha de auditoria na mesma transação.** Integrar cada comando com registro persistente de ator, instante do servidor, ação, alvo, empresa/unidade, antes/depois, justificativa e identificação da solicitação. Se o registro falhar, a alteração deve falhar. Guardar concessão e revogação de perfil como eventos históricos; não depender de `created_by`, `updated_at` ou logs no browser. Definir tabela/schema, retenção e políticas de leitura em revisão de governança; impedir alteração/exclusão da trilha pelo cliente.
9. **Transferência de empresa.** Não habilitar como edição comum. Exigir aprovação formal de origem/destino ou operador de plataforma autorizado, reavaliar/remover vínculos incompatíveis e preservar o histórico organizacional anterior. Deixar indisponível até esse fluxo existir.
10. **Testes de banco antes da liberação.** Em ambiente isolado, cobrir duas empresas, múltiplas unidades, usuário sem permissão, pendente/inativo/bloqueado, autoelevação, perfil de outra empresa, perfil de sistema, perda do último administrador, revogação de permissão, concorrência, falha de auditoria e tentativa direta de DML/RPC. Versionar a solução revisada em migration e executar advisors antes da aplicação.

## Riscos identificados

- O catálogo de permissões e os perfis globais já são visíveis a qualquer `authenticated`, inclusive sem cadastro operacional válido. A nova UI restringe a área administrativa, mas **não torna esse catálogo secreto**. Se confidencialidade do catálogo for requisito, revisar a RLS sem quebrar os dados necessários ao contexto individual.
- `v_meu_contexto` agrega perfis sem filtrar `p.ativo`. A desativação futura de perfil precisa ser refletida na autorização do servidor e na view; não depender da marcação visual. Esta etapa não muda a view nem habilita desativação.
- Grants excedentes da view, ausência de constraint completa empresa/unidade, cascatas e ausência de trilha de auditoria precisam de revisão antes de escrita.
- Security Advisor: proteção contra senhas vazadas desativada. Ver [orientação oficial](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Nenhuma configuração alterada nesta tarefa.
- A leitura do contexto no cliente não garante revogação instantânea de acesso; operações futuras devem consultar autorização atual no servidor, independentemente de estado React ou JWT antigo.

## Evidências e reprodução

Consultas com transações `READ ONLY`, `SET LOCAL ROLE authenticated` e claims locais, encerradas com rollback:

- Administrador existente: 1 usuário (próprio), 1 vínculo (próprio), 7 perfis, 39 permissões e 1 contexto; quatro permissões administrativas presentes. Grants de UPDATE em usuários/perfis e INSERT em vínculos administrativos: falsos.
- Identidade sem cadastro: 0 usuários, empresas, unidades, setores, vínculos pessoais e contexto. Catálogo global segue visível (7 perfis e 39 permissões). `anon` sem SELECT em usuários; `authenticated` sem DELETE em usuários.
- Apenas um usuário operacional existia no momento da inspeção. Não foram criados usuários ou tenants de teste no banco real. Testes completos entre duas empresas, mutações e auditoria ficam para um banco isolado antes da aprovação da proposta.

`npm.cmd run test:e2e` usa Playwright, Chrome instalado e Vite em `127.0.0.1:4175`. URL/chave de teste fictícias são passadas somente ao servidor de testes; todas as respostas Supabase do navegador são interceptadas. Não usa credenciais reais nem grava no banco. Fixtures de pendentes validam apresentação, não afirmam que a RLS atual permite listar outros usuários.

Cobertura: navegação do Administrador; rota/URL sem permissão; independência de usuários/perfis; loading, falha/retentativa e vazio; filtros; modal somente leitura, Escape/foco; cancelamento de consulta; telas 375/768/1440; serviço com autorização revogada; paginação acima de 500 registros. Capturas locais são geradas em `test-results/`, ignorado pelo Git.

Validação final em 15/09/2026:

- `npm.cmd run build`: sucesso (TypeScript + Vite). Aviso não bloqueante: pacote principal de 513,24 kB, acima do limiar de 500 kB. O módulo de configurações já é carregado sob demanda (23,25 kB JS).
- `npm.cmd run lint`: sucesso, sem erros ou warnings. Corrigidos os dois erros preexistentes do hook de autenticação e excluídos artefatos gerados dos testes da varredura.
- `npm.cmd run test:e2e`: **14 testes aprovados**, Chrome headless, 13,3 segundos. Capturas mobile/desktop também inspecionadas visualmente.
- `git diff --check`: sem erros de whitespace. Nenhum commit/push realizado.

O ambiente Windows possui Chrome instalado. O runner usa `npm.cmd`; para executar em outro sistema, adaptar o comando do servidor e o canal do navegador em `playwright.config.ts`.

## Organização do código

- `src/modules/configuracoes/{pages,components,hooks,services,types,lib}` e CSS local do módulo.
- `src/lib/permissions.ts`: checagem visual compartilhada com menu e rota.
- `src/components/AuthProvider.tsx` e `src/lib/authContext.ts`: separação do provider/contexto do hook existente, corrigindo Fast Refresh. Estado inicial de loading já considera erro de configuração, sem setState síncrono redundante no effect.
- Carregamento da página sob demanda em `App.tsx`; sem biblioteca visual nova.

### Arquivos criados

- `src/components/AuthProvider.tsx`
- `src/lib/authContext.ts`, `src/lib/permissions.ts`
- `src/modules/configuracoes/pages/ConfiguracoesPage.tsx`
- `src/modules/configuracoes/components/DetailsDialog.tsx`
- `src/modules/configuracoes/components/UsuarioDetails.tsx`, `UsuariosPanel.tsx`
- `src/modules/configuracoes/components/PerfilDetails.tsx`, `PerfisPanel.tsx`
- `src/modules/configuracoes/components/QueryFeedback.tsx`, `StatusBadge.tsx`
- `src/modules/configuracoes/hooks/useConfiguracoesQuery.ts`
- `src/modules/configuracoes/services/configuracoesService.ts`
- `src/modules/configuracoes/types/index.ts`, `lib/presentation.ts`, `configuracoes.css`
- `tests/configuracoes.spec.ts`, `playwright.config.ts`
- `docs/CONFIGURACOES_USUARIOS_PERFIS.md`

### Arquivos alterados

- `src/App.tsx`, `src/components/PermissionRoute.tsx`, `src/components/Sidebar.tsx`, `src/hooks/useAuth.tsx`
- `docs/REFERENCIA_PROJETO.md`
- `package.json`, `package-lock.json`: Playwright como dependência de desenvolvimento e script de teste.
- `.gitignore`, `eslint.config.js`: exclusão dos artefatos gerados por Playwright.

Próximo passo: revisar e aprovar a proposta de leitura administrativa, comandos e auditoria; implementá-la em ambiente isolado antes de conectar os botões de gravação.

Referências técnicas: [RLS e views](https://supabase.com/docs/guides/database/postgres/row-level-security), [SELECT e limites de leitura](https://supabase.com/docs/reference/javascript/select).
