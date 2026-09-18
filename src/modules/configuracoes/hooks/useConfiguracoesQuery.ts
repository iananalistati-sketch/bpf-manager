import { useEffect, useState } from 'react'
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

export function useUsuarioAdminActions() {
  const { contexto, session } = useAuth()
  const [busy, setBusy] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const canManageProfiles = hasPermission(contexto, 'perfis.gerenciar')
  const scope = contexto?.empresa_id && session?.user.id === contexto.usuario_id
    ? { usuarioId: contexto.usuario_id, empresaId: contexto.empresa_id }
    : null

  async function run(key: string, action: (currentScope: ReadScope) => Promise<void>) {
    if (!scope) {
      setError('Sua sessão administrativa não está disponível. Atualize a página e tente novamente.')
      return false
    }
    setBusy(key)
    setError(null)
    try {
      await action(scope)
      return true
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Não foi possível concluir a alteração.')
      return false
    } finally {
      setBusy(null)
    }
  }

  return {
    busy,
    error,
    clearError: () => setError(null),
    canManageProfiles,
    currentUserId: contexto?.usuario_id ?? null,
    alterarStatus: (usuarioId: string, status: Exclude<UsuarioStatus, 'pendente'>, justificativa: string) =>
      run(`status:${status}`, current => service.alterarStatus(current, usuarioId, status, justificativa)),
    alterarUnidade: (usuarioId: string, unidadeId: string | null, justificativa: string) =>
      run('unidade', current => service.alterarUnidade(current, usuarioId, unidadeId, justificativa)),
    alterarPerfil: (usuarioId: string, perfilId: string, acao: PerfilAction, justificativa: string) =>
      run(`perfil:${perfilId}:${acao}`, current => service.alterarPerfil(current, usuarioId, perfilId, acao, justificativa)),
  }
}

export const useUsuarios = () => useConfiguracoesQuery('usuarios.gerenciar', service.usuarios)
export const usePerfis = () => useConfiguracoesQuery('perfis.gerenciar', service.perfis)
