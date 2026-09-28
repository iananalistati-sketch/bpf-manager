import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'jsr:@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const json = (status: number, requestId: string, body: Record<string, unknown>) => new Response(JSON.stringify({ ...body, requestId }), {
  status,
  headers: { ...cors, 'Content-Type': 'application/json', 'X-Request-Id': requestId },
})

const logFailure = (requestId: string, stage: string, error: unknown, details: Record<string, unknown> = {}) => {
  const message = error instanceof Error ? error.message : typeof error === 'string' ? error : JSON.stringify(error)
  console.error(JSON.stringify({ requestId, stage, message, ...details }))
}

function resolveInviteRedirect(req: Request) {
  const configured = Deno.env.get('APP_URL')?.trim()
  const origin = req.headers.get('Origin')?.trim()

  if (configured) return `${configured.replace(/\/$/, '')}/redefinir-senha`
  if (!origin) return undefined

  try {
    const url = new URL(origin)
    const local = url.hostname === 'localhost' || url.hostname === '127.0.0.1'
    if (local && (url.protocol === 'http:' || url.protocol === 'https:')) {
      return `${url.origin}/redefinir-senha`
    }
  } catch {
    return undefined
  }

  return undefined
}

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID()

  if (req.method === 'OPTIONS') return new Response('ok', { headers: { ...cors, 'X-Request-Id': requestId } })
  if (req.method !== 'POST') return json(405, requestId, { error: 'Método não permitido.', code: 'INVITE_METHOD_NOT_ALLOWED' })

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const authorization = req.headers.get('Authorization')
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !authorization) {
    logFailure(requestId, 'bootstrap', 'Missing Supabase environment or authorization header')
    return json(401, requestId, { error: 'Sessão administrativa inválida.', code: 'INVITE_INVALID_SESSION' })
  }

  const caller = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  })
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  let body: {
    empresaId?: string
    email?: string
    nome?: string
    unidadeId?: string | null
    perfilIds?: string[]
    justificativa?: string
  }
  try { body = await req.json() } catch (error) {
    logFailure(requestId, 'payload_parse', error)
    return json(400, requestId, { error: 'Dados do convite inválidos.', code: 'INVITE_INVALID_PAYLOAD' })
  }

  const empresaId = body.empresaId?.trim() ?? ''
  const email = body.email?.trim().toLowerCase() ?? ''
  const nome = body.nome?.trim() ?? ''
  const justificativa = body.justificativa?.trim() ?? ''
  const perfilIds = Array.isArray(body.perfilIds) ? [...new Set(body.perfilIds)] : []
  if (!empresaId || !/^\S+@\S+\.\S+$/.test(email) || nome.length < 2 || justificativa.length < 5 || perfilIds.length === 0) {
    return json(400, requestId, { error: 'Preencha empresa, nome, e-mail, perfil e justificativa corretamente.', code: 'INVITE_INVALID_PAYLOAD' })
  }

  const { data: context, error: contextError } = await caller
    .rpc('meu_contexto_empresa', { p_empresa_id: empresaId })
    .maybeSingle()
  if (contextError || !context || !context.ativo || context.status !== 'ativo' || context.empresa_id !== empresaId) {
    logFailure(requestId, 'tenant_context', contextError ?? 'Context unavailable', { empresaId })
    return json(403, requestId, { error: 'A empresa selecionada não está disponível para sua sessão.', code: 'INVITE_TENANT_NOT_ALLOWED' })
  }

  const permissions = new Set<string>(context.permissoes ?? [])
  if (!permissions.has('configuracoes.visualizar') || !permissions.has('usuarios.gerenciar') || !permissions.has('usuarios.convidar')) {
    logFailure(requestId, 'permission_check', 'Required permission missing', { empresaId, actorId: context.usuario_id })
    return json(403, requestId, { error: 'Você não possui permissão para convidar usuários nesta empresa.', code: 'INVITE_PERMISSION_DENIED' })
  }

  const redirectTo = resolveInviteRedirect(req)
  const inviteOptions = redirectTo
    ? { data: { nome }, redirectTo }
    : { data: { nome } }

  const { data: invited, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, inviteOptions)
  if (inviteError || !invited.user) {
    logFailure(requestId, 'auth_invite', inviteError ?? 'Auth returned no user', { empresaId, email })
    const lower = inviteError?.message?.toLowerCase() ?? ''
    const alreadyExists = lower.includes('already') || lower.includes('registered') || lower.includes('exists')
    return json(409, requestId, {
      error: alreadyExists ? 'Este e-mail já possui cadastro no ambiente.' : 'Não foi possível gerar o convite de acesso no Supabase Auth.',
      code: alreadyExists ? 'INVITE_USER_ALREADY_EXISTS' : 'INVITE_AUTH_CREATE_FAILED',
    })
  }

  const targetId = invited.user.id
  const { error: linkError } = await admin.rpc('admin_usuario_vincular_convite_server', {
    p_ator_id: context.usuario_id,
    p_empresa_id: empresaId,
    p_usuario_id: targetId,
    p_unidade_id: body.unidadeId || null,
    p_perfil_ids: perfilIds,
    p_justificativa: justificativa,
  })
  if (linkError) {
    logFailure(requestId, 'tenant_link', linkError, { empresaId, actorId: context.usuario_id, targetId })
    const { error: cleanupError } = await admin.auth.admin.deleteUser(targetId)
    if (cleanupError) logFailure(requestId, 'auth_cleanup', cleanupError, { targetId })

    const lower = linkError.message.toLowerCase()
    const message = lower.includes('limite de usuarios ativos')
      ? 'O limite de usuários ativos do plano foi atingido.'
      : lower.includes('perfil')
        ? 'O perfil selecionado não pode ser delegado neste tenant.'
        : lower.includes('unidade')
          ? 'A unidade selecionada não é válida para esta empresa.'
          : lower.includes('membership') || lower.includes('permissao')
            ? 'Sua permissão para convidar usuários nesta empresa não está mais disponível.'
            : 'O convite foi criado no Auth, mas o vínculo empresarial falhou e foi revertido.'
    return json(400, requestId, { error: message, code: 'INVITE_TENANT_LINK_FAILED' })
  }

  console.log(JSON.stringify({ requestId, stage: 'completed', empresaId, actorId: context.usuario_id, targetId }))
  return json(200, requestId, { userId: targetId, email, empresaId, redirectTo: redirectTo ?? null })
})
