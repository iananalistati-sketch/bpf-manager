# Empresa TESTE — Documentos e Administração

> Procedimento atual: **QA secundário**, descrito a seguir. O procedimento v1 abaixo permanece como histórico da conta dedicada; ele não deve ser usado para uma conta que já tem empresa.

> **Retomada condicional da migração 32:** usar somente a revisão de 10/11/2026 após os gates e o checkpoint local verde. O próprio comando verifica o estado remoto antes de qualquer escrita; divergência bloqueia a retomada. A implantação remota ainda não está confirmada.

## Correção e retomada condicional — 10/11/2026

O trecho recebido do diagnóstico contém todas as 66 policies, as cinco roles restritas, 15 tabelas com RLS, o hash da view e as 31 versões esperadas, sem registro da32 ou role `bpf_tenant_admin`. Os nomes reais são `empresas_select_da_empresa`, `unidades_select_da_empresa`, `setores_select_da_empresa` e `perfis_select_visiveis`. O trecho não inclui funções e ACLs completas e, portanto, não comprova sozinho rollback.

A32 ainda pendente foi corrigida: quatro policies próprias `tenant_admin_primary_guard`, `AS RESTRICTIVE FOR SELECT TO authenticated`, intersectam as permissivas existentes, independentemente dos nomes. Elas não concedem acesso onde não há policy permissiva. As31 migrations já aplicadas não foram alteradas. Permissões das funções privadas de compatibilidade são ajustadas sob seus owners; quatro funções antigas de convite ficam sem EXECUTE para PUBLIC/anon/authenticated/service_role, preservando o canal server-only atual.

Antes do push, o helper executa o novo SELECT fixo `verify-tenant-admin-before-apply.sql`, hasheado no manifesto. Exige exatamente 17 booleans true: os oito checks documentais da31, executor correto, ausência de objetos32 inclusive overloads, fonte/owner/contrato/configuração de 22 funções alteradas, ACLs sem ampliação, view canônica conhecida, RLS/owners, roles sem privilégios inesperados/CREATE/SET/INHERIT, ausência de escrita direta de clientes e reconhecimento dos quatro convites antigos. Essa leitura verifica automaticamente os metadados que não couberam no envio do usuário. Permissões mais estreitas que o baseline são aceitas; permissões ampliadas são recusadas.

O mesmo SELECT é repetido no início da migração antes do primeiro DDL e comparado por teste ao arquivo separado. Qualquer flag false/NULL ou formato inesperado bloqueia. O payload local é revalidado depois da leitura e antes do push. Se a32 já estiver registrada, não repete push: exige o verificador final com quatro guards, predicados/dependências corretos, helper com fonte/owner/ACL seguros, 13 funções legadas limitadas e quatro convites antigos desativados. Não faz repair nem adota um estado misto.

Após gates internos e checkpoint local verde, usar o procedimento QA secundário abaixo com o e-mail original. `ADMIN_31_BLOQUEADO` informa somente os nomes dos checks divergentes e encerra antes da escrita; basta enviar essa saída curta para análise. Não é necessário copiar o diagnóstico inteiro novamente. Quando houver aplicação, a leitura posterior confirma histórico/estrutura e só então pode criar a TESTE. `QA_SECUNDARIO_PRONTO` permanece o resultado esperado, com onboarding real pelo login original.

Regressões locais cobrem as 66 policies reais (somente metadados no fixture), nomes arbitrários com permissiva adicional USING(true), ausência de permissivas, precondições em READ ONLY e rejeição de estado parcial antes do DDL. Em cada variante, a matriz completa de administração, isolamento, rollback de auditoria, compatibilidade e provisionamento QA é repetida; leituras diretas também são verificadas com empresas e vínculos ativos, evitando asserts em tabelas vazias. O verificador rejeita mudança de predicado/roles, perda de guard, exposição de helper/convites e mantém resultado estável com search_path diferente.

Validação em 10/11/2026: `validate:local` concluído com exit code 0: 78 testes de tooling, banco com as três variantes adicionais de policies, build, lint e 54 E2E sem skipped. Gates 08, 09 e 07: **APROVADOS**, sem bloqueadores na retomada condicional.

Implantação remota, smoke autenticado, advisors e concorrência PostgreSQL real permanecem pendentes. A validade deste conjunto não autoriza editar uma32 já registrada em outro ambiente.

## Diagnóstico do incidente — 09/11/2026

