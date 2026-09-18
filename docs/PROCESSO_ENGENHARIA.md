# Processo de Engenharia — BPF Manager

## Objetivo

Formalizar como os agentes especializados colaboram sem fragmentar a implementação. O Orquestrador é o único responsável por consolidar a solução final; os demais agentes atuam como especialistas consultivos e revisores.

## Princípio central

Nenhum agente trabalha em isolamento lógico. Todo achado relevante deve ser comunicado pelo Orquestrador aos agentes afetados antes da implementação ser considerada consolidada.

A comunicação ocorre por um ciclo explícito de **entrada → análise especializada → impactos cruzados → consolidação → revisão → gate**.

## Papéis

### Orquestrador / Tech Lead
- recebe a demanda;
- consulta a referência do projeto;
- seleciona os especialistas;
- reúne as recomendações;
- resolve conflitos;
- define arquitetura e ordem de implementação;
- implementa/consolida a mudança;
- distribui achados cruzados aos agentes afetados;
- decide se o gate pode avançar.

### Especialistas consultivos
- Produto/BPF;
- Dados/Supabase;
- Segurança/Permissões;
- Frontend/UX;
- Auditoria/Governança.

Eles sugerem regras e riscos, mas não produzem implementações independentes concorrentes.

### Agentes de controle
- QA Funcional;
- Validação de Fontes;
- Banco/Migrations;
- Segurança Adversarial.

Eles analisam a solução já consolidada e devolvem bloqueadores/atenções.

## Protocolo de comunicação entre agentes

Cada especialista deve devolver ao Orquestrador uma ficha curta:

```text
AGENTE:
RECOMENDAÇÃO:
DEPENDÊNCIAS:
IMPACTA:
RISCOS:
CRITÉRIOS DE ACEITE:
DÚVIDAS/CONFLITOS:
```

O campo `IMPACTA` identifica outros agentes que precisam receber aquela conclusão. Exemplos:

- Segurança altera RLS → impacta Dados, Banco/Migrations, QA e Validação de Fontes;
- Dados altera contrato de RPC → impacta Frontend, QA e Segurança;
- Frontend depende de nova permissão → impacta Segurança, Dados e QA;
- Auditoria exige novo evento → impacta Dados, Segurança e QA.

O Orquestrador deve resolver conflitos antes de implementar. Não é permitido deixar duas recomendações incompatíveis coexistirem silenciosamente.

## Gates obrigatórios

### Gate 1 — Arquitetura
Produto, Dados, Segurança, Frontend e Governança retornaram recomendações; dependências e conflitos foram consolidados.

### Gate 2 — Implementação consolidada
O Orquestrador implementou uma única solução coerente, sem frentes independentes concorrentes.

### Gate 3 — Banco/Migrations
Agente 08 revisou cadeia acumulada, roles, grants, owners, RLS, DDL, fixture e estado final esperado.

### Gate 4 — Segurança adversarial
Agente 09 tentou bypass, cross-tenant, autoelevação e chamadas diretas de backend.

### Gate 5 — Validação integrada
Agente 07 revisou contratos entre banco, frontend, testes e documentação e confirmou ausência de bloqueadores conhecidos.

### Gate 6 — QA automatizado
`validate:db`, `test:db`, `build`, `lint` e `test:e2e` aplicáveis passaram.

### Gate 7 — Checkpoint do usuário
Somente após os gates anteriores o usuário recebe comandos de validação local/visual.

### Gate 8 — Deploy remoto
Migrations/funções são aplicadas remotamente apenas após checkpoint verde; depois são executadas verificações remotas e advisors.

## Regra para bloqueadores

Qualquer agente pode marcar um achado como `BLOQUEADOR`. Nesse caso:

1. o Orquestrador interrompe o avanço do gate;
2. identifica agentes impactados;
3. compartilha o achado com esses agentes;
4. consolida uma correção única;
5. repete os gates afetados.

O usuário não deve ser usado como executor de descoberta de erros que poderiam ser encontrados nos gates internos.

## Artefatos de coordenação

Para cada marco relevante devem existir, quando aplicáveis:

- plano em `docs/planos/`;
- estado esperado em `docs/arquitetura/`;
- migrations versionadas;
- testes de regressão;
- documentação da decisão.

## Definição de pronto

Uma implantação só é considerada pronta quando:

- atende ao critério funcional;
- respeita multiempresa/multiunidade;
- autorização é imposta no backend;
- auditoria aplicável está coberta;
- estado acumulado das migrations é coerente;
- testes antigos foram revisados contra o comportamento novo;
- não existem bloqueadores dos agentes 07, 08 ou 09;
- os testes automatizados aplicáveis passaram;
- documentação está atualizada.