-- Marco 1.5 / Fase 2: contrato de tenant/contexto validado pelo backend.
-- Mantem v_meu_contexto e o runtime legado intactos; novos contratos usam memberships.
set lock_timeout = '5s';
set statement_timeout = '60s';

-- Reader dedicado ao contexto multiempresa. Nao loga, nao bypassa RLS e nao herda privilegios.
-- Em Supabase hospedado, roles restritas nao devem depender de USAGE no schema gerenciado auth.
do $block$
begin
  if not exists (select 1 from pg_roles where rolname = 'bpf_tenant_reader') then
    create role bpf_tenant_reader
      nologin noinherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
  end if;
end
$block$;

grant bpf_tenant_reader to postgres with inherit false, set true;
grant usage on schema public, private to bpf_tenant_reader;
grant usage on schema private to authenticated;

grant select (id, nome, email, ativo, status) on public.usuarios to bpf_tenant_reader;
grant select (id, usuario_id, empresa_id, unidade_id, status, is_owner)
  on public.usuario_empresas to bpf_tenant_reader;
grant select (usuario_empresa_id, perfil_id)
  on public.usuario_empresa_perfis to bpf_tenant_reader;
grant select (id, razao_social, nome_fantasia, ativo)
  on public.empresas to bpf_tenant_reader;
grant select (id, empresa_id, nome, ativo)
  on public.unidades to bpf_tenant_reader;
grant select (id, empresa_id, nome, is_system, ativo)
  on public.perfis to bpf_tenant_reader;
grant select (perfil_id, permissao_id)
  on public.perfil_permissoes to bpf_tenant_reader;
grant select (id, codigo)
  on public.permissoes to bpf_tenant_reader;

-- Subject JWT lido diretamente do setting confiavel da requisicao, como ja adotado
-- pelo reader administrativo remoto. Isso evita dependencia do schema auth.
create policy usuarios_tenant_reader_proprio on public.usuarios
  for select to bpf_tenant_reader
  using (id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid);

create policy usuario_empresas_tenant_reader_proprio on public.usuario_empresas
  for select to bpf_tenant_reader
  using (usuario_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid);

create policy usuario_empresa_perfis_tenant_reader_proprio on public.usuario_empresa_perfis
  for select to bpf_tenant_reader
  using (exists (
    select 1
    from public.usuario_empresas ue
    where ue.id = usuario_empresa_perfis.usuario_empresa_id
      and ue.usuario_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  ));

create policy empresas_tenant_reader_vinculos on public.empresas
  for select to bpf_tenant_reader
  using (exists (
    select 1
    from public.usuario_empresas ue
    where ue.empresa_id = empresas.id
      and ue.usuario_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
      and ue.status = 'ativo'
  ));

create policy unidades_tenant_reader_vinculos on public.unidades
  for select to bpf_tenant_reader
  using (exists (
    select 1
    from public.usuario_empresas ue
    where ue.empresa_id = unidades.empresa_id
      and ue.usuario_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
      and ue.status = 'ativo'
  ));

create policy perfis_tenant_reader_escopo on public.perfis
  for select to bpf_tenant_reader
  using (
    ativo and (
      (empresa_id is null and is_system)
      or exists (
        select 1
        from public.usuario_empresas ue
        where ue.empresa_id = perfis.empresa_id
          and ue.usuario_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
          and ue.status = 'ativo'
      )
    )
  );

create policy perfil_permissoes_tenant_reader_escopo on public.perfil_permissoes
  for select to bpf_tenant_reader
  using (exists (
    select 1 from public.perfis p where p.id = perfil_permissoes.perfil_id
  ));

create policy permissoes_tenant_reader_catalogo on public.permissoes
  for select to bpf_tenant_reader
  using (true);

-- Lista apenas memberships operacionais da identidade atual.
-- Funcoes privadas sao criadas e administradas enquanto o owner restrito esta ativo.
grant create on schema private to bpf_tenant_reader;
set role bpf_tenant_reader;

