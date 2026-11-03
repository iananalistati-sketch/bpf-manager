import { createHash } from 'node:crypto'
import { readFile,readdir } from 'node:fs/promises'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
import manifest from './secondary-qa-manifest.json' with {type:'json'}
import { checkNames as documentChecks } from './supabase-apply-documentos.mjs'
import { validateEmail } from './supabase-prepare-qa.mjs'
import { buildCliArgs,officialProjectRef,repositoryRoot,runCommand,withDatabasePassword } from './supabase-preflight.mjs'

export const administrationChecks=[...documentChecks,'administracao_contratos','administracao_role','administracao_rls']
export const secondaryChecks=['conta_valida','marcador_ausente','primario_ativo','segundo_vinculo','perfil_local','trial_valido','onboarding','auditoria']
export const secondaryVersions=Object.keys(manifest.migrations).sort().map(name=>name.slice(0,14))
const sameKeys=(value,keys)=>value&&typeof value==='object'&&!Array.isArray(value)
  &&JSON.stringify(Object.keys(value).sort())===JSON.stringify([...keys].sort())
const digest=text=>createHash('sha256').update(text.replaceAll('\r\n','\n')).digest('hex')

export function validateSecondaryEmail(email) {
  try{return validateEmail(email)}catch{
    throw new Error('Configure BPF_QA_EMAIL com seu e-mail original ja cadastrado e confirmado no Auth. Nao informe senha.')
  }
}

export async function validateSecondaryPayload(root=repositoryRoot) {
  const files=(await readdir(join(root,'supabase','migrations'),{withFileTypes:true})).filter(e=>e.name.endsWith('.sql'))
  if(files.some(e=>!e.isFile())||JSON.stringify(files.map(e=>e.name).sort())!==JSON.stringify(Object.keys(manifest.migrations).sort())) {
    throw new Error('Conjunto precisa conter exatamente as 32 migrations revisadas. Nenhuma escrita iniciada.')
  }
  for(const [name,hash] of Object.entries(manifest.migrations)) {
    if(digest(await readFile(join(root,'supabase','migrations',name),'utf8'))!==hash) throw new Error('Migration diverge da revisao aprovada; operacao interrompida.')
  }
  for(const name of Object.keys(manifest.sql)) await secondarySql(root,name)
}

export async function secondarySql(root,name,email) {
  if(!Object.hasOwn(manifest.sql,name))throw new Error('SQL fora do conjunto secundario revisado.')
  const sql=(await readFile(join(root,name),'utf8')).replaceAll('\r\n','\n')
  if(digest(sql)!==manifest.sql[name])throw new Error('SQL secundario diverge da revisao aprovada.')
  return email===undefined?sql:sql.replaceAll('__BPF_QA_EMAIL_HEX__',Buffer.from(validateSecondaryEmail(email),'utf8').toString('hex'))
}

export function classifyAdministrationHistory(data) {
  if(!data||!Array.isArray(data.migrations)||data.migrations.length!==32)throw new Error('Historico administrativo inesperado.')
  let applied=0,missing=false
  for(const [i,row] of data.migrations.entries()) {
    if(!row||row.local!==secondaryVersions[i]||(row.remote!==''&&row.remote!==row.local))throw new Error('Historico divergente; nao usar repair ou include-all.')
    if(!row.remote)missing=true
    else {if(missing)throw new Error('Historico possui lacuna.');applied++}
  }
  if(![31,32].includes(applied))throw new Error('Somente a transicao revisada 31 para 32 e permitida.')
  return applied
}

export function verifyAdministration(rows) {
  if(!Array.isArray(rows)||rows.length!==1||!sameKeys(rows[0],administrationChecks)
    ||administrationChecks.some(name=>rows[0][name]!==true))throw new Error('Verificacao remota administrativa incompleta ou divergente.')
}

export function classifySecondary(rows) {
  const row=Array.isArray(rows)&&rows.length===1?rows[0]:null
  if(!sameKeys(row,['checks','empresa_id','trial_fim'])||!sameKeys(row.checks,secondaryChecks)
    ||secondaryChecks.some(key=>typeof row.checks[key]!=='boolean'))throw new Error('Inspecao de segundo vinculo invalida.')
  const {checks}=row
  if(!checks.marcador_ausente&&secondaryChecks.filter(k=>k!=='marcador_ausente').every(k=>checks[k])) {
    if(!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(row.empresa_id)||typeof row.trial_fim!=='string'||!Number.isFinite(Date.parse(row.trial_fim)))throw new Error('Inspecao sem identificador ou prazo valido.')
    return {kind:'ready',row}
  }
  if(checks.conta_valida&&checks.primario_ativo&&checks.marcador_ausente&&row.empresa_id===null&&row.trial_fim===null
    &&secondaryChecks.filter(k=>!['conta_valida','primario_ativo','marcador_ausente'].includes(k)).every(k=>!checks[k]))return {kind:'eligible',row}
  return {kind:'blocked',row}
}

