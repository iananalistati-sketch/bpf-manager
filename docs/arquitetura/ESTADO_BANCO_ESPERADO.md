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

- comandos derivam empresa do ator autenticado, nunca de um `empresa_id` enviado pelo frontend;
- unidade deve pertencer à mesma empresa;
- perfil deve ser global de sistema compatível ou pertencer à empresa;
- usuário alvo deve estar no mesmo tenant, salvo o fluxo específico de convite pendente com alvo explícito;
- auditoria deve usar a empresa derivada do ator;
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