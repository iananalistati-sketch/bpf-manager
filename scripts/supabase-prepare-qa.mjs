import { createHash } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
import manifest from './qa-workspace-manifest.json' with { type: 'json' }
import { buildCliArgs, officialProjectRef, repositoryRoot, runCommand, withDatabasePassword } from './supabase-preflight.mjs'
import { validatePayload, verifyMetadata } from './supabase-apply-documentos.mjs'

const checkNames = ['conta_valida','marcador_ausente','conta_livre','identidade_isolada','perfil_local_completo','trial_preservado','onboarding_disponivel','provisionamento_auditado']
const readyChecks = checkNames.filter(name => !['marcador_ausente','conta_livre'].includes(name))
const resultNames = ['checks','empresa_id','unidade_id','perfil_id','trial_fim','quantidade_permissoes']
const sameKeys = (value, keys) => value && typeof value === 'object' && !Array.isArray(value)
  && JSON.stringify(Object.keys(value).sort()) === JSON.stringify([...keys].sort())

export function validateEmail(email) {
  if (typeof email !== 'string' || email.trim().length > 254
      || !/^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}$/.test(email.trim())) {
    throw new Error('Configure BPF_QA_EMAIL com o e-mail da conta exclusiva de teste ja cadastrada e confirmada no Auth. Nao informe senha.')
  }
  return email.trim().toLowerCase()
}

export async function qaSql(root, filename, email) {
  if (!Object.hasOwn(manifest, filename)) throw new Error('SQL fora do conjunto QA revisado.')
  const sql = (await readFile(join(root, filename), 'utf8')).replaceAll('\r\n','\n')
  if (createHash('sha256').update(sql).digest('hex') !== manifest[filename]) {
    throw new Error('SQL QA diverge da revisao aprovada. Operacao interrompida.')
  }
  const hex = Buffer.from(validateEmail(email),'utf8').toString('hex')
  return sql.replaceAll('__BPF_QA_EMAIL_HEX__', hex)
}

export function classifyQa(rows) {
  const row = Array.isArray(rows) && rows.length === 1 ? rows[0] : null
  if (!sameKeys(row,resultNames) || !sameKeys(row.checks,checkNames)
      || checkNames.some(name => typeof row.checks[name] !== 'boolean')) {
    throw new Error('Inspecao QA invalida ou incompleta. Nenhuma retomada automatica.')
  }
  const checks = row.checks
  if (readyChecks.every(name => checks[name]) && !checks.marcador_ausente && !checks.conta_livre) {
    for (const name of ['empresa_id','unidade_id','perfil_id']) {
      if (!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(row[name])) throw new Error('Inspecao QA sem identificadores validos.')
    }
    if (!Number.isInteger(row.quantidade_permissoes) || row.quantidade_permissoes < 7
        || typeof row.trial_fim !== 'string' || !Number.isFinite(Date.parse(row.trial_fim))) {
      throw new Error('Inspecao QA sem permissoes ou prazo valido.')
    }
    return { kind: 'ready', row }
  }
  if (checks.conta_valida && checks.conta_livre && checks.marcador_ausente
      && readyChecks.filter(name => name !== 'conta_valida').every(name => !checks[name])
      && resultNames.filter(name => name !== 'checks').every(name => row[name] === null)) return { kind: 'eligible', row }
  return { kind: 'blocked', row }
}

export async function prepareQa({ root = repositoryRoot, env = process.env, run = runCommand, output = process.stdout, prompt } = {}) {
  const email = validateEmail(env.BPF_QA_EMAIL)
  await validatePayload(root)
  for (const filename of Object.keys(manifest)) await qaSql(root,filename,email)
  return withDatabasePassword({ root, env, prompt, output, action: async secureContext => {
    const args = buildCliArgs(root,env,['db','query','--output','json','--agent','no'])
    // SQL uses Management API authentication; this CLI also resolves the linked
    // connection first. The secure DB password binding avoids temporary-login-role.
    const context = { ...secureContext, quiet: true }
    const query = async sql => {
      const result = await run(args,{ ...context, input: sql, parseOutput: JSON.parse })
      if (result.code !== 0) throw new Error('Consulta QA pela Management API falhou.')
      return result.data
    }
    const inspect = async () => classifyQa(await query(await qaSql(root,'scripts/sql/inspect-qa-workspace.sql',email)))
    output.write(`Preparacao REAL de empresa TESTE no projeto ${officialProjectRef}. Login administrativo existente do CLI e senha PostgreSQL oculta.\n`)
    const metadata = await run(buildCliArgs(root,env,['db','query','--file',join(root,'scripts/sql/verify-documentos-deploy.sql'),'--output','json','--agent','no']),{ ...context, parseOutput: JSON.parse })
    if (metadata.code !== 0) throw new Error('Verificacao estrutural remota indisponivel; preparacao nao iniciada.')
    verifyMetadata(metadata.data)
    const before = await inspect()
    if (before.kind === 'blocked') {
      output.write('ESTADO: QA_BLOQUEADO. Confira se a conta esta confirmada, habilitada e sem empresa/vinculos. Se o ambiente ja existe, houve divergencia; nao sera reparado automaticamente.\n')
      return 1
    }
    let status = 0
    if (before.kind === 'eligible') {
      await validatePayload(root)
      const sql = await qaSql(root,'scripts/sql/provision-qa-workspace.sql',email)
      output.write('Criando empresa, unidade e perfil locais de TESTE em uma unica transacao; trial Business de 14 dias...\n')
      try { status = await run(args,{ ...context, input: sql }) }
      catch { status = 1 }
    } else output.write('Empresa TESTE ja preparada; conferindo sem alterar dados, acessos ou prazo.\n')
    // A lost response may follow a commit. Inspect even after an error; never auto-retry.
    let after
    try { after = await inspect() }
    catch {
      output.write('ESTADO: QA_INDETERMINADO. A confirmacao remota falhou; nao repita a escrita sem conferir o estado.\n')
      return status || 1
    }
    if (after.kind !== 'ready') {
      output.write(after.kind === 'eligible'
        ? 'ESTADO: QA_NAO_CONFIRMADO. Nenhum ambiente QA confirmado; a requisicao pode estar em andamento. Diagnostique antes de tentar novamente.\n'
        : 'ESTADO: QA_DIVERGENTE. A verificacao encontrou conta, prazo ou vinculos divergentes; nenhum reparo automatico.\n')
      return status || 1
    }
    output.write(`ESTADO: QA_PRONTO. Empresa ${after.row.empresa_id}; perfil exclusivo com ${after.row.quantidade_permissoes} permissoes.\n`)
    output.write(`Trial termina em ${after.row.trial_fim}; depois passa a somente leitura. Entre com a conta de teste e conclua o onboarding antes de validar Documentos e Configuracoes.\n`)
    output.write('Nenhuma conta Auth criada, senha alterada, convite enviado ou perfil compartilhado modificado. Smoke autenticado continua separado.\n')
    return status
  } })
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    if (process.argv.length > 2) throw new Error('Este comando nao aceita argumentos; usa somente BPF_QA_EMAIL e o conjunto QA revisado.')
    process.exitCode = await prepareQa()
  } catch(error) { console.error(error.message); process.exitCode = error.exitCode ?? 1 }
}
