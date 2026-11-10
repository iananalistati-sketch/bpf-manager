import assert from 'node:assert/strict'
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { PassThrough } from 'node:stream'
import { test } from 'node:test'
import { buildCommands, officialProjectRef, preflight, readPassword, redact, runCommand } from './supabase-preflight.mjs'

const password = '  teste $&%"á🚀 senha  '
const silent = () => { let text = ''; return { write: chunk => { text += chunk }, value: () => text } }
const baseEnv = { npm_execpath: '/tmp/npm-cli.js' }
async function project(t, ref = officialProjectRef) {
  const root = await mkdtemp(join(tmpdir(), 'bpf preflight '))
  t.after(() => rm(root, { recursive: true, force: true }))
  await mkdir(join(root, 'supabase', '.temp'), { recursive: true })
  if (ref !== null) await writeFile(join(root, 'supabase', '.temp', 'project-ref'), ref)
  return root
}

for (const ref of [null, 'outro-projeto']) {
  test(`vinculo ${ref ?? 'ausente'} interrompe antes da senha e subprocessos`, async t => {
    const root = await project(t, ref)
    await assert.rejects(preflight({ root, env: baseEnv, prompt: () => assert.fail('prompt nao autorizado'), run: () => assert.fail('spawn nao autorizado'), output: silent() }))
  })
}

test('reusa senha intacta so no ambiente, fixa destino e apenas dois comandos', async t => {
  const root = await project(t)
  const calls = []
  const output = silent()
  const env = { ...baseEnv, SUPABASE_DB_PASSWORD: password, SUPABASE_PROJECT_ID: 'outro-projeto', SUPABASE_PROFILE: 'custom', SUPABASE_WORKDIR: '/outro', SUPABASE_DEBUG: 'true', SUPABASE_TELEMETRY_DEBUG: 'true' }
  const result = await preflight({ root, env, output, prompt: () => assert.fail('nao pedir senha existente'), run: async (args, options) => {
    calls.push({ args, env: { ...options.env }, root: options.root })
    return 0
  } })
  assert.equal(result, 0)
  assert.equal(calls.length, 2)
  assert.ok(calls[0].args.includes('migration'))
  assert.ok(calls[0].args.includes('list'))
  assert.ok(calls[1].args.includes('--dry-run'))
  assert.ok(calls[1].args.includes('--skip-vault'))
  for (const call of calls) {
    assert.equal(call.env.SUPABASE_DB_PASSWORD, password)
    assert.equal(call.env.SUPABASE_DEBUG, 'false')
    assert.equal(call.env.SUPABASE_TELEMETRY_DEBUG, 'false')
    assert.equal(call.root, root)
    assert.equal(call.args[call.args.indexOf('--project-ref') + 1], officialProjectRef)
    assert.equal(call.args[call.args.indexOf('--workdir') + 1], root)
    assert.equal(call.args[call.args.indexOf('--profile') + 1], 'supabase')
    assert.ok(call.args.includes('--package=supabase@2.121.0'))
    assert.ok(call.args.includes('--linked'))
    assert.ok(!call.args.includes('--password') && !call.args.includes('--db-url') && !call.args.includes('--debug'))
    assert.ok(!call.args.join(' ').includes(password))
  }
  assert.ok(!output.value().includes(password))
  assert.equal(env.SUPABASE_DB_PASSWORD, password, 'nao apagar vinculacao do processo pai')
})

for (const codes of [[7], [130], [0, 5]]) {
  test(`propaga falha ${codes.join('/')} e para na etapa correspondente`, async t => {
    const root = await project(t)
    let calls = 0
    assert.equal(await preflight({ root, env: { ...baseEnv, SUPABASE_DB_PASSWORD: password }, output: silent(), run: async () => codes[calls++] }), codes.at(-1))
    assert.equal(calls, codes.length)
  })
}

test('prompt vazio ou cancelado impede subprocessos', async t => {
  const root = await project(t)
  for (const prompt of [async () => '', async () => { throw Object.assign(new Error('cancelado'), { exitCode: 130 }) }]) {
    await assert.rejects(preflight({ root, env: baseEnv, output: silent(), prompt, run: () => assert.fail('nao conectar') }))
  }
})

test('caminhos Windows com espacos sao argumentos separados para Node, sem shell', () => {
  const root = 'C:\\Users\\Usuario Teste\\bpf-manager'
  const npmCli = 'C:\\Program Files\\nodejs\\node_modules\\npm\\bin\\npm-cli.js'
  const commands = buildCommands(root, { npm_execpath: npmCli })
  assert.equal(commands[0].args[0], npmCli)
  assert.equal(commands[0].args.at(-1), root)
  assert.throws(() => buildCommands(root, {}), /pelo npm/)
})

