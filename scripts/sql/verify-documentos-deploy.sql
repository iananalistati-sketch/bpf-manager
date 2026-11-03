-- Somente metadados: nao consulta dados de clientes nem executa DDL/DML.
with
expected_rpcs(signature) as (values
 ('public.documentos_listar(uuid,uuid)'),
 ('public.documento_historico(uuid)'),
 ('public.documento_criar(uuid,uuid,text,text,text,text,date)'),
 ('public.documento_rascunho_atualizar(uuid,uuid,text,text,text,date,uuid)'),
 ('public.documento_transicionar(uuid,text,text,uuid)'),
 ('public.documento_iniciar_revisao(uuid,text,date,uuid)')
),
rpcs as (select p.* from expected_rpcs e left join pg_proc p on p.oid=to_regprocedure(e.signature)),
expected_helpers(signature) as (values
 ('private.tenant_tem_permissao(uuid,text)'),
 ('private.assert_tenant_workspace_write_allowed(uuid)')
),
helpers as (select p.* from expected_helpers e left join pg_proc p on p.oid=to_regprocedure(e.signature)),
clients(name) as (values ('anon'),('authenticated'),('service_role')),
doc_tables as (select c.* from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relname in ('documentos','documento_versoes') and c.relkind='r')
select
 (select array_agg(version order by version) from supabase_migrations.schema_migrations)
   =array['20260916222814','20260916223052','20260917114644','20260918121022','20260918121032','20260918183533','20260918183540','20260918183644','20260918183653','20260918183707','20260918183715','20260923171840','20260924125456','20260928112650','20260928112818','20260928112903','20260928113214','20260928113241','20260928115436','20260928122912','20260928142149','20260928163955','20261013140933','20261013140938','20261013140943','20261013145027','20261013150027','20261013173500','20261013180000','20261014124000','20261015203000']::text[] as historico_exato,
 coalesce((select count(*)=2 and bool_and(c.relrowsecurity and pg_get_userbyid(c.relowner)='postgres') from doc_tables c),false)
   and not exists(select 1 from doc_tables c cross join clients r
     where has_table_privilege(r.name,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))
   and not exists(select 1 from doc_tables c join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped cross join clients r
     where has_column_privilege(r.name,c.oid,a.attname,'SELECT,INSERT,UPDATE,REFERENCES')) as tabelas_fechadas,
 coalesce((select count(oid)=6 and bool_and(prosecdef and pg_get_userbyid(proowner)='postgres'
     and proconfig @> array['search_path=""']::text[]
     and has_function_privilege('authenticated',oid,'EXECUTE')
     and not has_function_privilege('anon',oid,'EXECUTE')
     and not has_function_privilege('service_role',oid,'EXECUTE')) from rpcs),false)
   and (select count(*)=6 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname in ('documentos_listar','documento_historico','documento_criar','documento_rascunho_atualizar','documento_transicionar','documento_iniciar_revisao'))
   and not exists(select 1 from rpcs p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0)
   and to_regprocedure('public.documento_rascunho_atualizar(uuid,uuid,text,text,text,date)') is null
   and to_regprocedure('public.documento_transicionar(uuid,text,text)') is null
   and to_regprocedure('public.documento_iniciar_revisao(uuid,text,date)') is null as rpcs_finais,
 coalesce((select count(oid)=2 and bool_and(prosecdef and pg_get_userbyid(proowner)='postgres'
     and proconfig @> array['search_path=""']::text[]) from helpers),false)
   and not exists(select 1 from helpers p cross join clients r where has_function_privilege(r.name,p.oid,'EXECUTE'))
   and not exists(select 1 from helpers p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0) as helpers_fechados,
 (select count(*)=3 and bool_and((a.attname='unidade_id' and a.atttypid='uuid'::regtype)
     or (a.attname in ('titulo','tipo') and a.atttypid='text'::regtype and a.attnotnull))
     from pg_attribute a where a.attrelid=to_regclass('public.documento_versoes')
     and a.attname in ('titulo','tipo','unidade_id') and not a.attisdropped)
   and coalesce((select proargnames @> array['vigente_numero','vigente_revisao_prevista_em']::text[] from pg_proc where oid=to_regprocedure('public.documentos_listar(uuid,uuid)')),false)
   and coalesce((select proargnames @> array['titulo','tipo','unidade_id','descricao','aprovado_em','obsoleto_em']::text[] from pg_proc where oid=to_regprocedure('public.documento_historico(uuid)')),false)
   and coalesce((select proargnames[7]='p_versao_id' and pronargdefaults=1 from pg_proc where oid=to_regprocedure('public.documento_rascunho_atualizar(uuid,uuid,text,text,text,date,uuid)')),false)
   and coalesce((select proargnames[4]='p_versao_id' and pronargdefaults=1 from pg_proc where oid=to_regprocedure('public.documento_transicionar(uuid,text,text,uuid)')),false)
   and coalesce((select proargnames[4]='p_versao_id' and pronargdefaults=2 from pg_proc where oid=to_regprocedure('public.documento_iniciar_revisao(uuid,text,date,uuid)')),false) as contratos_versionados,
 exists(select 1 from pg_constraint where conrelid=to_regclass('public.documentos')
     and conname='documentos_unidade_empresa_fkey' and contype='f' and convalidated and confrelid=to_regclass('public.unidades')
     and conkey=array[(select attnum from pg_attribute where attrelid=to_regclass('public.documentos') and attname='unidade_id'),
                     (select attnum from pg_attribute where attrelid=to_regclass('public.documentos') and attname='empresa_id')]::smallint[]
     and confkey=array[(select attnum from pg_attribute where attrelid=to_regclass('public.unidades') and attname='id'),
                      (select attnum from pg_attribute where attrelid=to_regclass('public.unidades') and attname='empresa_id')]::smallint[])
   and exists(select 1 from pg_constraint c join pg_index i on i.indexrelid=c.conindid
     where c.conrelid=to_regclass('public.documento_versoes') and c.conname='documento_versoes_documento_numero_key'
       and c.contype='u' and i.indisunique and i.indisvalid and i.indisready and i.indnkeyatts=2 and i.indnatts=2
       and c.conkey=array[(select attnum from pg_attribute where attrelid=c.conrelid and attname='documento_id'),
                          (select attnum from pg_attribute where attrelid=c.conrelid and attname='numero')]::smallint[]
       and i.indkey[0]=(select attnum from pg_attribute where attrelid=c.conrelid and attname='documento_id')
       and i.indkey[1]=(select attnum from pg_attribute where attrelid=c.conrelid and attname='numero'))
   and exists(select 1 from pg_index i where i.indexrelid=to_regclass('public.idx_documento_versoes_um_vigente')
     and i.indrelid=to_regclass('public.documento_versoes') and i.indisunique and i.indisvalid and i.indisready
     and i.indnkeyatts=1 and i.indnatts=1
     and i.indkey[0]=(select attnum from pg_attribute where attrelid=i.indrelid and attname='documento_id')
     and pg_get_expr(i.indpred,i.indrelid)='(status = ''vigente''::text)') as integridade_documental,
 coalesce((select count(*)=5 and bool_and(not rolcanlogin and not rolinherit and not rolsuper and not rolbypassrls
     and not pg_has_role('authenticated',oid,'SET') and not pg_has_role('postgres',oid,'SET'))
     from pg_roles where rolname in ('bpf_authz_reader','bpf_admin_writer','bpf_tenant_reader','bpf_entitlement_reader','bpf_plan_enforcer')),false) as roles_restritas,
 (select count(*)=4 and bool_and(codigo in ('documentos.visualizar','documentos.criar','documentos.editar','documentos.aprovar'))
     from public.permissoes where codigo like 'documentos.%') as permissoes_documentais;