create function private.meus_vinculos()
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
  select
    ue.id,
    ue.empresa_id,
    e.nome_fantasia,
    e.razao_social,
    ue.unidade_id,
    un.nome,
    ue.status,
    ue.is_owner
  from public.usuarios u
  join public.usuario_empresas ue
    on ue.usuario_id = u.id
   and ue.status = 'ativo'
  join public.empresas e
    on e.id = ue.empresa_id
   and e.ativo
  left join public.unidades un on un.id = ue.unidade_id
  where nullif(current_setting('request.jwt.claim.sub', true), '')::uuid is not null
    and u.id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    and u.ativo
    and u.status = 'ativo'
  order by coalesce(e.nome_fantasia, e.razao_social), ue.empresa_id
$function$;

create function private.meu_contexto_empresa(p_empresa_id uuid)
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
  select
    u.id,
    ue.id,
    u.nome,
    u.email,
    u.ativo,
    ue.status,
    ue.empresa_id,
    e.nome_fantasia,
    e.razao_social,
    ue.unidade_id,
    un.nome,
    ue.is_owner,
    coalesce(array_agg(distinct p.nome) filter (where p.nome is not null), '{}'::text[]),
    coalesce(array_agg(distinct pm.codigo) filter (where pm.codigo is not null), '{}'::text[])
  from public.usuarios u
  join public.usuario_empresas ue
    on ue.usuario_id = u.id
   and ue.empresa_id = p_empresa_id
   and ue.status = 'ativo'
  join public.empresas e
    on e.id = ue.empresa_id
   and e.ativo
  left join public.unidades un on un.id = ue.unidade_id
  left join public.usuario_empresa_perfis uep on uep.usuario_empresa_id = ue.id
  left join public.perfis p
    on p.id = uep.perfil_id
   and p.ativo
   and ((p.empresa_id is null and p.is_system) or p.empresa_id = ue.empresa_id)
  left join public.perfil_permissoes pp on pp.perfil_id = p.id
  left join public.permissoes pm on pm.id = pp.permissao_id
  where nullif(current_setting('request.jwt.claim.sub', true), '')::uuid is not null
    and u.id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    and u.ativo
    and u.status = 'ativo'
  group by u.id, ue.id, e.nome_fantasia, e.razao_social, un.nome
$function$;

revoke all on function private.meus_vinculos() from public, anon, authenticated, service_role;
revoke all on function private.meu_contexto_empresa(uuid) from public, anon, authenticated, service_role;
grant execute on function private.meus_vinculos() to authenticated;
grant execute on function private.meu_contexto_empresa(uuid) to authenticated;

comment on function private.meus_vinculos() is
  'Lista memberships ativos do subject JWT globalmente ativo; owner restrito bpf_tenant_reader e sujeito a RLS.';
comment on function private.meu_contexto_empresa(uuid) is
  'Resolve contexto e RBAC de um tenant somente quando o subject JWT possui membership ativo na empresa solicitada.';

reset role;
revoke create on schema private from bpf_tenant_reader;
grant bpf_tenant_reader to postgres with inherit false, set false;

-- Wrappers RPC em public continuam SECURITY INVOKER; autorizacao real fica no reader restrito.
create function public.meus_vinculos()
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
security invoker
set search_path = ''
as $function$
  select * from private.meus_vinculos()
$function$;

create function public.meu_contexto_empresa(p_empresa_id uuid)
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
security invoker
set search_path = ''
as $function$
  select * from private.meu_contexto_empresa(p_empresa_id)
$function$;

revoke all on function public.meus_vinculos() from public, anon, service_role;
revoke all on function public.meu_contexto_empresa(uuid) from public, anon, service_role;
grant execute on function public.meus_vinculos() to authenticated;
grant execute on function public.meu_contexto_empresa(uuid) to authenticated;

comment on function public.meus_vinculos() is
  'RPC publica de leitura dos tenants autorizados da identidade atual.';
comment on function public.meu_contexto_empresa(uuid) is
  'RPC publica de contexto empresarial. O empresa_id informado nunca autoriza sozinho; membership ativo e validado no backend.';

reset lock_timeout;
reset statement_timeout;
