import { useEffect, useState, type FormEvent } from 'react'
import { CheckCircle2, KeyRound } from 'lucide-react'
import { Link } from 'react-router-dom'
import { Brand } from '../components/Brand'
import { useAuth } from '../hooks/useAuth'

export function ResetPasswordPage() {
  const { session, loading, updatePassword, signOut } = useAuth()
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState(false)
  const [submitting, setSubmitting] = useState(false)

  useEffect(() => { document.title = 'Redefinir senha | BPF Manager' }, [])

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setError(null)

    if (password.length < 8) {
      setError('Use uma senha com pelo menos 8 caracteres.')
      return
    }
    if (password !== confirmPassword) {
      setError('As senhas informadas não coincidem.')
      return
    }

    setSubmitting(true)
    const message = await updatePassword(password)
    if (message) {
      setSubmitting(false)
      setError(message)
      return
    }

    await signOut()
    setSubmitting(false)
    setSuccess(true)
  }

  if (loading) return <main className="login-page"><section className="login-card panel"><Brand /><p role="status">Validando link de recuperação…</p></section></main>

  if (success) {
    return <main className="login-page"><section className="login-card panel">
      <Brand />
      <span className="empty-icon"><CheckCircle2 size={34} /></span>
      <div>
        <h1>Senha atualizada</h1>
        <p>Sua nova senha foi salva. Faça login novamente para continuar.</p>
      </div>
      <Link className="button primary auth-link-button" to="/login">Voltar para o login</Link>
    </section></main>
  }

  if (!session) {
    return <main className="login-page"><section className="login-card panel">
      <Brand />
      <span className="empty-icon"><KeyRound size={34} /></span>
      <div>
        <h1>Link inválido ou expirado</h1>
        <p>Solicite um novo link de recuperação na tela de login.</p>
      </div>
      <Link className="button primary auth-link-button" to="/login">Ir para o login</Link>
    </section></main>
  }

  return <main className="login-page"><section className="login-card panel">
    <Brand />
    <span className="empty-icon"><KeyRound size={34} /></span>
    <div>
      <h1>Defina uma nova senha</h1>
      <p>Escolha uma nova senha para sua conta do BPF Manager.</p>
    </div>
    <form className="login-form" onSubmit={handleSubmit}>
      <label><span>Nova senha</span><input type="password" minLength={8} autoComplete="new-password" value={password} onChange={event => setPassword(event.target.value)} required /></label>
      <label><span>Confirmar nova senha</span><input type="password" minLength={8} autoComplete="new-password" value={confirmPassword} onChange={event => setConfirmPassword(event.target.value)} required /></label>
      {error && <p className="login-error" role="alert">{error}</p>}
      <button className="button primary" type="submit" disabled={submitting}>{submitting ? 'Atualizando...' : 'Atualizar senha'}</button>
    </form>
  </section></main>
}
