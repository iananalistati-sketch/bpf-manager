-- Consolida o fluxo de convite tenant-aware: a RPC SECURITY DEFINER valida tenant,
-- perfis e teto de delegacao antes de gravar usuario_perfis. RLS nao deve duplicar
-- essas regras e virar uma segunda fonte de autorizacao sujeita a GUCs/leituras indiretas.
set lock_timeout = '5s';
set statement_timeout = '60s';

-- Falha cedo se o owner esperado da RPC tiver sido alterado em alguma migration.
do $block$
declare
  v_owner text;
begin
  select pg_get_userbyid(p.proowner)
    into v_owner
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.proname = 'admin_usuario_vincular_convite_tenant'
    and pg_get_function_identity_arguments(p.oid) = 'p_empresa_id uuid, p_usuario_id uuid, p_unidade_id uuid, p_perfil_ids uuid[], p_justificativa text';

  if v_owner is distinct from 'bpf_admin_writer' then
    raise exception 'admin_usuario_vincular_convite_tenant owner inesperado: %', coalesce(v_owner, '<nao encontrado>');
  end if;
end
$block$;

-- Remove apenas a policy auxiliar criada para o fluxo tenant-aware.
-- A policy historica de administracao permanece inalterada para os demais comandos.
drop policy if exists usuario_perfis_admin_writer_tenant_insert on public.usuario_perfis;

-- bpf_admin_writer e NOLOGIN/NOBYPASSRLS e nao e atribuivel a authenticated.
-- As unicas escritas chegam por funcoes SECURITY DEFINER que fazem a autorizacao antes.
-- Portanto a RLS aqui atua como fronteira de role, nao como duplicacao da regra de negocio.
create policy usuario_perfis_admin_writer_rpc_insert
  on public.usuario_perfis
  for insert to bpf_admin_writer
  with check (true);

-- Guard rails do modelo de execucao.
do $block$
declare
  v_login boolean;
  v_bypass boolean;
  v_authenticated_member boolean;
begin
  select rolcanlogin, rolbypassrls
    into v_login, v_bypass
  from pg_roles
  where rolname = 'bpf_admin_writer';

  if v_login is distinct from false or v_bypass is distinct from false then
    raise exception 'bpf_admin_writer deve permanecer NOLOGIN e NOBYPASSRLS';
  end if;

  select pg_has_role('authenticated', 'bpf_admin_writer', 'SET')
    into v_authenticated_member;
  if v_authenticated_member then
    raise exception 'authenticated nao pode SET ROLE para bpf_admin_writer';
  end if;
end
$block$;

reset lock_timeout;
reset statement_timeout;
