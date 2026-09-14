import { useEffect, useState, type FormEvent } from 'react'
import { ArrowRight, ShieldCheck, UserPlus } from 'lucide-react'
import { Navigate, useLocation, useNavigate } from 'react-router-dom'
import { Brand } from '../components/Brand'
import { useAuth } from '../hooks/useAuth'

export function LoginPage() {
  const { session, signIn, signUp } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const [mode, setMode] = useState<'login' | 'signup'>('login')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  useEffect(() => { document.title = 'Login | BPF Manager' }, [])

  if (session) return <Navigate to="/dashboard" replace />

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setSubmitting(true)
    setError(null)
    setSuccess(null)

    if (mode === 'signup') {
      const result = await signUp(email.trim(), password)
      setSubmitting(false)

      if (result.error) {
        setError(result.error)
        return
      }

      if (result.needsEmailConfirmation) {
        setSuccess('Conta criada. Confirme o e-mail enviado pelo Supabase e depois faça login.')
        setMode('login')
        return
      }

      setSuccess('Conta criada. Seu acesso está aguardando aprovação do administrador.')
      return
    }

    const message = await signIn(email.trim(), password)
    setSubmitting(false)
    if (message) {
      setError(message)
      return
    }
    const redirectTo = (location.state as { from?: string } | null)?.from ?? '/dashboard'
    navigate(redirectTo, { replace: true })
  }

  const switchMode = () => {
    setMode(current => current === 'login' ? 'signup' : 'login')
    setError(null)
    setSuccess(null)
  }

  return <main className="login-page"><section className="login-card panel">
    <Brand />
    <span className="empty-icon">{mode === 'login' ? <ShieldCheck size={34} /> : <UserPlus size={34} />}</span>
    <div>
      <h1>{mode === 'login' ? 'Acesse o BPF Manager' : 'Crie uma conta de teste'}</h1>
      <p>{mode === 'login' ? 'Entre com as credenciais da sua organização.' : 'A conta será criada como pendente e precisará ser aprovada antes de acessar a plataforma.'}</p>
    </div>
    <form className="login-form" onSubmit={handleSubmit}>
      <label><span>E-mail</span><input type="email" autoComplete="email" value={email} onChange={event => setEmail(event.target.value)} required /></label>
      <label><span>Senha</span><input type="password" minLength={6} autoComplete={mode === 'login' ? 'current-password' : 'new-password'} value={password} onChange={event => setPassword(event.target.value)} required /></label>
      {error && <p className="login-error" role="alert">{error}</p>}
      {success && <p className="login-success" role="status">{success}</p>}
      <button className="button primary" type="submit" disabled={submitting}>
        {submitting ? (mode === 'login' ? 'Entrando...' : 'Criando...') : mode === 'login' ? <>Entrar <ArrowRight size={18} /></> : <>Criar conta <UserPlus size={18} /></>}
      </button>
    </form>
    <button className="text-link auth-mode-switch" type="button" onClick={switchMode}>
      {mode === 'login' ? 'Criar conta de teste' : 'Já tenho uma conta'}
    </button>
    <small>Gestão de BPF para indústrias de alimentação animal</small>
  </section></main>
}
