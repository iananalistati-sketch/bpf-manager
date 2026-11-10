-- Pending32 recovery: require clean, inspected state31 before the first DDL.
-- The marked SELECT equals the separately hashed read-only query.
do $readiness$
declare v_failed text[];
begin
 select array_agg(key order by key) into v_failed from (
-- BEGIN_READINESS_QUERY
-- Read-only state31 contract. Copied verbatim into migration32 before its first DDL.
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
     from public.permissoes where codigo like 'documentos.%') as permissoes_documentais
), expected as (
 select * from jsonb_to_recordset($baseline$[
{"signature":"private.admin_empresa_atualizar(text, text, text, text)","owner":"bpf_admin_writer","hash":"a2438d8bb82f13844be3a8e43a2c7ad8","prosecdef":true,"proconfig":["search_path=\"\""],"language":"plpgsql","returntype":"void","proretset":false,"proargnames":["p_razao_social","p_nome_fantasia","p_cnpj","p_justificativa"],"pronargdefaults":0,"proargmodes":null,"allargtypes":[],"defaults":null,"provolatile":"v","proparallel":"u","proisstrict":false,"proleakproof":false,"prokind":"f","public_execute":true,"execute":{"anon":true,"postgres":true,"service_role":true,"authenticated":true,"bpf_admin_writer":true,"bpf_authz_reader":true,"bpf_plan_enforcer":true,"bpf_tenant_reader":true,"bpf_entitlement_reader":true}},
{"signature":"private.admin_perfil_atualizar(uuid, text, text, boolean, uuid[], text)","owner":"bpf_admin_writer","hash":"908d48d302e59d18dfcdb4bb4fad8440","prosecdef":true,"proconfig":["search_path=\"\""],"language":"plpgsql","returntype":"void","proretset":false,"proargnames":["p_perfil_id","p_nome","p_descricao","p_ativo","p_permissao_ids","p_justificativa"],"pronargdefaults":0,"proargmodes":null,"allargtypes":[],"defaults":null,"provolatile":"v","proparallel":"u","proisstrict":false,"proleakproof":false,"prokind":"f","public_execute":true,"execute":{"anon":true,"postgres":true,"service_role":true,"authenticated":true,"bpf_admin_writer":true,"bpf_authz_reader":true,"bpf_plan_enforcer":true,"bpf_tenant_reader":true,"bpf_entitlement_reader":true}},
{"signature":"private.admin_perfil_criar(text, text, uuid[], text)","owner":"bpf_admin_writer","hash":"f4c130dd70acac646fe63c35954ab89c","prosecdef":true,"proconfig":["search_path=\"\""],"language":"plpgsql","returntype":"uuid","proretset":false,"proargnames":["p_nome","p_descricao","p_permissao_ids","p_justificativa"],"pronargdefaults":0,"proargmodes":null,"allargtypes":[],"defaults":null,"provolatile":"v","proparallel":"u","proisstrict":false,"proleakproof":false,"prokind":"f","public_execute":true,"execute":{"anon":true,"postgres":true,"service_role":true,"authenticated":true,"bpf_admin_writer":true,"bpf_authz_reader":true,"bpf_plan_enforcer":true,"bpf_tenant_reader":true,"bpf_entitlement_reader":true}},
{"signature":"private.admin_setor_salvar(uuid, uuid, text, text, boolean, text)","owner":"bpf_admin_writer","hash":"1b025bb47c4ffbaf3f9d0136b71f79b8","prosecdef":true,"proconfig":["search_path=\"\""],"language":"plpgsql","returntype":"uuid","proretset":false,"proargnames":["p_setor_id","p_unidade_id","p_nome","p_codigo","p_ativo","p_justificativa"],"pronargdefaults":0,"proargmodes":null,"allargtypes":[],"defaults":null,"provolatile":"v","proparallel":"u","proisstrict":false,"proleakproof":false,"prokind":"f","public_execute":true,"execute":{"anon":true,"postgres":true,"service_role":true,"authenticated":true,"bpf_admin_writer":true,"bpf_authz_reader":true,"bpf_plan_enforcer":true,"bpf_tenant_reader":true,"bpf_entitlement_reader":true}},
{"signature":"private.admin_unidade_salvar(uuid, text, text, boolean, text)","owner":"bpf_admin_writer","hash":"bf299bcfdd5c4cbe6883558317df012b","prosecdef":true,"proconfig":["search_path=\"\""],"language":"plpgsql","returntype":"uuid","proretset":false,"proargnames":["p_unidade_id","p_nome","p_codigo","p_ativo","p_justificativa"],"pronargdefaults":0,"proargmodes":null,"allargtypes":[],"defaults":null,"provolatile":"v","proparallel":"u","proisstrict":false,"proleakproof":false,"prokind":"f","public_execute":true,"execute":{"anon":true,"postgres":true,"service_role":true,"authenticated":true,"bpf_admin_writer":true,"bpf_authz_reader":true,"bpf_plan_enforcer":true,"bpf_tenant_reader":true,"bpf_entitlement_reader":true}},
{"signature":"private.admin_usuario_alterar_perfil(uuid, uuid, text, text)","owner":"bpf_admin_writer","hash":"bb4ea0050464dd3ffd3d50f0e1d04831","prosecdef":true,"proconfig":["search_path=\"\""],"language":"plpgsql","returntype":"void","proretset":false,"proargnames":["p_usuario_id","p_perfil_id","p_acao","p_justificativa"],"pronargdefaults":0,"proargmodes":null,"allargtypes":[],"defaults":null,"provolatile":"v","proparallel":"u","proisstrict":false,"proleakproof":false,"prokind":"f","public_execute":true,"execute":{"anon":true,"postgres":true,"service_role":true,"authenticated":true,"bpf_admin_writer":true,"bpf_authz_reader":true,"bpf_plan_enforcer":true,"bpf_tenant_reader":true,"bpf_entitlement_reader":true}},
{"signature":"private.admin_usuario_alterar_status(uuid, text, text)","owner":"bpf_admin_writer","hash":"1a552f6f2dbb2e4b2a71f24b76abf996","prosecdef":true,"proconfig":["search_path=\"\""],"language":"plpgsql","returntype":"void","proretset":false,"proargnames":["p_usuario_id","p_status","p_justificativa"],"pronargdefaults":0,"proargmodes":null,"allargtypes":[],"defaults":null,"provolatile":"v","proparallel":"u","proisstrict":false,"proleakproof":false,"prokind":"f","public_execute":true,"execute":{"anon":true,"postgres":true,"service_role":true,"authenticated":true,"bpf_admin_writer":true,"bpf_authz_reader":true,"bpf_plan_enforcer":true,"bpf_tenant_reader":true,"bpf_entitlement_reader":true}},
{"signature":"private.admin_usuario_alterar_unidade(uuid, uuid, text)","owner":"bpf_admin_writer","hash":"e6e829b1000731ef5f3758d8618aec03","prosecdef":true,"proconfig":["search_path=\"\""],"language":"plpgsql","returntype":"void","proretset":false,"proargnames":["p_usuario_id","p_unidade_id","p_justificativa"],"pronargdefaults":0,"proargmodes":null,"allargtypes":[],"defaults":null,"provolatile":"v","proparallel":"u","proisstrict":false,"proleakproof":false,"prokind":"f","public_execute":true,"execute":{"anon":true,"postgres":true,"service_role":true,"authenticated":true,"bpf_admin_writer":true,"bpf_authz_reader":true,"bpf_plan_enforcer":true,"bpf_tenant_reader":true,"bpf_entitlement_reader":true}},
{"signature":"private.ator_possui_permissao(uuid)","owner":"bpf_admin_writer","hash":"8b524a466f145824dda63b53aa64f7b0","prosecdef":false,"proconfig":["search_path=\"\""],"language":"sql","returntype":"boolean","proretset":false,"proargnames":["p_permissao_id"],"pronargdefaults":0,"proargmodes":null,"allargtypes":[],"defaults":null,"provolatile":"s","proparallel":"u","proisstrict":false,"proleakproof":false,"prokind":"f","public_execute":true,"execute":{"anon":true,"postgres":true,"service_role":true,"authenticated":true,"bpf_admin_writer":true,"bpf_authz_reader":true,"bpf_plan_enforcer":true,"bpf_tenant_reader":true,"bpf_entitlement_reader":true}},
{"signature":"private.consumo_plano_empresa(uuid)","owner":"bpf_plan_enforcer","hash":"5fa765b792a2dee6afff3eeaccaf21e9","prosecdef":true,"proconfig":["search_path=\"\""],"language":"sql","returntype":"record","proretset":true,"proargnames":["p_empresa_id","usuarios_ativos","unidades_ativas"],"pronargdefaults":0,"proargmodes":["i","t","t"],"allargtypes":["uuid","bigint","bigint"],"defaults":null,"provolatile":"s","proparallel":"u","proisstrict":false,"proleakproof":false,"prokind":"f","public_execute":false,"execute":{"anon":false,"postgres":false,"service_role":false,"authenticated":false,"bpf_admin_writer":false,"bpf_authz_reader":false,"bpf_plan_enforcer":true,"bpf_tenant_reader":false,"bpf_entitlement_reader":true}},
{"signature":"private.empresa_convite_usuarios()","owner":"bpf_authz_reader","hash":"76fa1a3fdac40b2ea5609921a3cd03e3","prosecdef":true,"proconfig":["search_path=\"\""],"language":"sql","returntype":"uuid","proretset":false,"proargnames":null,"pronargdefaults":0,"proargmodes":null,"allargtypes":[],"defaults":null,"provolatile":"s","proparallel":"u","proisstrict":false,"proleakproof":false,"prokind":"f","public_execute":true,"execute":{"anon":true,"postgres":true,"service_role":true,"authenticated":true,"bpf_admin_writer":true,"bpf_authz_reader":true,"bpf_plan_enforcer":true,"bpf_tenant_reader":true,"bpf_entitlement_reader":true}},
{"signature":"private.empresa_estrutura_admin()","owner":"bpf_authz_reader","hash":"d7402e38a6bffd55047638d25b2e288c","prosecdef":true,"proconfig":["search_path=\"\""],"language":"sql","returntype":"uuid","proretset":false,"proargnames":null,"pronargdefaults":0,"proargmodes":null,"allargtypes":[],"defaults":null,"provolatile":"s","proparallel":"u","proisstrict":false,"proleakproof":false,"prokind":"f","public_execute":true,"execute":{"anon":true,"postgres":true,"service_role":true,"authenticated":true,"bpf_admin_writer":true,"bpf_authz_reader":true,"bpf_plan_enforcer":true,"bpf_tenant_reader":true,"bpf_entitlement_reader":true}},
{"signature":"private.empresa_gestao_perfis()","owner":"bpf_authz_reader","hash":"616309186970969b4bb3312dc161e84e","prosecdef":true,"proconfig":["search_path=\"\""],"language":"sql","returntype":"uuid","proretset":false,"proargnames":null,"pronargdefaults":0,"proargmodes":null,"allargtypes":[],"defaults":null,"provolatile":"s","proparallel":"u","proisstrict":false,"proleakproof":false,"prokind":"f","public_execute":true,"execute":{"anon":true,"postgres":true,"service_role":true,"authenticated":true,"bpf_admin_writer":true,"bpf_authz_reader":true,"bpf_plan_enforcer":true,"bpf_tenant_reader":true,"bpf_entitlement_reader":true}},
{"signature":"private.empresa_leitura_auditoria()","owner":"bpf_authz_reader","hash":"356bf1b1843003d1273452995f1c7445","prosecdef":true,"proconfig":["search_path=\"\""],"language":"sql","returntype":"uuid","proretset":false,"proargnames":null,"pronargdefaults":0,"proargmodes":null,"allargtypes":[],"defaults":null,"provolatile":"s","proparallel":"u","proisstrict":false,"proleakproof":false,"prokind":"f","public_execute":true,"execute":{"anon":true,"postgres":true,"service_role":true,"authenticated":true,"bpf_admin_writer":true,"bpf_authz_reader":true,"bpf_plan_enforcer":true,"bpf_tenant_reader":true,"bpf_entitlement_reader":true}},
{"signature":"private.empresa_leitura_usuarios()","owner":"bpf_authz_reader","hash":"6f80897885ee44b0402b420364fe2e5f","prosecdef":true,"proconfig":["search_path=\"\""],"language":"sql","returntype":"uuid","proretset":false,"proargnames":null,"pronargdefaults":0,"proargmodes":null,"allargtypes":[],"defaults":null,"provolatile":"s","proparallel":"u","proisstrict":false,"proleakproof":false,"prokind":"f","public_execute":false,"execute":{"anon":false,"postgres":false,"service_role":false,"authenticated":true,"bpf_admin_writer":true,"bpf_authz_reader":true,"bpf_plan_enforcer":false,"bpf_tenant_reader":false,"bpf_entitlement_reader":false}},
{"signature":"private.existe_outro_admin_efetivo(uuid, uuid)","owner":"bpf_admin_writer","hash":"4a198ddae8ce8f178888a0b8ee9fb67b","prosecdef":false,"proconfig":["search_path=\"\""],"language":"sql","returntype":"boolean","proretset":false,"proargnames":["p_usuario_id","p_empresa_id"],"pronargdefaults":0,"proargmodes":null,"allargtypes":[],"defaults":null,"provolatile":"s","proparallel":"u","proisstrict":false,"proleakproof":false,"prokind":"f","public_execute":true,"execute":{"anon":true,"postgres":true,"service_role":true,"authenticated":true,"bpf_admin_writer":true,"bpf_authz_reader":true,"bpf_plan_enforcer":true,"bpf_tenant_reader":true,"bpf_entitlement_reader":true}},
{"signature":"private.usuario_admin_efetivo(uuid, uuid)","owner":"bpf_admin_writer","hash":"e48f6805ed7a8592b085a066ec0d6bae","prosecdef":false,"proconfig":["search_path=\"\""],"language":"sql","returntype":"boolean","proretset":false,"proargnames":["p_usuario_id","p_empresa_id"],"pronargdefaults":0,"proargmodes":null,"allargtypes":[],"defaults":null,"provolatile":"s","proparallel":"u","proisstrict":false,"proleakproof":false,"prokind":"f","public_execute":true,"execute":{"anon":true,"postgres":true,"service_role":true,"authenticated":true,"bpf_admin_writer":true,"bpf_authz_reader":true,"bpf_plan_enforcer":true,"bpf_tenant_reader":true,"bpf_entitlement_reader":true}},
{"signature":"private.validar_limite_membership()","owner":"bpf_plan_enforcer","hash":"366e681c2f0cf9cb779f58fcde1ffeaa","prosecdef":true,"proconfig":["search_path=\"\""],"language":"plpgsql","returntype":"trigger","proretset":false,"proargnames":null,"pronargdefaults":0,"proargmodes":null,"allargtypes":[],"defaults":null,"provolatile":"v","proparallel":"u","proisstrict":false,"proleakproof":false,"prokind":"f","public_execute":false,"execute":{"anon":false,"postgres":true,"service_role":false,"authenticated":false,"bpf_admin_writer":false,"bpf_authz_reader":false,"bpf_plan_enforcer":true,"bpf_tenant_reader":false,"bpf_entitlement_reader":false}},
{"signature":"private.validar_limite_usuario_legacy()","owner":"bpf_plan_enforcer","hash":"6bf058babbc82f69fbbc103f34d2ffb5","prosecdef":true,"proconfig":["search_path=\"\""],"language":"plpgsql","returntype":"trigger","proretset":false,"proargnames":null,"pronargdefaults":0,"proargmodes":null,"allargtypes":[],"defaults":null,"provolatile":"v","proparallel":"u","proisstrict":false,"proleakproof":false,"prokind":"f","public_execute":false,"execute":{"anon":false,"postgres":true,"service_role":false,"authenticated":false,"bpf_admin_writer":false,"bpf_authz_reader":false,"bpf_plan_enforcer":true,"bpf_tenant_reader":false,"bpf_entitlement_reader":false}},
{"signature":"public.admin_usuario_vincular_convite_server(uuid, uuid, uuid, uuid, uuid[], text)","owner":"postgres","hash":"a67829b81c76a533b31c803c9114102c","prosecdef":false,"proconfig":["search_path=\"\""],"language":"plpgsql","returntype":"void","proretset":false,"proargnames":["p_ator_id","p_empresa_id","p_usuario_id","p_unidade_id","p_perfil_ids","p_justificativa"],"pronargdefaults":0,"proargmodes":null,"allargtypes":[],"defaults":null,"provolatile":"v","proparallel":"u","proisstrict":false,"proleakproof":false,"prokind":"f","public_execute":false,"execute":{"anon":false,"postgres":true,"service_role":true,"authenticated":false,"bpf_admin_writer":false,"bpf_authz_reader":false,"bpf_plan_enforcer":false,"bpf_tenant_reader":false,"bpf_entitlement_reader":false}},
{"signature":"public.preparar_contratacao_server(uuid, uuid, text, text)","owner":"postgres","hash":"960721f68adc83180d041be95675f0f1","prosecdef":true,"proconfig":["search_path=\"\""],"language":"plpgsql","returntype":"record","proretset":true,"proargnames":["p_ator_id","p_empresa_id","p_plano_codigo","p_chave_idempotencia","contratacao_id","empresa_id","assinatura_id","plano_id","plano_codigo","status","expires_at"],"pronargdefaults":0,"proargmodes":["i","i","i","i","t","t","t","t","t","t","t"],"allargtypes":["uuid","uuid","text","text","uuid","uuid","uuid","uuid","text","text","timestamp with time zone"],"defaults":null,"provolatile":"v","proparallel":"u","proisstrict":false,"proleakproof":false,"prokind":"f","public_execute":false,"execute":{"anon":false,"postgres":true,"service_role":true,"authenticated":false,"bpf_admin_writer":false,"bpf_authz_reader":false,"bpf_plan_enforcer":false,"bpf_tenant_reader":false,"bpf_entitlement_reader":false}},
{"signature":"public.processar_evento_assinatura_server(uuid, text, text, text, text, text, text, text, text, timestamp with time zone, timestamp with time zone, timestamp with time zone, jsonb)","owner":"postgres","hash":"df78dc8a7acd1b99aa922829b40923e1","prosecdef":true,"proconfig":["search_path=\"\""],"language":"plpgsql","returntype":"record","proretset":true,"proargnames":["p_empresa_id","p_provedor","p_provedor_evento_id","p_tipo_evento","p_status_novo","p_plano_codigo","p_provedor_cliente_id","p_provedor_assinatura_id","p_provedor_preco_id","p_periodo_inicio","p_periodo_fim","p_ocorrido_em","p_metadata","assinatura_id","empresa_id","status","plano_id","evento_id","aplicado"],"pronargdefaults":8,"proargmodes":["i","i","i","i","i","i","i","i","i","i","i","i","i","t","t","t","t","t","t"],"allargtypes":["uuid","text","text","text","text","text","text","text","text","timestamp with time zone","timestamp with time zone","timestamp with time zone","jsonb","uuid","uuid","text","uuid","uuid","boolean"],"defaults":"NULL::text, NULL::text, NULL::text, NULL::text, NULL::timestamp with time zone, NULL::timestamp with time zone, NULL::timestamp with time zone, '{}'::jsonb","provolatile":"v","proparallel":"u","proisstrict":false,"proleakproof":false,"prokind":"f","public_execute":false,"execute":{"anon":false,"postgres":true,"service_role":true,"authenticated":false,"bpf_admin_writer":false,"bpf_authz_reader":false,"bpf_plan_enforcer":false,"bpf_tenant_reader":false,"bpf_entitlement_reader":false}}
]$baseline$::jsonb) as e(
 signature text,owner text,hash text,prosecdef boolean,proconfig text[],language text,returntype text,proretset boolean,
 proargnames text[],pronargdefaults integer,proargmodes text[],allargtypes text[],defaults text,
 provolatile text,proparallel text,proisstrict boolean,proleakproof boolean,prokind text,public_execute boolean,execute jsonb)
), actual as (
 select e.*,p.oid,p.proowner,p.proacl,pg_get_userbyid(p.proowner) actual_owner,
 md5(replace(p.prosrc,E'\r\n',E'\n')) actual_hash,
 p.prosecdef actual_secdef,p.proconfig actual_config,p.proretset actual_retset,p.proargnames actual_argnames,
 p.prorettype::regtype::text actual_return,(select l.lanname from pg_language l where l.oid=p.prolang) actual_language,
 p.pronargdefaults actual_argdefaults,p.proargmodes::text[] actual_argmodes,
 array(select format_type(t,NULL) from unnest(p.proallargtypes) t) actual_allargs,
 pg_get_expr(p.proargdefaults,0) actual_defaults,p.provolatile::text actual_volatile,p.proparallel::text actual_parallel,
 p.proisstrict actual_strict,p.proleakproof actual_leakproof,p.prokind::text actual_kind,
 exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0) actual_public,
 (select jsonb_object_agg(r.rolname,has_function_privilege(r.oid,p.oid,'EXECUTE')) from pg_roles r where e.execute ? r.rolname) actual_execute
 from expected e left join pg_proc p on p.oid=to_regprocedure(e.signature)
), tables as (
 select c.* from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public'
 and c.relkind='r' and c.relname in('empresas','unidades','setores','usuarios','perfis','permissoes','usuario_perfis',
 'perfil_permissoes','usuario_empresas','usuario_empresa_perfis','auditoria_eventos','empresa_planos','empresa_assinaturas','empresa_onboarding','saas_provisionamentos')
), clients as(select oid,rolname from pg_roles where rolname in('anon','authenticated'))
select documents.*,
 current_user='postgres' as executor_postgres,
 not exists(select 1 from pg_roles where rolname='bpf_tenant_admin')
 and not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('private','public') and p.proname in('admin_permissions','admin_scope_id','admin_assert','admin_has_other','admin_audit','admin_primary_empresa','primary_visible_empresa','assert_invite_tenant_write','admin_contexto_ler','admin_usuario_status_tenant','admin_usuario_unidade_tenant','admin_usuario_perfil_tenant','admin_empresa_tenant','admin_unidade_tenant','admin_setor_tenant','admin_perfil_tenant'))
 and not exists(select 1 from pg_policies where schemaname='public' and policyname like 'tenant_admin_%') as sem_objetos_32,
 coalesce((select count(*)=22 and bool_and(oid is not null and actual_owner=owner and actual_hash=hash and actual_secdef=prosecdef
 and actual_config is not distinct from proconfig and actual_retset=proretset and actual_argnames is not distinct from proargnames
 and actual_return=returntype and actual_language=language and actual_argdefaults=pronargdefaults
 and actual_argmodes is not distinct from proargmodes and actual_allargs=allargtypes and actual_defaults is not distinct from defaults
 and actual_volatile=provolatile and actual_parallel=proparallel and actual_strict=proisstrict and actual_leakproof=proleakproof and actual_kind=prokind) from actual),false)
 and not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname||'.'||p.proname in(select split_part(signature,'(',1) from expected)
 and p.oid not in(select oid from actual where oid is not null)) as funcoes_base_31,
 not exists(select 1 from actual a where a.actual_public and not a.public_execute)
 and not exists(select 1 from actual a cross join lateral jsonb_each(a.actual_execute) x where x.value='true'::jsonb and a.execute->x.key='false'::jsonb)
 and not exists(select 1 from actual a cross join lateral aclexplode(coalesce(a.proacl,acldefault('f',a.proowner))) g
   where g.grantee<>a.proowner and (g.is_grantable or (not a.public_execute and g.grantee<>0 and coalesce(a.execute->pg_get_userbyid(g.grantee),'false'::jsonb)<>'true'::jsonb))) as funcoes_acl_sem_ampliacao,
 coalesce((select md5(replace(replace(pg_get_viewdef(c.oid,true),E'\r\n',E'\n'),'public.',''))='f8d4c418587767ba36d0e5bf671ecc76'
 and c.reloptions @> array['security_invoker=true']::text[] and pg_get_userbyid(c.relowner)='postgres'
 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='v_meu_contexto' and c.relkind='v'),false) as view_base_31,
 coalesce((select count(*)=15 and bool_and(relrowsecurity and pg_get_userbyid(relowner)='postgres') from tables),false) as tabelas_rls,
 coalesce((select count(*)=5 and bool_and(not rolcanlogin and not rolinherit and not rolsuper and not rolcreaterole and not rolcreatedb and not rolreplication and not rolbypassrls
 and not has_schema_privilege(oid,'private','CREATE')
 and not pg_has_role('postgres',oid,'SET') and not pg_has_role('postgres',oid,'USAGE')
 and not pg_has_role('authenticated',oid,'SET') and not pg_has_role('authenticated',oid,'USAGE')
 and not pg_has_role('anon',oid,'SET') and not pg_has_role('anon',oid,'USAGE'))
 from pg_roles where rolname in('bpf_authz_reader','bpf_admin_writer','bpf_tenant_reader','bpf_plan_enforcer','bpf_entitlement_reader')),false)
 and not exists(select 1 from pg_roles r cross join clients c where (r.rolsuper or r.rolbypassrls or r.rolcreaterole or r.rolname in('postgres','service_role'))
   and (pg_has_role(c.oid,r.oid,'SET') or pg_has_role(c.oid,r.oid,'USAGE')))
 and not exists(select 1 from clients c where has_schema_privilege(c.oid,'public','CREATE') or has_schema_privilege(c.oid,'private','CREATE')) as roles_base_31,
 not exists(select 1 from tables t cross join clients r where has_table_privilege(r.oid,t.oid,'INSERT,UPDATE,DELETE,TRUNCATE'))
 and not exists(select 1 from tables t join pg_attribute a on a.attrelid=t.oid and a.attnum>0 and not a.attisdropped cross join clients r
 where has_column_privilege(r.oid,t.oid,a.attname,'INSERT,UPDATE')) as clientes_sem_escrita_direta,
 (select count(p.oid)=4 and bool_and(pg_get_userbyid(p.proowner)=e.owner)
 from (values('private.admin_usuario_vincular_convite(uuid,uuid,uuid[],text)','bpf_admin_writer'),
 ('private.admin_usuario_vincular_convite_tenant(uuid,uuid,uuid,uuid[],text)','bpf_admin_writer'),
 ('public.admin_usuario_vincular_convite(uuid,uuid,uuid[],text)','postgres'),
 ('public.admin_usuario_vincular_convite_tenant(uuid,uuid,uuid,uuid[],text)','postgres')) e(signature,owner)
 left join pg_proc p on p.oid=to_regprocedure(e.signature))
 and (select count(*)=4 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('public','private')
 and p.proname in('admin_usuario_vincular_convite','admin_usuario_vincular_convite_tenant')) as convites_legados_reconhecidos
