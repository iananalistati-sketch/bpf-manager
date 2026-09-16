# Leitura administrativa de usuários

Data: 16/09/2026. Entrega local preparada; aplicação remota pendente.

## 1. Decisão do Orquestrador

Ampliar somente SELECT de usuários e vínculos compatíveis da mesma empresa, com autorização no banco. Preservar leitura do próprio cadastro para bootstrap e manter todas as escritas administrativas indisponíveis. A implementação segue a referência do projeto e não altera a identidade visual.

## 2. Pareceres especializados

- **Dados / Supabase:** RLS nas tabelas existentes evita duplicar o contrato do service e oferece proteção também em consultas diretas. Helper privado com proprietário dedicado evita recursão entre usuários e perfis. Integridade empresa/unidade por FK composta, precedida de preflight.
- **Segurança / Permissões:** exigir identidade, ativo, status, empresa e as duas permissões no servidor; nenhum parâmetro de empresa confiado ao cliente. Proprietário sem login, bypass de RLS ou escrita. ACL e comentário da função devem preceder a transferência de proprietário. Nenhuma concessão administrativa automática.
- **Auditoria / Governança:** leitura não justifica uma auditoria parcial que prometa rastreabilidade de futuras escritas. Convites e comandos administrativos precisam de desenho transacional, histórico e autorização específica antes de implementação.
- **QA:** cenários positivos e negativos A/B, revogação, perfil inativo, filtro adulterado e FK devem ser exercitados no PostgreSQL, além dos testes de navegador. A validação local não substitui a validação no Supabase de destino.

## 3. Arquivos criados

- `supabase/migrations/20260916163832_administrative_user_read.sql`
- `supabase/tests/administrative_user_read.sql`
- `supabase/tests/fixtures/current_schema.sql`
- `scripts/test-db.mjs`
- `docs/LEITURA_ADMINISTRATIVA_USUARIOS.md`

## 4. Arquivos alterados

- `src/modules/configuracoes/components/UsuariosPanel.tsx`: apenas mensagem do escopo de consulta.
- `tests/configuracoes.spec.ts`: colega da mesma empresa e sete cenários adicionais de recusa pelo serviço.
- `package.json` / `package-lock.json`: PGlite como dependência exclusiva de desenvolvimento e `test:db`.
- `.gitignore`: artefatos temporários da CLI Supabase.
- `docs/REFERENCIA_PROJETO.md` e `docs/CONFIGURACOES_USUARIOS_PERFIS.md`: decisão e estado da entrega.

## 5. Migration e preflight

`20260916163832_administrative_user_read.sql`, criada via CLI Supabase, depende do schema existente. Não é um baseline para projetos vazios. Deve ser aplicada transacionalmente pelo mecanismo de migrations.

A inspeção remota anterior encontrou um usuário, nenhum usuário sem empresa, nenhum vínculo empresa/unidade incompatível e nenhum perfil atribuído de outra empresa. Não houve correção ou remoção de dados. A migration repete a verificação de empresa/unidade e aborta com erro se houver incompatibilidade. O teste local prova esse aborto. `lock_timeout=5s` limita a espera por locks; a constraint pode exigir janela de aplicação em tabelas maiores.

A tentativa de aplicação no projeto `yequhfvcbwnxmqobgumu` foi rejeitada pela revisão automática de aprovação, que exige autorização explícita do alvo e dos efeitos persistentes. **Nenhuma migration nem fixture desta etapa foi aplicada ao projeto remoto.** Não houve nova tentativa por outro mecanismo.

## 6. Modelo e justificativa

As consultas existentes continuam lendo `usuarios` e `usuario_perfis`. Novas políticas SELECT chamam `private.empresa_leitura_usuarios()`, sem parâmetros, `STABLE`, `SECURITY DEFINER`, `search_path=''`. Não foi criada RPC pública nem necessário alterar service/hook.

