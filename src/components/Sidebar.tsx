import { NavLink } from 'react-router-dom'
import { PanelLeftClose, PanelLeftOpen, X } from 'lucide-react'
import { navigationGroups } from '../lib/navigation'
import { Brand } from './Brand'

interface SidebarProps { collapsed: boolean; onToggle: () => void; onNavigate?: () => void; mobile?: boolean }
export function Sidebar({ collapsed, onToggle, onNavigate, mobile = false }: SidebarProps) {
  return <>
    <div className="sidebar-brand"><Brand />{mobile && <button className="icon-button" onClick={onNavigate} aria-label="Fechar menu"><X size={20} /></button>}</div>
    <nav aria-label="Navegação principal" className="navigation">
      {navigationGroups.map(group => <div className="nav-group" key={group.title}><h2>{group.title}</h2>
        {group.items.map(({ path, title, icon: Icon }) => <NavLink key={path} to={path} onClick={onNavigate} title={collapsed ? title : undefined} aria-label={collapsed ? title : undefined} className={({ isActive }) => `nav-link${isActive ? ' active' : ''}`}><Icon size={18} aria-hidden="true" /><span>{title}</span></NavLink>)}
      </div>)}
    </nav>
    {!mobile && <button className="sidebar-toggle" onClick={onToggle} aria-label={collapsed ? 'Expandir sidebar' : 'Recolher sidebar'} aria-expanded={!collapsed}>{collapsed ? <PanelLeftOpen size={18} /> : <PanelLeftClose size={18} />}<span>Recolher menu</span></button>}
    <div className="sidebar-footer"><span className="status-dot" /><span>Ambiente demonstrativo</span></div>
  </>
}
