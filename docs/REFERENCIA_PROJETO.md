# BPF Manager — Referência do Projeto

> Este documento é a referência principal para decisões de produto, arquitetura e evolução do BPF Manager. Antes de implementar novos módulos, fluxos, permissões, estruturas de dados ou integrações, este documento deve ser consultado para garantir aderência ao objetivo original da aplicação.

## 1. Objetivo geral

O **BPF Manager** é uma plataforma SaaS para gestão de **Boas Práticas de Fabricação (BPF)**, inicialmente voltada para indústrias de alimentação animal.

Seu objetivo é centralizar e digitalizar os controles que hoje costumam existir em planilhas, formulários e documentos separados, oferecendo rastreabilidade, controle de execução, monitoramento, verificação, ações corretivas, evidências e histórico de auditoria.

A plataforma deve permitir que uma organização administre suas rotinas de BPF de forma estruturada, segura, rastreável e auditável, mantendo histórico de alterações e suporte à operação de múltiplas empresas, unidades, setores e perfis de usuário.

Além do uso operacional, o produto deve permitir que um potencial cliente se cadastre, experimente um ambiente demonstrativo funcional, escolha um plano e, após contratação validada pelo backend, converta seu workspace em ambiente operacional real.

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
- aplicar controle de acesso por empresa, unidade, membership, perfil e permissão;
- permitir trial/demonstração antes da contratação;
- suportar planos e limites comerciais sem misturá-los com RBAC;
- ser preparada para web e futuro aplicativo mobile;
- ser preparada para evolução futura com automações e recursos de IA.

## 3. Público, comercialização e contexto inicial

O foco inicial é a indústria de alimentação animal, considerando como base os controles encontrados nos materiais de BPF analisados no início do projeto e a legislação aplicável ao segmento.

A arquitetura deve evitar dependências desnecessárias de um único cliente, formulário ou regra comercial. Regras regulatórias e parametrizações devem ser configuráveis e versionáveis sempre que possível.

### 3.1 Experiência de avaliação

O diferencial comercial aprovado é permitir que o prospect **experimente a plataforma antes de contratar**, por meio de um trial funcional e isolado.

Direção inicial:

- trial de 14 dias, configurável;
- sem cartão obrigatório para iniciar;
- workspace demonstrativo individual;
- dados demo coerentes com BPF;
- possibilidade de testar operações controladas;
- preservação de dados próprios na conversão, quando seguro;
- expiração preferencialmente em modo restrito/somente leitura, não exclusão imediata.

O detalhamento está em `docs/SAAS_PRODUTO_COMERCIAL.md`.

### 3.2 Planos

A arquitetura deve suportar planos configuráveis. Faixas iniciais para modelagem:

- Basic: até 10 usuários ativos e 1 unidade;
- Professional: até 30 usuários ativos e até 3 unidades;
- Business: até 75 usuários ativos e até 10 unidades;
- Enterprise: limites configuráveis.

Esses valores não são contrato comercial definitivo e não podem ser hardcoded em RLS ou regras estruturais.

A métrica comercial principal será quantidade de **usuários ativos**, não sessões simultâneas. Sessões/dispositivos poderão ser controlados separadamente como mecanismo técnico de segurança.

## 4. Estrutura organizacional e tenancy

O sistema deve suportar estrutura multiempresa e multiunidade:

**Empresa → Unidade/Fábrica → Setores → Linhas → Equipamentos**

A identidade da pessoa deve ser separada de sua participação em uma empresa.

Direção arquitetural do Marco 1.5:

**auth.users → usuarios (identidade global) → usuario_empresas (membership) → perfis/permissões no contexto empresarial**

Todo dado operacional relevante deve possuir vínculo organizacional suficiente para garantir isolamento entre empresas e unidades.

Uma mesma identidade poderá futuramente possuir vínculos distintos com múltiplas empresas, por exemplo como administrador, auditor, consultor ou responsável técnico.

Quando houver mais de um vínculo, a aplicação deverá trabalhar com tenant ativo explicitamente selecionado e validado no backend.

## 5. Perfis, autorização e entitlements

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

O Administrador deverá conseguir configurar o que cada perfil pode visualizar e executar, respeitando teto de delegação e regras de segurança.

A interface nunca deve ser considerada a única barreira de segurança. Restrições de acesso também devem existir nas rotas, na camada de dados e nas políticas de segurança do Supabase.

### 5.1 Perfil não é plano

- **Perfil/permissão** responde o que a pessoa pode fazer naquele vínculo empresarial.
- **Plano/entitlement** responde o que a empresa contratou e quais limites possui.

Uma ação pode exigir simultaneamente entitlement habilitado e permissão RBAC.

Plano comercial nunca substitui autorização de usuário.

## 6. Módulos previstos

### 6.1 Dashboard

Visão consolidada de conformidade BPF, atividades, vencimentos, não conformidades, calibrações, treinamentos, fornecedores, alertas e indicadores.

### 6.2 Agenda de BPF

