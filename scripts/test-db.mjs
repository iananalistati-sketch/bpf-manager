import { readdir, readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { PGlite } from '@electric-sql/pglite'
import { checkNames } from './supabase-apply-documentos.mjs'

const root = fileURLToPath(new URL('..', import.meta.url))
const migrationsDir = join(root, 'supabase', 'migrations')
const testsDir = join(root, 'supabase', 'tests')
const read = (path) => readFile(join(root, path), 'utf8')

const migrations = (await readdir(migrationsDir, { withFileTypes: true }))
  .filter(entry => entry.isFile() && /^\d{14}_.+\.sql$/.test(entry.name))
  .map(entry => `supabase/migrations/${entry.name}`)
  .sort()

const testSuites = (await readdir(testsDir, { withFileTypes: true }))
  .filter(entry => entry.isFile() && entry.name.endsWith('.sql'))
  .map(entry => `supabase/tests/${entry.name}`)
  .sort()

if (migrations.length === 0) throw new Error('No versioned migrations found')
if (testSuites.length === 0) throw new Error('No SQL test suites found')

const membershipMigration = 'supabase/migrations/20260923171840_membership_compatibility_foundation.sql'
if (!migrations.includes(membershipMigration)) throw new Error('Membership compatibility migration is missing')

const db = await PGlite.create()
try {
  const { rows: version } = await db.query('SHOW server_version')
  console.log(`Local PostgreSQL: ${version[0].server_version} (PGlite; reconstructed fixture)`)
  console.log(`Discovered ${migrations.length} migrations and ${testSuites.length} SQL suites automatically`)
  await db.exec(await read('supabase/tests/fixtures/current_schema.sql'))

  const baseMigration = await read(migrations[0])
  await db.exec(`BEGIN;
    INSERT INTO empresas(id, razao_social) VALUES
      ('00000000-0000-0000-0000-000000000001', 'A'),
      ('00000000-0000-0000-0000-000000000002', 'B');
    INSERT INTO unidades(id, empresa_id, nome) VALUES
      ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000002', 'B');
    INSERT INTO auth.users(id) VALUES ('00000000-0000-0000-0000-000000000004');
    UPDATE usuarios SET empresa_id = '00000000-0000-0000-0000-000000000001',
      unidade_id = '00000000-0000-0000-0000-000000000003';`)
  let rejected = false
  try { await db.exec(baseMigration) } catch (error) {
    if (!error.message.includes('Existing usuarios contain incompatible empresa/unidade')) throw error
    rejected = true
  } finally { await db.exec('ROLLBACK') }
  if (!rejected) throw new Error('Preflight accepted incompatible legacy data')
  console.log('PASS: preflight rejects incompatible legacy data')

  for (const path of migrations) {
    if (path === membershipMigration) {
      await db.exec(`
        INSERT INTO public.empresas(id, razao_social) VALUES
          ('81000000-0000-0000-0000-000000000001', 'Legacy Backfill');
        INSERT INTO public.unidades(id, empresa_id, nome) VALUES
          ('82000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001', 'Legacy Unit');
        INSERT INTO auth.users(id, email) VALUES
          ('83000000-0000-0000-0000-000000000001', 'legacy@example.test');
        UPDATE public.usuarios
          SET empresa_id = '81000000-0000-0000-0000-000000000001',
              unidade_id = '82000000-0000-0000-0000-000000000001',
              status = 'ativo', ativo = true
          WHERE id = '83000000-0000-0000-0000-000000000001';
        INSERT INTO public.perfis(id, empresa_id, nome, is_system, ativo)
          VALUES ('84000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001', 'Legacy Profile', false, true);
        INSERT INTO public.usuario_perfis(usuario_id, perfil_id)
          VALUES ('83000000-0000-0000-0000-000000000001', '84000000-0000-0000-0000-000000000001');
      `)
    }

    if (path.endsWith('_document_control_integrity.sql')) {
      const upgradeFixture = `
        BEGIN;
        INSERT INTO auth.users(id,email) VALUES ('dc000000-0000-0000-0000-000000000001','upgrade@example.test');
        INSERT INTO public.empresas(id,razao_social) VALUES ('dc100000-0000-0000-0000-000000000001','Document upgrade');
        INSERT INTO public.unidades(id,empresa_id,nome) VALUES ('dc200000-0000-0000-0000-000000000001','dc100000-0000-0000-0000-000000000001','Upgrade unit');
        INSERT INTO public.documentos(id,empresa_id,unidade_id,codigo,titulo,tipo,created_by)
        VALUES ('dc300000-0000-0000-0000-000000000001','dc100000-0000-0000-0000-000000000001','dc200000-0000-0000-0000-000000000001','UPGRADE','Original title','POP','dc000000-0000-0000-0000-000000000001');
        INSERT INTO public.documento_versoes(documento_id,numero,status,descricao,autor_id)
        VALUES ('dc300000-0000-0000-0000-000000000001',1,'rascunho','Original content','dc000000-0000-0000-0000-000000000001');
      `
      await db.exec(upgradeFixture)
      await db.exec(`INSERT INTO public.documento_versoes(documento_id,numero,status,autor_id)
        VALUES ('dc300000-0000-0000-0000-000000000001',2,'rascunho','dc000000-0000-0000-0000-000000000001')`)
      let blocked = false
      try { await db.exec(await read(path)) } catch (error) {
        if (error.code !== '55000' || !error.message.includes('Reconciliar metadados historicos')) throw error
        blocked = true
      } finally { await db.exec('ROLLBACK') }
      if (!blocked) throw new Error('Document upgrade accepted ambiguous multi-version history')
      const { rows: columns } = await db.query(`SELECT column_name FROM information_schema.columns
        WHERE table_schema='public' AND table_name='documento_versoes' AND column_name='titulo'`)
      if (columns.length) throw new Error('Rejected document upgrade left partial DDL')
      await db.exec(upgradeFixture)
      try {
        await db.exec(await read(path))
        const { rows: snapshot } = await db.query(`SELECT titulo,tipo,unidade_id,descricao
          FROM public.documento_versoes WHERE documento_id='dc300000-0000-0000-0000-000000000001'`)
        if (snapshot.length !== 1 || snapshot[0].titulo !== 'Original title' || snapshot[0].tipo !== 'POP'
          || snapshot[0].unidade_id !== 'dc200000-0000-0000-0000-000000000001' || snapshot[0].descricao !== 'Original content') {
          throw new Error('Document upgrade did not preserve existing v1 metadata')
        }
      } finally { await db.exec('ROLLBACK') }
      console.log('PASS: document upgrade preserves v1 and rejects ambiguous multi-version history atomically')
    }

    await db.exec(`BEGIN;\n${await read(path)}\nCOMMIT;`)
    console.log(`PASS: applied ${path.split('/').at(-1)}`)

    if (path === membershipMigration) {
      const { rows: membershipRows } = await db.query(`
        SELECT ue.usuario_id, ue.empresa_id, ue.unidade_id, ue.status, ue.is_owner,
               uep.perfil_id
        FROM public.usuario_empresas ue
        JOIN public.usuario_empresa_perfis uep ON uep.usuario_empresa_id = ue.id
        WHERE ue.usuario_id = '83000000-0000-0000-0000-000000000001'
      `)
      if (membershipRows.length !== 1
        || membershipRows[0].empresa_id !== '81000000-0000-0000-0000-000000000001'
        || membershipRows[0].unidade_id !== '82000000-0000-0000-0000-000000000001'
        || membershipRows[0].status !== 'ativo'
        || membershipRows[0].is_owner !== false
        || membershipRows[0].perfil_id !== '84000000-0000-0000-0000-000000000001') {
        throw new Error('Membership migration did not backfill legacy user/company/profile state correctly')
      }
      console.log('PASS: membership migration backfills legacy company, unit, status and profile')

      await db.exec(`
        DELETE FROM public.usuario_empresa_perfis
          WHERE usuario_empresa_id IN (SELECT id FROM public.usuario_empresas WHERE usuario_id = '83000000-0000-0000-0000-000000000001');
        DELETE FROM public.usuario_empresas WHERE usuario_id = '83000000-0000-0000-0000-000000000001';
        DELETE FROM public.usuario_perfis WHERE usuario_id = '83000000-0000-0000-0000-000000000001';
        DELETE FROM public.perfis WHERE id = '84000000-0000-0000-0000-000000000001';
        DELETE FROM auth.users WHERE id = '83000000-0000-0000-0000-000000000001';
        DELETE FROM public.unidades WHERE id = '82000000-0000-0000-0000-000000000001';
        DELETE FROM public.empresas WHERE id = '81000000-0000-0000-0000-000000000001';
      `)
    }
  }

  // Replay the exact read-only hosted inspection against the reconstructed final schema.
  await db.exec(`CREATE SCHEMA supabase_migrations;
    CREATE TABLE supabase_migrations.schema_migrations(version text PRIMARY KEY)`)
  for (const path of migrations) {
    await db.query('INSERT INTO supabase_migrations.schema_migrations(version) VALUES ($1)', [path.split('/').at(-1).slice(0, 14)])
  }
  const verificationSql = await read('scripts/sql/verify-documentos-deploy.sql')
  const { rows: verified } = await db.query(verificationSql)
  if (verified.length !== 1 || checkNames.some(name => verified[0][name] !== true)) {
    throw new Error(`Hosted metadata inspection disagrees with final schema: ${JSON.stringify(verified)}`)
  }
  for (const [mutation, check] of [
    ['GRANT SELECT(titulo) ON public.documentos TO authenticated', 'tabelas_fechadas'],
    ['GRANT EXECUTE ON FUNCTION private.tenant_tem_permissao(uuid,text) TO PUBLIC', 'helpers_fechados'],
    ['ALTER TABLE public.documento_versoes ALTER COLUMN titulo DROP NOT NULL', 'contratos_versionados'],
    ['ALTER TABLE public.documentos DROP CONSTRAINT documentos_unidade_empresa_fkey; ALTER TABLE public.documentos ADD CONSTRAINT documentos_unidade_empresa_fkey FOREIGN KEY (unidade_id) REFERENCES public.unidades(id)', 'integridade_documental'],
    ["DROP INDEX public.idx_documento_versoes_um_vigente; CREATE UNIQUE INDEX idx_documento_versoes_um_vigente ON public.documento_versoes(id) WHERE status='vigente'", 'integridade_documental'],
    ['ALTER TABLE public.documento_versoes DROP CONSTRAINT documento_versoes_documento_numero_key; ALTER TABLE public.documento_versoes ADD CONSTRAINT documento_versoes_documento_numero_key UNIQUE (id,numero)', 'integridade_documental'],
    ["DROP FUNCTION public.documento_transicionar(uuid,text,text,uuid); CREATE FUNCTION public.documento_transicionar(p_documento_id uuid,p_status_destino text,p_justificativa text,p_versao_id uuid) RETURNS void LANGUAGE plpgsql AS 'begin return; end'", 'contratos_versionados'],
    ["INSERT INTO supabase_migrations.schema_migrations(version) VALUES ('invalid-legacy-version')", 'historico_exato'],
  ]) {
    await db.exec(`BEGIN; ${mutation};`)
    try {
      const { rows } = await db.query(verificationSql)
      if (rows.length !== 1 || rows[0][check] !== false) throw new Error(`Metadata inspection accepted drift: ${check}`)
    } finally { await db.exec('ROLLBACK') }
  }
  await db.exec('DROP TABLE supabase_migrations.schema_migrations; DROP SCHEMA supabase_migrations')
  console.log('PASS: hosted inspection checks final schema and rejects column grants, helper exposure, snapshot/default drift, disguised keys/indexes and hidden history entries')

  for (const path of testSuites) {
    console.log(`RUN: ${path.split('/').at(-1)}`)
    const results = await db.exec(await read(path))
    for (const result of results) for (const row of result.rows) {
      if (row.result) console.log(row.result)
    }
  }

  const { rows: users } = await db.query('SELECT count(*)::int AS count FROM public.usuarios')
  if (users[0].count !== 0) throw new Error('Test fixtures were not rolled back')
  const { rows: audits } = await db.query('SELECT count(*)::int AS count FROM public.auditoria_eventos')
  if (audits[0].count !== 0) throw new Error('Audit test fixtures were not rolled back')
  const { rows: memberships } = await db.query('SELECT count(*)::int AS count FROM public.usuario_empresas')
  if (memberships[0].count !== 0) throw new Error('Membership test fixtures were not rolled back')
  const { rows: companyPlans } = await db.query('SELECT count(*)::int AS count FROM public.empresa_planos')
  if (companyPlans[0].count !== 0) throw new Error('Plan test fixtures were not rolled back')
  console.log('PASS: fixtures rolled back; remote Supabase was not accessed')
} catch (error) {
  console.error(`Database test failed: ${error.message}`)
  process.exitCode = 1
} finally {
  await db.close()
}
