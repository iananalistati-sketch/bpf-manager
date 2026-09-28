-- Corrige a leitura do subject JWT no Supabase hospedado.
-- PostgREST expõe o payload completo em request.jwt.claims; o setting legado
-- request.jwt.claim.sub é mantido como fallback para PGlite/testes e compatibilidade.
set lock_timeout = '5s';
set statement_timeout = '60s';

create or replace function private.request_jwt_subject()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $function$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
  )::uuid
$function$;

revoke all on function private.request_jwt_subject() from public, anon, service_role;
grant execute on function private.request_jwt_subject() to authenticated, bpf_tenant_reader, bpf_entitlement_reader, bpf_admin_writer;

alter policy usuarios_tenant_reader_proprio on public.usuarios
  using (id = private.request_jwt_subject());
alter policy usuario_empresas_tenant_reader_proprio on public.usuario_empresas
  using (usuario_id = private.request_jwt_subject());
alter policy usuario_empresa_perfis_tenant_reader_proprio on public.usuario_empresa_perfis
  using (exists (
    select 1 from public.usuario_empresas ue
    where ue.id = usuario_empresa_perfis.usuario_empresa_id
      and ue.usuario_id = private.request_jwt_subject()
  ));
alter policy empresas_tenant_reader_vinculos on public.empresas
  using (exists (
    select 1 from public.usuario_empresas ue
    where ue.empresa_id = empresas.id
      and ue.usuario_id = private.request_jwt_subject()
      and ue.status = 'ativo'
  ));
alter policy unidades_tenant_reader_vinculos on public.unidades
  using (exists (
    select 1 from public.usuario_empresas ue
    where ue.empresa_id = unidades.empresa_id
      and ue.usuario_id = private.request_jwt_subject()
      and ue.status = 'ativo'
  ));
alter policy perfis_tenant_reader_escopo on public.perfis
  using (
    ativo and (
      (empresa_id is null and is_system)
      or exists (
        select 1 from public.usuario_empresas ue
        where ue.empresa_id = perfis.empresa_id
          and ue.usuario_id = private.request_jwt_subject()
          and ue.status = 'ativo'
      )
    )
  );

alter policy usuarios_entitlement_reader_proprio on public.usuarios
  using (id = private.request_jwt_subject());
alter policy usuario_empresas_entitlement_reader_proprio on public.usuario_empresas
  using (usuario_id = private.request_jwt_subject());
alter policy empresa_planos_entitlement_reader_vinculos on public.empresa_planos
  using (exists (
    select 1
    from public.usuario_empresas ue
    join public.usuarios u on u.id = ue.usuario_id
    where ue.usuario_id = private.request_jwt_subject()
      and ue.empresa_id = empresa_planos.empresa_id
      and ue.status = 'ativo'
      and u.ativo
      and u.status = 'ativo'
  ));

-- Essa policy existe apenas em ambientes que aplicaram o hardening intermediário do writer.
do $block$
begin
  if exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='usuarios'
      and policyname='usuarios_admin_writer_actor_select'
  ) then
    execute 'alter policy usuarios_admin_writer_actor_select on public.usuarios using (id = private.request_jwt_subject() and ativo and status = ''ativo'')';
  end if;
end
$block$;

grant bpf_tenant_reader to postgres with inherit false, set true;
grant create on schema private to bpf_tenant_reader;
set role bpf_tenant_reader;

create or replace function private.meus_vinculos()
returns table (
  membership_id uuid,
  empresa_id uuid,
  nome_fantasia text,
  razao_social text,
  unidade_id uuid,
  unidade_nome text,
  status text,
  is_owner boolean
)
language sql
stable
security definer
set search_path = ''
as $function$
  select ue.id, ue.empresa_id, e.nome_fantasia, e.razao_social,
         ue.unidade_id, un.nome, ue.status, ue.is_owner
  from public.usuarios u
  join public.usuario_empresas ue on ue.usuario_id=u.id and ue.status='ativo'
  join public.empresas e on e.id=ue.empresa_id and e.ativo
  left join public.unidades un on un.id=ue.unidade_id
  where private.request_jwt_subject() is not null
    and u.id=private.request_jwt_subject()
    and u.ativo and u.status='ativo'
  order by coalesce(e.nome_fantasia,e.razao_social),ue.empresa_id
$function$;

