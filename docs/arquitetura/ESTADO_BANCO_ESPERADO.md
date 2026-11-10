# Estado Esperado do Banco — Administração

Este documento descreve o estado final esperado após as migrations administrativas validadas. Ele não substitui migrations nem schema dump; serve como contrato arquitetural para revisão dos agentes 02, 03, 07, 08 e 09.

## Roles

### `bpf_authz_reader`
- `NOLOGIN`;
- `NOINHERIT`;
- `NOBYPASSRLS`;
- possui apenas os acessos necessários aos helpers de autorização;
- funções auxiliares relevantes são `SECURITY DEFINER`, com `search_path=''`;
- não deve ser utilizável diretamente por `authenticated`.

### `bpf_admin_writer`
- `NOLOGIN`;
- `NOINHERIT`;
- `NOSUPERUSER`;
- `NOBYPASSRLS`;
- possui apenas grants de tabela/coluna exigidos pelos comandos administrativos;
- é owner das funções privadas de escrita quando aplicável;
- o deployer `postgres` pode receber `SET ROLE` temporariamente durante uma migration, mas o estado final deve remover essa capacidade quando não houver migration subsequente dependente dela.

## `authenticated`

### Escrita administrativa direta
Não deve possuir `INSERT`, `UPDATE` ou `DELETE` direto em:

- `usuarios`;
- `usuario_perfis`;
- `perfis`;
- `perfil_permissoes`;
- `empresas`;
- `unidades`;
- `setores`;
- `auditoria_eventos`.

### Leitura
Leitura pode existir quando necessária, sempre subordinada a RLS e ao escopo funcional correspondente.

`auditoria_eventos` pode conceder `SELECT` a `authenticated`, mas a policy deve limitar à empresa retornada por autorização com `auditoria.visualizar`.

## RPCs administrativas públicas

As funções públicas são `SECURITY INVOKER`, executáveis apenas por `authenticated` quando aplicável e chamam funções privadas controladas.

Esperadas no Marco 01:

- `admin_usuario_alterar_status`;
- `admin_usuario_alterar_unidade`;
- `admin_usuario_alterar_perfil`;
- `admin_usuario_vincular_convite`;
- `admin_empresa_atualizar`;
- `admin_unidade_salvar`;
- `admin_setor_salvar`;
- `admin_perfil_criar`;
- `admin_perfil_atualizar`.

`anon` e `service_role` não devem receber exposição pública por conveniência nessas wrappers.

## Segurança multiempresa

- contratos atuais recebem `p_empresa_id` explícito e validam a empresa contra JWT, identidade ativa e membership/permissões canônicas; a seleção do frontend não concede autorização;
- wrappers antigos resolvem apenas a empresa principal e delegam aos mesmos comandos canônicos; revogar o vínculo bloqueia leitura e escrita mesmo que perfis legados permaneçam;
- unidade deve pertencer à mesma empresa;
- perfil deve ser global de sistema compatível ou pertencer à empresa;
- usuário alvo deve estar no mesmo tenant, salvo o fluxo específico de convite pendente com alvo explícito;
- auditoria deve usar a empresa autorizada da operação e identificar o membership do ator;
- usuário pendente sem empresa não pode ser enumerado globalmente.

## Teto de delegação

Um ator não pode criar/editar perfil ou atribuir perfil que resulte em permissões que ele próprio não possui. Essa regra deve ser garantida no backend e coberta por teste adversarial.

## Último administrador

Operações que possam remover a capacidade administrativa efetiva devem preservar pelo menos um administrador efetivo por empresa. O desenho deve considerar concorrência, não apenas execução sequencial.

## Auditoria

- cliente não escreve diretamente;
- comandos administrativos registram eventos atomicamente;
- cada evento registra ator, empresa, entidade, registro, ação, antes/depois, justificativa e contexto quando aplicável;
- leitura é somente da própria empresa e requer permissão funcional.

## Invariantes para validação

- RLS habilitado nas tabelas expostas;
- nenhuma função `SECURITY DEFINER` relevante sem `search_path` seguro;
- nenhuma migration aplicada remotamente é reescrita;
- fixture local deve representar o estado mínimo necessário para reconstruir a cadeia;
- nomes de policies/triggers/indexes devem ser únicos ou substituídos explicitamente;
- grants de coluna devem cobrir todas as colunas lidas por `%ROWTYPE` ou queries internas;
- estado final de memberships/`SET ROLE` deve ser explicitamente verificável.

## Estado adicional 32 — Administração por tenant

`bpf_tenant_admin` é NOLOGIN, NOINHERIT, NOSUPERUSER, NOBYPASSRLS, sem SET por authenticated ou postgres no estado final. Implementações privadas SECURITY DEFINER pertencem a essa role; wrappers públicos são SECURITY INVOKER, todos com search_path vazio. ACLs são ajustadas antes da transferência de owner. Helpers de autorização pertencem a postgres com acesso privado restrito; a variável local de escopo sozinha não autoriza nenhuma operação.

Contratos públicos/privados: `admin_contexto_ler` e `admin_usuario_status_tenant`, `admin_usuario_unidade_tenant`, `admin_usuario_perfil_tenant`, `admin_empresa_tenant`, `admin_unidade_tenant`, `admin_setor_tenant`, `admin_perfil_tenant`. A leitura usa whitelist de recursos, JSON `{data,count}`, ordenação determinística e páginas de até 500 linhas; não oferece SQL dinâmico do cliente. Não existe fallback para leituras administrativas legadas no frontend.

A role recebe apenas SELECT de identidade e grants de coluna nas relações do tenant. Não escreve em usuarios ou usuario_perfis. Status/unidade/perfil são alterados em usuario_empresas/usuario_empresa_perfis; alterações globais de identidade estão fora deste fluxo. Não pode trocar empresa, owner, identidade ou campos fora do contrato. Perfis globais são somente leitura; teto de delegação e perfil em uso são verificados antes da mutation. Inativação protege próprio vínculo, último administrador efetivo e último owner ativo.

Toda escrita valida acesso, obtém lock de empresa, revalida permissão, bloqueia linha comercial, valida modo de escrita e alvos, muda estado e registra auditoria na mesma transação. O escopo GUC anterior é restaurado em sucesso/erro. O convite server-only verifica o ator real antes e depois do lock e respeita trial/somente leitura. Os contadores de uso/quota, billing e checkout dão precedência ao membership canônico sobre o fallback legado.

As 17 suites históricas validam o contrato até31; nove suites compatíveis são repetidas no estado32, além da matriz nova de administração e QA secundário. Testes antigos que exigem alteração da identidade global representam o contrato histórico, não são usados como expectativa pós32. A verificação remota de metadados não substitui smoke autenticado, concorrência PostgreSQL ou advisors.


## Retomada da32 pendente — 10/11/2026

A32 não depende mais de nomes das policies do baseline: quatro guards SELECT restritivos próprios limitam todas as permissivas aplicáveis. A verificação final confere predicados e dependências por OID, não apenas nomes. Antes do primeiro DDL, a transação exige o mesmo SELECT de 17 precondições executado pelo helper antes do push, incluindo fontes/ACLs legadas e ausência de estado misto. As funções privadas de compatibilidade perdem EXECUTE de PUBLIC/anon/service_role sob seus owners; os quatro convites antigos ficam fechados também para authenticated. O canal server-only atual é preservado. Ver detalhes e limitações no plano EMPRESA-TESTE-DOCUMENTOS.