O usuário reportou erro `42704` no comando 118 da migration32: `empresas_select_empresa` não existe em `public.empresas`. Os quatro nomes usados pelos ALTER POLICY foram definidos somente no fixture pré-migrations; a cadeia versionada de 1 a 31 não os cria. A revisão anterior deixou passar essa dependência do baseline. O helper não iniciou a criação QA nessa chamada e reportou `ADMIN_NAO_CONFIRMADO`. O histórico de 31 versões, isoladamente, não comprova rollback ou ausência de efeitos da tentativa.

O novo comando `supabase:diagnose:administracao` usa o vínculo oficial, o perfil `supabase`, CLI2.121.0 e a sessão de senha PostgreSQL oculta já existentes. Executa exatamente um SELECT fixo enviado por stdin à Management API, com SHA256 separado e normalização exclusiva de CRLF. Não depende dos quatro nomes de policies e não lê registros Auth/aplicação, senhas, `pg_authid` ou statements de migrations. Coleta versões completas do ledger, RLS/owner de tabelas, policies com predicados e roles, grants de tabela/coluna, flags e memberships de roles, metadados/hashes de funções novas e antigas e hash da view de contexto. Configurações de funções são limitadas a search_path, sem dump de GUCs arbitrárias.

Após atualizar o código, executar no computador autenticado:

```powershell
git pull --ff-only origin feature/supabase-auth
npm.cmd run supabase:diagnose:administracao
```

Enviar a saída para revisão. O parser exige formato exato e limitado; stdout/stderr brutos do CLI são suprimidos em falhas e a saída final passa por expurgo da senha. `DIAGNOSTICO_ADMIN_CONCLUIDO` confirma somente coleta de metadados: não autoriza retry, repair, push ou criação QA. Se a consulta falhar, permanece bloqueado e não há repetição automática.

Na entrega diagnóstica de 09/11, a correção ainda dependia de observar esse estado. As 31 migrations aplicadas permanecem imutáveis e a 32 também não foi alterada nesta entrega diagnóstica. A alternativa local avaliada usa guards SELECT restritivos com nomes próprios para intersectar as permissivas existentes, evitando dependência dos nomes e bypass por OR. Essa alternativa não foi liberada remotamente. Antes de revisar qualquer migration pendente é necessário conferir ledger e vestígios da tentativa, incluindo funções/roles/policies/grants e compatibilidade legada.

Validação em 09/11/2026: `validate:local` terminou com exit code 0, 75 testes de tooling, banco, build, lint e 54 E2E sem skipped. O diagnóstico foi executado em transação READ ONLY, com policies ausentes/renomeadas e vestígios da migração 32 sem mudança do ledger de 31 versões; os cinco helpers legados foram conferidos e GUCs fora de search_path foram omitidos. Respostas malformadas/CLI com erro não vazam saída bruta nem provocam retry; a senha é expurgada inclusive de metadados válidos. Agentes 08, 09 e 07: APROVADO somente para diagnóstico; escrita remota permanece bloqueada.

## QA secundário — 03/11/2026

O responsável confirmou o uso do login original, que já possui empresa, unidade, memberships e perfis legados. A migration adicional `20261029160000_tenant_administration.sql` permite administrar a empresa selecionada com autorização canônica no backend. As 31 migrations aplicadas remotamente permanecem imutáveis.

O novo fluxo cria **BPF TESTE** como segundo vínculo da mesma identidade. Não muda `usuarios.empresa_id`, `usuarios.unidade_id`, status global, perfis legados ou vínculos anteriores. Cria somente empresa/unidade/perfil locais, membership owner e atribuição canônica; todas as permissões existentes são copiadas para o perfil local no momento da criação. Plano Business com limites configurados, trial real de 14 dias, referências de pagamento nulas e onboarding não iniciado. Não concede permissões futuras nem simula contratação.

Após os gates internos e o checkpoint local verde, no computador já vinculado ao projeto oficial:

```powershell
git pull --ff-only origin feature/supabase-auth
npm.cmd ci
if ($LASTEXITCODE -ne 0) { throw 'Instalação falhou; não aplicar migrações.' }
npm.cmd run validate:local
if ($LASTEXITCODE -ne 0) { throw 'Validação falhou; não aplicar migrações.' }
$env:BPF_QA_EMAIL = 'email-original-da-conta@example.com'
npm.cmd run supabase:setup:qa:secondary
```

