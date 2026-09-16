# BPF Manager — Referência do Projeto

> Este documento é a referência principal para decisões de produto, arquitetura e evolução do BPF Manager. Antes de implementar novos módulos, fluxos, permissões, estruturas de dados ou integrações, este documento deve ser consultado para garantir aderência ao objetivo original da aplicação.

## 1. Objetivo geral

O **BPF Manager** é uma plataforma web para gestão de **Boas Práticas de Fabricação (BPF)**, inicialmente voltada para indústrias de alimentação animal.

Seu objetivo é centralizar e digitalizar os controles que hoje costumam existir em planilhas, formulários e documentos separados, oferecendo rastreabilidade, controle de execução, monitoramento, verificação, ações corretivas, evidências e histórico de auditoria.

A plataforma deve permitir que uma organização administre suas rotinas de BPF de forma estruturada, segura, rastreável e auditável, mantendo histórico de alterações e suporte à operação de múltiplas empresas, unidades, setores e perfis de usuário.

O princípio operacional central da aplicação é:

**Execução → Monitoramento → Verificação → Ação Corretiva → Registro**

Esse fluxo deve orientar o desenho funcional dos módulos sempre que aplicável.

## 2. Visão do produto

O BPF Manager deve funcionar como uma plataforma de gestão da qualidade e conformidade operacional, e não apenas como um repositório de formulários.

A aplicação deverá:

- transformar rotinas de BPF em processos digitais controlados;
- organizar documentos, POPs, registros, evidências e responsáveis;
- gerar agenda automática de atividades periódicas;
- registrar não conformidades e acompanhar suas ações corretivas;
- permitir rastreabilidade de matérias-primas, produção, lotes, produtos acabados e expedições;
- fornecer indicadores e dashboards gerenciais;
- permitir auditorias e geração de relatórios;
- manter trilha de auditoria das ações relevantes;
- aplicar controle de acesso por empresa, unidade, perfil e permissão;
- ser preparada para evolução futura com automações e recursos de IA.

## 3. Público e contexto inicial

O foco inicial é a indústria de alimentação animal, considerando como base os controles encontrados nos materiais de BPF analisados no início do projeto e a legislação aplicável ao segmento.

A arquitetura, entretanto, deve evitar dependências desnecessárias de um único cliente ou formulário específico. Regras regulatórias e parametrizações devem ser configuráveis e versionáveis sempre que possível.

## 4. Estrutura organizacional

Desde o início, o sistema deve suportar estrutura multiempresa e multiunidade:

**Empresa → Unidade/Fábrica → Setores → Linhas → Equipamentos → Usuários**

Todo dado operacional relevante deve possuir vínculo organizacional suficiente para garantir isolamento entre empresas e unidades.

## 5. Perfis e autorização

A autorização deve ser granular. Os perfis iniciais previstos são:

- Administrador
- Responsável Técnico
- Qualidade
- Supervisor
- Operador
- Auditor
- Consulta

O sistema deve trabalhar com permissões específicas, por exemplo:

- visualizar;
- criar;
- editar;
- excluir quando permitido;
- executar;
- monitorar;
- verificar;
- aprovar;
- exportar;
- gerenciar usuários;
- gerenciar perfis.

O Administrador deverá futuramente conseguir configurar o que cada perfil pode visualizar e executar.

A interface nunca deve ser considerada a única barreira de segurança. Restrições de acesso também devem existir nas rotas, na camada de dados e nas políticas de segurança do Supabase.

## 6. Módulos previstos

### 6.1 Dashboard

Visão consolidada de:

- conformidade BPF;
- atividades do dia;
- atividades vencidas;
- não conformidades abertas;
- calibrações próximas;
- treinamentos pendentes;
- fornecedores;
- alertas;
- indicadores e gráficos.

### 6.2 Agenda de BPF

Agenda automática de atividades baseada em frequência, prazo, responsável, unidade e tipo de controle.

### 6.3 Gestão documental

Controle de:

- Manual de BPF;
- POPs;
- documentos internos;
- revisões;
- autor;
- revisor;
- aprovador;
- vigência;
- versões obsoletas.

Fluxo documental previsto:

**Rascunho → Em revisão → Aguardando aprovação → Aprovado → Vigente → Obsoleto**

