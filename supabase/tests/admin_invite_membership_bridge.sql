begin;

insert into public.empresas(id, razao_social, nome_fantasia) values
  ('e1000000-0000-0000-0000-000000000001', 'Empresa Primaria', 'Primaria'),
  ('e1000000-0000-0000-0000-000000000002', 'Empresa Tenant B', 'Tenant B'),
  ('e1000000-0000-0000-0000-000000000003', 'Empresa Nao Autorizada', 'Tenant C');

insert into public.unidades(id, empresa_id, nome) values
  ('e2000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000002', 'Unidade B');

insert into auth.users(id,email) values
  ('e3000000-0000-0000-0000-000000000001','actor@example.test'),
  ('e3000000-0000-0000-0000-000000000002','target@example.test'),
  ('e3000000-0000-0000-0000-000000000003','target2@example.test'),
  ('e3000000-0000-0000-0000-000000000004','target-limit@example.test'),
  ('e3000000-0000-0000-0000-000000000005','target-recovery@example.test');

update public.usuarios
set empresa_id='e1000000-0000-0000-0000-000000000001', status='ativo', ativo=true, nome='Actor'
where id='e3000000-0000-0000-0000-000000000001';

insert into public.perfis(id,empresa_id,nome,is_system,ativo) values
  ('e4000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000002','Admin Tenant B',false,true),
  ('e4000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000002','Operador Tenant B',false,true);

insert into public.perfil_permissoes(perfil_id,permissao_id)
select 'e4000000-0000-0000-0000-000000000001', id
from public.permissoes
where codigo in ('configuracoes.visualizar','usuarios.gerenciar','usuarios.convidar');

insert into public.perfil_permissoes(perfil_id,permissao_id)
select 'e4000000-0000-0000-0000-000000000002', id
from public.permissoes
where codigo='configuracoes.visualizar';

insert into public.usuario_empresas(id,usuario_id,empresa_id,status,is_owner) values
  ('e6000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000002','ativo',true);
insert into public.usuario_empresa_perfis(usuario_empresa_id,perfil_id) values
  ('e6000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001');

-- Estado final da arquitetura: o convite autenticado antigo foi fechado e a Edge chama
-- exclusivamente a RPC server-only como service_role, passando explicitamente o ator validado.
set local role service_role;
select public.admin_usuario_vincular_convite_server(
  'e3000000-0000-0000-0000-000000000001',
  'e1000000-0000-0000-0000-000000000002',
  'e3000000-0000-0000-0000-000000000002',
  'e2000000-0000-0000-0000-000000000002',
  array['e4000000-0000-0000-0000-000000000002']::uuid[],
  'Convite tenant B para teste'
);
reset role;

do $block$
declare
  v_legacy_empresa uuid;
  v_status text;
  v_memberships int;
  v_profiles int;
  v_legacy_profiles int;
  v_audits int;
begin
  select empresa_id,status into v_legacy_empresa,v_status
  from public.usuarios where id='e3000000-0000-0000-0000-000000000002';
  if v_legacy_empresa <> 'e1000000-0000-0000-0000-000000000002' or v_status <> 'ativo' then
    raise exception 'legacy compatibility was not synchronized';
  end if;

  select count(*) into v_memberships
  from public.usuario_empresas
  where usuario_id='e3000000-0000-0000-0000-000000000002'
    and empresa_id='e1000000-0000-0000-0000-000000000002'
    and unidade_id='e2000000-0000-0000-0000-000000000002'
    and status='ativo';
  if v_memberships <> 1 then raise exception 'membership was not created'; end if;

  select count(*) into v_profiles
  from public.usuario_empresa_perfis uep
  join public.usuario_empresas ue on ue.id=uep.usuario_empresa_id
  where ue.usuario_id='e3000000-0000-0000-0000-000000000002'
    and ue.empresa_id='e1000000-0000-0000-0000-000000000002'
    and uep.perfil_id='e4000000-0000-0000-0000-000000000002';
  if v_profiles <> 1 then raise exception 'membership profile was not created'; end if;

  select count(*) into v_legacy_profiles
  from public.usuario_perfis
  where usuario_id='e3000000-0000-0000-0000-000000000002'
    and perfil_id='e4000000-0000-0000-0000-000000000002';
  if v_legacy_profiles <> 1 then raise exception 'legacy profile compatibility was not synchronized'; end if;

  select count(*) into v_audits from public.auditoria_eventos
  where empresa_id='e1000000-0000-0000-0000-000000000002'
    and registro_id='e3000000-0000-0000-0000-000000000002'
    and acao='usuario.convidado_vinculado';
  if v_audits <> 1 then raise exception 'tenant invitation audit missing'; end if;
