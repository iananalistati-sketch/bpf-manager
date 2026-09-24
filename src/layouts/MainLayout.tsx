import { useEffect, useRef, useState } from 'react'
import { Link, Outlet, useLocation } from 'react-router-dom'
import { Building2, ChevronRight, LogOut, Menu } from 'lucide-react'
import { Sidebar } from '../components/Sidebar'
import { navigationGroups } from '../lib/navigation'
import { useAuth } from '../hooks/useAuth'

export function MainLayout() {
  const [collapsed, setCollapsed] = useState(false)
  const [tenantError, setTenantError] = useState<string | null>(null)
  const dialog = useRef<HTMLDialogElement>(null)
  const menuButton = useRef<HTMLButtonElement>(null)
  const location = useLocation()
  const { contexto, vinculos, empresaAtivaId, trocarEmpresa, signOut } = useAuth()
  const current = navigationGroups.flatMap(group => group.items).find(item => item.path === location.pathname)
  const closeMenu = () => { dialog.current?.close(); menuButton.current?.focus() }
  const displayName = contexto?.nome || contexto?.email || 'Usuário'
  const initials = displayName.split(/\s+/).filter(Boolean).slice(0, 2).map(part => part[0]?.toUpperCase()).join('') || 'US'

  useEffect(() => {
    document.title = `${current?.title ?? 'Página não encontrada'} | BPF Manager`
    window.scrollTo(0, 0)
  }, [location.pathname, current?.title])

  useEffect(() => {
    const media = window.matchMedia('(min-width: 761px)')
    const handleResize = () => { if (media.matches) dialog.current?.close() }
    media.addEventListener('change', handleResize)
    return () => media.removeEventListener('change', handleResize)
  }, [])

  const handleTenantChange = async (empresaId: string) => {
    setTenantError(null)
    const error = await trocarEmpresa(empresaId)
    setTenantError(error)
  }

  return <div className={`app-shell${collapsed ? ' sidebar-collapsed' : ''}`}>
    <a className="skip-link" href="#main-content">Ir para o conteúdo</a>
    <aside className="desktop-sidebar"><Sidebar collapsed={collapsed} onToggle={() => setCollapsed(!collapsed)} /></aside>
    <dialog ref={dialog} className="mobile-sidebar" aria-label="Menu de navegação" onClick={event => { if (event.target === event.currentTarget) closeMenu() }}>
      <Sidebar mobile collapsed={false} onToggle={() => {}} onNavigate={closeMenu} />
    </dialog>
    <div className="workspace"><header className="header">
      <div className="breadcrumb"><button ref={menuButton} className="icon-button mobile-menu-button" aria-label="Abrir menu" aria-haspopup="dialog" onClick={() => dialog.current?.showModal()}><Menu size={22} /></button><span className="breadcrumb-root">Workspace</span><ChevronRight size={14} className="breadcrumb-root" aria-hidden="true" /><span>{current?.title ?? 'Página não encontrada'}</span></div>
      <div className="header-account">
        <div className="unit"><Building2 size={18} aria-hidden="true" /><div><small>{vinculos.length > 1 ? 'Empresa ativa' : 'Unidade'}</small>{vinculos.length > 1 ? <select aria-label="Empresa ativa" value={empresaAtivaId ?? ''} onChange={event => void handleTenantChange(event.target.value)}>{vinculos.map(vinculo => <option key={vinculo.membership_id} value={vinculo.empresa_id}>{vinculo.nome_fantasia || vinculo.razao_social || vinculo.empresa_id}</option>)}</select> : <strong>{contexto?.unidade_nome || contexto?.nome_fantasia || 'Não vinculada'}</strong>}</div></div>
        <Link className="user-profile" to="/configuracoes" aria-label={`Usuário ${displayName} — configurações`}><span className="avatar">{initials}</span><span><small>Usuário</small><strong>{displayName}</strong></span></Link><button className="icon-button" type="button" aria-label="Sair" title="Sair" onClick={() => void signOut()}><LogOut size={18} /></button>
      </div>
      {tenantError && <p className="tenant-switch-error" role="alert">{tenantError}</p>}
    </header><main id="main-content" tabIndex={-1}><Outlet /></main><footer className="workspace-footer"><span>BPF Manager · Gestão de Boas Práticas de Fabricação</span><span>{contexto?.nome_fantasia || contexto?.razao_social || 'Ambiente autenticado'}</span></footer></div>
  </div>
}
