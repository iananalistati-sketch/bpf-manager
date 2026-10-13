begin;

insert into auth.users(id,email,raw_user_meta_data) values
  ('b1000000-0000-0000-0000-000000000001','commercial-owner@example.test','{"nome":"Commercial Owner"}'::jsonb),
  ('b1000000-0000-0000-0000-000000000002','commercial-target@example.test','{"nome":"Commercial Target"}'::jsonb);

insert into public.perfis(id,empresa_id,nome,is_system,ativo)
select 'b1100000-0000-0000-0000-000000000001',null,'Administrador',true,true
where not exists (
  select 1 from public.perfis where is_system and empresa_id is null and lower(nome)=lower('Administrador') and ativo
);

-- O provisionamento atribui o perfil Administrador, mas esta suite precisa montar
-- explicitamente as permissoes exigidas pelos comandos administrativos que serao testados.
insert into public.permissoes(codigo,modulo,acao)
values
  ('configuracoes.visualizar','configuracoes','visualizar'),
  ('usuarios.gerenciar','usuarios','gerenciar'),
  ('estrutura.gerenciar','estrutura','gerenciar')
on conflict (codigo) do nothing;

insert into public.perfil_permissoes(perfil_id,permissao_id)
select p.id,pm.id
from public.perfis p
join public.permissoes pm
  on pm.codigo in ('configuracoes.visualizar','usuarios.gerenciar','estrutura.gerenciar')
where p.is_system
  and p.empresa_id is null
  and p.ativo
  and lower(p.nome)=lower('Administrador')
on conflict (perfil_id,permissao_id) do nothing;

set local role service_role;
select * from public.provisionar_trial_server(
  'b1000000-0000-0000-0000-000000000001',
  'Commercial Guard QA Ltda',
  'Commercial Guard QA',
  'Unidade Principal',
  'trial-commercial-guard-20261013'
);
reset role;

create temp table qa_commercial_guard as
select empresa_id
from public.saas_provisionamentos
where chave_idempotencia='trial-commercial-guard-20261013';
grant select on qa_commercial_guard to authenticated;

update public.usuarios
set empresa_id=(select empresa_id from qa_commercial_guard),
    status='ativo',
    ativo=true
where id='b1000000-0000-0000-0000-000000000002';

select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;

-- Trial valido permite escrita administrativa normal.
select public.admin_usuario_alterar_status(
  'b1000000-0000-0000-0000-000000000002',
  'bloqueado',
  'QA trial valido'
);

reset role;

do $block$
begin
  if not exists (
    select 1 from public.usuarios
    where id='b1000000-0000-0000-0000-000000000002'
      and status='bloqueado'
      and not ativo
  ) then
    raise exception 'valid trial admin mutation was not applied';
  end if;
end
$block$;

update public.usuarios
set status='ativo', ativo=true
where id='b1000000-0000-0000-0000-000000000002';

-- Expira mantendo a invariavel trial_fim > trial_inicio.
update public.empresa_assinaturas
set trial_inicio=now()-interval '15 days',
    trial_fim=now()-interval '1 day'
where empresa_id=(select empresa_id from qa_commercial_guard);

set local role authenticated;

do $block$
begin
  begin
    perform public.admin_usuario_alterar_status(
      'b1000000-0000-0000-0000-000000000002',
      'bloqueado',
      'QA trial expirado'
    );
    raise exception 'expected expired trial admin mutation rejection';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.admin_unidade_salvar(
      null,
      'Unidade Nao Permitida',
      'BLOCK',
      true,
      'QA trial expirado'
    );
    raise exception 'expected expired trial structure mutation rejection';
  exception when insufficient_privilege then null;
  end;
end
$block$;

reset role;

do $block$
begin
  if not exists (
    select 1 from public.usuarios
    where id='b1000000-0000-0000-0000-000000000002'
      and status='ativo'
      and ativo
  ) then
    raise exception 'expired trial mutation changed target state';
  end if;

  if exists (
    select 1 from public.unidades
    where empresa_id=(select empresa_id from qa_commercial_guard)
      and codigo='BLOCK'
  ) then
    raise exception 'expired trial structure write was persisted';
  end if;

  if has_function_privilege('anon','private.assert_primary_workspace_write_allowed()','EXECUTE') then
    raise exception 'anon unexpectedly can execute commercial write guard';
  end if;
end
$block$;

select 'PASS: active trial permits admin writes, expired trial blocks user/structure mutations, and legacy no-subscription compatibility remains covered by existing suites' as result;
rollback;
