import assert from 'node:assert/strict'
import { cp, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import qaManifest from './qa-workspace-manifest.json' with { type: 'json' }
import { checkNames as metadataChecks } from './supabase-apply-documentos.mjs'
import { classifyQa, diagnoseQa, explainQaDiagnosis, prepareQa, qaSql, validateEmail } from './supabase-prepare-qa.mjs'
import { officialProjectRef, repositoryRoot, runCommand } from './supabase-preflight.mjs'

const env = { npm_execpath:'/tmp/npm-cli.js', BPF_QA_EMAIL:'qa@example.test', SUPABASE_DB_PASSWORD:'db-secret-not-needed', SUPABASE_DEBUG:'true' }
const logger = () => { let text=''; return { write:value=>{text+=value}, value:()=>text } }
const metadata = () => [Object.fromEntries(metadataChecks.map(name=>[name,true]))]
const diagnosis = overrides => [{auth_encontrados:1,cadastros_encontrados:1,auth_confirmados:1,auth_banidos:0,
  auth_excluidos:0,cadastros_habilitados:1,emails_coincidentes:1,empresas_principais:0,unidades_principais:0,
  memberships:0,perfis_legados:0,provisionamentos:0,empresas_criadas:0,
  marcador_existe:false,marcador_desta_conta:false,marcador_valido:false,...overrides}]
const sample = ready => [{
  checks:{conta_valida:true,marcador_ausente:!ready,conta_livre:!ready,identidade_isolada:ready,
    perfil_local_completo:ready,trial_preservado:ready,onboarding_disponivel:ready,provisionamento_auditado:ready},
  empresa_id:ready?'ab000000-0000-0000-0000-000000000001':null,
  unidade_id:ready?'ab000000-0000-0000-0000-000000000002':null,
  perfil_id:ready?'ab000000-0000-0000-0000-000000000003':null,
  trial_fim:ready?'2026-10-30T15:00:00+00:00':null,
  quantidade_permissoes:ready?43:null,
}]
async function checkout(t) {
  const root=await mkdtemp(join(tmpdir(),'bpf qa bootstrap '))
  t.after(()=>rm(root,{recursive:true,force:true}))
  await cp(join(repositoryRoot,'supabase','migrations'),join(root,'supabase','migrations'),{recursive:true})
  await mkdir(join(root,'supabase','.temp'),{recursive:true})
  await writeFile(join(root,'supabase','.temp','project-ref'),officialProjectRef)
  await mkdir(join(root,'scripts','sql'),{recursive:true})
  for (const file of [...Object.keys(qaManifest),'scripts/sql/verify-documentos-deploy.sql']) await cp(join(repositoryRoot,file),join(root,file))
  return root
}
function runner({before=sample(false),after=sample(true),mutationCode=0,mutationThrows=false,afterFails=false,badMetadata=false,onInspect,diagnosticData=diagnosis(),diagnosticCode=0}={}) {
  const calls=[]
  let inspected=0
  return {calls,run:async (args,context)=>{
    calls.push({args,context})
    assert.equal(args[args.indexOf('--project-ref')+1],officialProjectRef)
    assert.equal(args[args.indexOf('--profile')+1],'supabase')
    assert.ok(args.includes('--linked'))
    assert.ok(args.includes('--package=supabase@2.121.0'))
    for(const forbidden of ['push','reset','repair','--db-url','--debug']) assert.ok(!args.includes(forbidden))
    assert.equal(context.env.SUPABASE_DB_PASSWORD,env.SUPABASE_DB_PASSWORD)
    assert.ok(!args.join(' ').includes(env.SUPABASE_DB_PASSWORD))
    assert.equal(context.env.SUPABASE_DEBUG,'false')
    assert.ok(!args.join(' ').includes(env.BPF_QA_EMAIL))
    assert.ok(!args.join(' ').includes('do $qa$'))
    if(args.includes('--file')) return {code:badMetadata?1:0,data:metadata()}
    assert.ok(context.input.includes(Buffer.from(env.BPF_QA_EMAIL).toString('hex')))
    if(context.input.includes('with alvo as')) return {code:diagnosticCode,data:diagnosticData}
    if(context.input.includes('do $qa$')) {
      if(mutationThrows) throw new Error('lost process')
      return mutationCode
    }
    inspected+=1
    if(onInspect) await onInspect(inspected)
    if(inspected>1 && afterFails) return {code:1,data:null}
    return {code:0,data:inspected===1?before:after}
  }}
}

test('QA creates only after metadata and eligible account; SQL sent via stdin',async t=>{
  const root=await checkout(t),mock=runner(),output=logger()
  assert.equal(await prepareQa({root,env,run:mock.run,output}),0)
  assert.equal(mock.calls.length,4)
  assert.equal(mock.calls.filter(c=>c.context.input?.includes('do $qa$')).length,1)
  assert.ok(output.value().includes('QA_PRONTO'))
})
test('QA existing environment only inspects; never renews or recreates',async t=>{
  const root=await checkout(t),mock=runner({before:sample(true)})
  assert.equal(await prepareQa({root,env,run:mock.run,output:logger()}),0)
  assert.equal(mock.calls.length,3)
  assert.ok(!mock.calls.some(c=>c.context.input?.includes('do $qa$')))
})
test('QA bound/blocked account stops before mutation',async t=>{
  const root=await checkout(t),before=sample(false)
  before[0].checks.conta_livre=false
  const mock=runner({before}),output=logger()
  assert.equal(await prepareQa({root,env,run:mock.run,output}),1)
  assert.equal(mock.calls.length,3)
  assert.ok(output.value().includes('QA_BLOQUEADO'))
  assert.ok(output.value().includes('DIAGNOSTICO_QA_CONCLUIDO'))
  assert.ok(!mock.calls.some(c=>c.context.input?.includes('do $qa$')))
})
for(const options of [{mutationCode:7},{mutationThrows:true}]) {
  test(`QA inspects after mutation failure and preserves failure ${JSON.stringify(options)}`,async t=>{
    const root=await checkout(t),mock=runner(options),output=logger()
    assert.equal(await prepareQa({root,env,run:mock.run,output}),options.mutationCode??1)
    assert.equal(mock.calls.length,4)
    assert.ok(output.value().includes('QA_PRONTO'))
  })
}
for(const options of [{afterFails:true},{after:sample(false)}]) {
  test(`QA distinguishes lost confirmation from absent environment ${JSON.stringify(options)}`,async t=>{
    const root=await checkout(t),mock=runner(options),output=logger()
    assert.equal(await prepareQa({root,env,run:mock.run,output}),1)
    assert.equal(mock.calls.filter(c=>c.context.input?.includes('do $qa$')).length,1)
    assert.ok(output.value().includes(options.afterFails?'QA_INDETERMINADO':'QA_NAO_CONFIRMADO'))
  })
}
test('QA metadata failure prevents account query and mutation',async t=>{
  const root=await checkout(t),mock=runner({badMetadata:true})
  await assert.rejects(prepareQa({root,env,run:mock.run,output:logger()}),/estrutural/)
  assert.equal(mock.calls.length,1)
})
test('QA tampered SQL or project stops before any connection',async t=>{
  const root=await checkout(t)
  await writeFile(join(root,'supabase','.temp','project-ref'),'other-ref')
  await assert.rejects(prepareQa({root,env,run:()=>assert.fail('no connection'),prompt:()=>assert.fail('no password')}),/vinculado/)
  await writeFile(join(root,'scripts','sql','provision-qa-workspace.sql'),'select true;')
  await assert.rejects(prepareQa({root,env,run:()=>assert.fail('no connection')}),/diverge/)
})
test('QA rechecks SQL after eligibility before mutation',async t=>{
  const root=await checkout(t),mock=runner({onInspect:async n=>{
    if(n===1)await writeFile(join(root,'scripts','sql','provision-qa-workspace.sql'),'select true;')
  }})
  await assert.rejects(prepareQa({root,env,run:mock.run,output:logger()}),/diverge/)
  assert.equal(mock.calls.length,2)
})
test('QA parser rejects missing/extra/string checks and incomplete identifiers',()=>{
  for(const rows of [[],[{}],[...sample(true),...sample(true)]]) assert.throws(()=>classifyQa(rows))
  const strings=sample(true);strings[0].checks.trial_preservado='true'
  assert.throws(()=>classifyQa(strings))
  const missing=sample(true);missing[0].empresa_id=null
  assert.throws(()=>classifyQa(missing))
  assert.equal(classifyQa(sample(true)).kind,'ready')
})
test('QA email uses encoded UTF8 and cannot become SQL syntax or argv',async()=>{
  const email="o'hara@example.test"
  assert.equal(validateEmail(' '+email.toUpperCase()+' '),email)
  const sql=await qaSql(repositoryRoot,'scripts/sql/provision-qa-workspace.sql',email)
  assert.ok(!sql.includes(email))
  assert.ok(sql.includes(Buffer.from(email).toString('hex')))
  for(const bad of [undefined,'','a\nb@example.test','x@example.test; DROP TABLE empresas']) assert.throws(()=>validateEmail(bad))
})
test('QA real subprocess consumes SQL from stdin without placing it in argv',async t=>{
  const root=await checkout(t),file=join(root,'fake-cli.mjs')
  await writeFile(file,`let text='';for await(const chunk of process.stdin)text+=chunk;process.stdout.write(JSON.stringify({received:text,args:process.argv.slice(2)}))`)
  const result=await runCommand([file],{root,env:process.env,password:'',input:'select 42;',parseOutput:JSON.parse,quiet:true,output:logger(),errorOutput:logger()})
  assert.deepEqual(result,{code:0,data:{received:'select 42;',args:[]}})
})
test('QA missing password uses reviewed hidden prompt once; empty or cancelled input prevents CLI',async t=>{
  const root=await checkout(t),mock=runner()
  let prompted=0
  assert.equal(await prepareQa({root,env:{...env,SUPABASE_DB_PASSWORD:undefined},prompt:async()=>{prompted++;return env.SUPABASE_DB_PASSWORD},run:mock.run,output:logger()}),0)
  assert.equal(prompted,1)
  for(const prompt of [async()=>'',async()=>{throw Object.assign(new Error('cancelled'),{exitCode:130})}]) {
    await assert.rejects(prepareQa({root,env:{...env,SUPABASE_DB_PASSWORD:undefined},prompt,run:()=>assert.fail('no CLI'),output:logger()}))
  }
})

test('QA standalone diagnosis runs only the fixed SELECT with a single password prompt',async t=>{
  const root=await checkout(t),mock=runner({diagnosticData:diagnosis({empresas_principais:1,memberships:2})}),output=logger()
  let prompted=0
  assert.equal(await diagnoseQa({root,env:{...env,SUPABASE_DB_PASSWORD:undefined},prompt:async()=>{prompted++;return env.SUPABASE_DB_PASSWORD},run:mock.run,output}),0)
  assert.equal(prompted,1)
  assert.equal(mock.calls.length,1)
  assert.ok(mock.calls[0].context.input.includes('with alvo as'))
  assert.ok(output.value().includes('EMPRESA_PRINCIPAL_EXISTENTE'))
  assert.ok(output.value().includes('VINCULOS_EMPRESARIAIS_EXISTENTES'))
  assert.ok(!output.value().includes(env.BPF_QA_EMAIL))
})
test('QA diagnosis distinguishes missing Auth/app, ambiguity, confirmation and every guard',()=>{
  for(const [overrides,reason] of [
    [{auth_encontrados:0},'CONTA_AUTH_NAO_ENCONTRADA'],
    [{auth_encontrados:2},'EMAIL_AMBIGUO_NO_AUTH'],
    [{cadastros_encontrados:0},'CADASTRO_DA_APLICACAO_AUSENTE'],
    [{auth_confirmados:0},'EMAIL_NAO_CONFIRMADO'],
    [{auth_banidos:1},'CONTA_AUTH_BANIDA'],
    [{auth_excluidos:1},'CONTA_AUTH_EXCLUIDA'],
    [{cadastros_habilitados:0},'CADASTRO_INATIVO_OU_BLOQUEADO'],
    [{emails_coincidentes:0},'EMAIL_DO_CADASTRO_DIVERGENTE'],
    [{empresas_principais:1},'EMPRESA_PRINCIPAL_EXISTENTE'],
    [{unidades_principais:1},'UNIDADE_PRINCIPAL_EXISTENTE'],
    [{memberships:1},'VINCULOS_EMPRESARIAIS_EXISTENTES'],
    [{perfis_legados:1},'PERFIS_LEGADOS_EXISTENTES'],
    [{provisionamentos:1},'PROVISIONAMENTO_ANTERIOR'],
    [{empresas_criadas:1},'EMPRESAS_CRIADAS_PELA_CONTA'],
    [{marcador_existe:true},'MARCADOR_QA_DE_OUTRA_CONTA'],
    [{marcador_existe:true,marcador_desta_conta:true},'MARCADOR_QA_INCOMPLETO_OU_DIVERGENTE'],
  ]) assert.ok(explainQaDiagnosis(diagnosis(overrides)).reasons.includes(reason))
  assert.deepEqual(explainQaDiagnosis(diagnosis()),{reasons:[],existing:false})
  assert.deepEqual(explainQaDiagnosis(diagnosis({marcador_existe:true,marcador_desta_conta:true,marcador_valido:true,empresas_principais:1})),{reasons:[],existing:true})
})
test('QA diagnosis rejects unexpected payload without echoing PII or raw errors',async t=>{
  const root=await checkout(t),output=logger()
  const secret='fake-token-or-sensitive-payload'
  for(const data of [[],[{}],diagnosis({auth_encontrados:'1'}),diagnosis({email:env.BPF_QA_EMAIL,token:secret})]) {
    await assert.rejects(diagnoseQa({root,env,output,run:async(args,context)=>{
      context.output.write(secret);context.errorOutput.write(env.BPF_QA_EMAIL)
      return {code:0,data}
    }}),/diagnostico QA invalida/)
  }
  await assert.rejects(diagnoseQa({root,env,output,run:async(args,context)=>{
    context.output.write(secret);context.errorOutput.write(env.BPF_QA_EMAIL)
    return {code:8,data:null}
  }}),/indisponivel/)
  await assert.rejects(diagnoseQa({root,env,output,run:async()=>{throw new Error(secret+' '+env.BPF_QA_EMAIL)}}),/indisponivel/)
  assert.ok(!output.value().includes(secret))
  assert.ok(!output.value().includes(env.BPF_QA_EMAIL))
})
test('QA failed automatic diagnosis preserves blocking with no mutation or second password',async t=>{
  const root=await checkout(t),before=sample(false)
  before[0].checks.conta_livre=false
  const mock=runner({before,diagnosticCode:9}),output=logger()
  let prompts=0
  assert.equal(await prepareQa({root,env:{...env,SUPABASE_DB_PASSWORD:undefined},prompt:async()=>{prompts++;return env.SUPABASE_DB_PASSWORD},run:mock.run,output}),1)
  assert.equal(prompts,1)
  assert.equal(mock.calls.length,3)
  assert.ok(output.value().includes('DIAGNOSTICO_QA_INDISPONIVEL'))
  assert.ok(!mock.calls.some(c=>c.context.input?.includes('do $qa$')))
})
