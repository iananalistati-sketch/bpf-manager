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
from documents;
