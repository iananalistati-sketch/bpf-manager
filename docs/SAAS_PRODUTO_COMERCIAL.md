# BPF Manager — Modelo SaaS, Trial e Comercial

## Objetivo

Definir a direção comercial e de produto do BPF Manager como SaaS, sem acoplar regras comerciais transitórias à arquitetura técnica.

Este documento complementa `docs/REFERENCIA_PROJETO.md` e deve ser consultado antes de alterações relacionadas a cadastro público, trial, demonstração, planos, cobrança, limites, assinatura, provisionamento e onboarding.

## Princípio de experiência

O diferencial comercial do BPF Manager será permitir que um potencial cliente **experimente a plataforma antes de contratar**, com um ambiente funcional e representativo das rotinas de BPF.

A jornada desejada é:

**Cadastro → Trial demonstrativo → Exploração da plataforma → Configuração própria opcional → Escolha de plano → Pagamento confirmado → Conversão do workspace → Onboarding → Operação real**

A experiência não deve exigir contato comercial prévio para o usuário compreender o produto.

## Trial

### Direção inicial

- duração inicial prevista: 14 dias;
- sem necessidade de cartão para iniciar;
- ambiente com dados demonstrativos coerentes com BPF;
- possibilidade de o usuário testar operações controladas;
- trial isolado por workspace/tenant, evitando interferência entre prospects;
- dados criados pelo prospect podem ser preservados se ele contratar;
- ao expirar sem assinatura, o workspace deve preferencialmente entrar em modo restrito/somente leitura, em vez de apagar dados imediatamente;
- limpeza definitiva de workspaces expirados deve respeitar política de retenção a ser definida.

### Dados demonstrativos

O trial deve nascer de um template controlado, por exemplo com:

- empresa/fábrica demonstrativa;
- unidade e setores;
- documentos e POPs;
- fornecedores;
- recebimentos;
- agenda BPF;
- treinamentos;
- equipamentos/calibrações;
- não conformidade;
- produção e lote;
- rastreabilidade;
- indicadores e auditoria.

O usuário deve poder distinguir claramente dados demonstrativos de dados próprios.

### Transição para uso real

O produto deve suportar um fluxo do tipo **“Começar com minha empresa”**, no qual o workspace trial deixa de operar como demonstração e inicia onboarding com os dados reais do cliente.

A conversão para cliente pagante deve, quando tecnicamente seguro, preservar os dados próprios já criados durante o trial.

## Planos

Os nomes e limites comerciais devem ser configuráveis e não hardcoded na aplicação.

Faixas iniciais para modelagem:

| Plano | Usuários ativos | Unidades | Direção funcional |
| --- | ---: | ---: | --- |
| Basic | até 10 | 1 | núcleo BPF, documentos, agenda e operação essencial |
| Professional | até 30 | até 3 | recursos operacionais e analíticos ampliados |
| Business | até 75 | até 10 | multiunidade, consolidação e recursos avançados |
| Enterprise | customizado | customizado | limites, integrações, SLA e requisitos negociados |

Essas faixas são referência inicial de produto e podem mudar sem migration estrutural.

## Usuários ativos x sessões simultâneas

A métrica comercial principal deve ser **quantidade de usuários ativos cadastrados**, por ser mais simples de compreender, operar e auditar.

Sessões/dispositivos simultâneos podem existir como controle de segurança e prevenção de compartilhamento indevido de credenciais, mas não devem ser a unidade comercial principal nesta primeira versão.

Exemplo de regra técnica futura:

- limite configurável de sessões/dispositivos por identidade;
- expiração e revogação de sessões;
- visualização das sessões ativas;
- encerramento remoto de sessão.

## Perfil não é plano

O sistema deve manter separação entre:

- **RBAC/perfil**: o que uma pessoa pode fazer dentro de uma empresa;
- **plano/entitlement**: o que a empresa contratou e quais limites possui.

Uma ação pode exigir simultaneamente:

1. recurso contratado/habilitado para a empresa;
2. permissão funcional do usuário naquele vínculo empresarial.

Nunca usar nome de plano como substituto de autorização de usuário.

## Entitlements e limites

Planos devem ser descritos por recursos/limites configuráveis, por exemplo:

- `usuarios_ativos.max`;
- `unidades.max`;
- `armazenamento_mb.max`;
- `producao.enabled`;
- `rastreabilidade.enabled`;
- `auditoria_avancada.enabled`;
- `api.enabled`;
- `integracoes.enabled`.

O backend deve ser a autoridade final para validação de limites.

## Assinatura

A assinatura pertence à empresa/workspace, não ao usuário individual.

Estados mínimos previstos:

- `trialing`;
- `active`;
- `past_due`;
- `paused`;
- `canceled`;
- `expired`.

A estrutura deve aceitar integração futura com provedor de pagamento sem acoplar o domínio a um fornecedor específico.

## Pagamento e provisionamento

A confirmação de pagamento deve ocorrer no backend por evento confiável do provedor, tipicamente webhook.

O frontend nunca deve transformar um usuário em administrador apenas porque uma tela de checkout retornou sucesso.

O provisionamento pós-pagamento deve ser idempotente e criar/ativar de forma controlada:

- assinatura;
- empresa/workspace, quando aplicável;
- vínculo do owner com a empresa;
- perfil administrativo inicial;
- limites/entitlements;
- configurações iniciais;
- evento de auditoria.

## Identidade e vínculo empresarial

A identidade da pessoa deve ser separada de sua participação em uma empresa.

Direção arquitetural:

```text
auth.users
   ↓
usuarios  (identidade global)
   ↓
usuario_empresas  (membership/escopo)
   ↓
usuario_empresa_perfis
```

Uma identidade poderá, no futuro, participar de mais de uma empresa com papéis diferentes.

Exemplos:

- administrador da Empresa A;
- auditor da Empresa B;
- consultor de uma Empresa C;
- participante de um workspace trial.

## Tenant ativo

Quando uma pessoa possuir mais de um vínculo empresarial, a aplicação deve trabalhar com um **tenant ativo explicitamente selecionado**.

O tenant ativo não pode ser confiado somente ao frontend. Toda leitura/escrita crítica deve validar que o vínculo é ativo e autorizado.

## Onboarding

Após contratação/conversão, o onboarding inicial deve conduzir o cliente por dados mínimos, como:

1. empresa;
2. unidade principal;
3. responsável técnico;
4. tipo de operação;
5. estrutura/setores;
6. usuários iniciais;
7. configurações BPF.

No futuro, essas respostas poderão gerar agenda, checklists e parametrizações iniciais automaticamente.

## Mobile/app

A evolução para aplicativo mobile reforça a necessidade de manter regras críticas em serviços, RPCs, Edge Functions e banco, e não apenas em componentes React.

Web e app devem reutilizar os mesmos contratos de backend.

## Decisões que permanecem abertas

Antes de integração real de cobrança, ainda devem ser definidos:

- provedor de pagamento;
- preços e periodicidades;
- política de grace period;
- retenção após trial/cancelamento;
- impostos e faturamento;
- política de upgrade/downgrade;
- prorrata;
- limites de armazenamento;
- regras de sessões/dispositivos;
- disponibilidade exata de módulos por plano.

Essas decisões não devem bloquear a construção da fundação SaaS, desde que o modelo permaneça configurável.

---

**Status:** Direção aprovada para o Marco 1.5  
**Atualização:** 18/09/2026
