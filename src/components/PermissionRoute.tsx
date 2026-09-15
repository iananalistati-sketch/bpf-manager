import { Navigate, useLocation } from 'react-router-dom'
import { ShieldAlert } from 'lucide-react'
import { useAuth } from '../hooks/useAuth'

type PermissionRouteProps = {
  permission: string
  children: React.ReactNode
}

export function PermissionRoute({ permission, children }: PermissionRouteProps) {
  const { contexto } = useAuth()
  const location = useLocation()
  const permissions = contexto?.permissoes ?? []

  if (permissions.includes(permission)) return <>{children}</>

  if (location.pathname !== '/dashboard' && permissions.includes('dashboard.visualizar')) {
    return <Navigate to="/dashboard" replace state={{ denied: location.pathname }} />
  }

  return <main className="auth-state-page"><section className="auth-state-card panel">
    <ShieldAlert size={36} />
    <h1>Acesso não autorizado</h1>
    <p>Seu perfil não possui a permissão <strong>{permission}</strong> necessária para acessar este módulo.</p>
  </section></main>
}
