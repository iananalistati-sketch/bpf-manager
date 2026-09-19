import { Building2, History, LayoutGrid, Network, ShieldCheck, Users } from 'lucide-react'
import { useSearchParams } from 'react-router-dom'
import { useAuth } from '../../../hooks/useAuth'
import { hasPermission } from '../../../lib/permissions'
import { AuditoriaPanel } from '../components/AuditoriaPanel'
import { EstruturaPanel } from '../components/EstruturaPanel'
import { PerfisPanel } from '../components/PerfisPanel'
import { UsuariosPanel } from '../components/UsuariosPanel'
import '../configuracoes.css'

const sections = [
  { id: 'geral', title: 'Visão Geral', icon: LayoutGrid, permission: 'configuracoes.visualizar', description: 'Contexto organizacional e áreas administrativas disponíveis.' },
  { id: 'usuarios', title: 'Usuários', icon: Users, permission: 'usuarios.gerenciar', description: 'Convites, status, unidades e perfis de acesso.' },
  { id: 'perfis', title: 'Perfis e Permissões', icon: ShieldCheck, permission: 'perfis.gerenciar', description: 'Perfis de sistema e perfis customizados da empresa.' },
  { id: 'estrutura', title: 'Estrutura', icon: Network, permission: 'estrutura.gerenciar', description: 'Empresa, unidades e setores operacionais.' },
  { id: 'auditoria', title: 'Auditoria', icon: History, permission: 'auditoria.visualizar', description: 'Trilha das alterações administrativas da empresa.' },
]

export function ConfiguracoesPage() {
  const { contexto } = useAuth()
  const [params, setParams] = useSearchParams()
  const selected = sections.find(section => section.id === params.get('secao')) ?? sections[0]
  const allowed = hasPermission(contexto, 'configuracoes.visualizar') && hasPermission(contexto, selected.permission)
  const navigate = (id: string) => setParams({ secao: id })
  return <div className="settings-page">
    <div className="page-heading"><div><span className="eyebrow">ADMINISTRAÇÃO</span><h1>Configurações</h1><p>Gerencie acessos, estrutura organizacional e governança da sua empresa.</p></div><span className="badge green">Administração segura</span></div>
    <nav className="settings-tabs" aria-label="Seções de configurações">{sections.filter(section => hasPermission(contexto, section.permission)).map(({ id, title, icon: Icon }) => <button key={id} aria-current={selected.id === id ? 'page' : undefined} onClick={() => navigate(id)}><Icon size={17} />{title}</button>)}</nav>
    <section className="panel settings-content" aria-label={selected.title}>
      {!allowed ? <div className="settings-feedback" role="alert"><ShieldCheck size={28} /><h2>Acesso não autorizado</h2><p>Seu acesso não permite consultar esta área administrativa.</p><button className="button secondary" onClick={() => navigate('geral')}>Voltar à visão geral</button></div>
        : selected.id === 'usuarios' ? <UsuariosPanel />
          : selected.id === 'perfis' ? <PerfisPanel />
            : selected.id === 'estrutura' ? <EstruturaPanel />
              : selected.id === 'auditoria' ? <AuditoriaPanel />
                : <>
                  <div className="settings-section-heading"><div><h2>Visão Geral</h2><p>Seu contexto organizacional e as áreas disponíveis.</p></div><Building2 size={23} className="muted" /></div>
                  <dl className="settings-overview"><div><dt>Empresa</dt><dd>{contexto?.nome_fantasia || contexto?.razao_social || 'Não informada'}</dd></div><div><dt>Unidade</dt><dd>{contexto?.unidade_nome || 'Não vinculada'}</dd></div><div><dt>Seu cadastro</dt><dd>{contexto?.nome || contexto?.email || 'Não informado'}</dd></div><div><dt>Seus perfis</dt><dd>{contexto?.perfis?.join(', ') || 'Nenhum perfil informado'}</dd></div></dl>
                  <div className="settings-overview-cards">{sections.slice(1).filter(section => hasPermission(contexto, section.permission)).map(({ id, title, icon: Icon, description }) => <button className="settings-overview-card" key={id} onClick={() => navigate(id)}><span className="metric-icon green"><Icon size={23} /></span><h3>{title}</h3><p>{description}</p><span className="text-link">Acessar área →</span></button>)}</div>
                  <p className="settings-notice"><ShieldCheck size={18} /><span><strong>Administração por permissão.</strong> A interface respeita o contexto autenticado, enquanto as operações críticas também são validadas no banco e registradas na trilha de auditoria.</span></p>
                </>}
    </section>
  </div>
}
