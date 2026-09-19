# Leitura administrativa de usuários

Data: 18/09/2026. Entrega aplicada e validada no Supabase remoto.

## 1. Decisão do Orquestrador

Ampliar somente SELECT de usuários e vínculos compatíveis da mesma empresa, com autorização no banco. Preservar leitura do próprio cadastro para bootstrap e manter todas as escritas administrativas indisponíveis. A implementação segue a referência do projeto e não altera a identidade visual.

## 2. Pareceres especializados

- **Dados / Supabase:** RLS nas tabelas existentes evita duplicar o contrato do service e oferece proteção também em consultas diretas. Helper privado com proprietário dedicado evita recursão entre usuários e perfis. Integridade empresa/unidade por FK composta, precedida de preflight.
- **Segurança / Permissões:** exigir identidade, ativo, status, empresa e as duas permissões no servidor; nenhum parâmetro de empresa confiado ao cliente. Proprietário sem login, bypass de RLS ou escrita. ACL e comentário da função devem preceder a transferência de proprietário. Nenhuma concessão administrativa automática.
- **Auditoria / Governança:** leitura não justifica uma auditoria parcial que prometa rastreabilidade de futuras escritas. Convites e comandos administrativos precisam de desenho transacional, histórico e autorização específica antes de implementação.
- **QA:** cenários positivos e negativos A/B, revogação, perfil inativo, filtro adulterado e FK devem ser exercitados no PostgreSQL, além dos testes de navegador. A validação local deve ser complementada por validação no Supabase de destino.

## 3. Arquivos criados

- `supabase/migrations/20260916163832_administrative_user_read.sql`
- `supabase/migrations/20260916223100_fix_authz_reader_identity.sql`
- `supabase/migrations/20260916223400_optimize_administrative_read_rls.sql`
- `supabase/tests/administrative_user_read.sql`
- `supabase/tests/fixtures/current_schema.sql`
- `scripts/test-db.mjs`
- `docs/LEITURA_ADMINISTRATIVA_USUARIOS.md`

## 4. Arquivos alterados

- `src/modules/configuracoes/components/UsuariosPanel.tsx`: apenas mensagem do escopo de consulta.
- `tests/configuracoes.spec.ts`: colega da mesma empresa e cenários adicionais de recusa pelo serviço.
- `package.json` / `package-lock.json`: PGlite como dependência exclusiva de desenvolvimento e `test:db`.
- `.gitignore`: artefatos temporários da CLI Supabase.
- `docs/REFERENCIA_PROJETO.md` e `docs/CONFIGURACOES_USUARIOS_PERFIS.md`: decisão e estado da entrega.

## 5. Migrations e preflight

A fundação foi implantada no Supabase remoto em migrations versionadas. A migration base depende do schema existente e não é um baseline para projetos vazios.

O preflight rejeita vínculos em que `usuarios.unidade_id` pertence a empresa diferente de `usuarios.empresa_id`; nenhum dado incompatível foi encontrado no destino autorizado. Não houve correção ou remoção silenciosa de dados.

As migrations remotas registradas nesta etapa são:

- `administrative_user_read`;
- `fix_authz_reader_identity`;
- `optimize_administrative_read_rls`.

A migration de correção passou a obter o subject do JWT pelo contexto da requisição dentro da role restrita, sem depender de `USAGE` sobre o schema gerenciado `auth`. A migration de otimização consolidou policies de leitura preservando a semântica de leitura própria e leitura administrativa por empresa.

## 6. Modelo e justificativa

As consultas existentes continuam lendo `usuarios` e `usuario_perfis`. As policies SELECT usam `private.empresa_leitura_usuarios()`, sem parâmetros, `STABLE`, `SECURITY DEFINER`, `search_path=''`. Não foi criada RPC pública nem necessário alterar service/hook para a leitura.

O proprietário `bpf_authz_reader` é NOLOGIN, NOINHERIT, NOSUPERUSER, NOCREATEROLE, NOCREATEDB, NOREPLICATION e NOBYPASSRLS. Recebe SELECT somente nas colunas necessárias de cinco tabelas, com policies próprias. A função não executa como postgres nem como dono das tabelas.

EXECUTE é permitido somente a `authenticated`; `anon` e `service_role` não recebem execução do helper. O frontend continua sem qualquer credencial administrativa.

## 7. Isolamento multiempresa

O helper obtém a identidade autenticada e retorna uma empresa autorizada ou NULL. A policy compara `usuarios.empresa_id` a esse resultado independentemente do filtro enviado pelo navegador. Vínculos administrativos exigem usuário na empresa autorizada e perfil global de sistema ou da mesma empresa.

A policy de leitura própria permanece válida para bootstrap. Uma identidade sem permissão administrativa não recebe a listagem da empresa. Cadastros sem empresa não são enumeráveis por administradores de empresas.

A validação no Supabase remoto confirmou que a sessão administrativa recebe apenas a empresa autorizada e não visualiza registros de empresa externa.

