-- Execute after all administrative-user migrations in an isolated database.
-- Fixtures and assertions are transactional. Never remove the final ROLLBACK.
BEGIN;
SET LOCAL statement_timeout = '30s';

CREATE TEMP TABLE qa_cmd_ids (name text PRIMARY KEY, id uuid NOT NULL DEFAULT gen_random_uuid());
INSERT INTO qa_cmd_ids(name) VALUES
  ('company_a'), ('company_b'), ('unit_a1'), ('unit_a2'), ('unit_b'),
  ('manager'), ('target'), ('sole_admin'), ('second_admin'), ('foreign_user'), ('pending_user'),
  ('profile_manager'), ('profile_admin'), ('profile_basic'), ('profile_b');
GRANT SELECT ON qa_cmd_ids TO authenticated;

CREATE FUNCTION pg_temp.cmd_id(key text) RETURNS uuid LANGUAGE sql STABLE
  AS $$ SELECT id FROM pg_temp.qa_cmd_ids WHERE name = key $$;
CREATE FUNCTION pg_temp.cmd_assert(ok boolean, label text) RETURNS void LANGUAGE plpgsql
  AS $$ BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'QA command failed: %', label; END IF; END $$;

INSERT INTO public.empresas(id, razao_social, nome_fantasia)
SELECT id, 'QA CMD ' || id::text, 'QA CMD ' || name FROM qa_cmd_ids WHERE name LIKE 'company_%';
INSERT INTO public.unidades(id, empresa_id, nome) VALUES
  (pg_temp.cmd_id('unit_a1'), pg_temp.cmd_id('company_a'), 'QA A1'),
  (pg_temp.cmd_id('unit_a2'), pg_temp.cmd_id('company_a'), 'QA A2'),
  (pg_temp.cmd_id('unit_b'), pg_temp.cmd_id('company_b'), 'QA B');

INSERT INTO auth.users(id, email, raw_user_meta_data)
SELECT id, id::text || '@example.invalid', jsonb_build_object('nome', 'QA ' || name)
FROM qa_cmd_ids
WHERE name IN ('manager','target','sole_admin','second_admin','foreign_user','pending_user');

UPDATE public.usuarios SET empresa_id = pg_temp.cmd_id('company_a'), unidade_id = pg_temp.cmd_id('unit_a1'), ativo = true, status = 'ativo'
WHERE id IN (pg_temp.cmd_id('manager'), pg_temp.cmd_id('target'), pg_temp.cmd_id('sole_admin'), pg_temp.cmd_id('second_admin'));
UPDATE public.usuarios SET empresa_id = pg_temp.cmd_id('company_b'), unidade_id = pg_temp.cmd_id('unit_b'), ativo = true, status = 'ativo'
WHERE id = pg_temp.cmd_id('foreign_user');
UPDATE public.usuarios SET empresa_id = pg_temp.cmd_id('company_a'), unidade_id = pg_temp.cmd_id('unit_a1'), ativo = false, status = 'pendente'
WHERE id = pg_temp.cmd_id('pending_user');

-- Ensure the four permissions used by command authorization/admin-safety exist in the fixture.
INSERT INTO public.permissoes(codigo)
VALUES ('configuracoes.gerenciar'), ('perfis.gerenciar')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO public.perfis(id, empresa_id, nome, is_system, ativo) VALUES
  (pg_temp.cmd_id('profile_manager'), pg_temp.cmd_id('company_a'), 'QA Manager', false, true),
  (pg_temp.cmd_id('profile_admin'), pg_temp.cmd_id('company_a'), 'QA Admin', false, true),
  (pg_temp.cmd_id('profile_basic'), pg_temp.cmd_id('company_a'), 'QA Basic', false, true),
  (pg_temp.cmd_id('profile_b'), pg_temp.cmd_id('company_b'), 'QA B Profile', false, true);

-- Manager can administer users/profiles but is deliberately not an effective critical admin.
INSERT INTO public.perfil_permissoes(perfil_id, permissao_id)
SELECT pg_temp.cmd_id('profile_manager'), id FROM public.permissoes
WHERE codigo IN ('configuracoes.visualizar','usuarios.gerenciar','perfis.gerenciar');
-- Critical admin additionally owns configuracoes.gerenciar.
INSERT INTO public.perfil_permissoes(perfil_id, permissao_id)
SELECT pg_temp.cmd_id('profile_admin'), id FROM public.permissoes
WHERE codigo IN ('configuracoes.visualizar','usuarios.gerenciar','perfis.gerenciar','configuracoes.gerenciar');
INSERT INTO public.perfil_permissoes(perfil_id, permissao_id)
SELECT pg_temp.cmd_id('profile_b'), id FROM public.permissoes
WHERE codigo IN ('configuracoes.visualizar','usuarios.gerenciar','perfis.gerenciar','configuracoes.gerenciar');

