import assert from 'node:assert/strict'
import {cp,mkdir,mkdtemp,rm,writeFile} from 'node:fs/promises'
import {tmpdir} from 'node:os'
import {join} from 'node:path'
import {test} from 'node:test'
import manifest from './secondary-qa-manifest.json' with {type:'json'}
import {administrationChecks,classifyAdministrationHistory,classifySecondary,readinessChecks,secondaryChecks,secondaryVersions,setupSecondaryQa,validateSecondaryEmail,validateSecondaryPayload,verifyAdministration,verifyReadiness} from './supabase-setup-secondary-qa.mjs'
import {repositoryRoot,officialProjectRef} from './supabase-preflight.mjs'

const env={npm_execpath:'/tmp/npm-cli.js',BPF_QA_EMAIL:'admin@example.test',SUPABASE_DB_PASSWORD:'fictitious password $& spaces'}
const logger=()=>{let text='';return{write:chunk=>{text+=chunk},value:()=>text}}
const history=count=>({migrations:secondaryVersions.map((local,i)=>({local,remote:i<count?local:''}))})
const metadata=()=>[Object.fromEntries(administrationChecks.map(name=>[name,true]))]
const ready=()=>[Object.fromEntries(readinessChecks.map(name=>[name,true]))]
const inspection=ready=>[{checks:Object.fromEntries(secondaryChecks.map(name=>[name,
  name==='marcador_ausente'?!ready:['conta_valida','primario_ativo'].includes(name)?true:ready])),
  empresa_id:ready?'ac100000-0000-0000-0000-000000000001':null,trial_fim:ready?'2026-11-12T12:00:00Z':null}]
