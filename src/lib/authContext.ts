import { createContext } from 'react'
import type { Session } from '@supabase/supabase-js'
import type { MeuContexto } from '../types/auth'

type SignUpResult = { error: string | null; needsEmailConfirmation: boolean }
export type AuthContextValue = {
  session: Session | null
  contexto: MeuContexto | null
  loading: boolean
  contextoError: string | null
  signIn: (email: string, password: string) => Promise<string | null>
  signUp: (email: string, password: string) => Promise<SignUpResult>
  signOut: () => Promise<void>
  refreshContexto: () => Promise<void>
}
export const AuthContext = createContext<AuthContextValue | undefined>(undefined)
