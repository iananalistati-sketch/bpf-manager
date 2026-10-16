begin;

insert into auth.users(id,email,raw_user_meta_data) values
  ('af000000-0000-0000-0000-000000000001','onboarding-owner@example.test','{"nome":"Onboarding Owner"}'::jsonb),
  ('af000000-0000-0000-0000-000000000002','onboarding-member@example.test','{"nome":"Onboarding Member"}'::jsonb);

insert into public.perfis(id,empresa_id,nome,is_system,ativo)
select 'af100000-0000-0000-0000-000000000001',null,'Administrador',true,true
where not exists (
  select 1 from public.perfis where is_system and empresa_id is null and lower(nome)=lower('Administrador') and ativo
);

set local role service_role;
select * from public.provisionar_trial_server(
  'af000000-0000-0000-0000-000000000001',
  'Onboarding QA Ltda',
  'Onboarding QA',
  'Unidade Principal',
  'trial-onboarding-owner-20261013'
);
reset role;

create temp table qa_onboarding_empresa as
select empresa_id
from public.saas_provisionamentos
where chave_idempotencia='trial-onboarding-owner-20261013';
grant select on qa_onboarding_empresa to authenticated;

insert into public.usuario_empresas(usuario_id,empresa_id,status,is_owner)
select 'af000000-0000-0000-0000-000000000002',empresa_id,'ativo',false
from qa_onboarding_empresa;

update public.usuarios
set empresa_id=(select empresa_id from qa_onboarding_empresa),
    status='ativo',
    ativo=true
where id='af000000-0000-0000-0000-000000000002';

-- Owner pode avançar e concluir. O segundo update deve preservar os dados do primeiro.
select set_config('request.jwt.claim.sub','af000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"af000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;

select * from public.atualizar_meu_onboarding(
  (select empresa_id from qa_onboarding_empresa),
  'responsavel',
  '{"responsavel_tecnico":"Dra. QA"}'::jsonb,
  false
);

select * from public.atualizar_meu_onboarding(
  (select empresa_id from qa_onboarding_empresa),
  'concluido',
  '{"tipo_operacao":"fabricacao","setores":["Recebimento","Producao"]}'::jsonb,
  true
);

reset role;

do $block$
declare
  v_empresa uuid := (select empresa_id from qa_onboarding_empresa);
  v_count integer;
begin
  if not exists (
    select 1 from public.empresa_onboarding eo
    where eo.empresa_id=v_empresa
      and eo.status='concluido'
      and eo.etapa_atual='concluido'
      and eo.started_at is not null
      and eo.completed_at is not null
      and eo.dados->>'responsavel_tecnico'='Dra. QA'
      and eo.dados->>'tipo_operacao'='fabricacao'
      and jsonb_array_length(eo.dados->'setores')=2
  ) then
    raise exception 'owner onboarding was not persisted/merged correctly';
  end if;

  select count(*) into v_count
  from public.auditoria_eventos ae
  where ae.empresa_id=v_empresa
    and ae.acao in ('workspace.onboarding_atualizado','workspace.onboarding_concluido');
  if v_count <> 2 then raise exception 'onboarding audit trail incomplete'; end if;
end
$block$;

-- Payload fora do contrato é rejeitado no backend antes de qualquer escrita.
select set_config('request.jwt.claim.sub','af000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"af000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $block$
begin
  begin
    perform public.atualizar_meu_onboarding(
      (select empresa_id from qa_onboarding_empresa),
      'estrutura',
      '{"campo_injetado":"nao permitido"}'::jsonb,
      false
    );
    raise exception 'expected unsupported onboarding field rejection';
  exception when invalid_parameter_value then null;
  end;
end
$block$;
reset role;

-- Membro não-owner não pode alterar o onboarding.
select set_config('request.jwt.claim.sub','af000000-0000-0000-0000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"af000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $block$
begin
  begin
    perform public.atualizar_meu_onboarding(
      (select empresa_id from qa_onboarding_empresa),
      'estrutura',
      '{"setores":["Fraude"]}'::jsonb,
      false
    );
    raise exception 'expected non-owner onboarding rejection';
  exception when insufficient_privilege then null;
  end;
end
$block$;
reset role;

-- Trial expirado permanece somente leitura, inclusive para o owner.
update public.empresa_assinaturas
set trial_inicio=now()-interval '15 days',
    trial_fim=now()-interval '1 day'
where empresa_id=(select empresa_id from qa_onboarding_empresa);

select set_config('request.jwt.claim.sub','af000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"af000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $block$
begin
  begin
    perform public.atualizar_meu_onboarding(
      (select empresa_id from qa_onboarding_empresa),
      'estrutura',
      '{"setores":["Nao deve gravar"]}'::jsonb,
      false
    );
    raise exception 'expected expired trial onboarding rejection';
  exception when insufficient_privilege then null;
  end;
end
$block$;
reset role;

do $block$
begin
  if has_function_privilege('anon','public.atualizar_meu_onboarding(uuid,text,jsonb,boolean)','EXECUTE') then
    raise exception 'anon unexpectedly can mutate onboarding';
  end if;
  if has_function_privilege('service_role','public.atualizar_meu_onboarding(uuid,text,jsonb,boolean)','EXECUTE') then
    raise exception 'service_role unexpectedly has explicit onboarding execute';
  end if;
  if not has_function_privilege('authenticated','public.atualizar_meu_onboarding(uuid,text,jsonb,boolean)','EXECUTE') then
    raise exception 'authenticated lost onboarding execute';
  end if;
end
$block$;

select 'PASS: owner onboarding merges data, audits progress/conclusion, rejects non-owner mutation and respects expired-trial read-only mode' as result;
rollback;
