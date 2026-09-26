-- Security regression: profile managers cannot delegate permissions they do not possess.
BEGIN;
SET LOCAL statement_timeout='30s';
CREATE TEMP TABLE qa_sec_ids(name text PRIMARY KEY,id uuid NOT NULL DEFAULT gen_random_uuid());
INSERT INTO qa_sec_ids(name) VALUES ('company'),('unit'),('actor'),('target'),('limited_profile'),('elevated_profile');
GRANT SELECT ON qa_sec_ids TO authenticated;
CREATE FUNCTION pg_temp.sid(k text) RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT id FROM pg_temp.qa_sec_ids WHERE name=k $$;
CREATE FUNCTION pg_temp.sassert(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'QA security failed: %',label; END IF; END $$;

INSERT INTO public.empresas(id,razao_social) VALUES(pg_temp.sid('company'),'QA Security');
INSERT INTO public.unidades(id,empresa_id,nome) VALUES(pg_temp.sid('unit'),pg_temp.sid('company'),'QA Unit');
INSERT INTO auth.users(id,email) VALUES(pg_temp.sid('actor'),'actor-sec@example.invalid'),(pg_temp.sid('target'),'target-sec@example.invalid');
UPDATE public.usuarios SET empresa_id=pg_temp.sid('company'),unidade_id=pg_temp.sid('unit'),status='ativo',ativo=true WHERE id IN(pg_temp.sid('actor'),pg_temp.sid('target'));
INSERT INTO public.perfis(id,empresa_id,nome,is_system,ativo) VALUES
 (pg_temp.sid('limited_profile'),pg_temp.sid('company'),'Limited Manager',false,true),
 (pg_temp.sid('elevated_profile'),pg_temp.sid('company'),'Elevated',false,true);
INSERT INTO public.perfil_permissoes(perfil_id,permissao_id)
SELECT pg_temp.sid('limited_profile'),id FROM public.permissoes WHERE codigo IN ('configuracoes.visualizar','usuarios.gerenciar','perfis.gerenciar');
INSERT INTO public.perfil_permissoes(perfil_id,permissao_id)
SELECT pg_temp.sid('elevated_profile'),id FROM public.permissoes WHERE codigo IN ('configuracoes.visualizar','usuarios.gerenciar','perfis.gerenciar','configuracoes.gerenciar');
INSERT INTO public.usuario_perfis(usuario_id,perfil_id) VALUES(pg_temp.sid('actor'),pg_temp.sid('limited_profile'));

SELECT set_config('request.jwt.claim.sub',pg_temp.sid('actor')::text,true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.sid('actor'),'role','authenticated')::text,true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  BEGIN
    PERFORM public.admin_usuario_alterar_perfil(pg_temp.sid('target'),pg_temp.sid('elevated_profile'),'atribuir','QA tenta elevar terceiro');
    RAISE EXCEPTION 'QA security failed: elevated profile delegated';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT pg_temp.sassert((SELECT count(*)=0 FROM public.usuario_perfis WHERE usuario_id=pg_temp.sid('target') AND perfil_id=pg_temp.sid('elevated_profile')),'elevated profile not linked');

-- Grant structure permission directly to the actor only for testing custom-profile creation ceiling.
INSERT INTO public.perfil_permissoes(perfil_id,permissao_id)
SELECT pg_temp.sid('limited_profile'),id FROM public.permissoes WHERE codigo='estrutura.gerenciar' ON CONFLICT DO NOTHING;
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  BEGIN
    PERFORM public.admin_perfil_criar('Forbidden Audit','',ARRAY[(SELECT id FROM public.permissoes WHERE codigo='auditoria.visualizar')],'QA tenta conceder permissao alheia');
    RAISE EXCEPTION 'QA security failed: foreign permission granted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT pg_temp.sassert((SELECT count(*)=0 FROM public.perfis WHERE empresa_id=pg_temp.sid('company') AND nome='Forbidden Audit'),'forbidden profile rolled back');

SELECT 'PASS: permission delegation ceiling blocks indirect privilege escalation' AS result;
ROLLBACK;
