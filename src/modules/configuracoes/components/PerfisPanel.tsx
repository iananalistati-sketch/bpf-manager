import { useState } from 'react'
import { ArrowRight, Plus, RefreshCw, ShieldCheck } from 'lucide-react'
import { usePerfis } from '../hooks/useConfiguracoesQuery'
import { QueryFeedback } from './QueryFeedback'
import { PerfilCreateDialog } from './PerfilCreateDialog'
import { PerfilDetails } from './PerfilDetails'

export function PerfisPanel() {
  const query = usePerfis()
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [creating, setCreating] = useState(false)
  if (!query.allowed) return <QueryFeedback error="Você não possui acesso à área de perfis e permissões." />
  if (query.loading || query.error || !query.data) return <QueryFeedback loading={query.loading} error={query.error} onRetry={query.reload} />
  const data = query.data
  const selected = data.perfis.find(perfil => perfil.id === selectedId)
  return <>
    <div className="settings-section-heading"><div><h2>Perfis e Permissões</h2><p>Use perfis de sistema como referência e crie perfis exclusivos da sua empresa.</p></div><div className="settings-heading-actions"><button className="button primary" onClick={() => setCreating(true)}><Plus size={15} />Novo perfil</button><button className="button secondary" onClick={() => { setSelectedId(null); query.reload() }}><RefreshCw size={15} />Atualizar</button></div></div>
    <p className="settings-notice"><ShieldCheck size={19} /><span><strong>Permissões configuráveis.</strong> Perfis de sistema são globais e somente leitura; perfis da empresa podem ser criados, editados e inativados com auditoria.</span></p>
    {!data.perfis.length ? <QueryFeedback empty="Nenhum perfil foi retornado para seu acesso atual." /> : <div className="settings-profiles-grid">{data.perfis.map(perfil => <article className="settings-profile-card" key={perfil.id}>
      <div className="settings-profile-top"><span className="metric-icon green"><ShieldCheck size={20} /></span><span className={`badge ${perfil.ativo ? 'green' : 'neutral'}`}>{perfil.ativo ? 'Ativo' : 'Inativo'}</span></div>
      <h3>{perfil.nome}</h3><p>{perfil.descricao || 'Descrição não informada.'}</p><div className="settings-tags">{perfil.is_system ? <span className="badge blue">Perfil de sistema</span> : <span className="badge green">Perfil da empresa</span>}<span className="badge neutral">{data.vinculos.filter(link => link.perfil_id === perfil.id).length} permissões</span></div>
      <button className="text-link" onClick={() => setSelectedId(perfil.id)} aria-label={`Ver permissões de ${perfil.nome}`}>{perfil.is_system ? 'Ver permissões' : 'Gerenciar perfil'}<ArrowRight size={15} /></button>
    </article>)}</div>}
    {selected && <PerfilDetails perfil={selected} data={data} onClose={() => setSelectedId(null)} onChanged={() => query.reload()} />}
    {creating && <PerfilCreateDialog data={data} onClose={() => setCreating(false)} onChanged={() => query.reload()} />}
  </>
}
