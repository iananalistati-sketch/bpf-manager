import { createHash } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
import manifest from './admin-diagnosis-manifest.json' with {type:'json'}
import { buildCliArgs,officialProjectRef,redact,repositoryRoot,runCommand,withDatabasePassword } from './supabase-preflight.mjs'

export async function diagnosisSql(root=repositoryRoot) {
  const sql=(await readFile(join(root,manifest.file),'utf8')).replaceAll('\r\n','\n')
  if(createHash('sha256').update(sql).digest('hex')!==manifest.sha256)throw new Error('SQL diagnostico diverge da revisao. Nenhuma consulta iniciada.')
  return sql
}

export function parseAdministrationDiagnosis(rows) {
  const report=Array.isArray(rows)&&rows.length===1?rows[0]?.relatorio:null
  const arrays=['versoes','tabelas','policies','acls','roles','membros_roles','funcoes']
  const exact=(value,keys)=>value&&typeof value==='object'&&!Array.isArray(value)
    &&JSON.stringify(Object.keys(value).sort())===JSON.stringify(keys.sort())
  const text=(value,max=256)=>typeof value==='string'&&value.length<=max
  const nullableText=(value,max)=>value===null||text(value,max)
  const bool=value=>typeof value==='boolean'
  const valid={
    tabelas:r=>exact(r,['tabela','owner','rls','force_rls'])&&text(r.tabela)&&text(r.owner)&&bool(r.rls)&&bool(r.force_rls),
    policies:r=>exact(r,['schemaname','tablename','policyname','permissive','roles','cmd','qual','with_check'])
      &&r.schemaname==='public'&&text(r.tablename)&&text(r.policyname)&&['PERMISSIVE','RESTRICTIVE'].includes(r.permissive)
      &&['ALL','SELECT','INSERT','UPDATE','DELETE'].includes(r.cmd)&&Array.isArray(r.roles)&&r.roles.length<=256
      &&r.roles.every(v=>text(v))&&nullableText(r.qual,16384)&&nullableText(r.with_check,16384),
    acls:r=>exact(r,['tabela','coluna','grantee','privilegio','delegavel'])&&text(r.tabela)&&nullableText(r.coluna,256)
      &&text(r.grantee)&&['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN'].includes(r.privilegio)&&bool(r.delegavel),
    roles:r=>exact(r,['nome','login','inherit','superuser','bypass_rls','create_role'])&&text(r.nome)
      &&['login','inherit','superuser','bypass_rls','create_role'].every(k=>bool(r[k])),
    membros_roles:r=>exact(r,['role','membro','admin','inherit','set'])&&text(r.role)&&text(r.membro)
      &&['admin','inherit','set'].every(k=>bool(r[k])),
    funcoes:r=>exact(r,['esquema','assinatura','proname','owner','security_definer','configuracao','acl','corpo_md5'])
      &&['public','private'].includes(r.esquema)&&text(r.assinatura,2048)&&text(r.proname)&&text(r.owner)&&bool(r.security_definer)
      &&Array.isArray(r.configuracao)&&r.configuracao.length<=1&&r.configuracao.every(v=>text(v,1024)&&v.startsWith('search_path='))
      &&nullableText(r.acl,16384)&&text(r.corpo_md5,32)&&/^[0-9a-f]{32}$/.test(r.corpo_md5),
  }
  if(!report||typeof report!=='object'||Array.isArray(report)
    ||JSON.stringify(Object.keys(report).sort())!==JSON.stringify([...arrays,'view_contexto'].sort())
    ||arrays.some(key=>!Array.isArray(report[key])||report[key].length>8192)
    ||report.versoes.some(v=>typeof v!=='string'||!/^\d{14}$/.test(v))
    ||Object.entries(valid).some(([key,check])=>report[key].some(r=>!check(r)))
    ||(report.view_contexto!==null&&(!text(report.view_contexto,32)||!/^[0-9a-f]{32}$/.test(report.view_contexto)))
    ||JSON.stringify(report).length>1024*1024) {
    throw new Error('Resposta diagnostica invalida. Nenhuma escrita foi solicitada.')
  }
  return report
}

export async function diagnoseAdministration({root=repositoryRoot,env=process.env,prompt,run=runCommand,output=process.stdout}={}) {
  await diagnosisSql(root)
  return withDatabasePassword({root,env,prompt,output,action:async context=>{
    output.write(`Diagnostico administrativo SOMENTE LEITURA no projeto ${officialProjectRef}. Sem push, repair ou criacao QA.\n`)
    const sink={write(){}}
    let result,report
    try {
      result=await run(buildCliArgs(root,env,['db','query','--output','json','--agent','no']),{
        ...context,input:await diagnosisSql(root),quiet:true,output:sink,errorOutput:sink,parseOutput:JSON.parse,
      })
      if(result.code!==0)throw new Error('query failed')
      report=parseAdministrationDiagnosis(result.data)
    } catch {
      output.write('DIAGNOSTICO_ADMIN_INDISPONIVEL. Nenhuma escrita solicitada; detalhes brutos do CLI suprimidos.\n')
      return result?.code||1
    }
    output.write(redact(JSON.stringify(report,null,2),context.password)+'\n')
    output.write('DIAGNOSTICO_ADMIN_CONCLUIDO. Metadados coletados; nao confirma rollback nem autoriza repetir a aplicacao.\n')
    return 0
  }})
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href) {
  try{if(process.argv.length>2)throw new Error('Diagnostico nao aceita argumentos.');process.exitCode=await diagnoseAdministration()}
  catch(error){console.error(error.message);process.exitCode=error.exitCode??1}
}
