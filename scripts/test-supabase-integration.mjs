import { readFile } from 'node:fs/promises'
import { createClient } from '@supabase/supabase-js'

async function loadLocalEnv() {
  try {
    const text = await readFile(new URL('../.env.integration.local', import.meta.url), 'utf8')
    for (const source of text.split(/\r?\n/)) {
      const line = source.trim()
      if (!line || line.startsWith('#')) continue
      const match = line.match(/^([A-Z0-9_]+)=(.*)$/)
      if (!match || process.env[match[1]]) continue
      let value = match[2].trim()
      if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) value = value.slice(1, -1)
      process.env[match[1]] = value
    }
  } catch (error) {
    if (error.code !== 'ENOENT') throw error
  }
}

await loadLocalEnv()

const env = (name, required = true) => {
  const value = process.env[name]?.trim()
  if (required && !value) throw new Error(`Missing ${name}. Configure .env.integration.local.`)
  return value ?? ''
}

const url = env('BPF_INTEGRATION_SUPABASE_URL')
const publishableKey = env('BPF_INTEGRATION_PUBLISHABLE_KEY')
const adminEmail = env('BPF_INTEGRATION_ADMIN_EMAIL')
const adminPassword = env('BPF_INTEGRATION_ADMIN_PASSWORD')
const environment = env('BPF_INTEGRATION_ENVIRONMENT')
const allowProduction = env('BPF_INTEGRATION_ALLOW_PRODUCTION', false) === 'YES'
const allowMutations = env('BPF_INTEGRATION_ALLOW_MUTATIONS', false) === 'YES'
const serviceRoleKey = env('BPF_INTEGRATION_SERVICE_ROLE_KEY', false)
const inviteEmail = env('BPF_INTEGRATION_INVITE_EMAIL', false)
const explicitProfileId = env('BPF_INTEGRATION_PROFILE_ID', false)
const productionMutationConfirmation = env('BPF_INTEGRATION_PRODUCTION_MUTATION_CONFIRM', false)

if (!['homologation', 'official'].includes(environment)) {
  throw new Error('BPF_INTEGRATION_ENVIRONMENT must be homologation or official.')
}

const projectRef = new URL(url).hostname.split('.')[0]
const officialRef = 'yequhfvcbwnxmqobgumu'
const isOfficial = projectRef === officialRef

if (isOfficial && (!allowProduction || environment !== 'official')) {
  throw new Error('Official project requires BPF_INTEGRATION_ENVIRONMENT=official and BPF_INTEGRATION_ALLOW_PRODUCTION=YES.')
}
if (!isOfficial && environment === 'official') {
  throw new Error('BPF_INTEGRATION_ENVIRONMENT=official is allowed only for the configured official project ref.')
}
if (isOfficial && allowMutations && productionMutationConfirmation !== officialRef) {
  throw new Error(`Mutation smoke on the official project requires BPF_INTEGRATION_PRODUCTION_MUTATION_CONFIRM=${officialRef}.`)
}

const client = createClient(url, publishableKey, { auth: { persistSession: false, autoRefreshToken: false } })

const fail = (message, error) => {
  const detail = error?.message ? `: ${error.message}` : ''
  throw new Error(`${message}${detail}`)
}

console.log(`Hosted Supabase integration: ${projectRef} (${environment})`)
console.log(isOfficial
  ? `MODE: official ${allowMutations ? 'controlled-mutation smoke' : 'read-only smoke'}`
  : `MODE: homologation ${allowMutations ? 'mutation smoke' : 'read-only smoke'}`)

const { data: login, error: loginError } = await client.auth.signInWithPassword({ email: adminEmail, password: adminPassword })
if (loginError || !login.session) fail('Admin login failed', loginError)
console.log('PASS: hosted Auth login')

