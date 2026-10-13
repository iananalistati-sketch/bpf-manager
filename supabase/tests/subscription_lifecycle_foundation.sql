begin;

insert into auth.users(id,email,raw_user_meta_data)
values ('bb000000-0000-0000-0000-000000000001','billing-owner@example.test','{"nome":"Billing Owner"}'::jsonb);

insert into public.perfis(id,empresa_id,nome,is_system,ativo)
select 'bb100000-0000-0000-0000-000000000001',null,'Administrador',true,true
where not exists (
  select 1 from public.perfis
  where is_system and empresa_id is null and lower(nome)=lower('Administrador') and ativo
);

set local role service_role;
select * from public.provisionar_trial_server(
  'bb000000-0000-0000-0000-000000000001',
  'Billing Lifecycle Ltda',
  'Billing Lifecycle',
  'Unidade Principal',
  'trial-billing-lifecycle-20261013'
);
reset role;

create temp table qa_subscription as
select sp.empresa_id, ea.id as assinatura_id
from public.saas_provisionamentos sp
join public.empresa_assinaturas ea on ea.empresa_id=sp.empresa_id
where sp.chave_idempotencia='trial-billing-lifecycle-20261013';
grant select on qa_subscription to authenticated, service_role;

-- Confirmacao confiavel de pagamento converte trial -> active, troca o plano e registra o evento.
set local role service_role;
create temp table qa_activation as
select * from public.processar_evento_assinatura_server(
  (select empresa_id from qa_subscription),
  'qa-pay',
  'evt-activation-001',
  'subscription.activated',
  'active',
  'business',
  'cus-qa-001',
  'sub-qa-001',
  'price-business-001',
  now(),
  now()+interval '30 days',
  now(),
  '{"source":"qa"}'::jsonb
);
reset role;

do $block$
declare
  v_empresa uuid := (select empresa_id from qa_subscription);
  v_count integer;
begin
  if not exists (
    select 1
    from public.empresa_assinaturas ea
    join public.planos p on p.id=ea.plano_id
    where ea.empresa_id=v_empresa
      and ea.status='active'
      and p.codigo='business'
      and ea.provedor='qa-pay'
      and ea.provedor_cliente_id='cus-qa-001'
      and ea.provedor_assinatura_id='sub-qa-001'
      and ea.provedor_preco_id='price-business-001'
      and ea.converted_at is not null
      and ea.provedor_ultimo_evento_em is not null
  ) then
    raise exception 'trial was not converted to active Business subscription';
  end if;

  if not exists (
    select 1
    from public.empresa_planos ep
    join public.planos p on p.id=ep.plano_id
    where ep.empresa_id=v_empresa and p.codigo='business' and ep.origem='assinatura'
  ) then
    raise exception 'paid plan assignment was not synchronized';
  end if;

  select count(*) into v_count
  from public.assinatura_eventos ae
  where ae.empresa_id=v_empresa and ae.provedor='qa-pay' and ae.provedor_evento_id='evt-activation-001' and ae.aplicado;
  if v_count <> 1 then raise exception 'activation event history missing'; end if;

  if not exists (select 1 from qa_activation where aplicado and status='active') then
    raise exception 'activation result did not report applied active state';
  end if;
end
$block$;

-- Retry identico e side-effect free.
set local role service_role;
create temp table qa_retry as
select * from public.processar_evento_assinatura_server(
  (select empresa_id from qa_subscription),
  'qa-pay',
  'evt-activation-001',
  'subscription.activated',
  'active',
  'business',
  'cus-qa-001',
  'sub-qa-001',
  'price-business-001',
  (select periodo_inicio from public.empresa_assinaturas where empresa_id=(select empresa_id from qa_subscription)),
  (select periodo_fim from public.empresa_assinaturas where empresa_id=(select empresa_id from qa_subscription)),
  (select ocorrido_em from public.assinatura_eventos where provedor='qa-pay' and provedor_evento_id='evt-activation-001'),
  '{"source":"qa"}'::jsonb
);
reset role;

do $block$
declare v_count integer;
begin
  if not exists (select 1 from qa_retry where not aplicado and status='active') then
    raise exception 'idempotent retry was not reported as already processed';
  end if;
  select count(*) into v_count
  from public.assinatura_eventos
  where provedor='qa-pay' and provedor_evento_id='evt-activation-001';
  if v_count <> 1 then raise exception 'idempotent retry duplicated commercial event'; end if;
end
$block$;

-- A mesma chave do provedor com payload divergente deve falhar fechado.
set local role service_role;
do $block$
begin
  begin
    perform public.processar_evento_assinatura_server(
      (select empresa_id from qa_subscription),
      'qa-pay','evt-activation-001','subscription.activated','past_due',
      null,null,'sub-qa-001',null,null,null,now(),'{"source":"tampered"}'::jsonb
    );
    raise exception 'expected divergent provider event rejection';
  exception when unique_violation then null;
  end;
end
$block$;
reset role;

-- Falha de pagamento entra em read-only e recuperacao posterior restaura acesso normal.
set local role service_role;
select * from public.processar_evento_assinatura_server(
  (select empresa_id from qa_subscription),
  'qa-pay','evt-past-due-001','invoice.payment_failed','past_due',
  null,null,'sub-qa-001',null,null,null,now()+interval '1 minute','{}'::jsonb
);
reset role;