end
$block$;

-- Recuperação de membership pendente preexistente para o mesmo alvo/tenant.
insert into public.usuario_empresas(
  id,usuario_id,empresa_id,unidade_id,status,is_owner,created_by
) values (
  'e6000000-0000-0000-0000-000000000005',
  'e3000000-0000-0000-0000-000000000005',
  'e1000000-0000-0000-0000-000000000002',
  null,'pendente',false,null
);

set local role service_role;
select public.admin_usuario_vincular_convite_server(
  'e3000000-0000-0000-0000-000000000001',
  'e1000000-0000-0000-0000-000000000002',
  'e3000000-0000-0000-0000-000000000005',
  'e2000000-0000-0000-0000-000000000002',
  array['e4000000-0000-0000-0000-000000000002']::uuid[],
  'Recupera membership pendente'
);
reset role;

do $block$
declare v_count int; v_membership_id uuid; v_status text; v_unit uuid;
begin
  select id,status,unidade_id into v_membership_id,v_status,v_unit
  from public.usuario_empresas
  where usuario_id='e3000000-0000-0000-0000-000000000005'
    and empresa_id='e1000000-0000-0000-0000-000000000002';
  if v_membership_id <> 'e6000000-0000-0000-0000-000000000005'
     or v_status <> 'ativo'
     or v_unit <> 'e2000000-0000-0000-0000-000000000002' then
    raise exception 'preexisting membership was not recovered through restricted upsert';
  end if;
  select count(*) into v_count
  from public.usuario_empresa_perfis
  where usuario_empresa_id=v_membership_id
    and perfil_id='e4000000-0000-0000-0000-000000000002';
  if v_count <> 1 then raise exception 'recovered membership did not receive profile'; end if;
end
$block$;

-- Tenant adulterado deve falhar antes de qualquer mutação do alvo.
set local role service_role;
do $block$
begin
  begin
    perform public.admin_usuario_vincular_convite_server(
      'e3000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000003',
      'e3000000-0000-0000-0000-000000000003',
      null,
      array['e4000000-0000-0000-0000-000000000002']::uuid[],
      'Tentativa fora do tenant'
    );
    raise exception 'expected unauthorized tenant invite rejection';
  exception when insufficient_privilege then null;
  end;
end
$block$;
reset role;

do $block$
declare v_empresa uuid; v_status text; v_memberships int; v_audits int;
begin
  select empresa_id,status into v_empresa,v_status
  from public.usuarios where id='e3000000-0000-0000-0000-000000000003';
  if v_empresa is not null or v_status <> 'pendente' then
    raise exception 'unauthorized tenant attempt mutated target user';
  end if;
  select count(*) into v_memberships from public.usuario_empresas
    where usuario_id='e3000000-0000-0000-0000-000000000003';
  select count(*) into v_audits from public.auditoria_eventos
    where registro_id='e3000000-0000-0000-0000-000000000003';
  if v_memberships <> 0 or v_audits <> 0 then
    raise exception 'unauthorized tenant attempt left partial state';
  end if;
end
$block$;

