import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase, supabaseConfigError } from '../lib/supabase'
import type { MeuContexto, MeuContextoEmpresa, VinculoEmpresa, WorkspaceCommercial } from '../types/auth'
import { AuthContext, type AuthContextValue } from '../lib/authContext'

const tenantStorageKey = (userId: string) => `bpf-manager:empresa-ativa:${userId}`

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [contexto, setContexto] = useState<MeuContexto | null>(null)
  const [vinculos, setVinculos] = useState<VinculoEmpresa[]>([])
  const [empresaAtivaId, setEmpresaAtivaId] = useState<string | null>(null)
  const [workspaceCommercial, setWorkspaceCommercial] = useState<WorkspaceCommercial | null>(null)
  const [workspaceCommercialError, setWorkspaceCommercialError] = useState<string | null>(null)
  const generation = useRef(0)
  const selectedTenant = useRef<{ userId: string; empresaId: string } | null>(null)
  const [loading, setLoading] = useState(!supabaseConfigError)
  const [contextoError, setContextoError] = useState<string | null>(supabaseConfigError)

  const loadLegacyContexto = useCallback(async () => {
    const { data, error } = await supabase
      .from('v_meu_contexto')
      .select('*')
      .maybeSingle()

    if (error) return { contexto: null as MeuContexto | null, error }
    return { contexto: (data as MeuContexto | null) ?? null, error: null }
  }, [])

  const loadTenantContexto = useCallback(async (empresaId: string) => {
    const { data, error } = await supabase
      .rpc('meu_contexto_empresa', { p_empresa_id: empresaId })
      .maybeSingle()

    if (error || !data) return { contexto: null as MeuContextoEmpresa | null, error }
    return { contexto: data as MeuContextoEmpresa, error: null }
  }, [])

  const loadWorkspaceCommercial = useCallback(async (empresaId: string) => {
    const { data, error } = await supabase
      .rpc('meu_workspace_comercial', { p_empresa_id: empresaId })
      .maybeSingle()

    return { commercial: error ? null : data as WorkspaceCommercial | null, error }
  }, [])

  const loadContexto = useCallback(async (activeSession: Session | null, requestId: number) => {
    const current = () => generation.current === requestId
    if (!current()) return
    if (supabaseConfigError) {
      setContexto(null)
      setVinculos([])
      setEmpresaAtivaId(null)
      setWorkspaceCommercial(null)
      setWorkspaceCommercialError(null)
      setContextoError(supabaseConfigError)
      return
    }

    if (!activeSession) {
      setContexto(null)
      setVinculos([])
      setEmpresaAtivaId(null)
      setWorkspaceCommercial(null)
      setWorkspaceCommercialError(null)
      setContextoError(null)
      return
    }

    const legacy = await loadLegacyContexto()
    if (!current()) return
    const { data: vinculosData, error: vinculosError } = await supabase.rpc('meus_vinculos')
    if (!current()) return

    if (vinculosError) {
      setVinculos([])
      setEmpresaAtivaId(legacy.contexto?.empresa_id ?? null)
      setWorkspaceCommercial(null)
      setWorkspaceCommercialError('Não foi possível validar os vínculos e a disponibilidade de escrita do workspace.')
      setContexto(legacy.contexto)
      setContextoError(legacy.error ? 'Não foi possível carregar seu contexto de acesso.' : null)
      return
    }

    const nextVinculos = Array.isArray(vinculosData) ? vinculosData as VinculoEmpresa[] : []
    setVinculos(nextVinculos)

    if (nextVinculos.length === 0) {
      setEmpresaAtivaId(legacy.contexto?.empresa_id ?? null)
      setWorkspaceCommercial(null)
      setWorkspaceCommercialError(null)
      setContexto(legacy.contexto)
      setContextoError(legacy.error ? 'Não foi possível carregar seu contexto de acesso.' : null)
      return
    }

    const savedEmpresaId = selectedTenant.current?.userId === activeSession.user.id
      ? selectedTenant.current.empresaId
      : window.localStorage.getItem(tenantStorageKey(activeSession.user.id))
    const legacyEmpresaId = legacy.contexto?.empresa_id ?? null
    const empresaId = nextVinculos.some(v => v.empresa_id === savedEmpresaId)
      ? savedEmpresaId!
      : nextVinculos.some(v => v.empresa_id === legacyEmpresaId)
        ? legacyEmpresaId!
        : nextVinculos[0].empresa_id

    const tenant = await loadTenantContexto(empresaId)
    if (!current()) return
    if (!tenant.contexto) {
      setContexto(null)
      setEmpresaAtivaId(null)
      setWorkspaceCommercial(null)
      setWorkspaceCommercialError(null)
      setContextoError('Não foi possível validar a empresa ativa para sua sessão.')
      return
    }

    const { commercial, error: commercialError } = await loadWorkspaceCommercial(empresaId)
    if (!current()) return
    setWorkspaceCommercialError(commercialError ? 'Não foi possível validar a disponibilidade de escrita do workspace. Atualize o contexto para tentar novamente.' : null)
    window.localStorage.setItem(tenantStorageKey(activeSession.user.id), empresaId)
    setEmpresaAtivaId(empresaId)
    setWorkspaceCommercial(commercial)
    setContexto(tenant.contexto)
    setContextoError(null)
  }, [loadLegacyContexto, loadTenantContexto, loadWorkspaceCommercial])

  useEffect(() => {
    if (supabaseConfigError) return

    const run = (nextSession: Session | null) => {
      const requestId = ++generation.current
      if (!nextSession) selectedTenant.current = null
      setSession(nextSession)
      setLoading(true)
      void loadContexto(nextSession, requestId).catch(() => {
        if (generation.current !== requestId) return
        setContexto(null)
        setEmpresaAtivaId(null)
        setWorkspaceCommercial(null)
        setContextoError('Não foi possível carregar seu contexto de acesso.')
      }).finally(() => {
        if (generation.current === requestId) setLoading(false)
      })
    }

    const bootstrapId = generation.current
    void supabase.auth.getSession().then(({ data, error }) => {
      if (generation.current !== bootstrapId) return
      if (error) {
        setContextoError('Não foi possível inicializar a sessão do Supabase.')
        setLoading(false)
      } else run(data.session)
    })

    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, nextSession) => {
      // getSession owns the initial load. Avoid two competing bootstrap requests.
      if (event === 'INITIAL_SESSION') return
      // Defer Supabase calls until its auth callback releases the session lock.
      const eventId = ++generation.current
      setSession(nextSession)
      setLoading(true)
      window.setTimeout(() => {
        if (generation.current === eventId) run(nextSession)
      }, 0)
    })

    return () => { generation.current += 1; subscription.unsubscribe() }
  }, [loadContexto])

  const value = useMemo<AuthContextValue>(() => ({
    session,
    contexto,
    vinculos,
    empresaAtivaId,
    workspaceCommercial,
    workspaceCommercialError,
    loading,
    contextoError,
    signIn: async (email, password) => {
      if (supabaseConfigError) return supabaseConfigError
      const { error } = await supabase.auth.signInWithPassword({ email, password })
      return error ? 'E-mail ou senha inválidos.' : null
    },
    signUp: async (email, password, nome) => {
      if (supabaseConfigError) return { error: supabaseConfigError, needsEmailConfirmation: false }

      const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: {
          data: { nome: nome.trim() },
          emailRedirectTo: `${window.location.origin}/login?trial=1`,
        },
      })
      if (error) {
        return {
          error: error.message.toLowerCase().includes('password')
            ? 'A senha não atende aos requisitos mínimos de segurança.'
            : 'Não foi possível criar a conta. Verifique o e-mail informado e tente novamente.',
          needsEmailConfirmation: false,
        }
      }

      return { error: null, needsEmailConfirmation: !data.session }
    },
    requestPasswordReset: async (email) => {
      if (supabaseConfigError) return supabaseConfigError
      const redirectTo = `${window.location.origin}/redefinir-senha`
      const { error } = await supabase.auth.resetPasswordForEmail(email, { redirectTo })
      return error ? 'Não foi possível solicitar a recuperação agora. Tente novamente em instantes.' : null
    },
    updatePassword: async (password) => {
      if (supabaseConfigError) return supabaseConfigError
      const { error } = await supabase.auth.updateUser({ password })
      if (!error) return null
      return error.message.toLowerCase().includes('password')
        ? 'A nova senha não atende aos requisitos mínimos de segurança.'
        : 'Não foi possível atualizar a senha. Solicite um novo link de recuperação.'
    },
    signOut: async () => {
      if (supabaseConfigError) return
      generation.current += 1
      selectedTenant.current = null
      setSession(null)
      setContexto(null)
      setEmpresaAtivaId(null)
      setVinculos([])
      setWorkspaceCommercial(null)
      setWorkspaceCommercialError(null)
      await supabase.auth.signOut()
    },
    refreshContexto: async () => {
      const requestId = ++generation.current
      setLoading(true)
      try { await loadContexto(session, requestId) }
      finally { if (generation.current === requestId) setLoading(false) }
    },
    trocarEmpresa: async (empresaId) => {
      if (!session) return 'Sua sessão não está disponível.'
      if (!vinculos.some(v => v.empresa_id === empresaId)) return 'Empresa não autorizada para este usuário.'

      const requestId = ++generation.current
      selectedTenant.current = { userId: session.user.id, empresaId }
      setLoading(true)
      try {
        const tenant = await loadTenantContexto(empresaId)
        if (generation.current !== requestId) return null
        if (!tenant.contexto) {
          selectedTenant.current = null
          return 'Não foi possível validar o acesso à empresa selecionada.'
        }
        const { commercial, error: commercialError } = await loadWorkspaceCommercial(empresaId)
        if (generation.current !== requestId) return null
        setWorkspaceCommercialError(commercialError ? 'Não foi possível validar a disponibilidade de escrita do workspace. Atualize o contexto para tentar novamente.' : null)
        window.localStorage.setItem(tenantStorageKey(session.user.id), empresaId)
        setEmpresaAtivaId(empresaId)
        setWorkspaceCommercial(commercial)
        setContexto(tenant.contexto)
        setContextoError(null)
        return null
      } catch {
        if (generation.current !== requestId) return null
        selectedTenant.current = null
        return 'Não foi possível carregar a empresa selecionada.'
      } finally {
        if (generation.current === requestId) setLoading(false)
      }
    },
  }), [session, contexto, vinculos, empresaAtivaId, workspaceCommercial, workspaceCommercialError, loading, contextoError, loadContexto, loadTenantContexto, loadWorkspaceCommercial])

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
