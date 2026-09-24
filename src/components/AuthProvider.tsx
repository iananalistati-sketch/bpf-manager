import { useEffect, useMemo, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase, supabaseConfigError } from '../lib/supabase'
import type { MeuContexto, MeuContextoEmpresa, VinculoEmpresa } from '../types/auth'
import { AuthContext, type AuthContextValue } from '../lib/authContext'

const tenantStorageKey = (userId: string) => `bpf-manager:empresa-ativa:${userId}`

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [contexto, setContexto] = useState<MeuContexto | null>(null)
  const [vinculos, setVinculos] = useState<VinculoEmpresa[]>([])
  const [empresaAtivaId, setEmpresaAtivaId] = useState<string | null>(null)
  const [loading, setLoading] = useState(!supabaseConfigError)
  const [contextoError, setContextoError] = useState<string | null>(supabaseConfigError)

  const loadLegacyContexto = async () => {
    const { data, error } = await supabase
      .from('v_meu_contexto')
      .select('*')
      .maybeSingle()

    if (error) return { contexto: null as MeuContexto | null, error }
    return { contexto: (data as MeuContexto | null) ?? null, error: null }
  }

  const loadTenantContexto = async (empresaId: string) => {
    const { data, error } = await supabase
      .rpc('meu_contexto_empresa', { p_empresa_id: empresaId })
      .maybeSingle()

    if (error || !data) return { contexto: null as MeuContextoEmpresa | null, error }
    return { contexto: data as MeuContextoEmpresa, error: null }
  }

  const loadContexto = async (activeSession: Session | null) => {
    if (supabaseConfigError) {
      setContexto(null)
      setVinculos([])
      setEmpresaAtivaId(null)
      setContextoError(supabaseConfigError)
      return
    }

    if (!activeSession) {
      setContexto(null)
      setVinculos([])
      setEmpresaAtivaId(null)
      setContextoError(null)
      return
    }

    const legacy = await loadLegacyContexto()
    const { data: vinculosData, error: vinculosError } = await supabase.rpc('meus_vinculos')

    if (vinculosError) {
      setVinculos([])
      setEmpresaAtivaId(legacy.contexto?.empresa_id ?? null)
      setContexto(legacy.contexto)
      setContextoError(legacy.error ? 'Não foi possível carregar seu contexto de acesso.' : null)
      return
    }

    const nextVinculos = Array.isArray(vinculosData) ? vinculosData as VinculoEmpresa[] : []
    setVinculos(nextVinculos)

    if (nextVinculos.length === 0) {
      setEmpresaAtivaId(legacy.contexto?.empresa_id ?? null)
      setContexto(legacy.contexto)
      setContextoError(legacy.error ? 'Não foi possível carregar seu contexto de acesso.' : null)
      return
    }

    const savedEmpresaId = window.localStorage.getItem(tenantStorageKey(activeSession.user.id))
    const legacyEmpresaId = legacy.contexto?.empresa_id ?? null
    const empresaId = nextVinculos.some(v => v.empresa_id === savedEmpresaId)
      ? savedEmpresaId!
      : nextVinculos.some(v => v.empresa_id === legacyEmpresaId)
        ? legacyEmpresaId!
        : nextVinculos[0].empresa_id

    const tenant = await loadTenantContexto(empresaId)
    if (!tenant.contexto) {
      setContexto(null)
      setEmpresaAtivaId(null)
      setContextoError('Não foi possível validar a empresa ativa para sua sessão.')
      return
    }

    window.localStorage.setItem(tenantStorageKey(activeSession.user.id), empresaId)
    setEmpresaAtivaId(empresaId)
    setContexto(tenant.contexto)
    setContextoError(null)
  }

  useEffect(() => {
    if (supabaseConfigError) return

    const bootstrap = async () => {
      const { data, error } = await supabase.auth.getSession()
      if (error) {
        setContextoError('Não foi possível inicializar a sessão do Supabase.')
        setLoading(false)
        return
      }
      setSession(data.session)
      await loadContexto(data.session)
      setLoading(false)
    }

    void bootstrap()

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession)
      setLoading(true)
      window.setTimeout(() => {
        void loadContexto(nextSession).finally(() => setLoading(false))
      }, 0)
    })

    return () => subscription.unsubscribe()
  }, [])

  const value = useMemo<AuthContextValue>(() => ({
    session,
    contexto,
    vinculos,
    empresaAtivaId,
    loading,
    contextoError,
    signIn: async (email, password) => {
      if (supabaseConfigError) return supabaseConfigError
      const { error } = await supabase.auth.signInWithPassword({ email, password })
      return error ? 'E-mail ou senha inválidos.' : null
    },
    signUp: async (email, password) => {
      if (supabaseConfigError) return { error: supabaseConfigError, needsEmailConfirmation: false }

      const { data, error } = await supabase.auth.signUp({ email, password })
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
      await supabase.auth.signOut()
    },
    refreshContexto: async () => {
      setLoading(true)
      await loadContexto(session)
      setLoading(false)
    },
    trocarEmpresa: async (empresaId) => {
      if (!session) return 'Sua sessão não está disponível.'
      if (!vinculos.some(v => v.empresa_id === empresaId)) return 'Empresa não autorizada para este usuário.'

      setLoading(true)
      try {
        const tenant = await loadTenantContexto(empresaId)
        if (!tenant.contexto) return 'Não foi possível validar o acesso à empresa selecionada.'
        window.localStorage.setItem(tenantStorageKey(session.user.id), empresaId)
        setEmpresaAtivaId(empresaId)
        setContexto(tenant.contexto)
        setContextoError(null)
        return null
      } finally {
        setLoading(false)
      }
    },
  }), [session, contexto, vinculos, empresaAtivaId, loading, contextoError])

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