Usar o e-mail original informado pelo usuário, sem acrescentar alias. A senha PostgreSQL é solicitada de forma oculta; não é a senha da aplicação. O helper exige login administrativo já existente do CLI, vínculo oficial, CLI fixa 2.121.0 e hashes das exatas 32 migrations/SQLs operacionais no manifesto secundário. O e-mail segue validado em hex e SQL por stdin; senha apenas no ambiente do subprocesso com expurgo de saída. Não cria conta Auth nem altera senha ou confirmação.

Com 31 migrations alinhadas, aplica somente a 32; com 32, não repete push. Verifica 11 checks estruturais, incluindo os oito documentais, owners/ACLs de 16 funções administrativas públicas/privadas, role sem escrita global/legada inclusive grants por coluna e RLS. Isso não comprova corpos remotos de funções, concorrência real ou smoke PostgREST. Antes de qualquer escrita o conjunto local é revalidado. Erros e respostas perdidas preservam o exit code e são seguidos de inspeção; não há retry automático, repair ou include-all. Se o push falhar, a criação QA não começa nesta chamada.

O bootstrap é um único DO como postgres e usa marcador separado `bpf:qa-secondary:v1`. Exige identidade confirmada/habilitada e principal ativo. Obtém locks, captura fingerprint da identidade e vínculos anteriores, cria o ambiente e compara a preservação antes de gravar auditoria `workspace.qa_secundario_preparado`. Falha integralmente se a preservação ou auditoria falhar. Um marcador existente não restaura permissões nem renova o prazo; a inspeção bloqueia divergência ou expiração.

Resultado esperado: `QA_SECUNDARIO_PRONTO`, ID da TESTE e prazo do trial. Entrar com o login original, selecionar **BPF TESTE** e concluir o formulário real de onboarding. O trial vencido permite leitura e bloqueia escrita. Testar Configurações e Documentos nesse tenant; não remover os vínculos principais. A execução remota deste procedimento ainda não foi realizada pelo agente.

A leitura administrativa e as mutations passam empresa explícita e validam JWT, identidade, membership, perfil e permissão canônicos. Os wrappers antigos continuam restritos à empresa principal e seguem a mesma revogação; o convite autenticado antigo foi retirado, permanecendo o canal server-only da Edge. Mudanças administrativas afetam o vínculo empresarial, nunca o status global da pessoa. Ver contrato em `docs/arquitetura/ESTADO_BANCO_ESPERADO.md`.

Validação local em 03/11/2026: `validate:local` concluído com exit code 0, 68 testes de tooling, replay das 31 migrations/17 suites históricas, aplicação da 32 com matriz adversarial/QA secundário e nove suites compatíveis repetidas no estado final, TypeScript/build, ESLint e 54 testes E2E sem skipped. Os cinco E2E novos distinguem empresa principal A de ativa B, negam fallback em RPC ausente, conferem payloads das mutations e descartam respostas atrasadas de leitura/escrita após troca/desmontagem. A matriz SQL verifica todas as escritas com permissão removida e rollback integral em falha de auditoria, convite server-only, oito wrappers públicos/privados, quota e drift de ACL inclusive grants por coluna. E2E usa backend interceptado; nenhum bootstrap ou deploy remoto foi executado pelo agente.

Gates 08, 09 e 07 desta atualização: **APROVADOS**, sem bloqueadores; Agente 10: **APROVADO** no escopo SaaS. Checkpoint do usuário e implantação remota permanecem pendentes.

## Histórico: QA v1 para conta sem vínculos


## Escopo autorizado

Em 16/10/2026, após confirmar as 31 migrations e os oito checks remotos, o usuário solicitou uma empresa de teste com todas as liberações necessárias para validar as implementações. O e-mail da conta foi informado na conversa; não é gravado em código, SQL versionado ou manifesto.

A empresa **BPF TESTE** terá uma conta exclusiva, uma unidade inicial e o perfil local **Administrador TESTE**, com todas as permissões existentes no momento da criação. O catálogo de permissões não concede acesso automaticamente a módulos ainda não implementados. O trial usa o plano Business existente e seus limites configurados, por 14 dias; depois, as regras comerciais normais bloqueiam escrita. Não há pagamento, checkout ou conversão fictícia.

## Por que uma conta exclusiva

Documentos aceita tenant ativo, mas algumas operações administrativas ainda resolvem a empresa principal em `usuarios.empresa_id`. Adicionar TESTE como vínculo secundário de uma conta real não permite validar toda Administração com isolamento garantido: uma tela poderia mostrar TESTE e uma RPC legada continuar atuando na empresa principal.

