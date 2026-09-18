# AGENTS.md — BPF Manager

Este arquivo define como agentes de IA devem atuar neste repositório.

## Referência obrigatória

Antes de propor, editar ou revisar qualquer implementação relevante, consulte:

- `docs/REFERENCIA_PROJETO.md`
- o documento do agente especializado aplicável em `docs/agentes/`

`docs/REFERENCIA_PROJETO.md` é a fonte principal de verdade sobre objetivo, escopo, arquitetura, segurança, módulos e princípios do BPF Manager.

## Regra central

Nenhuma implementação deve contrariar silenciosamente a referência do projeto. Se uma demanda exigir mudança de direção, a divergência deve ser explicitada e a documentação deve ser atualizada no mesmo ciclo da mudança.

## Modelo de trabalho

Os agentes especializados atuam de forma consultiva. Eles analisam sua área, levantam riscos e sugerem soluções. O Orquestrador/Tech Lead integra essas recomendações, resolve conflitos entre elas e é responsável por definir e implementar a estrutura final coerente.

Antes de solicitar um checkpoint local ao usuário, o Agente 07 — Validação de Fontes / Revisão Integrada deve revisar o conjunto já implementado, especialmente migrations encadeadas, grants/RLS, contratos frontend-backend e testes potencialmente obsoletos.

## Fluxo recomendado

1. Entender a demanda.
2. Identificar os agentes especialistas envolvidos.
3. Validar aderência ao objetivo do BPF Manager.
4. Definir critérios de aceite.
5. Coletar recomendações de produto, dados, segurança, frontend, QA e governança aplicáveis.
6. O Orquestrador consolida as recomendações e implementa a menor mudança coerente possível.
7. Executar revisão integrada de fontes com o Agente 07.
8. Corrigir bloqueadores encontrados antes do checkpoint local.
9. Executar build/testes aplicáveis.
10. Revisar a alteração sob a ótica de segurança e rastreabilidade.
11. Atualizar documentação quando a decisão alterar comportamento, arquitetura ou escopo.

## Agentes especializados

- `docs/agentes/00-ORQUESTRADOR.md`
- `docs/agentes/01-BPF-PRODUTO.md`
- `docs/agentes/02-DADOS-SUPABASE.md`
- `docs/agentes/03-SEGURANCA-PERMISSOES.md`
- `docs/agentes/04-FRONTEND-UX.md`
- `docs/agentes/05-QA.md`
- `docs/agentes/06-AUDITORIA-GOVERNANCA.md`
- `docs/agentes/07-VALIDACAO-FONTES.md`

## Regras globais

- Preservar suporte multiempresa e multiunidade.
- Não conceder privilégios automaticamente por conveniência.
- Não depender apenas da interface para segurança.
- Aplicar RLS em tabelas expostas.
- Não expor `service_role` ou secrets no frontend.
- Não usar `user_metadata` editável como fonte de autorização.
- Preservar histórico de registros relevantes.
- Preferir inativação, exclusão lógica ou versionamento quando houver valor de auditoria.
- Reutilizar regras de autorização em vez de duplicá-las.
- Manter o fluxo `Execução → Monitoramento → Verificação → Ação Corretiva → Registro` quando aplicável.
- Não transformar o produto em simples repositório de formulários.
- Manter a identidade visual aprovada, salvo necessidade funcional clara.

## Uso com Codex no VS Code

Ao solicitar trabalho ao Codex neste repositório, informe o objetivo da tarefa e peça explicitamente para respeitar `AGENTS.md`. Para tarefas maiores, indique também quais agentes especializados devem orientar a solução.
