import { spawn } from 'node:child_process'
import { readFile } from 'node:fs/promises'
import { isAbsolute, join, win32 } from 'node:path'
import { emitKeypressEvents } from 'node:readline'
import { fileURLToPath, pathToFileURL } from 'node:url'

export const officialProjectRef = 'yequhfvcbwnxmqobgumu'
export const cliVersion = '2.121.0'
export const repositoryRoot = fileURLToPath(new URL('..', import.meta.url))

export function readPassword(input = process.stdin, output = process.stdout) {
  if (!input.isTTY || !output.isTTY || typeof input.setRawMode !== 'function') {
    return Promise.reject(new Error('Use um terminal interativo para informar a senha oculta ou uma vinculacao segura de SUPABASE_DB_PASSWORD.'))
  }
  return new Promise((resolve, reject) => {
    let password = ''
    const previousRaw = Boolean(input.isRaw)
    const previousFlowing = input.readableFlowing === true
    const cleanup = () => {
      input.off('keypress', onKey)
      input.off('end', onEnd)
      input.off('error', onError)
      input.setRawMode(previousRaw)
      if (!previousFlowing) input.pause()
      output.write('\n')
    }
    const finish = error => {
      cleanup()
      if (error) { password = ''; reject(error) }
      else { const value = password; password = ''; resolve(value) }
    }
    const cancelled = () => Object.assign(new Error('Operacao cancelada antes de conectar.'), { exitCode: 130 })
    const onEnd = () => finish(cancelled())
    const onError = () => finish(new Error('Nao foi possivel ler a senha no terminal.'))
    const onKey = (text, key = {}) => {
      if ((key.ctrl && ['c', 'd'].includes(key.name)) || key.name === 'escape') return finish(cancelled())
      if (key.name === 'return' || key.name === 'enter') return finish(password.length ? null : new Error('Senha vazia. Nenhuma conexao foi iniciada.'))
      if (key.name === 'backspace') { password = Array.from(password).slice(0, -1).join(''); return }
      if (key.ctrl && key.name === 'u') { password = ''; return }
      if (key.ctrl || key.meta || !text || /[\x00-\x1f\x7f]/.test(text)) return
      password += text
    }
    emitKeypressEvents(input)
    input.setRawMode(true)
    input.on('keypress', onKey)
    input.once('end', onEnd)
    input.once('error', onError)
    input.resume()
    output.write('Senha do PostgreSQL do projeto oficial (entrada oculta; nao e a senha do usuario da aplicacao): ')
  })
}

export function redact(text, password) {
  const patterns = [...new Set([password, encodeURIComponent(password)])].filter(Boolean).sort((a, b) => b.length - a.length)
  return patterns.reduce((value, secret) => value.replaceAll(secret, '[REDACTED]'), String(text))
}

export function buildCliArgs(root, env, command) {
  const npmCli = env.npm_execpath
  if (!npmCli || (!isAbsolute(npmCli) && !win32.isAbsolute(npmCli)) || !/\.m?js$/i.test(npmCli)) {
    throw new Error('Execute este comando pelo npm, usando o script publicado no repositorio.')
  }
  const target = ['--linked', '--project-ref', officialProjectRef, '--profile', 'supabase', '--workdir', root]
  return [npmCli, 'exec', '--yes', `--package=supabase@${cliVersion}`, '--', 'supabase', ...command, ...target]
}

export function buildCommands(root, env) {
  return [
    { name: 'Historico remoto de migrations', args: buildCliArgs(root, env, ['migration', 'list']) },
    { name: 'Simulacao de aplicacao (sem aplicar migrations)', args: buildCliArgs(root, env, ['db', 'push', '--dry-run', '--skip-vault']) },
  ]
}

// Buffer CLI output until completion so a credential split across chunks is redacted too.
export function runCommand(args, { root, env, password, output = process.stdout, errorOutput = process.stderr, spawnProcess = spawn, parseOutput, quiet = false }) {
  return new Promise((resolve, reject) => {
    const child = spawnProcess(process.execPath, args, { cwd: root, env, shell: false, stdio: ['ignore', 'pipe', 'pipe'] })
    const stdout = []
    const stderr = []
    let size = 0
    let overflow = false
    const collect = target => chunk => {
      size += chunk.length
      if (size > 2 * 1024 * 1024) { overflow = true; child.kill(); return }
      target.push(Buffer.from(chunk))
    }
    child.stdout.on('data', collect(stdout))
    child.stderr.on('data', collect(stderr))
    child.once('error', () => reject(new Error('Nao foi possivel iniciar o Supabase CLI pelo npm.')))
    child.once('close', (code, signal) => {
      if (overflow) return reject(new Error('Saida do CLI excedeu o limite; operacao interrompida.'))
      const status = signal ? 130 : code ?? 1
      const text = Buffer.concat(stdout).toString('utf8')
      if (!quiet || status !== 0) output.write(redact(text, password))
      errorOutput.write(redact(Buffer.concat(stderr).toString('utf8'), password))
      if (!parseOutput) return resolve(status)
      if (status !== 0) return resolve({ code: status, data: null })
      try { resolve({ code: status, data: parseOutput(text) }) }
      catch { reject(new Error('Resposta estruturada do CLI invalida; operacao interrompida.')) }
    })
  })
}

export async function withDatabasePassword({ root = repositoryRoot, env = process.env, prompt = readPassword, output = process.stdout, action }) {
  let linkedRef
  try { linkedRef = (await readFile(join(root, 'supabase', '.temp', 'project-ref'), 'utf8')).trim() }
  catch { throw new Error('Vinculo Supabase indisponivel. Este comando exige o projeto oficial ja vinculado neste checkout.') }
  if (linkedRef !== officialProjectRef) throw new Error('O checkout nao esta vinculado ao projeto oficial esperado. Nenhuma credencial foi solicitada ou enviada.')
  buildCliArgs(root, env, ['migration', 'list'])
  let password = env.SUPABASE_DB_PASSWORD || await prompt()
  if (!password.length) throw new Error('Senha vazia. Nenhuma conexao foi iniciada.')
  const childEnv = { ...env, SUPABASE_DB_PASSWORD: password, SUPABASE_PROJECT_ID: officialProjectRef, SUPABASE_WORKDIR: root, SUPABASE_PROFILE: 'supabase', SUPABASE_DEBUG: 'false', SUPABASE_TELEMETRY_DEBUG: 'false' }
  try { return await action({ root, env: childEnv, password, output }) }
  finally { delete childEnv.SUPABASE_DB_PASSWORD; password = '' }
}

export async function preflight({ root = repositoryRoot, env = process.env, prompt = readPassword, run = runCommand, output = process.stdout } = {}) {
  return withDatabasePassword({ root, env, prompt, output, action: async context => {
    output.write(`Preflight do projeto ${officialProjectRef}; CLI ${cliVersion}. Apenas listagem e dry-run.\n`)
    for (const command of buildCommands(root, env)) {
      output.write(`\n${command.name}...\n`)
      const code = await run(command.args, context)
      if (code !== 0) {
        output.write('Etapa interrompida. A senha substitui o login temporario, mas nao restaura um banco indisponivel.\n')
        return code
      }
    }
    output.write('\nPreflight concluido. O dry-run nao executou migrations nem comprovou suas precondicoes SQL.\n')
    return 0
  } })
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    if (process.argv.length > 2) throw new Error('Este comando nao aceita argumentos: executa somente listagem e dry-run fixos.')
    process.exitCode = await preflight()
  } catch (error) {
    console.error(error.message)
    process.exitCode = error.exitCode ?? 1
  }
}
