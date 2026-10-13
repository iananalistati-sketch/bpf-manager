-- Marco 1.5 / Onboarding: mutacao tenant-aware do onboarding inicial do owner.
set lock_timeout = '5s';
set statement_timeout = '60s';

create or replace function public.atualizar_meu_onboarding(
  p_empresa_id uuid,
  p_etapa_atual text,
  p_dados jsonb,
  p_concluir boolean default false
)
returns table (
  empresa_id uuid,
  status text,
  etapa_atual text,
  dados jsonb,
  started_at timestamptz,
  completed_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_subject uuid := private.request_jwt_subject();
  v_before public.empresa_onboarding%rowtype;
  v_after public.empresa_onboarding%rowtype;
  v_etapa text := btrim(coalesce(p_etapa_atual, ''));
begin
  if v_subject is null then
    raise exception using errcode='42501', message='Sessao invalida para atualizar onboarding';
  end if;

  if v_etapa not in ('empresa','responsavel','operacao','estrutura','concluido') then
    raise exception using errcode='22023', message='Etapa de onboarding invalida';
  end if;

  if p_dados is null or jsonb_typeof(p_dados) <> 'object' then
    raise exception using errcode='22023', message='Dados de onboarding devem ser um objeto JSON';
  end if;

  if not exists (
    select 1
    from public.usuarios u
    join public.usuario_empresas ue on ue.usuario_id=u.id
    where u.id=v_subject
      and u.ativo
      and u.status='ativo'
      and ue.empresa_id=p_empresa_id
      and ue.status='ativo'
      and ue.is_owner
  ) then
    raise exception using errcode='42501', message='Somente o owner ativo pode concluir o onboarding deste workspace';
  end if;

  select * into v_before
  from public.empresa_onboarding eo
  where eo.empresa_id=p_empresa_id
  for update;

  if not found then
    raise exception using errcode='P0002', message='Onboarding nao encontrado para o workspace';
  end if;

  update public.empresa_onboarding eo
  set status = case when p_concluir then 'concluido' else 'em_andamento' end,
      etapa_atual = case when p_concluir then 'concluido' else v_etapa end,
      dados = eo.dados || p_dados,
      started_at = coalesce(eo.started_at, now()),
      completed_at = case when p_concluir then coalesce(eo.completed_at, now()) else null end,
      updated_at = now()
  where eo.empresa_id=p_empresa_id
  returning eo.* into v_after;

  insert into public.auditoria_eventos(
    empresa_id, unidade_id, ator_id, entidade, registro_id, acao,
    antes, depois, justificativa, contexto
  )
  select
    p_empresa_id,
    ue.unidade_id,
    v_subject,
    'empresa',
    p_empresa_id,
    case when p_concluir then 'workspace.onboarding_concluido' else 'workspace.onboarding_atualizado' end,
    jsonb_build_object('status',v_before.status,'etapa_atual',v_before.etapa_atual,'dados',v_before.dados),
    jsonb_build_object('status',v_after.status,'etapa_atual',v_after.etapa_atual,'dados',v_after.dados),
    case when p_concluir then 'Conclusao do onboarding inicial' else 'Atualizacao do onboarding inicial' end,
    jsonb_build_object('origem','authenticated_rpc','is_owner',true)
  from public.usuario_empresas ue
  where ue.usuario_id=v_subject and ue.empresa_id=p_empresa_id;

  return query
  select v_after.empresa_id, v_after.status, v_after.etapa_atual, v_after.dados, v_after.started_at, v_after.completed_at;
end
$function$;

revoke all on function public.atualizar_meu_onboarding(uuid,text,jsonb,boolean) from public, anon, service_role;
grant execute on function public.atualizar_meu_onboarding(uuid,text,jsonb,boolean) to authenticated;

comment on function public.atualizar_meu_onboarding(uuid,text,jsonb,boolean) is
  'Atualiza/conclui o onboarding somente para o owner ativo do tenant autenticado, com merge de dados e auditoria.';

reset lock_timeout;
reset statement_timeout;
