begin;

insert into public.empresas(id, razao_social, nome_fantasia) values
  ('c1000000-0000-0000-0000-000000000001', 'Empresa Basic', 'Tenant Basic'),
  ('c1000000-0000-0000-0000-000000000002', 'Empresa Business', 'Tenant Business'),
  ('c1000000-0000-0000-0000-000000000003', 'Empresa Sem Plano', 'Tenant Livre');

insert into auth.users(id, email) values
  ('c3000000-0000-0000-0000-000000000001', 'basic-owner@example.test'),
  ('c3000000-0000-0000-0000-000000000002', 'business-owner@example.test'),
  ('c3000000-0000-0000-0000-000000000003', 'free-owner@example.test');

update public.usuarios set empresa_id='c1000000-0000-0000-0000-000000000001', status='ativo', ativo=true
where id='c3000000-0000-0000-0000-000000000001';
update public.usuarios set empresa_id='c1000000-0000-0000-0000-000000000002', status='ativo', ativo=true
where id='c3000000-0000-0000-0000-000000000002';
update public.usuarios set empresa_id='c1000000-0000-0000-0000-000000000003', status='ativo', ativo=true
where id='c3000000-0000-0000-0000-000000000003';

insert into public.usuario_empresas(id, usuario_id, empresa_id, status, is_owner) values
  ('c6000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'ativo', true),
  ('c6000000-0000-0000-0000-000000000002', 'c3000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000002', 'ativo', true),
  ('c6000000-0000-0000-0000-000000000003', 'c3000000-0000-0000-0000-000000000003', 'c1000000-0000-0000-0000-000000000003', 'ativo', true);

insert into public.empresa_planos(empresa_id, plano_id, origem)
select 'c1000000-0000-0000-0000-000000000001', id, 'manual' from public.planos where codigo='basic';
insert into public.empresa_planos(empresa_id, plano_id, origem)
select 'c1000000-0000-0000-0000-000000000002', id, 'manual' from public.planos where codigo='business';

-- Seeds aprovados: limites quantitativos sem hardcode por nome comercial.
do $block$
declare
  v_basic_users bigint;
  v_basic_units bigint;
  v_prof_users bigint;
  v_business_units bigint;
  v_enterprise_entitlements int;
begin
  select pe.valor_inteiro into v_basic_users
  from public.plano_entitlements pe join public.planos p on p.id=pe.plano_id
  where p.codigo='basic' and pe.chave='usuarios_ativos.max';
  select pe.valor_inteiro into v_basic_units
  from public.plano_entitlements pe join public.planos p on p.id=pe.plano_id
  where p.codigo='basic' and pe.chave='unidades.max';
  select pe.valor_inteiro into v_prof_users
  from public.plano_entitlements pe join public.planos p on p.id=pe.plano_id
  where p.codigo='professional' and pe.chave='usuarios_ativos.max';
  select pe.valor_inteiro into v_business_units
  from public.plano_entitlements pe join public.planos p on p.id=pe.plano_id
  where p.codigo='business' and pe.chave='unidades.max';
  select count(*) into v_enterprise_entitlements
  from public.plano_entitlements pe join public.planos p on p.id=pe.plano_id
  where p.codigo='enterprise';

  if v_basic_users <> 10 or v_basic_units <> 1 or v_prof_users <> 30 or v_business_units <> 10 then
    raise exception 'plan seed limits differ from approved architecture';
  end if;
  if v_enterprise_entitlements <> 0 then
    raise exception 'enterprise must remain configurable instead of receiving invented fixed limits';
  end if;
end
$block$;

-- Valor tipado inconsistente deve ser rejeitado.
do $block$
declare v_plan uuid;
begin
  select id into v_plan from public.planos where codigo='basic';
  begin
    insert into public.plano_entitlements(plano_id,chave,tipo,valor_inteiro)
    values(v_plan,'recurso.invalido','booleano',1);
    raise exception 'expected typed entitlement rejection';
  exception when check_violation then null;
  end;
end
$block$;

-- RPC: subject Basic enxerga apenas seu plano e seus entitlements.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c3000000-0000-0000-0000-000000000001', true);

do $block$
declare
  v_count int;
  v_users bigint;
  v_units bigint;
begin
  select count(*) into v_count
  from public.meu_plano_entitlements('c1000000-0000-0000-0000-000000000001');
  if v_count <> 2 then raise exception 'expected 2 Basic entitlements, got %', v_count; end if;

  select valor_inteiro into v_users
  from public.meu_plano_entitlements('c1000000-0000-0000-0000-000000000001')
  where chave='usuarios_ativos.max';
  select valor_inteiro into v_units
  from public.meu_plano_entitlements('c1000000-0000-0000-0000-000000000001')
  where chave='unidades.max';
  if v_users <> 10 or v_units <> 1 then raise exception 'Basic entitlements resolved incorrectly'; end if;

  select count(*) into v_count
  from public.meu_plano_entitlements('c1000000-0000-0000-0000-000000000002');
  if v_count <> 0 then raise exception 'cross-tenant plan lookup leaked data'; end if;
end
$block$;

-- Authenticated nao recebe leitura direta das tabelas comerciais.
do $block$
begin
  begin
    perform * from public.planos;
    raise exception 'expected direct plan table read rejection';
  exception when insufficient_privilege then null;
  end;
end
$block$;

reset role;

-- Anon nunca pode executar o contrato de entitlement.
do $block$
begin
  if has_function_privilege('anon', 'public.meu_plano_entitlements(uuid)', 'EXECUTE') then
    raise exception 'anon unexpectedly has entitlement RPC execute';
  end if;
end
$block$;

-- Basic permite uma unica unidade ativa. Inativa pode existir, ativacao acima do limite nao.
insert into public.unidades(id, empresa_id, nome, ativo)
values ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'Unidade Basic 1', true);