export async function setupSecondaryQa({root=repositoryRoot,env=process.env,run=runCommand,output=process.stdout,prompt}={}) {
  const email=validateSecondaryEmail(env.BPF_QA_EMAIL)
  await validateSecondaryPayload(root)
  output.write(`APLICACAO REAL: Administracao 32 e empresa TESTE secundaria no projeto ${officialProjectRef}. Preserva o login e a empresa principal.\n`)
  return withDatabasePassword({root,env,prompt,output,action:async context=>{
    const history=async()=>{
      const result=await run(buildCliArgs(root,env,['migration','list','--output-format','json','--agent','no']),{...context,quiet:true,parseOutput:JSON.parse})
      if(result.code!==0)throw new Error('Historico remoto indisponivel.')
      return classifyAdministrationHistory(result.data)
    }
    const query=async sql=>{
      const result=await run(buildCliArgs(root,env,['db','query','--output','json','--agent','no']),{...context,quiet:true,input:sql,parseOutput:JSON.parse})
      if(result.code!==0)throw new Error('Consulta administrativa indisponivel.')
      return result.data
    }
    let state=await history(),code=0
    if(state===31) {
      await validateSecondaryPayload(root)
      output.write('31 alinhadas; aplicando somente 20261029160000_tenant_administration.sql...\n')
      try{code=await run(buildCliArgs(root,env,['db','push','--skip-vault','--yes']),context)}catch{code=1}
      try{state=await history()}catch{output.write('ESTADO: ADMIN_INDETERMINADO. Nao repetir push sem conferir o historico.\n');return code||1}
      if(state!==32){output.write('ESTADO: ADMIN_NAO_CONFIRMADO. A escrita pode estar em andamento; diagnostique antes de repetir.\n');return code||1}
    } else output.write('32 migrations alinhadas; sem repetir push.\n')
    try{verifyAdministration(await query(await secondarySql(root,'scripts/sql/verify-tenant-admin.sql')))}catch{
      output.write('ESTADO: ADMIN_32_VERIFICACAO_PENDENTE. Historico confirmado; nenhum QA foi criado nesta chamada. Nao repetir push.\n');return code||1
    }
    if(code!==0){output.write('ESTADO: ADMIN_32_OK_CLI_COM_ERRO. Estrutura confirmada; erro original preservado, QA nao iniciado.\n');return code}
    const inspect=async()=>classifySecondary(await query(await secondarySql(root,'scripts/sql/inspect-secondary-qa.sql',email)))
    const before=await inspect()
    if(before.kind==='blocked'){output.write('ESTADO: QA_SECUNDARIO_BLOQUEADO. Confira conta confirmada/ativa, vinculo principal ativo ou divergencia do marcador. Nenhum reparo automatico.\n');return 1}
    if(before.kind==='eligible') {
      await validateSecondaryPayload(root)
      output.write('Criando TESTE como segundo vinculo, com perfil local e trial Business de 14 dias...\n')
      try{code=await run(buildCliArgs(root,env,['db','query','--output','json','--agent','no']),{...context,quiet:true,input:await secondarySql(root,'scripts/sql/provision-secondary-qa.sql',email)})}catch{code=1}
    } else output.write('TESTE secundaria ja existe; sem renovar trial ou restaurar permissoes.\n')
    let after
    try{after=await inspect()}catch{output.write('ESTADO: QA_SECUNDARIO_INDETERMINADO. Nao repetir escrita sem conferir o estado.\n');return code||1}
    if(after.kind!=='ready'){output.write('ESTADO: QA_SECUNDARIO_NAO_CONFIRMADO. Nenhuma retomada ou reparacao automatica.\n');return code||1}
    output.write(`ESTADO: QA_SECUNDARIO_PRONTO. Empresa ${after.row.empresa_id}; trial ate ${after.row.trial_fim}.\n`)
    output.write('Entre com seu login original, selecione BPF TESTE e conclua o onboarding. Identidade e empresa principal preservadas; smoke autenticado permanece separado.\n')
    return code
  }})
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href) {
  try{if(process.argv.length>2)throw new Error('Este comando nao aceita argumentos adicionais.');process.exitCode=await setupSecondaryQa()}
  catch(error){console.error(error.message);process.exitCode=error.exitCode??1}
}