O proprietário `bpf_authz_reader` é NOLOGIN, NOINHERIT, NOSUPERUSER, NOCREATEROLE, NOCREATEDB, NOREPLICATION e NOBYPASSRLS. Recebe SELECT somente nas colunas necessárias de cinco tabelas, com políticas próprias: usuário/vínculos do ator, perfis ativos compatíveis, respectivas permissões e os dois códigos exigidos. O grafo dessas políticas não retorna às políticas administrativas do cliente, evitando recursão. A função não executa como postgres nem como dono das tabelas.

EXECUTE é removido de PUBLIC, anon, authenticated e service_role e devolvido apenas a authenticated. USAGE no schema não confere acesso às tabelas. O CREATE temporário do proprietário é revogado após a transferência. O postgres mantém ADMIN da role que criou, sem INHERIT/SET ao final; clientes não recebem membership. O teste detectou e corrigiu uma tentativa redundante de conceder ADMIN de volta ao próprio concedente.

## 7. Isolamento multiempresa

O helper obtém `auth.uid()` e retorna uma empresa autorizada ou NULL. A policy compara `usuarios.empresa_id` a esse resultado, independentemente do filtro enviado pelo navegador. Vínculos administrativos exigem usuário na empresa autorizada e perfil global de sistema ou da mesma empresa. Perfis inativos do alvo podem continuar visíveis para revisão, mas não autorizam o ator.

A policy anterior de leitura própria continua válida. Portanto, uma identidade inativa/sem permissão pode ler o próprio cadastro para inicializar o contexto; ela **não recebe a listagem administrativa**. Cadastros sem empresa não são enumeráveis por administradores de empresas.

## 8. Validação de permissões no servidor

O helper exige usuário existente, `ativo=true`, `status='ativo'`, empresa não nula e os códigos `configuracoes.visualizar` **e** `usuarios.gerenciar`. As permissões podem vir de perfis ativos distintos, desde que compatíveis. Não se utiliza nome de perfil, empresa do cliente ou `user_metadata` para autorizar. Os filtros e verificações adicionais do service permanecem como defesa do cliente, sem substituir RLS.

## 9. Correção de v_meu_contexto

A migration mantém as colunas/aliases, `security_invoker=true` e o filtro pelo próprio `auth.uid()`. O JOIN de perfis passa a exigir ativo e escopo compatível. Perfis inativos e suas permissões deixam de compor os arrays. Grants excedentes da view são reduzidos a SELECT para authenticated.

## 10. Integridade Empresa x Unidade

Adiciona UNIQUE em `unidades(id, empresa_id)` e FK `usuarios(unidade_id, empresa_id)` para esse par, com NO ACTION. O CHECK anterior que exige empresa quando há unidade e a FK simples existente são preservados. Unidade nula continua permitida; unidade de outra empresa e transferência da empresa de uma unidade referenciada são rejeitadas. A combinação com o comportamento anterior de exclusão de unidade deve ser revisada antes de habilitar qualquer operação destrutiva.

## 11. Pendentes: desenho futuro

Convite emitido por comando autorizado no servidor, vinculado à empresa/unidade, com token armazenado por hash, expiração e uso único. Solicitação de vínculo não concede acesso; deve ter destino validado, controle contra enumeração e aprovação por ator autorizado. A aprovação revalida convite/solicitação, empresa, unidade e perfis delegáveis na mesma transação. Nunca usar empresa/perfil de metadata editável como autorização nem listar todos os cadastros sem empresa.

## 12. Auditoria futura

Cada comando de aprovação, bloqueio, unidade, empresa, perfis ou permissões deve registrar atomicamente ator autenticado, horário do servidor, empresa/unidade, ação, alvo, antes/depois, justificativa, ID da solicitação e versão esperada. Se o registro falhar, a alteração deve falhar. Trilha imutável para o cliente, leitura restrita, retenção definida e histórico de concessão/revogação. Transferência de empresa exige fluxo específico e revisão de vínculos. Preservar último administrador e impedir autoelevação com validação transacional e controle de concorrência. Nenhuma tabela ou trilha fictícia foi criada nesta etapa.

## 13. Riscos e limites

