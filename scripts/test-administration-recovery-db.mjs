import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { verifyReadiness } from './supabase-setup-secondary-qa.mjs'
import { testTenantAdministration } from './test-tenant-administration-db.mjs'

const quote=value=>'"'+value.replaceAll('"','""')+'"'
const tables=['empresas','unidades','setores','perfis']

export async function testAdministrationRecovery(db,migration,readiness) {
  const fixture=JSON.parse(await readFile(new URL('../supabase/tests/fixtures/hosted31-policies.json',import.meta.url),'utf8'))
  assert.equal(fixture.policies.length,66)
  const embedded=migration.split('-- BEGIN_READINESS_QUERY\n')[1]?.split('\n-- END_READINESS_QUERY')[0]
  assert.equal(embedded,readiness.trim().replace(/;$/,''))
  for(const variant of ['hosted31','permissive_unknown','no_permissive']) {
    await db.exec('BEGIN')
    try {
      if(variant==='hosted31') {
        for(const p of(await db.query("select tablename,policyname from pg_policies where schemaname='public'")).rows) {
          if(fixture.tables.includes(p.tablename))await db.exec(`DROP POLICY ${quote(p.policyname)} ON public.${quote(p.tablename)}`)
        }
        for(const p of fixture.policies) {
          assert.equal(p.schemaname,'public');assert.ok(fixture.tables.includes(p.tablename))
          const roles=p.roles.map(r=>r==='public'?'PUBLIC':quote(r)).join(',')
          await db.exec(`CREATE POLICY ${quote(p.policyname)} ON public.${quote(p.tablename)} AS ${p.permissive} FOR ${p.cmd} TO ${roles}${p.qual?' USING ('+p.qual+')':''}${p.with_check?' WITH CHECK ('+p.with_check+')':''}`)
        }
      } else {
        for(const table of tables) {
          const name=`${table}_select_empresa`
          await db.exec(variant==='no_permissive'?`DROP POLICY ${name} ON public.${table}`
            :`ALTER POLICY ${name} ON public.${table} RENAME TO arbitrary_${table};CREATE POLICY legacy_extra_allow ON public.${table} FOR SELECT TO authenticated USING(true)`)
        }
      }
      verifyReadiness((await db.query(readiness)).rows)
      await db.exec(migration)
      await db.query('insert into supabase_migrations.schema_migrations values($1)',['20261029160000'])
      await testTenantAdministration(db,{withinTransaction:true,directPrimaryAllowed:variant!=='no_permissive'})
      console.log(`PASS: recovery32 complete mutation/QA matrix on ${variant}; restrictive guards preserve or narrow access`)
    } finally {await db.exec('ROLLBACK')}
  }
  await db.exec('BEGIN')
  try {
    await db.exec('CREATE ROLE bpf_tenant_admin NOLOGIN;SAVEPOINT refused_migration')
    await assert.rejects(db.exec(migration),error=>error.code==='55000'&&error.message.includes('sem_objetos_32'))
    await db.exec('ROLLBACK TO SAVEPOINT refused_migration')
    assert.equal((await db.query("select count(*)::int n from pg_proc where proname='admin_contexto_ler'")).rows[0].n,0)
    assert.equal((await db.query('select count(*)::int n from supabase_migrations.schema_migrations')).rows[0].n,31)
  } finally {await db.exec('ROLLBACK')}
  console.log('PASS: migration embedded gate refuses mixed state before its first DDL')
}