Agenda automática de atividades baseada em frequência, prazo, responsável, unidade e tipo de controle.

### 6.3 Gestão documental

Controle de Manual de BPF, POPs, documentos internos, revisões, autor, revisor, aprovador, vigência e versões obsoletas.

Fluxo previsto:

**Rascunho → Em revisão → Aguardando aprovação → Aprovado → Vigente → Obsoleto**

Documentos controlados não devem ser apagados quando houver necessidade de preservar histórico.

### 6.4 Fornecedores

Cadastro, qualificação, avaliação, documentos, validade, situação e histórico.

### 6.5 Recebimentos

Inspeção de matérias-primas, ingredientes, insumos e embalagens. Não conformidades detectadas devem poder gerar automaticamente uma NC.

### 6.6 Higienização

Planos e registros de limpeza e higienização, com execução, monitoramento e verificação.

### 6.7 Treinamentos

Programação, registro, participantes, avaliação, evidências, validade e acompanhamento.

### 6.8 Água

Controle de potabilidade, limpeza de reservatórios, coletas, análises, resultados e evidências.

### 6.9 Equipamentos

Cadastro, manutenção, calibração, vencimentos e evidências.

### 6.10 Controle de pragas

Ocorrências, ações preventivas, aplicações, monitoramento e evidências.

### 6.11 Resíduos

Geração, segregação, coleta, destinação e evidências de resíduos e efluentes.

### 6.12 Não conformidades e CAPA

**Abertura → Classificação → Causa raiz → Plano de ação → Responsável → Prazo → Execução → Verificação de eficácia → Encerramento**

Poderá futuramente incluir metodologias como 5 Porquês e Ishikawa.

### 6.13 Produção

Ordens de produção, produto, lote, datas, matérias-primas, controles de processo, monitoramento e verificação.

### 6.14 Rastreabilidade

Rastreabilidade bidirecional:

**matéria-prima → produção → lote de produto acabado → carregamento → nota fiscal → cliente**

E também no sentido inverso.

### 6.15 Recall

Registro e execução de simulações de recolhimento, incluindo exercício periódico/anual previsto nos procedimentos.

### 6.16 Higiene e saúde pessoal

Checklists e registros relacionados às condições de higiene, saúde e conduta das pessoas envolvidas na operação.

### 6.17 Auditorias

Planejamento, checklists, evidências, achados, não conformidades, responsáveis, planos de ação e resultados.

### 6.18 Relatórios

Relatórios analíticos e gerenciais, com geração futura em PDF e Excel.

### 6.19 Configurações e administração

Gestão de empresas, unidades, setores, usuários, perfis, permissões, parâmetros e cadastros auxiliares.

Estado em 18/09/2026: o Marco 1 administrativo foi concluído e implantado no Supabase remoto. `/configuracoes` possui Usuários, Perfis e Permissões, Estrutura e Auditoria; alterações críticas usam RPCs auditadas; RLS e isolamento por empresa foram validados; proteção contra autoelevação, cross-tenant e remoção do último administrador efetivo está ativa; a Edge Function `admin-invite-user` está publicada com JWT obrigatório para o fluxo de convite. As migrations remotas desse marco são imutáveis.

O próximo trabalho estrutural é o **Marco 1.5 — Fundação SaaS**, antes do Marco 2 operacional.

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

Registros finalizados, aprovados ou relevantes para auditoria não devem ser simplesmente apagados. Sempre que possível, utilizar inativação, exclusão lógica, versionamento ou histórico.

No contexto SaaS, também devem ser auditáveis eventos de trial, conversão, membership, assinatura, plano e provisionamento.

## 8. Segurança

A segurança é requisito arquitetural e não funcionalidade opcional.

Diretrizes:

- autenticação pelo Supabase Auth;
- isolamento multiempresa por RLS;
- membership e tenant ativo validados no backend;
- nenhuma chave `service_role` ou secret no frontend;
- uso de publishable key no cliente;
- RLS em todas as tabelas expostas;
- autorização baseada em dados controlados pelo sistema;
- não utilizar `user_metadata` editável para decisões de autorização, plano ou tenant;
- rotas da aplicação devem validar permissões;
- a camada visual não substitui controle no banco;
- novos usuários devem nascer sem privilégios e depender de vínculo/provisionamento autorizado;
- pagamento confirmado na interface nunca concede privilégio;
- webhook/provisionamento futuro deve ser server-side e idempotente;
- trial não pode acessar dados de tenants reais.

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

### Evolução para app

A futura aplicação mobile deve reutilizar os mesmos contratos de backend. Regras críticas de negócio, autorização, entitlement, trial e provisionamento não devem ficar exclusivas no React web.

### Versionamento e desenvolvimento

- GitHub
- VS Code
- desenvolvimento local
- branches para funcionalidades relevantes
- commits estáveis entre etapas importantes

## 10. Estrutura de dados base e evolução SaaS

A fundação atual contempla:

