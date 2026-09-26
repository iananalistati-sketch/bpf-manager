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
