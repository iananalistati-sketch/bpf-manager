import { useEffect, useState, type FormEvent } from 'react'
import { ArrowRight, KeyRound, ShieldCheck, UserPlus } from 'lucide-react'
import { Navigate, useLocation, useNavigate } from 'react-router-dom'
import { Brand } from '../components/Brand'
import { useAuth } from '../hooks/useAuth'

type AuthMode = 'login' | 'signup' | 'forgot'

export function LoginPage() {
  const { session, contexto, vinculos, loading, signIn, signUp, requestPasswordReset } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const [mode, setMode] = useState<AuthMode>('login')
  const [nome, setNome] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  useEffect(() => { document.title = 'Login | BPF Manager' }, [])

  if (!loading && session) {
    const hasWorkspace = Boolean(contexto?.empresa_id) || vinculos.length > 0
    return <Navigate to={hasWorkspace ? '/dashboard' : '/iniciar-trial'} replace />
  }

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setSubmitting(true)
    setError(null)
    setSuccess(null)

    if (mode === 'forgot') {
      const message = await requestPasswordReset(email.trim())
      setSubmitting(false)
      if (message) {
        setError(message)
        return
      }
      setSuccess('Se existir uma conta para este e-mail, enviaremos um link para redefinir a senha.')
      return
    }

    if (mode === 'signup') {
      const result = await signUp(email.trim(), password, nome.trim())
      setSubmitting(false)

      if (result.error) {
        setError(result.error)
        return
      }

      if (result.needsEmailConfirmation) {
        setSuccess('Conta criada. Confirme o e-mail e depois entre para iniciar seu trial de 14 dias.')
        setMode('login')
        return
      }

      navigate('/iniciar-trial', { replace: true })
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

  const changeMode = (nextMode: AuthMode) => {
    setMode(nextMode)
    setPassword('')
    setError(null)
    setSuccess(null)
  }

  const title = mode === 'login'
    ? 'Acesse o BPF Manager'
    : mode === 'signup'
      ? 'Comece seu teste gratuito'
      : 'Recupere seu acesso'

  const description = mode === 'login'
    ? 'Entre com as credenciais da sua organização.'
    : mode === 'signup'
      ? 'Crie sua conta e prepare um ambiente isolado por 14 dias, sem cartão.'
      : 'Informe seu e-mail. Se houver uma conta vinculada, enviaremos um link seguro de redefinição.'

  return <main className="login-page"><section className="login-card panel">
    <Brand />
    <span className="empty-icon">
      {mode === 'login' ? <ShieldCheck size={34} /> : mode === 'signup' ? <UserPlus size={34} /> : <KeyRound size={34} />}
    </span>
    <div>
      <h1>{title}</h1>
      <p>{description}</p>
    </div>
    <form className="login-form" onSubmit={handleSubmit}>
      {mode === 'signup' && <label><span>Seu nome</span><input type="text" autoComplete="name" minLength={2} value={nome} onChange={event => setNome(event.target.value)} required /></label>}
      <label><span>E-mail</span><input type="email" autoComplete="email" value={email} onChange={event => setEmail(event.target.value)} required /></label>
      {mode !== 'forgot' && <label><span>Senha</span><input type="password" minLength={6} autoComplete={mode === 'login' ? 'current-password' : 'new-password'} value={password} onChange={event => setPassword(event.target.value)} required /></label>}
      {mode === 'login' && <button className="text-link auth-inline-link" type="button" onClick={() => changeMode('forgot')}>Esqueci minha senha</button>}
      {error && <p className="login-error" role="alert">{error}</p>}
      {success && <p className="login-success" role="status">{success}</p>}
      <button className="button primary" type="submit" disabled={submitting}>
        {submitting
          ? mode === 'login' ? 'Entrando...' : mode === 'signup' ? 'Criando...' : 'Enviando...'
          : mode === 'login' ? <>Entrar <ArrowRight size={18} /></>
            : mode === 'signup' ? <>Criar conta e continuar <UserPlus size={18} /></>
              : <>Enviar link <KeyRound size={18} /></>}
      </button>
    </form>
    {mode === 'login'
      ? <button className="text-link auth-mode-switch" type="button" onClick={() => changeMode('signup')}>Testar gratuitamente por 14 dias</button>
      : <button className="text-link auth-mode-switch" type="button" onClick={() => changeMode('login')}>Voltar para o login</button>}
    <small>Gestão de BPF para indústrias de alimentação animal</small>
  </section></main>
}
