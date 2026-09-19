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
  if (req.method !== 'POST') return json(405, { error: 'Método não permitido.' })

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const authorization = req.headers.get('Authorization')
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !authorization) return json(401, { error: 'Sessão administrativa inválida.' })

  const caller = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } })
  const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } })

  const { data: context, error: contextError } = await caller.from('v_meu_contexto').select('usuario_id,empresa_id,ativo,status,permissoes').maybeSingle()
  if (contextError || !context || !context.ativo || context.status !== 'ativo' || !context.empresa_id) return json(403, { error: 'Seu acesso administrativo não está disponível.' })
  const permissions = new Set<string>(context.permissoes ?? [])
  if (!permissions.has('configuracoes.visualizar') || !permissions.has('usuarios.gerenciar') || !permissions.has('usuarios.convidar')) {
    return json(403, { error: 'Você não possui permissão para convidar usuários.' })
  }

  let body: { email?: string; nome?: string; unidadeId?: string | null; perfilIds?: string[]; justificativa?: string }
  try { body = await req.json() } catch { return json(400, { error: 'Dados do convite inválidos.' }) }
  const email = body.email?.trim().toLowerCase() ?? ''
  const nome = body.nome?.trim() ?? ''
  const justificativa = body.justificativa?.trim() ?? ''
  const perfilIds = Array.isArray(body.perfilIds) ? [...new Set(body.perfilIds)] : []
  if (!/^\S+@\S+\.\S+$/.test(email) || nome.length < 2 || justificativa.length < 5 || perfilIds.length === 0) {
    return json(400, { error: 'Preencha nome, e-mail, perfil e justificativa corretamente.' })
  }

  const { data: invited, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, { data: { nome } })
  if (inviteError || !invited.user) {
    const message = inviteError?.message?.toLowerCase().includes('already') || inviteError?.message?.toLowerCase().includes('registered')
      ? 'Este e-mail já possui cadastro no ambiente.'
      : 'Não foi possível gerar o convite de acesso.'
    return json(409, { error: message })
  }

  const targetId = invited.user.id
  const { error: linkError } = await caller.rpc('admin_usuario_vincular_convite', {
    p_usuario_id: targetId,
    p_unidade_id: body.unidadeId || null,
    p_perfil_ids: perfilIds,
    p_justificativa: justificativa,
  })
  if (linkError) {
    // Auth and PostgreSQL cannot share one transaction. Best-effort compensation keeps a failed
    // authorization step from leaving an unlinked invited identity behind.
    await admin.auth.admin.deleteUser(targetId)
    return json(400, { error: 'O convite não pôde ser vinculado à empresa. Nenhum acesso foi concedido.' })
  }

  return json(200, { userId: targetId, email })
})
