import { readFile } from 'node:fs/promises'
import { PGlite } from '@electric-sql/pglite'

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), 'utf8')
const membershipMigration = 'supabase/migrations/20260923143000_membership_compatibility_foundation.sql'
const migrations = [
  'supabase/migrations/20260916163832_administrative_user_read.sql',
  'supabase/migrations/20260916223100_fix_authz_reader_identity.sql',
  'supabase/migrations/20260916223400_optimize_administrative_read_rls.sql',
  'supabase/migrations/20260918112000_admin_user_commands.sql',
  'supabase/migrations/20260918120500_fix_admin_writer_select_grants.sql',
  'supabase/migrations/20260918133000_serialize_last_admin_mutations.sql',
  'supabase/migrations/20260918134450_allow_admin_writer_set_role.sql',
  'supabase/migrations/20260918134500_complete_administration_foundation.sql',
  'supabase/migrations/20260918134600_expand_admin_audit_writer_policy.sql',
  'supabase/migrations/20260918134700_harden_profile_delegation.sql',
  'supabase/migrations/20260918134800_fix_complete_admin_writer_grants.sql',
  membershipMigration,
]
const testSuites = [
  'supabase/tests/administrative_user_read.sql',
  'supabase/tests/admin_user_commands.sql',
  'supabase/tests/complete_administration_foundation.sql',
  'supabase/tests/profile_delegation_security.sql',
  'supabase/tests/structure_admin_paths.sql',
  'supabase/tests/membership_compatibility.sql',
]

const db = await PGlite.create()
try {
  const { rows: version } = await db.query('SHOW server_version')
  console.log(`Local PostgreSQL: ${version[0].server_version} (PGlite; reconstructed fixture)`)
  await db.exec(await read('supabase/tests/fixtures/current_schema.sql'))

  const baseMigration = await read(migrations[0])
  await db.exec(`BEGIN;\n    INSERT INTO empresas(id, razao_social) VALUES\n      ('00000000-0000-0000-0000-000000000001', 'A'),\n      ('00000000-0000-0000-0000-000000000002', 'B');\n    INSERT INTO unidades(id, empresa_id, nome) VALUES\n      ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000002', 'B');\n    INSERT INTO auth.users(id) VALUES ('00000000-0000-0000-0000-000000000004');\n    UPDATE usuarios SET empresa_id = '00000000-0000-0000-0000-000000000001',\n      unidade_id = '00000000-0000-0000-0000-000000000003';`)
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
  const { rows: memberships } = await db.query('SELECT count(*)::int AS count FROM public.usuario_empresas')
  if (memberships[0].count !== 0) throw new Error('Membership test fixtures were not rolled back')
  console.log('PASS: fixtures rolled back; remote Supabase was not accessed')
} catch (error) {
  console.error(`Database test failed: ${error.message}`)
  process.exitCode = 1
} finally {
  await db.close()
}