-- Prepara 10 usuários ativos no Tenant B; o 11º deve falhar pelo limite Basic e rollbackar tudo.
insert into auth.users(id,email)
select ('f3000000-0000-0000-0000-' || lpad(i::text,12,'0'))::uuid,
       'tenant-b-fill-' || i || '@example.test'
from generate_series(1,7) i;

update public.usuarios
set empresa_id='e1000000-0000-0000-0000-000000000002', status='ativo', ativo=true
where id in (
  select ('f3000000-0000-0000-0000-' || lpad(i::text,12,'0'))::uuid
  from generate_series(1,7) i
);

insert into public.empresa_planos(empresa_id,plano_id,origem)
select 'e1000000-0000-0000-0000-000000000002', id, 'manual'
from public.planos where codigo='basic';

set local role service_role;
do $block$
begin
  begin
    perform public.admin_usuario_vincular_convite_server(
      'e3000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000002',
      'e3000000-0000-0000-0000-000000000004',
      'e2000000-0000-0000-0000-000000000002',
      array['e4000000-0000-0000-0000-000000000002']::uuid[],
      'Convite acima do limite do plano'
    );
    raise exception 'expected plan user limit rejection';
  exception when check_violation then
    if sqlerrm <> 'Limite de usuarios ativos do plano atingido' then raise; end if;
  end;
end
$block$;
reset role;

do $block$
declare
  v_empresa uuid;
  v_status text;
  v_memberships int;
  v_membership_profiles int;
  v_legacy_profiles int;
  v_audits int;
begin
  select empresa_id,status into v_empresa,v_status
  from public.usuarios where id='e3000000-0000-0000-0000-000000000004';
  if v_empresa is not null or v_status <> 'pendente' then
    raise exception 'plan-limit failure did not rollback legacy user state';
  end if;

  select count(*) into v_memberships from public.usuario_empresas
    where usuario_id='e3000000-0000-0000-0000-000000000004';
  select count(*) into v_membership_profiles
  from public.usuario_empresa_perfis uep
  join public.usuario_empresas ue on ue.id=uep.usuario_empresa_id
  where ue.usuario_id='e3000000-0000-0000-0000-000000000004';
  select count(*) into v_legacy_profiles from public.usuario_perfis
    where usuario_id='e3000000-0000-0000-0000-000000000004';
  select count(*) into v_audits from public.auditoria_eventos
    where registro_id='e3000000-0000-0000-0000-000000000004';

  if v_memberships <> 0 or v_membership_profiles <> 0 or v_legacy_profiles <> 0 or v_audits <> 0 then
    raise exception 'plan-limit failure left partial invitation state';
  end if;
end
$block$;

-- Fronteira final: somente service_role executa a RPC server-only; o caminho antigo fica fechado.
do $block$
begin
  if not has_function_privilege('service_role','public.admin_usuario_vincular_convite_server(uuid,uuid,uuid,uuid,uuid[],text)','EXECUTE') then
    raise exception 'service_role lost server invite RPC execute';
  end if;
  if has_function_privilege('authenticated','public.admin_usuario_vincular_convite_server(uuid,uuid,uuid,uuid,uuid[],text)','EXECUTE') then
    raise exception 'authenticated unexpectedly can execute server invite RPC';
  end if;
  if has_function_privilege('anon','public.admin_usuario_vincular_convite_server(uuid,uuid,uuid,uuid,uuid[],text)','EXECUTE') then
    raise exception 'anon unexpectedly can execute server invite RPC';
  end if;
  if has_function_privilege('authenticated','public.admin_usuario_vincular_convite_tenant(uuid,uuid,uuid,uuid[],text)','EXECUTE') then
    raise exception 'legacy authenticated invite RPC unexpectedly remains executable';
  end if;
end
$block$;

select 'PASS: server-only tenant invitation covers membership/profile/audit sync, recovery, cross-tenant rejection, plan rollback and closed legacy surface' as result;

rollback;
