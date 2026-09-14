import { useEffect, useRef, useState } from 'react'
import { Link, Outlet, useLocation } from 'react-router-dom'
import { Building2, ChevronRight, Menu } from 'lucide-react'
import { Sidebar } from '../components/Sidebar'
import { navigationGroups } from '../lib/navigation'

export function MainLayout() {
  const [collapsed, setCollapsed] = useState(false)
  const dialog = useRef<HTMLDialogElement>(null)
  const menuButton = useRef<HTMLButtonElement>(null)
  const location = useLocation()
  const current = navigationGroups.flatMap(group => group.items).find(item => item.path === location.pathname)
  const closeMenu = () => { dialog.current?.close(); menuButton.current?.focus() }
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
  return <div className={`app-shell${collapsed ? ' sidebar-collapsed' : ''}`}>
    <a className="skip-link" href="#main-content">Ir para o conteúdo</a>
    <aside className="desktop-sidebar"><Sidebar collapsed={collapsed} onToggle={() => setCollapsed(!collapsed)} /></aside>
    <dialog ref={dialog} className="mobile-sidebar" aria-label="Menu de navegação" onClick={event => { if (event.target === event.currentTarget) closeMenu() }}>
      <Sidebar mobile collapsed={false} onToggle={() => {}} onNavigate={closeMenu} />
    </dialog>
    <div className="workspace"><header className="header">
      <div className="breadcrumb"><button ref={menuButton} className="icon-button mobile-menu-button" aria-label="Abrir menu" aria-haspopup="dialog" onClick={() => dialog.current?.showModal()}><Menu size={22} /></button><span className="breadcrumb-root">Workspace</span><ChevronRight size={14} className="breadcrumb-root" aria-hidden="true" /><span>{current?.title ?? 'Página não encontrada'}</span></div>
      <div className="header-account"><div className="unit"><Building2 size={18} aria-hidden="true" /><div><small>Unidade</small><strong>Unidade Principal</strong></div></div><Link className="user-profile" to="/configuracoes" aria-label="Usuário Administrador — configurações"><span className="avatar">AD</span><span><small>Usuário</small><strong>Administrador</strong></span></Link></div>
    </header><main id="main-content" tabIndex={-1}><Outlet /></main><footer className="workspace-footer"><span>BPF Manager · Gestão de Boas Práticas de Fabricação</span><span>Versão inicial · Dados demonstrativos</span></footer></div>
  </div>
}
