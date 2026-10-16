import { createHash } from 'node:crypto'
import { readFile, readdir } from 'node:fs/promises'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
import manifest from './documentos-deploy-manifest.json' with { type: 'json' }
import { buildCliArgs, officialProjectRef, repositoryRoot, runCommand, withDatabasePassword } from './supabase-preflight.mjs'

export const expectedVersions = Object.keys(manifest.migrations).sort().map(name => name.slice(0, 14))
export const checkNames = ['historico_exato', 'tabelas_fechadas', 'rpcs_finais', 'helpers_fechados', 'contratos_versionados', 'integridade_documental', 'roles_restritas', 'permissoes_documentais']

export async function validatePayload(root) {
  const files = (await readdir(join(root, 'supabase', 'migrations'), { withFileTypes: true }))
    .filter(entry => entry.name.endsWith('.sql'))
  const names = files.map(entry => entry.name).sort()
  if (files.some(entry => !entry.isFile()) || JSON.stringify(names) !== JSON.stringify(Object.keys(manifest.migrations).sort())) {
    throw new Error('O conjunto local precisa conter exatamente as 31 migrations revisadas. Nenhuma aplicacao foi iniciada nesta etapa.')
  }
  for (const [name, expected] of [...Object.entries(manifest.migrations), [manifest.verification_file, manifest.verification_sha256]]) {
    const path = name === manifest.verification_file ? join(root, name) : join(root, 'supabase', 'migrations', name)
    const text = (await readFile(path, 'utf8')).replaceAll('\r\n', '\n')
    if (createHash('sha256').update(text).digest('hex') !== expected) {
      throw new Error(`Arquivo diverge da revisao aprovada: ${name}. Operacao interrompida.`)
    }
  }
}

export function classifyHistory(data) {
  if (!data || !Array.isArray(data.migrations) || data.migrations.length !== expectedVersions.length) {
    throw new Error('Historico inesperado: quantidade ou formato divergente. Nao usar repair ou include-all.')
  }
  let applied = 0
  let missing = false
  data.migrations.forEach((row, index) => {
    if (!row || row.local !== expectedVersions[index] || (row.remote !== '' && row.remote !== row.local)) {
      throw new Error('Historico inesperado: versao desconhecida, duplicada ou divergente. Operacao interrompida.')
    }
    if (row.remote === '') missing = true
    else {
      if (missing) throw new Error('Historico remoto nao e um prefixo alinhado. Operacao interrompida.')
      applied += 1
    }
  })
  if (applied === 29) return 'pending'
  if (applied === 30) return 'partial'
  if (applied === 31) return 'complete'
  throw new Error('Historico fora do bloco aprovado: esperado 29, 30 ou 31 aplicadas.')
}

export function verifyMetadata(data) {
  if (!Array.isArray(data) || data.length !== 1 || !data[0] ||
      JSON.stringify(Object.keys(data[0]).sort()) !== JSON.stringify([...checkNames].sort())) {
    throw new Error('Consulta estrutural nao retornou exatamente uma linha com os oito checks esperados.')
  }
  const failed = checkNames.filter(name => data[0][name] !== true)
  if (failed.length) throw new Error(`Checks estruturais pendentes: ${failed.join(', ')}.`)
}

export async function applyDocumentos({ root = repositoryRoot, env = process.env, prompt, run = runCommand, output = process.stdout } = {}) {
  await validatePayload(root)
  output.write(`APLICACAO REAL de Documentos no projeto ${officialProjectRef}. Somente as migrations 30 e 31 revisadas.\n`)
  return withDatabasePassword({ root, env, prompt, output, action: async context => {
    const history = async () => {
      const result = await run(buildCliArgs(root, env, ['migration', 'list', '--output-format', 'json', '--agent', 'no']), { ...context, parseOutput: JSON.parse, quiet: true })
      if (result.code !== 0) throw new Error('Nao foi possivel consultar o historico remoto.')
      return classifyHistory(result.data)
    }
    output.write('Conferindo historico remoto...\n')
    let state = await history()
    if (state === 'partial') {
      output.write('ESTADO: PARCIAL_30. A fundacao ja consta aplicada e a corretiva esta pendente; exige diagnostico antes de retomar. Nenhum push foi executado nesta chamada.\n')
      return 1
    }
    let pushCode = 0
    if (state === 'pending') {
      await validatePayload(root)
      output.write('29 alinhadas; aplicando somente 20261014124000 e 20261015203000...\n')
      try {
        pushCode = await run(buildCliArgs(root, env, ['db', 'push', '--skip-vault', '--yes']), context)
      } catch {
        pushCode = 1
        output.write('A tentativa de aplicacao terminou sem resultado confiavel do CLI; verificando historico.\n')
      }
      // Each migration commits independently. Always inspect after a push attempt.
      try { state = await history() }
      catch {
        output.write('ESTADO: INDETERMINADO. A tentativa pode ter aplicado parte ou todas as migrations. Nao repetir push, reset ou repair sem conferir o historico.\n')
        return pushCode || 1
      }
      if (state !== 'complete') {
        output.write(state === 'partial'
          ? 'ESTADO: PARCIAL_30. Migration 30 aplicada; 31 pendente. Nao houve rollback automatico da migration 30.\n'
          : 'ESTADO: HISTORICO_29. Nenhuma das duas migrations consta aplicada. A falha deve ser diagnosticada antes de nova tentativa.\n')
        return pushCode || 1
      }
      output.write('Historico confirma as 31 migrations alinhadas.\n')
    } else output.write('As 31 migrations ja estao alinhadas; sem repetir push.\n')

    // This independent channel uses the Management API's existing CLI authentication.
    // Failure here cannot undo migrations already confirmed in the database history.
    try {
      await validatePayload(root)
      output.write('Conferindo estrutura, historico completo, RLS e ACLs (Management API)...\n')
      const result = await run(buildCliArgs(root, env, ['db', 'query', '--file', join(root, manifest.verification_file), '--output', 'json', '--agent', 'no']), { ...context, parseOutput: JSON.parse, quiet: true })
      if (result.code !== 0) throw new Error('Consulta administrativa indisponivel ou recusada.')
      verifyMetadata(result.data)
    } catch (error) {
      output.write(`ESTADO: HISTORICO_31_VERIFICACAO_PENDENTE. Migrations confirmadas; nao repetir push. ${error.message}\n`)
      return pushCode || 1
    }
    output.write('ESTADO: HISTORICO_31_E_ESTRUTURA_OK. Oito checks aprovados. Nenhuma permissao foi concedida a perfis. Smoke PostgREST permanece uma etapa separada.\n')
    return pushCode
  } })
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    if (process.argv.length > 2) throw new Error('Este comando nao aceita argumentos; aplica somente o bloco Documentos revisado.')
    process.exitCode = await applyDocumentos()
  } catch (error) {
    console.error(error.message)
    process.exitCode = error.exitCode ?? 1
  }
}
