with documents as (
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
   =array['20260916222814','20260916223052','20260917114644','20260918121022','20260918121032','20260918183533','20260918183540','20260918183644','20260918183653','20260918183707','20260918183715','20260923171840','20260924125456','20260928112650','20260928112818','20260928112903','20260928113214','20260928113241','20260928115436','20260928122912','20260928142149','20260928163955','20261013140933','20261013140938','20261013140943','20261013145027','20261013150027','20261013173500','20261013180000','20261014124000','20261015203000','20261029160000']::text[] as historico_exato,
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
     from public.permissoes where codigo like 'documentos.%') as permissoes_documentais
), admin_functions as (
 select p.*,n.nspname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('private','public') and p.proname in('admin_contexto_ler','admin_usuario_status_tenant','admin_usuario_unidade_tenant',
 'admin_usuario_perfil_tenant','admin_empresa_tenant','admin_unidade_tenant','admin_setor_tenant','admin_perfil_tenant')
), legacy_closed as (
 select p.* from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname in
 ('empresa_leitura_usuarios','empresa_gestao_perfis','empresa_convite_usuarios','empresa_estrutura_admin','empresa_leitura_auditoria',
 'admin_usuario_alterar_status','admin_usuario_alterar_unidade','admin_usuario_alterar_perfil','admin_empresa_atualizar',
 'admin_unidade_salvar','admin_setor_salvar','admin_perfil_criar','admin_perfil_atualizar')
)
, retired_invites as (
 select p.* from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('private','public')
 and p.proname in('admin_usuario_vincular_convite','admin_usuario_vincular_convite_tenant')
)

select documents.*,
 (select count(*)=16 and bool_and(coalesce(p.proconfig,'{}'::text[]) @> array['search_path=""'])
   and bool_and(case when p.nspname='private' then p.prosecdef and p.proowner='bpf_tenant_admin'::regrole else not p.prosecdef end)
   and bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE'))
   and bool_and(not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE'))
   from admin_functions p)
 and (select count(*)=13 and bool_and(p.prosecdef and p.proconfig @> array['search_path=""']::text[]
   and pg_get_userbyid(p.proowner)=case when p.proname like 'empresa_%' then 'bpf_authz_reader' else 'bpf_admin_writer' end
   and has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE')
   and not has_function_privilege('service_role',p.oid,'EXECUTE')) from legacy_closed p)
 and not exists(select 1 from legacy_closed p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0)
 and (select count(*)=4 and bool_and(not has_function_privilege('authenticated',p.oid,'EXECUTE')
   and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE')) from retired_invites p)
 and not exists(select 1 from retired_invites p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0) as administracao_contratos,
 (select count(*)=1 and bool_and(not rolcanlogin and not rolinherit and not rolsuper and not rolbypassrls)
   from pg_roles where rolname='bpf_tenant_admin')
   and not pg_has_role('authenticated','bpf_tenant_admin','SET')
   and not pg_has_role('postgres','bpf_tenant_admin','SET')
   and not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relname in('usuarios','usuario_perfis')
     and has_table_privilege('bpf_tenant_admin',c.oid,'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))
   and not exists(select 1 from pg_attribute a where a.attrelid in('public.usuarios'::regclass,'public.usuario_perfis'::regclass)
     and a.attnum>0 and not a.attisdropped
     and has_column_privilege('bpf_tenant_admin',a.attrelid,a.attname,'INSERT,UPDATE,REFERENCES')) as administracao_role,
 (select count(*)=10 and bool_and(relrowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname in('usuarios','empresas','unidades','setores','perfis','permissoes',
   'perfil_permissoes','usuario_empresas','usuario_empresa_perfis','auditoria_eventos'))
 and (select count(*)=4 and bool_and(not p.polpermissive and p.polcmd='r' and p.polroles=array['authenticated'::regrole::oid]
   and p.polwithcheck is null and md5(regexp_replace(replace(replace(pg_get_expr(p.polqual,p.polrelid),'public.',''),'private.',''),'\s+','','g'))=e.hash
   and exists(select 1 from pg_depend d where d.classid='pg_policy'::regclass and d.objid=p.oid and d.refclassid='pg_proc'::regclass and d.refobjid=to_regprocedure('private.primary_visible_empresa()'))
   and (c.relname<>'setores' or exists(select 1 from pg_depend d where d.classid='pg_policy'::regclass and d.objid=p.oid and d.refclassid='pg_class'::regclass and d.refobjid='public.unidades'::regclass)))
   from (values ('empresas','5148e012d01c99726624b73af85c0f04'),('perfis','2106fe59761c4bca9adb24d2e535c692'),('setores','a7f83b793c786c50014d32b7d31559f4'),('unidades','3a5de2a711a1a27e9ca36d41937dbbee')) e(name,hash)
   join pg_class c on c.relname=e.name and c.relnamespace='public'::regnamespace
   join pg_policy p on p.polrelid=c.oid and p.polname='tenant_admin_primary_guard')
 and coalesce((select p.prosecdef and p.provolatile='s' and p.prorettype='uuid'::regtype and p.proconfig @> array['search_path=""']::text[]
   and pg_get_userbyid(p.proowner)='postgres' and md5(replace(p.prosrc,E'\r\n',E'\n'))='2c00f1010f99ed954a472835381b6ee1'
   and has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE')
   and not has_function_privilege('service_role',p.oid,'EXECUTE')
   and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0)
   from pg_proc p where p.oid=to_regprocedure('private.primary_visible_empresa()')),false) as administracao_rls
from documents;
