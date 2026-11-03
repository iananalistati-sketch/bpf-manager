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

create temp table qa_documento(id uuid);
grant select, insert on qa_documento to authenticated;

select set_config('request.jwt.claim.sub','bd000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"bd000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;

insert into qa_documento
select public.documento_criar(
  'bd100000-0000-0000-0000-000000000001',
  'bd200000-0000-0000-0000-000000000001',
  'POP-001',
  'Higienização das instalações',
  'POP',
  'Procedimento inicial controlado.',
  current_date+180
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

-- Editar a nova revisao nao altera a evidencia da versao vigente.
select public.documento_rascunho_atualizar(
  (select id from qa_documento), null,
  'Titulo da segunda versao', 'Manual', 'Conteudo da segunda versao', current_date+365
);
do $block$
begin
  if not exists (select 1 from public.documento_historico((select id from qa_documento))
      where numero=1 and titulo='Higienização de instalações e equipamentos'
        and tipo='POP' and unidade_id='bd200000-0000-0000-0000-000000000001'
        and descricao='Procedimento revisado antes da submissão.' and status='vigente') then
    raise exception 'draft v2 changed published v1 evidence';
  end if;
  if not exists (select 1 from public.documentos_listar('bd100000-0000-0000-0000-000000000001',null)
      where documento_id=(select id from qa_documento) and versao_numero=2 and vigente_numero=1
        and titulo='Titulo da segunda versao' and tipo='Manual' and unidade_id is null) then
    raise exception 'list lost current published version or new draft snapshot';
  end if;
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

-- Inspecao do efeito auditavel como deployer: o editor documental nao ganha auditoria administrativa.
do $block$
begin
  if (select count(*) from public.auditoria_eventos
      where registro_id=(select id from qa_documento) and acao='documento.status_alterado') <> 8 then
    raise exception 'document workflow audit missing';
  end if;
end
$block$;

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

-- Matriz adversarial: todas as mutacoes, revogacao, estados, tenant e rollback.
create function pg_temp.expect_document_error(p_sql text,p_code text)
returns void language plpgsql security invoker as $fn$
declare rejected boolean := false;
begin
  begin
    execute p_sql;
  exception when others then
    if sqlstate <> p_code then raise; end if;
    rejected := true;
  end;
  if not rejected then raise exception 'Expected SQLSTATE % for %',p_code,p_sql; end if;
end
$fn$;
grant execute on function pg_temp.expect_document_error(text,text) to authenticated;

update public.empresa_assinaturas set status='active'
where empresa_id='bd100000-0000-0000-0000-000000000001';
create temp table qa_document_calls(name text,sql text);
create temp table qa_document_baseline(state jsonb);
grant select on qa_document_calls,qa_document_baseline to authenticated;

-- Uma segunda linha em rascunho oferece OLD valido para editar/transicionar.
set local role authenticated;
select public.documento_criar('bd100000-0000-0000-0000-000000000001',null,
  'POP-MATRIX','Documento da matriz','POP','Conteudo matriz',null);
reset role;
insert into qa_document_calls values
('criar', $q$select public.documento_criar('bd100000-0000-0000-0000-000000000001',null,'POP-INVALID','Documento indevido','POP','Texto',null)$q$),
('editar', format($q$select public.documento_rascunho_atualizar(%L,null,'Novo titulo','POP','Texto',null)$q$,
  (select id from public.documentos where codigo='POP-MATRIX'))),
('transicionar',format($q$select public.documento_transicionar(%L,'em_revisao','Encaminhar revisao')$q$,
  (select id from public.documentos where codigo='POP-MATRIX'))),
('revisar',format($q$select public.documento_iniciar_revisao(%L,'Revisao da matriz',null)$q$,
  (select id from qa_documento)));

-- Snapshot completo inclui auditoria e comprova ausencia de qualquer estado parcial.
insert into qa_document_baseline
select jsonb_build_object(
  'docs',(select jsonb_agg(to_jsonb(d) order by id) from public.documentos d),
  'versions',(select jsonb_agg(to_jsonb(v) order by id) from public.documento_versoes v),
  'audit',(select jsonb_agg(to_jsonb(a) order by id) from public.auditoria_eventos a));

-- Viewer e tenant estrangeiro: todas as mutacoes chamadas diretamente falham.
do $block$
declare actor text; cmd record;
begin
  foreach actor in array array['bd000000-0000-0000-0000-000000000002','bd000000-0000-0000-0000-000000000003'] loop
    perform set_config('request.jwt.claim.sub',actor,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
    set local role authenticated;
    for cmd in select * from qa_document_calls loop
      perform pg_temp.expect_document_error(cmd.sql,'42501');
    end loop;
    perform pg_temp.expect_document_error(format('select * from public.documento_historico(%L)',(select id from qa_documento)),
      case when actor='bd000000-0000-0000-0000-000000000003' then '42501' else '00000' end)
      where actor='bd000000-0000-0000-0000-000000000003';
    -- Nao revelar o status nem distinguir ID conhecido de inexistente.
    perform pg_temp.expect_document_error(format('select public.documento_transicionar(%L,%L,%L)',
      (select id from qa_documento),'invalid','Tentativa externa'),'42501');
    perform pg_temp.expect_document_error($q$select public.documento_transicionar('ffffffff-ffff-ffff-ffff-ffffffffffff','invalid','Tentativa externa')$q$,'42501');
    reset role;
  end loop;
end
$block$;

select set_config('request.jwt.claim.sub','bd000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"bd000000-0000-0000-0000-000000000001","role":"authenticated"}',true);

-- Revogar perfil, membership, identidade ou tenant invalida imediatamente cada RPC.
do $block$
declare scenario text; cmd record;
begin
  foreach scenario in array array['perfil','membership','identidade','empresa'] loop
    if scenario='perfil' then update public.perfis set ativo=false where id='bd400000-0000-0000-0000-000000000001';
    elsif scenario='membership' then update public.usuario_empresas set status='bloqueado' where id='bd300000-0000-0000-0000-000000000001';
    elsif scenario='identidade' then update public.usuarios set ativo=false where id='bd000000-0000-0000-0000-000000000001';
    else update public.empresas set ativo=false where id='bd100000-0000-0000-0000-000000000001'; end if;
    set local role authenticated;
    for cmd in select * from qa_document_calls loop perform pg_temp.expect_document_error(cmd.sql,'42501'); end loop;
    perform pg_temp.expect_document_error($q$select * from public.documentos_listar('bd100000-0000-0000-0000-000000000001',null)$q$,'42501');
    reset role;
    update public.perfis set ativo=true where id='bd400000-0000-0000-0000-000000000001';
    update public.usuario_empresas set status='ativo' where id='bd300000-0000-0000-0000-000000000001';
    update public.usuarios set ativo=true where id='bd000000-0000-0000-0000-000000000001';
    update public.empresas set ativo=true where id='bd100000-0000-0000-0000-000000000001';
  end loop;
end
$block$;

-- Cada estado comercial bloqueado aplica-se a TODAS as mutacoes; consulta permanece.
do $block$
declare commercial text; cmd record;
begin
  foreach commercial in array array['past_due','paused','canceled','expired','trialing'] loop
    update public.empresa_assinaturas set status=commercial
    where empresa_id='bd100000-0000-0000-0000-000000000001';
    set local role authenticated;
    for cmd in select * from qa_document_calls loop perform pg_temp.expect_document_error(cmd.sql,'42501'); end loop;
    if not exists (select 1 from public.documento_historico((select id from qa_documento))) then
      raise exception 'readonly lost historical evidence';
    end if;
    reset role;
  end loop;
end
$block$;
update public.empresa_assinaturas set status='active'
where empresa_id='bd100000-0000-0000-0000-000000000001';

set local role authenticated;
do $block$
declare doc uuid := (select id from qa_documento); draft uuid; cmd record;
begin
  select documento_id into strict draft from public.documentos_listar('bd100000-0000-0000-0000-000000000001',null) where codigo='POP-MATRIX';
  -- Tenant/unidade adulterada, validacoes de entrada, OLD/NEW invalidos, versao stale.
  perform pg_temp.expect_document_error($q$select public.documento_criar('bd100000-0000-0000-0000-000000000002',null,'POP-X','Cross tenant','POP','',null)$q$,'42501');
  perform pg_temp.expect_document_error($q$select public.documento_criar('bd100000-0000-0000-0000-000000000001','bd200000-0000-0000-0000-000000000002','POP-X','Wrong unit','POP','',null)$q$,'23514');
  perform pg_temp.expect_document_error(format($q$select public.documento_rascunho_atualizar(%L,'bd200000-0000-0000-0000-000000000002','Wrong unit','POP','',null)$q$,draft),'23514');
  perform pg_temp.expect_document_error(format($q$select public.documento_rascunho_atualizar(%L,null,'Change published','POP','',null)$q$,doc),'23514');
  perform pg_temp.expect_document_error(format($q$select public.documento_transicionar(%L,'aprovado','Pular etapas')$q$,draft),'23514');
  perform pg_temp.expect_document_error(format($q$select public.documento_transicionar(%L,'em_revisao','x')$q$,draft),'22023');
  perform pg_temp.expect_document_error(format($q$select public.documento_iniciar_revisao(%L,'Revisao invalida',null)$q$,draft),'23514');
  perform pg_temp.expect_document_error(format($q$select public.documento_iniciar_revisao(%L,'x',null)$q$,doc),'22023');
  perform pg_temp.expect_document_error(format($q$select public.documento_criar('bd100000-0000-0000-0000-000000000001',null,'POP-MATRIX','Codigo duplicado','POP','',null)$q$),'23505');
  for cmd in select * from qa_document_calls where name<>'criar' loop
    -- O argumento opcional tem o mesmo nome nas tres RPCs; chamada nomeada apos os posicionais.
    perform pg_temp.expect_document_error(left(cmd.sql,length(cmd.sql)-1)||$q$,p_versao_id=>'ffffffff-ffff-ffff-ffff-ffffffffffff')$q$,'40001');
    perform pg_temp.expect_document_error(replace(cmd.sql,case when cmd.name='revisar' then doc::text else draft::text end,'ffffffff-ffff-ffff-ffff-ffffffffffff'),'42501');
  end loop;
end
$block$;
reset role;

-- Falha injetada no ultimo elo da transacao deve desfazer documentos, versoes E auditoria.
create function pg_temp.reject_document_audit() returns trigger language plpgsql as $fn$
begin raise exception using errcode='P0001', message='Injected document audit failure'; end
$fn$;
create trigger qa_reject_document_audit before insert on public.auditoria_eventos
for each row when (new.entidade='documento') execute function pg_temp.reject_document_audit();
set local role authenticated;
do $block$
declare cmd record;
begin
  for cmd in select * from qa_document_calls loop perform pg_temp.expect_document_error(cmd.sql,'P0001'); end loop;
end
$block$;
reset role;
-- Nenhuma tentativa negativa ou falha na auditoria pode deixar estado parcial.
do $block$
declare v_state jsonb;
begin
  select jsonb_build_object(
    'docs',(select jsonb_agg(to_jsonb(d) order by id) from public.documentos d),
    'versions',(select jsonb_agg(to_jsonb(v) order by id) from public.documento_versoes v),
    'audit',(select jsonb_agg(to_jsonb(a) order by id) from public.auditoria_eventos a)) into v_state;
  if v_state is distinct from (select state from qa_document_baseline) then raise exception 'negative or failed mutation left partial state'; end if;
  if not exists (select 1 from public.auditoria_eventos where registro_id=(select id from qa_documento)
      and acao='documento.versao_substituida' and antes->>'status'='vigente' and depois->>'status'='obsoleto'
      and contexto->>'substituida_por' is not null) then raise exception 'automatic obsolescence audit missing'; end if;
end
$block$;
drop trigger qa_reject_document_audit on public.auditoria_eventos;

-- Permissoes por fase: editar nao aprova/publica; aprovar nao edita/revisa.
set local role authenticated;
select public.documento_criar('bd100000-0000-0000-0000-000000000001',null,'POP-APPROVAL','Documento de aprovacao','POP','Aprovacao',null);
select public.documento_transicionar(documento_id,'em_revisao','Encaminhamento tecnico')
from public.documentos_listar('bd100000-0000-0000-0000-000000000001',null) where codigo='POP-APPROVAL';
select public.documento_transicionar(documento_id,'aguardando_aprovacao','Revisao concluida')
from public.documentos_listar('bd100000-0000-0000-0000-000000000001',null) where codigo='POP-APPROVAL';
reset role;
delete from public.perfil_permissoes where perfil_id='bd400000-0000-0000-0000-000000000001'
  and permissao_id=(select id from public.permissoes where codigo='documentos.aprovar');
set local role authenticated;
select pg_temp.expect_document_error(format('select public.documento_transicionar(%L,%L,%L)',documento_id,'aprovado','Aprovar sem permissao'),'42501')
from public.documentos_listar('bd100000-0000-0000-0000-000000000001',null) where codigo='POP-APPROVAL';
select pg_temp.expect_document_error(format('select public.documento_transicionar(%L,%L,%L)',id,'obsoleto','Obsoletar sem permissao'),'42501') from qa_documento;
reset role;
insert into public.perfil_permissoes(perfil_id,permissao_id) select 'bd400000-0000-0000-0000-000000000001',id from public.permissoes where codigo='documentos.aprovar';
delete from public.perfil_permissoes where perfil_id='bd400000-0000-0000-0000-000000000001'
  and permissao_id=(select id from public.permissoes where codigo='documentos.editar');
set local role authenticated;
do $block$
declare cmd record;
begin
  for cmd in select * from qa_document_calls where name in ('editar','transicionar','revisar') loop
    perform pg_temp.expect_document_error(cmd.sql,'42501');
  end loop;
end
$block$;
select public.documento_transicionar(documento_id,'aprovado','Aprovacao por papel especifico')
from public.documentos_listar('bd100000-0000-0000-0000-000000000001',null) where codigo='POP-APPROVAL';
reset role;
delete from public.perfil_permissoes where perfil_id='bd400000-0000-0000-0000-000000000001'
  and permissao_id=(select id from public.permissoes where codigo='documentos.aprovar');
set local role authenticated;
select pg_temp.expect_document_error(format('select public.documento_transicionar(%L,%L,%L)',documento_id,'vigente','Publicar sem permissao'),'42501')
from public.documentos_listar('bd100000-0000-0000-0000-000000000001',null) where codigo='POP-APPROVAL';
reset role;
insert into public.perfil_permissoes(perfil_id,permissao_id) select 'bd400000-0000-0000-0000-000000000001',id from public.permissoes where codigo in ('documentos.editar','documentos.aprovar');

-- Publicacao v3 com falha APOS obsolescencia e auditoria de v2 deve reverter tudo.
set local role authenticated;
select public.documento_iniciar_revisao(id,'Terceira revisao controlada',null) from qa_documento;
select public.documento_transicionar(id,'em_revisao','Terceira revisao enviada') from qa_documento;
select public.documento_transicionar(id,'aguardando_aprovacao','Terceira revisao concluida') from qa_documento;
select public.documento_transicionar(id,'aprovado','Terceira revisao aprovada') from qa_documento;
reset role;
truncate qa_document_baseline;
insert into qa_document_baseline select jsonb_build_object(
  'docs',(select jsonb_agg(to_jsonb(d) order by id) from public.documentos d),
  'versions',(select jsonb_agg(to_jsonb(v) order by id) from public.documento_versoes v),
  'audit',(select jsonb_agg(to_jsonb(a) order by id) from public.auditoria_eventos a));
create trigger qa_reject_document_publish before insert on public.auditoria_eventos
for each row when (new.entidade='documento' and new.acao='documento.status_alterado') execute function pg_temp.reject_document_audit();
set local role authenticated;
select pg_temp.expect_document_error(format('select public.documento_transicionar(%L,%L,%L)',id,'vigente','Publicacao deve reverter'),'P0001') from qa_documento;
reset role;
do $block$
declare state jsonb;
begin
  select jsonb_build_object(
    'docs',(select jsonb_agg(to_jsonb(d) order by id) from public.documentos d),
    'versions',(select jsonb_agg(to_jsonb(v) order by id) from public.documento_versoes v),
    'audit',(select jsonb_agg(to_jsonb(a) order by id) from public.auditoria_eventos a)) into state;
  if state is distinct from (select b.state from qa_document_baseline b) then raise exception 'publication failure did not restore old/current versions and audit'; end if;
end
$block$;
drop trigger qa_reject_document_publish on public.auditoria_eventos;
set local role authenticated;
select public.documento_transicionar(id,'vigente','Publicacao consolidada') from qa_documento;
reset role;

-- Membership secundario usa apenas RBAC e assinatura do tenant alvo, nao o legado primario.
insert into public.usuario_empresas(id,usuario_id,empresa_id,unidade_id,status,is_owner) values
('bd300000-0000-0000-0000-000000000004','bd000000-0000-0000-0000-000000000001','bd100000-0000-0000-0000-000000000002','bd200000-0000-0000-0000-000000000002','ativo',false);
insert into public.usuario_empresa_perfis(usuario_empresa_id,perfil_id) values
('bd300000-0000-0000-0000-000000000004','bd400000-0000-0000-0000-000000000003');
update public.empresa_assinaturas set status='expired' where empresa_id='bd100000-0000-0000-0000-000000000001';
-- Claims-only JWT deve funcionar com subject legado vazio.
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
select public.documento_criar('bd100000-0000-0000-0000-000000000002',null,'POP-SECONDARY','Documento secundario','POP','Secundario',null);
reset role;
update public.empresa_assinaturas set status='active' where empresa_id='bd100000-0000-0000-0000-000000000001';
insert into public.empresa_assinaturas(empresa_id,status) values('bd100000-0000-0000-0000-000000000002','expired');
set local role authenticated;
select public.documento_criar('bd100000-0000-0000-0000-000000000001',null,'POP-PRIMARY','Documento primario','POP','Primario',null);
select pg_temp.expect_document_error($q$select public.documento_criar('bd100000-0000-0000-0000-000000000002',null,'POP-SECONDARY-X','Bloqueado secundario','POP','',null)$q$,'42501');
reset role;
-- Revogar so perfil B nao remove A nem aproveita permissoes do primario em B.
delete from public.usuario_empresa_perfis where usuario_empresa_id='bd300000-0000-0000-0000-000000000004';
set local role authenticated;
select pg_temp.expect_document_error($q$select * from public.documentos_listar('bd100000-0000-0000-0000-000000000002',null)$q$,'42501');
select pg_temp.expect_document_error('select * from public.documentos','42501');
select pg_temp.expect_document_error('select * from public.documento_versoes','42501');
reset role;

do $block$
declare sig text; role_name text;
begin
  foreach sig in array array['public.documentos_listar(uuid,uuid)','public.documento_historico(uuid)',
    'public.documento_criar(uuid,uuid,text,text,text,text,date)',
    'public.documento_rascunho_atualizar(uuid,uuid,text,text,text,date,uuid)',
    'public.documento_transicionar(uuid,text,text,uuid)',
    'public.documento_iniciar_revisao(uuid,text,date,uuid)'] loop
    if not has_function_privilege('authenticated',sig,'EXECUTE') then raise exception 'Missing authenticated EXECUTE %',sig; end if;
    foreach role_name in array array['anon','service_role'] loop
      if has_function_privilege(role_name,sig,'EXECUTE') then raise exception 'Unexpected % EXECUTE %',role_name,sig; end if;
    end loop;
  end loop;
end
$block$;
select 'PASS: document adversarial matrix covers all writes, foreign targets, roles/membership revocation, inactive tenant, read-only lifecycle, snapshots, audit, stale versions, rollback and secondary membership' as result;
rollback;