from documents
-- END_READINESS_QUERY
 ) checked cross join lateral jsonb_each(to_jsonb(checked)) flag(key,value)
 where value is distinct from 'true'::jsonb;
 if coalesce(cardinality(v_failed),0)>0 then
   raise exception using errcode='55000',message='ADMIN_31_BLOQUEADO: '||array_to_string(v_failed,', ');
 end if;
end $readiness$;

-- Administration follows the selected membership, never an implicit UI tenant.
set lock_timeout='5s';
set statement_timeout='60s';

create role bpf_tenant_admin nologin noinherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
grant bpf_tenant_admin to postgres with inherit false,set true;
grant usage on schema public,private to bpf_tenant_admin;
grant create on schema private to bpf_tenant_admin;

create function private.admin_permissions(p_empresa uuid,p_usuario uuid)
returns text[] language sql stable security definer set search_path='' as $$
  select coalesce(array_agg(distinct pm.codigo),'{}'::text[])
  from public.usuarios u
  join public.usuario_empresas ue on ue.usuario_id=u.id and ue.empresa_id=p_empresa and ue.status='ativo'
  join public.empresas e on e.id=ue.empresa_id and e.ativo
  join public.usuario_empresa_perfis up on up.usuario_empresa_id=ue.id
  join public.perfis p on p.id=up.perfil_id and p.ativo and
    ((p.empresa_id is null and p.is_system) or p.empresa_id=p_empresa)
  join public.perfil_permissoes pp on pp.perfil_id=p.id
  join public.permissoes pm on pm.id=pp.permissao_id
  where u.id=p_usuario and u.ativo and u.status='ativo'
