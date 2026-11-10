# Plano Integrado — Marco 01 Administração

## Estado atual

O projeto possui autenticação Supabase, leitura administrativa multiempresa, comandos administrativos auditados para usuários existentes e uma implementação em andamento para convites, estrutura organizacional, perfis customizados e auditoria consultável.

As migrations anteriores de leitura/escrita já aplicadas remotamente devem permanecer imutáveis. As migrations do Marco 01 ainda devem ser validadas integralmente antes de deploy remoto.

## Estado desejado

Administrador efetivo, conforme permissões e não por nome de perfil, deve conseguir no escopo da própria empresa:

- convidar/vincular usuários com unidade e perfis iniciais;
- alterar status, unidade e perfis de usuários;
- criar e editar perfis customizados sem poder delegar privilégios superiores aos próprios;
- administrar empresa, unidades e setores;
- consultar trilha de auditoria da própria empresa;
- preservar proteção contra autoelevação, cross-tenant e perda do último administrador efetivo.

## Dependências cruzadas

| Mudança | Dados | Segurança | Frontend | QA | Banco/Migrations | Auditoria |
| --- | --- | --- | --- | --- | --- | --- |
| Convite de usuário | RPC/Edge Function | alvo explícito, sem enumeração | modal convite | cenário positivo/negativo | grants/RLS de usuário pendente | evento de vínculo |
| Estrutura | empresa/unidade/setor | escopo empresa | CRUD | cross-company | grants coluna/ROWTYPE | antes/depois |
| Perfis customizados | perfil/permissão | teto de delegação | editor permissões | autoelevação | triggers/grants/RLS | criação/edição |
| Auditoria | consulta eventos | RLS por empresa | painel leitura | isolamento | grant SELECT + policy | imutável pelo cliente |

## Critérios de aceite

- nenhum `authenticated` possui escrita direta nas tabelas administrativas;
- todas as escritas passam por comandos controlados;
- `service_role` não aparece no frontend;
- usuário sem permissão não consegue chamar RPC com sucesso;
- IDs de outra empresa não permitem leitura/escrita;
- perfil criado/atribuído não pode conter permissão que o ator não possui;
- usuário pendente sem empresa não é globalmente enumerável;
- auditoria da empresa B não é visível na empresa A;
- último administrador efetivo não pode ser removido/bloqueado por operações concorrentes ou sequenciais;
- migrations executam em sequência limpa no fixture local;
- testes antigos foram revisados contra o comportamento novo;
- agentes 08, 09 e 07 estão sem bloqueadores;
- `test:db`, `build`, `lint` e `test:e2e` passam antes do checkpoint visual.

## Gates do marco

1. especialistas consultivos revisam o desenho;
2. Orquestrador consolida implementação;
3. Agente 08 valida banco/migrations;
4. Agente 09 valida segurança adversarial;
5. Agente 07 cruza fontes/contratos;
6. QA executa testes;
7. usuário valida local/visual;
8. Orquestrador aplica e verifica Supabase remoto.

## Regra de comunicação

Qualquer agente que encontre um problema deve informar `IMPACTA` com as áreas relacionadas. O Orquestrador deve reconsultar essas áreas antes de corrigir e avançar de gate. Correções locais não podem contradizer silenciosamente decisões de outro especialista.