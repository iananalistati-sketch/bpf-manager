import { useEffect, useState } from 'react'
import { useAuth } from '../../../hooks/useAuth'
import { hasPermission } from '../../../lib/permissions'
import { supabase } from '../../../lib/supabase'
import type { MeuContexto } from '../../../types/auth'
import { createConfiguracoesService } from '../services/configuracoesService'
import type { ReadScope } from '../types'

const service = createConfiguracoesService(supabase)
type QueryState<T> = { contexto: MeuContexto; revision: number; data: T | null; error: string | null }

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

  // Não reutiliza dados de outro contexto, permissão ou atualização, nem durante logout.
  const current = allowed && state?.contexto === contexto && state?.revision === revision ? state : null
  return { data: current?.data ?? null, error: current?.error ?? null, loading: allowed && !current,
    allowed, reload: () => setRevision(value => value + 1) }
}

export const useUsuarios = () => useConfiguracoesQuery('usuarios.gerenciar', service.usuarios)
export const usePerfis = () => useConfiguracoesQuery('perfis.gerenciar', service.perfis)