Documentos controlados não devem ser apagados quando houver necessidade de preservar histórico.

### 6.4 Fornecedores

Cadastro, qualificação, avaliação, documentos, validade, situação e histórico de fornecedores.

### 6.5 Recebimentos

Registro de inspeção de matérias-primas, ingredientes, insumos e embalagens. Não conformidades detectadas no recebimento devem poder gerar automaticamente uma NC.

### 6.6 Higienização

Planos e registros de limpeza e higienização de instalações, equipamentos e utensílios, com execução, monitoramento e verificação.

### 6.7 Treinamentos

Programação, registro, participantes, avaliação, evidências, validade e acompanhamento das capacitações.

### 6.8 Água

Controle de potabilidade, limpeza de reservatórios, coletas, análises, resultados e evidências.

### 6.9 Equipamentos

Cadastro de equipamentos e instrumentos, manutenção preventiva/corretiva, calibração, vencimentos e evidências.

### 6.10 Controle de pragas

Registros de ocorrência, ações preventivas, aplicações, monitoramento, evidências e acompanhamento.

### 6.11 Resíduos

Controle de geração, segregação, coleta, destinação e evidências de resíduos e efluentes.

### 6.12 Não conformidades e CAPA

Fluxo esperado:

**Abertura → Classificação → Causa raiz → Plano de ação → Responsável → Prazo → Execução → Verificação de eficácia → Encerramento**

O sistema poderá futuramente incluir metodologias como 5 Porquês e Ishikawa.

### 6.13 Produção

Ordens de produção, produto, lote, datas, matérias-primas, controles de processo, monitoramento e verificação.

### 6.14 Rastreabilidade

Rastreabilidade bidirecional:

**matéria-prima → produção → lote de produto acabado → carregamento → nota fiscal → cliente**

E também no sentido inverso.

### 6.15 Recall

Registro e execução de simulações de recolhimento, incluindo o exercício periódico/anual previsto nos procedimentos.

### 6.16 Higiene e saúde pessoal

Checklists e registros relacionados às condições de higiene, saúde e conduta das pessoas envolvidas na operação.

### 6.17 Auditorias

Planejamento, checklists, evidências, achados, não conformidades, responsáveis, planos de ação e resultados.

### 6.18 Relatórios

Relatórios analíticos e gerenciais, com geração futura em PDF e Excel.

### 6.19 Configurações e administração

Gestão de:

- empresas;
- unidades;
- setores;
- usuários;
- perfis;
- permissões;
- parâmetros da plataforma;
- cadastros auxiliares.

Estado da primeira versão de Usuários e Perfis (15/09/2026): `/configuracoes` oferece Visão Geral, Usuários e Perfis e Permissões, com acesso granular e consultas reais. A RLS atual limita usuários/vínculos ao próprio cadastro; a interface informa essa limitação. Os perfis e suas permissões são consultáveis, mas nenhuma gravação administrativa foi habilitada. A liberação de leitura ampliada, aprovação, status, vínculos e edição de permissões depende de revisão do backend e auditoria transacional, conforme [proposta e evidências da etapa](CONFIGURACOES_USUARIOS_PERFIS.md).

## 7. Trilhas de auditoria

A trilha de auditoria deve existir desde a fundação do sistema.

Para operações críticas, deve ser possível identificar, conforme aplicável:

- usuário;
- data e hora;
- registro alterado;
- operação realizada;
- valor anterior;
- valor novo;
- empresa/unidade;
- eventualmente IP, dispositivo ou origem da alteração.

Registros finalizados, aprovados ou que possuam relevância de auditoria não devem ser simplesmente apagados.

Sempre que possível, utilizar inativação, exclusão lógica, versionamento ou histórico.

## 8. Segurança

A segurança é requisito arquitetural e não funcionalidade opcional.

Diretrizes:

- autenticação pelo Supabase Auth;
- isolamento multiempresa por RLS;
- nenhuma chave `service_role` ou secret no frontend;
- uso de publishable key no cliente;
- RLS em todas as tabelas expostas;
- autorização baseada em dados controlados pelo sistema;
- não utilizar `user_metadata` editável pelo usuário para decisões de autorização;
- rotas da aplicação devem validar permissões;
- a camada visual não substitui controle no banco;
- novos usuários devem nascer sem privilégios e depender de aprovação/vínculo quando aplicável.

