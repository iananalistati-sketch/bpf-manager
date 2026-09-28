begin;

insert into public.empresas(id, razao_social) values
  ('91000000-0000-0000-0000-000000000001', 'Empresa A'),
  ('91000000-0000-0000-0000-000000000002', 'Empresa B');

insert into public.unidades(id, empresa_id, nome) values
  ('92000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', 'Unidade A'),
  ('92000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000002', 'Unidade B');

insert into auth.users(id, email) values
  ('93000000-0000-0000-0000-000000000001', 'a@example.test'),
  ('93000000-0000-0000-0000-000000000002', 'b@example.test');

update public.usuarios
set empresa_id = '91000000-0000-0000-0000-000000000001',
    unidade_id = '92000000-0000-0000-0000-000000000001',
    status = 'ativo', ativo = true
where id = '93000000-0000-0000-0000-000000000001';

update public.usuarios
set empresa_id = '91000000-0000-0000-0000-000000000002',
    unidade_id = '92000000-0000-0000-0000-000000000002',
    status = 'ativo', ativo = true
where id = '93000000-0000-0000-0000-000000000002';

insert into public.perfis(id, empresa_id, nome, is_system, ativo) values
  ('94000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', 'Perfil A', false, true),
  ('94000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000002', 'Perfil B', false, true);

insert into public.usuario_empresas(id, usuario_id, empresa_id, unidade_id, status)
values
  ('95000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001', 'ativo'),
  ('95000000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000002', '92000000-0000-0000-0000-000000000002', 'ativo');

insert into public.usuario_empresa_perfis(usuario_empresa_id, perfil_id)
values
  ('95000000-0000-0000-0000-000000000001', '94000000-0000-0000-0000-000000000001'),
  ('95000000-0000-0000-0000-000000000002', '94000000-0000-0000-0000-000000000002');

-- Unidade de outra empresa deve ser rejeitada.
do $block$
begin
  begin
    insert into public.usuario_empresas(usuario_id, empresa_id, unidade_id, status)
    values (
      '93000000-0000-0000-0000-000000000001',
      '91000000-0000-0000-0000-000000000002',
      '92000000-0000-0000-0000-000000000001',
      'ativo'
    );
    raise exception 'expected incompatible unit rejection';
  exception
    when check_violation then null;
  end;
end
$block$;

-- Perfil de outra empresa deve ser rejeitado.
do $block$
begin
  begin
    insert into public.usuario_empresa_perfis(usuario_empresa_id, perfil_id)
    values ('95000000-0000-0000-0000-000000000001', '94000000-0000-0000-0000-000000000002');
    raise exception 'expected incompatible profile rejection';
  exception
    when check_violation then null;
  end;
end
$block$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '93000000-0000-0000-0000-000000000001', true);

do $block$
declare
  v_memberships int;
  v_profiles int;
begin
  select count(*) into v_memberships from public.usuario_empresas;
  if v_memberships <> 1 then
    raise exception 'RLS membership isolation failed: expected 1, got %', v_memberships;
  end if;

  select count(*) into v_profiles from public.usuario_empresa_perfis;
  if v_profiles <> 1 then
    raise exception 'RLS membership profile isolation failed: expected 1, got %', v_profiles;
  end if;
end
$block$;

-- authenticated possui somente SELECT direto nestas tabelas.
do $block$
begin
  begin
    update public.usuario_empresas
      set status = 'bloqueado'
      where id = '95000000-0000-0000-0000-000000000001';
    raise exception 'expected direct membership update privilege rejection';
  exception
    when insufficient_privilege then null;
  end;
end
$block$;

reset role;

select 'PASS: membership compatibility enforces tenant/profile scope, own-read RLS and no direct authenticated writes' as result;

rollback;
