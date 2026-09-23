begin;

insert into public.empresas(id, razao_social, nome_fantasia) values
  ('a1000000-0000-0000-0000-000000000001', 'Empresa A', 'Tenant A'),
  ('a1000000-0000-0000-0000-000000000002', 'Empresa B', 'Tenant B'),
  ('a1000000-0000-0000-0000-000000000003', 'Empresa C', 'Tenant C');

insert into public.unidades(id, empresa_id, nome) values
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'Unidade A'),
  ('a2000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000002', 'Unidade B'),
  ('a2000000-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000003', 'Unidade C');

insert into auth.users(id, email) values
  ('a3000000-0000-0000-0000-000000000001', 'multi@example.test'),
  ('a3000000-0000-0000-0000-000000000002', 'other@example.test');

update public.usuarios
set empresa_id = 'a1000000-0000-0000-0000-000000000001',
    unidade_id = 'a2000000-0000-0000-0000-000000000001',
    nome = 'Usuario Multi', status = 'ativo', ativo = true
where id = 'a3000000-0000-0000-0000-000000000001';

update public.usuarios
set empresa_id = 'a1000000-0000-0000-0000-000000000003',
    unidade_id = 'a2000000-0000-0000-0000-000000000003',
    nome = 'Usuario Outro', status = 'ativo', ativo = true
where id = 'a3000000-0000-0000-0000-000000000002';

insert into public.perfis(id, empresa_id, nome, is_system, ativo) values
  ('a4000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'Perfil Tenant A', false, true),
  ('a4000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000002', 'Perfil Tenant B', false, true),
  ('a4000000-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000003', 'Perfil Tenant C', false, true);

insert into public.permissoes(id, codigo, modulo, acao) values
  ('a5000000-0000-0000-0000-000000000001', 'tenant_a.visualizar', 'tenant_a', 'visualizar'),
  ('a5000000-0000-0000-0000-000000000002', 'tenant_b.visualizar', 'tenant_b', 'visualizar'),
  ('a5000000-0000-0000-0000-000000000003', 'tenant_c.visualizar', 'tenant_c', 'visualizar');

insert into public.perfil_permissoes(perfil_id, permissao_id) values
  ('a4000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000001'),
  ('a4000000-0000-0000-0000-000000000002', 'a5000000-0000-0000-0000-000000000002'),
  ('a4000000-0000-0000-0000-000000000003', 'a5000000-0000-0000-0000-000000000003');

insert into public.usuario_empresas(id, usuario_id, empresa_id, unidade_id, status, is_owner) values
  ('a6000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'ativo', true),
  ('a6000000-0000-0000-0000-000000000002', 'a3000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000002', 'ativo', false),
  ('a6000000-0000-0000-0000-000000000003', 'a3000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000003', 'a2000000-0000-0000-0000-000000000003', 'ativo', true);

insert into public.usuario_empresa_perfis(usuario_empresa_id, perfil_id) values
  ('a6000000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000001'),
  ('a6000000-0000-0000-0000-000000000002', 'a4000000-0000-0000-0000-000000000002'),
  ('a6000000-0000-0000-0000-000000000003', 'a4000000-0000-0000-0000-000000000003');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a3000000-0000-0000-0000-000000000001', true);

do $block$
declare
  v_count int;
  v_perm_a text[];
  v_perm_b text[];
  v_owner_a boolean;
begin
  select count(*) into v_count from public.meus_vinculos();
  if v_count <> 2 then
    raise exception 'expected 2 authorized memberships, got %', v_count;
  end if;

  select permissoes, is_owner into v_perm_a, v_owner_a
  from public.meu_contexto_empresa('a1000000-0000-0000-0000-000000000001');
  if v_perm_a is null or not ('tenant_a.visualizar' = any(v_perm_a)) or ('tenant_b.visualizar' = any(v_perm_a)) then
    raise exception 'tenant A permissions leaked or missing: %', v_perm_a;
  end if;
  if v_owner_a is distinct from true then
    raise exception 'tenant A owner flag not preserved';
  end if;

  select permissoes into v_perm_b
  from public.meu_contexto_empresa('a1000000-0000-0000-0000-000000000002');
  if v_perm_b is null or not ('tenant_b.visualizar' = any(v_perm_b)) or ('tenant_a.visualizar' = any(v_perm_b)) then
    raise exception 'tenant B permissions leaked or missing: %', v_perm_b;
  end if;

  select count(*) into v_count
  from public.meu_contexto_empresa('a1000000-0000-0000-0000-000000000003');
  if v_count <> 0 then
    raise exception 'cross-tenant empresa_id spoofing returned unauthorized context';
  end if;
end
$block$;

reset role;

-- Membership bloqueado deixa de ser contexto operacional.
update public.usuario_empresas
set status = 'bloqueado'
where id = 'a6000000-0000-0000-0000-000000000002';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a3000000-0000-0000-0000-000000000001', true);

do $block$
declare
  v_count int;
begin
  select count(*) into v_count from public.meus_vinculos();
  if v_count <> 1 then
    raise exception 'blocked membership remained selectable';
  end if;

  select count(*) into v_count
  from public.meu_contexto_empresa('a1000000-0000-0000-0000-000000000002');
  if v_count <> 0 then
    raise exception 'blocked membership still resolved context';
  end if;
end
$block$;

reset role;

-- Identidade global inativa invalida todos os tenants.
update public.usuarios
set ativo = false, status = 'inativo'
where id = 'a3000000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a3000000-0000-0000-0000-000000000001', true);

do $block$
declare
  v_count int;
begin
  select count(*) into v_count from public.meus_vinculos();
  if v_count <> 0 then
    raise exception 'inactive global identity retained tenant access';
  end if;
end
$block$;

reset role;
set local role anon;

do $block$
begin
  begin
    perform * from public.meus_vinculos();
    raise exception 'expected anon execute rejection';
  exception
    when insufficient_privilege then null;
  end;
end
$block$;

reset role;

select 'PASS: tenant context validates active memberships, isolates RBAC and rejects cross-tenant spoofing' as result;

rollback;
