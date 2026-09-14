import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase, supabaseConfigError } from '../lib/supabase'
import type { MeuContexto } from '../types/auth'

type SignUpResult = {
  error: string | null
  needsEmailConfirmation: boolean
}

type AuthContextValue = {
  session: Session | null
  contexto: MeuContexto | null
  loading: boolean
  contextoError: string | null
  signIn: (email: string, password: string) => Promise<string | null>
  signUp: (email: string, password: string) => Promise<SignUpResult>
  signOut: () => Promise<void>
  refreshContexto: () => Promise<void>
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [contexto, setContexto] = useState<MeuContexto | null>(null)
  const [loading, setLoading] = useState(!supabaseConfigError)
  const [contextoError, setContextoError] = useState<string | null>(supabaseConfigError)

  const loadContexto = async (activeSession: Session | null) => {
    if (supabaseConfigError) {
      setContexto(null)
      setContextoError(supabaseConfigError)
      return
    }

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
    if (supabaseConfigError) {
      setLoading(false)
      return
    }

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

      return {
        error: null,
        needsEmailConfirmation: !data.session,
      }
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
  }), [session, contexto, loading, contextoError])

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) throw new Error('useAuth deve ser usado dentro de AuthProvider')
  return context
}