test('prompt exige TTY', async () => {
  await assert.rejects(readPassword({ isTTY: false }, silent()), /terminal interativo/)
})

function terminal() {
  const input = new PassThrough()
  input.isTTY = true
  input.isRaw = false
  input.setRawMode = value => { input.isRaw = value }
  input.pause()
  const output = { ...silent(), isTTY: true }
  return { input, output }
}

test('prompt oculto preserva espacos/especiais e restaura terminal', async () => {
  const { input, output } = terminal()
  const pending = readPassword(input, output)
  input.write(`${password}\r`)
  assert.equal(await pending, password)
  assert.equal(input.isRaw, false)
  assert.equal(input.isPaused(), true)
  assert.ok(!output.value().includes(password))
})

for (const event of ['ctrl-c', 'eof', 'error']) {
  test(`${event} restaura terminal e cancela prompt`, async () => {
    const { input, output } = terminal()
    const pending = readPassword(input, output)
    input.write('segredo')
    if (event === 'ctrl-c') input.write('\x03')
    else if (event === 'eof') input.emit('end')
    else input.emit('error', new Error('erro de terminal'))
    await assert.rejects(pending)
    assert.equal(input.isRaw, false)
    assert.equal(input.isPaused(), true)
    assert.ok(!output.value().includes('segredo'))
  })
}

test('subprocesso real recebe segredo por env e saidas fragmentadas sao expurgadas', async t => {
  const root = await project(t)
  const file = join(root, 'fake-cli.mjs')
  await writeFile(file, `const p=process.env.SUPABASE_DB_PASSWORD; process.stdout.write(p.slice(0,3)); setTimeout(()=>{process.stdout.write(p.slice(3));process.stderr.write(encodeURIComponent(p));process.exitCode=9},5)`)
  const output = silent()
  const errorOutput = silent()
  const code = await runCommand([file], { root, env: { ...process.env, SUPABASE_DB_PASSWORD: password }, password, output, errorOutput })
  assert.equal(code, 9)
  assert.equal(output.value(), '[REDACTED]')
  assert.equal(errorOutput.value(), '[REDACTED]')
  assert.equal(redact(`antes ${password} depois`, password), 'antes [REDACTED] depois')
})


test('overflow descarta todos os buffers para nao expor fragmentos de segredo', async t => {
  const root = await project(t)
  const file = join(root, 'overflow-cli.mjs')
  await writeFile(file, `process.stdout.write('x'.repeat(2097150));process.stdout.write(process.env.SUPABASE_DB_PASSWORD);`)
  const output = silent()
  const errorOutput = silent()
  await assert.rejects(runCommand([file], { root, env: { ...process.env, SUPABASE_DB_PASSWORD: password }, password, output, errorOutput }), /excedeu o limite/)
  assert.equal(output.value(), '')
  assert.equal(errorOutput.value(), '')
})


test('TTY inicialmente sem fluxo volta a pausar para permitir o processo encerrar', async () => {
  const input = new PassThrough()
  input.isTTY = true
  input.isRaw = false
  input.setRawMode = value => { input.isRaw = value }
  const output = { ...silent(), isTTY: true }
  assert.equal(input.readableFlowing, null)
  const pending = readPassword(input, output)
  input.write('senha-ficticia\r')
  assert.equal(await pending, 'senha-ficticia')
  assert.equal(input.isRaw, false)
  assert.equal(input.isPaused(), true)
})


test('parser interno usa JSON bruto sem expor senha coincidente com metadados', async t => {
  const root = await project(t)
  const file = join(root, 'json-cli.mjs')
  await writeFile(file, `process.stdout.write(JSON.stringify({version:'2026'}))`)
  const output = silent()
  const result = await runCommand([file], { root, env: process.env, password: '2026', output, errorOutput: silent(), quiet: true, parseOutput: JSON.parse })
  assert.deepEqual(result, { code: 0, data: { version: '2026' } })
  assert.equal(output.value(), '')
})

test('JSON invalido nao ecoa o conteudo bruto na excecao', async t => {
  const root = await project(t)
  const file = join(root, 'invalid-json-cli.mjs')
  await writeFile(file, `process.stdout.write(process.env.SUPABASE_DB_PASSWORD)`)
  const output = silent()
  await assert.rejects(runCommand([file], { root, env: { ...process.env, SUPABASE_DB_PASSWORD: password }, password, output, errorOutput: silent(), quiet: true, parseOutput: JSON.parse }), error => {
    assert.ok(!error.message.includes(password))
    return /estruturada/.test(error.message)
  })
  assert.equal(output.value(), '')
})
