-- Consolidated local replay for hosted migration 20260928112903_tenant_permission_helper.
-- Preserves the original hardening sequence while aligning Supabase migration history.


-- BEGIN 20260925121500_harden_tenant_invite_actor_read.sql
-- Permite ao writer restrito ler a propria identidade durante checagens tenant-aware,
-- mesmo quando a empresa primaria legada difere do tenant ativo.
set lock_timeout = '5s';
set statement_timeout = '60s';

create policy usuarios_admin_writer_actor_select on public.usuarios
  for select to bpf_admin_writer
  using (
    id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    and ativo and status='ativo'
  );

reset lock_timeout;
reset statement_timeout;

-- END 20260925121500_harden_tenant_invite_actor_read.sql

-- BEGIN 20260925122000_fix_tenant_invite_target_visibility.sql
-- Corrige a transicao RLS do usuario convidado: durante o UPDATE, o writer restrito
-- precisa continuar enxergando o mesmo alvo tanto no estado pendente (antes) quanto
-- no estado ja vinculado ao tenant ativo (depois).
set lock_timeout = '5s';
set statement_timeout = '60s';

create policy usuarios_admin_writer_invite_target_select_tenant on public.usuarios
  for select to bpf_admin_writer
  using (
    id = nullif(current_setting('bpf.invite_target', true), '')::uuid
    and (
      (empresa_id is null and status = 'pendente')
      or (
        empresa_id = nullif(current_setting('bpf.active_empresa', true), '')::uuid
        and ativo and status = 'ativo'
      )
    )
  );

reset lock_timeout;
reset statement_timeout;

-- END 20260925122000_fix_tenant_invite_target_visibility.sql

-- BEGIN 20260925122500_harden_tenant_invite_membership_upsert.sql
-- Garante que o caminho ON CONFLICT do convite tenant-aware consiga recuperar um
-- membership pendente/preexistente do mesmo alvo sem abrir UPDATE genérico ao writer.
set lock_timeout = '5s';
set statement_timeout = '60s';

create policy usuario_empresas_admin_writer_invite_target_update
  on public.usuario_empresas
  for update to bpf_admin_writer
  using (
    empresa_id = nullif(current_setting('bpf.active_empresa', true), '')::uuid
    and usuario_id = nullif(current_setting('bpf.invite_target', true), '')::uuid
  )
  with check (
    empresa_id = nullif(current_setting('bpf.active_empresa', true), '')::uuid
    and usuario_id = nullif(current_setting('bpf.invite_target', true), '')::uuid
    and status = 'ativo'
  );

reset lock_timeout;
reset statement_timeout;

-- END 20260925122500_harden_tenant_invite_membership_upsert.sql

-- BEGIN 20260925123000_fix_tenant_invite_legacy_profile_insert.sql
-- Corrige o INSERT legado em usuario_perfis durante convite tenant-aware.
-- A policy anterior dependia de reler o usuario-alvo depois da transicao pendente -> ativo,
-- acoplando a escrita a uma segunda cadeia de RLS em usuarios. Para o fluxo de convite,
-- o alvo e o tenant ja foram validados pela funcao SECURITY DEFINER e registrados em GUCs
-- locais da transacao. Mantemos o escopo minimo: somente invite_target, tenant ativo,
-- perfil ativo/compativel e created_by igual ao subject autenticado.
set lock_timeout = '5s';
set statement_timeout = '60s';

drop policy if exists usuario_perfis_admin_writer_tenant_insert on public.usuario_perfis;

create policy usuario_perfis_admin_writer_tenant_insert on public.usuario_perfis
  for insert to bpf_admin_writer
  with check (
    usuario_id = nullif(current_setting('bpf.invite_target', true), '')::uuid
    and created_by = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    and nullif(current_setting('bpf.active_empresa', true), '')::uuid is not null
    and exists (
      select 1
      from public.perfis p
      where p.id = usuario_perfis.perfil_id
        and p.ativo
        and (
          (p.empresa_id is null and p.is_system)
          or p.empresa_id = nullif(current_setting('bpf.active_empresa', true), '')::uuid
        )
    )
  );

