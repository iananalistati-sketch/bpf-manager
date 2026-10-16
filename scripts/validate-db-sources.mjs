import { readdir, readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = fileURLToPath(new URL('..', import.meta.url))
const testsDir = join(root, 'supabase', 'tests')
const migrationsDir = join(root, 'supabase', 'migrations')

const errors = []

const testEntries = await readdir(testsDir, { withFileTypes: true })
const sqlFiles = testEntries
  .filter(entry => entry.isFile() && entry.name.endsWith('.sql'))
  .map(entry => entry.name)
  .sort()

const migrationEntries = await readdir(migrationsDir, { withFileTypes: true })
const migrationFiles = migrationEntries
  .filter(entry => entry.isFile() && entry.name.endsWith('.sql'))
  .map(entry => entry.name)
  .sort()

if (!migrationFiles.length) errors.push('no migration files found')
for (const file of migrationFiles) {
  if (!/^\d{14}_[a-z0-9_]+\.sql$/.test(file)) {
    errors.push(`${file}: migration filename must use YYYYMMDDHHMMSS_snake_case.sql`)
  }
}
if (new Set(migrationFiles).size !== migrationFiles.length) errors.push('duplicated migration filename detected')

for (let index = 1; index < migrationFiles.length; index += 1) {
  if (migrationFiles[index - 1] >= migrationFiles[index]) {
    errors.push(`migration order is not strictly increasing near ${migrationFiles[index]}`)
  }
}

for (const file of sqlFiles) {
  const path = join(testsDir, file)
  const text = await readFile(path, 'utf8')
  const lines = text.split(/\r?\n/)
  let role = 'deployer'

  for (let index = 0; index < lines.length; index += 1) {
    const source = lines[index]
    const line = source.replace(/--.*$/, '').trim()
    if (!line) continue

    const setRole = line.match(/^SET(?:\s+LOCAL)?\s+ROLE\s+([A-Za-z0-9_"]+)\s*;?$/i)
    if (setRole) {
      role = setRole[1].replaceAll('"', '')
      continue
    }

    if (/^RESET\s+ROLE\s*;?$/i.test(line)) {
      role = 'deployer'
      continue
    }

    const createsTemp = /\bCREATE\s+(?:TEMP|TEMPORARY)\s+TABLE\b/i.test(line)
      || /\bINTO\s+(?:TEMP|TEMPORARY)\s+TABLE\b/i.test(line)

    if (role !== 'deployer' && createsTemp) {
      errors.push(`${file}:${index + 1}: temporary table created while SET ROLE ${role} is active`)
    }
  }

  const meaningful = lines
    .map(line => line.replace(/--.*$/, '').trim())
    .filter(Boolean)
  if (meaningful.at(-1)?.toUpperCase() !== 'ROLLBACK;') {
    errors.push(`${file}: test must end with ROLLBACK; to avoid leaking fixtures`)
  }
}

if (errors.length) {
  console.error('Database source validation failed:')
  for (const error of errors) console.error(`- ${error}`)
  process.exitCode = 1
} else {
  console.log(`PASS: database source preflight (${sqlFiles.length} SQL test files; ${migrationFiles.length} migrations auto-discovered)`)
}