Por isso o comando exige uma conta já cadastrada e confirmada no Auth, habilitada, sem empresa, unidade, membership, perfil legado ou provisionamento anterior. `pendente` é o estado normal de uma conta nova, aceito pelo provisionamento canônico; identidades bloqueadas/inativas não são reativadas. Uma conta com vínculos anteriores é recusada, não movida para TESTE. O helper não cria usuários Auth, altera senhas ou envia convites.

## Execução operacional

No computador com o projeto oficial vinculado e o login administrativo Supabase já existente:

```powershell
git pull --ff-only origin feature/supabase-auth
$env:BPF_QA_EMAIL = 'conta-exclusiva@example.com'
npm.cmd run supabase:prepare:qa
```

Use o e-mail real da conta de teste no lugar do exemplo. A senha PostgreSQL é solicitada em entrada oculta ou reutilizada de uma vinculação segura de `SUPABASE_DB_PASSWORD`. O SQL é executado pela Management API com o login administrativo existente. Na CLI 2.121.0, `db query --linked` também resolve a conexão antes da chamada HTTP; a senha evita reintroduzir o erro de criação do login temporário.

O comando confere as 31 migrations locais pelos hashes aprovados, o vínculo/projeto/perfil/CLI fixos e os oito checks estruturais remotos antes de preparar dados. Não aceita argumentos adicionais. Os SQLs operacionais têm manifesto próprio com hashes; só CRLF é normalizado. O e-mail é validado e convertido em UTF8/hex para substituição, enviado por stdin, sem arquivo temporário nem SQL nos argumentos do processo. A senha permanece no ambiente do subprocesso com expurgo de saída e debug desativado.

## Transação e reexecução

Um único `DO` administrativo, como `postgres`, executa toda a criação atomicamente:

1. Obtém advisory lock pelo marcador único `bpf:qa-documentos:v1`, confere a conta e bloqueia sua identidade.
2. Usa `provisionar_trial_server` existente para criar empresa, unidade, vínculo owner, assinatura de 14 dias, onboarding e trilha inicial. A empresa TESTE torna-se a principal dessa identidade antes sem vínculos.
3. Alinha apenas o novo tenant ao Business nas relações de plano e assinatura, preservando `trialing`, datas e referências de cobrança nulas. O catálogo de planos/entitlements não é alterado.
4. Cria o perfil local com snapshot das permissões atuais e o atribui ao vínculo legado; a ponte existente sincroniza o membership. Remove somente a atribuição de Administrador que a própria função acabou de criar nessa conta, sem alterar o perfil compartilhado.
5. Guarda IDs, snapshot de permissões/entitlements e prazo no ledger de provisionamento e registra `workspace.qa_preparado`. A atribuição administrativa via CLI é explícita na auditoria; não se simula sessão JWT do usuário alvo.

O SQL não desativa RLS/triggers, não concede roles e não instala funções permanentes nem migrations. Falha na última auditoria reverte toda a criação.

Se o marcador já existe para o mesmo usuário, o `DO` não altera dados: a inspeção verifica identidade principal/canônica, unidade, perfil local, permissões do snapshot, trial/plano, onboarding e auditoria. Outro usuário, estado divergente, trial expirado ou acesso revogado não são reparados. O helper não acrescenta permissões futuras nem renova prazo. Dados de teste e onboarding concluído posteriormente são preservados.

Depois de qualquer tentativa de escrita, inclusive erro/queda de processo, uma leitura independente confere o estado. Estados possíveis:

- `QA_PRONTO`: ambiente confirmado pelos checks; o exit code de eventual falha anterior do CLI continua preservado.
- `QA_BLOQUEADO`: pré-condições da conta ou estado existente não permitem avançar; nenhuma escrita iniciada nessa chamada.
- `QA_NAO_CONFIRMADO`: a leitura ainda mostra conta elegível, sem ambiente confirmado. Uma requisição perdida pode continuar em andamento; não é prova de rollback.
- `QA_DIVERGENTE`: estado posterior não satisfaz os checks; não há reparo automático.
- `QA_INDETERMINADO`: a leitura posterior falhou; não repetir escrita sem diagnóstico.

## Validação e limites