reset lock_timeout;
reset statement_timeout;

-- END 20260925123000_fix_tenant_invite_legacy_profile_insert.sql

-- BEGIN 20260925123500_make_invite_legacy_profile_policy_nonrecursive.sql
-- Remove a cadeia RLS indireta do INSERT legado em usuario_perfis durante convite tenant-aware.
-- O conjunto de perfis ja e validado dentro da funcao SECURITY DEFINER antes da mutacao.
-- A policy passa a conferir somente os valores previamente validados e gravados em GUCs
-- locais da transacao, evitando uma subconsulta em perfis sujeita a outra RLS.
set lock_timeout = '5s';
set statement_timeout = '60s';

-- Mantem a mesma assinatura/owner/ACL e adiciona apenas o contexto validado de perfis.
grant bpf_admin_writer to postgres with inherit false, set true;
grant create on schema private to bpf_admin_writer;
set role bpf_admin_writer;

create or replace function private.admin_usuario_vincular_convite_tenant(
  p_empresa_id uuid,
  p_usuario_id uuid,
  p_unidade_id uuid,
  p_perfil_ids uuid[],
  p_justificativa text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_ator uuid := nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
  v_usuario public.usuarios%rowtype;
  v_membership_id uuid;
  v_perfil_id uuid;
  v_permissoes text[];
begin
  select c.permissoes into v_permissoes
  from private.meu_contexto_empresa(p_empresa_id) c
  where c.usuario_id = v_ator;

  if v_permissoes is null
     or not ('configuracoes.visualizar' = any(v_permissoes))
     or not ('usuarios.gerenciar' = any(v_permissoes))
     or not ('usuarios.convidar' = any(v_permissoes)) then
    raise exception using errcode='42501', message='Sem permissao para convidar usuarios no tenant selecionado';
  end if;

  if length(btrim(coalesce(p_justificativa,''))) < 5 then
    raise exception using errcode='22023', message='Justificativa deve possuir ao menos 5 caracteres';
  end if;
  if coalesce(array_length(p_perfil_ids,1),0) = 0 then
    raise exception using errcode='22023', message='Selecione ao menos um perfil';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_empresa_id::text, 0));
  perform set_config('bpf.active_empresa', p_empresa_id::text, true);
  perform set_config('bpf.invite_target', p_usuario_id::text, true);

  if p_unidade_id is not null and not exists (
    select 1 from public.unidades
    where id=p_unidade_id and empresa_id=p_empresa_id and ativo
  ) then
    raise exception using errcode='22023', message='Unidade invalida, inativa ou fora da empresa';
  end if;

  foreach v_perfil_id in array p_perfil_ids loop
    if not exists (
      select 1 from public.perfis p
      where p.id=v_perfil_id and p.ativo
        and ((p.empresa_id is null and p.is_system) or p.empresa_id=p_empresa_id)
    ) then
      raise exception using errcode='22023', message='Perfil invalido, inativo ou fora da empresa';
    end if;
    if exists (
      select 1
      from public.perfil_permissoes pp
      join public.permissoes pm on pm.id=pp.permissao_id
      where pp.perfil_id=v_perfil_id
        and not (pm.codigo = any(v_permissoes))
    ) then
      raise exception using errcode='42501', message='Nao e permitido delegar um perfil com permissoes superiores as do ator';
    end if;
  end loop;

  -- So depois de validar todos os perfis o conjunto e exposto a policies da mesma transacao.
  perform set_config('bpf.invite_profiles', p_perfil_ids::text, true);

  select * into v_usuario
  from public.usuarios
  where id=p_usuario_id and empresa_id is null and status='pendente'
  for update;
  if not found then
    raise exception using errcode='P0002', message='Convite pendente nao encontrado';
  end if;

  update public.usuarios
  set empresa_id=p_empresa_id, unidade_id=p_unidade_id, status='ativo', ativo=true, updated_at=now()
  where id=p_usuario_id;

  insert into public.usuario_perfis(usuario_id, perfil_id, created_by)
    select p_usuario_id, x, v_ator from unnest(p_perfil_ids) x
    on conflict (usuario_id, perfil_id) do nothing;

  insert into public.usuario_empresas(usuario_id, empresa_id, unidade_id, status, is_owner, created_by)
  values(p_usuario_id, p_empresa_id, p_unidade_id, 'ativo', false, v_ator)
  on conflict (usuario_id, empresa_id) do update
    set unidade_id=excluded.unidade_id, status='ativo', updated_at=now()
  returning id into v_membership_id;

  insert into public.usuario_empresa_perfis(usuario_empresa_id, perfil_id, created_by)
    select v_membership_id, x, v_ator from unnest(p_perfil_ids) x
    on conflict (usuario_empresa_id, perfil_id) do nothing;

  insert into public.auditoria_eventos(
    empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto
  ) values(
    p_empresa_id,p_unidade_id,v_ator,'usuario',p_usuario_id,'usuario.convidado_vinculado',
    jsonb_build_object('empresa_id',null,'status','pendente'),
    jsonb_build_object('empresa_id',p_empresa_id,'unidade_id',p_unidade_id,'status','ativo','perfil_ids',p_perfil_ids,'membership_id',v_membership_id),
    btrim(p_justificativa),jsonb_build_object('origem','edge_function','modelo','membership')
  );
