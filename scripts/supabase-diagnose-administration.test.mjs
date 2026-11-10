import assert from 'node:assert/strict'
import { cp,mkdir,mkdtemp,readFile,rm,writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import manifest from './admin-diagnosis-manifest.json' with {type:'json'}
import { diagnoseAdministration,diagnosisSql,parseAdministrationDiagnosis } from './supabase-diagnose-administration.mjs'
import { officialProjectRef,repositoryRoot } from './supabase-preflight.mjs'

const env={npm_execpath:'/tmp/npm-cli.js',SUPABASE_DB_PASSWORD:'fake-db-secret'}
const rows=()=>[{relatorio:{versoes:['20260916222814'],tabelas:[],policies:[],acls:[],roles:[],membros_roles:[],funcoes:[],view_contexto:null}}]
const logger=()=>{let value='';return{write:text=>{value+=text},value:()=>value}}
async function checkout(t) {
  const root=await mkdtemp(join(tmpdir(),'bpf admin diagnosis '))
  t.after(()=>rm(root,{recursive:true,force:true}))
  await mkdir(join(root,'supabase','.temp'),{recursive:true});await mkdir(join(root,'scripts','sql'),{recursive:true})
  await writeFile(join(root,'supabase','.temp','project-ref'),officialProjectRef)
  await cp(join(repositoryRoot,manifest.file),join(root,manifest.file))
  return root
}
test('admin diagnosis uses exactly one fixed stdin SELECT, hidden password and no write command',async t=>{
  const root=await checkout(t),output=logger();let calls=0
  const run=async(args,context)=>{
    calls++
    assert.ok(args.includes('query')&&!args.some(a=>['push','repair','reset'].includes(a)))
    assert.equal(args[args.indexOf('--project-ref')+1],officialProjectRef)
    assert.equal(args[args.indexOf('--profile')+1],'supabase')
    assert.equal(context.input,await diagnosisSql(root))
    assert.equal(context.env.SUPABASE_DB_PASSWORD,env.SUPABASE_DB_PASSWORD)
    assert.ok(!args.join(' ').includes('select')&&!args.join(' ').includes(env.SUPABASE_DB_PASSWORD))
    context.output.write('private stdout');context.errorOutput.write('private stderr')
    return{code:0,data:rows()}
  }
  assert.equal(await diagnoseAdministration({root,env,run,output}),0)
  assert.equal(calls,1)
  assert.ok(output.value().includes('DIAGNOSTICO_ADMIN_CONCLUIDO'))
  assert.ok(!output.value().includes('private'))
})
for(const failure of ['code','throw','invalid'])test(`admin diagnosis suppresses raw failure ${failure} without retry`,async t=>{
  const root=await checkout(t),output=logger();let calls=0
  const run=async(args,context)=>{
    calls++;context.output.write('token=private');context.errorOutput.write('token=private')
    if(failure==='throw')throw new Error('token=private')
    return failure==='code'?{code:7,data:null}:{code:0,data:[{private:'token=private'}]}
  }
  assert.equal(await diagnoseAdministration({root,env,run,output}),failure==='code'?7:1)
  assert.equal(calls,1)
  assert.ok(!output.value().includes('private'))
  assert.ok(output.value().includes('DIAGNOSTICO_ADMIN_INDISPONIVEL'))
})
test('admin diagnosis altered SQL stops before credentials or remote calls and accepts CRLF only normalization',async t=>{
  const root=await checkout(t),path=join(root,manifest.file)
  await writeFile(path,(await readFile(path,'utf8')).replaceAll('\n','\r\n'))
  await diagnosisSql(root)
  await writeFile(path,'select true;')
  await assert.rejects(diagnoseAdministration({root,env,prompt:()=>assert.fail(),run:()=>assert.fail()}),/diverge/)
})
test('admin diagnosis parser accepts metadata only in its exact response envelope',()=>{
  assert.equal(parseAdministrationDiagnosis(rows()).view_contexto,null)
  for(const value of [null,[],[{}],rows().concat(rows())])assert.throws(()=>parseAdministrationDiagnosis(value))
  for(const field of ['versoes','tabelas','policies','acls','roles','membros_roles','funcoes']) {
    const value=rows();value[0].relatorio[field]=null;assert.throws(()=>parseAdministrationDiagnosis(value))
  }
  const extra=rows();extra[0].relatorio.token='private';assert.throws(()=>parseAdministrationDiagnosis(extra))
  for(const field of ['tabelas','policies','acls','roles','membros_roles','funcoes']) {
    const value=rows();value[0].relatorio[field]=[{token:'private'}];assert.throws(()=>parseAdministrationDiagnosis(value))
  }
})
test('admin diagnosis redacts the database password even inside otherwise valid metadata',async t=>{
  const root=await checkout(t),output=logger(),data=rows()
  data[0].relatorio.tabelas=[{tabela:'empresas',owner:env.SUPABASE_DB_PASSWORD,rls:true,force_rls:false}]
  assert.equal(await diagnoseAdministration({root,env,output,run:async()=>({code:0,data})}),0)
  assert.ok(!output.value().includes(env.SUPABASE_DB_PASSWORD))
  assert.ok(output.value().includes('[REDACTED]'))
})
