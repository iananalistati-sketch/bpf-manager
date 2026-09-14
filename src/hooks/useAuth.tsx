import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import type { MeuContexto } from '../types/auth'

type AuthContextValue = {
  session: Session | null
  contexto: MeuContexto | null
  loading: boolean
  contextoError: string | null
  signIn: (email: string, password: string) => Promise<string | null>
  signOut: () => Promise<void>
  refreshContexto: () => Promise<void>
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [contexto, setContexto] = useState<MeuContexto | null>(null)
  const [loading, setLoading] = useState(true)
  const [contextoError, setContextoError] = useState<string | null>(null)

  const loadContexto = async (activeSession: Session | null) => {
    if (!activeSession) {
      setContexto(null)
      setContextoError(null)
      return
    }

    const { data, error } = await supabase
      .from('v_meu_contexto')
      .select('*')
      .maybeSingle()

    if (error) {
      setContexto(null)
      setContextoError('Não foi possível carregar seu contexto de acesso.')
      return
    }

    setContexto((data as MeuContexto | null) ?? null)
    setContextoError(null)
  }

  useEffect(() => {
    const bootstrap = async () => {
      const { data } = await supabase.auth.getSession()
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
    loading,
    contextoError,
    signIn: async (email, password) => {
      const { error } = await supabase.auth.signInWithPassword({ email, password })
      return error ? 'E-mail ou senha inválidos.' : null
    },
    signOut: async () => {
      await supabase.auth.signOut()
    },
    refreshContexto: async () => {
      setLoading(true)
      await loadContexto(session)
      setLoading(false)
    },
  }), [session, contexto, loading, contextoError])

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) throw new Error('useAuth deve ser usado dentro de AuthProvider')
  return context
}