INSERT INTO public.usuario_perfis(usuario_id, perfil_id) VALUES
  (pg_temp.cmd_id('manager'), pg_temp.cmd_id('profile_manager')),
  (pg_temp.cmd_id('target'), pg_temp.cmd_id('profile_basic')),
  (pg_temp.cmd_id('sole_admin'), pg_temp.cmd_id('profile_admin')),
  (pg_temp.cmd_id('foreign_user'), pg_temp.cmd_id('profile_b'));

-- Authenticate as the non-critical manager from company A.
SELECT set_config('request.jwt.claim.sub', pg_temp.cmd_id('manager')::text, true);
SELECT set_config('request.jwt.claims', jsonb_build_object('sub', pg_temp.cmd_id('manager'), 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;

SELECT pg_temp.cmd_assert(private.empresa_leitura_usuarios() = pg_temp.cmd_id('company_a'), 'manager has user-admin company');
SELECT pg_temp.cmd_assert(private.empresa_gestao_perfis() = pg_temp.cmd_id('company_a'), 'manager has profile-admin company');

-- Status: normal target can be blocked and reactivated, with atomic audit.
SELECT public.admin_usuario_alterar_status(pg_temp.cmd_id('target'), 'bloqueado', 'QA bloqueio controlado');
RESET ROLE;
SELECT pg_temp.cmd_assert((SELECT status = 'bloqueado' AND ativo = false FROM public.usuarios WHERE id = pg_temp.cmd_id('target')), 'target blocked');
SELECT pg_temp.cmd_assert((SELECT count(*) = 1 FROM public.auditoria_eventos WHERE registro_id = pg_temp.cmd_id('target') AND acao = 'usuario.status_alterado'), 'status audit inserted');
SET LOCAL ROLE authenticated;
SELECT public.admin_usuario_alterar_status(pg_temp.cmd_id('target'), 'ativo', 'QA reativacao controlada');

-- Self-block, pending activation and foreign-company target must fail.
DO $$ BEGIN
  BEGIN
    PERFORM public.admin_usuario_alterar_status(pg_temp.cmd_id('manager'), 'bloqueado', 'QA self block');
    RAISE EXCEPTION 'QA command failed: self block accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.admin_usuario_alterar_status(pg_temp.cmd_id('pending_user'), 'ativo', 'QA pending bypass');
    RAISE EXCEPTION 'QA command failed: pending activation accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.admin_usuario_alterar_status(pg_temp.cmd_id('foreign_user'), 'bloqueado', 'QA foreign block');
    RAISE EXCEPTION 'QA command failed: foreign company accepted';
  EXCEPTION WHEN no_data_found THEN NULL; END;
END $$;

-- The sole effective admin cannot be blocked by a manager who is not effective admin.
DO $$ BEGIN
  BEGIN
    PERFORM public.admin_usuario_alterar_status(pg_temp.cmd_id('sole_admin'), 'bloqueado', 'QA ultimo admin');
    RAISE EXCEPTION 'QA command failed: last effective admin could be blocked';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;

-- Once a second critical admin exists, blocking the first is allowed.
RESET ROLE;
INSERT INTO public.usuario_perfis(usuario_id, perfil_id) VALUES (pg_temp.cmd_id('second_admin'), pg_temp.cmd_id('profile_admin'));
SET LOCAL ROLE authenticated;
SELECT public.admin_usuario_alterar_status(pg_temp.cmd_id('sole_admin'), 'bloqueado', 'QA com segundo admin');
RESET ROLE;
SELECT pg_temp.cmd_assert((SELECT status = 'bloqueado' FROM public.usuarios WHERE id = pg_temp.cmd_id('sole_admin')), 'critical admin blocked only with another available');
UPDATE public.usuarios SET status = 'ativo', ativo = true WHERE id = pg_temp.cmd_id('sole_admin');
DELETE FROM public.usuario_perfis WHERE usuario_id = pg_temp.cmd_id('second_admin') AND perfil_id = pg_temp.cmd_id('profile_admin');

-- Unit: same-company active unit succeeds; foreign unit is rejected by server-side validation.
SET LOCAL ROLE authenticated;
SELECT public.admin_usuario_alterar_unidade(pg_temp.cmd_id('target'), pg_temp.cmd_id('unit_a2'), 'QA troca de unidade');
RESET ROLE;
SELECT pg_temp.cmd_assert((SELECT unidade_id = pg_temp.cmd_id('unit_a2') FROM public.usuarios WHERE id = pg_temp.cmd_id('target')), 'same-company unit accepted');
SELECT pg_temp.cmd_assert((SELECT count(*) = 1 FROM public.auditoria_eventos WHERE registro_id = pg_temp.cmd_id('target') AND acao = 'usuario.unidade_alterada'), 'unit audit inserted');
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  BEGIN
    PERFORM public.admin_usuario_alterar_unidade(pg_temp.cmd_id('target'), pg_temp.cmd_id('unit_b'), 'QA unidade externa');
    RAISE EXCEPTION 'QA command failed: cross-company unit accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END $$;

-- Profiles: manager can assign/remove compatible profile from another user.
SELECT public.admin_usuario_alterar_perfil(pg_temp.cmd_id('target'), pg_temp.cmd_id('profile_manager'), 'atribuir', 'QA atribuir perfil');
RESET ROLE;
SELECT pg_temp.cmd_assert((SELECT count(*) = 1 FROM public.usuario_perfis WHERE usuario_id = pg_temp.cmd_id('target') AND perfil_id = pg_temp.cmd_id('profile_manager')), 'profile assigned');
SELECT pg_temp.cmd_assert((SELECT count(*) = 1 FROM public.auditoria_eventos WHERE registro_id = pg_temp.cmd_id('target') AND acao = 'usuario.perfil_atribuido'), 'profile assignment audited');
SET LOCAL ROLE authenticated;
SELECT public.admin_usuario_alterar_perfil(pg_temp.cmd_id('target'), pg_temp.cmd_id('profile_manager'), 'remover', 'QA remover perfil');
RESET ROLE;
SELECT pg_temp.cmd_assert((SELECT count(*) = 0 FROM public.usuario_perfis WHERE usuario_id = pg_temp.cmd_id('target') AND perfil_id = pg_temp.cmd_id('profile_manager')), 'profile removed');
SELECT pg_temp.cmd_assert((SELECT count(*) = 1 FROM public.auditoria_eventos WHERE registro_id = pg_temp.cmd_id('target') AND acao = 'usuario.perfil_removido'), 'profile removal audited');

-- Self profile change and cross-company profile assignment are denied.
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  BEGIN
    PERFORM public.admin_usuario_alterar_perfil(pg_temp.cmd_id('manager'), pg_temp.cmd_id('profile_admin'), 'atribuir', 'QA auto elevacao');
    RAISE EXCEPTION 'QA command failed: self elevation accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.admin_usuario_alterar_perfil(pg_temp.cmd_id('target'), pg_temp.cmd_id('profile_b'), 'atribuir', 'QA perfil externo');
    RAISE EXCEPTION 'QA command failed: foreign profile accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END $$;

-- Removing the profile that makes the sole effective admin critical must fail.
DO $$ BEGIN
  BEGIN
    PERFORM public.admin_usuario_alterar_perfil(pg_temp.cmd_id('sole_admin'), pg_temp.cmd_id('profile_admin'), 'remover', 'QA remover ultimo admin');
    RAISE EXCEPTION 'QA command failed: last admin profile removal accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;

RESET ROLE;
-- Direct client writes and audit reads remain unavailable; only RPC execution is exposed.
SELECT pg_temp.cmd_assert(NOT has_table_privilege('authenticated', 'public.usuarios', 'UPDATE'), 'authenticated still has no direct user UPDATE');
SELECT pg_temp.cmd_assert(NOT has_table_privilege('authenticated', 'public.usuario_perfis', 'INSERT,DELETE'), 'authenticated still has no direct profile-link writes');
SELECT pg_temp.cmd_assert(NOT has_table_privilege('authenticated', 'public.auditoria_eventos', 'SELECT,INSERT,UPDATE,DELETE'), 'audit table inaccessible directly');
SELECT pg_temp.cmd_assert(has_function_privilege('authenticated', 'public.admin_usuario_alterar_status(uuid,text,text)', 'EXECUTE'), 'authenticated can execute status command');
SELECT pg_temp.cmd_assert(NOT has_function_privilege('anon', 'public.admin_usuario_alterar_status(uuid,text,text)', 'EXECUTE'), 'anon cannot execute status command');
SELECT pg_temp.cmd_assert((SELECT count(*) >= 5 FROM public.auditoria_eventos), 'successful commands generated audit trail');

SELECT 'PASS: audited admin user commands, tenant isolation, anti-self-elevation, last-admin protection and no direct client writes' AS result;
ROLLBACK;
