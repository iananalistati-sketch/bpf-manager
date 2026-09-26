import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'jsr:@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), {
  status,
  headers: { ...cors, 'Content-Type': 'application/json' },
})

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json(405, { error: 'Método não permitido.', code: 'method_not_allowed' })

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const authorization = req.headers.get('Authorization')
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !authorization) {
    return json(401, { error: 'Sessão administrativa inválida.', code: 'invalid_session' })
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
  try { body = await req.json() } catch {
    return json(400, { error: 'Dados do convite inválidos.', code: 'invalid_payload' })
  }

  const empresaId = body.empresaId?.trim() ?? ''
  const email = body.email?.trim().toLowerCase() ?? ''
  const nome = body.nome?.trim() ?? ''
  const justificativa = body.justificativa?.trim() ?? ''
  const perfilIds = Array.isArray(body.perfilIds) ? [...new Set(body.perfilIds)] : []
  if (!empresaId || !/^\S+@\S+\.\S+$/.test(email) || nome.length < 2 || justificativa.length < 5 || perfilIds.length === 0) {
    return json(400, { error: 'Preencha empresa, nome, e-mail, perfil e justificativa corretamente.', code: 'invalid_payload' })
  }

  const { data: context, error: contextError } = await caller
    .rpc('meu_contexto_empresa', { p_empresa_id: empresaId })
    .maybeSingle()
  if (contextError || !context || !context.ativo || context.status !== 'ativo' || context.empresa_id !== empresaId) {
    return json(403, { error: 'A empresa selecionada não está disponível para sua sessão.', code: 'tenant_not_allowed' })
  }

  const permissions = new Set<string>(context.permissoes ?? [])
  if (!permissions.has('configuracoes.visualizar') || !permissions.has('usuarios.gerenciar') || !permissions.has('usuarios.convidar')) {
    return json(403, { error: 'Você não possui permissão para convidar usuários nesta empresa.', code: 'permission_denied' })
  }

  const { data: invited, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, { data: { nome } })
  if (inviteError || !invited.user) {
    const lower = inviteError?.message?.toLowerCase() ?? ''
    const alreadyExists = lower.includes('already') || lower.includes('registered') || lower.includes('exists')
    return json(409, {
      error: alreadyExists ? 'Este e-mail já possui cadastro no ambiente.' : 'Não foi possível gerar o convite de acesso no Supabase Auth.',
      code: alreadyExists ? 'user_already_exists' : 'auth_invite_failed',
    })
  }

  const targetId = invited.user.id
  const { error: linkError } = await caller.rpc('admin_usuario_vincular_convite_tenant', {
    p_empresa_id: empresaId,
    p_usuario_id: targetId,
    p_unidade_id: body.unidadeId || null,
    p_perfil_ids: perfilIds,
    p_justificativa: justificativa,
  })
  if (linkError) {
    await admin.auth.admin.deleteUser(targetId)
    const lower = linkError.message.toLowerCase()
    const message = lower.includes('limite de usuarios ativos')
      ? 'O limite de usuários ativos do plano foi atingido.'
      : lower.includes('perfil')
        ? 'O perfil selecionado não pode ser delegado neste tenant.'
        : lower.includes('unidade')
          ? 'A unidade selecionada não é válida para esta empresa.'
          : 'O convite foi criado no Auth, mas o vínculo empresarial falhou. O usuário foi removido novamente.'
    return json(400, { error: message, code: 'tenant_link_failed' })
  }

  return json(200, { userId: targetId, email, empresaId })
})
