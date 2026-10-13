-- Marco 1.5 / Fase 3: catalogo de planos, entitlements tipados e limites no backend.
-- Plano/entitlement permanece separado de RBAC e nenhuma empresa existente recebe plano automaticamente.
set lock_timeout = '5s';
set statement_timeout = '60s';

create table public.planos (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  nome text not null,
  descricao text null,
  ativo boolean not null default true,
  ordem_exibicao integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint planos_codigo_check check (
    codigo = lower(codigo)
    and codigo ~ '^[a-z0-9][a-z0-9._-]*$'
  ),
  constraint planos_nome_check check (length(btrim(nome)) > 0)
);

create table public.plano_entitlements (
  id uuid primary key default gen_random_uuid(),
  plano_id uuid not null references public.planos(id) on update no action on delete cascade,
  chave text not null,
  tipo text not null check (tipo in ('booleano', 'inteiro', 'texto')),
  valor_booleano boolean null,
  valor_inteiro bigint null,
  valor_texto text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint plano_entitlements_plano_chave_key unique (plano_id, chave),
  constraint plano_entitlements_chave_check check (
    chave = lower(chave)
    and chave ~ '^[a-z0-9][a-z0-9._-]*$'
  ),
  constraint plano_entitlements_valor_tipado_check check (
    (tipo = 'booleano' and valor_booleano is not null and valor_inteiro is null and valor_texto is null)
    or (tipo = 'inteiro' and valor_booleano is null and valor_inteiro is not null and valor_inteiro >= 0 and valor_texto is null)
    or (tipo = 'texto' and valor_booleano is null and valor_inteiro is null and valor_texto is not null and length(btrim(valor_texto)) > 0)
  )
);

create index idx_plano_entitlements_plano on public.plano_entitlements (plano_id);

-- Relacao comercial atual da empresa com um plano. Nao representa pagamento nem assinatura.
-- A futura camada de assinaturas/provisionamento sera a responsavel por manter esta atribuicao.
create table public.empresa_planos (
  empresa_id uuid primary key references public.empresas(id) on update no action on delete no action,
  plano_id uuid not null references public.planos(id) on update no action on delete no action,
  origem text not null default 'manual'
    check (origem in ('manual', 'legacy', 'trial', 'assinatura', 'provisionamento')),
  assigned_at timestamptz not null default now(),
  assigned_by uuid null references public.usuarios(id) on update no action on delete set null,
  updated_at timestamptz not null default now()
);

create index idx_empresa_planos_plano on public.empresa_planos (plano_id);

alter table public.planos enable row level security;
alter table public.plano_entitlements enable row level security;
alter table public.empresa_planos enable row level security;

revoke all on table public.planos from public, anon, authenticated, service_role;
revoke all on table public.plano_entitlements from public, anon, authenticated, service_role;
revoke all on table public.empresa_planos from public, anon, authenticated, service_role;

-- Seeds comerciais aprovados para arquitetura. Nomes nao participam de autorizacao nem enforcement.
insert into public.planos (codigo, nome, descricao, ordem_exibicao)
values
  ('basic', 'Basic', 'Plano inicial para operacoes de menor porte', 10),
  ('professional', 'Professional', 'Plano intermediario para operacoes em crescimento', 20),
  ('business', 'Business', 'Plano ampliado para estruturas com maior escala', 30),
  ('enterprise', 'Enterprise', 'Plano com limites configuraveis por contrato', 40)
on conflict (codigo) do nothing;

insert into public.plano_entitlements (plano_id, chave, tipo, valor_inteiro)
select p.id, seed.chave, 'inteiro', seed.valor
from public.planos p
join (values
  ('basic', 'usuarios_ativos.max', 10::bigint),
  ('basic', 'unidades.max', 1::bigint),
  ('professional', 'usuarios_ativos.max', 30::bigint),
  ('professional', 'unidades.max', 3::bigint),
  ('business', 'usuarios_ativos.max', 75::bigint),
  ('business', 'unidades.max', 10::bigint)
) as seed(codigo, chave, valor) on seed.codigo = p.codigo
on conflict (plano_id, chave) do nothing;

