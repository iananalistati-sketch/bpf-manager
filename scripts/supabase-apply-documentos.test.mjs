import assert from 'node:assert/strict'
import { cp, mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import manifest from './documentos-deploy-manifest.json' with { type: 'json' }
import { applyDocumentos, checkNames, classifyHistory, expectedVersions, validatePayload, verifyMetadata } from './supabase-apply-documentos.mjs'
import { officialProjectRef, repositoryRoot } from './supabase-preflight.mjs'

const env = { npm_execpath: '/tmp/npm-cli.js', SUPABASE_DB_PASSWORD: 'senha-ficticia $& com espacos' }
const history = count => ({ migrations: expectedVersions.map((local, i) => ({ local, remote: i < count ? local : '', time: 'irrelevante' })) })
const metadata = () => [Object.fromEntries(checkNames.map(name => [name, true]))]
const logger = () => { let text = ''; return { write: value => { text += value }, value: () => text } }
async function checkout(t) {
  const root = await mkdtemp(join(tmpdir(), 'bpf apply test '))
  t.after(() => rm(root, { recursive: true, force: true }))
  await cp(join(repositoryRoot, 'supabase', 'migrations'), join(root, 'supabase', 'migrations'), { recursive: true })
  await mkdir(join(root, 'supabase', '.temp'), { recursive: true })
  await writeFile(join(root, 'supabase', '.temp', 'project-ref'), officialProjectRef)
  await mkdir(join(root, 'scripts', 'sql'), { recursive: true })
  await cp(join(repositoryRoot, manifest.verification_file), join(root, manifest.verification_file))
  return root
}
function runner(states = [29, 31], { pushCode = 0, queryCode = 0, checks = metadata(), pushThrows = false, afterFirstHistory } = {}) {
  const calls = []
  let next = 0
  const run = async (args, context) => {
    calls.push(args)
    assert.equal(context.env.SUPABASE_DB_PASSWORD, env.SUPABASE_DB_PASSWORD)
    assert.equal(args[args.indexOf('--project-ref') + 1], officialProjectRef)
    assert.ok(!args.join(' ').includes(env.SUPABASE_DB_PASSWORD))
    if (args.includes('list')) {
      const state = states[next++]
      if (state === 'unreadable') throw new Error('resposta indisponivel')
      if (next === 1 && afterFirstHistory) await afterFirstHistory()
      return { code: 0, data: history(state) }
    }
    if (args.includes('push')) {
      assert.ok(args.includes('--skip-vault'))
      assert.ok(args.slice(args.indexOf('push')).includes('--yes'))
      for (const forbidden of ['--include-all', '--include-seed', '--include-roles', '--db-url', '--debug']) assert.ok(!args.includes(forbidden))
      if (pushThrows) throw new Error('processo perdido')
      return pushCode
    }
    assert.ok(args.includes('query'))
    assert.ok(args.includes('--file'))
    assert.equal(args[args.indexOf('--output') + 1], 'json')
    assert.equal(args[args.indexOf('--agent') + 1], 'no')
    return { code: queryCode, data: checks }
  }
  return { run, calls }
}

test('aplica exatamente bloco pendente e confere historico e estrutura', async t => {
  const root = await checkout(t)
  const mock = runner()
  const output = logger()
  assert.equal(await applyDocumentos({ root, env, run: mock.run, output }), 0)
  assert.equal(mock.calls.length, 4)
  assert.ok(output.value().includes('HISTORICO_31_E_ESTRUTURA_OK'))
})

test('31 alinhadas executa somente verificacao, sem reaplicar', async t => {
  const root = await checkout(t)
  const mock = runner([31])
  assert.equal(await applyDocumentos({ root, env, run: mock.run, output: logger() }), 0)
  assert.equal(mock.calls.length, 2)
  assert.ok(!mock.calls.some(args => args.includes('push')))
})

test('estado parcial anterior recusa push e requer diagnostico', async t => {
  const root = await checkout(t)
  const mock = runner([30])
  const output = logger()
  assert.equal(await applyDocumentos({ root, env, run: mock.run, output }), 1)
  assert.equal(mock.calls.length, 1)
  assert.ok(output.value().includes('PARCIAL_30'))
})

for (const [state, label] of [[29, 'HISTORICO_29'], [30, 'PARCIAL_30'], ['unreadable', 'INDETERMINADO']]) {
  test(`falha do push consulta historico e classifica ${label}`, async t => {
    const root = await checkout(t)
    const mock = runner([29, state], { pushCode: 7 })
    const output = logger()
    assert.equal(await applyDocumentos({ root, env, run: mock.run, output }), 7)
    assert.equal(mock.calls.length, 3)
    assert.ok(output.value().includes(label))
  })
}

test('erro no processo apos inicio tambem consulta o historico', async t => {
  const root = await checkout(t)
  const mock = runner([29, 30], { pushThrows: true })
  const output = logger()
  assert.equal(await applyDocumentos({ root, env, run: mock.run, output }), 1)
  assert.equal(mock.calls.length, 3)
  assert.ok(output.value().includes('PARCIAL_30'))
})

test('31 alinhadas apos erro do CLI preserva o erro original e verifica estrutura', async t => {
  const root = await checkout(t)
  const mock = runner([29, 31], { pushCode: 8 })
  const output = logger()
  assert.equal(await applyDocumentos({ root, env, run: mock.run, output }), 8)
  assert.ok(output.value().includes('HISTORICO_31_E_ESTRUTURA_OK'))
})

for (const checks of [[], [{}], [{ ...metadata()[0], tabelas_fechadas: false }], [{ ...metadata()[0], rpcs_finais: 'true' }]]) {
  test(`verificacao incompleta nao desfaz nem repete aplicacao (${JSON.stringify(checks).length})`, async t => {
    const root = await checkout(t)
    const mock = runner([29, 31], { checks })
    const output = logger()
    assert.equal(await applyDocumentos({ root, env, run: mock.run, output }), 1)
    assert.ok(output.value().includes('HISTORICO_31_VERIFICACAO_PENDENTE'))
    assert.equal(mock.calls.filter(args => args.includes('push')).length, 1)
  })
}

test('falha da Management API distingue migrations ja confirmadas', async t => {
  const root = await checkout(t)
  const mock = runner([29, 31], { queryCode: 1 })
  const output = logger()
  assert.equal(await applyDocumentos({ root, env, run: mock.run, output }), 1)
  assert.ok(output.value().includes('HISTORICO_31_VERIFICACAO_PENDENTE'))
})

test('hash divergente interrompe antes de pedir senha ou executar comandos', async t => {
  const root = await checkout(t)
  await writeFile(join(root, 'supabase', 'migrations', Object.keys(manifest.migrations).at(-1)), '-- modificado')
  await assert.rejects(applyDocumentos({ root, env: {}, prompt: () => assert.fail('nao pedir senha'), run: () => assert.fail('nao conectar'), output: logger() }), /diverge/)
})

test('migration extra interrompe antes de qualquer conexao', async t => {
  const root = await checkout(t)
  await writeFile(join(root, 'supabase', 'migrations', '20261017000000_extra.sql'), 'select 1;')
  await assert.rejects(applyDocumentos({ root, env: {}, prompt: () => assert.fail('nao pedir senha'), output: logger() }), /31 migrations/)
})

test('revalida payload depois da leitura remota e antes do push', async t => {
  const root = await checkout(t)
  const mock = runner([29], { afterFirstHistory: () => writeFile(join(root, 'supabase', 'migrations', Object.keys(manifest.migrations).at(-1)), '-- alterado durante a consulta') })
  await assert.rejects(applyDocumentos({ root, env, run: mock.run, output: logger() }), /diverge/)
  assert.equal(mock.calls.length, 1)
})

test('normaliza somente CRLF para checkout Windows e confere arquivo de verificacao', async t => {
  const root = await checkout(t)
  for (const file of [...Object.keys(manifest.migrations).map(name => join(root, 'supabase', 'migrations', name)), join(root, manifest.verification_file)]) {
    const text = await readFile(file, 'utf8')
    await writeFile(file, text.replaceAll('\n', '\r\n'))
  }
  await validatePayload(root)
  await writeFile(join(root, manifest.verification_file), 'select true;')
  await assert.rejects(validatePayload(root), /diverge/)
})

test('historico inesperado/duplicado/adulterado e resultado vazio falham fechado', () => {
  const bad = history(29)
  bad.migrations[3].remote = ''
  assert.throws(() => classifyHistory(bad))
  for (const value of [null, {}, { migrations: [] }, history(28)]) assert.throws(() => classifyHistory(value))
  const duplicate = history(29)
  duplicate.migrations[0] = duplicate.migrations[1]
  assert.throws(() => classifyHistory(duplicate))
  const foreign = history(29)
  foreign.migrations.push({ local: '', remote: '20990101000000' })
  assert.throws(() => classifyHistory(foreign))
  assert.throws(() => verifyMetadata([]))
  assert.throws(() => verifyMetadata([metadata()[0], metadata()[0]]))
})
