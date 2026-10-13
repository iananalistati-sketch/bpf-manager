import { useEffect, useState, type FormEvent } from 'react'
import { ArrowRight, Building2, CheckCircle2 } from 'lucide-react'
import { Navigate, useNavigate } from 'react-router-dom'
import { Brand } from '../components/Brand'
import { useAuth } from '../hooks/useAuth'
import { supabase } from '../lib/supabase'

type TrialResponse = {
  empresaId?: string
  trialFim?: string
  error?: string
  code?: string
}

export function TrialSetupPage() {
  const { session, contexto, vinculos, loading, refreshContexto, signOut } = useAuth()
  const navigate = useNavigate()
  const [razaoSocial, setRazaoSocial] = useState('')
  const [nomeFantasia, setNomeFantasia] = useState('')
  const [unidadeNome, setUnidadeNome] = useState('Unidade Principal')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => { document.title = 'Iniciar trial | BPF Manager' }, [])

  if (loading) return <main className="auth-state-page"><section className="auth-state-card panel"><p>Preparando seu acesso...</p></section></main>
  if (!session) return <Navigate to="/login" replace />
  if (contexto?.empresa_id || vinculos.length > 0) return <Navigate to="/dashboard" replace />

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setSubmitting(true)
    setError(null)

    try {
      const { data, error: invokeError } = await supabase.functions.invoke<TrialResponse>('start-trial', {
        body: {
          razaoSocial: razaoSocial.trim(),
          nomeFantasia: nomeFantasia.trim(),
          unidadeNome: unidadeNome.trim(),
        },
      })

      if (invokeError) {
        setError('Não foi possível criar seu ambiente de teste agora. Tente novamente em instantes.')
        return
      }

      if (data?.error) {
        setError(data.error)
        return
      }

      await refreshContexto()
      navigate('/onboarding', { replace: true })
    } finally {
      setSubmitting(false)
    }
  }

  return <main className="login-page">
    <section className="trial-card panel">
      <Brand />
      <span className="empty-icon"><Building2 size={34} /></span>
      <div className="trial-heading">
        <h1>Prepare seu ambiente de teste</h1>
        <p>Criaremos um workspace isolado com 14 dias de acesso para você conhecer o BPF Manager.</p>
      </div>

      <div className="trial-benefits" aria-label="O que será criado">
        <span><CheckCircle2 size={16} /> Empresa e unidade principal</span>
        <span><CheckCircle2 size={16} /> Seu acesso como administrador</span>
        <span><CheckCircle2 size={16} /> Plano inicial e onboarding</span>
      </div>

      <form className="login-form" onSubmit={handleSubmit}>
        <label>
          <span>Razão social</span>
          <input value={razaoSocial} onChange={event => setRazaoSocial(event.target.value)} minLength={2} maxLength={180} required />
        </label>
        <label>
          <span>Nome da empresa</span>
          <input value={nomeFantasia} onChange={event => setNomeFantasia(event.target.value)} minLength={2} maxLength={120} required />
        </label>
        <label>
          <span>Unidade principal</span>
          <input value={unidadeNome} onChange={event => setUnidadeNome(event.target.value)} minLength={2} maxLength={120} required />
        </label>

        {error && <p className="login-error" role="alert">{error}</p>}

        <button className="button primary" type="submit" disabled={submitting}>
          {submitting ? 'Preparando ambiente...' : <>Iniciar meu trial <ArrowRight size={18} /></>}
        </button>
      </form>

      <button className="text-link auth-mode-switch" type="button" onClick={() => void signOut()}>
        Sair e usar outra conta
      </button>
      <small>Nenhum cartão é necessário para iniciar o período de teste.</small>
    </section>
  </main>
}
