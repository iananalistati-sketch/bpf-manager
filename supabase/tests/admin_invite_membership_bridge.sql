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
  ('e3000000-0000-0000-0000-000000000003','target2@example.test');

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

set local role authenticated;
select set_config('request.jwt.claim.sub','e3000000-0000-0000-0000-000000000001',true);

select public.admin_usuario_vincular_convite_tenant(
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

  select count(*) into v_audits from public.auditoria_eventos
  where empresa_id='e1000000-0000-0000-0000-000000000002'
    and registro_id='e3000000-0000-0000-0000-000000000002'
    and acao='usuario.convidado_vinculado';
  if v_audits <> 1 then raise exception 'tenant invitation audit missing'; end if;
end
$block$;

set local role authenticated;
select set_config('request.jwt.claim.sub','e3000000-0000-0000-0000-000000000001',true);

do $block$
begin
  begin
    perform public.admin_usuario_vincular_convite_tenant(
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
begin
  if has_function_privilege('anon','public.admin_usuario_vincular_convite_tenant(uuid,uuid,uuid,uuid[],text)','EXECUTE') then
    raise exception 'anon unexpectedly can execute tenant invite RPC';
  end if;
  if not has_function_privilege('authenticated','public.admin_usuario_vincular_convite_tenant(uuid,uuid,uuid,uuid[],text)','EXECUTE') then
    raise exception 'authenticated lost tenant invite RPC execute';
  end if;
end
$block$;

select 'PASS: tenant-aware invitation synchronizes legacy/membership state, audits and rejects unauthorized tenant' as result;

rollback;
