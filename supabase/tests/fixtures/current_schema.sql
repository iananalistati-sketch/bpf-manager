-- TEST FIXTURE ONLY: minimal reconstruction of the inspected pre-migration schema.
-- Not a baseline, schema dump, or migration for deployment.
-- Replace the immutable bootstrap superuser with a managed-style deployer.
CREATE ROLE qa_bootstrap SUPERUSER LOGIN;
SET SESSION AUTHORIZATION qa_bootstrap;
ALTER ROLE postgres RENAME TO qa_original;
CREATE ROLE postgres LOGIN NOSUPERUSER CREATEROLE BYPASSRLS;
GRANT ALL ON SCHEMA public TO postgres;
DO $$ BEGIN EXECUTE format('GRANT CREATE ON DATABASE %I TO postgres', current_database()); END $$;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;
GRANT authenticated TO postgres WITH INHERIT FALSE, SET TRUE;
SET SESSION AUTHORIZATION postgres;
CREATE SCHEMA auth;
CREATE SCHEMA private;
CREATE TABLE auth.users (id uuid PRIMARY KEY, email text, raw_user_meta_data jsonb);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
GRANT USAGE ON SCHEMA public, auth TO authenticated;
CREATE TABLE public.empresas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), razao_social text NOT NULL,
  nome_fantasia text, ativo boolean NOT NULL DEFAULT true
);
CREATE TABLE public.unidades (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL REFERENCES public.empresas,
  nome text NOT NULL, ativo boolean NOT NULL DEFAULT true
);
CREATE TABLE public.usuarios (
  id uuid PRIMARY KEY REFERENCES auth.users ON DELETE CASCADE, nome text, email text,
  empresa_id uuid REFERENCES public.empresas, unidade_id uuid REFERENCES public.unidades ON DELETE SET NULL,
  ativo boolean NOT NULL DEFAULT true, status text NOT NULL DEFAULT 'pendente'
    CHECK (status IN ('pendente', 'ativo', 'inativo', 'bloqueado')),
  CHECK (unidade_id IS NULL OR empresa_id IS NOT NULL)
);
CREATE TABLE public.perfis (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid REFERENCES public.empresas,
  nome text NOT NULL, is_system boolean NOT NULL DEFAULT false, ativo boolean NOT NULL DEFAULT true
);
CREATE TABLE public.permissoes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), codigo text NOT NULL UNIQUE
);
CREATE TABLE public.usuario_perfis (
  usuario_id uuid REFERENCES public.usuarios ON DELETE CASCADE,
  perfil_id uuid REFERENCES public.perfis ON DELETE CASCADE,
  PRIMARY KEY (usuario_id, perfil_id)
);
CREATE TABLE public.perfil_permissoes (
  perfil_id uuid REFERENCES public.perfis ON DELETE CASCADE,
  permissao_id uuid REFERENCES public.permissoes ON DELETE CASCADE,
  PRIMARY KEY (perfil_id, permissao_id)
);
CREATE FUNCTION private.handle_new_auth_user() RETURNS trigger LANGUAGE plpgsql
SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  INSERT INTO public.usuarios(id, nome, email)
  VALUES (new.id, new.raw_user_meta_data ->> 'nome', new.email);
  RETURN new;
END $$;
REVOKE ALL ON FUNCTION private.handle_new_auth_user() FROM PUBLIC;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION private.handle_new_auth_user();
ALTER TABLE public.usuarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usuario_perfis ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.empresas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.unidades ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.perfis ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permissoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.perfil_permissoes ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
CREATE POLICY usuarios_select_proprio ON public.usuarios FOR SELECT TO authenticated
USING (id = (SELECT auth.uid()));
CREATE POLICY usuario_perfis_select_proprio ON public.usuario_perfis FOR SELECT TO authenticated
USING (usuario_id = (SELECT auth.uid()));
CREATE POLICY empresas_select_empresa ON public.empresas FOR SELECT TO authenticated
USING (id IN (SELECT empresa_id FROM public.usuarios WHERE id = (SELECT auth.uid()) AND ativo AND status = 'ativo'));
CREATE POLICY unidades_select_empresa ON public.unidades FOR SELECT TO authenticated
USING (empresa_id IN (SELECT empresa_id FROM public.usuarios WHERE id = (SELECT auth.uid()) AND ativo AND status = 'ativo'));
CREATE POLICY perfis_select_empresa ON public.perfis FOR SELECT TO authenticated
USING ((empresa_id IS NULL AND is_system) OR empresa_id IN
  (SELECT empresa_id FROM public.usuarios WHERE id = (SELECT auth.uid()) AND ativo AND status = 'ativo'));
-- Existing shared catalog policy; the migration must not add a global policy.
CREATE POLICY permissoes_select_catalogo ON public.permissoes FOR SELECT TO authenticated USING (true);
CREATE POLICY perfil_permissoes_select_empresa ON public.perfil_permissoes FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.perfis p WHERE p.id = perfil_id));
CREATE VIEW public.v_meu_contexto WITH (security_invoker = true) AS
SELECT u.id AS usuario_id, u.nome, u.email, u.ativo, u.status, u.empresa_id,
  e.nome_fantasia, e.razao_social, u.unidade_id, un.nome AS unidade_nome,
  coalesce(array_agg(DISTINCT p.nome) FILTER (WHERE p.nome IS NOT NULL), '{}'::text[]) AS perfis,
  coalesce(array_agg(DISTINCT pm.codigo) FILTER (WHERE pm.codigo IS NOT NULL), '{}'::text[]) AS permissoes
FROM public.usuarios u
LEFT JOIN public.empresas e ON e.id = u.empresa_id
LEFT JOIN public.unidades un ON un.id = u.unidade_id
LEFT JOIN public.usuario_perfis up ON up.usuario_id = u.id
LEFT JOIN public.perfis p ON p.id = up.perfil_id
LEFT JOIN public.perfil_permissoes pp ON pp.perfil_id = p.id
LEFT JOIN public.permissoes pm ON pm.id = pp.permissao_id
WHERE u.id = (SELECT auth.uid())
GROUP BY u.id, e.nome_fantasia, e.razao_social, un.nome;
GRANT ALL ON public.v_meu_contexto TO authenticated;
INSERT INTO public.permissoes(codigo) VALUES ('configuracoes.visualizar'), ('usuarios.gerenciar');