Após `QA_PRONTO`, entrar na aplicação com a conta de teste e concluir o onboarding pelo formulário real. Isso também valida o fluxo implementado; o helper não marca onboarding como concluído com dados fictícios. Em seguida, validar Configurações e o fluxo Documentos v1/v2, com auditoria e isolamento. Smoke autenticado remoto, concorrência PostgreSQL real e advisors continuam separados da inspeção de metadados.

QA local: 31 migrations e 17 suítes SQL existentes, mais harness operacional de QA. Cobertura adicional: conta real/bloqueada/não confirmada/banida e role indevida recusadas; rollback com falha na auditoria final; criação única e replay sem alteração; revogação de permissão, trial expirado e membership bloqueado detectados; permissão futura não concedida; JWT da conta QA alcança contexto primário/canônico, comercial normal, criação administrativa de segunda unidade e workflow documental até vigente; cross-tenant negado e conta/catálogos reais preservados. O fixture adiciona campos de lifecycle Auth somente na transação local de teste, revertida ao final.

`validate:local` passou com build, lint e 49 E2E. Depois da correção da autenticação do helper, os testes de tooling foram reexecutados: 50 aprovados, sem skipped. O teste de stdin usa subprocesso Node real; os testes de CLI usam substitutos locais. Nenhuma empresa TESTE foi criada remotamente pelo agente: a execução no computador autenticado permanece pendente.

Gates 08, 09, 07 e 10: **APROVADOS**. O bloqueador de autenticação do preflight da CLI foi corrigido com a sessão de senha oculta já revisada; a mensagem após resposta de escrita perdida usa confirmação pendente, sem inferir rollback.

## Diagnóstico de QA_BLOQUEADO — 16/10/2026

O usuário reportou `QA_BLOQUEADO` antes de qualquer escrita. A saída original agregava várias condições em `conta_valida`/`conta_livre`, sem identificar o impedimento. Esse resultado não permite concluir que a conta tem empresa, não está confirmada ou sequer existe no Auth.

Foi acrescentado o comando estritamente de leitura:

```powershell
$env:BPF_QA_EMAIL = 'conta-exclusiva@example.com'
npm.cmd run supabase:diagnose:qa
```

Ele reutiliza projeto/CLI/perfil fixos e a senha oculta necessária ao preflight da CLI. Executa somente o novo SELECT hasheado `scripts/sql/diagnose-qa-account.sql`, sem chamar o provisionamento ou modificar confirmação, senhas, status, vínculos e permissões. Auth e cadastro da aplicação são contados separadamente, distinguindo também email ambíguo, banimento/exclusão, email do cadastro divergente e vínculos anteriores inclusive inativos. Marcador QA de outra identidade é informado apenas por booleano, sem expor seus dados.

A resposta tem exatamente 13 contagens e três booleanos; o formatter só imprime códigos `CAUSA_QA` conhecidos. Nenhum email, UUID, payload Auth ou metadado é retornado pelo SELECT. stdout/stderr brutos e exceções do CLI são suprimidos nesse diagnóstico, inclusive em falhas e JSON inválido. `DIAGNOSTICO_QA_CONCLUIDO` e exit code 0 confirmam apenas que a leitura foi concluída e interpretada, não que um ambiente foi criado ou esteja pronto.

O caminho `supabase:prepare:qa` agora chama esse mesmo diagnóstico automaticamente ao bloquear, reutilizando a sessão sem pedir senha novamente. Falha diagnóstica mantém `QA_BLOQUEADO`, exit code 1 e ausência de escrita. Para marcador da própria conta, também mostra os nomes dos checks de inspeção pendentes; não recomenda recriar nem reparar o ambiente automaticamente.

No procedimento v1, um vínculo prévio impede provisionamento; o novo fluxo secundário acima atende a conta existente sem remover ou transferir seus vínculos. Outros impedimentos devem ser tratados conforme a causa efetivamente observada. O email informado pelo usuário permanece somente na conversa e na variável local, sem novo padrão embutido no repositório.

QA desta correção: 54 testes de tooling e 31 migrations/17 suítes SQL, incluindo os cenários QA e o diagnóstico contra contas ausentes/ambíguas/não confirmadas/banidas/excluídas/inativas, cadastro ausente e vínculos prévios. Marcador de outra conta ou com UUID inválido é diagnosticado sem casts de UUID. Nenhuma migration ou SQL de provisionamento/inspeção anterior foi alterado. Causa remota e criação da empresa TESTE continuam pendentes de evidência do computador autenticado.

Gates 08, 09 e 07 do diagnóstico: **APROVADOS**, sem bloqueadores conhecidos.
