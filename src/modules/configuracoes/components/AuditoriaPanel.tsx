import { useState } from 'react'
import { History, RefreshCw, Search } from 'lucide-react'
import { useAuditoria } from '../hooks/useConfiguracoesQuery'
import { QueryFeedback } from './QueryFeedback'

function formatDate(value: string) {
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? value : new Intl.DateTimeFormat('pt-BR', { dateStyle: 'short', timeStyle: 'medium' }).format(date)
}
function formatJson(value: Record<string, unknown> | null) {
  if (!value || !Object.keys(value).length) return '—'
  return JSON.stringify(value, null, 2)
}

export function AuditoriaPanel() {
  const query = useAuditoria()
  const [search, setSearch] = useState('')
  const [entity, setEntity] = useState('')
  if (!query.allowed) return <QueryFeedback error="Você não possui acesso à trilha de auditoria." />
  if (query.loading || query.error || !query.data) return <QueryFeedback loading={query.loading} error={query.error} onRetry={query.reload} />
  const { eventos, usuarios } = query.data
  const entities = [...new Set(eventos.map(item => item.entidade))].sort()
  const filtered = eventos.filter(item => {
    if (entity && item.entidade !== entity) return false
    const actor = usuarios.find(user => user.id === item.ator_id)
    const haystack = [item.acao, item.entidade, item.justificativa, actor?.nome, actor?.email, item.registro_id].filter(Boolean).join(' ').toLocaleLowerCase('pt-BR')
    return haystack.includes(search.trim().toLocaleLowerCase('pt-BR'))
  })
  return <>
    <div className="settings-section-heading"><div><h2>Auditoria</h2><p>Histórico das alterações administrativas registradas na sua empresa.</p></div><button className="button secondary" onClick={query.reload}><RefreshCw size={15} />Atualizar</button></div>
    <p className="settings-notice"><History size={19} /><span><strong>Trilha imutável para o cliente.</strong> Esta tela é somente leitura e o banco limita os eventos à empresa do usuário autenticado.</span></p>
    <div className="settings-filters settings-audit-filters"><label>Pesquisar<span className="settings-input-icon"><Search size={14} /><input type="search" value={search} onChange={event => setSearch(event.target.value)} placeholder="Ação, justificativa ou ator" /></span></label><label>Entidade<select value={entity} onChange={event => setEntity(event.target.value)}><option value="">Todas</option>{entities.map(item => <option key={item} value={item}>{item}</option>)}</select></label></div>
    <div className="settings-results"><span role="status">{filtered.length} de {eventos.length} eventos</span><button className="text-link" onClick={() => { setSearch(''); setEntity('') }}>Limpar filtros</button></div>
    {!filtered.length ? <QueryFeedback empty={eventos.length ? 'Nenhum evento corresponde aos filtros.' : 'Nenhum evento de auditoria registrado.'} /> : <div className="settings-audit-list">{filtered.map(evento => {
      const actor = usuarios.find(user => user.id === evento.ator_id)
      return <details className="settings-audit-event" key={evento.id}><summary><span><strong>{evento.acao}</strong><small>{evento.entidade} · {formatDate(evento.created_at)}</small></span><span className="badge neutral">{actor?.nome || actor?.email || evento.ator_id.slice(0, 8)}</span></summary><div className="settings-audit-body"><dl><div><dt>Justificativa</dt><dd>{evento.justificativa}</dd></div><div><dt>Registro</dt><dd>{evento.registro_id}</dd></div></dl><div className="settings-audit-json"><div><h4>Antes</h4><pre>{formatJson(evento.antes)}</pre></div><div><h4>Depois</h4><pre>{formatJson(evento.depois)}</pre></div></div></div></details>
    })}</div>}
  </>
}