## 8. Validação de permissões no servidor

O helper exige usuário existente, `ativo=true`, `status='ativo'`, empresa não nula e os códigos `configuracoes.visualizar` e `usuarios.gerenciar`, provenientes de perfis ativos compatíveis. Não se utiliza nome de perfil, empresa enviada pelo cliente ou `user_metadata` para autorizar.

Os filtros e verificações adicionais do service permanecem como defesa do cliente, sem substituir RLS.

## 9. Correção de v_meu_contexto

A view mantém as colunas/aliases, `security_invoker=true` e o filtro pelo próprio `auth.uid()`. O JOIN de perfis exige perfil ativo e escopo compatível. Perfis inativos ou incompatíveis e suas permissões deixam de compor os arrays.

A validação remota confirmou uma linha de contexto para a identidade testada, com empresa, unidade, perfil e permissões coerentes.

## 10. Integridade Empresa x Unidade

Existe UNIQUE em `unidades(id, empresa_id)` e FK composta `usuarios(unidade_id, empresa_id)` para esse par, com `NO ACTION`. Unidade nula continua permitida; unidade de outra empresa e alteração incompatível são rejeitadas.

A inspeção remota após aplicação encontrou zero vínculos usuário/unidade incompatíveis.

## 11. Pendentes: desenho futuro

Convite deve ser emitido por comando autorizado no servidor, vinculado à empresa/unidade, com token armazenado por hash, expiração e uso único. Solicitação de vínculo não concede acesso; deve ter destino validado, controle contra enumeração e aprovação por ator autorizado.

A aprovação deve revalidar empresa, unidade, perfis delegáveis e estado atual na mesma transação. Nunca usar empresa/perfil de metadata editável como autorização nem listar todos os cadastros sem empresa.

## 12. Auditoria futura

Cada comando de aprovação, bloqueio, unidade, empresa, perfis ou permissões deve registrar atomicamente ator autenticado, horário do servidor, empresa/unidade, ação, alvo, antes/depois, justificativa e contexto suficiente para auditoria. Se o registro falhar, a alteração deve falhar.

A trilha deve ser imutável para o cliente, com leitura restrita. Transferência de empresa exige fluxo específico e revisão de vínculos. Deve ser preservado pelo menos um administrador válido e impedida autoelevação indevida com validação transacional e controle de concorrência.

## 13. Riscos e limites

- As escritas administrativas permanecem bloqueadas; leitura segura não implica autorização para alterar dados.
- Policies/grants adicionais futuros podem ampliar acesso por composição; revisar o grafo e executar a suíte a cada mudança.
- Cascatas existentes, integridade de vínculos usuário/perfil e ausência de auditoria persistente precisam de revisão antes de qualquer escrita.
- A proteção contra senhas vazadas do Supabase Auth permanece desabilitada e deve ser tratada separadamente.
- Advisors de performance apontam FKs sem índice de cobertura e pontos de otimização de RLS; não bloqueiam a entrega funcional atual, mas devem ser tratados em etapa própria.
- `private` deve permanecer fora dos schemas expostos pela API; não há função nova em `public` para a autorização administrativa.
- Build conserva aviso de chunk principal acima de 500 kB; não impede execução.

## 14. Build

`npm.cmd run build`: aprovado, TypeScript e Vite. Aviso de tamanho acima de 500 kB no chunk principal, já existente. PGlite não integra o bundle do frontend.

## 15. Lint

`npm.cmd run lint`: aprovado, sem erros. `git diff --check`: aprovado; apenas avisos de conversão LF/CRLF no ambiente Windows.

## 16. Testes

- `npm.cmd run test:e2e`: 21 aprovados em Chrome.
- `npm.cmd run test:db`: aprovado em PostgreSQL efêmero em memória, incluindo preflight, isolamento multiempresa, permissões, perfil inativo, FK composta e rollback das fixtures.
- Validação remota pós-migration: helper restrito, `security_invoker`, ACLs, ausência de escrita para `authenticated`, zero vínculos organizacionais incompatíveis e leitura administrativa limitada à empresa do ator.
- As fixtures SQL permanecem exclusivas para ambiente isolado e não devem ser executadas em produção.

## 17. Git

A implementação e as migrations estão versionadas no branch `feature/supabase-auth`. O estado remoto do banco foi validado depois da aplicação. O fluxo de desenvolvimento passa a ser: Orquestrador e agentes definem a mudança, implementação é feita no GitHub/Supabase, e a validação local ocorre após `git pull`.

## 18. Próximo passo

Implementar a fundação de escritas administrativas em duas etapas:

1. backend/banco: trilha de auditoria e comandos transacionais seguros para aprovação, alteração de status, unidade e perfis, com isolamento multiempresa, proteção contra autoelevação e perda do último administrador;
2. frontend: habilitar as ações administrativas em `Configurações → Usuários` somente depois que os comandos de backend estiverem validados.

Nenhuma escrita administrativa deve ser habilitada por acesso direto às tabelas.
