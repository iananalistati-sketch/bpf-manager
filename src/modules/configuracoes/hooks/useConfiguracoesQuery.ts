import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { useAuth } from '../../../hooks/useAuth'
import { hasPermission } from '../../../lib/permissions'
import { supabase } from '../../../lib/supabase'
import type { MeuContexto, UsuarioStatus } from '../../../types/auth'
import { createConfiguracoesService } from '../services/configuracoesService'
import type { ReadScope } from '../types'

const service = createConfiguracoesService(supabase)
type QueryState<T> = { contexto: MeuContexto; revision: number; data: T | null; error: string | null }
type PerfilAction = 'atribuir' | 'remover'

function useConfiguracoesQuery<T>(permission: string, loader: (scope: ReadScope, signal: AbortSignal) => Promise<T>) {
  const { contexto, session, loading: authLoading } = useAuth()
  const [revision, setRevision] = useState(0)
  const [state, setState] = useState<QueryState<T> | null>(null)
  const allowed = !authLoading && session?.user.id === contexto?.usuario_id
    && hasPermission(contexto, 'configuracoes.visualizar') && hasPermission(contexto, permission)

  useEffect(() => {
    if (!allowed || !contexto?.empresa_id) return
    const controller = new AbortController()
    let cancelled = false
    const timeout = window.setTimeout(() => controller.abort(), 20000)
    void loader({ usuarioId: contexto.usuario_id, empresaId: contexto.empresa_id }, controller.signal)
      .then(data => {
        if (!cancelled) setState({ contexto, revision, data, error: null })
      })
      .catch((error: unknown) => {
        if (!cancelled) setState({ contexto, revision, data: null, error: controller.signal.aborted
          ? 'A consulta demorou mais que o esperado. Tente novamente.'
          : error instanceof Error ? error.message : 'Não foi possível carregar os dados. Tente novamente.' })
      })
      .finally(() => window.clearTimeout(timeout))
    return () => { cancelled = true; controller.abort(); window.clearTimeout(timeout) }
  }, [allowed, contexto, revision, loader])

  const current = allowed && state?.contexto === contexto && state?.revision === revision ? state : null
  return { data: current?.data ?? null, error: current?.error ?? null, loading: allowed && !current,
    allowed, reload: () => setRevision(value => value + 1) }
}

function useActionRunner() {
  const { contexto, session, refreshContexto } = useAuth()
  const scope = contexto?.empresa_id && session?.user.id === contexto.usuario_id
    ? { usuarioId: contexto.usuario_id, empresaId: contexto.empresa_id }
    : null
  const scopeKey = scope ? `${scope.usuarioId}:${scope.empresaId}` : null
  const [feedback,setFeedback] = useState<{scopeKey:string|null;busy:string|null;error:string|null;success:string|null}>({scopeKey,busy:null,error:null,success:null})
  const liveScope = useRef(scopeKey)
  const operation = useRef(0)
  useLayoutEffect(() => {
    liveScope.current=scopeKey
    operation.current+=1
    return () => { liveScope.current=null; operation.current+=1 }
  },[scopeKey])
  const visible = feedback.scopeKey===scopeKey ? feedback : null

  async function run<T>(key: string, action: (currentScope: ReadScope) => Promise<T>, successMessage?: string, refreshContext = false) {
    if (!scope) {
      setFeedback({scopeKey,busy:null,error:'Sua sessão administrativa não está disponível. Atualize a página e tente novamente.',success:null})
      return { ok: false as const, value: null }
    }
    const request = ++operation.current
    const isCurrent = () => liveScope.current === scopeKey && operation.current === request
    setFeedback({scopeKey,busy:key,error:null,success:null})
    try {
      const value = await action(scope)
      if (!isCurrent()) return { ok: false as const, value: null }
      if (refreshContext) await refreshContexto()
      if (!isCurrent()) return { ok: false as const, value: null }
      if (successMessage) setFeedback(previous=>({...previous,success:successMessage}))
      return { ok: true as const, value }
    } catch (reason) {
      if (isCurrent()) setFeedback(previous=>({...previous,error:reason instanceof Error ? reason.message : 'Não foi possível concluir a alteração.'}))
      return { ok: false as const, value: null }
    } finally { if (isCurrent()) setFeedback(previous=>({...previous,busy:null})) }
  }

  return { contexto, scope, busy:visible?.busy??null, error:visible?.error??null, success:visible?.success??null, run,
    clearFeedback: () => setFeedback(previous=>({scopeKey,busy:previous.scopeKey===scopeKey?previous.busy:null,error:null,success:null})) }
}

