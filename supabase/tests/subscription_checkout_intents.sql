begin;

insert into auth.users(id,email,raw_user_meta_data) values
  ('bc000000-0000-0000-0000-000000000001','checkout-owner@example.test','{"nome":"Checkout Owner"}'::jsonb),
  ('bc000000-0000-0000-0000-000000000002','checkout-member@example.test','{"nome":"Checkout Member"}'::jsonb);

insert into public.perfis(id,empresa_id,nome,is_system,ativo)
select 'bc100000-0000-0000-0000-000000000001',null,'Administrador',true,true
where not exists (
  select 1 from public.perfis
  where is_system and empresa_id is null and lower(nome)=lower('Administrador') and ativo
);

set local role service_role;
select * from public.provisionar_trial_server(
  'bc000000-0000-0000-0000-000000000001',
  'Checkout Intent Ltda',
  'Checkout Intent',
  'Unidade Principal',
  'trial-checkout-intent-20261013'
);
reset role;

create temp table qa_checkout_empresa as
select empresa_id
from public.saas_provisionamentos
where chave_idempotencia='trial-checkout-intent-20261013';

insert into public.usuario_empresas(usuario_id,empresa_id,status,is_owner,created_by)
select
  'bc000000-0000-0000-0000-000000000002',
  empresa_id,
  'ativo',
  false,
  'bc000000-0000-0000-0000-000000000001'
from qa_checkout_empresa;

update public.usuarios
set empresa_id=(select empresa_id from qa_checkout_empresa),status='ativo',ativo=true
where id='bc000000-0000-0000-0000-000000000002';

create temp table qa_prepare (
  contratacao_id uuid,
  empresa_id uuid,
  assinatura_id uuid,
  plano_id uuid,
  plano_codigo text,
  status text,
  expires_at timestamptz
);
create temp table qa_retry (like qa_prepare);
create temp table qa_checkout (
  contratacao_id uuid,
  empresa_id uuid,
  assinatura_id uuid,
  plano_id uuid,
  status text,
  checkout_url text
);
create temp table qa_checkout_retry (like qa_checkout);

grant select on qa_checkout_empresa to service_role, authenticated;
grant select,insert on qa_prepare,qa_retry,qa_checkout,qa_checkout_retry to service_role;
grant select on qa_prepare,qa_retry,qa_checkout,qa_checkout_retry to authenticated;

-- Owner prepara uma contratacao sem alterar ainda o estado comercial corrente.
set local role service_role;
insert into qa_prepare
select * from public.preparar_contratacao_server(
  'bc000000-0000-0000-0000-000000000001',
  (select empresa_id from qa_checkout_empresa),
  'business',
  'checkout:intent:owner:business:001'
);
reset role;

do $block$
declare v_count integer;
begin
  if not exists (
    select 1 from qa_prepare
    where plano_codigo='business' and status='preparada' and expires_at > now()
  ) then raise exception 'owner checkout intent was not prepared'; end if;

  select count(*) into v_count
  from public.assinatura_contratacoes
  where chave_idempotencia='checkout:intent:owner:business:001';
  if v_count <> 1 then raise exception 'checkout intent was not persisted exactly once'; end if;

  if not exists (
    select 1
    from public.empresa_assinaturas ea
    where ea.empresa_id=(select empresa_id from qa_checkout_empresa)
      and ea.status='trialing'
  ) then raise exception 'preparing checkout unexpectedly changed subscription status'; end if;

  if not exists (
    select 1
    from public.auditoria_eventos ae
    where ae.empresa_id=(select empresa_id from qa_checkout_empresa)
      and ae.acao='assinatura.contratacao_preparada'
      and ae.registro_id=(select contratacao_id from qa_prepare)
  ) then raise exception 'checkout preparation audit missing'; end if;
end
$block$;

-- Retry com a mesma chave e payload retorna a mesma contratacao sem duplicar.
set local role service_role;
insert into qa_retry
select * from public.preparar_contratacao_server(
  'bc000000-0000-0000-0000-000000000001',
  (select empresa_id from qa_checkout_empresa),
  'business',
  'checkout:intent:owner:business:001'
);
reset role;

do $block$
declare v_count integer;
begin
  if (select contratacao_id from qa_retry) is distinct from (select contratacao_id from qa_prepare) then
    raise exception 'idempotent preparation returned another checkout intent';
  end if;

  select count(*) into v_count
  from public.assinatura_contratacoes
  where chave_idempotencia='checkout:intent:owner:business:001';
  if v_count <> 1 then raise exception 'idempotent preparation duplicated checkout intent'; end if;
end
$block$;

-- A chave nao pode ser reaproveitada para outro plano.
set local role service_role;
do $block$
begin
  begin
    perform public.preparar_contratacao_server(
      'bc000000-0000-0000-0000-000000000001',
      (select empresa_id from qa_checkout_empresa),
      'professional',
      'checkout:intent:owner:business:001'
    );
    raise exception 'expected divergent checkout intent rejection';
  exception when unique_violation then null;
  end;
end
$block$;
reset role;

