-- Execute after the administrative-read migration, as postgres in an isolated database.
-- Fixtures and assertions are transactional. Never remove the final ROLLBACK.
-- With psql use -v ON_ERROR_STOP=1; disconnect on error to roll back an aborted transaction.
BEGIN;
SET LOCAL statement_timeout = '30s';

CREATE TEMP TABLE qa_ids (name text PRIMARY KEY, id uuid NOT NULL DEFAULT gen_random_uuid());
INSERT INTO qa_ids(name) VALUES
  ('company_a'), ('company_b'), ('unit_a'), ('unit_b'),
  ('admin'), ('colleague'), ('other_company'), ('pending'),
  ('profile_a'), ('profile_b'), ('inactive_profile'), ('split_profile');
GRANT SELECT ON qa_ids TO authenticated;

CREATE FUNCTION pg_temp.qa_id(key text) RETURNS uuid LANGUAGE sql STABLE
  AS $$ SELECT id FROM pg_temp.qa_ids WHERE name = key $$;
CREATE FUNCTION pg_temp.assert_ok(ok boolean, label text) RETURNS void LANGUAGE plpgsql
  AS $$ BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'QA failed: %', label; END IF; END $$;

INSERT INTO public.empresas(id, razao_social, nome_fantasia)
SELECT id, 'QA ' || id::text, 'QA ' || name FROM qa_ids WHERE name LIKE 'company_%';
INSERT INTO public.unidades(id, empresa_id, nome) VALUES
  (pg_temp.qa_id('unit_a'), pg_temp.qa_id('company_a'), 'QA Unidade A'),
  (pg_temp.qa_id('unit_b'), pg_temp.qa_id('company_b'), 'QA Unidade B');
INSERT INTO auth.users(id, email, raw_user_meta_data)
SELECT id, id::text || '@example.invalid', jsonb_build_object('nome', 'QA ' || name)
FROM qa_ids WHERE name IN ('admin', 'colleague', 'other_company', 'pending');
-- The existing Auth trigger creates public.usuarios with no privileges.
UPDATE public.usuarios SET empresa_id = pg_temp.qa_id('company_a'),
  unidade_id = pg_temp.qa_id('unit_a'), ativo = true, status = 'ativo'
WHERE id IN (pg_temp.qa_id('admin'), pg_temp.qa_id('colleague'));
UPDATE public.usuarios SET empresa_id = pg_temp.qa_id('company_b'),
  unidade_id = pg_temp.qa_id('unit_b'), ativo = true, status = 'ativo'
WHERE id = pg_temp.qa_id('other_company');
SELECT pg_temp.assert_ok((SELECT count(*) = 4 FROM public.usuarios WHERE id IN
  (pg_temp.qa_id('admin'), pg_temp.qa_id('colleague'), pg_temp.qa_id('other_company'), pg_temp.qa_id('pending'))), 'Auth trigger created four fixtures');

INSERT INTO public.perfis(id, empresa_id, nome, is_system, ativo) VALUES
  (pg_temp.qa_id('profile_a'), pg_temp.qa_id('company_a'), 'QA Admin A', false, true),
  (pg_temp.qa_id('profile_b'), pg_temp.qa_id('company_b'), 'QA Admin B', false, true),
  (pg_temp.qa_id('inactive_profile'), pg_temp.qa_id('company_a'), 'QA Inativo', false, false);
INSERT INTO public.perfil_permissoes(perfil_id, permissao_id)
SELECT f.id, p.id FROM qa_ids f CROSS JOIN public.permissoes p
WHERE f.name IN ('profile_a', 'profile_b', 'inactive_profile')
  AND p.codigo IN ('configuracoes.visualizar', 'usuarios.gerenciar');
SELECT pg_temp.assert_ok((SELECT count(*) = 6 FROM public.perfil_permissoes WHERE perfil_id IN
  (pg_temp.qa_id('profile_a'), pg_temp.qa_id('profile_b'), pg_temp.qa_id('inactive_profile'))), 'required permission catalog exists');
INSERT INTO public.usuario_perfis(usuario_id, perfil_id) VALUES
  (pg_temp.qa_id('admin'), pg_temp.qa_id('profile_a')),
  (pg_temp.qa_id('admin'), pg_temp.qa_id('inactive_profile')),
  (pg_temp.qa_id('colleague'), pg_temp.qa_id('profile_a')),
  (pg_temp.qa_id('other_company'), pg_temp.qa_id('profile_b'));

