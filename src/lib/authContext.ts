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
  requestPasswordReset: (email: string) => Promise<string | null>
  updatePassword: (password: string) => Promise<string | null>
  signOut: () => Promise<void>
  refreshContexto: () => Promise<void>
}
export const AuthContext = createContext<AuthContextValue | undefined>(undefined)
