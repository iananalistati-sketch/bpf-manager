import assert from 'node:assert/strict'

// Exercise the fixed read-only preconditions on the cumulative31 fixture.
// `sql` must be the same fixed SELECT that setup executes before push.
export async function testAdministrationReadinessAdversarial(db,sql) {
  const inspect=async()=>{
    const rows=(await db.query(sql)).rows
    assert.equal(rows.length,1)
    const report=rows[0]
    assert.ok(Object.keys(report).length>0)
    assert.ok(Object.values(report).every(value=>typeof value==='boolean'),'readiness must return exact boolean checks')
    return report
  }
  const requireReady=async()=>{
    const report=await inspect()
    assert.ok(Object.values(report).every(Boolean),JSON.stringify(report))
  }
  const requireBlocked=async(label)=>{
    const report=await inspect()
    assert.ok(Object.values(report).some(value=>value===false),`readiness accepted ${label}: ${JSON.stringify(report)}`)
  }
  const privileged=async(statement)=>{
    await db.exec('SET SESSION AUTHORIZATION qa_bootstrap')
    try{await db.exec(statement)}finally{await db.exec('SET SESSION AUTHORIZATION postgres')}
  }
  await db.exec('BEGIN READ ONLY')
  try{await requireReady()}finally{await db.exec('ROLLBACK')}

  const cases=[
    ['32 role only',"CREATE ROLE bpf_tenant_admin NOLOGIN NOINHERIT NOBYPASSRLS"],
    ['32 private helper only',"CREATE FUNCTION private.admin_primary_empresa() RETURNS uuid LANGUAGE sql AS $$ SELECT NULL::uuid $$"],
    ['32 RPC unexpected overload',"CREATE FUNCTION public.admin_contexto_ler(p_empresa_id uuid,p_recurso text) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$"],
    ['32 policy only',"CREATE POLICY tenant_admin_partial ON public.empresas FOR SELECT TO authenticated USING(true)"],
    ['changed legacy source',"CREATE OR REPLACE FUNCTION private.empresa_leitura_usuarios() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$ SELECT NULL::uuid $$"],
    ['changed legacy owner',"ALTER FUNCTION private.empresa_leitura_usuarios() OWNER TO postgres"],
    ['unsafe legacy search_path',"ALTER FUNCTION private.empresa_leitura_usuarios() SET search_path=public"],
    ['legacy helper anon exposure',"GRANT EXECUTE ON FUNCTION private.empresa_leitura_usuarios() TO anon"],
    ['extra legacy overload',"CREATE FUNCTION private.empresa_leitura_usuarios(p_empresa uuid) RETURNS uuid LANGUAGE sql AS $$ SELECT p_empresa $$"],
    ['missing legacy helper',"DROP FUNCTION private.empresa_leitura_usuarios() CASCADE"],
    ['authenticated SET writer',"GRANT bpf_admin_writer TO authenticated WITH SET TRUE,INHERIT FALSE"],
    ['authenticated inherits writer',"GRANT bpf_admin_writer TO authenticated WITH SET FALSE,INHERIT TRUE"],
    ['postgres SET writer',"GRANT bpf_admin_writer TO postgres WITH SET TRUE,INHERIT FALSE"],
    ['postgres inherits writer',"GRANT bpf_admin_writer TO postgres WITH SET FALSE,INHERIT TRUE"],
    ['authenticated SET service role',"GRANT service_role TO authenticated WITH SET TRUE,INHERIT FALSE"],
    ['anon inherits service role',"GRANT service_role TO anon WITH SET FALSE,INHERIT TRUE"],
    ['authenticated SET unexpected bypass role',"CREATE ROLE unsafe_extra_role BYPASSRLS; GRANT unsafe_extra_role TO authenticated WITH SET TRUE,INHERIT FALSE"],
    ['reader private schema CREATE residue',"GRANT CREATE ON SCHEMA private TO bpf_authz_reader"],
    ['authenticated public schema CREATE',"GRANT CREATE ON SCHEMA public TO authenticated"],
    ['authenticated private schema CREATE',"GRANT CREATE ON SCHEMA private TO authenticated"],
    ['reader bypass RLS',"ALTER ROLE bpf_authz_reader BYPASSRLS"],
    ['reader can create roles',"ALTER ROLE bpf_authz_reader CREATEROLE"],
    ['authenticated global column UPDATE',"GRANT UPDATE(status) ON public.usuarios TO authenticated"],
    ['anon legacy column INSERT',"GRANT INSERT(usuario_id) ON public.usuario_perfis TO anon"],
    ['document column grant',"GRANT SELECT(titulo) ON public.documentos TO authenticated"],
    ['administration RLS disabled',"ALTER TABLE public.usuario_empresas DISABLE ROW LEVEL SECURITY"],
    ['ledger32 without schema32',"INSERT INTO supabase_migrations.schema_migrations(version) VALUES('20261029160000')"],
    ['ledger gap',"DELETE FROM supabase_migrations.schema_migrations WHERE version='20260916223052'"],
  ]
  for(const [label,statement] of cases) {
    await db.exec('BEGIN')
    try{
      await privileged(statement)
      await requireBlocked(label)
    }finally{await db.exec('ROLLBACK')}
  }
  // Correct ALTER VIEW drift without changing its columns or dependencies.
  await db.exec('BEGIN')
  try{
    const body=(await db.query("SELECT pg_get_viewdef('public.v_meu_contexto'::regclass,true) AS source")).rows[0].source.replace(/;\s*$/,'')
    await privileged(`CREATE OR REPLACE VIEW public.v_meu_contexto WITH(security_invoker=true) AS SELECT * FROM (${body}) context_before WHERE false`)
    await requireBlocked('changed context view')
  }finally{await db.exec('ROLLBACK')}
  await requireReady()
  console.log('PASS09: readiness is read-only and rejects mixed32, legacy source/owner/ACL/search_path/overloads, role escalation, column grants, disabled RLS, altered view and ledger drift')
}
