-- Regression coverage for structure-only administration and row-snapshot/update grant paths.
BEGIN;
SET LOCAL statement_timeout = '30s';

CREATE TEMP TABLE qa_structure_ids(name text PRIMARY KEY, id uuid NOT NULL DEFAULT gen_random_uuid());
INSERT INTO qa_structure_ids(name) VALUES ('company'),('unit_a'),('unit_b'),('actor'),('profile');
GRANT SELECT ON qa_structure_ids TO authenticated;
CREATE FUNCTION pg_temp.stid(k text) RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT id FROM pg_temp.qa_structure_ids WHERE name=k $$;
CREATE FUNCTION pg_temp.stassert(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'QA structure failed: %',label; END IF; END $$;

-- Temporary result holders are always owned by the deployer. Client roles receive only the
-- minimum grants needed to write/read results while exercising RPCs under SET ROLE.
CREATE TEMP TABLE qa_structure_sector(id uuid PRIMARY KEY);
GRANT SELECT, INSERT, DELETE ON qa_structure_sector TO authenticated;

INSERT INTO public.empresas(id,razao_social) VALUES(pg_temp.stid('company'),'QA Structure');
INSERT INTO public.unidades(id,empresa_id,nome,codigo) VALUES
 (pg_temp.stid('unit_a'),pg_temp.stid('company'),'Unidade A','UA'),
 (pg_temp.stid('unit_b'),pg_temp.stid('company'),'Unidade B','UB');
INSERT INTO auth.users(id,email) VALUES(pg_temp.stid('actor'),'structure@example.invalid');
UPDATE public.usuarios SET empresa_id=pg_temp.stid('company'),unidade_id=pg_temp.stid('unit_a'),status='ativo',ativo=true WHERE id=pg_temp.stid('actor');
INSERT INTO public.perfis(id,empresa_id,nome,is_system,ativo) VALUES(pg_temp.stid('profile'),pg_temp.stid('company'),'Structure Manager',false,true);
INSERT INTO public.perfil_permissoes(perfil_id,permissao_id)
SELECT pg_temp.stid('profile'),id FROM public.permissoes WHERE codigo IN ('configuracoes.visualizar','estrutura.gerenciar');
INSERT INTO public.usuario_perfis(usuario_id,perfil_id) VALUES(pg_temp.stid('actor'),pg_temp.stid('profile'));

SELECT set_config('request.jwt.claim.sub',pg_temp.stid('actor')::text,true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.stid('actor'),'role','authenticated')::text,true);
SET LOCAL ROLE authenticated;

-- Must work without usuarios.gerenciar: update uses a full unidade row snapshot for audit.
SELECT public.admin_unidade_salvar(pg_temp.stid('unit_b'),'Unidade B Editada','UB2',true,'QA edita unidade');
DELETE FROM qa_structure_sector;
INSERT INTO qa_structure_sector(id)
SELECT public.admin_setor_salvar(null,pg_temp.stid('unit_a'),'Qualidade','QLD',true,'QA cria setor');
RESET ROLE;
SELECT pg_temp.stassert((SELECT nome='Unidade B Editada' AND codigo='UB2' FROM public.unidades WHERE id=pg_temp.stid('unit_b')),'unit update works for structure-only actor');

SET LOCAL ROLE authenticated;
SELECT public.admin_setor_salvar((SELECT id FROM qa_structure_sector),pg_temp.stid('unit_b'),'Qualidade Central','QLD2',true,'QA move setor');
RESET ROLE;
SELECT pg_temp.stassert((SELECT unidade_id=pg_temp.stid('unit_b') AND nome='Qualidade Central' FROM public.setores WHERE id=(SELECT id FROM qa_structure_sector)),'sector move uses allowed unidade_id update');
SELECT pg_temp.stassert((SELECT count(*)>=3 FROM public.auditoria_eventos WHERE empresa_id=pg_temp.stid('company')),'structure changes audited');
SELECT pg_temp.stassert(NOT has_table_privilege('authenticated','public.unidades','UPDATE'),'authenticated still lacks direct unit update');
SELECT pg_temp.stassert(NOT has_table_privilege('authenticated','public.setores','UPDATE'),'authenticated still lacks direct sector update');

SELECT 'PASS: structure-only administration updates units/sectors with audit and no direct client writes' AS result;
ROLLBACK;