async function checkout(t){
 const root=await mkdtemp(join(tmpdir(),'bpf secondary '));t.after(()=>rm(root,{recursive:true,force:true}))
 await mkdir(join(root,'supabase','.temp'),{recursive:true});await mkdir(join(root,'scripts','sql'),{recursive:true})
 await writeFile(join(root,'supabase','.temp','project-ref'),officialProjectRef)
 await cp(join(repositoryRoot,'supabase','migrations'),join(root,'supabase','migrations'),{recursive:true})
 for(const file of Object.keys(manifest.sql))await cp(join(repositoryRoot,file),join(root,file))
 return root
}
function runner({states=[31,32],before=inspection(false),after=inspection(true),pushCode=0,qaCode=0,metadataRows=metadata(),readinessRows=ready(),lostAfterPush=false,lostAfterQa=false,qaThrows=false,onFirstHistory,onReadiness}={}){
 const calls=[];let listed=0,inspected=0
 return {calls,run:async(args,context)=>{
  calls.push({args,input:context.input})
  assert.equal(context.env.SUPABASE_DB_PASSWORD,env.SUPABASE_DB_PASSWORD)
  assert.equal(args[args.indexOf('--project-ref')+1],officialProjectRef)
  assert.ok(!args.join(' ').includes(env.SUPABASE_DB_PASSWORD));assert.ok(!args.join(' ').includes(env.BPF_QA_EMAIL))
  if(args.includes('list')){if(listed>0&&lostAfterPush)throw new Error('lost history');const data=history(states[listed++]);if(listed===1&&onFirstHistory)await onFirstHistory();return{code:0,data}}
  if(args.includes('push')){for(const flag of ['--include-all','--include-seed','--include-roles','--db-url','--debug'])assert.ok(!args.includes(flag));return pushCode}
  assert.ok(args.includes('query'));assert.equal(args[args.indexOf('--output')+1],'json');assert.equal(args[args.indexOf('--agent')+1],'no')
  if(context.input.startsWith('-- Read-only state31 contract')){if(onReadiness)await onReadiness();return{code:0,data:readinessRows}}
  if(context.input.startsWith('with documents as'))return{code:0,data:metadataRows}
  if(context.input.includes('do $qa$')){if(qaThrows)throw new Error('lost process');return qaCode}
  if(inspected>0&&lostAfterQa)throw new Error('lost inspection')
  return{code:0,data:inspected++===0?before:after}
 }}
}
test('secondary rollout applies only32, verifies, provisions and inspects without changing login',async t=>{
 const root=await checkout(t),mock=runner(),output=logger()
 assert.equal(await setupSecondaryQa({root,env,run:mock.run,output}),0)
 assert.equal(mock.calls.length,8)
 assert.equal(mock.calls.filter(c=>c.args.includes('push')).length,1)
 assert.equal(mock.calls.filter(c=>c.input?.includes('do $qa$')).length,1)
 assert.ok(output.value().includes('QA_SECUNDARIO_PRONTO'))
})
test('secondary missing email asks for the original account without aliases or dedicated account',()=>{
 assert.throws(()=>validateSecondaryEmail(undefined),/e-mail original/)
 assert.equal(validateSecondaryEmail('Admin@Example.test'),'admin@example.test')
})
test('secondary32 with existing QA is read-only and never renews/regrants',async t=>{
 const root=await checkout(t),mock=runner({states:[32],before:inspection(true)})
 assert.equal(await setupSecondaryQa({root,env,run:mock.run,output:logger()}),0)
 assert.equal(mock.calls.length,4);assert.ok(!mock.calls.some(c=>c.args.includes('push')||c.input?.includes('do $qa$')))
})
test('secondary rollout rejects unknown/partial/foreign histories',()=>{
 assert.equal(classifyAdministrationHistory(history(31)),31)
 for(const data of [history(30),{migrations:[]},null])assert.throws(()=>classifyAdministrationHistory(data))
 const gap=history(32);gap.migrations[1].remote='';assert.throws(()=>classifyAdministrationHistory(gap))
})
for(const options of [{pushCode:9},{lostAfterPush:true}])test(`secondary push failure ${JSON.stringify(options)} never starts QA`,async t=>{
 const root=await checkout(t),mock=runner(options)
 assert.equal(await setupSecondaryQa({root,env,run:mock.run,output:logger()}),options.pushCode??1)
 assert.ok(!mock.calls.some(c=>c.input?.includes('do $qa$')))
})
test('secondary metadata mismatch confirms history only and prevents QA',async t=>{
 const root=await checkout(t),mock=runner({metadataRows:[]}),output=logger()
 assert.equal(await setupSecondaryQa({root,env,run:mock.run,output}),1)
 assert.ok(output.value().includes('ADMIN_32_VERIFICACAO_PENDENTE'))
 assert.ok(!mock.calls.some(c=>c.input?.includes('do $qa$')))
})
for(const options of [{qaCode:7},{qaThrows:true},{lostAfterQa:true}])test(`secondary QA error ${JSON.stringify(options)} inspects without retry`,async t=>{
 const root=await checkout(t),mock=runner({states:[32],...options}),output=logger()
 assert.equal(await setupSecondaryQa({root,env,run:mock.run,output}),options.qaCode??1)
 assert.equal(mock.calls.filter(c=>c.input?.includes('do $qa$')).length,1)
 assert.ok(output.value().includes(options.lostAfterQa?'QA_SECUNDARIO_INDETERMINADO':'QA_SECUNDARIO_PRONTO'))
})
test('secondary blocked account or drift never mutates/reassigns it',async t=>{
 const root=await checkout(t),before=inspection(false);before[0].checks.primario_ativo=false
 const mock=runner({states:[32],before}),output=logger()
 assert.equal(await setupSecondaryQa({root,env,run:mock.run,output}),1)
 assert.ok(output.value().includes('QA_SECUNDARIO_BLOQUEADO'))
 assert.ok(!mock.calls.some(c=>c.input?.includes('do $qa$')))
})
test('secondary corrupted migration/SQL or extra file stops before credentials or remote calls',async t=>{
 const root=await checkout(t)
 await validateSecondaryPayload(root)
 await writeFile(join(root,'scripts','sql','provision-secondary-qa.sql'),'select true;')
 await assert.rejects(setupSecondaryQa({root,env,prompt:()=>assert.fail('no password'),run:()=>assert.fail('no remote')}),/diverge/)
})
test('secondary revalidates payload between history and push',async t=>{
 const root=await checkout(t),mock=runner({onFirstHistory:()=>writeFile(join(root,'supabase','migrations',Object.keys(manifest.migrations).at(-1)),'-- modified')})
 await assert.rejects(setupSecondaryQa({root,env,run:mock.run,output:logger()}),/diverge/)
 assert.equal(mock.calls.length,1)
})
test('secondary verifies every baseline check before push and fails closed on malformed or mixed state',async t=>{
 const root=await checkout(t)
 for(const name of readinessChecks) {
  const data=ready();data[0][name]=false
  const mock=runner({readinessRows:data})
  await assert.rejects(setupSecondaryQa({root,env,run:mock.run,output:logger()}),/ADMIN_31_BLOQUEADO/)
  assert.ok(!mock.calls.some(c=>c.args.includes('push')||c.input?.includes('do $qa$')))
 }
 for(const data of [[],[{}],ready().concat(ready())])assert.throws(()=>verifyReadiness(data))
 for(const invalid of [null,'true',1]){const data=ready();data[0].sem_objetos_32=invalid;assert.throws(()=>verifyReadiness(data))}
})
test('secondary revalidates reviewed files after the read-only gate and before its first write',async t=>{
 const root=await checkout(t),mock=runner({onReadiness:()=>writeFile(join(root,'supabase','migrations',Object.keys(manifest.migrations).at(-1)),'-- changed after gate')})
 await assert.rejects(setupSecondaryQa({root,env,run:mock.run,output:logger()}),/diverge/)
 assert.ok(!mock.calls.some(c=>c.args.includes('push')))
})
test('migration embeds the exact read-only gate before creating its first role',async()=>{
 const migration=await (await import('node:fs/promises')).readFile(join(repositoryRoot,'supabase','migrations',Object.keys(manifest.migrations).at(-1)),'utf8')
 const sql=await (await import('node:fs/promises')).readFile(join(repositoryRoot,'scripts/sql/verify-tenant-admin-before-apply.sql'),'utf8')
 const embedded=migration.split('-- BEGIN_READINESS_QUERY\n')[1]?.split('\n-- END_READINESS_QUERY')[0]
 assert.equal(embedded,sql.trim().replace(/;$/,''))
 assert.ok(migration.indexOf('-- END_READINESS_QUERY')<migration.indexOf('create role bpf_tenant_admin'))
})
test('secondary strict parsers reject missing/extra/nonboolean fields and identifiers',()=>{
 for(const data of [[],[{}],metadata().concat(metadata())])assert.throws(()=>verifyAdministration(data))
 const strings=metadata();strings[0].administracao_role='true';assert.throws(()=>verifyAdministration(strings))
 assert.equal(classifySecondary(inspection(false)).kind,'eligible')
 assert.equal(classifySecondary(inspection(true)).kind,'ready')
 const invalid=inspection(true);invalid[0].empresa_id=null;assert.throws(()=>classifySecondary(invalid))
})