create or replace function private.meu_contexto_empresa(p_empresa_id uuid)
returns table (
  usuario_id uuid,
  membership_id uuid,
  nome text,
  email text,
  ativo boolean,
  status text,
  empresa_id uuid,
  nome_fantasia text,
  razao_social text,
  unidade_id uuid,
  unidade_nome text,
  is_owner boolean,
  perfis text[],
  permissoes text[]
)
language sql
stable
security definer
set search_path = ''
as $function$
  select u.id,ue.id,u.nome,u.email,u.ativo,ue.status,ue.empresa_id,
         e.nome_fantasia,e.razao_social,ue.unidade_id,un.nome,ue.is_owner,
         coalesce(array_agg(distinct p.nome) filter (where p.nome is not null),'{}'::text[]),
         coalesce(array_agg(distinct pm.codigo) filter (where pm.codigo is not null),'{}'::text[])
  from public.usuarios u
  join public.usuario_empresas ue on ue.usuario_id=u.id and ue.empresa_id=p_empresa_id and ue.status='ativo'
  join public.empresas e on e.id=ue.empresa_id and e.ativo
  left join public.unidades un on un.id=ue.unidade_id
  left join public.usuario_empresa_perfis uep on uep.usuario_empresa_id=ue.id
  left join public.perfis p on p.id=uep.perfil_id and p.ativo
    and ((p.empresa_id is null and p.is_system) or p.empresa_id=ue.empresa_id)
  left join public.perfil_permissoes pp on pp.perfil_id=p.id
  left join public.permissoes pm on pm.id=pp.permissao_id
  where private.request_jwt_subject() is not null
    and u.id=private.request_jwt_subject()
    and u.ativo and u.status='ativo'
  group by u.id,ue.id,e.nome_fantasia,e.razao_social,un.nome
$function$;

reset role;
revoke create on schema private from bpf_tenant_reader;
grant bpf_tenant_reader to postgres with inherit false, set false;

grant bpf_entitlement_reader to postgres with inherit false, set true;
grant create on schema private to bpf_entitlement_reader;
set role bpf_entitlement_reader;

create or replace function private.meu_plano_entitlements(p_empresa_id uuid)
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
  select p.id,p.codigo,p.nome,p.ativo,ep.origem,
         pe.chave,pe.tipo,pe.valor_booleano,pe.valor_inteiro,pe.valor_texto
  from public.usuario_empresas ue
  join public.usuarios u on u.id=ue.usuario_id and u.ativo and u.status='ativo'
  join public.empresa_planos ep on ep.empresa_id=ue.empresa_id
  join public.planos p on p.id=ep.plano_id
  left join public.plano_entitlements pe on pe.plano_id=p.id
  where ue.usuario_id=private.request_jwt_subject()
    and ue.empresa_id=p_empresa_id
    and ue.status='ativo'
  order by pe.chave nulls last
$function$;

create or replace function private.meu_plano_resumo(p_empresa_id uuid)
returns table (
  plano_id uuid,
  plano_codigo text,
  plano_nome text,
  origem text,
  usuarios_ativos bigint,
  usuarios_ativos_max bigint,
  unidades_ativas bigint,
  unidades_max bigint
)
language sql
stable
security definer
set search_path = ''
as $function$
  select p.id,p.codigo,p.nome,ep.origem,
         consumo.usuarios_ativos,
         (select pe.valor_inteiro from public.plano_entitlements pe
          where pe.plano_id=p.id and pe.chave='usuarios_ativos.max' and pe.tipo='inteiro'),
         consumo.unidades_ativas,
         (select pe.valor_inteiro from public.plano_entitlements pe
          where pe.plano_id=p.id and pe.chave='unidades.max' and pe.tipo='inteiro')
  from public.usuario_empresas ue
  join public.usuarios u on u.id=ue.usuario_id and u.ativo and u.status='ativo'
  cross join lateral private.consumo_plano_empresa(p_empresa_id) consumo
  left join public.empresa_planos ep on ep.empresa_id=ue.empresa_id
  left join public.planos p on p.id=ep.plano_id
  where ue.usuario_id=private.request_jwt_subject()
    and ue.empresa_id=p_empresa_id
    and ue.status='ativo'
  limit 1
$function$;

reset role;
revoke create on schema private from bpf_entitlement_reader;
grant bpf_entitlement_reader to postgres with inherit false, set false;

reset lock_timeout;
reset statement_timeout;
