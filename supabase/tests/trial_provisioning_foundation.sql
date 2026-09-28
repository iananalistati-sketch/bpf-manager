begin;

-- Fixture dedicada ao provisionamento SaaS.
insert into auth.users(id,email,raw_user_meta_data) values
  ('aa000000-0000-0000-0000-000000000001','trial-owner@example.test','{"nome":"Trial Owner"}'::jsonb),
  ('aa000000-0000-0000-0000-000000000002','existing-member@example.test','{"nome":"Existing Member"}'::jsonb);

insert into public.perfis(id,empresa_id,nome,is_system,ativo)
select 'ab000000-0000-0000-0000-000000000001',null,'Administrador',true,true
where not exists (
  select 1 from public.perfis where is_system and empresa_id is null and lower(nome)=lower('Administrador') and ativo
);

-- Um usuario ja vinculado nao pode abrir novo trial pelo fluxo inicial.
insert into public.empresas(id,razao_social,nome_fantasia)
values('ac000000-0000-0000-0000-000000000001','Empresa Existente','Existente');
insert into public.usuario_empresas(usuario_id,empresa_id,status,is_owner)
values('aa000000-0000-0000-0000-000000000002','ac000000-0000-0000-0000-000000000001','ativo',false);

set local role service_role;

select * from public.provisionar_trial_server(
  'aa000000-0000-0000-0000-000000000001',
  'Fabrica Trial Ltda',
  'Fabrica Trial',
  'Unidade Principal',
  'trial-aa000001-20260928'
);

reset role;

do $block$
declare
  v_empresa uuid;
  v_unidade uuid;
  v_membership uuid;
  v_assinatura uuid;
  v_trial_inicio timestamptz;
  v_trial_fim timestamptz;
  v_count integer;
begin
  select sp.empresa_id into v_empresa
  from public.saas_provisionamentos sp
  where sp.chave_idempotencia='trial-aa000001-20260928'
    and sp.tipo='trial' and sp.status='concluido';
  if v_empresa is null then raise exception 'trial provisioning was not completed'; end if;

  select ue.id,ue.unidade_id into v_membership,v_unidade
  from public.usuario_empresas ue
  where ue.usuario_id='aa000000-0000-0000-0000-000000000001'
    and ue.empresa_id=v_empresa
    and ue.status='ativo'
    and ue.is_owner;
  if v_membership is null or v_unidade is null then raise exception 'owner membership missing'; end if;

  select ea.id,ea.trial_inicio,ea.trial_fim into v_assinatura,v_trial_inicio,v_trial_fim
  from public.empresa_assinaturas ea
  where ea.empresa_id=v_empresa and ea.status='trialing';
  if v_assinatura is null then raise exception 'trial subscription missing'; end if;
  if v_trial_fim < v_trial_inicio + interval '13 days 23 hours'
     or v_trial_fim > v_trial_inicio + interval '14 days 1 hour' then
    raise exception 'trial duration is not approximately 14 days';
  end if;

  select count(*) into v_count
  from public.empresa_planos ep
  join public.planos p on p.id=ep.plano_id
  where ep.empresa_id=v_empresa and ep.origem='trial' and p.codigo='basic';
  if v_count <> 1 then raise exception 'trial plan assignment missing'; end if;

  select count(*) into v_count
  from public.usuario_empresa_perfis uep
  join public.perfis p on p.id=uep.perfil_id
  where uep.usuario_empresa_id=v_membership
    and p.is_system and lower(p.nome)=lower('Administrador');
  if v_count <> 1 then raise exception 'owner admin membership profile missing'; end if;

  select count(*) into v_count
  from public.usuario_perfis up
  join public.perfis p on p.id=up.perfil_id
  where up.usuario_id='aa000000-0000-0000-0000-000000000001'
    and p.is_system and lower(p.nome)=lower('Administrador');
  if v_count <> 1 then raise exception 'legacy admin profile compatibility missing'; end if;

  if not exists (
    select 1 from public.usuarios u
    where u.id='aa000000-0000-0000-0000-000000000001'
      and u.empresa_id=v_empresa and u.unidade_id=v_unidade and u.status='ativo' and u.ativo
  ) then raise exception 'legacy primary tenant compatibility missing'; end if;

  if not exists (
    select 1 from public.empresa_onboarding eo
    where eo.empresa_id=v_empresa and eo.status='nao_iniciado' and eo.etapa_atual='empresa'
  ) then raise exception 'onboarding foundation missing'; end if;

  if not exists (
    select 1 from public.auditoria_eventos ae
    where ae.empresa_id=v_empresa
      and ae.registro_id=v_empresa
      and ae.acao='workspace.trial_provisionado'
  ) then raise exception 'trial provisioning audit missing'; end if;
end
$block$;

-- Repetir exatamente a mesma requisicao deve retornar o mesmo workspace, sem duplicar estado.
set local role service_role;
select * from public.provisionar_trial_server(
  'aa000000-0000-0000-0000-000000000001',
  'Fabrica Trial Ltda',
  'Fabrica Trial',
  'Unidade Principal',
  'trial-aa000001-20260928'
);
reset role;

do $block$
declare v_count integer;
begin
  select count(*) into v_count from public.saas_provisionamentos
  where chave_idempotencia='trial-aa000001-20260928';
  if v_count <> 1 then raise exception 'idempotency record duplicated'; end if;

  select count(*) into v_count
  from public.usuario_empresas
  where usuario_id='aa000000-0000-0000-0000-000000000001';
  if v_count <> 1 then raise exception 'idempotent retry duplicated membership'; end if;
end
$block$;

-- Usuario previamente vinculado nao pode usar o fluxo de trial inicial.
set local role service_role;
do $block$
begin
  begin
    perform public.provisionar_trial_server(
      'aa000000-0000-0000-0000-000000000002',
      'Outra Empresa Ltda','Outra Empresa','Unidade','trial-aa000002-20260928'
    );
    raise exception 'expected existing membership trial rejection';
  exception when check_violation then null;
  end;
end
$block$;
reset role;

-- Superficie publica fechada.
do $block$
begin
  if has_function_privilege('authenticated','public.provisionar_trial_server(uuid,text,text,text,text)','EXECUTE') then
    raise exception 'authenticated unexpectedly can provision trial';
  end if;
  if has_function_privilege('anon','public.provisionar_trial_server(uuid,text,text,text,text)','EXECUTE') then
    raise exception 'anon unexpectedly can provision trial';
  end if;
  if not has_function_privilege('service_role','public.provisionar_trial_server(uuid,text,text,text,text)','EXECUTE') then
    raise exception 'service_role lost provisioning execute';
  end if;
end
$block$;

select 'PASS: trial provisioning creates isolated owner workspace, Basic trial plan, 14-day subscription, onboarding and audit with idempotent retry' as result;
rollback;
