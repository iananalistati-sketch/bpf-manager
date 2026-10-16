import assert from 'node:assert/strict'
import { qaSql, classifyQa, explainQaDiagnosis } from './supabase-prepare-qa.mjs'
import { repositoryRoot } from './supabase-preflight.mjs'

export async function testQaWorkspace(db) {
  const email = 'qa-bootstrap@example.test'
  const user = 'aa000000-0000-0000-0000-000000000001'
  const realUser = 'aa000000-0000-0000-0000-000000000002'
  const realCompany = 'aa100000-0000-0000-0000-000000000001'
  const sql = await qaSql(repositoryRoot,'scripts/sql/provision-qa-workspace.sql',email)
  const inspect = async targetEmail => classifyQa((await db.query(await qaSql(repositoryRoot,'scripts/sql/inspect-qa-workspace.sql',targetEmail ?? email))).rows)
  const diagnose = async targetEmail => explainQaDiagnosis((await db.query(await qaSql(repositoryRoot,'scripts/sql/diagnose-qa-account.sql',targetEmail ?? email))).rows)
  const realSnapshot = async () => (await db.query(`select jsonb_build_object(
    'usuario',(select to_jsonb(u) from public.usuarios u where id='${realUser}'),
    'empresa',(select to_jsonb(e) from public.empresas e where id='${realCompany}'),
    'perfis',(select jsonb_agg(to_jsonb(p) order by id) from public.perfis p where empresa_id is null or empresa_id='${realCompany}'),
    'permissoes',(select jsonb_agg(to_jsonb(p) order by id) from public.permissoes p),
    'planos',(select jsonb_agg(to_jsonb(p) order by id) from public.planos p),
    'entitlements',(select jsonb_agg(to_jsonb(p) order by id) from public.plano_entitlements p),
    'vinculos',(select jsonb_agg(to_jsonb(p) order by perfil_id) from public.usuario_perfis p where usuario_id='${realUser}')
  ) as snapshot`)).rows[0].snapshot
  const expectFailure = async (before, statement, code) => {
    await db.exec('SAVEPOINT qa_rejection')
    try {
      if (before) await db.exec(before)
      await assert.rejects(db.exec(statement), error => error.code === code)
    } finally { await db.exec('ROLLBACK TO SAVEPOINT qa_rejection; RELEASE SAVEPOINT qa_rejection') }
  }
  await db.exec('BEGIN')
  try {
    // Local fixture only: hosted Auth already has these account lifecycle fields.
    await db.exec(`ALTER TABLE auth.users ADD COLUMN email_confirmed_at timestamptz;
      ALTER TABLE auth.users ADD COLUMN deleted_at timestamptz;
      ALTER TABLE auth.users ADD COLUMN banned_until timestamptz;
      INSERT INTO auth.users(id,email,email_confirmed_at) VALUES
        ('${user}','${email}',now()),('${realUser}','real-bootstrap@example.test',now()),
        ('aa000000-0000-0000-0000-000000000003','other-bootstrap@example.test',now());
      INSERT INTO public.empresas(id,razao_social) VALUES ('${realCompany}','Empresa real preservada');
      UPDATE public.usuarios SET empresa_id='${realCompany}',status='ativo' WHERE id='${realUser}';
      INSERT INTO public.usuario_empresas(usuario_id,empresa_id,status) VALUES ('${realUser}','${realCompany}','ativo');
      INSERT INTO public.perfis(id,nome,is_system) VALUES ('aa200000-0000-0000-0000-000000000001','Administrador',true);
      INSERT INTO public.perfil_permissoes(perfil_id,permissao_id)
        SELECT 'aa200000-0000-0000-0000-000000000001',id FROM public.permissoes;
      INSERT INTO public.usuario_perfis(usuario_id,perfil_id)
        VALUES ('${realUser}','aa200000-0000-0000-0000-000000000001');`)
    const preserved = await realSnapshot()
    assert.equal((await inspect()).kind,'eligible')
    assert.deepEqual(await diagnose(),{reasons:[],existing:false})
    assert.ok((await diagnose('missing@example.test')).reasons.includes('CONTA_AUTH_NAO_ENCONTRADA'))
    for(const [mutation,reason] of [
      [`DELETE FROM public.usuarios WHERE id='${user}'`,'CADASTRO_DA_APLICACAO_AUSENTE'],
      [`INSERT INTO auth.users(id,email,email_confirmed_at) VALUES ('aa000000-0000-0000-0000-000000000004','${email}',now())`,'EMAIL_AMBIGUO_NO_AUTH'],
      [`UPDATE auth.users SET email_confirmed_at=null WHERE id='${user}'`,'EMAIL_NAO_CONFIRMADO'],
      [`UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id='${user}'`,'CONTA_AUTH_BANIDA'],
      [`UPDATE auth.users SET deleted_at=now() WHERE id='${user}'`,'CONTA_AUTH_EXCLUIDA'],
      [`UPDATE public.usuarios SET ativo=false WHERE id='${user}'`,'CADASTRO_INATIVO_OU_BLOQUEADO'],
      [`UPDATE public.usuarios SET email='different@example.test' WHERE id='${user}'`,'EMAIL_DO_CADASTRO_DIVERGENTE'],
      [`INSERT INTO public.usuario_empresas(usuario_id,empresa_id,status) VALUES ('${user}','${realCompany}','inativo')`,'VINCULOS_EMPRESARIAIS_EXISTENTES'],
      [`INSERT INTO public.usuario_perfis(usuario_id,perfil_id) VALUES ('${user}','aa200000-0000-0000-0000-000000000001')`,'PERFIS_LEGADOS_EXISTENTES'],
      [`INSERT INTO public.saas_provisionamentos(chave_idempotencia,tipo,usuario_id,status) VALUES ('diagnostic-prior-trial','trial','${user}','falhou')`,'PROVISIONAMENTO_ANTERIOR'],
      [`UPDATE public.usuarios SET empresa_id='${realCompany}' WHERE id='${user}'`,'EMPRESA_PRINCIPAL_EXISTENTE'],
      [`INSERT INTO public.empresas(razao_social,created_by) VALUES ('Old test company','${user}')`,'EMPRESAS_CRIADAS_PELA_CONTA'],
    ]) {
      await db.exec(`SAVEPOINT qa_diagnostic; ${mutation}`)
      try { assert.ok((await diagnose()).reasons.includes(reason),reason) }
      finally { await db.exec('ROLLBACK TO SAVEPOINT qa_diagnostic; RELEASE SAVEPOINT qa_diagnostic') }
    }
    console.log('PASS: read-only QA diagnosis distinguishes missing Auth/app, ambiguous email, account lifecycle and all prior links without mutation')
    await expectFailure(`UPDATE public.usuarios SET status='bloqueado' WHERE id='${user}'`,sql,'42501')
    await expectFailure(`UPDATE auth.users SET email_confirmed_at=null WHERE id='${user}'`,sql,'42501')
    await expectFailure(`UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id='${user}'`,sql,'42501')
    await expectFailure(null,await qaSql(repositoryRoot,'scripts/sql/provision-qa-workspace.sql','real-bootstrap@example.test'),'23514')
    await expectFailure('SET LOCAL ROLE authenticated',sql,'42501')
    await expectFailure(`CREATE FUNCTION pg_temp.fail_qa_audit() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN IF new.acao='workspace.qa_preparado' THEN RAISE EXCEPTION 'injected QA audit failure'; END IF; RETURN new; END $$;
      CREATE TRIGGER qa_audit_failure BEFORE INSERT ON public.auditoria_eventos
      FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_qa_audit()`,sql,'P0001')
    assert.equal((await inspect()).kind,'eligible')
    assert.deepEqual(await realSnapshot(),preserved)
    console.log('PASS: QA rejects real/blocked/unconfirmed/banned accounts and non-admin role; audit failure rolls back whole bootstrap')

    await db.exec(sql)
    const ready = await inspect()
    assert.equal(ready.kind,'ready')
    assert.deepEqual(await diagnose(),{reasons:[],existing:true})
    assert.ok((await diagnose('other-bootstrap@example.test')).reasons.includes('MARCADOR_QA_DE_OUTRA_CONTA'))
    await db.exec(`SAVEPOINT qa_bad_marker; UPDATE public.saas_provisionamentos
      SET contexto=contexto || '{"qa_perfil_id":"invalid-uuid","qa_marker":"unexpected"}'::jsonb
      WHERE chave_idempotencia='bpf:qa-documentos:v1'`)
    try { assert.ok((await diagnose()).reasons.includes('MARCADOR_QA_INCOMPLETO_OU_DIVERGENTE')) }
    finally { await db.exec('ROLLBACK TO SAVEPOINT qa_bad_marker; RELEASE SAVEPOINT qa_bad_marker') }
    assert.deepEqual(await realSnapshot(),preserved)
    const snapshotSql = `select jsonb_build_object(
      'ledger',(select to_jsonb(s) from public.saas_provisionamentos s where chave_idempotencia='bpf:qa-documentos:v1'),
      'audits',(select jsonb_agg(to_jsonb(a) order by id) from public.auditoria_eventos a),
      'user',(select to_jsonb(u) from public.usuarios u where id='${user}')) as snapshot`
    const beforeReplay = (await db.query(snapshotSql)).rows[0].snapshot
    await db.exec(sql)
    assert.deepEqual((await db.query(snapshotSql)).rows[0].snapshot,beforeReplay)
    await expectFailure(null,await qaSql(repositoryRoot,'scripts/sql/provision-qa-workspace.sql','other-bootstrap@example.test'),'23505')
    console.log('PASS: QA creates one isolated primary tenant/profile with all current permissions; replay does not change grants or dates')

    for (const mutation of [
      `DELETE FROM public.perfil_permissoes WHERE perfil_id='${ready.row.perfil_id}' AND permissao_id=(SELECT id FROM public.permissoes WHERE codigo='documentos.aprovar')`,
      `UPDATE public.empresa_assinaturas SET trial_inicio=trial_inicio-interval '30 days',trial_fim=trial_fim-interval '30 days' WHERE empresa_id='${ready.row.empresa_id}'`,
      `UPDATE public.usuario_empresas SET status='bloqueado' WHERE usuario_id='${user}'`,
    ]) {
      await db.exec(`SAVEPOINT qa_drift; ${mutation}`)
      try { await db.exec(sql); assert.equal((await inspect()).kind,'blocked') }
      finally { await db.exec('ROLLBACK TO SAVEPOINT qa_drift; RELEASE SAVEPOINT qa_drift') }
    }
    await db.exec('SAVEPOINT qa_future_permission')
    try {
      await db.exec("INSERT INTO public.permissoes(codigo,modulo,acao) VALUES ('futuro.perigoso','futuro','perigoso')")
      await db.exec(sql)
      assert.equal((await inspect()).row.quantidade_permissoes,ready.row.quantidade_permissoes)
    } finally { await db.exec('ROLLBACK TO SAVEPOINT qa_future_permission; RELEASE SAVEPOINT qa_future_permission') }
    console.log('PASS: QA replay detects revoked grants, expired trial and blocked membership; future permissions are not granted')

    await db.query("SELECT set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claims',$2,true)",[user,JSON.stringify({sub:user,role:'authenticated'})])
    await db.exec('SET LOCAL ROLE authenticated')
    const context = (await db.query('select * from public.meu_contexto_empresa($1)',[ready.row.empresa_id])).rows[0]
    assert.equal(context.empresa_id,ready.row.empresa_id)
    assert.equal(context.permissoes.length,ready.row.quantidade_permissoes)
    assert.equal((await db.query('select * from public.v_meu_contexto')).rows[0].empresa_id,ready.row.empresa_id)
    assert.equal((await db.query('select * from public.meu_workspace_comercial($1)',[ready.row.empresa_id])).rows[0].modo_acesso,'normal')
    await db.query('select public.admin_unidade_salvar(null,$1,$2,true,$3)',['Segunda unidade TESTE','QA2','Validar multiunidade no tenant QA'])
    const doc = (await db.query('select public.documento_criar($1,$2,$3,$4,$5,$6,null) as id',
      [ready.row.empresa_id,ready.row.unidade_id,'POP-QA','POP de teste','POP','Evidencia QA'])).rows[0].id
    for (const state of ['em_revisao','aguardando_aprovacao','aprovado','vigente']) {
      await db.query('select public.documento_transicionar($1,$2,$3)',[doc,state,'Validacao do perfil QA'])
    }
    await expectFailure(null,`select * from public.documentos_listar('${realCompany}')`,'42501')
    await db.exec('RESET ROLE')
    assert.equal((await db.query('select count(*)::int as n from public.unidades where empresa_id=$1',[ready.row.empresa_id])).rows[0].n,2)
    assert.deepEqual(await realSnapshot(),preserved)
    console.log('PASS: QA JWT reaches own primary context, commercial state, legacy admin and complete document workflow; cross-tenant denied')
  } finally { await db.exec('ROLLBACK') }
}
