-- Execute after all administration migrations in isolated PostgreSQL. Final ROLLBACK is mandatory.
BEGIN;
SET LOCAL statement_timeout = '30s';

CREATE TEMP TABLE qa_admin_ids(name text PRIMARY KEY, id uuid NOT NULL DEFAULT gen_random_uuid());
INSERT INTO qa_admin_ids(name) VALUES
 ('company_a'),('company_b'),('unit_a'),('unit_b'),('actor'),('invitee'),('profile_admin'),('profile_system'),('custom_profile');
GRANT SELECT ON qa_admin_ids TO authenticated;
CREATE FUNCTION pg_temp.aid(k text) RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT id FROM pg_temp.qa_admin_ids WHERE name=k $$;
CREATE FUNCTION pg_temp.assert_admin(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'QA admin failed: %',label; END IF; END $$;

INSERT INTO public.empresas(id,razao_social,nome_fantasia) VALUES
 (pg_temp.aid('company_a'),'Empresa A','A'),(pg_temp.aid('company_b'),'Empresa B','B');
INSERT INTO public.unidades(id,empresa_id,nome,codigo) VALUES
 (pg_temp.aid('unit_a'),pg_temp.aid('company_a'),'Unidade A','UA'),
 (pg_temp.aid('unit_b'),pg_temp.aid('company_b'),'Unidade B','UB');
INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
 (pg_temp.aid('actor'),'actor@example.invalid','{"nome":"Actor"}'::jsonb),
 (pg_temp.aid('invitee'),'invitee@example.invalid','{"nome":"Invitee"}'::jsonb);
UPDATE public.usuarios SET empresa_id=pg_temp.aid('company_a'),unidade_id=pg_temp.aid('unit_a'),status='ativo',ativo=true WHERE id=pg_temp.aid('actor');

INSERT INTO public.perfis(id,empresa_id,nome,is_system,ativo) VALUES
 (pg_temp.aid('profile_admin'),pg_temp.aid('company_a'),'QA Admin',false,true),
 (pg_temp.aid('profile_system'),null,'QA System',true,true);
INSERT INTO public.perfil_permissoes(perfil_id,permissao_id)
SELECT pg_temp.aid('profile_admin'),id FROM public.permissoes
WHERE codigo IN ('configuracoes.visualizar','configuracoes.gerenciar','usuarios.gerenciar','perfis.gerenciar','usuarios.convidar','estrutura.gerenciar','auditoria.visualizar');
INSERT INTO public.usuario_perfis(usuario_id,perfil_id) VALUES(pg_temp.aid('actor'),pg_temp.aid('profile_admin'));

-- Temporary result holders are created by the deployer before SET ROLE so both
-- the deployer and authenticated test role can use them without ownership surprises.
CREATE TEMP TABLE qa_profile_created(id uuid PRIMARY KEY);
GRANT SELECT, INSERT, DELETE ON qa_profile_created TO authenticated;

SELECT set_config('request.jwt.claim.sub',pg_temp.aid('actor')::text,true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.aid('actor'),'role','authenticated')::text,true);
SET LOCAL ROLE authenticated;

-- Company structure management.
SELECT public.admin_empresa_atualizar('Empresa A Atualizada','A Nova','00.000.000/0001-00','QA altera empresa');
SELECT public.admin_unidade_salvar(null,'Unidade Nova','UN',true,'QA cria unidade');
RESET ROLE;
SELECT pg_temp.assert_admin((SELECT razao_social='Empresa A Atualizada' FROM public.empresas WHERE id=pg_temp.aid('company_a')),'company updated');
SELECT pg_temp.assert_admin((SELECT count(*)=1 FROM public.unidades WHERE empresa_id=pg_temp.aid('company_a') AND nome='Unidade Nova'),'unit created');
SELECT id INTO TEMP TABLE qa_new_unit FROM public.unidades WHERE empresa_id=pg_temp.aid('company_a') AND nome='Unidade Nova';
GRANT SELECT ON qa_new_unit TO authenticated;
SET LOCAL ROLE authenticated;
SELECT public.admin_setor_salvar(null,(SELECT id FROM qa_new_unit),'Qualidade','QLD',true,'QA cria setor');
RESET ROLE;
SELECT pg_temp.assert_admin((SELECT count(*)=1 FROM public.setores WHERE nome='Qualidade'),'sector created');

