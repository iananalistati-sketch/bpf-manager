import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'jsr:@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const json = (status: number, requestId: string, body: Record<string, unknown>) => new Response(
  JSON.stringify({ ...body, requestId }),
  { status, headers: { ...cors, 'Content-Type': 'application/json', 'X-Request-Id': requestId } },
)

const logFailure = (requestId: string, stage: string, error: unknown, details: Record<string, unknown> = {}) => {
  const message = error instanceof Error ? error.message : typeof error === 'string' ? error : JSON.stringify(error)
  console.error(JSON.stringify({ requestId, stage, message, ...details }))
}

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID()

  if (req.method === 'OPTIONS') return new Response('ok', { headers: { ...cors, 'X-Request-Id': requestId } })
  if (req.method !== 'POST') return json(405, requestId, { error: 'Método não permitido.', code: 'TRIAL_METHOD_NOT_ALLOWED' })

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const authorization = req.headers.get('Authorization')

  if (!supabaseUrl || !anonKey || !serviceRoleKey || !authorization) {
    logFailure(requestId, 'bootstrap', 'Missing Supabase environment or authorization header')
    return json(401, requestId, { error: 'Sessão inválida.', code: 'TRIAL_INVALID_SESSION' })
  }

  const caller = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { data: userData, error: userError } = await caller.auth.getUser()
  const user = userData.user
  if (userError || !user) {
    logFailure(requestId, 'identity', userError ?? 'Authenticated user unavailable')
    return json(401, requestId, { error: 'Não foi possível validar sua identidade.', code: 'TRIAL_INVALID_SESSION' })
  }

  let body: { razaoSocial?: string; nomeFantasia?: string; unidadeNome?: string }
  try {
    body = await req.json()
  } catch (error) {
    logFailure(requestId, 'payload_parse', error, { userId: user.id })
    return json(400, requestId, { error: 'Dados do trial inválidos.', code: 'TRIAL_INVALID_PAYLOAD' })
  }

  const razaoSocial = body.razaoSocial?.trim() ?? ''
  const nomeFantasia = body.nomeFantasia?.trim() ?? ''
  const unidadeNome = body.unidadeNome?.trim() ?? ''

  if (razaoSocial.length < 2 || nomeFantasia.length < 2 || unidadeNome.length < 2) {
    return json(400, requestId, {
      error: 'Preencha razão social, nome da empresa e unidade principal.',
      code: 'TRIAL_INVALID_PAYLOAD',
    })
  }

  const idempotencyKey = `trial:self-service:${user.id}`
  const { data, error } = await admin.rpc('provisionar_trial_server', {
    p_usuario_id: user.id,
    p_razao_social: razaoSocial,
    p_nome_fantasia: nomeFantasia,
    p_unidade_nome: unidadeNome,
    p_chave_idempotencia: idempotencyKey,
  })

  if (error) {
    logFailure(requestId, 'provisioning', error, { userId: user.id })
    const lower = error.message.toLowerCase()
    const message = lower.includes('ja possui vinculo empresarial')
      ? 'Sua conta já possui uma empresa vinculada. Atualize a página para continuar.'
      : lower.includes('plano inicial')
        ? 'O plano inicial do trial está temporariamente indisponível.'
        : lower.includes('perfil administrador')
          ? 'A configuração administrativa do trial está indisponível.'
          : 'Não foi possível preparar seu ambiente de teste agora.'

    return json(400, requestId, { error: message, code: 'TRIAL_PROVISIONING_FAILED' })
  }

  const result = Array.isArray(data) ? data[0] : data
  if (!result?.empresa_id || !result?.membership_id) {
    logFailure(requestId, 'provisioning_result', 'Provisioning returned no workspace', { userId: user.id })
    return json(500, requestId, { error: 'O ambiente foi processado, mas o retorno ficou incompleto.', code: 'TRIAL_INVALID_RESULT' })
  }

  console.log(JSON.stringify({ requestId, stage: 'completed', userId: user.id, empresaId: result.empresa_id }))
  return json(200, requestId, {
    empresaId: result.empresa_id,
    unidadeId: result.unidade_id,
    membershipId: result.membership_id,
    assinaturaId: result.assinatura_id,
    trialFim: result.trial_fim,
  })
})
