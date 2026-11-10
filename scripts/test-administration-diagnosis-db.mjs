import assert from 'node:assert/strict'
import { diagnosisSql,parseAdministrationDiagnosis } from './supabase-diagnose-administration.mjs'

export async function testAdministrationDiagnosis(db) {
  const sql=await diagnosisSql()
  const inspect=async()=>parseAdministrationDiagnosis((await db.query(sql)).rows)
  await db.exec('BEGIN READ ONLY')
  try {
    const report=await inspect()
    assert.equal(report.versoes.length,31)
    assert.ok(report.tabelas.some(t=>t.tabela==='empresas'&&t.rls))
    assert.ok(report.acls.some(g=>g.grantee==='authenticated'))
    assert.equal(report.roles.some(r=>r.nome==='bpf_tenant_admin'),false)
    assert.ok(report.funcoes.some(f=>f.proname==='admin_usuario_alterar_status'&&f.corpo_md5.length===32))
    for(const name of ['empresa_leitura_usuarios','empresa_gestao_perfis','empresa_convite_usuarios','empresa_estrutura_admin','empresa_leitura_auditoria']) {
      assert.ok(report.funcoes.some(f=>f.proname===name&&f.esquema==='private'))
    }
  } finally {await db.exec('ROLLBACK')}
  await db.exec('BEGIN')
  try {
    await db.exec('ALTER POLICY empresas_select_empresa ON public.empresas RENAME TO hosted_company_policy; DROP POLICY unidades_select_empresa ON public.unidades')
    const report=await inspect()
    assert.ok(report.policies.some(p=>p.policyname==='hosted_company_policy'))
    assert.equal(report.policies.some(p=>p.policyname==='unidades_select_empresa'),false)
    await db.exec("CREATE ROLE bpf_tenant_admin NOLOGIN;CREATE FUNCTION private.admin_diagnosis_trace() RETURNS boolean LANGUAGE sql SET application_name='private-marker-test' AS $$select true$$")
    const traces=await inspect()
    assert.ok(traces.roles.some(r=>r.nome==='bpf_tenant_admin'))
    assert.ok(traces.funcoes.some(f=>f.proname==='admin_diagnosis_trace'))
    assert.ok(!JSON.stringify(traces).includes('private-marker-test'))
    assert.equal(traces.versoes.length,31)
  } finally {await db.exec('ROLLBACK')}
  console.log('PASS: administration diagnosis runs in read-only transaction, tolerates missing/renamed policies and exposes traces despite unchanged ledger')
}
