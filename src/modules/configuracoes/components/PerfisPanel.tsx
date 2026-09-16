import { useState } from 'react'
import { ArrowRight, RefreshCw, ShieldCheck } from 'lucide-react'
import { usePerfis } from '../hooks/useConfiguracoesQuery'
import { QueryFeedback } from './QueryFeedback'
import { PerfilDetails } from './PerfilDetails'

export function PerfisPanel() {
  const query = usePerfis()
  const [selectedId, setSelectedId] = useState<string | null>(null)
  if (!query.allowed) return <QueryFeedback error="Você não possui acesso à área de perfis e permissões." />
  if (query.loading || query.error || !query.data) return <QueryFeedback loading={query.loading} error={query.error} onRetry={query.reload} />
  const data = query.data
  const selected = data.perfis.find(perfil => perfil.id === selectedId)
  return <>
    <div className="settings-section-heading"><div><h2>Perfis e Permissões</h2><p>Perfis de sistema e perfis disponíveis na sua empresa.</p></div><button className="button secondary" onClick={() => { setSelectedId(null); query.reload() }}><RefreshCw size={15} />Atualizar</button></div>
    <p className="settings-notice"><ShieldCheck size={19} />Consulte as permissões de cada perfil. Alterações e atribuições permanecem indisponíveis nesta etapa.</p>
    {!data.perfis.length ? <QueryFeedback empty="Nenhum perfil foi retornado para seu acesso atual." /> : <div className="settings-profiles-grid">{data.perfis.map(perfil => <article className="settings-profile-card" key={perfil.id}>
      <div className="settings-profile-top"><span className="metric-icon green"><ShieldCheck size={20} /></span><span className={`badge ${perfil.ativo ? 'green' : 'neutral'}`}>{perfil.ativo ? 'Ativo' : 'Inativo'}</span></div>
      <h3>{perfil.nome}</h3><p>{perfil.descricao || 'Descrição não informada.'}</p><div className="settings-tags">{perfil.is_system && <span className="badge blue">Perfil de sistema</span>}<span className="badge neutral">{data.vinculos.filter(link => link.perfil_id === perfil.id).length} permissões</span></div>
      <button className="text-link" onClick={() => setSelectedId(perfil.id)} aria-label={`Ver permissões de ${perfil.nome}`}>Ver permissões<ArrowRight size={15} /></button>
    </article>)}</div>}
    {selected && <PerfilDetails perfil={selected} data={data} onClose={() => setSelectedId(null)} />}
  </>
}