- Validação local usa PostgreSQL 18.3 via PGlite; o remoto inspecionado usa PostgreSQL 17.6. A fixture reconstrói somente os objetos necessários e não é um dump integral nem valida PostgREST/Auth reais. Validar também no destino autorizado antes da liberação.
- A aplicação remota permanece pendente; a tela remota continuará retornando apenas o próprio cadastro até a migration. A mensagem nova não afirma completude da listagem.
- Políticas/grants adicionais futuros podem ampliar o acesso por composição OR; rever o grafo e executar a suíte a cada mudança.
- O catálogo global já era visível a authenticated. A migration não cria uma nova policy `USING (true)` nem torna o catálogo secreto.
- Cascatas existentes, integridade de vínculos usuário/perfil e ausência de auditoria persistente precisam de revisão antes de qualquer escrita. Perfis incompatíveis não autorizam nesta implementação, mas ainda precisam de integridade própria na próxima etapa.
- A inspeção anterior indicou proteção contra senhas vazadas desativada; nenhuma configuração de Auth foi alterada. Não houve reexecução de advisors após migration, pois ela não foi aplicada remotamente.
- `private` deve permanecer fora dos schemas expostos pela API. A configuração de exposição não foi verificada na API de gerenciamento nesta etapa; não há função nova em public.
- Build conserva aviso de chunk principal de 513,24 kB; não impede execução.

## 14. Build

`npm.cmd run build`: aprovado, TypeScript e Vite. Aviso de tamanho acima de 500 kB no chunk principal, já existente. PGlite não integra o bundle do frontend.

## 15. Lint

`npm.cmd run lint`: aprovado, sem erros. `git diff --check`: aprovado, sem erros de whitespace (Git informa conversão LF/CRLF do ambiente).

## 16. Testes

- `npm.cmd run test:e2e`: **21 aprovados** em Chrome, 13 segundos. Respostas HTTP interceptadas, nenhuma credencial real ou escrita remota. Inclui navegação, filtros, estados, detalhe somente leitura, dimensões 375/768/1440, contexto revogado e filtros adulterados.
- `npm.cmd run test:db`: **aprovado**. PostgreSQL efêmero em memória, migration executada como postgres sem SUPERUSER, com CREATEROLE e BYPASSRLS equivalentes às capacidades relevantes do deployer. Testes assumem authenticated para verificar RLS; o helper executa com sua role restrita.
- Banco cobre A/B em ambos os sentidos, consulta sem filtro e filtro adulterado, ausência de cada permissão, permissões combinadas entre perfis, inativo/bloqueado/pendente, ator sem empresa/inexistente/sem subject, perfil inativo/cruzado/global de sistema/global não sistema, FK cruzada, transferência de unidade, recusa de escrita, grants, ACL, owner, search_path e membership.
- Preflight de legado incompatível rejeitado; migration aplicada em fixture válida; fixtures de teste revertidas por ROLLBACK e ausência de resíduos verificada. Sem dependência de pgTAP.
- **Testes no Supabase remoto após migration: pendentes**, não executados por bloqueio de aprovação. Fixtures SQL não devem ser executadas em produção; usar clone/homologação autorizado, com transação e interrupção no primeiro erro.

## 17. Git

Alterações locais nos arquivos das seções 3 e 4. Nenhum commit ou push realizado. O arquivo temporário `supabase/.temp/cli-latest`, produzido pela CLI, foi removido; o diretório está ignorado. O status exibido pelo Git pode conservar uma entrada de intenção de adição desse artefato, criada antes da limpeza; não representa conteúdo para entrega.

## 18. Próximo passo

Obter autorização explícita para o alvo remoto e a alteração persistente; preferir homologação/clone antes da liberação no projeto em uso. Aplicar a migration versionada, conferir histórico/versão, grants e advisors e validar a leitura pela API autenticada. Executar os cenários SQL no ambiente isolado autorizado. Só então considerar esta fundação liberada no Supabase. Cadastro, aprovação, edição, bloqueio e gestão de perfis continuam fora do escopo.
