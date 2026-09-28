import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL?.trim()
const supabasePublishableKey = (
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ??
  import.meta.env.VITE_SUPABASE_ANON_KEY
)?.trim()

const hasValidUrl = Boolean(supabaseUrl && /^https?:\/\//i.test(supabaseUrl))
const hasKey = Boolean(supabasePublishableKey)

export const supabaseConfigError = !hasValidUrl
  ? 'A URL do Supabase não está configurada corretamente. Verifique VITE_SUPABASE_URL no arquivo .env.local.'
  : !hasKey
    ? 'A chave publishable do Supabase não foi encontrada. Verifique VITE_SUPABASE_PUBLISHABLE_KEY no arquivo .env.local.'
    : null

// Mantém a aplicação renderizável mesmo quando o .env.local estiver incorreto.
// Enquanto houver supabaseConfigError, o AuthProvider não realiza chamadas à API.
export const supabase = createClient(
  hasValidUrl ? supabaseUrl! : 'http://127.0.0.1:54321',
  hasKey ? supabasePublishableKey! : 'configuracao-ausente',
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
    },
  },
)