export function useUsuarioAdminActions() {
  const action = useActionRunner()
  const canManageProfiles = hasPermission(action.contexto, 'perfis.gerenciar')
  const canInvite = hasPermission(action.contexto, 'usuarios.convidar')
  return {
    busy: action.busy, error: action.error, success: action.success, clearError: action.clearFeedback,
    canManageProfiles, canInvite, currentUserId: action.contexto?.usuario_id ?? null,
    alterarStatus: async (usuarioId: string, status: Exclude<UsuarioStatus, 'pendente'>, justificativa: string) =>
      (await action.run(`status:${status}`, current => service.alterarStatus(current, usuarioId, status, justificativa), 'Status atualizado com sucesso.')).ok,
    alterarUnidade: async (usuarioId: string, unidadeId: string | null, justificativa: string) =>
      (await action.run('unidade', current => service.alterarUnidade(current, usuarioId, unidadeId, justificativa), 'Unidade atualizada com sucesso.')).ok,
    alterarPerfil: async (usuarioId: string, perfilId: string, acao: PerfilAction, justificativa: string) =>
      (await action.run(`perfil:${perfilId}:${acao}`, current => service.alterarPerfil(current, usuarioId, perfilId, acao, justificativa), 'Perfil atualizado com sucesso.')).ok,
    convidarUsuario: async (input: { email: string; nome: string; unidadeId: string | null; perfilIds: string[]; justificativa: string }) =>
      action.run('convidar', current => service.convidarUsuario(current, input), 'Convite enviado e acesso vinculado com sucesso.'),
  }
}

export function useAdministracaoActions() {
  const action = useActionRunner()
  return {
    busy: action.busy, error: action.error, success: action.success, clearFeedback: action.clearFeedback,
    perfilCriar: (nome: string, descricao: string, permissaoIds: string[], justificativa: string) =>
      action.run('perfil:criar', current => service.perfilCriar(current, nome, descricao, permissaoIds, justificativa), 'Perfil criado com sucesso.'),
    perfilAtualizar: (perfilId: string, nome: string, descricao: string, ativo: boolean, permissaoIds: string[], justificativa: string) =>
      action.run(`perfil:${perfilId}:salvar`, current => service.perfilAtualizar(current, perfilId, nome, descricao, ativo, permissaoIds, justificativa), 'Perfil atualizado com sucesso.'),
    empresaAtualizar: (razao: string, fantasia: string, cnpj: string, justificativa: string) =>
      action.run('empresa:salvar', current => service.empresaAtualizar(current, razao, fantasia, cnpj, justificativa), 'Empresa atualizada com sucesso.', true),
    unidadeSalvar: (id: string | null, nome: string, codigo: string, ativo: boolean, justificativa: string) =>
      action.run(`unidade:${id ?? 'nova'}`, current => service.unidadeSalvar(current, id, nome, codigo, ativo, justificativa), 'Unidade salva com sucesso.'),
    setorSalvar: (id: string | null, unidadeId: string, nome: string, codigo: string, ativo: boolean, justificativa: string) =>
      action.run(`setor:${id ?? 'novo'}`, current => service.setorSalvar(current, id, unidadeId, nome, codigo, ativo, justificativa), 'Setor salvo com sucesso.'),
  }
}

export const useUsuarios = () => useConfiguracoesQuery('usuarios.gerenciar', service.usuarios)
export const usePerfis = () => useConfiguracoesQuery('perfis.gerenciar', service.perfis)
export const useEstrutura = () => useConfiguracoesQuery('estrutura.gerenciar', service.estrutura)
export const useAuditoria = () => useConfiguracoesQuery('auditoria.visualizar', service.auditoria)
export const usePlano = () => useConfiguracoesQuery('configuracoes.visualizar', service.plano)
