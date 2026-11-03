-- Marco 1.5 / Fase 1: fundacao aditiva de membership por empresa.
-- Mantem usuarios.empresa_id, usuarios.unidade_id e usuario_perfis intactos para compatibilidade.
set lock_timeout = '5s';
set statement_timeout = '60s';

-- Bloqueia migracao silenciosa de vinculos legados semanticamente incompatíveis.
do $block$
begin
  if exists (
    select 1
    from public.usuario_perfis up
    join public.usuarios u on u.id = up.usuario_id
    join public.perfis p on p.id = up.perfil_id
    where u.empresa_id is not null
      and not ((p.empresa_id is null and p.is_system) or p.empresa_id = u.empresa_id)
  ) then
    raise exception using
      errcode = '23514',
      message = 'Existing usuario_perfis contain profiles incompatible with usuarios.empresa_id';
  end if;
end
$block$;

create table public.usuario_empresas (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references public.usuarios(id) on update no action on delete cascade,
  empresa_id uuid not null references public.empresas(id) on update no action on delete no action,
  unidade_id uuid null references public.unidades(id) on update no action on delete set null,
  status text not null default 'ativo'
    check (status in ('pendente', 'ativo', 'inativo', 'bloqueado')),
  is_owner boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid null references public.usuarios(id) on update no action on delete set null,
  constraint usuario_empresas_usuario_empresa_key unique (usuario_id, empresa_id)
);

create index idx_usuario_empresas_empresa_status
  on public.usuario_empresas (empresa_id, status);
create index idx_usuario_empresas_usuario_status
  on public.usuario_empresas (usuario_id, status);
create index idx_usuario_empresas_unidade
  on public.usuario_empresas (unidade_id);

create table public.usuario_empresa_perfis (
  usuario_empresa_id uuid not null references public.usuario_empresas(id) on update no action on delete cascade,
  perfil_id uuid not null references public.perfis(id) on update no action on delete no action,
  created_at timestamptz not null default now(),
  created_by uuid null references public.usuarios(id) on update no action on delete set null,
  primary key (usuario_empresa_id, perfil_id)
);

create index idx_usuario_empresa_perfis_perfil
  on public.usuario_empresa_perfis (perfil_id);

create function private.validar_usuario_empresa_unidade()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if new.unidade_id is not null and not exists (
    select 1
    from public.unidades un
    where un.id = new.unidade_id
      and un.empresa_id = new.empresa_id
  ) then
    raise exception using
      errcode = '23514',
      message = 'Unidade do membership deve pertencer a mesma empresa';
  end if;
  return new;
end
$function$;

create trigger trg_usuario_empresas_unidade
before insert or update of empresa_id, unidade_id on public.usuario_empresas
for each row execute function private.validar_usuario_empresa_unidade();

create function private.validar_usuario_empresa_perfil()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_empresa uuid;
begin
  select ue.empresa_id
    into v_empresa
  from public.usuario_empresas ue
  where ue.id = new.usuario_empresa_id;

  if v_empresa is null then
    raise exception using errcode = '23503', message = 'Membership nao encontrado';
  end if;

  if not exists (
    select 1
    from public.perfis p
    where p.id = new.perfil_id
      and ((p.empresa_id is null and p.is_system) or p.empresa_id = v_empresa)
  ) then
    raise exception using
      errcode = '23514',
      message = 'Perfil deve ser de sistema ou pertencer a empresa do membership';
  end if;

  return new;
end
$function$;

create trigger trg_usuario_empresa_perfis_escopo
before insert or update of usuario_empresa_id, perfil_id on public.usuario_empresa_perfis
for each row execute function private.validar_usuario_empresa_perfil();

-- Backfill aditivo do modelo legado. is_owner permanece falso: owner e conceito SaaS
-- distinto de Administrador e sera atribuido explicitamente no provisionamento futuro.
insert into public.usuario_empresas (
  usuario_id, empresa_id, unidade_id, status, is_owner, created_by
)
select
  u.id,
  u.empresa_id,
  u.unidade_id,
  u.status,
  false,
  null
from public.usuarios u
where u.empresa_id is not null
on conflict (usuario_id, empresa_id) do nothing;

insert into public.usuario_empresa_perfis (usuario_empresa_id, perfil_id, created_by)
select
  ue.id,
  up.perfil_id,
  up.created_by
from public.usuario_perfis up
join public.usuarios u on u.id = up.usuario_id and u.empresa_id is not null
join public.usuario_empresas ue on ue.usuario_id = u.id and ue.empresa_id = u.empresa_id
join public.perfis p on p.id = up.perfil_id
where (p.empresa_id is null and p.is_system) or p.empresa_id = ue.empresa_id
on conflict (usuario_empresa_id, perfil_id) do nothing;

alter table public.usuario_empresas enable row level security;
alter table public.usuario_empresa_perfis enable row level security;

revoke all on table public.usuario_empresas from public, anon, authenticated;
revoke all on table public.usuario_empresa_perfis from public, anon, authenticated;
grant select on table public.usuario_empresas to authenticated;
grant select on table public.usuario_empresa_perfis to authenticated;

create policy usuario_empresas_select_proprio
  on public.usuario_empresas
  for select to authenticated
  using (usuario_id = (select auth.uid()));

create policy usuario_empresa_perfis_select_proprio
  on public.usuario_empresa_perfis
  for select to authenticated
  using (exists (
    select 1
    from public.usuario_empresas ue
    where ue.id = usuario_empresa_perfis.usuario_empresa_id
      and ue.usuario_id = (select auth.uid())
  ));

comment on table public.usuario_empresas is
  'Membership usuario x empresa. Fase de compatibilidade do Marco 1.5; ainda nao substitui usuarios.empresa_id no runtime.';
comment on table public.usuario_empresa_perfis is
  'Perfis atribuídos no contexto de um membership empresarial; coexistem temporariamente com usuario_perfis.';

reset lock_timeout;
reset statement_timeout;