select set_config('request.jwt.claim.sub','bb000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"bb000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $block$
declare v_context record;
begin
  select * into v_context
  from public.meu_workspace_comercial((select empresa_id from qa_subscription));
  if v_context.assinatura_status <> 'past_due' or v_context.modo_acesso <> 'somente_leitura' then
    raise exception 'past_due subscription should be read-only';
  end if;
end
$block$;
reset role;

set local role service_role;
select * from public.processar_evento_assinatura_server(
  (select empresa_id from qa_subscription),
  'qa-pay','evt-recovered-001','invoice.payment_succeeded','active',
  null,null,'sub-qa-001',null,null,null,now()+interval '2 minutes','{}'::jsonb
);
reset role;

set local role authenticated;
do $block$
declare v_context record;
begin
  select * into v_context
  from public.meu_workspace_comercial((select empresa_id from qa_subscription));
  if v_context.assinatura_status <> 'active' or v_context.modo_acesso <> 'normal' then
    raise exception 'recovered active subscription should restore normal access';
  end if;
end
$block$;
reset role;

-- Evento antigo e valido pela matriz nao pode retroceder o estado atual.
set local role service_role;
create temp table qa_stale as
select * from public.processar_evento_assinatura_server(
  (select empresa_id from qa_subscription),
  'qa-pay','evt-stale-001','invoice.payment_failed','past_due',
  null,null,'sub-qa-001',null,null,null,now()-interval '1 hour','{"delayed":true}'::jsonb
);
reset role;

do $block$
begin
  if not exists (select 1 from qa_stale where not aplicado and status='active') then
    raise exception 'stale event should be recorded without changing current state';
  end if;
  if not exists (
    select 1 from public.assinatura_eventos
    where provedor='qa-pay' and provedor_evento_id='evt-stale-001'
      and not aplicado and motivo='evento_fora_de_ordem'
  ) then
    raise exception 'stale event history missing ignored reason';
  end if;
end
$block$;

-- O plano pago so pode ser reduzido se comportar o consumo atual.
insert into public.unidades(empresa_id,nome,ativo)
values ((select empresa_id from qa_subscription),'Unidade Secundaria',true);

set local role service_role;
do $block$
begin
  begin
    perform public.processar_evento_assinatura_server(
      (select empresa_id from qa_subscription),
      'qa-pay','evt-downgrade-001','subscription.plan_changed','active',
      'basic',null,'sub-qa-001','price-basic-001',null,null,now()+interval '3 minutes','{}'::jsonb
    );
    raise exception 'expected incompatible downgrade rejection';
  exception when check_violation then
    if sqlerrm <> 'Plano selecionado nao comporta as unidades ativas atuais' then raise; end if;
  end;
end
$block$;
reset role;

do $block$
begin
  if exists (
    select 1 from public.assinatura_eventos
    where provedor='qa-pay' and provedor_evento_id='evt-downgrade-001'
  ) then raise exception 'rejected downgrade unexpectedly persisted event'; end if;
  if not exists (
    select 1 from public.empresa_assinaturas ea
    join public.planos p on p.id=ea.plano_id
    where ea.empresa_id=(select empresa_id from qa_subscription)
      and ea.status='active' and p.codigo='business'
  ) then raise exception 'rejected downgrade changed subscription state'; end if;
end
$block$;

-- Transicoes sem sentido sao bloqueadas mesmo pelo contrato de backend.
set local role service_role;
do $block$
begin
  begin
    perform public.processar_evento_assinatura_server(
      (select empresa_id from qa_subscription),
      'qa-pay','evt-invalid-transition-001','subscription.invalid','trialing',
      null,null,'sub-qa-001',null,null,null,now()+interval '4 minutes','{}'::jsonb
    );
    raise exception 'expected invalid commercial transition rejection';
  exception when check_violation then
    if sqlerrm not like 'Transicao comercial invalida:%' then raise; end if;
  end;
end
$block$;
reset role;

-- Superficie: somente backend privilegiado executa o processador; tabela de eventos permanece fechada.
do $block$
begin
  if has_function_privilege(
    'authenticated',
    'public.processar_evento_assinatura_server(uuid,text,text,text,text,text,text,text,text,timestamptz,timestamptz,timestamptz,jsonb)',
    'EXECUTE'
  ) then raise exception 'authenticated unexpectedly can process billing events'; end if;

  if has_function_privilege(
    'anon',
    'public.processar_evento_assinatura_server(uuid,text,text,text,text,text,text,text,text,timestamptz,timestamptz,timestamptz,jsonb)',
    'EXECUTE'
  ) then raise exception 'anon unexpectedly can process billing events'; end if;

  if not has_function_privilege(
    'service_role',
    'public.processar_evento_assinatura_server(uuid,text,text,text,text,text,text,text,text,timestamptz,timestamptz,timestamptz,jsonb)',
    'EXECUTE'
  ) then raise exception 'service_role lost billing event processor execute'; end if;

  if has_table_privilege('authenticated','public.assinatura_eventos','SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'authenticated unexpectedly has direct commercial event access';
  end if;
end
$block$;

select 'PASS: subscription lifecycle converts trial safely, enforces idempotency/order/transitions/capacity, toggles read-only state and keeps billing writes server-only' as result;
rollback;
