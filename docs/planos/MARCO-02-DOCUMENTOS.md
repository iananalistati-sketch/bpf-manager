# Marco 2 — Revisão consolidada de Documentos

Revisão local sobre `feature/supabase-auth`, base `4b3228774d6c4b60ba2a12b6049f758906557a54`. Nenhuma aplicação remota foi executada neste ciclo.

## Contrato consolidado

- `documentos` preserva identidade e código; `documento_versoes` guarda título, tipo, unidade, descrição, prazo e evidências de cada versão. Arquivos futuros devem referenciar `documento_versoes.id` em Storage privado, sem substituir evidências publicadas.
- Durante a elaboração de v2, v1 permanece vigente e consultável. O cabeçalho mantém os metadados vigentes até publicar v2. A listagem mostra a versão mais recente e `vigente_numero`/`vigente_revisao_prevista_em`; o histórico devolve snapshots completos.
- Publicar v2 torna v1 obsoleta e gera `documento.versao_substituida`, além de `documento.status_alterado` para v2. Tudo participa da mesma transação.
- Permissões por membership: criar exige `documentos.criar`; editar, encaminhar/concluir revisão e iniciar nova versão exigem `documentos.editar`; aprovar, publicar e obsoletar exigem `documentos.aprovar`; consultas exigem `documentos.visualizar`.
- Identidade global, empresa, membership e perfil devem estar ativos. A empresa é resolvida a partir do alvo nas mutações por ID; alvos externos/inexistentes não revelam seu estado.
- O gate comercial considera a assinatura do tenant alvo. `active` e trial válido escrevem; demais estados são somente leitura. Empresas legadas sem assinatura mantêm compatibilidade. Nenhuma regra nova usa `usuarios.empresa_id` como autorização.
- As três mutações de documento existente aceitam `p_versao_id` opcional. A UI sempre envia a versão esperada; divergência retorna `40001`. Clientes antigos continuam compatíveis, mas devem migrar para enviar esse parâmetro.
- A UI preserva a unidade original na edição e distingue erro comercial de ausência de assinatura. Erro comercial bloqueia controles de escrita, mantendo consulta e tentativa de atualização de contexto. Respostas antigas não reaplicam contexto, lista ou histórico após troca de tenant.

## Correções e compatibilidade

As 30 migrations anteriores permanecem intactas. A corretiva aditiva `20261015203000_document_control_integrity.sql` acrescenta snapshots, FK composta unidade/empresa no documento, autorização antes do lock/estado e auditoria da substituição.

O upgrade faz backfill de documentos com uma versão. Se encontrar múltiplas versões preexistentes, aborta antes de DDL com `55000`: os metadados históricos precisam ser reconciliados com evidências reais em tarefa específica. Copiar o título atual para versões antigas fabricaria histórico. O harness verifica upgrade v1 e rejeição atômica de histórico ambíguo.

O manifesto npm foi realinhado aos ranges já registrados no lockfile (`react-hooks ^7.1.1`, `react-refresh ^0.5.6`); não houve atualização de lockfile. O Playwright usa `npm.cmd` no Windows e `npm` em outros sistemas. Chrome continua padrão; `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` permite apontar um Chromium instalado.

## Matriz e gates

- Agente 08: **APROVADO** após replay cumulativo, inspeção de roles/ACL/RLS/search_path e execução das mutações.
- Agente 09: **APROVADO** após revisão adversarial consolidada e PoC do erro de autorização.
- Agente 07: **APROVADO** após cruzar contratos SQL, frontend, autenticação, testes e limites documentados, sem bloqueadores de integração.
- A suíte SQL executa chamadas diretas das quatro RPCs de escrita; viewer, tenant e alvo adulterados, perfil/membership/identidade/empresa desativados, fases editar/aprovar independentes, estados comerciais bloqueados, versões antigas, estados inválidos e rollback com falha injetada na auditoria.
- Publicação com falha no último evento comprova rollback do cabeçalho, versão nova, versão anterior e auditoria de substituição. Testes cobrem JWT claims-only e membership secundário com assinatura independente da empresa primária.
- Playwright cobre v1/v2, edição preservando unidade, permissões separadas, rota/menu, erro/recuperação, consulta somente leitura, payload de versão esperada, respostas atrasadas e layouts de 375/768/1440 px.
- O teste SQL cria temporárias como deployer com grants mínimos; auditoria administrativa é inspecionada como deployer, sem conceder privilégios ao editor documental.

QA local em 15/10/2026: `npm run validate:local` terminou com exit code 0: preflight, **31 migrations / 17 suítes SQL**, TypeScript/build, ESLint e **49 testes Playwright aprovados** (nenhum skipped). Execução Linux com Node 24.19.0, npm 11.9.0 e `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium`; foram usados dois workers. Nenhuma chamada ao Supabase oficial foi necessária. O aviso de chunk acima de 500 kB permanece não bloqueante. Os seletores antigos de heading e badge de Documentos foram tornados exatos para distinguir conteúdo e mensagens de feedback.

## Limites e rollout