-- Custom profile CRUD and system-profile immutability.
SET LOCAL ROLE authenticated;
DELETE FROM qa_profile_created;
INSERT INTO qa_profile_created(id)
SELECT public.admin_perfil_criar('QA Custom','Perfil customizado',ARRAY[(SELECT id FROM public.permissoes WHERE codigo='auditoria.visualizar')],'QA cria perfil');
RESET ROLE;
SELECT pg_temp.assert_admin((SELECT count(*)=1 FROM public.perfis WHERE id=(SELECT id FROM qa_profile_created) AND empresa_id=pg_temp.aid('company_a') AND not is_system),'custom profile created');
SET LOCAL ROLE authenticated;
SELECT public.admin_perfil_atualizar((SELECT id FROM qa_profile_created),'QA Custom 2','Atualizado',true,ARRAY[(SELECT id FROM public.permissoes WHERE codigo='estrutura.gerenciar')],'QA edita perfil');
DO $$ BEGIN
  BEGIN
    PERFORM public.admin_perfil_atualizar(pg_temp.aid('profile_system'),'Hack','x',true,'{}'::uuid[],'QA tenta sistema');
    RAISE EXCEPTION 'QA admin failed: system profile mutated';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;

-- Invite linkage: only the explicitly targeted unlinked pending user is promoted.
SELECT public.admin_usuario_vincular_convite(pg_temp.aid('invitee'),pg_temp.aid('unit_a'),ARRAY[(SELECT id FROM qa_profile_created)],'QA vincula convite');
RESET ROLE;
SELECT pg_temp.assert_admin((SELECT empresa_id=pg_temp.aid('company_a') AND status='ativo' AND ativo FROM public.usuarios WHERE id=pg_temp.aid('invitee')),'invitee linked and active');
SELECT pg_temp.assert_admin((SELECT count(*)=1 FROM public.usuario_perfis WHERE usuario_id=pg_temp.aid('invitee') AND perfil_id=(SELECT id FROM qa_profile_created)),'invitee profile linked');

-- Cross-company structure must fail.
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  BEGIN
    PERFORM public.admin_setor_salvar(null,pg_temp.aid('unit_b'),'Invasao','X',true,'QA setor externo');
    RAISE EXCEPTION 'QA admin failed: cross-company sector accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END $$;

-- Audit is readable to authorized actor and remains same-company scoped.
SELECT pg_temp.assert_admin((SELECT count(*) >= 5 FROM public.auditoria_eventos),'authorized audit visible');
RESET ROLE;
INSERT INTO public.auditoria_eventos(empresa_id,ator_id,entidade,registro_id,acao,justificativa)
VALUES(pg_temp.aid('company_b'),pg_temp.aid('actor'),'qa',gen_random_uuid(),'qa.foreign','QA foreign audit');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_admin((SELECT count(*)=0 FROM public.auditoria_eventos WHERE empresa_id=pg_temp.aid('company_b')),'foreign audit hidden');
RESET ROLE;

-- Direct writes remain closed to the client.
SELECT pg_temp.assert_admin(NOT has_table_privilege('authenticated','public.empresas','UPDATE'),'no direct company update');
SELECT pg_temp.assert_admin(NOT has_table_privilege('authenticated','public.unidades','INSERT,UPDATE'),'no direct unit writes');
SELECT pg_temp.assert_admin(NOT has_table_privilege('authenticated','public.setores','INSERT,UPDATE'),'no direct sector writes');
SELECT pg_temp.assert_admin(NOT has_table_privilege('authenticated','public.perfis','INSERT,UPDATE'),'no direct profile writes');
SELECT pg_temp.assert_admin(has_function_privilege('authenticated','public.admin_perfil_criar(text,text,uuid[],text)','EXECUTE'),'profile rpc exposed to authenticated');
SELECT pg_temp.assert_admin(NOT has_function_privilege('anon','public.admin_perfil_criar(text,text,uuid[],text)','EXECUTE'),'profile rpc hidden from anon');

SELECT 'PASS: complete administration foundation, invite linkage, structure/profile writes, audit isolation and no direct client writes' AS result;
ROLLBACK;
