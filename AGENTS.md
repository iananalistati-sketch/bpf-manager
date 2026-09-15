# AGENTS.md — BPF Manager

Este arquivo define como agentes de IA devem atuar neste repositório.

## Referência obrigatória

Antes de propor, editar ou revisar qualquer implementação relevante, consulte:

- `docs/REFERENCIA_PROJETO.md`
- o documento do agente especializado aplicável em `docs/agentes/`

`docs/REFERENCIA_PROJETO.md` é a fonte principal de verdade sobre objetivo, escopo, arquitetura, segurança, módulos e princípios do BPF Manager.

## Regra central

Nenhuma implementação deve contrariar silenciosamente a referência do projeto. Se uma demanda exigir mudança de direção, a divergência deve ser explicitada e a documentação deve ser atualizada no mesmo ciclo da mudança.

## Fluxo recomendado

1. Entender a demanda.
2. Identificar os agentes especialistas envolvidos.
3. Validar aderência ao objetivo do BPF Manager.
4. Definir critérios de aceite.
5. Revisar impactos em dados, segurança, permissões, auditoria e UX.
6. Implementar a menor mudança coerente possível.
7. Executar build/testes aplicáveis.
8. Revisar a alteração sob a ótica de segurança e rastreabilidade.
9. Atualizar documentação quando a decisão alterar comportamento, arquitetura ou escopo.

## Agentes especializados

- `docs/agentes/00-ORQUESTRADOR.md`
- `docs/agentes/01-BPF-PRODUTO.md`
- `docs/agentes/02-DADOS-SUPABASE.md`
- `docs/agentes/03-SEGURANCA-PERMISSOES.md`
- `docs/agentes/04-FRONTEND-UX.md`
- `docs/agentes/05-QA.md`
- `docs/agentes/06-AUDITORIA-GOVERNANCA.md`

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
