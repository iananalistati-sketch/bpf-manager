# Empresa exclusiva de teste — Documentos e Administração

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

Um vínculo prévio exige uma conta de teste exclusiva, não a remoção ou transferência da conta existente. Outros impedimentos devem ser tratados conforme a causa efetivamente observada. O email informado pelo usuário permanece somente na conversa e na variável local, sem novo padrão embutido no repositório.

QA desta correção: 54 testes de tooling e 31 migrations/17 suítes SQL, incluindo os cenários QA e o diagnóstico contra contas ausentes/ambíguas/não confirmadas/banidas/excluídas/inativas, cadastro ausente e vínculos prévios. Marcador de outra conta ou com UUID inválido é diagnosticado sem casts de UUID. Nenhuma migration ou SQL de provisionamento/inspeção anterior foi alterado. Causa remota e criação da empresa TESTE continuam pendentes de evidência do computador autenticado.

Gates 08, 09 e 07 do diagnóstico: **APROVADOS**, sem bloqueadores conhecidos.
