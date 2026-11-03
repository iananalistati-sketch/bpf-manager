# BPF Manager

Plataforma web para gestão de **Boas Práticas de Fabricação (BPF)**, inicialmente voltada para indústrias de alimentação animal.

## Referência obrigatória do projeto

Antes de desenvolver novos módulos, fluxos, permissões, estruturas de dados ou integrações, consulte:

**[`docs/REFERENCIA_PROJETO.md`](docs/REFERENCIA_PROJETO.md)**

Esse documento registra o objetivo geral da aplicação, visão do produto, módulos previstos, arquitetura, princípios de segurança, estrutura organizacional, regras de autorização, trilha de auditoria e critérios que devem orientar novas implementações.

Se uma implementação futura entrar em conflito com essa referência, a divergência deve ser discutida antes de ser incorporada definitivamente ao projeto.

## Stack atual

- React
- TypeScript
- Vite
- React Router
- Supabase PostgreSQL
- Supabase Auth
- Supabase RLS
- GitHub

## Desenvolvimento local

```bash
npm install
npm run dev
```

No Windows PowerShell deste projeto, caso a execução de `npm.ps1` esteja bloqueada, utilize:

```powershell
npm.cmd install
npm.cmd run dev
```

As variáveis locais do Supabase devem ficar em `.env.local`. Use `.env.example` apenas como referência e nunca versione credenciais ou arquivos locais de ambiente.