-- Reader de entitlements: nao loga, nao herda privilegios e nao bypassa RLS.
do $block$
begin
  if not exists (select 1 from pg_roles where rolname = 'bpf_entitlement_reader') then
    create role bpf_entitlement_reader
      nologin noinherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'bpf_plan_enforcer') then
    create role bpf_plan_enforcer
      nologin noinherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
  end if;
end
$block$;

grant bpf_entitlement_reader to postgres with inherit false, set true;
grant bpf_plan_enforcer to postgres with inherit false, set true;
grant usage on schema public, private to bpf_entitlement_reader, bpf_plan_enforcer;
grant usage on schema private to authenticated;

-- Reader pode enxergar somente a identidade e os memberships do subject atual.
grant select (id, ativo, status) on public.usuarios to bpf_entitlement_reader;
grant select (id, usuario_id, empresa_id, status) on public.usuario_empresas to bpf_entitlement_reader;
grant select (id, codigo, nome, descricao, ativo, ordem_exibicao) on public.planos to bpf_entitlement_reader;
grant select (plano_id, chave, tipo, valor_booleano, valor_inteiro, valor_texto) on public.plano_entitlements to bpf_entitlement_reader;
grant select (empresa_id, plano_id, origem, assigned_at) on public.empresa_planos to bpf_entitlement_reader;

create policy usuarios_entitlement_reader_proprio on public.usuarios
  for select to bpf_entitlement_reader
  using (id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid);

create policy usuario_empresas_entitlement_reader_proprio on public.usuario_empresas
  for select to bpf_entitlement_reader
  using (usuario_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid);

create policy empresa_planos_entitlement_reader_vinculos on public.empresa_planos
  for select to bpf_entitlement_reader
  using (exists (
    select 1
    from public.usuario_empresas ue
    join public.usuarios u on u.id = ue.usuario_id
    where ue.usuario_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
      and ue.empresa_id = empresa_planos.empresa_id
      and ue.status = 'ativo'
      and u.ativo
      and u.status = 'ativo'
  ));

create policy planos_entitlement_reader_vinculos on public.planos
  for select to bpf_entitlement_reader
  using (exists (
    select 1 from public.empresa_planos ep where ep.plano_id = planos.id
  ));

create policy plano_entitlements_entitlement_reader_vinculos on public.plano_entitlements
  for select to bpf_entitlement_reader
  using (exists (
    select 1 from public.planos p where p.id = plano_entitlements.plano_id
  ));

-- Enforcer possui somente leitura e existe para triggers internos de limite.
-- Ele nao pode logar nem chamar mutacoes da aplicacao.
grant select (id, empresa_id, ativo, status) on public.usuarios to bpf_plan_enforcer;
grant select (usuario_id, empresa_id, status) on public.usuario_empresas to bpf_plan_enforcer;
grant select (id, empresa_id, ativo) on public.unidades to bpf_plan_enforcer;
grant select (id, ativo) on public.planos to bpf_plan_enforcer;
grant select (plano_id, chave, tipo, valor_inteiro) on public.plano_entitlements to bpf_plan_enforcer;
grant select (empresa_id, plano_id) on public.empresa_planos to bpf_plan_enforcer;

create policy usuarios_plan_enforcer_select on public.usuarios
  for select to bpf_plan_enforcer using (true);
create policy usuario_empresas_plan_enforcer_select on public.usuario_empresas
  for select to bpf_plan_enforcer using (true);
create policy unidades_plan_enforcer_select on public.unidades
  for select to bpf_plan_enforcer using (true);
create policy planos_plan_enforcer_select on public.planos
  for select to bpf_plan_enforcer using (true);
create policy plano_entitlements_plan_enforcer_select on public.plano_entitlements
  for select to bpf_plan_enforcer using (true);