$$;

create function private.admin_scope_id()
returns uuid language sql stable security definer set search_path='' as $$
  select e.id from public.empresas e
  where e.id=nullif(current_setting('bpf.admin_empresa',true),'')::uuid
    and 'configuracoes.visualizar'=any(private.admin_permissions(e.id,private.request_jwt_subject()))
$$;

create function private.admin_assert(p_empresa uuid,p_permission text,p_write boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
  if p_empresa is null or not coalesce(array['configuracoes.visualizar',p_permission]
      <@ private.admin_permissions(p_empresa,private.request_jwt_subject()),false) then
    raise exception using errcode='42501',message='Acesso administrativo nao autorizado nesta empresa';
  end if;
  if p_write then
    perform pg_advisory_xact_lock(hashtextextended(p_empresa::text,0));
    if not array['configuracoes.visualizar',p_permission]
      <@ private.admin_permissions(p_empresa,private.request_jwt_subject()) then
      raise exception using errcode='42501',message='Acesso administrativo revogado nesta empresa';
    end if;
    perform 1 from public.empresa_assinaturas where empresa_id=p_empresa for update;
    perform private.assert_tenant_workspace_write_allowed(p_empresa);
  end if;
end $$;

create function private.admin_has_other(p_empresa uuid,p_usuario uuid,p_owner boolean default false)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.usuario_empresas ue
    join public.usuarios u on u.id=ue.usuario_id and u.ativo and u.status='ativo'
    where ue.empresa_id=p_empresa and ue.usuario_id<>p_usuario and ue.status='ativo'
      and case when p_owner then ue.is_owner else
        array['configuracoes.visualizar','usuarios.gerenciar','perfis.gerenciar']
          <@ private.admin_permissions(p_empresa,ue.usuario_id) end)
$$;

create function private.admin_audit(p_empresa uuid,p_unidade uuid,p_entidade text,p_id uuid,
  p_acao text,p_antes jsonb,p_depois jsonb,p_justificativa text)
returns void language plpgsql security invoker set search_path='' as $$
begin
  if length(btrim(coalesce(p_justificativa,'')))<5 then
    raise exception using errcode='22023',message='Justificativa deve possuir ao menos 5 caracteres';
  end if;
  insert into public.auditoria_eventos(empresa_id,unidade_id,ator_id,entidade,registro_id,
    acao,antes,depois,justificativa,contexto)
  values(p_empresa,p_unidade,private.request_jwt_subject(),p_entidade,p_id,p_acao,p_antes,p_depois,
    btrim(p_justificativa),jsonb_build_object('origem','tenant_admin_rpc',
      'membership_ator_id',(select id from public.usuario_empresas
        where usuario_id=private.request_jwt_subject() and empresa_id=p_empresa)));
end $$;