- empresas;
- unidades;
- setores;
- usuários;
- perfis;
- permissões;
- vínculo usuário/perfil;
- vínculo perfil/permissão;
- auditoria.

O Marco 1.5 deverá evoluir essa base para incluir, conceitualmente:

- identidade global;
- `usuario_empresas`/membership;
- vínculo perfil por membership;
- tenant ativo;
- trial/workspace;
- planos;
- entitlements/limites;
- assinaturas;
- onboarding/provisionamento.

As colunas atuais `usuarios.empresa_id`, `usuarios.unidade_id` e o vínculo `usuario_perfis` não devem ser removidos de forma abrupta, pois o Marco 1 remoto depende deles. A migração será incremental por novas migrations e backfill controlado.

Ver `docs/arquitetura/ESTADO_SAAS_ESPERADO.md`.

## 11. Regras para novas implementações

Antes de desenvolver uma nova funcionalidade, validar:

1. Qual problema operacional, regulatório ou comercial ela resolve?
2. A qual empresa/unidade/workspace o dado pertence?
3. A autorização depende de qual membership/tenant ativo?
4. Quais perfis podem visualizar e executar a ação?
5. Qual permissão deve controlá-la?
6. Existe entitlement ou limite de plano aplicável?
7. Existe necessidade de execução, monitoramento e verificação?
8. Existe possibilidade de gerar não conformidade?
9. É necessário histórico ou trilha de auditoria?
10. O registro pode ser apagado ou deve ser apenas inativado/versionado?
11. Existe frequência ou prazo que deva alimentar a agenda?
12. O dado será utilizado em rastreabilidade, auditoria, dashboard ou relatório?
13. A solução está protegida também no backend/RLS e não apenas na interface?
14. A implementação preserva multiempresa, multiunidade e futuro multi-membership?
15. O contrato pode ser reutilizado por web e futuro mobile?

## 12. Princípios de desenvolvimento

- Priorizar segurança e integridade dos dados.
- Não conceder privilégios automaticamente por conveniência.
- Evitar regras críticas hardcoded quando puderem ser parametrizadas.
- Separar identidade, membership, RBAC, plano e assinatura.
- Preservar histórico de dados relevantes.
- Criar componentes e fluxos reutilizáveis.
- Evitar duplicação de regras de autorização.
- Validar cada etapa antes de seguir para a próxima.
- Não alterar a identidade visual aprovada sem necessidade funcional.
- Manter a interface simples mesmo quando as regras de negócio forem complexas.
- Desenvolver primeiro a fundação correta; automações e IA entram posteriormente sobre processos estáveis.
- Migrations já aplicadas remotamente são imutáveis.

## 13. Roadmap estrutural

- **Marco 1 — Administração segura:** concluído e implantado.
- **Marco 1.5 — Fundação SaaS:** próximo marco; identidade global, membership, tenant ativo, trial, planos, entitlements, assinatura abstrata, provisionamento e onboarding.
- **Marco 2 — Documentos + Agenda BPF.**
- **Marco 3 — Operação básica:** fornecedores, recebimentos, higienização, treinamentos, água, equipamentos, pragas e resíduos.
- **Marco 4 — Qualidade:** NC/CAPA e auditorias.
- **Marco 5 — Produção, rastreabilidade e recall.**
- **Marco 6 — Consolidação:** dashboards, relatórios, otimizações e preparação avançada para automações/IA.

## 14. IA e automações futuras

A arquitetura deve permitir uso futuro de IA para auxiliar análise de causas de não conformidades, identificação de padrões, priorização de riscos, sugestão de ações, detecção de atrasos, apoio a auditorias e resumo de indicadores/evidências.

IA deverá atuar como apoio à decisão, e não substituir controles, aprovações e responsabilidades formais do processo de qualidade.

## 15. Referências funcionais de origem

A definição inicial do produto foi construída a partir da análise do Manual de BPF, POPs e formulários fornecidos no início do projeto, incluindo controles relacionados a fornecedores, recebimento, higienização, treinamento, água, equipamentos, pragas, resíduos, não conformidades, produção, rastreabilidade, recall e higiene/saúde pessoal.

Esses materiais servem como referência de domínio, mas o BPF Manager não deve ser apenas uma cópia digital dos formulários. A plataforma deve transformar esses controles em processos integrados e rastreáveis.

Para decisões comerciais/SaaS, consultar também `docs/SAAS_PRODUTO_COMERCIAL.md`.

## 16. Regra de governança deste documento

Este arquivo deve ser tratado como **fonte de verdade do escopo e da direção do projeto**.

Sempre que uma decisão relevante alterar objetivo, arquitetura, segurança, estrutura organizacional, modelo SaaS, módulos ou princípios do sistema, este documento deve ser atualizado no mesmo ciclo da alteração.

Se uma implementação entrar em conflito com esta referência, a divergência deve ser discutida antes de ser incorporada definitivamente ao projeto.

---

**Projeto:** BPF Manager  
**Documento:** Referência geral do projeto  
**Status:** Ativo  
**Última atualização:** 18/09/2026
