import { useEffect, useState, type FormEvent } from 'react'
import { ArrowRight, ShieldCheck } from 'lucide-react'
import { Navigate, useLocation, useNavigate } from 'react-router-dom'
import { Brand } from '../components/Brand'
import { useAuth } from '../hooks/useAuth'

export function LoginPage() {
  const { session, signIn } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  useEffect(() => { document.title = 'Login | BPF Manager' }, [])

  if (session) return <Navigate to="/dashboard" replace />

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setSubmitting(true)
    setError(null)
    const message = await signIn(email.trim(), password)
    setSubmitting(false)
    if (message) {
      setError(message)
      return
    }
    const redirectTo = (location.state as { from?: string } | null)?.from ?? '/dashboard'
    navigate(redirectTo, { replace: true })
  }

  return <main className="login-page"><section className="login-card panel">
    <Brand />
    <span className="empty-icon"><ShieldCheck size={34} /></span>
    <div><h1>Acesse o BPF Manager</h1><p>Entre com as credenciais da sua organização.</p></div>
    <form className="login-form" onSubmit={handleSubmit}>
      <label><span>E-mail</span><input type="email" autoComplete="email" value={email} onChange={event => setEmail(event.target.value)} required /></label>
      <label><span>Senha</span><input type="password" autoComplete="current-password" value={password} onChange={event => setPassword(event.target.value)} required /></label>
      {error && <p className="login-error" role="alert">{error}</p>}
      <button className="button primary" type="submit" disabled={submitting}>{submitting ? 'Entrando...' : <>Entrar <ArrowRight size={18} /></>}</button>
    </form>
    <small>Gestão de BPF para indústrias de alimentação animal</small>
  </section></main>
}