revoke all on function private.admin_permissions(uuid,uuid),private.admin_scope_id(),
  private.admin_assert(uuid,text,boolean),private.admin_has_other(uuid,uuid,boolean),
  private.admin_audit(uuid,uuid,text,uuid,text,jsonb,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function private.admin_permissions(uuid,uuid),private.admin_scope_id(),
  private.admin_assert(uuid,text,boolean),private.admin_has_other(uuid,uuid,boolean),
  private.admin_audit(uuid,uuid,text,uuid,text,jsonb,jsonb,text),private.request_jwt_subject() to bpf_tenant_admin;

-- This role has no write privilege on global identities or legacy profile links.
grant select on public.usuarios,public.empresas,public.unidades,public.setores,public.perfis,
  public.permissoes,public.perfil_permissoes,public.usuario_empresas,public.usuario_empresa_perfis,
  public.auditoria_eventos to bpf_tenant_admin;
grant update(razao_social,nome_fantasia,cnpj,updated_at) on public.empresas to bpf_tenant_admin;
grant insert(empresa_id,nome,codigo,ativo,created_by),update(nome,codigo,ativo,updated_at) on public.unidades to bpf_tenant_admin;
grant insert(unidade_id,nome,codigo,ativo,created_by),update(unidade_id,nome,codigo,ativo,updated_at) on public.setores to bpf_tenant_admin;
grant insert(empresa_id,nome,descricao,is_system,ativo,created_by),update(nome,descricao,ativo,updated_at) on public.perfis to bpf_tenant_admin;
grant insert(perfil_id,permissao_id,created_by),delete on public.perfil_permissoes to bpf_tenant_admin;
grant update(status,unidade_id,updated_at) on public.usuario_empresas to bpf_tenant_admin;
grant insert(usuario_empresa_id,perfil_id,created_by),delete on public.usuario_empresa_perfis to bpf_tenant_admin;
grant insert(empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto)
  on public.auditoria_eventos to bpf_tenant_admin;

create policy tenant_admin_empresas on public.empresas for all to bpf_tenant_admin
  using(id=private.admin_scope_id()) with check(id=private.admin_scope_id());
create policy tenant_admin_unidades on public.unidades for all to bpf_tenant_admin
  using(empresa_id=private.admin_scope_id()) with check(empresa_id=private.admin_scope_id());
create policy tenant_admin_setores on public.setores for all to bpf_tenant_admin
  using(exists(select 1 from public.unidades un where un.id=setores.unidade_id and un.empresa_id=private.admin_scope_id()))
  with check(exists(select 1 from public.unidades un where un.id=setores.unidade_id and un.empresa_id=private.admin_scope_id()));
create policy tenant_admin_perfis_read on public.perfis for select to bpf_tenant_admin
  using(empresa_id=private.admin_scope_id() or (empresa_id is null and is_system));
create policy tenant_admin_perfis_insert on public.perfis for insert to bpf_tenant_admin
  with check(empresa_id=private.admin_scope_id() and not is_system);
create policy tenant_admin_perfis_update on public.perfis for update to bpf_tenant_admin
  using(empresa_id=private.admin_scope_id() and not is_system)
  with check(empresa_id=private.admin_scope_id() and not is_system);
create policy tenant_admin_permissions on public.permissoes for select to bpf_tenant_admin using(true);
create policy tenant_admin_profile_permissions_read on public.perfil_permissoes for select to bpf_tenant_admin
  using(exists(select 1 from public.perfis p where p.id=perfil_id));
create policy tenant_admin_profile_permissions_insert on public.perfil_permissoes for insert to bpf_tenant_admin
  with check(exists(select 1 from public.perfis p where p.id=perfil_id and p.empresa_id=private.admin_scope_id() and not p.is_system));
create policy tenant_admin_profile_permissions_delete on public.perfil_permissoes for delete to bpf_tenant_admin
  using(exists(select 1 from public.perfis p where p.id=perfil_id and p.empresa_id=private.admin_scope_id() and not p.is_system));
create policy tenant_admin_memberships on public.usuario_empresas for all to bpf_tenant_admin
  using(empresa_id=private.admin_scope_id()) with check(empresa_id=private.admin_scope_id());
create policy tenant_admin_users_read on public.usuarios for select to bpf_tenant_admin
  using(exists(select 1 from public.usuario_empresas ue where ue.usuario_id=usuarios.id and ue.empresa_id=private.admin_scope_id()));
create policy tenant_admin_membership_profiles on public.usuario_empresa_perfis for all to bpf_tenant_admin
  using(exists(select 1 from public.usuario_empresas ue where ue.id=usuario_empresa_id and ue.empresa_id=private.admin_scope_id()))
  with check(exists(select 1 from public.usuario_empresas ue where ue.id=usuario_empresa_id and ue.empresa_id=private.admin_scope_id())
    and exists(select 1 from public.perfis p where p.id=perfil_id and ((p.empresa_id is null and p.is_system) or p.empresa_id=private.admin_scope_id())));
create policy tenant_admin_audit_read on public.auditoria_eventos for select to bpf_tenant_admin
  using(empresa_id=private.admin_scope_id());
create policy tenant_admin_audit_insert on public.auditoria_eventos for insert to bpf_tenant_admin
  with check(empresa_id=private.admin_scope_id() and ator_id=private.request_jwt_subject());

create function private.admin_contexto_ler(p_empresa_id uuid,p_recurso text,p_offset integer default 0,p_limit integer default 500)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_previous_scope text:=current_setting('bpf.admin_empresa',true); v_permission text; v_result jsonb;
begin
  v_permission:=case p_recurso
    when 'usuarios' then 'usuarios.gerenciar' when 'usuario_perfis' then 'usuarios.gerenciar'
    when 'perfis' then 'configuracoes.visualizar' when 'permissoes' then 'perfis.gerenciar'
    when 'perfil_permissoes' then 'perfis.gerenciar' when 'empresas' then 'configuracoes.visualizar'
    when 'unidades' then 'configuracoes.visualizar' when 'setores' then 'estrutura.gerenciar'
    when 'auditoria_eventos' then 'auditoria.visualizar' when 'atores_auditoria' then 'auditoria.visualizar' end;
  if v_permission is null or p_offset is null or p_offset<0 or p_limit is null or p_limit<1 or p_limit>500 then
    raise exception using errcode='22023',message='Consulta administrativa invalida';
  end if;
  perform private.admin_assert(p_empresa_id,v_permission,false);
  perform set_config('bpf.admin_empresa',p_empresa_id::text,true);
  with registros as materialized (
    select u.id::text as chave,jsonb_build_object('id',u.id,'membership_id',ue.id,'nome',u.nome,'email',u.email,
      'empresa_id',ue.empresa_id,'unidade_id',ue.unidade_id,'status',ue.status,'ativo',ue.status='ativo',
      'identidade_ativa',u.ativo,'identidade_status',u.status,'created_at',ue.created_at) as registro
      from public.usuario_empresas ue join public.usuarios u on u.id=ue.usuario_id where p_recurso='usuarios' and ue.empresa_id=p_empresa_id
    union all select e.id::text,jsonb_build_object('id',e.id,'nome_fantasia',e.nome_fantasia,'razao_social',e.razao_social,'cnpj',e.cnpj,'ativo',e.ativo)
      from public.empresas e where p_recurso='empresas' and e.id=p_empresa_id
    union all select un.id::text,jsonb_build_object('id',un.id,'empresa_id',un.empresa_id,'nome',un.nome,'codigo',un.codigo,'ativo',un.ativo)
      from public.unidades un where p_recurso='unidades' and un.empresa_id=p_empresa_id
    union all select s.id::text,jsonb_build_object('id',s.id,'unidade_id',s.unidade_id,'nome',s.nome,'codigo',s.codigo,'ativo',s.ativo)
      from public.setores s join public.unidades un on un.id=s.unidade_id where p_recurso='setores' and un.empresa_id=p_empresa_id
    union all select p.id::text,jsonb_build_object('id',p.id,'empresa_id',p.empresa_id,'nome',p.nome,'descricao',p.descricao,'is_system',p.is_system,'ativo',p.ativo)
      from public.perfis p where p_recurso='perfis' and (p.empresa_id=p_empresa_id or (p.empresa_id is null and p.is_system))
    union all select pm.id::text,jsonb_build_object('id',pm.id,'codigo',pm.codigo,'modulo',pm.modulo,'acao',pm.acao,'descricao',pm.descricao)
      from public.permissoes pm where p_recurso='permissoes'
    union all select ue.usuario_id::text||up.perfil_id::text,jsonb_build_object('usuario_id',ue.usuario_id,'perfil_id',up.perfil_id)
      from public.usuario_empresa_perfis up join public.usuario_empresas ue on ue.id=up.usuario_empresa_id
      where p_recurso='usuario_perfis' and ue.empresa_id=p_empresa_id
    union all select p.id::text||pp.permissao_id::text,jsonb_build_object('perfil_id',p.id,'permissao_id',pp.permissao_id)
      from public.perfil_permissoes pp join public.perfis p on p.id=pp.perfil_id
      where p_recurso='perfil_permissoes' and (p.empresa_id=p_empresa_id or (p.empresa_id is null and p.is_system))
    union all select ae.created_at::text||ae.id::text,jsonb_build_object('id',ae.id,'empresa_id',ae.empresa_id,'unidade_id',ae.unidade_id,'ator_id',ae.ator_id,
      'entidade',ae.entidade,'registro_id',ae.registro_id,'acao',ae.acao,'antes',ae.antes,'depois',ae.depois,'justificativa',ae.justificativa,'contexto',ae.contexto,'created_at',ae.created_at)
      from public.auditoria_eventos ae where p_recurso='auditoria_eventos' and ae.empresa_id=p_empresa_id
    union all select u.id::text,jsonb_build_object('id',u.id,'nome',u.nome,'email',u.email)
      from public.usuarios u where p_recurso='atores_auditoria'
      and exists(select 1 from public.auditoria_eventos ae where ae.empresa_id=p_empresa_id and ae.ator_id=u.id)
  ), pagina as(select registro from registros order by chave limit p_limit offset p_offset)
  select jsonb_build_object('data',coalesce((select jsonb_agg(registro) from pagina),'[]'::jsonb),
    'count',(select count(*) from registros)) into v_result;
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  return v_result;
exception when others then
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  raise;
end $$;

create function private.admin_usuario_status_tenant(p_empresa_id uuid,p_usuario_id uuid,p_status text,p_justificativa text)
returns void language plpgsql security definer set search_path='' as $$
declare v_previous_scope text:=current_setting('bpf.admin_empresa',true); v_old public.usuario_empresas%rowtype; v_admin boolean;
begin
  perform private.admin_assert(p_empresa_id,'usuarios.gerenciar',true);
  perform set_config('bpf.admin_empresa',p_empresa_id::text,true);
  select * into v_old from public.usuario_empresas where usuario_id=p_usuario_id and empresa_id=p_empresa_id for update;
  if not found then raise exception using errcode='42501',message='Usuario fora do escopo autorizado'; end if;
  if v_old.status='pendente' or p_status is null or p_status not in('ativo','inativo','bloqueado') then
    raise exception using errcode='22023',message='Status administrativo invalido'; end if;
  if p_usuario_id=private.request_jwt_subject() and p_status<>'ativo' then
    raise exception using errcode='42501',message='Nao e permitido inativar ou bloquear o proprio usuario'; end if;
  if v_old.status=p_status then raise exception using errcode='22023',message='Nenhuma alteracao de status identificada'; end if;
  v_admin:=array['configuracoes.visualizar','usuarios.gerenciar','perfis.gerenciar'] <@ private.admin_permissions(p_empresa_id,p_usuario_id);
  if p_status<>'ativo' and ((v_admin and not private.admin_has_other(p_empresa_id,p_usuario_id,false))
      or (v_old.is_owner and not private.admin_has_other(p_empresa_id,p_usuario_id,true))) then
    raise exception using errcode='42501',message='Operacao removeria o ultimo administrador ou owner efetivo da empresa'; end if;
  update public.usuario_empresas set status=p_status,updated_at=now() where id=v_old.id;
  perform private.admin_audit(p_empresa_id,v_old.unidade_id,'usuario',p_usuario_id,'usuario.status_alterado',
    to_jsonb(v_old),to_jsonb(v_old)||jsonb_build_object('status',p_status),p_justificativa);
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
exception when others then
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  raise;
end $$;

create function private.admin_usuario_unidade_tenant(p_empresa_id uuid,p_usuario_id uuid,p_unidade_id uuid,p_justificativa text)
returns void language plpgsql security definer set search_path='' as $$
declare v_previous_scope text:=current_setting('bpf.admin_empresa',true); v_old public.usuario_empresas%rowtype;
begin
  perform private.admin_assert(p_empresa_id,'usuarios.gerenciar',true);
  perform set_config('bpf.admin_empresa',p_empresa_id::text,true);
  select * into v_old from public.usuario_empresas where usuario_id=p_usuario_id and empresa_id=p_empresa_id for update;
  if not found then raise exception using errcode='42501',message='Usuario fora do escopo autorizado'; end if;
  if v_old.status='pendente' then raise exception using errcode='42501',message='Usuario pendente exige fluxo de vinculacao/aprovacao dedicado'; end if;
  if p_unidade_id is not null and not exists(select 1 from public.unidades where id=p_unidade_id and empresa_id=p_empresa_id and ativo) then
    raise exception using errcode='42501',message='Unidade invalida, inativa ou fora da empresa'; end if;
  if v_old.unidade_id is not distinct from p_unidade_id then raise exception using errcode='22023',message='Nenhuma alteracao de unidade identificada'; end if;
  update public.usuario_empresas set unidade_id=p_unidade_id,updated_at=now() where id=v_old.id;
  perform private.admin_audit(p_empresa_id,p_unidade_id,'usuario',p_usuario_id,'usuario.unidade_alterada',
    to_jsonb(v_old),to_jsonb(v_old)||jsonb_build_object('unidade_id',p_unidade_id),p_justificativa);
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
exception when others then
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  raise;
end $$;

create function private.admin_usuario_perfil_tenant(p_empresa_id uuid,p_usuario_id uuid,p_perfil_id uuid,p_acao text,p_justificativa text)
returns void language plpgsql security definer set search_path='' as $$
declare v_previous_scope text:=current_setting('bpf.admin_empresa',true); v_member public.usuario_empresas%rowtype; v_profile public.perfis%rowtype; v_admin boolean; v_exists boolean;
begin
  perform private.admin_assert(p_empresa_id,'perfis.gerenciar',true);
  perform set_config('bpf.admin_empresa',p_empresa_id::text,true);
  if p_usuario_id=private.request_jwt_subject() then raise exception using errcode='42501',message='Nao e permitido alterar o proprio perfil administrativo'; end if;
  if p_acao is null or p_acao not in('atribuir','remover') then raise exception using errcode='22023',message='Acao de perfil invalida'; end if;
  select * into v_member from public.usuario_empresas where usuario_id=p_usuario_id and empresa_id=p_empresa_id for update;
  if not found or v_member.status='pendente' then raise exception using errcode='42501',message='Usuario fora do escopo autorizado'; end if;
  select * into v_profile from public.perfis where id=p_perfil_id and ((empresa_id is null and is_system) or empresa_id=p_empresa_id);
  if not found or (p_acao='atribuir' and not v_profile.ativo) then raise exception using errcode='42501',message='Perfil fora do escopo autorizado'; end if;
  if p_acao='atribuir' and exists(select 1 from public.perfil_permissoes pp join public.permissoes pm on pm.id=pp.permissao_id
    where pp.perfil_id=p_perfil_id and not pm.codigo=any(private.admin_permissions(p_empresa_id,private.request_jwt_subject()))) then
    raise exception using errcode='42501',message='Nao e permitido delegar um perfil com permissoes superiores as do ator'; end if;
  select exists(select 1 from public.usuario_empresa_perfis where usuario_empresa_id=v_member.id and perfil_id=p_perfil_id) into v_exists;
  if v_exists=(p_acao='atribuir') then raise exception using errcode='22023',message='Atribuicao de perfil sem alteracao'; end if;
  v_admin:=array['configuracoes.visualizar','usuarios.gerenciar','perfis.gerenciar'] <@ private.admin_permissions(p_empresa_id,p_usuario_id);
  if p_acao='atribuir' then
    insert into public.usuario_empresa_perfis(usuario_empresa_id,perfil_id,created_by) values(v_member.id,p_perfil_id,private.request_jwt_subject());
  else
    delete from public.usuario_empresa_perfis where usuario_empresa_id=v_member.id and perfil_id=p_perfil_id;
  end if;
  if v_admin and not array['configuracoes.visualizar','usuarios.gerenciar','perfis.gerenciar'] <@ private.admin_permissions(p_empresa_id,p_usuario_id)
    and not private.admin_has_other(p_empresa_id,p_usuario_id,false) then
    raise exception using errcode='42501',message='Operacao removeria o ultimo administrador efetivo da empresa'; end if;
  perform private.admin_audit(p_empresa_id,v_member.unidade_id,'usuario',p_usuario_id,
    case when p_acao='atribuir' then 'usuario.perfil_atribuido' else 'usuario.perfil_removido' end,
    jsonb_build_object('membership_id',v_member.id,'perfil_id',p_perfil_id,'atribuido',v_exists),
    jsonb_build_object('membership_id',v_member.id,'perfil_id',p_perfil_id,'atribuido',not v_exists),p_justificativa);
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
exception when others then
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  raise;
end $$;

create function private.admin_empresa_tenant(p_empresa_id uuid,p_razao_social text,p_nome_fantasia text,p_cnpj text,p_justificativa text)
returns void language plpgsql security definer set search_path='' as $$
declare v_previous_scope text:=current_setting('bpf.admin_empresa',true); v_old public.empresas%rowtype;
begin
  perform private.admin_assert(p_empresa_id,'estrutura.gerenciar',true);
  perform set_config('bpf.admin_empresa',p_empresa_id::text,true);
  if length(btrim(coalesce(p_razao_social,'')))<2 then raise exception using errcode='22023',message='Razao social invalida'; end if;
  select * into v_old from public.empresas where id=p_empresa_id for update;
  update public.empresas set razao_social=btrim(p_razao_social),nome_fantasia=nullif(btrim(p_nome_fantasia),''),cnpj=nullif(btrim(p_cnpj),''),updated_at=now() where id=p_empresa_id;
  perform private.admin_audit(p_empresa_id,null,'empresa',p_empresa_id,'empresa.atualizada',
    jsonb_build_object('razao_social',v_old.razao_social,'nome_fantasia',v_old.nome_fantasia,'cnpj',v_old.cnpj),
    jsonb_build_object('razao_social',btrim(p_razao_social),'nome_fantasia',nullif(btrim(p_nome_fantasia),''),'cnpj',nullif(btrim(p_cnpj),'')),p_justificativa);
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
exception when others then
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  raise;
end $$;

create function private.admin_unidade_tenant(p_empresa_id uuid,p_unidade_id uuid,p_nome text,p_codigo text,p_ativo boolean,p_justificativa text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_previous_scope text:=current_setting('bpf.admin_empresa',true); v_old public.unidades%rowtype; v_id uuid;
begin
  perform private.admin_assert(p_empresa_id,'estrutura.gerenciar',true);
  perform set_config('bpf.admin_empresa',p_empresa_id::text,true);
  if length(btrim(coalesce(p_nome,'')))<2 then raise exception using errcode='22023',message='Nome da unidade invalido'; end if;
  if p_unidade_id is null then
    insert into public.unidades(empresa_id,nome,codigo,ativo,created_by)
      values(p_empresa_id,btrim(p_nome),nullif(btrim(p_codigo),''),coalesce(p_ativo,true),private.request_jwt_subject()) returning id into v_id;
  else
    select * into v_old from public.unidades where id=p_unidade_id and empresa_id=p_empresa_id for update;
    if not found then raise exception using errcode='42501',message='Unidade fora do escopo autorizado'; end if;
    if not coalesce(p_ativo,true) and exists(select 1 from public.usuario_empresas ue join public.usuarios u on u.id=ue.usuario_id
      where ue.unidade_id=p_unidade_id and ue.status='ativo' and u.ativo and u.status='ativo') then
      raise exception using errcode='23514',message='Unidade possui usuarios ativos vinculados'; end if;
    v_id:=p_unidade_id;
    update public.unidades set nome=btrim(p_nome),codigo=nullif(btrim(p_codigo),''),ativo=coalesce(p_ativo,true),updated_at=now() where id=v_id;
  end if;
  perform private.admin_audit(p_empresa_id,v_id,'unidade',v_id,case when p_unidade_id is null then 'unidade.criada' else 'unidade.atualizada' end,
    case when p_unidade_id is null then null else to_jsonb(v_old) end,jsonb_build_object('nome',btrim(p_nome),'codigo',nullif(btrim(p_codigo),''),'ativo',coalesce(p_ativo,true)),p_justificativa);
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  return v_id;
exception when others then
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  raise;
end $$;

create function private.admin_setor_tenant(p_empresa_id uuid,p_setor_id uuid,p_unidade_id uuid,p_nome text,p_codigo text,p_ativo boolean,p_justificativa text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_previous_scope text:=current_setting('bpf.admin_empresa',true); v_old public.setores%rowtype; v_id uuid;
begin
  perform private.admin_assert(p_empresa_id,'estrutura.gerenciar',true);
  perform set_config('bpf.admin_empresa',p_empresa_id::text,true);
  if not exists(select 1 from public.unidades where id=p_unidade_id and empresa_id=p_empresa_id and ativo) then
    raise exception using errcode='42501',message='Unidade fora do escopo autorizado'; end if;
  if length(btrim(coalesce(p_nome,'')))<2 then raise exception using errcode='22023',message='Nome do setor invalido'; end if;
  if p_setor_id is null then
    insert into public.setores(unidade_id,nome,codigo,ativo,created_by)
      values(p_unidade_id,btrim(p_nome),nullif(btrim(p_codigo),''),coalesce(p_ativo,true),private.request_jwt_subject()) returning id into v_id;
  else
    select s.* into v_old from public.setores s join public.unidades un on un.id=s.unidade_id
      where s.id=p_setor_id and un.empresa_id=p_empresa_id for update of s;
    if not found then raise exception using errcode='42501',message='Setor fora do escopo autorizado'; end if;
    v_id:=p_setor_id;
    update public.setores set unidade_id=p_unidade_id,nome=btrim(p_nome),codigo=nullif(btrim(p_codigo),''),ativo=coalesce(p_ativo,true),updated_at=now() where id=v_id;
  end if;
  perform private.admin_audit(p_empresa_id,p_unidade_id,'setor',v_id,case when p_setor_id is null then 'setor.criado' else 'setor.atualizado' end,
    case when p_setor_id is null then null else to_jsonb(v_old) end,jsonb_build_object('unidade_id',p_unidade_id,'nome',btrim(p_nome),'codigo',nullif(btrim(p_codigo),''),'ativo',coalesce(p_ativo,true)),p_justificativa);
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  return v_id;
exception when others then
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  raise;
end $$;

create function private.admin_perfil_tenant(p_empresa_id uuid,p_perfil_id uuid,p_nome text,p_descricao text,p_ativo boolean,p_permissao_ids uuid[],p_justificativa text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_previous_scope text:=current_setting('bpf.admin_empresa',true); v_old public.perfis%rowtype; v_id uuid; v_perm uuid; v_old_permissions uuid[];
begin
  perform private.admin_assert(p_empresa_id,'perfis.gerenciar',true);
  perform set_config('bpf.admin_empresa',p_empresa_id::text,true);
  if length(btrim(coalesce(p_nome,'')))<2 then raise exception using errcode='22023',message='Nome do perfil invalido'; end if;
  foreach v_perm in array coalesce(p_permissao_ids,'{}'::uuid[]) loop
    if not exists(select 1 from public.permissoes pm where pm.id=v_perm and pm.codigo=any(private.admin_permissions(p_empresa_id,private.request_jwt_subject()))) then
      raise exception using errcode='42501',message='Nao e permitido conceder uma permissao que o ator nao possui'; end if;
  end loop;
  if p_perfil_id is null then
    insert into public.perfis(empresa_id,nome,descricao,is_system,ativo,created_by)
      values(p_empresa_id,btrim(p_nome),nullif(btrim(p_descricao),''),false,coalesce(p_ativo,true),private.request_jwt_subject()) returning id into v_id;
  else
    select * into v_old from public.perfis where id=p_perfil_id and empresa_id=p_empresa_id and not is_system for update;
    if not found then raise exception using errcode='42501',message='Perfil de sistema ou fora do escopo nao pode ser alterado'; end if;
    select coalesce(array_agg(permissao_id order by permissao_id),'{}'::uuid[]) into v_old_permissions from public.perfil_permissoes where perfil_id=p_perfil_id;
    if exists(select 1 from public.usuario_empresa_perfis up join public.usuario_empresas ue on ue.id=up.usuario_empresa_id
      join public.usuarios u on u.id=ue.usuario_id and u.ativo and u.status='ativo'
      where up.perfil_id=p_perfil_id and ue.status='ativo') and
      (not coalesce(p_ativo,true) or v_old_permissions is distinct from
        array(select distinct x from unnest(coalesce(p_permissao_ids,'{}'::uuid[])) x order by x)) then
      raise exception using errcode='23514',message='Perfil em uso por usuarios ativos deve ser desvinculado antes de alterar permissoes'; end if;
    v_id:=p_perfil_id;
    update public.perfis set nome=btrim(p_nome),descricao=nullif(btrim(p_descricao),''),ativo=coalesce(p_ativo,true),updated_at=now() where id=v_id;
    if v_old_permissions is distinct from array(select distinct x from unnest(coalesce(p_permissao_ids,'{}'::uuid[])) x order by x) then
      delete from public.perfil_permissoes where perfil_id=v_id;
    end if;
  end if;
  if p_perfil_id is null or v_old_permissions is distinct from array(select distinct x from unnest(coalesce(p_permissao_ids,'{}'::uuid[])) x order by x) then
    insert into public.perfil_permissoes(perfil_id,permissao_id,created_by)
      select v_id,x,private.request_jwt_subject() from (select distinct unnest(coalesce(p_permissao_ids,'{}'::uuid[])) x) a;
  end if;
  perform private.admin_audit(p_empresa_id,null,'perfil',v_id,case when p_perfil_id is null then 'perfil.criado' else 'perfil.atualizado' end,
    case when p_perfil_id is null then null else to_jsonb(v_old)||jsonb_build_object('permissao_ids',v_old_permissions) end,
    jsonb_build_object('nome',btrim(p_nome),'descricao',nullif(btrim(p_descricao),''),'ativo',coalesce(p_ativo,true),'permissao_ids',coalesce(p_permissao_ids,'{}'::uuid[])),p_justificativa);
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  return v_id;
exception when others then
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  raise;
end $$;

-- Narrow owners/ACLs; authenticated cannot SET this role or call its private helpers.
do $acl$ declare r record; begin
  for r in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname in('admin_contexto_ler','admin_usuario_status_tenant','admin_usuario_unidade_tenant',
      'admin_usuario_perfil_tenant','admin_empresa_tenant','admin_unidade_tenant','admin_setor_tenant','admin_perfil_tenant') loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',r.signature);
    execute format('grant execute on function %s to authenticated,bpf_admin_writer',r.signature);
    execute format('alter function %s owner to bpf_tenant_admin',r.signature);
  end loop;
end $acl$;
create function public.admin_contexto_ler(p_empresa_id uuid,p_recurso text,p_offset integer default 0,p_limit integer default 500) returns jsonb
language sql security invoker set search_path='' as $$ select private.admin_contexto_ler(p_empresa_id,p_recurso,p_offset,p_limit) $$;
revoke all on function public.admin_contexto_ler(uuid,text,integer,integer) from public,anon,authenticated,service_role;
grant execute on function public.admin_contexto_ler(uuid,text,integer,integer) to authenticated,bpf_admin_writer;
create function public.admin_usuario_status_tenant(p_empresa_id uuid,p_usuario_id uuid,p_status text,p_justificativa text) returns void
language sql security invoker set search_path='' as $$ select private.admin_usuario_status_tenant(p_empresa_id,p_usuario_id,p_status,p_justificativa) $$;
revoke all on function public.admin_usuario_status_tenant(uuid,uuid,text,text) from public,anon,authenticated,service_role;
grant execute on function public.admin_usuario_status_tenant(uuid,uuid,text,text) to authenticated,bpf_admin_writer;
create function public.admin_usuario_unidade_tenant(p_empresa_id uuid,p_usuario_id uuid,p_unidade_id uuid,p_justificativa text) returns void
language sql security invoker set search_path='' as $$ select private.admin_usuario_unidade_tenant(p_empresa_id,p_usuario_id,p_unidade_id,p_justificativa) $$;
revoke all on function public.admin_usuario_unidade_tenant(uuid,uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.admin_usuario_unidade_tenant(uuid,uuid,uuid,text) to authenticated,bpf_admin_writer;
create function public.admin_usuario_perfil_tenant(p_empresa_id uuid,p_usuario_id uuid,p_perfil_id uuid,p_acao text,p_justificativa text) returns void
language sql security invoker set search_path='' as $$ select private.admin_usuario_perfil_tenant(p_empresa_id,p_usuario_id,p_perfil_id,p_acao,p_justificativa) $$;
revoke all on function public.admin_usuario_perfil_tenant(uuid,uuid,uuid,text,text) from public,anon,authenticated,service_role;
grant execute on function public.admin_usuario_perfil_tenant(uuid,uuid,uuid,text,text) to authenticated,bpf_admin_writer;
create function public.admin_empresa_tenant(p_empresa_id uuid,p_razao_social text,p_nome_fantasia text,p_cnpj text,p_justificativa text) returns void
language sql security invoker set search_path='' as $$ select private.admin_empresa_tenant(p_empresa_id,p_razao_social,p_nome_fantasia,p_cnpj,p_justificativa) $$;
revoke all on function public.admin_empresa_tenant(uuid,text,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.admin_empresa_tenant(uuid,text,text,text,text) to authenticated,bpf_admin_writer;
create function public.admin_unidade_tenant(p_empresa_id uuid,p_unidade_id uuid,p_nome text,p_codigo text,p_ativo boolean,p_justificativa text) returns uuid
language sql security invoker set search_path='' as $$ select private.admin_unidade_tenant(p_empresa_id,p_unidade_id,p_nome,p_codigo,p_ativo,p_justificativa) $$;
revoke all on function public.admin_unidade_tenant(uuid,uuid,text,text,boolean,text) from public,anon,authenticated,service_role;
grant execute on function public.admin_unidade_tenant(uuid,uuid,text,text,boolean,text) to authenticated,bpf_admin_writer;
create function public.admin_setor_tenant(p_empresa_id uuid,p_setor_id uuid,p_unidade_id uuid,p_nome text,p_codigo text,p_ativo boolean,p_justificativa text) returns uuid
language sql security invoker set search_path='' as $$ select private.admin_setor_tenant(p_empresa_id,p_setor_id,p_unidade_id,p_nome,p_codigo,p_ativo,p_justificativa) $$;
revoke all on function public.admin_setor_tenant(uuid,uuid,uuid,text,text,boolean,text) from public,anon,authenticated,service_role;
grant execute on function public.admin_setor_tenant(uuid,uuid,uuid,text,text,boolean,text) to authenticated,bpf_admin_writer;
create function public.admin_perfil_tenant(p_empresa_id uuid,p_perfil_id uuid,p_nome text,p_descricao text,p_ativo boolean,p_permissao_ids uuid[],p_justificativa text) returns uuid
language sql security invoker set search_path='' as $$ select private.admin_perfil_tenant(p_empresa_id,p_perfil_id,p_nome,p_descricao,p_ativo,p_permissao_ids,p_justificativa) $$;
revoke all on function public.admin_perfil_tenant(uuid,uuid,text,text,boolean,uuid[],text) from public,anon,authenticated,service_role;
grant execute on function public.admin_perfil_tenant(uuid,uuid,text,text,boolean,uuid[],text) to authenticated,bpf_admin_writer;

revoke create on schema private from bpf_tenant_admin;
grant bpf_tenant_admin to postgres with inherit false,set false;


-- Compatibility uses the primary company only as routing; authorization is canonical.
create function private.admin_primary_empresa() returns uuid language sql stable security definer set search_path='' as $$
  select empresa_id from public.usuarios where id=private.request_jwt_subject() and ativo and status='ativo'
$$;
revoke all on function private.admin_primary_empresa() from public,anon,authenticated,service_role;
grant execute on function private.admin_primary_empresa(),private.admin_permissions(uuid,uuid),private.admin_has_other(uuid,uuid,boolean),private.request_jwt_subject() to bpf_admin_writer,bpf_authz_reader;
grant bpf_authz_reader to postgres with inherit false,set true;
grant create on schema private to bpf_authz_reader;
set role bpf_authz_reader;
create or replace function private.empresa_leitura_usuarios() returns uuid language sql stable security definer set search_path='' as $$
  select private.admin_primary_empresa() where array['configuracoes.visualizar','usuarios.gerenciar'] <@ private.admin_permissions(private.admin_primary_empresa(),private.request_jwt_subject())
$$;
create or replace function private.empresa_gestao_perfis() returns uuid language sql stable security definer set search_path='' as $$
  select private.admin_primary_empresa() where array['configuracoes.visualizar','perfis.gerenciar'] <@ private.admin_permissions(private.admin_primary_empresa(),private.request_jwt_subject())
$$;
create or replace function private.empresa_convite_usuarios() returns uuid language sql stable security definer set search_path='' as $$
  select private.admin_primary_empresa() where array['configuracoes.visualizar','usuarios.gerenciar','usuarios.convidar'] <@ private.admin_permissions(private.admin_primary_empresa(),private.request_jwt_subject())
$$;
create or replace function private.empresa_estrutura_admin() returns uuid language sql stable security definer set search_path='' as $$
  select private.admin_primary_empresa() where array['configuracoes.visualizar','estrutura.gerenciar'] <@ private.admin_permissions(private.admin_primary_empresa(),private.request_jwt_subject())
$$;
create or replace function private.empresa_leitura_auditoria() returns uuid language sql stable security definer set search_path='' as $$
  select private.admin_primary_empresa() where array['configuracoes.visualizar','auditoria.visualizar'] <@ private.admin_permissions(private.admin_primary_empresa(),private.request_jwt_subject())
$$;
revoke all on function private.empresa_leitura_usuarios(),private.empresa_gestao_perfis(),
 private.empresa_convite_usuarios(),private.empresa_estrutura_admin(),private.empresa_leitura_auditoria() from public,anon,service_role;
grant execute on function private.empresa_leitura_usuarios(),private.empresa_gestao_perfis(),
 private.empresa_convite_usuarios(),private.empresa_estrutura_admin(),private.empresa_leitura_auditoria() to authenticated,bpf_admin_writer;
reset role;
revoke create on schema private from bpf_authz_reader;
grant bpf_authz_reader to postgres with inherit false,set false;
grant bpf_admin_writer to postgres with inherit false,set true;
grant create on schema private to bpf_admin_writer;
set role bpf_admin_writer;
create or replace function private.ator_possui_permissao(p_permissao_id uuid) returns boolean
language sql stable security invoker set search_path='' as $$
 select exists(select 1 from public.permissoes where id=p_permissao_id
   and codigo=any(private.admin_permissions(private.admin_primary_empresa(),private.request_jwt_subject())))
$$;
create or replace function private.usuario_admin_efetivo(p_usuario_id uuid,p_empresa_id uuid) returns boolean
language sql stable security invoker set search_path='' as $$
 select array['configuracoes.visualizar','usuarios.gerenciar','perfis.gerenciar'] <@ private.admin_permissions(p_empresa_id,p_usuario_id)
$$;
create or replace function private.existe_outro_admin_efetivo(p_usuario_id uuid,p_empresa_id uuid) returns boolean
language sql stable security invoker set search_path='' as $$
 select private.admin_has_other(p_empresa_id,p_usuario_id,false)
$$;
create or replace function private.admin_usuario_alterar_status(p_usuario_id uuid,p_status text,p_justificativa text) returns void
language sql security definer set search_path='' as $$
 select public.admin_usuario_status_tenant(private.admin_primary_empresa(),p_usuario_id,p_status,p_justificativa)
$$;
create or replace function private.admin_usuario_alterar_unidade(p_usuario_id uuid,p_unidade_id uuid,p_justificativa text) returns void
language sql security definer set search_path='' as $$
 select public.admin_usuario_unidade_tenant(private.admin_primary_empresa(),p_usuario_id,p_unidade_id,p_justificativa)
$$;
create or replace function private.admin_usuario_alterar_perfil(p_usuario_id uuid,p_perfil_id uuid,p_acao text,p_justificativa text) returns void
language sql security definer set search_path='' as $$
 select public.admin_usuario_perfil_tenant(private.admin_primary_empresa(),p_usuario_id,p_perfil_id,p_acao,p_justificativa)
$$;
create or replace function private.admin_empresa_atualizar(p_razao_social text,p_nome_fantasia text,p_cnpj text,p_justificativa text) returns void
language sql security definer set search_path='' as $$
 select public.admin_empresa_tenant(private.admin_primary_empresa(),p_razao_social,p_nome_fantasia,p_cnpj,p_justificativa)
$$;
create or replace function private.admin_unidade_salvar(p_unidade_id uuid,p_nome text,p_codigo text,p_ativo boolean,p_justificativa text) returns uuid
language sql security definer set search_path='' as $$
 select public.admin_unidade_tenant(private.admin_primary_empresa(),p_unidade_id,p_nome,p_codigo,p_ativo,p_justificativa)
$$;
create or replace function private.admin_setor_salvar(p_setor_id uuid,p_unidade_id uuid,p_nome text,p_codigo text,p_ativo boolean,p_justificativa text) returns uuid
language sql security definer set search_path='' as $$
 select public.admin_setor_tenant(private.admin_primary_empresa(),p_setor_id,p_unidade_id,p_nome,p_codigo,p_ativo,p_justificativa)
$$;
create or replace function private.admin_perfil_criar(p_nome text,p_descricao text,p_permissao_ids uuid[],p_justificativa text) returns uuid
language sql security definer set search_path='' as $$
 select public.admin_perfil_tenant(private.admin_primary_empresa(),null,p_nome,p_descricao,true,p_permissao_ids,p_justificativa)
$$;
create or replace function private.admin_perfil_atualizar(p_perfil_id uuid,p_nome text,p_descricao text,p_ativo boolean,p_permissao_ids uuid[],p_justificativa text) returns void
language sql security definer set search_path='' as $$
 select public.admin_perfil_tenant(private.admin_primary_empresa(),p_perfil_id,p_nome,p_descricao,p_ativo,p_permissao_ids,p_justificativa)
$$;
revoke all on function private.admin_usuario_alterar_status(uuid,text,text),private.admin_usuario_alterar_unidade(uuid,uuid,text),
 private.admin_usuario_alterar_perfil(uuid,uuid,text,text),private.admin_empresa_atualizar(text,text,text,text),
 private.admin_unidade_salvar(uuid,text,text,boolean,text),private.admin_setor_salvar(uuid,uuid,text,text,boolean,text),
 private.admin_perfil_criar(text,text,uuid[],text),private.admin_perfil_atualizar(uuid,text,text,boolean,uuid[],text) from public,anon,service_role;
grant execute on function private.admin_usuario_alterar_status(uuid,text,text),private.admin_usuario_alterar_unidade(uuid,uuid,text),
 private.admin_usuario_alterar_perfil(uuid,uuid,text,text),private.admin_empresa_atualizar(text,text,text,text),
 private.admin_unidade_salvar(uuid,text,text,boolean,text),private.admin_setor_salvar(uuid,uuid,text,text,boolean,text),
 private.admin_perfil_criar(text,text,uuid[],text),private.admin_perfil_atualizar(uuid,text,text,boolean,uuid[],text) to authenticated;
-- Retired invitation paths must lose PUBLIC too, while their owner is active.
revoke all on function private.admin_usuario_vincular_convite(uuid,uuid,uuid[],text),
 private.admin_usuario_vincular_convite_tenant(uuid,uuid,uuid,uuid[],text) from public,anon,authenticated,service_role;
reset role;
revoke create on schema private from bpf_admin_writer;
grant bpf_admin_writer to postgres with inherit false,set false;
-- Old invitation path is retired; the tenant-aware server invitation remains unchanged.
revoke execute on function public.admin_usuario_vincular_convite(uuid,uuid,uuid[],text),
 public.admin_usuario_vincular_convite_tenant(uuid,uuid,uuid,uuid[],text) from public,anon,authenticated,service_role;

create or replace view public.v_meu_contexto with(security_invoker=true) as
select c.usuario_id,c.nome,c.email,c.ativo,c.status,c.empresa_id,c.nome_fantasia,c.razao_social,
 c.unidade_id,c.unidade_nome,c.perfis,c.permissoes
from public.usuarios u cross join lateral public.meu_contexto_empresa(u.empresa_id) c
where u.id=private.request_jwt_subject();


grant bpf_plan_enforcer to postgres with inherit false,set true;
grant create on schema private to bpf_plan_enforcer;
set role bpf_plan_enforcer;
create or replace function private.consumo_plano_empresa(p_empresa_id uuid)
returns table(usuarios_ativos bigint,unidades_ativas bigint)
language sql stable security definer set search_path='' as $$
 select (select count(*) from (
   select ue.usuario_id from public.usuario_empresas ue join public.usuarios u on u.id=ue.usuario_id
     where ue.empresa_id=p_empresa_id and ue.status='ativo' and u.ativo and u.status='ativo'
   union
   select u.id from public.usuarios u where u.empresa_id=p_empresa_id and u.ativo and u.status='ativo'
     and not exists(select 1 from public.usuario_empresas ue where ue.usuario_id=u.id and ue.empresa_id=p_empresa_id)
 ) ativos), (select count(*) from public.unidades where empresa_id=p_empresa_id and ativo)
$$;
create or replace function private.validar_limite_usuario_legacy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_limite bigint;
  v_consumo bigint;
begin
  if new.empresa_id is null or not new.ativo or new.status <> 'ativo' then return new; end if;
  if tg_op = 'UPDATE'
     and old.empresa_id is not distinct from new.empresa_id
     and old.ativo
     and old.status = 'ativo' then
    return new;
  end if;

  v_limite := private.limite_inteiro_empresa(new.empresa_id, 'usuarios_ativos.max');
  if v_limite is null then return new; end if;

  select count(*) into v_consumo
  from (
    select u.id as usuario_id
    from public.usuarios u
    where u.empresa_id = new.empresa_id
      and u.ativo and u.status = 'ativo'
      and not exists(select 1 from public.usuario_empresas canonical where canonical.usuario_id=u.id and canonical.empresa_id=new.empresa_id)
      and u.id <> new.id
    union
    select ue.usuario_id
    from public.usuario_empresas ue
    join public.usuarios identity_user on identity_user.id=ue.usuario_id and identity_user.ativo and identity_user.status='ativo'
    where ue.empresa_id = new.empresa_id
      and ue.status = 'ativo'
      and ue.usuario_id <> new.id
  ) ativos;

  if v_consumo + 1 > v_limite then
    raise exception using
      errcode = '23514',
      message = 'Limite de usuarios ativos do plano atingido';
  end if;
  return new;
end
$function$;
create or replace function private.validar_limite_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_limite bigint;
  v_consumo bigint;
begin
  if new.status <> 'ativo' then return new; end if;
  if tg_op = 'UPDATE'
     and old.empresa_id is not distinct from new.empresa_id
     and old.usuario_id = new.usuario_id
     and old.status = 'ativo' then
    return new;
  end if;

  v_limite := private.limite_inteiro_empresa(new.empresa_id, 'usuarios_ativos.max');
  if v_limite is null then return new; end if;

  select count(*) into v_consumo
  from (
    select u.id as usuario_id
    from public.usuarios u
    where u.empresa_id = new.empresa_id
      and u.ativo and u.status = 'ativo'
      and not exists(select 1 from public.usuario_empresas canonical where canonical.usuario_id=u.id and canonical.empresa_id=new.empresa_id)
      and u.id <> new.usuario_id
    union
    select ue.usuario_id
    from public.usuario_empresas ue
    join public.usuarios identity_user on identity_user.id=ue.usuario_id and identity_user.ativo and identity_user.status='ativo'
    where ue.empresa_id = new.empresa_id
      and ue.status = 'ativo'
      and ue.usuario_id <> new.usuario_id
  ) ativos;

  if v_consumo + 1 > v_limite then
    raise exception using
      errcode = '23514',
      message = 'Limite de usuarios ativos do plano atingido';
  end if;
  return new;
end
$function$;

grant execute on function private.consumo_plano_empresa(uuid) to postgres;
reset role;
revoke create on schema private from bpf_plan_enforcer;
grant bpf_plan_enforcer to postgres with inherit false,set false;


-- Direct legacy reads also lose tenant visibility after canonical revocation.
create function private.primary_visible_empresa() returns uuid language sql stable security definer set search_path='' as $$
 select u.empresa_id from public.usuarios u
 join public.usuario_empresas ue on ue.usuario_id=u.id and ue.empresa_id=u.empresa_id and ue.status='ativo'
 join public.empresas e on e.id=ue.empresa_id and e.ativo
 where u.id=private.request_jwt_subject() and u.ativo and u.status='ativo'
$$;
revoke all on function private.primary_visible_empresa() from public,anon,authenticated,service_role;
grant execute on function private.primary_visible_empresa() to authenticated;
-- Restrictive guards intersect every legacy permissive policy, whatever its name.
-- They grant no access and cannot be bypassed by another permissive USING(true).
create policy tenant_admin_primary_guard on public.empresas as restrictive for select to authenticated using(id=private.primary_visible_empresa());
create policy tenant_admin_primary_guard on public.unidades as restrictive for select to authenticated using(empresa_id=private.primary_visible_empresa());
create policy tenant_admin_primary_guard on public.setores as restrictive for select to authenticated using(exists(select 1 from public.unidades un
 where un.id=setores.unidade_id and un.empresa_id=private.primary_visible_empresa()));
create policy tenant_admin_primary_guard on public.perfis as restrictive for select to authenticated using((empresa_id is null and is_system) or empresa_id=private.primary_visible_empresa());


-- The trusted invitation channel shares the same locks and commercial checks.
create function private.assert_invite_tenant_write(p_ator uuid,p_empresa uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_subscription public.empresa_assinaturas%rowtype;
begin
 if not array['configuracoes.visualizar','usuarios.gerenciar','usuarios.convidar'] <@ private.admin_permissions(p_empresa,p_ator) then
   raise exception using errcode='42501',message='Convite nao autorizado neste tenant'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_empresa::text,0));
 select * into v_subscription from public.empresa_assinaturas where empresa_id=p_empresa for update;
 if not array['configuracoes.visualizar','usuarios.gerenciar','usuarios.convidar'] <@ private.admin_permissions(p_empresa,p_ator) then
   raise exception using errcode='42501',message='Acesso de convite revogado neste tenant'; end if;
 if v_subscription.id is not null and not (v_subscription.status='active' or
   (v_subscription.status='trialing' and v_subscription.trial_fim>now())) then
   raise exception using errcode='42501',message='Workspace em modo somente leitura'; end if;
end $$;
revoke all on function private.assert_invite_tenant_write(uuid,uuid) from public,anon,authenticated,service_role;
grant usage on schema private to service_role;
grant execute on function private.assert_invite_tenant_write(uuid,uuid) to service_role;

create or replace function public.admin_usuario_vincular_convite_server(
  p_ator_id uuid,
  p_empresa_id uuid,
  p_usuario_id uuid,
  p_unidade_id uuid,
  p_perfil_ids uuid[],
  p_justificativa text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_membership_id uuid;
  v_perfil_id uuid;
  v_permissoes text[];
begin
  if p_ator_id is null or p_empresa_id is null or p_usuario_id is null then
    raise exception using errcode='22023', message='Parametros obrigatorios ausentes';
  end if;
  if length(btrim(coalesce(p_justificativa,''))) < 5 then
    raise exception using errcode='22023', message='Justificativa deve possuir ao menos 5 caracteres';
  end if;
  if coalesce(array_length(p_perfil_ids,1),0) = 0 then
    raise exception using errcode='22023', message='Selecione ao menos um perfil';
  end if;

  perform private.assert_invite_tenant_write(p_ator_id,p_empresa_id);

  -- O ator precisa permanecer ativo globalmente e no tenant informado.
  if not exists (
    select 1
    from public.usuarios u
    join public.usuario_empresas ue
      on ue.usuario_id=u.id
     and ue.empresa_id=p_empresa_id
     and ue.status='ativo'
    where u.id=p_ator_id and u.ativo and u.status='ativo'
  ) then
    raise exception using errcode='42501', message='Ator sem membership ativo no tenant selecionado';
  end if;

  select coalesce(array_agg(distinct pm.codigo), array[]::text[])
    into v_permissoes
  from public.usuario_empresas ue
  join public.usuario_empresa_perfis uep on uep.usuario_empresa_id=ue.id
  join public.perfis p on p.id=uep.perfil_id
    and p.ativo
    and ((p.empresa_id is null and p.is_system) or p.empresa_id=p_empresa_id)
  join public.perfil_permissoes pp on pp.perfil_id=p.id
  join public.permissoes pm on pm.id=pp.permissao_id
  where ue.usuario_id=p_ator_id
    and ue.empresa_id=p_empresa_id
    and ue.status='ativo';

  if not ('configuracoes.visualizar'=any(v_permissoes))
     or not ('usuarios.gerenciar'=any(v_permissoes))
     or not ('usuarios.convidar'=any(v_permissoes)) then
    raise exception using errcode='42501', message='Sem permissao para convidar usuarios no tenant selecionado';
  end if;

  -- Lock already acquired before authorization and commercial checks above.

  if p_unidade_id is not null and not exists (
    select 1 from public.unidades
    where id=p_unidade_id and empresa_id=p_empresa_id and ativo
  ) then
    raise exception using errcode='22023', message='Unidade invalida, inativa ou fora da empresa';
  end if;

  foreach v_perfil_id in array p_perfil_ids loop
    if not exists (
      select 1 from public.perfis p
      where p.id=v_perfil_id and p.ativo
        and ((p.empresa_id is null and p.is_system) or p.empresa_id=p_empresa_id)
    ) then
      raise exception using errcode='22023', message='Perfil invalido, inativo ou fora da empresa';
    end if;

    if exists (
      select 1
      from public.perfil_permissoes pp
      join public.permissoes pm on pm.id=pp.permissao_id
      where pp.perfil_id=v_perfil_id
        and not (pm.codigo=any(v_permissoes))
    ) then
      raise exception using errcode='42501', message='Nao e permitido delegar um perfil com permissoes superiores as do ator';
    end if;
  end loop;

  perform 1
  from public.usuarios
  where id=p_usuario_id and empresa_id is null and status='pendente'
  for update;
  if not found then
    raise exception using errcode='P0002', message='Convite pendente nao encontrado';
  end if;

  update public.usuarios
  set empresa_id=p_empresa_id,
      unidade_id=p_unidade_id,
      status='ativo',
      ativo=true,
      updated_at=now()
  where id=p_usuario_id;

  insert into public.usuario_perfis(usuario_id,perfil_id,created_by)
  select p_usuario_id,x,p_ator_id from unnest(p_perfil_ids) x
  on conflict (usuario_id,perfil_id) do nothing;

  insert into public.usuario_empresas(usuario_id,empresa_id,unidade_id,status,is_owner,created_by)
  values(p_usuario_id,p_empresa_id,p_unidade_id,'ativo',false,p_ator_id)
  on conflict (usuario_id,empresa_id) do update
    set unidade_id=excluded.unidade_id,
        status='ativo',
        updated_at=now()
  returning id into v_membership_id;

  insert into public.usuario_empresa_perfis(usuario_empresa_id,perfil_id,created_by)
  select v_membership_id,x,p_ator_id from unnest(p_perfil_ids) x
  on conflict (usuario_empresa_id,perfil_id) do nothing;

  insert into public.auditoria_eventos(
    empresa_id,unidade_id,ator_id,entidade,registro_id,acao,
    antes,depois,justificativa,contexto
  ) values (
    p_empresa_id,p_unidade_id,p_ator_id,'usuario',p_usuario_id,'usuario.convidado_vinculado',
    jsonb_build_object('empresa_id',null,'status','pendente'),
    jsonb_build_object(
      'empresa_id',p_empresa_id,
      'unidade_id',p_unidade_id,
      'status','ativo',
      'perfil_ids',p_perfil_ids,
      'membership_id',v_membership_id
    ),
    btrim(p_justificativa),
    jsonb_build_object('origem','edge_function','modelo','membership','executor','service_role')
  );
end
$function$;

-- Keep the trusted billing/checkout counters identical to the canonical summary.
-- Fixed function names and a checked replacement of the immutable pre-32 body.
do $billing$
declare r record; v_source text; v_definition text;
begin
 if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in('processar_evento_assinatura_server','preparar_contratacao_server'))<>2 then
   raise exception using errcode='55000',message='Contratos comerciais anteriores ausentes ou ambiguos';
 end if;
 for r in select p.oid,p.prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in('processar_evento_assinatura_server','preparar_contratacao_server') loop
   v_source:=regexp_replace(r.prosrc,
     'select count\(\*\) into v_consumo_usuarios\s+from \(.*?\) ativos;',
     'select c.usuarios_ativos into v_consumo_usuarios from private.consumo_plano_empresa(p_empresa_id) c;', 'is');
   if v_source=r.prosrc then raise exception using errcode='55000',message='Contrato comercial anterior diverge da revisao'; end if;
   v_definition:=replace(pg_get_functiondef(r.oid),r.prosrc,v_source);
   execute v_definition;
 end loop;
end $billing$;

reset lock_timeout;
reset statement_timeout;
