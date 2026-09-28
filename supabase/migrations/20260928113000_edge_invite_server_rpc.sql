-- Convite tenant-aware executado exclusivamente pela Edge Function.
-- A Edge valida o JWT do ator e esta RPC revalida tenant/RBAC no banco antes da mutacao atomica.
-- SECURITY INVOKER: a chamada ocorre como service_role; authenticated/anon nao possuem EXECUTE.
set lock_timeout = '5s';
set statement_timeout = '60s';

create or replace function public.admin_usuario_vincular_convite_server(
  p_ator_id uuid,
  p_empresa_id uuid,
  p_usuario_id uuid,
  p_unidade_id uuid,
  p_perfil_ids uuid[],
  p_justificativa text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_membership_id uuid;
  v_perfil_id uuid;
  v_permissoes text[];
begin
  if p_ator_id is null or p_empresa_id is null or p_usuario_id is null then
    raise exception using errcode='22023', message='Parametros obrigatorios ausentes';
  end if;
  if length(btrim(coalesce(p_justificativa,''))) < 5 then
    raise exception using errcode='22023', message='Justificativa deve possuir ao menos 5 caracteres';
  end if;
  if coalesce(array_length(p_perfil_ids,1),0) = 0 then
    raise exception using errcode='22023', message='Selecione ao menos um perfil';
  end if;

  -- O ator precisa permanecer ativo globalmente e no tenant informado.
  if not exists (
    select 1
    from public.usuarios u
    join public.usuario_empresas ue
      on ue.usuario_id=u.id
     and ue.empresa_id=p_empresa_id
     and ue.status='ativo'
    where u.id=p_ator_id and u.ativo and u.status='ativo'
  ) then
    raise exception using errcode='42501', message='Ator sem membership ativo no tenant selecionado';
  end if;

  select coalesce(array_agg(distinct pm.codigo), array[]::text[])
    into v_permissoes
  from public.usuario_empresas ue
  join public.usuario_empresa_perfis uep on uep.usuario_empresa_id=ue.id
  join public.perfis p on p.id=uep.perfil_id
    and p.ativo
    and ((p.empresa_id is null and p.is_system) or p.empresa_id=p_empresa_id)
  join public.perfil_permissoes pp on pp.perfil_id=p.id
  join public.permissoes pm on pm.id=pp.permissao_id
  where ue.usuario_id=p_ator_id
    and ue.empresa_id=p_empresa_id
    and ue.status='ativo';

  if not ('configuracoes.visualizar'=any(v_permissoes))
     or not ('usuarios.gerenciar'=any(v_permissoes))
     or not ('usuarios.convidar'=any(v_permissoes)) then
    raise exception using errcode='42501', message='Sem permissao para convidar usuarios no tenant selecionado';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_empresa_id::text,0));

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
        and not (pm.codigo=any(v_permissoes))
    ) then
      raise exception using errcode='42501', message='Nao e permitido delegar um perfil com permissoes superiores as do ator';
    end if;
  end loop;

  perform 1
  from public.usuarios
  where id=p_usuario_id and empresa_id is null and status='pendente'
  for update;
  if not found then
    raise exception using errcode='P0002', message='Convite pendente nao encontrado';
  end if;

  update public.usuarios
  set empresa_id=p_empresa_id,
      unidade_id=p_unidade_id,
      status='ativo',
      ativo=true,
      updated_at=now()
  where id=p_usuario_id;

  insert into public.usuario_perfis(usuario_id,perfil_id,created_by)
  select p_usuario_id,x,p_ator_id from unnest(p_perfil_ids) x
  on conflict (usuario_id,perfil_id) do nothing;

  insert into public.usuario_empresas(usuario_id,empresa_id,unidade_id,status,is_owner,created_by)
  values(p_usuario_id,p_empresa_id,p_unidade_id,'ativo',false,p_ator_id)
  on conflict (usuario_id,empresa_id) do update
    set unidade_id=excluded.unidade_id,
        status='ativo',
        updated_at=now()
  returning id into v_membership_id;

  insert into public.usuario_empresa_perfis(usuario_empresa_id,perfil_id,created_by)
  select v_membership_id,x,p_ator_id from unnest(p_perfil_ids) x
  on conflict (usuario_empresa_id,perfil_id) do nothing;

  insert into public.auditoria_eventos(
    empresa_id,unidade_id,ator_id,entidade,registro_id,acao,
    antes,depois,justificativa,contexto
  ) values (
    p_empresa_id,p_unidade_id,p_ator_id,'usuario',p_usuario_id,'usuario.convidado_vinculado',
    jsonb_build_object('empresa_id',null,'status','pendente'),
    jsonb_build_object(
      'empresa_id',p_empresa_id,
      'unidade_id',p_unidade_id,
      'status','ativo',
      'perfil_ids',p_perfil_ids,
      'membership_id',v_membership_id
    ),
    btrim(p_justificativa),
    jsonb_build_object('origem','edge_function','modelo','membership','executor','service_role')
  );
end
$function$;

revoke all on function public.admin_usuario_vincular_convite_server(uuid,uuid,uuid,uuid,uuid[],text)
  from public, anon, authenticated;
grant execute on function public.admin_usuario_vincular_convite_server(uuid,uuid,uuid,uuid,uuid[],text)
  to service_role;

-- O caminho antigo deixa de ser uma superficie autenticada depois da migracao.
do $block$
begin
  if to_regprocedure('public.admin_usuario_vincular_convite_tenant(uuid,uuid,uuid,uuid[],text)') is not null then
    revoke execute on function public.admin_usuario_vincular_convite_tenant(uuid,uuid,uuid,uuid[],text) from authenticated;
  end if;
  if to_regprocedure('private.admin_usuario_vincular_convite_tenant(uuid,uuid,uuid,uuid[],text)') is not null then
    revoke execute on function private.admin_usuario_vincular_convite_tenant(uuid,uuid,uuid,uuid[],text) from authenticated;
  end if;
end
$block$;

comment on function public.admin_usuario_vincular_convite_server(uuid,uuid,uuid,uuid,uuid[],text) is
  'RPC atomica de convite tenant-aware, exclusiva da Edge Function via service_role e com RBAC revalidado no banco.';

reset lock_timeout;
reset statement_timeout;
