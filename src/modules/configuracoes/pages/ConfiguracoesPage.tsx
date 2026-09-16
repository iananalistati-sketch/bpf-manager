import { Building2, LayoutGrid, ShieldCheck, Users } from 'lucide-react'
import { useSearchParams } from 'react-router-dom'
import { useAuth } from '../../../hooks/useAuth'
import { hasPermission } from '../../../lib/permissions'
import { UsuariosPanel } from '../components/UsuariosPanel'
import { PerfisPanel } from '../components/PerfisPanel'
import '../configuracoes.css'

const sections = [
  { id: 'geral', title: 'Visão Geral', icon: LayoutGrid, permission: 'configuracoes.visualizar' },
  { id: 'usuarios', title: 'Usuários', icon: Users, permission: 'usuarios.gerenciar' },
  { id: 'perfis', title: 'Perfis e Permissões', icon: ShieldCheck, permission: 'perfis.gerenciar' },
]

export function ConfiguracoesPage() {
  const { contexto } = useAuth()
  const [params, setParams] = useSearchParams()
  const selected = sections.find(section => section.id === params.get('secao')) ?? sections[0]
  const allowed = hasPermission(contexto, 'configuracoes.visualizar') && hasPermission(contexto, selected.permission)
  const navigate = (id: string) => setParams({ secao: id })
  return <div className="settings-page">
    <div className="page-heading"><div><span className="eyebrow">ADMINISTRAÇÃO</span><h1>Configurações</h1><p>Organize os acessos e consulte a estrutura da sua empresa.</p></div><span className="badge green">Consulta administrativa</span></div>
    <nav className="settings-tabs" aria-label="Seções de configurações">{sections.filter(section => hasPermission(contexto, section.permission)).map(({ id, title, icon: Icon }) => <button key={id} aria-current={selected.id === id ? 'page' : undefined} onClick={() => navigate(id)}><Icon size={17} />{title}</button>)}</nav>
    <section className="panel settings-content" aria-label={selected.title}>
      {!allowed ? <div className="settings-feedback" role="alert"><ShieldCheck size={28} /><h2>Acesso não autorizado</h2><p>Seu acesso não permite consultar esta área administrativa.</p><button className="button secondary" onClick={() => navigate('geral')}>Voltar à visão geral</button></div>
        : selected.id === 'usuarios' ? <UsuariosPanel /> : selected.id === 'perfis' ? <PerfisPanel />
          : <>
            <div className="settings-section-heading"><div><h2>Visão Geral</h2><p>Seu contexto organizacional e as áreas disponíveis.</p></div><Building2 size={23} className="muted" /></div>
            <dl className="settings-overview"><div><dt>Empresa</dt><dd>{contexto?.nome_fantasia || contexto?.razao_social || 'Não informada'}</dd></div><div><dt>Unidade</dt><dd>{contexto?.unidade_nome || 'Não vinculada'}</dd></div><div><dt>Seu cadastro</dt><dd>{contexto?.nome || contexto?.email || 'Não informado'}</dd></div><div><dt>Seus perfis</dt><dd>{contexto?.perfis?.join(', ') || 'Nenhum perfil informado'}</dd></div></dl>
            <div className="settings-overview-cards">{sections.slice(1).filter(section => hasPermission(contexto, section.permission)).map(({ id, title, icon: Icon }) => <button className="settings-overview-card" key={id} onClick={() => navigate(id)}><span className="metric-icon green"><Icon size={23} /></span><h3>{title}</h3><p>{id === 'usuarios' ? 'Consulte cadastros, status e vínculos disponíveis para seu acesso.' : 'Confira os perfis e suas permissões agrupadas por módulo.'}</p><span className="text-link">Acessar área →</span></button>)}</div>
            <p className="settings-notice">Nesta versão, os dados estão disponíveis para consulta. Aprovações e alterações administrativas serão habilitadas após a revisão das regras de acesso e do histórico de alterações.</p>
            {hasPermission(contexto, 'configuracoes.gerenciar') && <p className="settings-muted">Você possui permissão para configurações administrativas gerais. Novos controles serão disponibilizados nas próximas etapas.</p>}
          </>}
    </section>
  </div>
}