- **Não fazer deploy antes do checkpoint local verde.** Confirmar no Supabase oficial quais migrations estão pendentes; não presumir que somente a migration 30 esteja pendente agora, pois este ciclo acrescenta a 31. Quando autorizado, usar Supabase CLI preservando timestamps e verificar o estado remoto depois.
- **Nenhuma concessão automática de `documentos.*`.** Antes de habilitar o módulo remotamente, revisar os perfis destinatários e atribuir as permissões por backend autorizado. O teto de delegação impede que um administrador sem essas permissões as conceda a si mesmo. Não usar bypass no frontend nem atribuir a todos os perfis.
- As RPCs documentais mantêm o owner privilegiado usado pela camada comercial anterior: `SECURITY DEFINER`, `search_path=''`, ACL restrita e tabelas sem acesso direto para `anon`, `authenticated` ou `service_role`. RLS está habilitada, mas o owner do deployer não depende dela; a autorização explícita das RPCs continua sendo a barreira efetiva. Uma role documental restrita é evolução de defesa em profundidade, não foi introduzida nesta revisão.
- A consulta administrativa de auditoria segue o tenant primário legado. O histórico documental tenant-aware permanece disponível para memberships secundários; a modernização da auditoria administrativa é escopo separado.
- PGlite prova replay e comportamento SQL local, não operação real de PostgREST nem concorrência entre conexões PostgreSQL. Locks pai→versão e índices únicos foram revisados; concorrência real e smoke hospedado ficam para o gate remoto.
- Storage/anexos reais, revisão com devolução/reprovação, segregação obrigatória de pessoas e Agenda BPF continuam fora desta entrega. O build ainda emite aviso de chunk principal acima de 500 kB.

Checkpoint único no Windows: `npm.cmd run validate:local`. No Linux: `npm run validate:local`. Não requer credenciais do Supabase oficial; os testes E2E interceptam o backend de teste.

## Arquivos deste ciclo

- `package.json`, `playwright.config.ts`: dependências e execução portável.
- `scripts/test-db.mjs`: upgrade documental sob dados preexistentes.
- `src/components/AuthProvider.tsx`, `src/lib/authContext.ts`: gerações de sessão/tenant e erro comercial explícito.
- `src/modules/documentos/pages/DocumentosPage.tsx`, `src/modules/documentos/documentos.css`: workflow, snapshots, permissões, unidade, histórico e responsividade.
- `supabase/migrations/20261015203000_document_control_integrity.sql`: corretiva aditiva.
- `supabase/tests/document_control_foundation.sql`: regressões funcionais e adversariais.
- `tests/documentos.spec.ts`, `tests/documentos-regression.spec.ts`: seletores precisos e regressões de interface.
- `docs/REFERENCIA_PROJETO.md`, este plano: contratos, decisões e limites de rollout.


## Preflight remoto com senha local — 16/10/2026

O usuario confirmou o checkpoint local. O Supabase CLI 2.121.0, entretanto, respondeu HTTP400 na criacao de login temporario: a API de gerenciamento recebeu ECONNREFUSED ao conectar ao PostgreSQL. Repetir o comando sem alterar a autenticacao nao resolve essa dependencia.

Foi acrescentado `npm.cmd run supabase:preflight` (Linux/macOS: `npm run supabase:preflight`). Ele:

- Exige o checkout vinculado ao projeto oficial antes de solicitar credenciais.
- Reusa SUPABASE_DB_PASSWORD ja configurada ou pede a senha PostgreSQL em entrada oculta, sem PowerShell e sem valores no historico do terminal. A senha do banco e diferente da senha de login da aplicacao.
- Usa a rota suportada pelo CLI que dispensa criar um login temporario. Mantem o fallback IPv4/pooler do CLI, sem alterar TLS, DNS, banco ou vinculo.
- Fixa CLI 2.121.0, projeto oficial, perfil `supabase` e diretório do checkout. Executa Node+`npm-cli.js` com argumentos separados e sem shell, inclusive em caminhos Windows com espacos.
- Executa somente `migration list --linked` e, se houver sucesso, `db push --linked --dry-run --skip-vault`. Nunca executa push real, reset ou repair. Nenhum argumento adicional e aceito.
- Passa a senha apenas pelo ambiente do subprocesso, desativa debug herdado, nao grava credenciais e expurga valores da saida (inclusive entre chunks). Em overflow, descarta toda a saida. Para no primeiro erro e mantem seu status de falha.

Os testes de tooling usam senhas ficticias e CLI substituto local, sem conectar ao Supabase. Cobrem segredo, comandos fixos, projeto, cancelamento, redacao e interrupcao por falha. A compatibilidade Windows foi simulada; ainda depende da execucao no computador do usuario.

A alternativa contorna a chamada da API de login temporario; nao recupera um PostgreSQL realmente indisponivel. Se a conexao com senha tambem falhar, o banco remoto continua sendo uma dependencia externa. O dry-run mostra pendencias, mas nao aplica SQL nem verifica as precondicoes da corretiva 31. A aplicacao remota permanece pendente.

Fontes do comportamento: Supabase CLI tag v2.121.0, `apps/cli/src/command-internal/db-config.layer.ts`, `config/project-ref.layer.ts` e `command-internal/db-push-core.ts` no repositorio oficial `supabase/cli`.


Gates 07 e 09 do helper: APROVADOS. QA deste bloco: `validate:local` com exit code 0 (31 migrations, 17 suítes SQL, build, lint e 49 E2E); depois do ajuste de lifecycle da entrada, os 16 testes de tooling passaram novamente. Prompt oculto tambem foi exercitado em PTY Linux real, com senha ficticia, e encerrou com exit code 0. Sem execucao Windows real e sem acesso remoto. Nenhuma migration anterior foi modificada.
