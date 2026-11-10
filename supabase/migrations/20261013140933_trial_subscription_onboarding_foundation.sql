-- Marco 1.5 / Trial, assinatura e onboarding: fundacao de dominio.
set lock_timeout = '5s';
set statement_timeout = '60s';

create table public.empresa_assinaturas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null unique references public.empresas(id) on update no action on delete no action,
  plano_id uuid null references public.planos(id) on update no action on delete no action,
  status text not null check (status in ('trialing','active','past_due','paused','canceled','expired')),
  trial_inicio timestamptz null,
  trial_fim timestamptz null,
  periodo_inicio timestamptz null,
  periodo_fim timestamptz null,
  provedor text null,
  provedor_cliente_id text null,
  provedor_assinatura_id text null,
  metadata jsonb not null default '{}'::jsonb,
  converted_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint empresa_assinaturas_trial_periodo_check check (
    status <> 'trialing'
    or (trial_inicio is not null and trial_fim is not null and trial_fim > trial_inicio)
  )
);

create index idx_empresa_assinaturas_status on public.empresa_assinaturas(status);
create index idx_empresa_assinaturas_trial_fim on public.empresa_assinaturas(trial_fim) where status='trialing';
create unique index idx_empresa_assinaturas_provedor_ref
  on public.empresa_assinaturas(provedor, provedor_assinatura_id)
  where provedor is not null and provedor_assinatura_id is not null;

create table public.empresa_onboarding (
  empresa_id uuid primary key references public.empresas(id) on update no action on delete cascade,
  status text not null default 'nao_iniciado' check (status in ('nao_iniciado','em_andamento','concluido')),
  etapa_atual text null,
  dados jsonb not null default '{}'::jsonb,
  started_at timestamptz null,
  completed_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint empresa_onboarding_conclusao_check check (
    (status='concluido' and completed_at is not null)
    or (status<>'concluido' and completed_at is null)
  )
);

create table public.saas_provisionamentos (
  id uuid primary key default gen_random_uuid(),
  chave_idempotencia text not null unique,
  tipo text not null check (tipo in ('trial','assinatura','conversao')),
  usuario_id uuid not null references public.usuarios(id) on update no action on delete no action,
  empresa_id uuid null references public.empresas(id) on update no action on delete no action,
  status text not null check (status in ('processando','concluido','falhou')),
  contexto jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  completed_at timestamptz null,
  constraint saas_provisionamentos_chave_check check (length(btrim(chave_idempotencia)) >= 12)
);

create index idx_saas_provisionamentos_usuario on public.saas_provisionamentos(usuario_id, created_at desc);

alter table public.empresa_assinaturas enable row level security;
alter table public.empresa_onboarding enable row level security;
alter table public.saas_provisionamentos enable row level security;

revoke all on table public.empresa_assinaturas from public, anon, authenticated, service_role;
revoke all on table public.empresa_onboarding from public, anon, authenticated, service_role;
revoke all on table public.saas_provisionamentos from public, anon, authenticated, service_role;

comment on table public.empresa_assinaturas is
  'Estado comercial do workspace desacoplado do provedor de pagamento; trial e assinatura pertencem a empresa.';
comment on table public.empresa_onboarding is
  'Progresso do onboarding empresarial, separado da identidade do usuario.';
comment on table public.saas_provisionamentos is
  'Registro idempotente dos provisionamentos SaaS executados pelo backend.';

reset lock_timeout;
reset statement_timeout;