## 9. Arquitetura técnica atual

### Frontend

- React
- TypeScript
- Vite
- React Router
- Lucide React
- CSS organizado da aplicação

### Backend e dados

- Supabase PostgreSQL
- Supabase Auth
- Supabase Storage
- Supabase Row Level Security
- Supabase Edge Functions quando necessário

### Hospedagem prevista

- Cloudflare Pages para o frontend

### Versionamento e desenvolvimento

- GitHub
- VS Code
- desenvolvimento local
- branches para funcionalidades relevantes
- commits estáveis entre etapas importantes

## 10. Estrutura de dados base

A fundação atual contempla, entre outras estruturas:

- empresas;
- unidades;
- setores;
- usuários;
- perfis;
- permissões;
- vínculo usuário/perfil;
- vínculo perfil/permissão.

A aplicação deve evoluir mantendo coerência relacional e evitando estruturas improvisadas que dificultem auditoria, RLS ou rastreabilidade.

## 11. Regras para novas implementações

Antes de desenvolver uma nova funcionalidade, validar:

1. Qual problema operacional ou regulatório ela resolve?
2. A qual empresa/unidade o dado pertence?
3. Quais perfis podem visualizar e executar a ação?
4. Qual permissão deve controlá-la?
5. Existe necessidade de execução, monitoramento e verificação?
6. Existe possibilidade de gerar não conformidade?
7. É necessário histórico ou trilha de auditoria?
8. O registro pode ser apagado ou deve ser apenas inativado/versionado?
9. Existe frequência ou prazo que deva alimentar a agenda?
10. O dado será utilizado em rastreabilidade, auditoria, dashboard ou relatório?
11. A solução está protegida também no banco/RLS e não apenas na interface?
12. A implementação preserva a capacidade multiempresa?

## 12. Princípios de desenvolvimento

- Priorizar segurança e integridade dos dados.
- Não conceder privilégios automaticamente por conveniência.
- Evitar regras críticas hardcoded quando puderem ser parametrizadas.
- Preservar histórico de dados relevantes.
- Criar componentes e fluxos reutilizáveis.
- Evitar duplicação de regras de autorização.
- Validar cada etapa antes de seguir para a próxima.
- Não alterar a identidade visual aprovada sem necessidade funcional.
- Manter a interface simples mesmo quando as regras de negócio forem complexas.
- Desenvolver primeiro a fundação correta; automações e IA entram posteriormente sobre processos estáveis.

## 13. IA e automações futuras

A arquitetura deve permitir uso futuro de IA para auxiliar, por exemplo:

- análise de causas de não conformidades;
- identificação de padrões recorrentes;
- priorização de riscos;
- sugestão de ações corretivas;
- detecção de atrasos;
- apoio à análise de auditorias;
- resumo de indicadores e evidências.

IA deverá atuar como apoio à decisão, e não substituir controles, aprovações e responsabilidades formais do processo de qualidade.

## 14. Referências funcionais de origem

A definição inicial do produto foi construída a partir da análise do Manual de BPF, POPs e formulários fornecidos no início do projeto, incluindo controles relacionados a:

- fornecedores;
- recebimento;
- higienização;
- treinamento;
- água;
- equipamentos e calibração;
- pragas;
- resíduos;
- não conformidades;
- produção;
- rastreabilidade;
- recall;
- higiene e saúde pessoal.

Esses materiais servem como referência de domínio, mas o BPF Manager não deve ser apenas uma cópia digital dos formulários. A plataforma deve transformar esses controles em processos integrados e rastreáveis.

## 15. Regra de governança deste documento

Este arquivo deve ser tratado como **fonte de verdade do escopo e da direção do projeto**.

Sempre que uma decisão relevante alterar objetivo, arquitetura, segurança, estrutura organizacional, módulos ou princípios do sistema, este documento deve ser atualizado no mesmo ciclo da alteração.

Se uma implementação entrar em conflito com esta referência, a divergência deve ser discutida antes de ser incorporada definitivamente ao projeto.

---

**Projeto:** BPF Manager  
**Documento:** Referência geral do projeto  
**Status:** Ativo  
**Última atualização:** 15/09/2026