do $block$
begin
  begin
    insert into public.unidades(id, empresa_id, nome, ativo)
    values ('c2000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000001', 'Unidade Basic 2', true);
    raise exception 'expected active unit plan limit rejection';
  exception when check_violation then
    if sqlerrm <> 'Limite de unidades ativas do plano atingido' then raise; end if;
  end;
end
$block$;

insert into public.unidades(id, empresa_id, nome, ativo)
values ('c2000000-0000-0000-0000-000000000003', 'c1000000-0000-0000-0000-000000000001', 'Unidade Basic Inativa', false);

do $block$
begin
  begin
    update public.unidades set ativo=true where id='c2000000-0000-0000-0000-000000000003';
    raise exception 'expected unit activation plan limit rejection';
  exception when check_violation then
    if sqlerrm <> 'Limite de unidades ativas do plano atingido' then raise; end if;
  end;
end
$block$;

-- Basic conta usuarios distintos entre legado e membership. Owner atual ja consome 1 vaga.
insert into auth.users(id,email)
select ('d3000000-0000-0000-0000-' || lpad(i::text,12,'0'))::uuid,
       'basic-user-' || i || '@example.test'
from generate_series(1,10) i;

update public.usuarios
set empresa_id='c1000000-0000-0000-0000-000000000001', status='ativo', ativo=true
where id in (
  select ('d3000000-0000-0000-0000-' || lpad(i::text,12,'0'))::uuid
  from generate_series(1,9) i
);

do $block$
begin
  begin
    update public.usuarios
    set empresa_id='c1000000-0000-0000-0000-000000000001', status='ativo', ativo=true
    where id='d3000000-0000-0000-0000-000000000010';
    raise exception 'expected active user plan limit rejection';
  exception when check_violation then
    if sqlerrm <> 'Limite de usuarios ativos do plano atingido' then raise; end if;
  end;
end
$block$;

-- O mesmo limite vale para inclusao direta de membership ativo.
do $block$
begin
  begin
    insert into public.usuario_empresas(usuario_id,empresa_id,status)
    values('d3000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000000001','ativo');
    raise exception 'expected membership plan limit rejection';
  exception when check_violation then
    if sqlerrm <> 'Limite de usuarios ativos do plano atingido' then raise; end if;
  end;
end
$block$;

-- Empresa sem atribuicao comercial permanece sem enforcement durante a transicao.
insert into public.unidades(id, empresa_id, nome, ativo) values
  ('c2000000-0000-0000-0000-000000000010', 'c1000000-0000-0000-0000-000000000003', 'Livre 1', true),
  ('c2000000-0000-0000-0000-000000000011', 'c1000000-0000-0000-0000-000000000003', 'Livre 2', true);

select 'PASS: plan entitlements isolate tenants, enforce typed commercial limits in backend and preserve unassigned tenants' as result;

rollback;
