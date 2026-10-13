-- Marco 1.5 / Trial: provisionamento atomico e idempotente pelo backend.
set lock_timeout = '5s';
set statement_timeout = '60s';

create or replace function public.provisionar_trial_server(
  p_usuario_id uuid,
  p_razao_social text,
  p_nome_fantasia text,
  p_unidade_nome text,
  p_chave_idempotencia text
)
returns table (
  empresa_id uuid,
  unidade_id uuid,
  membership_id uuid,
  assinatura_id uuid,
  trial_fim timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_empresa_id uuid;
  v_unidade_id uuid;
  v_membership_id uuid;
  v_assinatura_id uuid;
  v_trial_inicio timestamptz := now();
  v_trial_fim timestamptz := now() + interval '14 days';
  v_plano_id uuid;
  v_admin_perfil_id uuid;
  v_existing public.saas_provisionamentos%rowtype;
begin
  if p_usuario_id is null
     or length(btrim(coalesce(p_razao_social,''))) < 2
     or length(btrim(coalesce(p_nome_fantasia,''))) < 2
     or length(btrim(coalesce(p_unidade_nome,''))) < 2
     or length(btrim(coalesce(p_chave_idempotencia,''))) < 12 then
    raise exception using errcode='22023', message='Dados invalidos para provisionamento do trial';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_chave_idempotencia,0));

  select * into v_existing
  from public.saas_provisionamentos sp
  where sp.chave_idempotencia=btrim(p_chave_idempotencia)
  for update;

  if found then
    if v_existing.usuario_id <> p_usuario_id or v_existing.tipo <> 'trial' then
      raise exception using errcode='23505', message='Chave de idempotencia ja utilizada';
    end if;
    if v_existing.status='concluido' and v_existing.empresa_id is not null then
      return query
      select e.id, ue.unidade_id, ue.id, ea.id, ea.trial_fim
      from public.empresas e
      join public.usuario_empresas ue on ue.empresa_id=e.id and ue.usuario_id=p_usuario_id
      join public.empresa_assinaturas ea on ea.empresa_id=e.id
      where e.id=v_existing.empresa_id;
      return;
    end if;
    raise exception using errcode='55000', message='Provisionamento anterior nao concluido';
  end if;

  if not exists (select 1 from public.usuarios u where u.id=p_usuario_id) then
    raise exception using errcode='P0002', message='Usuario nao encontrado';
  end if;
  if exists (select 1 from public.usuario_empresas ue where ue.usuario_id=p_usuario_id) then
    raise exception using errcode='23514', message='Usuario ja possui vinculo empresarial';
  end if;

  select p.id into v_plano_id
  from public.planos p
  where p.codigo='basic' and p.ativo;
  if v_plano_id is null then
    raise exception using errcode='55000', message='Plano inicial do trial indisponivel';
  end if;

  select p.id into v_admin_perfil_id
  from public.perfis p
  where p.is_system and p.ativo and p.empresa_id is null and lower(p.nome)=lower('Administrador')
  order by p.id limit 1;
  if v_admin_perfil_id is null then
    raise exception using errcode='55000', message='Perfil Administrador indisponivel';
  end if;

  insert into public.saas_provisionamentos(chave_idempotencia,tipo,usuario_id,status,contexto)
  values(btrim(p_chave_idempotencia),'trial',p_usuario_id,'processando',jsonb_build_object('duracao_dias',14));

  insert into public.empresas(razao_social,nome_fantasia,ativo,created_by)
  values(btrim(p_razao_social),btrim(p_nome_fantasia),true,p_usuario_id)
  returning id into v_empresa_id;

  insert into public.empresa_planos(empresa_id,plano_id,origem,assigned_by)
  values(v_empresa_id,v_plano_id,'trial',p_usuario_id);

  insert into public.empresa_assinaturas(empresa_id,plano_id,status,trial_inicio,trial_fim,metadata)
  values(v_empresa_id,v_plano_id,'trialing',v_trial_inicio,v_trial_fim,
    jsonb_build_object('origem','self_service_trial','duracao_dias',14))
  returning id into v_assinatura_id;

  insert into public.unidades(empresa_id,nome,ativo,created_by)
  values(v_empresa_id,btrim(p_unidade_nome),true,p_usuario_id)
  returning id into v_unidade_id;

  insert into public.usuario_empresas(usuario_id,empresa_id,unidade_id,status,is_owner,created_by)
  values(p_usuario_id,v_empresa_id,v_unidade_id,'ativo',true,p_usuario_id)
  returning id into v_membership_id;

  insert into public.usuario_empresa_perfis(usuario_empresa_id,perfil_id,created_by)
  values(v_membership_id,v_admin_perfil_id,p_usuario_id)
  on conflict (usuario_empresa_id,perfil_id) do nothing;

  update public.usuarios
  set empresa_id=v_empresa_id, unidade_id=v_unidade_id, status='ativo', ativo=true, updated_at=now()
  where id=p_usuario_id;

  insert into public.usuario_perfis(usuario_id,perfil_id,created_by)
  values(p_usuario_id,v_admin_perfil_id,p_usuario_id)
  on conflict (usuario_id,perfil_id) do nothing;

  insert into public.empresa_onboarding(empresa_id,status,etapa_atual,dados)
  values(v_empresa_id,'nao_iniciado','empresa','{}'::jsonb);

  insert into public.auditoria_eventos(
    empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto
  ) values(
    v_empresa_id,v_unidade_id,p_usuario_id,'empresa',v_empresa_id,'workspace.trial_provisionado',null,
    jsonb_build_object('assinatura_id',v_assinatura_id,'membership_id',v_membership_id,'plano_id',v_plano_id,'trial_fim',v_trial_fim,'is_owner',true),
    'Provisionamento inicial do trial',
    jsonb_build_object('origem','server_provisioning','idempotency_key',btrim(p_chave_idempotencia))
  );

  update public.saas_provisionamentos
  set empresa_id=v_empresa_id,status='concluido',completed_at=now(),
      contexto=contexto || jsonb_build_object('assinatura_id',v_assinatura_id,'membership_id',v_membership_id)
  where chave_idempotencia=btrim(p_chave_idempotencia);

  return query select v_empresa_id,v_unidade_id,v_membership_id,v_assinatura_id,v_trial_fim;
end
$function$;

revoke all on function public.provisionar_trial_server(uuid,text,text,text,text) from public, anon, authenticated;
grant execute on function public.provisionar_trial_server(uuid,text,text,text,text) to service_role;

comment on function public.provisionar_trial_server(uuid,text,text,text,text) is
  'Provisiona trial self-service de 14 dias de forma atomica e idempotente; uso exclusivo do backend.';

reset lock_timeout;
reset statement_timeout;