end
$function$;

reset role;
revoke create on schema private from bpf_admin_writer;
grant bpf_admin_writer to postgres with inherit false, set false;

-- Elimina a dependencia da policy de INSERT em usuario_perfis de SELECTs sujeitos a RLS.
drop policy if exists usuario_perfis_admin_writer_tenant_insert on public.usuario_perfis;
create policy usuario_perfis_admin_writer_tenant_insert on public.usuario_perfis
  for insert to bpf_admin_writer
  with check (
    usuario_id = nullif(current_setting('bpf.invite_target', true), '')::uuid
    and created_by = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    and perfil_id = any(
      coalesce(
        nullif(current_setting('bpf.invite_profiles', true), '')::uuid[],
        array[]::uuid[]
      )
    )
  );

reset lock_timeout;
reset statement_timeout;

-- END 20260925123500_make_invite_legacy_profile_policy_nonrecursive.sql

-- BEGIN 20260925124000_simplify_invite_legacy_profile_rls.sql
-- Simplifica a policy de INSERT legado em usuario_perfis no fluxo de convite tenant-aware.
-- A autorizacao do tenant, a compatibilidade/atividade dos perfis e o teto de delegacao ja sao
-- validados dentro de private.admin_usuario_vincular_convite_tenant antes deste INSERT.
-- Aqui a RLS cumpre apenas a funcao de impedir que bpf_admin_writer insira para outro alvo
-- fora do convite corrente. Isso evita depender de GUC de array/created_by na expressao RLS.
set lock_timeout = '5s';
set statement_timeout = '60s';

drop policy if exists usuario_perfis_admin_writer_tenant_insert on public.usuario_perfis;

create policy usuario_perfis_admin_writer_tenant_insert on public.usuario_perfis
  for insert to bpf_admin_writer
  with check (
    usuario_id = nullif(current_setting('bpf.invite_target', true), '')::uuid
    and nullif(current_setting('bpf.active_empresa', true), '')::uuid is not null
  );

reset lock_timeout;
reset statement_timeout;

-- END 20260925124000_simplify_invite_legacy_profile_rls.sql

-- BEGIN 20260925124500_stop_duplicating_invite_auth_in_usuario_perfis_rls.sql
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

-- END 20260925124500_stop_duplicating_invite_auth_in_usuario_perfis_rls.sql

