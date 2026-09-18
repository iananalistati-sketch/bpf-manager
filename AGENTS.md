# AGENTS.md — BPF Manager

Este arquivo define como agentes de IA devem atuar neste repositório.

## Referência obrigatória

Antes de propor, editar ou revisar qualquer implementação relevante, consulte:

- `docs/REFERENCIA_PROJETO.md`
- `docs/PROCESSO_ENGENHARIA.md`
- o documento do agente especializado aplicável em `docs/agentes/`

`docs/REFERENCIA_PROJETO.md` é a fonte principal de verdade sobre objetivo, escopo, arquitetura, segurança, módulos e princípios do BPF Manager.

## Regra central

Nenhuma implementação deve contrariar silenciosamente a referência do projeto. Se uma demanda exigir mudança de direção, a divergência deve ser explicitada e a documentação deve ser atualizada no mesmo ciclo da mudança.

## Modelo de trabalho

Os agentes especializados atuam de forma consultiva. Eles analisam sua área, levantam riscos, sugerem soluções e identificam impactos sobre outros agentes. O Orquestrador/Tech Lead integra essas recomendações, resolve conflitos e é o único responsável por definir e consolidar a estrutura final da implementação.

Agentes não trabalham como silos. Todo achado relevante deve declarar quais áreas impacta, e o Orquestrador deve repassar essa conclusão aos agentes afetados antes de consolidar a solução.

## Fluxo obrigatório

1. Entender a demanda e consultar a referência do projeto.
2. O Orquestrador seleciona os especialistas necessários.
3. Cada especialista devolve recomendação, dependências, impactos, riscos e critérios de aceite.
4. O Orquestrador compartilha achados cruzados entre os agentes afetados e resolve conflitos.
5. O Orquestrador consolida e implementa uma única solução coerente.
6. Agente 08 revisa banco/migrations e o estado acumulado.
7. Agente 09 executa revisão adversarial de segurança.
8. Agente 07 executa validação integrada de fontes e contratos.
9. QA executa os testes aplicáveis.
10. Somente sem bloqueadores é permitido solicitar checkpoint local ao usuário.
11. Após checkpoint verde, aplicar mudanças remotas e validar o estado final.

O detalhamento dos gates está em `docs/PROCESSO_ENGENHARIA.md`.

## Agentes especializados

- `docs/agentes/00-ORQUESTRADOR.md`
- `docs/agentes/01-BPF-PRODUTO.md`
- `docs/agentes/02-DADOS-SUPABASE.md`
- `docs/agentes/03-SEGURANCA-PERMISSOES.md`
- `docs/agentes/04-FRONTEND-UX.md`
- `docs/agentes/05-QA.md`
- `docs/agentes/06-AUDITORIA-GOVERNANCA.md`
- `docs/agentes/07-VALIDACAO-FONTES.md`
- `docs/agentes/08-BANCO-MIGRATIONS.md`
- `docs/agentes/09-SEGURANCA-ADVERSARIAL.md`

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
- Migrations já aplicadas remotamente são imutáveis; correções posteriores exigem nova migration.
- Nenhum checkpoint deve ser solicitado enquanto existir bloqueador conhecido nos gates internos.

## Uso com Codex no VS Code

Ao solicitar trabalho ao Codex neste repositório, informe o objetivo da tarefa e peça explicitamente para respeitar `AGENTS.md` e `docs/PROCESSO_ENGENHARIA.md`.