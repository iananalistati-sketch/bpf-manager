begin;

insert into auth.users(id,email,raw_user_meta_data) values
  ('bd000000-0000-0000-0000-000000000001','docs-editor@example.test','{"nome":"Docs Editor"}'::jsonb),
  ('bd000000-0000-0000-0000-000000000002','docs-viewer@example.test','{"nome":"Docs Viewer"}'::jsonb),
  ('bd000000-0000-0000-0000-000000000003','docs-foreign@example.test','{"nome":"Docs Foreign"}'::jsonb);

insert into public.empresas(id,razao_social,nome_fantasia) values
  ('bd100000-0000-0000-0000-000000000001','Empresa Documentos Ltda','Empresa Documentos'),
  ('bd100000-0000-0000-0000-000000000002','Empresa Estrangeira Ltda','Empresa Estrangeira');

insert into public.unidades(id,empresa_id,nome,ativo) values
  ('bd200000-0000-0000-0000-000000000001','bd100000-0000-0000-0000-000000000001','Unidade Principal',true),
  ('bd200000-0000-0000-0000-000000000002','bd100000-0000-0000-0000-000000000002','Unidade Estrangeira',true);

update public.usuarios
set empresa_id='bd100000-0000-0000-0000-000000000001',
    unidade_id='bd200000-0000-0000-0000-000000000001',
    status='ativo',ativo=true
where id in (
  'bd000000-0000-0000-0000-000000000001',
  'bd000000-0000-0000-0000-000000000002'
);

update public.usuarios
set empresa_id='bd100000-0000-0000-0000-000000000002',
    unidade_id='bd200000-0000-0000-0000-000000000002',
    status='ativo',ativo=true
where id='bd000000-0000-0000-0000-000000000003';

insert into public.usuario_empresas(id,usuario_id,empresa_id,unidade_id,status,is_owner) values
  ('bd300000-0000-0000-0000-000000000001','bd000000-0000-0000-0000-000000000001','bd100000-0000-0000-0000-000000000001','bd200000-0000-0000-0000-000000000001','ativo',true),
  ('bd300000-0000-0000-0000-000000000002','bd000000-0000-0000-0000-000000000002','bd100000-0000-0000-0000-000000000001','bd200000-0000-0000-0000-000000000001','ativo',false),
  ('bd300000-0000-0000-0000-000000000003','bd000000-0000-0000-0000-000000000003','bd100000-0000-0000-0000-000000000002','bd200000-0000-0000-0000-000000000002','ativo',true);

insert into public.perfis(id,empresa_id,nome,is_system,ativo) values
  ('bd400000-0000-0000-0000-000000000001','bd100000-0000-0000-0000-000000000001','Editor Documental',false,true),
  ('bd400000-0000-0000-0000-000000000002','bd100000-0000-0000-0000-000000000001','Consulta Documental',false,true),
  ('bd400000-0000-0000-0000-000000000003','bd100000-0000-0000-0000-000000000002','Editor Estrangeiro',false,true);

insert into public.usuario_empresa_perfis(usuario_empresa_id,perfil_id) values
  ('bd300000-0000-0000-0000-000000000001','bd400000-0000-0000-0000-000000000001'),
  ('bd300000-0000-0000-0000-000000000002','bd400000-0000-0000-0000-000000000002'),
  ('bd300000-0000-0000-0000-000000000003','bd400000-0000-0000-0000-000000000003');

insert into public.perfil_permissoes(perfil_id,permissao_id)
select 'bd400000-0000-0000-0000-000000000001',id
from public.permissoes
where codigo in ('documentos.visualizar','documentos.criar','documentos.editar','documentos.aprovar');

insert into public.perfil_permissoes(perfil_id,permissao_id)
select 'bd400000-0000-0000-0000-000000000002',id
from public.permissoes
where codigo='documentos.visualizar';

insert into public.perfil_permissoes(perfil_id,permissao_id)
select 'bd400000-0000-0000-0000-000000000003',id
from public.permissoes
where codigo in ('documentos.visualizar','documentos.criar','documentos.editar','documentos.aprovar');

insert into public.empresa_assinaturas(
  empresa_id,status,trial_inicio,trial_fim
) values (
  'bd100000-0000-0000-0000-000000000001',
  'trialing',
  now(),
  now()+interval '14 days'
);

