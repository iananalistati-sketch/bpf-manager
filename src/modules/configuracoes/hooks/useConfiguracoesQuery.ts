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

function useActionRunner() {
  const { contexto, session, refreshContexto } = useAuth()
  const [busy, setBusy] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const scope = contexto?.empresa_id && session?.user.id === contexto.usuario_id
    ? { usuarioId: contexto.usuario_id, empresaId: contexto.empresa_id }
    : null

  async function run<T>(key: string, action: (currentScope: ReadScope) => Promise<T>, successMessage?: string, refreshContext = false) {
    if (!scope) {
      setError('Sua sessão administrativa não está disponível. Atualize a página e tente novamente.')
      return { ok: false as const, value: null }
    }
    setBusy(key); setError(null); setSuccess(null)
    try {
      const value = await action(scope)
      if (refreshContext) await refreshContexto()
      if (successMessage) setSuccess(successMessage)
      return { ok: true as const, value }
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Não foi possível concluir a alteração.')
      return { ok: false as const, value: null }
    } finally { setBusy(null) }
  }

  return { contexto, scope, busy, error, success, run, clearFeedback: () => { setError(null); setSuccess(null) } }
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