-- Membership ativo sem ownership nao pode iniciar cobranca.
set local role service_role;
do $block$
begin
  begin
    perform public.preparar_contratacao_server(
      'bc000000-0000-0000-0000-000000000002',
      (select empresa_id from qa_checkout_empresa),
      'professional',
      'checkout:intent:member:professional:001'
    );
    raise exception 'expected non-owner checkout rejection';
  exception when insufficient_privilege then null;
  end;
end
$block$;
reset role;

-- Adapter confiavel anexa checkout HTTPS, mas nao ativa a assinatura.
set local role service_role;
insert into qa_checkout
select * from public.registrar_checkout_assinatura_server(
  (select contratacao_id from qa_prepare),
  'qa-pay',
  'checkout-qa-001',
  'https://pay.example.test/checkout/qa-001',
  '{"adapter":"qa"}'::jsonb
);
reset role;

do $block$
begin
  if not exists (
    select 1 from qa_checkout
    where status='checkout_criado'
      and checkout_url='https://pay.example.test/checkout/qa-001'
  ) then raise exception 'checkout adapter result invalid'; end if;

  if not exists (
    select 1 from public.assinatura_contratacoes
    where id=(select contratacao_id from qa_prepare)
      and status='checkout_criado'
      and provedor='qa-pay'
      and provedor_checkout_id='checkout-qa-001'
      and checkout_url='https://pay.example.test/checkout/qa-001'
  ) then raise exception 'checkout provider data was not persisted'; end if;

  if not exists (
    select 1 from public.empresa_assinaturas
    where empresa_id=(select empresa_id from qa_checkout_empresa)
      and status='trialing'
  ) then raise exception 'checkout registration incorrectly activated subscription'; end if;
end
$block$;

-- Registro repetido e identico e idempotente; dados divergentes falham fechado.
set local role service_role;
insert into qa_checkout_retry
select * from public.registrar_checkout_assinatura_server(
  (select contratacao_id from qa_prepare),
  'qa-pay',
  'checkout-qa-001',
  'https://pay.example.test/checkout/qa-001',
  '{"adapter":"qa"}'::jsonb
);

do $block$
begin
  begin
    perform public.registrar_checkout_assinatura_server(
      (select contratacao_id from qa_prepare),
      'qa-pay',
      'checkout-qa-002',
      'https://pay.example.test/checkout/qa-002',
      '{"adapter":"qa"}'::jsonb
    );
    raise exception 'expected divergent checkout registration rejection';
  exception when unique_violation then null;
  end;
end
$block$;
reset role;

do $block$
begin
  if (select contratacao_id from qa_checkout_retry) is distinct from (select contratacao_id from qa_checkout) then
    raise exception 'idempotent checkout registration returned another intent';
  end if;
end
$block$;

-- O plano alvo precisa comportar o consumo atual, independentemente do plano hoje atribuido.
update public.empresa_planos ep
set plano_id=p.id,origem='manual',updated_at=now()
from public.planos p
where ep.empresa_id=(select empresa_id from qa_checkout_empresa)
  and p.codigo='business';

insert into public.unidades(empresa_id,nome,ativo)
values ((select empresa_id from qa_checkout_empresa),'Unidade Secundaria',true);

set local role service_role;
do $block$
begin
  begin
    perform public.preparar_contratacao_server(
      'bc000000-0000-0000-0000-000000000001',
      (select empresa_id from qa_checkout_empresa),
      'basic',
      'checkout:intent:owner:basic:overflow'
    );
    raise exception 'expected incompatible target plan rejection';
  exception when check_violation then
    if sqlerrm <> 'Plano selecionado nao comporta as unidades ativas atuais' then raise; end if;
  end;
end
$block$;
reset role;

-- Fronteira de privilegios: browser nao prepara nem registra checkout e nao le a tabela diretamente.
do $block$
begin
  if has_function_privilege(
    'authenticated',
    'public.preparar_contratacao_server(uuid,uuid,text,text)',
    'EXECUTE'
  ) then raise exception 'authenticated unexpectedly can prepare checkout directly'; end if;

  if has_function_privilege(
    'anon',
    'public.preparar_contratacao_server(uuid,uuid,text,text)',
    'EXECUTE'
  ) then raise exception 'anon unexpectedly can prepare checkout directly'; end if;

  if not has_function_privilege(
    'service_role',
    'public.preparar_contratacao_server(uuid,uuid,text,text)',
    'EXECUTE'
  ) then raise exception 'service_role lost checkout preparation execute'; end if;

  if has_function_privilege(
    'authenticated',
    'public.registrar_checkout_assinatura_server(uuid,text,text,text,jsonb)',
    'EXECUTE'
  ) then raise exception 'authenticated unexpectedly can register provider checkout'; end if;

  if has_table_privilege('authenticated','public.assinatura_contratacoes','SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'authenticated unexpectedly has direct checkout intent access'; end if;
  if has_table_privilege('anon','public.assinatura_contratacoes','SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'anon unexpectedly has direct checkout intent access'; end if;
  if has_table_privilege('service_role','public.assinatura_contratacoes','SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'service_role unexpectedly has direct checkout intent access outside server RPCs'; end if;
end
$block$;

select 'PASS: checkout intents are owner-only, idempotent, capacity-aware, provider-neutral, server-only and never activate subscriptions before trusted payment events' as result;
rollback;