try {
  const { data: vinculos, error: vinculosError } = await client.rpc('meus_vinculos')
  if (vinculosError) fail('meus_vinculos failed', vinculosError)
  if (!Array.isArray(vinculos) || vinculos.length === 0) fail('Admin has no active hosted membership')
  console.log(`PASS: meus_vinculos returned ${vinculos.length} active membership(s)`)

  const tenant = vinculos[0]
  const empresaId = tenant.empresa_id

  const { data: contexto, error: contextoError } = await client.rpc('meu_contexto_empresa', { p_empresa_id: empresaId }).maybeSingle()
  if (contextoError || !contexto) fail('meu_contexto_empresa failed', contextoError)
  if (contexto.empresa_id !== empresaId || contexto.status !== 'ativo') fail('Hosted tenant context is inconsistent')
  console.log('PASS: hosted JWT subject + tenant context')

  const { data: resumo, error: resumoError } = await client.rpc('meu_plano_resumo', { p_empresa_id: empresaId }).maybeSingle()
  if (resumoError || !resumo) fail('meu_plano_resumo failed', resumoError)
  if (typeof resumo.usuarios_ativos !== 'number' && typeof resumo.usuarios_ativos !== 'string') fail('Plan summary did not return usage')
  console.log('PASS: hosted plan summary')

  const { data: entitlements, error: entitlementsError } = await client.rpc('meu_plano_entitlements', { p_empresa_id: empresaId })
  if (entitlementsError) fail('meu_plano_entitlements failed', entitlementsError)
  if (!Array.isArray(entitlements)) fail('Plan entitlements did not return an array')
  console.log('PASS: hosted plan entitlements')

  if (!allowMutations) {
    console.log(`SKIP: mutation smoke disabled (${isOfficial ? 'recommended default on official project' : 'set BPF_INTEGRATION_ALLOW_MUTATIONS=YES when needed'})`)
  } else {
    if (!serviceRoleKey) fail('Mutation smoke requires BPF_INTEGRATION_SERVICE_ROLE_KEY')
    if (!inviteEmail) fail('Mutation smoke requires BPF_INTEGRATION_INVITE_EMAIL')
    if (inviteEmail.toLowerCase() === adminEmail.toLowerCase()) fail('Invite smoke email must differ from admin email')

    const admin = createClient(url, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } })

    let profileId = explicitProfileId
    if (!profileId) {
      const { data: profiles, error: profileError } = await admin
        .from('perfis')
        .select('id,nome,empresa_id,is_system,ativo')
        .eq('ativo', true)
        .order('nome')
      if (profileError) fail('Could not discover a smoke profile', profileError)
      const preferred = profiles?.find(profile => profile.nome === 'Consulta' && (profile.is_system || profile.empresa_id === empresaId))
        ?? profiles?.find(profile => profile.is_system || profile.empresa_id === empresaId)
      profileId = preferred?.id ?? ''
    }
    if (!profileId) fail('No valid profile available for invitation smoke')

    const { data: invokeData, error: invokeError } = await client.functions.invoke('admin-invite-user', {
      body: {
        empresaId,
        email: inviteEmail,
        nome: isOfficial ? 'Smoke Test Oficial' : 'Smoke Test Homologacao',
        unidadeId: contexto.unidade_id ?? null,
        perfilIds: [profileId],
        justificativa: `Smoke integration ${environment} ${new Date().toISOString()}`,
      },
    })
    if (invokeError) fail('admin-invite-user Edge Function failed', invokeError)
    const userId = invokeData?.userId
    if (!userId) fail('Edge Function did not return invited userId')

    try {
      const { data: authUser, error: authUserError } = await admin.auth.admin.getUserById(userId)
      if (authUserError || !authUser.user) fail('Invited Auth user was not persisted', authUserError)

      const { data: membership, error: membershipError } = await admin
        .from('usuario_empresas').select('id,usuario_id,empresa_id,status')
        .eq('usuario_id', userId).eq('empresa_id', empresaId).maybeSingle()
      if (membershipError || !membership || membership.status !== 'ativo') fail('Invited membership was not persisted', membershipError)

      const { data: profileLink, error: profileLinkError } = await admin
        .from('usuario_empresa_perfis').select('usuario_empresa_id,perfil_id')
        .eq('usuario_empresa_id', membership.id).eq('perfil_id', profileId).maybeSingle()
      if (profileLinkError || !profileLink) fail('Invited membership profile was not persisted', profileLinkError)

      const { data: audit, error: auditError } = await admin
        .from('auditoria_eventos').select('id,acao,registro_id,empresa_id')
        .eq('registro_id', userId).eq('empresa_id', empresaId)
        .eq('acao', 'usuario.convidado_vinculado').maybeSingle()
      if (auditError || !audit) fail('Invitation audit was not persisted', auditError)

      console.log('PASS: Edge invite -> Auth -> membership -> profile -> audit')
    } finally {
      const { error: cleanupError } = await admin.auth.admin.deleteUser(userId)
      if (cleanupError) console.warn(`WARN: integration cleanup failed for ${userId}: ${cleanupError.message}`)
      else console.log('PASS: invitation smoke cleanup')
    }
  }

  console.log('PASS: hosted Supabase integration gate')
} finally {
  await client.auth.signOut()
}