select set_config('request.jwt.claim.sub','bd000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"bd000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;

create temp table qa_documento(id uuid);
insert into qa_documento
select public.documento_criar(
  'bd100000-0000-0000-0000-000000000001',
  'bd200000-0000-0000-0000-000000000001',
  'POP-001',
  'Higienização das instalações',
  'POP',
  'Procedimento inicial controlado.',
  current_date+interval '180 days'
);

do $block$
declare
  v_row record;
begin
  select * into v_row
  from public.documentos_listar(
    'bd100000-0000-0000-0000-000000000001',
    'bd200000-0000-0000-0000-000000000001'
  )
  where documento_id=(select id from qa_documento);

  if v_row.codigo <> 'POP-001'
     or v_row.titulo <> 'Higienização das instalações'
     or v_row.versao_numero <> 1
     or v_row.status <> 'rascunho' then
    raise exception 'created document was not exposed correctly';
  end if;
end
$block$;

select public.documento_rascunho_atualizar(
  (select id from qa_documento),
  'bd200000-0000-0000-0000-000000000001',
  'Higienização de instalações e equipamentos',
  'POP',
  'Procedimento revisado antes da submissão.',
  current_date+180
);

select public.documento_transicionar(
  (select id from qa_documento),
  'em_revisao',
  'Encaminhado para revisão técnica'
);
select public.documento_transicionar(
  (select id from qa_documento),
  'aguardando_aprovacao',
  'Revisão técnica concluída'
);
select public.documento_transicionar(
  (select id from qa_documento),
  'aprovado',
  'Conteúdo aprovado pelo responsável'
);
select public.documento_transicionar(
  (select id from qa_documento),
  'vigente',
  'Documento liberado para uso'
);

do $block$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.documento_historico((select id from qa_documento))
  where numero=1 and status='vigente' and aprovado_em is not null and vigencia_inicio is not null;
  if v_count <> 1 then raise exception 'version 1 did not reach vigente with approval evidence'; end if;

  if not exists (
    select 1 from public.auditoria_eventos
    where registro_id=(select id from qa_documento)
      and acao='documento.status_alterado'
  ) then raise exception 'document workflow audit missing'; end if;
end
$block$;

select public.documento_iniciar_revisao(
  (select id from qa_documento),
  'Revisão periódica do procedimento',
  current_date+365
);

do $block$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.documento_historico((select id from qa_documento));
  if v_count <> 2 then raise exception 'new revision did not create version 2'; end if;

  if not exists (
    select 1 from public.documento_historico((select id from qa_documento))
    where numero=2 and status='rascunho' and motivo_revisao='Revisão periódica do procedimento'
  ) then raise exception 'version 2 draft did not preserve review context'; end if;

  if not exists (
    select 1 from public.documento_historico((select id from qa_documento))
    where numero=1 and status='vigente'
  ) then raise exception 'previous version should remain vigente during draft review'; end if;
end
$block$;

select public.documento_transicionar(
  (select id from qa_documento),
  'em_revisao',
  'Segunda versão enviada para revisão'
);
select public.documento_transicionar(
  (select id from qa_documento),
  'aguardando_aprovacao',
  'Segunda versão revisada'
);
select public.documento_transicionar(
  (select id from qa_documento),
  'aprovado',
  'Segunda versão aprovada'
);
select public.documento_transicionar(
  (select id from qa_documento),
  'vigente',
  'Segunda versão liberada'
);

do $block$
begin
  if not exists (
    select 1 from public.documento_historico((select id from qa_documento))
    where numero=1 and status='obsoleto' and obsoleto_em is not null
  ) then raise exception 'publishing version 2 did not obsolete version 1'; end if;

  if not exists (
    select 1 from public.documento_historico((select id from qa_documento))
    where numero=2 and status='vigente'
  ) then raise exception 'version 2 did not become vigente'; end if;
end
$block$;

reset role;

-- Viewer can read but cannot mutate.
select set_config('request.jwt.claim.sub','bd000000-0000-0000-0000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"bd000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
set local role authenticated;

do $block$
begin
  if not exists (
    select 1 from public.documentos_listar('bd100000-0000-0000-0000-000000000001',null)
    where documento_id=(select id from qa_documento)
  ) then raise exception 'viewer could not read tenant document'; end if;

  begin
    perform public.documento_criar(
      'bd100000-0000-0000-0000-000000000001',
      null,'POP-002','Documento indevido','POP','Sem permissão',null
    );
    raise exception 'expected viewer create rejection';
  exception when insufficient_privilege then null;
  end;
end
$block$;

reset role;

-- Foreign tenant cannot spoof the company id.
select set_config('request.jwt.claim.sub','bd000000-0000-0000-0000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"bd000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
set local role authenticated;

do $block$
begin
  begin
    perform * from public.documentos_listar('bd100000-0000-0000-0000-000000000001',null);
    raise exception 'expected cross-tenant document read rejection';
  exception when insufficient_privilege then null;
  end;
end
$block$;

reset role;

-- Expired trial blocks document writes without deleting existing history.
update public.empresa_assinaturas
set trial_inicio=now()-interval '15 days',
    trial_fim=now()-interval '1 day'
where empresa_id='bd100000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub','bd000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"bd000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;

do $block$
begin
  begin
    perform public.documento_iniciar_revisao(
      (select id from qa_documento),
      'Tentativa em trial expirado',
      null
    );
    raise exception 'expected expired trial document write rejection';
  exception when insufficient_privilege then
    if sqlerrm <> 'Workspace em modo somente leitura' then raise; end if;
  end;

  if not exists (
    select 1 from public.documentos_listar('bd100000-0000-0000-0000-000000000001',null)
    where documento_id=(select id from qa_documento)
  ) then raise exception 'expired trial should preserve document read access'; end if;
end
$block$;

reset role;

-- Direct table access stays closed; only authenticated RPC contracts are public.
do $block$
begin
  if has_table_privilege('authenticated','public.documentos','SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'authenticated unexpectedly has direct documentos table access';
  end if;
  if has_table_privilege('authenticated','public.documento_versoes','SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'authenticated unexpectedly has direct documento_versoes table access';
  end if;
  if has_table_privilege('service_role','public.documentos','SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'service_role unexpectedly has direct documentos table access';
  end if;

  if not has_function_privilege('authenticated','public.documentos_listar(uuid,uuid)','EXECUTE') then
    raise exception 'authenticated lost document list execute';
  end if;
  if has_function_privilege('anon','public.documentos_listar(uuid,uuid)','EXECUTE') then
    raise exception 'anon unexpectedly can list documents';
  end if;
end
$block$;

select 'PASS: controlled documents enforce tenant-aware RBAC, workflow/version history, audit, commercial read-only and closed direct-table access' as result;
rollback;