create policy empresa_planos_plan_enforcer_select on public.empresa_planos
  for select to bpf_plan_enforcer using (true);

-- Contrato de leitura do plano/entitlements do tenant atual.
grant create on schema private to bpf_entitlement_reader;
set role bpf_entitlement_reader;

create function private.meu_plano_entitlements(p_empresa_id uuid)
returns table (
  plano_id uuid,
  plano_codigo text,
  plano_nome text,
  plano_ativo boolean,
  origem text,
  chave text,
  tipo text,
  valor_booleano boolean,
  valor_inteiro bigint,
  valor_texto text
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    p.id,
    p.codigo,
    p.nome,
    p.ativo,
    ep.origem,
    pe.chave,
    pe.tipo,
    pe.valor_booleano,
    pe.valor_inteiro,
    pe.valor_texto
  from public.empresa_planos ep
  join public.planos p on p.id = ep.plano_id
  left join public.plano_entitlements pe on pe.plano_id = p.id
  where ep.empresa_id = p_empresa_id
  order by pe.chave nulls last
$function$;

revoke all on function private.meu_plano_entitlements(uuid) from public, anon, authenticated, service_role;
grant execute on function private.meu_plano_entitlements(uuid) to authenticated;
comment on function private.meu_plano_entitlements(uuid) is
  'Resolve o plano e os entitlements apenas quando o subject JWT possui membership ativo no tenant solicitado.';

reset role;
revoke create on schema private from bpf_entitlement_reader;
grant bpf_entitlement_reader to postgres with inherit false, set false;

create function public.meu_plano_entitlements(p_empresa_id uuid)
returns table (
  plano_id uuid,
  plano_codigo text,
  plano_nome text,
  plano_ativo boolean,
  origem text,
  chave text,
  tipo text,
  valor_booleano boolean,
  valor_inteiro bigint,
  valor_texto text
)
language sql
stable
security invoker
set search_path = ''
as $function$
  select * from private.meu_plano_entitlements(p_empresa_id)
$function$;

revoke all on function public.meu_plano_entitlements(uuid) from public, anon, service_role;
grant execute on function public.meu_plano_entitlements(uuid) to authenticated;
comment on function public.meu_plano_entitlements(uuid) is
  'RPC publica read-only de plano/entitlements; empresa_id informado nao concede acesso por si so.';

-- Helpers internos e triggers de enforcement. Ausencia de plano/entitlement = sem limite
-- nesta fase; isso evita regressao nas empresas existentes antes da atribuicao comercial.
grant create on schema private to bpf_plan_enforcer;
set role bpf_plan_enforcer;

create function private.limite_inteiro_empresa(p_empresa_id uuid, p_chave text)
returns bigint
language sql
stable
security definer
set search_path = ''
as $function$
  select pe.valor_inteiro
  from public.empresa_planos ep
  join public.plano_entitlements pe
    on pe.plano_id = ep.plano_id
   and pe.chave = p_chave
   and pe.tipo = 'inteiro'
  where ep.empresa_id = p_empresa_id
$function$;

create function private.validar_limite_unidades()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_limite bigint;
  v_consumo bigint;
begin
  if not new.ativo then return new; end if;
  if tg_op = 'UPDATE' and old.ativo and old.empresa_id = new.empresa_id then return new; end if;

  v_limite := private.limite_inteiro_empresa(new.empresa_id, 'unidades.max');
  if v_limite is null then return new; end if;

  select count(*) into v_consumo
  from public.unidades u
  where u.empresa_id = new.empresa_id
    and u.ativo
    and (tg_op = 'INSERT' or u.id <> new.id);

  if v_consumo + 1 > v_limite then
    raise exception using
      errcode = '23514',
      message = 'Limite de unidades ativas do plano atingido';
  end if;
  return new;
end
$function$;

create function private.validar_limite_usuario_legacy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_limite bigint;
  v_consumo bigint;
begin
  if new.empresa_id is null or not new.ativo or new.status <> 'ativo' then return new; end if;
  if tg_op = 'UPDATE'
     and old.empresa_id is not distinct from new.empresa_id
     and old.ativo
     and old.status = 'ativo' then
    return new;
  end if;

  v_limite := private.limite_inteiro_empresa(new.empresa_id, 'usuarios_ativos.max');
  if v_limite is null then return new; end if;

  select count(*) into v_consumo
  from (
    select u.id as usuario_id
    from public.usuarios u
    where u.empresa_id = new.empresa_id
      and u.ativo and u.status = 'ativo'
      and u.id <> new.id
    union
    select ue.usuario_id
    from public.usuario_empresas ue
    where ue.empresa_id = new.empresa_id
      and ue.status = 'ativo'
      and ue.usuario_id <> new.id
  ) ativos;

  if v_consumo + 1 > v_limite then
    raise exception using
      errcode = '23514',
      message = 'Limite de usuarios ativos do plano atingido';
  end if;
  return new;
end
$function$;

create function private.validar_limite_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_limite bigint;
  v_consumo bigint;
begin
  if new.status <> 'ativo' then return new; end if;
  if tg_op = 'UPDATE'
     and old.empresa_id is not distinct from new.empresa_id
     and old.usuario_id = new.usuario_id
     and old.status = 'ativo' then
    return new;
  end if;

  v_limite := private.limite_inteiro_empresa(new.empresa_id, 'usuarios_ativos.max');
  if v_limite is null then return new; end if;

  select count(*) into v_consumo
  from (
    select u.id as usuario_id
    from public.usuarios u
    where u.empresa_id = new.empresa_id
      and u.ativo and u.status = 'ativo'
      and u.id <> new.usuario_id
    union
    select ue.usuario_id
    from public.usuario_empresas ue
    where ue.empresa_id = new.empresa_id
      and ue.status = 'ativo'
      and ue.usuario_id <> new.usuario_id
  ) ativos;

  if v_consumo + 1 > v_limite then
    raise exception using
      errcode = '23514',
      message = 'Limite de usuarios ativos do plano atingido';
  end if;
  return new;
end
$function$;

revoke all on function private.limite_inteiro_empresa(uuid, text) from public, anon, authenticated, service_role;
revoke all on function private.validar_limite_unidades() from public, anon, authenticated, service_role;
revoke all on function private.validar_limite_usuario_legacy() from public, anon, authenticated, service_role;
revoke all on function private.validar_limite_membership() from public, anon, authenticated, service_role;
grant execute on function private.validar_limite_unidades() to postgres;
grant execute on function private.validar_limite_usuario_legacy() to postgres;
grant execute on function private.validar_limite_membership() to postgres;

reset role;
revoke create on schema private from bpf_plan_enforcer;
grant bpf_plan_enforcer to postgres with inherit false, set false;

create trigger trg_unidades_limite_plano
before insert or update of empresa_id, ativo on public.unidades
for each row execute function private.validar_limite_unidades();

create trigger trg_usuarios_limite_plano
before insert or update of empresa_id, ativo, status on public.usuarios
for each row execute function private.validar_limite_usuario_legacy();

create trigger trg_usuario_empresas_limite_plano
before insert or update of empresa_id, usuario_id, status on public.usuario_empresas
for each row execute function private.validar_limite_membership();

comment on table public.planos is
  'Catalogo comercial configuravel. Codigo e estavel; nome comercial nao participa de RBAC ou RLS.';
comment on table public.plano_entitlements is
  'Recursos e limites tipados por plano. Ausencia de chave significa que nao ha regra definida para aquele plano.';
comment on table public.empresa_planos is
  'Atribuicao comercial atual de plano por empresa; nao comprova pagamento e sera mantida pelo provisionamento/assinatura futuro.';

reset lock_timeout;
reset statement_timeout;
