-- Metadata only. No application/Auth rows, credentials, DDL or writes.
with target_tables as (
 select c.oid,c.relname,c.relowner,c.relrowsecurity,c.relforcerowsecurity,c.relacl
 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relkind='r' and c.relname in
 ('empresas','unidades','setores','usuarios','perfis','permissoes','usuario_perfis',
 'perfil_permissoes','usuario_empresas','usuario_empresa_perfis','auditoria_eventos',
 'empresa_planos','empresa_assinaturas','empresa_onboarding','saas_provisionamentos')
), grants as (
 select t.relname as tabela,null::text as coluna,
 case when a.grantee=0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end as grantee,
 a.privilege_type as privilegio,a.is_grantable as delegavel
 from target_tables t cross join lateral aclexplode(coalesce(t.relacl,acldefault('r',t.relowner))) a
 union all
 select t.relname,a.attname::text,
 case when g.grantee=0 then 'PUBLIC' else pg_get_userbyid(g.grantee) end,
 g.privilege_type,g.is_grantable
 from target_tables t join pg_attribute a on a.attrelid=t.oid and a.attnum>0 and not a.attisdropped
 cross join lateral aclexplode(a.attacl) g
), target_functions as (
 select n.nspname as esquema,p.oid::regprocedure::text as assinatura,p.proname,
 pg_get_userbyid(p.proowner) as owner,p.prosecdef as security_definer,
 array(select setting from unnest(p.proconfig) setting where setting like 'search_path=%') as configuracao,p.proacl::text as acl,
 md5(replace(p.prosrc,E'\r\n',E'\n')) as corpo_md5
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in('public','private') and (p.proname like 'admin_%'
 or p.proname in('primary_visible_empresa','assert_invite_tenant_write','consumo_plano_empresa',
 'validar_limite_usuario_legacy','validar_limite_membership','processar_evento_assinatura_server',
 'preparar_contratacao_server','ator_possui_permissao','usuario_admin_efetivo',
 'existe_outro_admin_efetivo','empresa_leitura_usuarios','empresa_gestao_perfis',
 'empresa_estrutura_admin','empresa_convite_usuarios','empresa_leitura_auditoria'))
)
select jsonb_build_object(
 'versoes',(select coalesce(jsonb_agg(version order by version),'[]'::jsonb) from supabase_migrations.schema_migrations),
 'tabelas',(select coalesce(jsonb_agg(jsonb_build_object('tabela',relname,'owner',pg_get_userbyid(relowner),
   'rls',relrowsecurity,'force_rls',relforcerowsecurity) order by relname),'[]'::jsonb) from target_tables),
 'policies',(select coalesce(jsonb_agg(to_jsonb(p) order by tablename,policyname),'[]'::jsonb)
   from pg_policies p where schemaname='public' and tablename in(select relname from target_tables)),
 'acls',(select coalesce(jsonb_agg(to_jsonb(g) order by tabela,coluna,grantee,privilegio),'[]'::jsonb) from grants g),
 'roles',(select coalesce(jsonb_agg(jsonb_build_object('nome',rolname,'login',rolcanlogin,
   'inherit',rolinherit,'superuser',rolsuper,'bypass_rls',rolbypassrls,'create_role',rolcreaterole)
   order by rolname),'[]'::jsonb) from pg_roles where rolname like 'bpf_%'),
 'membros_roles',(select coalesce(jsonb_agg(jsonb_build_object('role',r.rolname,'membro',u.rolname,
   'admin',m.admin_option,'inherit',m.inherit_option,'set',m.set_option) order by r.rolname,u.rolname),'[]'::jsonb)
   from pg_auth_members m join pg_roles r on r.oid=m.roleid join pg_roles u on u.oid=m.member
   where r.rolname like 'bpf_%'),
 'funcoes',(select coalesce(jsonb_agg(to_jsonb(f) order by esquema,assinatura),'[]'::jsonb) from target_functions f),
 'view_contexto',(select md5(replace(pg_get_viewdef(c.oid,true),E'\r\n',E'\n'))
   from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='v_meu_contexto' and c.relkind='v')
) as relatorio;
