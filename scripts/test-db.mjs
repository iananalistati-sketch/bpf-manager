import { readFile } from 'node:fs/promises'
import { PGlite } from '@electric-sql/pglite'

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), 'utf8')
const migrations = [
  'supabase/migrations/20260916163832_administrative_user_read.sql',
  'supabase/migrations/20260916223100_fix_authz_reader_identity.sql',
  'supabase/migrations/20260916223400_optimize_administrative_read_rls.sql',
  'supabase/migrations/20260918112000_admin_user_commands.sql',
]
const testSuites = [
  'supabase/tests/administrative_user_read.sql',
  'supabase/tests/admin_user_commands.sql',
]

const db = await PGlite.create()
try {
  const { rows: version } = await db.query('SHOW server_version')
  console.log(`Local PostgreSQL: ${version[0].server_version} (PGlite; reconstructed fixture)`)
  await db.exec(await read('supabase/tests/fixtures/current_schema.sql'))

  const baseMigration = await read(migrations[0])
  // Prove the foundational preflight rejects incompatible legacy data without repairing it.
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
    await db.exec(`BEGIN;\n${await read(path)}\nCOMMIT;`)
    console.log(`PASS: applied ${path.split('/').at(-1)}`)
  }

  for (const path of testSuites) {
    const results = await db.exec(await read(path))
    for (const result of results) for (const row of result.rows) {
      if (row.result) console.log(row.result)
    }
  }

  const { rows: users } = await db.query('SELECT count(*)::int AS count FROM public.usuarios')
  if (users[0].count !== 0) throw new Error('Test fixtures were not rolled back')
  const { rows: audits } = await db.query('SELECT count(*)::int AS count FROM public.auditoria_eventos')
  if (audits[0].count !== 0) throw new Error('Audit test fixtures were not rolled back')
  console.log('PASS: fixtures rolled back; remote Supabase was not accessed')
} catch (error) {
  console.error(`Database test failed: ${error.message}`)
  process.exitCode = 1
} finally {
  await db.close()
}
