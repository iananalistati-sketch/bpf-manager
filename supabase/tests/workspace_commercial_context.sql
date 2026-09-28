begin;

insert into auth.users(id,email,raw_user_meta_data) values
  ('ad000000-0000-0000-0000-000000000001','commercial-owner@example.test','{"nome":"Commercial Owner"}'::jsonb),
  ('ad000000-0000-0000-0000-000000000002','commercial-foreign@example.test','{"nome":"Commercial Foreign"}'::jsonb);

insert into public.perfis(id,empresa_id,nome,is_system,ativo)
select 'ae000000-0000-0000-0000-000000000001',null,'Administrador',true,true
where not exists (
  select 1 from public.perfis where is_system and empresa_id is null and lower(nome)=lower('Administrador') and ativo
);

set local role service_role;
select * from public.provisionar_trial_server(
  'ad000000-0000-0000-0000-000000000001',
  'Workspace Comercial Ltda','Workspace Comercial','Unidade Principal','trial-ad000001-20260928'
);
reset role;

create temp table qa_commercial_empresa as
select empresa_id from public.saas_provisionamentos where chave_idempotencia='trial-ad000001-20260928';
grant select on qa_commercial_empresa to authenticated;

select set_config('request.jwt.claim.sub','ad000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"ad000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;

do $block$
declare
  v_empresa uuid := (select empresa_id from qa_commercial_empresa);
  v_context record;
begin
  select * into v_context from public.meu_workspace_comercial(v_empresa);
  if v_context.assinatura_status <> 'trialing' then raise exception 'trial status not exposed'; end if;
  if v_context.plano_codigo <> 'basic' then raise exception 'trial plan not exposed'; end if;
  if v_context.trial_expirado then raise exception 'new trial unexpectedly expired'; end if;
  if v_context.dias_trial_restantes < 13 or v_context.dias_trial_restantes > 14 then raise exception 'trial remaining days invalid'; end if;
  if v_context.modo_acesso <> 'normal' then raise exception 'active trial should have normal access'; end if;
  if v_context.onboarding_status <> 'nao_iniciado' or v_context.onboarding_etapa <> 'empresa' then
    raise exception 'onboarding context invalid';
  end if;
end
$block$;

-- Tenant adulterado deve ser rejeitado.
do $block$
begin
  begin
    perform public.meu_workspace_comercial('ac000000-0000-0000-0000-000000000099');
    raise exception 'expected commercial tenant rejection';
  exception when insufficient_privilege then null;
  end;
end
$block$;

reset role;

-- Expiracao nao apaga workspace: simula um trial de 14 dias já encerrado,
-- preservando a invariavel trial_fim > trial_inicio do dominio.
update public.empresa_assinaturas
set trial_inicio=now()-interval '15 days',
    trial_fim=now()-interval '1 day'
where empresa_id=(select empresa_id from qa_commercial_empresa);

set local role authenticated;
do $block$
declare
  v_empresa uuid := (select empresa_id from qa_commercial_empresa);
  v_context record;
begin
  select * into v_context from public.meu_workspace_comercial(v_empresa);
  if not v_context.trial_expirado then raise exception 'expired trial was not detected'; end if;
  if v_context.dias_trial_restantes <> 0 then raise exception 'expired trial should have zero remaining days'; end if;
  if v_context.modo_acesso <> 'somente_leitura' then raise exception 'expired trial should be read-only'; end if;
end
$block$;
reset role;

-- Fronteira: somente authenticated pode consultar o proprio contexto.
do $block$
begin
  if not has_function_privilege('authenticated','public.meu_workspace_comercial(uuid)','EXECUTE') then
    raise exception 'authenticated lost commercial context execute';
  end if;
  if has_function_privilege('anon','public.meu_workspace_comercial(uuid)','EXECUTE') then
    raise exception 'anon unexpectedly can read commercial context';
  end if;
end
$block$;

select 'PASS: commercial workspace context exposes plan/trial/onboarding, isolates tenant and turns expired trial read-only without deleting data' as result;
rollback;
