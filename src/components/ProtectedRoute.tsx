import { Navigate, Outlet } from 'react-router-dom'
import { ShieldAlert } from 'lucide-react'
import { useAuth } from '../hooks/useAuth'

function AccessState({ title, message, action }: { title: string; message: string; action?: () => void }) {
  return <main className="auth-state-page"><section className="auth-state-card panel"><ShieldAlert size={36} /><h1>{title}</h1><p>{message}</p>{action && <button className="button primary" onClick={action}>Sair</button>}</section></main>
}

export function ProtectedRoute() {
  const { session, contexto, loading, contextoError, signOut } = useAuth()

  if (loading) return <main className="auth-state-page"><section className="auth-state-card panel"><p>Carregando acesso...</p></section></main>
  if (!session) return <Navigate to="/login" replace />
  if (contextoError) return <AccessState title="Não foi possível validar o acesso" message={contextoError} action={() => void signOut()} />
  if (!contexto) return <AccessState title="Cadastro não encontrado" message="Seu usuário autenticado ainda não possui um cadastro de acesso válido no BPF Manager." action={() => void signOut()} />
  if (contexto.status === 'pendente') return <AccessState title="Acesso aguardando aprovação" message="Seu cadastro foi criado, mas ainda precisa ser vinculado a uma empresa, unidade e perfil de acesso." action={() => void signOut()} />
  if (contexto.status === 'inativo' || contexto.status === 'bloqueado' || !contexto.ativo) return <AccessState title="Acesso indisponível" message="Seu usuário está inativo ou bloqueado. Procure o administrador responsável pela sua organização." action={() => void signOut()} />
  if (!contexto.empresa_id) return <AccessState title="Empresa não vinculada" message="Seu usuário ainda não está vinculado a uma empresa." action={() => void signOut()} />

  return <Outlet />
}