-- BEGIN 20260925125000_bridge_legacy_profile_sync_outside_rls.sql
-- Fecha o fluxo de convite tenant-aware sem depender da RLS de usuario_perfis para a
-- compatibilidade legada. A autorizacao continua na RPC bpf_admin_writer; a escrita
-- legada passa por um helper minimo, SECURITY DEFINER, com validacoes redundantes e
-- sem exposicao a authenticated/anon/service_role.
set lock_timeout = '5s';
set statement_timeout = '60s';

create or replace function private.sync_invite_legacy_profile(
  p_usuario_id uuid,
  p_perfil_id uuid,
  p_created_by uuid,
  p_empresa_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
  v_active_empresa uuid := nullif(current_setting('bpf.active_empresa', true), '')::uuid;
  v_invite_target uuid := nullif(current_setting('bpf.invite_target', true), '')::uuid;
begin
  if v_actor is null
     or v_active_empresa is null
     or v_invite_target is null
     or p_created_by is distinct from v_actor
     or p_usuario_id is distinct from v_invite_target
     or p_empresa_id is distinct from v_active_empresa then
    raise exception using errcode='42501', message='Contexto de sincronizacao legada do convite invalido';
  end if;

  if not exists (
    select 1
    from public.usuarios u
    where u.id = p_usuario_id
      and u.empresa_id = p_empresa_id
      and u.ativo
      and u.status = 'ativo'
  ) then
    raise exception using errcode='42501', message='Usuario do convite nao esta ativo no tenant validado';
  end if;

  if not exists (
    select 1
    from public.perfis p
    where p.id = p_perfil_id
      and p.ativo
      and ((p.empresa_id is null and p.is_system) or p.empresa_id = p_empresa_id)
  ) then
    raise exception using errcode='42501', message='Perfil do convite nao e compativel com o tenant validado';
  end if;

  insert into public.usuario_perfis(usuario_id, perfil_id, created_by)
  values (p_usuario_id, p_perfil_id, p_created_by)
  on conflict (usuario_id, perfil_id) do nothing;
end
$function$;

revoke all on function private.sync_invite_legacy_profile(uuid,uuid,uuid,uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.sync_invite_legacy_profile(uuid,uuid,uuid,uuid)
  to bpf_admin_writer;

-- A RPC continua owned por bpf_admin_writer e passa a chamar o helper somente depois de
-- validar tenant, perfis e teto de delegacao e depois de promover o usuario pendente.
grant bpf_admin_writer to postgres with inherit false, set true;
grant create on schema private to bpf_admin_writer;
set role bpf_admin_writer;

create or replace function private.admin_usuario_vincular_convite_tenant(
  p_empresa_id uuid,
  p_usuario_id uuid,
  p_unidade_id uuid,
  p_perfil_ids uuid[],
  p_justificativa text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_ator uuid := nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
  v_usuario public.usuarios%rowtype;
  v_membership_id uuid;
  v_perfil_id uuid;
  v_permissoes text[];
begin
  select c.permissoes into v_permissoes
  from private.meu_contexto_empresa(p_empresa_id) c
  where c.usuario_id = v_ator;

  if v_permissoes is null
     or not ('configuracoes.visualizar' = any(v_permissoes))
     or not ('usuarios.gerenciar' = any(v_permissoes))
     or not ('usuarios.convidar' = any(v_permissoes)) then
    raise exception using errcode='42501', message='Sem permissao para convidar usuarios no tenant selecionado';
  end if;

  if length(btrim(coalesce(p_justificativa,''))) < 5 then
    raise exception using errcode='22023', message='Justificativa deve possuir ao menos 5 caracteres';
  end if;
  if coalesce(array_length(p_perfil_ids,1),0) = 0 then
    raise exception using errcode='22023', message='Selecione ao menos um perfil';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_empresa_id::text, 0));
  perform set_config('bpf.active_empresa', p_empresa_id::text, true);
  perform set_config('bpf.invite_target', p_usuario_id::text, true);

  if p_unidade_id is not null and not exists (
    select 1 from public.unidades
    where id=p_unidade_id and empresa_id=p_empresa_id and ativo
  ) then
    raise exception using errcode='22023', message='Unidade invalida, inativa ou fora da empresa';
  end if;

  foreach v_perfil_id in array p_perfil_ids loop
    if not exists (
      select 1 from public.perfis p
      where p.id=v_perfil_id and p.ativo
        and ((p.empresa_id is null and p.is_system) or p.empresa_id=p_empresa_id)
    ) then
      raise exception using errcode='22023', message='Perfil invalido, inativo ou fora da empresa';
    end if;
    if exists (
      select 1
      from public.perfil_permissoes pp
      join public.permissoes pm on pm.id=pp.permissao_id
      where pp.perfil_id=v_perfil_id
        and not (pm.codigo = any(v_permissoes))
    ) then
      raise exception using errcode='42501', message='Nao e permitido delegar um perfil com permissoes superiores as do ator';
    end if;
  end loop;

  select * into v_usuario
  from public.usuarios
  where id=p_usuario_id and empresa_id is null and status='pendente'
  for update;
  if not found then
    raise exception using errcode='P0002', message='Convite pendente nao encontrado';
  end if;

  update public.usuarios
  set empresa_id=p_empresa_id, unidade_id=p_unidade_id, status='ativo', ativo=true, updated_at=now()
  where id=p_usuario_id;

  foreach v_perfil_id in array p_perfil_ids loop
    perform private.sync_invite_legacy_profile(p_usuario_id, v_perfil_id, v_ator, p_empresa_id);
  end loop;

  insert into public.usuario_empresas(usuario_id, empresa_id, unidade_id, status, is_owner, created_by)
  values(p_usuario_id, p_empresa_id, p_unidade_id, 'ativo', false, v_ator)
  on conflict (usuario_id, empresa_id) do update
    set unidade_id=excluded.unidade_id, status='ativo', updated_at=now()
  returning id into v_membership_id;

  insert into public.usuario_empresa_perfis(usuario_empresa_id, perfil_id, created_by)
    select v_membership_id, x, v_ator from unnest(p_perfil_ids) x
    on conflict (usuario_empresa_id, perfil_id) do nothing;

  insert into public.auditoria_eventos(
    empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto
  ) values(
    p_empresa_id,p_unidade_id,v_ator,'usuario',p_usuario_id,'usuario.convidado_vinculado',
    jsonb_build_object('empresa_id',null,'status','pendente'),
    jsonb_build_object('empresa_id',p_empresa_id,'unidade_id',p_unidade_id,'status','ativo','perfil_ids',p_perfil_ids,'membership_id',v_membership_id),
    btrim(p_justificativa),jsonb_build_object('origem','edge_function','modelo','membership')
  );
end
$function$;

reset role;
revoke create on schema private from bpf_admin_writer;
grant bpf_admin_writer to postgres with inherit false, set false;

-- usuario_perfis permanece protegido para acesso direto. A RPC nao depende mais da
-- policy de INSERT para a compatibilidade legada; o helper estrito acima e a unica ponte.
drop policy if exists usuario_perfis_admin_writer_rpc_insert on public.usuario_perfis;
drop policy if exists usuario_perfis_admin_writer_tenant_insert on public.usuario_perfis;

-- Guard rails: helper nao pode ser executado por papeis de cliente.
do $block$
begin
  if has_function_privilege('authenticated','private.sync_invite_legacy_profile(uuid,uuid,uuid,uuid)','EXECUTE')
     or has_function_privilege('anon','private.sync_invite_legacy_profile(uuid,uuid,uuid,uuid)','EXECUTE')
     or has_function_privilege('service_role','private.sync_invite_legacy_profile(uuid,uuid,uuid,uuid)','EXECUTE') then
    raise exception 'Helper de sincronizacao legada nao pode ser executado por papeis de cliente';
  end if;
end
$block$;

reset lock_timeout;
reset statement_timeout;

-- END 20260925125000_bridge_legacy_profile_sync_outside_rls.sql
