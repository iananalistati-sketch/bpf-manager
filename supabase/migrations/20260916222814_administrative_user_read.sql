-- Administrative reads only. Existing self-read policies remain intact.
-- Requires the existing BPF schema; this is not a baseline migration.
set lock_timeout = '5s';
set statement_timeout = '60s';

-- Fail closed before changing integrity; never repair tenant data implicitly.
do $preflight$
begin
  if exists (
    select 1 from public.usuarios u
    left join public.unidades un on un.id = u.unidade_id
    where u.unidade_id is not null
      and (u.empresa_id is null or un.id is null or un.empresa_id <> u.empresa_id)
  ) then
    raise exception 'Existing usuarios contain incompatible empresa/unidade; migration aborted';
  end if;
end
$preflight$;

alter table public.unidades
  add constraint unidades_id_empresa_unique unique (id, empresa_id);
alter table public.usuarios
  add constraint usuarios_unidade_empresa_fkey
  foreign key (unidade_id, empresa_id)
  references public.unidades (id, empresa_id)
  on update no action on delete no action;
comment on constraint usuarios_unidade_empresa_fkey on public.usuarios is
  'A unidade vinculada deve pertencer a empresa do usuario; sem correcao automatica de historico.';

-- This owner cannot log in, bypass RLS, write data, or inherit client policies.
-- A dedicated policy graph avoids usuarios -> perfis -> usuarios recursion.
create role bpf_authz_reader
  nologin noinherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
grant bpf_authz_reader to postgres with inherit false, set true;
create schema if not exists private authorization postgres;
revoke create on schema private from public, anon, authenticated;
grant usage on schema private to authenticated, bpf_authz_reader;
grant usage on schema public, auth to bpf_authz_reader;
grant execute on function auth.uid() to bpf_authz_reader;

grant select (id, empresa_id, ativo, status) on public.usuarios to bpf_authz_reader;
grant select (usuario_id, perfil_id) on public.usuario_perfis to bpf_authz_reader;
grant select (id, empresa_id, is_system, ativo) on public.perfis to bpf_authz_reader;
grant select (perfil_id, permissao_id) on public.perfil_permissoes to bpf_authz_reader;
grant select (id, codigo) on public.permissoes to bpf_authz_reader;

create policy usuarios_authz_reader_proprio on public.usuarios
  for select to bpf_authz_reader
  using (id = (select auth.uid()));
create policy usuario_perfis_authz_reader_proprio on public.usuario_perfis
  for select to bpf_authz_reader
  using (usuario_id = (select auth.uid()));
create policy perfis_authz_reader_escopo on public.perfis
  for select to bpf_authz_reader
  using (
    ativo and (
      (empresa_id is null and is_system)
      or empresa_id = (
        select u.empresa_id from public.usuarios u
        where u.id = (select auth.uid()) and u.ativo and u.status = 'ativo'
      )
    )
  );
create policy perfil_permissoes_authz_reader_escopo on public.perfil_permissoes
  for select to bpf_authz_reader
  using (exists (
    select 1 from public.perfis p where p.id = perfil_permissoes.perfil_id
  ));
create policy permissoes_authz_reader_codigos on public.permissoes
  for select to bpf_authz_reader
  using (codigo in ('configuracoes.visualizar', 'usuarios.gerenciar'));

-- No tenant/actor parameter. The result is one authorized tenant or NULL.
-- SECURITY DEFINER selects as the restricted reader above, never as postgres.
create function private.empresa_leitura_usuarios()
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select u.empresa_id
  from public.usuarios u
  join public.usuario_perfis up on up.usuario_id = u.id
  join public.perfis p on p.id = up.perfil_id
    and p.ativo
    and ((p.empresa_id is null and p.is_system) or p.empresa_id = u.empresa_id)
  join public.perfil_permissoes pp on pp.perfil_id = p.id
  join public.permissoes pm on pm.id = pp.permissao_id
  where (select auth.uid()) is not null
    and u.id = (select auth.uid())
    and u.ativo and u.status = 'ativo' and u.empresa_id is not null
  group by u.empresa_id
  having bool_or(pm.codigo = 'configuracoes.visualizar')
     and bool_or(pm.codigo = 'usuarios.gerenciar')
$function$;

-- Ownership transfer needs CREATE only temporarily; clients never receive it.
-- Set ACL and comment before transfer: postgres does not inherit reader rights.
revoke all on function private.empresa_leitura_usuarios() from public, anon, authenticated, service_role;
grant execute on function private.empresa_leitura_usuarios() to authenticated;
comment on function private.empresa_leitura_usuarios() is
  'Empresa autorizada para leitura administrativa: auth.uid ativo, ambas permissoes de perfis ativos validos. Owner restrito e sujeito a RLS; sem parametros nem escrita.';
grant create on schema private to bpf_authz_reader;
alter function private.empresa_leitura_usuarios() owner to bpf_authz_reader;
revoke create on schema private from bpf_authz_reader;
-- Keep DBA role administration for future migrations, without SET or inheritance.
-- No application role receives membership.
-- CREATE ROLE already gives its creator ADMIN; do not regrant ADMIN to the grantor.
grant bpf_authz_reader to postgres with inherit false, set false;

create policy usuarios_select_administracao_empresa on public.usuarios
  for select to authenticated
  using (empresa_id = (select private.empresa_leitura_usuarios()));

-- List only assignments of users in the authorized tenant to compatible roles.
-- Inactive target roles remain visible for review; they never authorize reads.
create policy usuario_perfis_select_administracao_empresa on public.usuario_perfis
  for select to authenticated
  using (exists (
    select 1
    from public.usuarios u
    join public.perfis p on p.id = usuario_perfis.perfil_id
      and ((p.empresa_id is null and p.is_system) or p.empresa_id = u.empresa_id)
    where u.id = usuario_perfis.usuario_id
      and u.empresa_id = (select private.empresa_leitura_usuarios())
  ));

create or replace view public.v_meu_contexto
with (security_invoker = true)
as
select
  u.id as usuario_id,
  u.nome,
  u.email,
  u.ativo,
  u.status,
  u.empresa_id,
  e.nome_fantasia,
  e.razao_social,
  u.unidade_id,
  un.nome as unidade_nome,
  coalesce(array_agg(distinct p.nome) filter (where p.nome is not null), '{}'::text[]) as perfis,
  coalesce(array_agg(distinct pm.codigo) filter (where pm.codigo is not null), '{}'::text[]) as permissoes
from public.usuarios u
left join public.empresas e on e.id = u.empresa_id
left join public.unidades un on un.id = u.unidade_id
left join public.usuario_perfis up on up.usuario_id = u.id
left join public.perfis p on p.id = up.perfil_id and p.ativo
  and ((p.empresa_id is null and p.is_system) or p.empresa_id = u.empresa_id)
left join public.perfil_permissoes pp on pp.perfil_id = p.id
left join public.permissoes pm on pm.id = pp.permissao_id
where u.id = (select auth.uid())
group by u.id, u.nome, u.email, u.ativo, u.status, u.empresa_id,
  e.nome_fantasia, e.razao_social, u.unidade_id, un.nome;

revoke all on public.v_meu_contexto from public, anon, authenticated;
grant select on public.v_meu_contexto to authenticated;

reset lock_timeout;
reset statement_timeout;
