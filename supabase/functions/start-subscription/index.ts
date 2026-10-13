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
  if (req.method !== 'POST') {
    return json(405, requestId, { error: 'Método não permitido.', code: 'SUBSCRIPTION_METHOD_NOT_ALLOWED' })
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const authorization = req.headers.get('Authorization')

  if (!supabaseUrl || !anonKey || !serviceRoleKey || !authorization) {
    logFailure(requestId, 'bootstrap', 'Missing Supabase environment or authorization header')
    return json(401, requestId, { error: 'Sessão inválida.', code: 'SUBSCRIPTION_INVALID_SESSION' })
  }

  const caller = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const accessToken = authorization.replace(/^Bearer\s+/i, '').trim()
  const { data: userData, error: userError } = await caller.auth.getUser(accessToken)
  const user = userData.user
  if (userError || !user) {
    logFailure(requestId, 'identity', userError ?? 'Authenticated user unavailable')
    return json(401, requestId, { error: 'Não foi possível validar sua identidade.', code: 'SUBSCRIPTION_INVALID_SESSION' })
  }

  let body: { empresaId?: string; planoCodigo?: string; idempotencyKey?: string }
  try {
    body = await req.json()
  } catch (error) {
    logFailure(requestId, 'payload_parse', error, { userId: user.id })
    return json(400, requestId, { error: 'Dados da contratação inválidos.', code: 'SUBSCRIPTION_INVALID_PAYLOAD' })
  }

  const empresaId = body.empresaId?.trim() ?? ''
  const planoCodigo = body.planoCodigo?.trim().toLowerCase() ?? ''
  const idempotencyKey = body.idempotencyKey?.trim() ?? ''

  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(empresaId)
    || planoCodigo.length < 1 || planoCodigo.length > 120
    || !/^[a-z0-9][a-z0-9._-]*$/.test(planoCodigo)
    || idempotencyKey.length < 12 || idempotencyKey.length > 200
  ) {
    return json(400, requestId, {
      error: 'Empresa, plano ou chave de idempotência inválidos.',
      code: 'SUBSCRIPTION_INVALID_PAYLOAD',
    })
  }

  const { data: context, error: contextError } = await caller
    .rpc('meu_contexto_empresa', { p_empresa_id: empresaId })
    .maybeSingle()

  if (contextError || !context || context.empresa_id !== empresaId || context.status !== 'ativo' || !context.ativo) {
    logFailure(requestId, 'tenant_context', contextError ?? 'Context unavailable', { empresaId, userId: user.id })
    return json(403, requestId, {
      error: 'A empresa selecionada não está disponível para sua sessão.',
      code: 'SUBSCRIPTION_TENANT_NOT_ALLOWED',
    })
  }

  if (!context.is_owner) {
    return json(403, requestId, {
      error: 'Somente o responsável principal da empresa pode iniciar uma contratação.',
      code: 'SUBSCRIPTION_OWNER_REQUIRED',
    })
  }

  const { data, error } = await admin.rpc('preparar_contratacao_server', {
    p_ator_id: context.usuario_id,
    p_empresa_id: empresaId,
    p_plano_codigo: planoCodigo,
    p_chave_idempotencia: idempotencyKey,
  })

  if (error) {
    logFailure(requestId, 'prepare_checkout', error, { empresaId, actorId: context.usuario_id, planoCodigo })
    const lower = error.message.toLowerCase()
    const message = lower.includes('ja possui este plano ativo')
      ? 'Este workspace já utiliza o plano selecionado.'
      : lower.includes('nao comporta as unidades')
        ? 'O plano selecionado não comporta a quantidade atual de unidades ativas.'
        : lower.includes('nao comporta os usuarios')
          ? 'O plano selecionado não comporta a quantidade atual de usuários ativos.'
          : lower.includes('plano comercial')
            ? 'O plano selecionado não está disponível.'
            : 'Não foi possível preparar a contratação agora.'

    return json(400, requestId, { error: message, code: 'SUBSCRIPTION_PREPARE_FAILED' })
  }

  const result = Array.isArray(data) ? data[0] : data
  if (!result?.contratacao_id || !result?.assinatura_id) {
    logFailure(requestId, 'prepare_result', 'Preparation returned incomplete result', { empresaId, actorId: context.usuario_id })
    return json(500, requestId, {
      error: 'A contratação foi processada, mas o retorno ficou incompleto.',
      code: 'SUBSCRIPTION_INVALID_RESULT',
    })
  }

  if (result.status === 'expirada') {
    return json(409, requestId, {
      error: 'Esta tentativa de contratação expirou. Inicie uma nova tentativa.',
      code: 'SUBSCRIPTION_INTENT_EXPIRED',
      contratacaoId: result.contratacao_id,
    })
  }

  console.log(JSON.stringify({
    requestId,
    stage: 'prepared',
    empresaId,
    actorId: context.usuario_id,
    contratacaoId: result.contratacao_id,
    planoCodigo: result.plano_codigo,
  }))

  return json(202, requestId, {
    contratacaoId: result.contratacao_id,
    assinaturaId: result.assinatura_id,
    empresaId: result.empresa_id,
    planoId: result.plano_id,
    planoCodigo: result.plano_codigo,
    status: result.status,
    expiresAt: result.expires_at,
    checkoutUrl: null,
    requiresProviderAdapter: true,
  })
})