SELECT set_config('request.jwt.claim.sub', pg_temp.qa_id('admin')::text, true);
SELECT set_config('request.jwt.claims', jsonb_build_object('sub', pg_temp.qa_id('admin'), 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_ok(private.empresa_leitura_usuarios() = pg_temp.qa_id('company_a'), 'authorized scope derives from identity');
SELECT pg_temp.assert_ok((SELECT count(*) = 2 FROM public.usuarios), 'unfiltered query sees only company A');
SELECT pg_temp.assert_ok((SELECT count(*) = 0 FROM public.usuarios WHERE empresa_id = pg_temp.qa_id('company_b')), 'tampered company filter cannot read B');
SELECT pg_temp.assert_ok((SELECT count(*) = 0 FROM public.usuarios WHERE empresa_id IS NULL), 'pending without company is not exposed');
SELECT pg_temp.assert_ok((SELECT count(*) = 3 FROM public.usuario_perfis), 'same-company links including inactive profiles are readable');
SELECT pg_temp.assert_ok((SELECT count(*) = 0 FROM public.usuario_perfis WHERE usuario_id = pg_temp.qa_id('other_company')), 'B links are not exposed');
SELECT pg_temp.assert_ok((SELECT NOT ('QA Inativo' = ANY(perfis)) AND 'usuarios.gerenciar' = ANY(permissoes) FROM public.v_meu_contexto), 'view excludes inactive profile');

-- Company B has equivalent access, never company A's rows.
SELECT set_config('request.jwt.claim.sub', pg_temp.qa_id('other_company')::text, true);
SELECT pg_temp.assert_ok(private.empresa_leitura_usuarios() = pg_temp.qa_id('company_b'), 'B scope derives from B identity');
SELECT pg_temp.assert_ok((SELECT count(*) = 1 AND bool_and(empresa_id = pg_temp.qa_id('company_b')) FROM public.usuarios), 'B cannot read A');
SELECT set_config('request.jwt.claim.sub', pg_temp.qa_id('admin')::text, true);

-- Each required permission is independently necessary. Self-read remains for bootstrap.
RESET ROLE;
DELETE FROM public.perfil_permissoes WHERE perfil_id = pg_temp.qa_id('profile_a')
  AND permissao_id = (SELECT id FROM public.permissoes WHERE codigo = 'usuarios.gerenciar');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_ok(private.empresa_leitura_usuarios() IS NULL, 'missing usuarios.gerenciar denies scope');
SELECT pg_temp.assert_ok((SELECT count(*) = 1 AND bool_and(id = auth.uid()) FROM public.usuarios), 'missing permission keeps self only');
SELECT pg_temp.assert_ok((SELECT NOT ('usuarios.gerenciar' = ANY(permissoes)) FROM public.v_meu_contexto), 'inactive profile does not restore revoked permission');
SELECT pg_temp.assert_ok((SELECT count(*) = 0 FROM public.usuario_perfis WHERE usuario_id <> auth.uid()), 'missing permission denies colleague links');
RESET ROLE;
-- Permissions may legitimately be combined across active compatible profiles.
INSERT INTO public.perfis(id, empresa_id, nome) VALUES (pg_temp.qa_id('split_profile'), pg_temp.qa_id('company_a'), 'QA Split');
INSERT INTO public.perfil_permissoes(perfil_id, permissao_id)
SELECT pg_temp.qa_id('split_profile'), id FROM public.permissoes WHERE codigo = 'usuarios.gerenciar';
INSERT INTO public.usuario_perfis(usuario_id, perfil_id) VALUES (pg_temp.qa_id('admin'), pg_temp.qa_id('split_profile'));
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_ok(private.empresa_leitura_usuarios() = pg_temp.qa_id('company_a'), 'permissions combine across active profiles');
RESET ROLE;
DELETE FROM public.usuario_perfis WHERE perfil_id = pg_temp.qa_id('split_profile');
INSERT INTO public.perfil_permissoes(perfil_id, permissao_id)
SELECT pg_temp.qa_id('profile_a'), id FROM public.permissoes WHERE codigo = 'usuarios.gerenciar';
DELETE FROM public.perfil_permissoes WHERE perfil_id = pg_temp.qa_id('profile_a')
  AND permissao_id = (SELECT id FROM public.permissoes WHERE codigo = 'configuracoes.visualizar');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_ok(private.empresa_leitura_usuarios() IS NULL, 'missing configuracoes.visualizar denies scope');
SELECT pg_temp.assert_ok((SELECT count(*) = 1 FROM public.usuarios), 'missing view permission denies colleagues');
RESET ROLE;
INSERT INTO public.perfil_permissoes(perfil_id, permissao_id)
SELECT pg_temp.qa_id('profile_a'), id FROM public.permissoes WHERE codigo = 'configuracoes.visualizar';

UPDATE public.usuarios SET ativo = false WHERE id = pg_temp.qa_id('admin');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_ok(private.empresa_leitura_usuarios() IS NULL, 'ativo=false denies scope');
SELECT pg_temp.assert_ok((SELECT count(*) = 1 FROM public.usuarios), 'inactive identity sees self only');
RESET ROLE;
UPDATE public.usuarios SET ativo = true, status = 'bloqueado' WHERE id = pg_temp.qa_id('admin');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_ok(private.empresa_leitura_usuarios() IS NULL, 'blocked status denies scope');
SELECT pg_temp.assert_ok((SELECT count(*) = 1 FROM public.usuarios), 'blocked identity sees self only');
RESET ROLE;
UPDATE public.usuarios SET status = 'inativo' WHERE id = pg_temp.qa_id('admin');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_ok(private.empresa_leitura_usuarios() IS NULL, 'inactive status denies scope');
RESET ROLE;
UPDATE public.usuarios SET status = 'pendente' WHERE id = pg_temp.qa_id('admin');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_ok(private.empresa_leitura_usuarios() IS NULL, 'pending status denies scope');
RESET ROLE;
UPDATE public.usuarios SET status = 'ativo' WHERE id = pg_temp.qa_id('admin');
UPDATE public.usuarios SET empresa_id = NULL, unidade_id = NULL WHERE id = pg_temp.qa_id('admin');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_ok(private.empresa_leitura_usuarios() IS NULL, 'identity without company denies scope');
SELECT pg_temp.assert_ok((SELECT count(*) = 1 FROM public.usuarios), 'identity without company sees only self');
SELECT set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
SELECT pg_temp.assert_ok(private.empresa_leitura_usuarios() IS NULL, 'missing identity denies scope');
SELECT pg_temp.assert_ok((SELECT count(*) = 0 FROM public.usuarios), 'missing identity cannot enumerate users');
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT pg_temp.assert_ok(private.empresa_leitura_usuarios() IS NULL, 'missing subject denies scope');
SELECT set_config('request.jwt.claim.sub', pg_temp.qa_id('admin')::text, true);
RESET ROLE;
UPDATE public.usuarios SET empresa_id = pg_temp.qa_id('company_a'), unidade_id = pg_temp.qa_id('unit_a') WHERE id = pg_temp.qa_id('admin');
UPDATE public.perfis SET ativo = false WHERE id = pg_temp.qa_id('profile_a');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_ok(private.empresa_leitura_usuarios() IS NULL, 'all profiles inactive deny scope');
SELECT pg_temp.assert_ok((SELECT cardinality(perfis) = 0 AND cardinality(permissoes) = 0 FROM public.v_meu_contexto), 'inactive profiles grant no context');
RESET ROLE;

-- Legacy mismatched profile links must not authorize the user in another company.
INSERT INTO public.usuario_perfis(usuario_id, perfil_id) VALUES (pg_temp.qa_id('admin'), pg_temp.qa_id('profile_b'));
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_ok(private.empresa_leitura_usuarios() IS NULL, 'foreign profile cannot grant administrative scope');
SELECT pg_temp.assert_ok((SELECT cardinality(permissoes) = 0 FROM public.v_meu_contexto), 'foreign profile cannot grant context permissions');
RESET ROLE;

UPDATE public.perfis SET empresa_id = NULL, is_system = true WHERE id = pg_temp.qa_id('split_profile');
INSERT INTO public.perfil_permissoes(perfil_id, permissao_id)
SELECT pg_temp.qa_id('split_profile'), id FROM public.permissoes WHERE codigo = 'configuracoes.visualizar';
INSERT INTO public.usuario_perfis(usuario_id, perfil_id) VALUES (pg_temp.qa_id('admin'), pg_temp.qa_id('split_profile'));
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_ok(private.empresa_leitura_usuarios() = pg_temp.qa_id('company_a'), 'active global system profile authorizes own company');
SELECT pg_temp.assert_ok((SELECT 'usuarios.gerenciar' = ANY(permissoes) FROM public.v_meu_contexto), 'global system permissions remain in context');
DO $$ BEGIN
  BEGIN
    UPDATE public.usuarios SET nome = 'not permitted' WHERE id = auth.uid();
    RAISE EXCEPTION 'QA failed: authenticated write succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;
UPDATE public.perfis SET is_system = false WHERE id = pg_temp.qa_id('split_profile');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_ok(private.empresa_leitura_usuarios() IS NULL, 'global non-system profile cannot authorize');
SELECT pg_temp.assert_ok((SELECT cardinality(permissoes) = 0 FROM public.v_meu_contexto), 'global non-system permissions excluded');
RESET ROLE;

-- This executes as the fixture owner: failure must come from FK, not RLS or grants.
DO $$
BEGIN
  BEGIN
    UPDATE public.usuarios SET unidade_id = pg_temp.qa_id('unit_b') WHERE id = pg_temp.qa_id('colleague');
    RAISE EXCEPTION 'QA failed: cross-company unit accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
  BEGIN
    UPDATE public.unidades SET empresa_id = pg_temp.qa_id('company_b') WHERE id = pg_temp.qa_id('unit_a');
    RAISE EXCEPTION 'QA failed: referenced unit reassigned to another company';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
END $$;
UPDATE public.usuarios SET unidade_id = NULL WHERE id = pg_temp.qa_id('colleague');
UPDATE public.usuarios SET unidade_id = pg_temp.qa_id('unit_a') WHERE id = pg_temp.qa_id('colleague');
SELECT pg_temp.assert_ok((SELECT unidade_id = pg_temp.qa_id('unit_a') FROM public.usuarios WHERE id = pg_temp.qa_id('colleague')), 'valid unit and null unit accepted');

SELECT pg_temp.assert_ok(NOT has_table_privilege('authenticated', 'public.usuarios', 'INSERT,UPDATE,DELETE,TRUNCATE'), 'user writes remain revoked');
SELECT pg_temp.assert_ok(NOT has_table_privilege('authenticated', 'public.usuario_perfis', 'INSERT,UPDATE,DELETE,TRUNCATE'), 'profile-link writes remain revoked');
SELECT pg_temp.assert_ok((SELECT 'security_invoker=true' = ANY(reloptions) FROM pg_class WHERE oid = 'public.v_meu_contexto'::regclass), 'context view remains security invoker');
SELECT pg_temp.assert_ok(NOT has_table_privilege('authenticated', 'public.v_meu_contexto', 'INSERT,UPDATE,DELETE,TRUNCATE'), 'view write grants revoked');
SELECT pg_temp.assert_ok((SELECT NOT rolcanlogin AND NOT rolsuper AND NOT rolbypassrls AND NOT rolinherit AND NOT rolcreaterole FROM pg_roles WHERE rolname = 'bpf_authz_reader'), 'helper owner is restricted');
SELECT pg_temp.assert_ok(NOT pg_has_role('authenticated', 'bpf_authz_reader', 'MEMBER'), 'client cannot assume helper owner');
SELECT pg_temp.assert_ok(NOT has_schema_privilege('bpf_authz_reader', 'private', 'CREATE'), 'temporary CREATE revoked');
SELECT pg_temp.assert_ok(NOT has_column_privilege('bpf_authz_reader', 'public.usuarios', 'email', 'SELECT'), 'helper owner cannot read unnecessary personal columns');
SELECT pg_temp.assert_ok(NOT has_function_privilege('anon', 'private.empresa_leitura_usuarios()', 'EXECUTE'), 'anonymous cannot execute helper');
SELECT pg_temp.assert_ok(NOT has_function_privilege('service_role', 'private.empresa_leitura_usuarios()', 'EXECUTE'), 'service role receives no helper execution grant');
SELECT pg_temp.assert_ok((SELECT bool_or(admin_option) AND bool_and(NOT inherit_option AND NOT set_option)
  FROM pg_auth_members WHERE roleid = 'bpf_authz_reader'::regrole AND member = 'postgres'::regrole), 'DBA retains administration without SET or inheritance');
SELECT pg_temp.assert_ok((SELECT prosecdef AND proowner = 'bpf_authz_reader'::regrole AND 'search_path=""' = ANY(proconfig)
  FROM pg_proc WHERE oid = 'private.empresa_leitura_usuarios()'::regprocedure), 'helper runs with fixed path and restricted owner');
SELECT 'PASS: administrative read, tenant isolation, status/permissions, inactive profiles, company/unit FK and read-only grants' AS result;
ROLLBACK;
