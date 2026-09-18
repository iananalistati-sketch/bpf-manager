import { useState } from 'react'
import { Eye, Info, RefreshCw } from 'lucide-react'
import { useUsuarios } from '../hooks/useConfiguracoesQuery'
import { displayDate, emptyFilters, filterUsuarios, statusLabels } from '../lib/presentation'
import { QueryFeedback } from './QueryFeedback'
import { StatusBadge } from './StatusBadge'
import { UsuarioDetails } from './UsuarioDetails'

export function UsuariosPanel() {
  const query = useUsuarios()
  const [filters, setFilters] = useState(emptyFilters)
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const data = query.data
  if (!query.allowed) return <QueryFeedback error="Você não possui acesso à área de usuários." />
  if (query.loading || query.error || !data) return <QueryFeedback loading={query.loading} error={query.error} onRetry={query.reload} />
  const users = filterUsuarios(data.usuarios, data.vinculos, filters)
  const selected = data.usuarios.find(user => user.id === selectedId)
  const setFilter = (name: keyof typeof filters, value: string) => setFilters(previous => ({ ...previous, [name]: value }))
  const refreshAfterChange = () => { setSelectedId(null); query.reload() }

  return <>
    <div className="settings-section-heading"><div><h2>Usuários</h2><p>Consulte cadastros e administre acessos autorizados.</p></div><button className="button secondary" onClick={() => { setSelectedId(null); query.reload() }}><RefreshCw size={15} />Atualizar</button></div>
    <div className="settings-notice"><Info size={19} /><p><strong>Gestão restrita à sua empresa.</strong> Os registros disponíveis dependem das suas permissões. Alterações de status, unidade e perfil usam comandos protegidos no servidor e geram auditoria. Usuários pendentes permanecem fora deste fluxo.</p></div>
    <div className="settings-filters">
      <label>Nome ou e-mail<input type="search" value={filters.busca} onChange={event => setFilter('busca', event.target.value)} placeholder="Buscar usuário" /></label>
      <label>Status<select aria-label="Status" value={filters.status} onChange={event => setFilter('status', event.target.value)}><option value="">Todos os status</option>{Object.entries(statusLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
      <label>Unidade<select aria-label="Unidade" value={filters.unidade} onChange={event => setFilter('unidade', event.target.value)}><option value="">Todas as unidades</option><option value="sem-unidade">Sem unidade</option>{data.unidades.map(unidade => <option key={unidade.id} value={unidade.id}>{unidade.nome}</option>)}</select></label>
      <label>Perfil<select aria-label="Perfil" value={filters.perfil} onChange={event => setFilter('perfil', event.target.value)}><option value="">Todos os perfis</option><option value="sem-perfil">Sem vínculo visível</option>{data.perfis.map(perfil => <option key={perfil.id} value={perfil.id}>{perfil.nome}</option>)}</select></label>
    </div>
    <div className="settings-results"><span role="status">{users.length} de {data.usuarios.length} registros visíveis</span><button className="text-link" onClick={() => setFilters(emptyFilters)}>Limpar filtros</button></div>
    {!users.length ? <QueryFeedback empty={data.usuarios.length ? 'Nenhum usuário corresponde aos filtros selecionados.' : 'Nenhum cadastro foi retornado para seu acesso atual.'} /> : <div className="settings-user-list">
      {users.map(user => {
        const empresa = data.empresas.find(item => item.id === user.empresa_id)
        const unidade = data.unidades.find(item => item.id === user.unidade_id)
        const perfis = data.perfis.filter(perfil => data.vinculos.some(link => link.usuario_id === user.id && link.perfil_id === perfil.id))
        return <article className={`settings-user-card${user.status === 'pendente' ? ' pending' : ''}`} key={user.id}>
          <div className="settings-user-heading"><div><h3>{user.nome || 'Nome não informado'}</h3><p>{user.email || 'E-mail não informado'}</p></div><StatusBadge status={user.status} /></div>
          <dl className="settings-user-meta"><div><dt>Empresa</dt><dd>{empresa ? empresa.nome_fantasia || empresa.razao_social : user.empresa_id ? 'Não disponível para consulta' : 'Não vinculada'}</dd></div><div><dt>Unidade</dt><dd>{unidade?.nome || (user.unidade_id ? 'Não disponível para consulta' : 'Não vinculada')}</dd></div><div><dt>Situação</dt><dd>{user.ativo ? 'Ativo' : 'Inativo'}</dd></div><div><dt>Cadastro</dt><dd>{displayDate(user.created_at)}</dd></div></dl>
          <div className="settings-user-footer"><div className="settings-tags" aria-label="Perfis do usuário">{perfis.length ? perfis.map(perfil => <span className="badge neutral" key={perfil.id}>{perfil.nome}</span>) : <span className="settings-muted">Sem vínculo de perfil visível</span>}</div><button className="button secondary" onClick={() => setSelectedId(user.id)} aria-label={`Ver detalhes de ${user.nome || user.email || 'usuário'}`}><Eye size={15} />Detalhes</button></div>
          {user.status === 'pendente' && <p className="settings-pending-label">Aguardando aprovação e vínculo de acesso</p>}
        </article>
      })}
    </div>}
    {selected && <UsuarioDetails usuario={selected} data={data} onClose={() => setSelectedId(null)} onChanged={refreshAfterChange} />}
  </>
}
